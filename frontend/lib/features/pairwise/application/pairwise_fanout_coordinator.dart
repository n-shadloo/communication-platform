import 'dart:typed_data';

import 'package:communication_platform/core/application/ports/time_source.dart';
import 'package:communication_platform/core/protocol/application_message_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/pairwise/application/ports/pairwise_orchestration_ports.dart';
import 'package:communication_platform/features/pairwise/application/ports/pairwise_transport_store.dart';
import 'package:communication_platform/features/pairwise/domain/pairwise_model.dart';

/// Prepares one exact per-device envelope and commits all state before network I/O.
final class PairwiseFanoutCoordinator {
  const PairwiseFanoutCoordinator({
    required this.store,
    required this.liveDevices,
    required this.claims,
    required this.crypto,
    required this.clock,
  });

  final PairwiseTransportStore store;
  final PairwiseLiveDeviceResolverPort liveDevices;
  final PairwiseSelectiveClaimPort claims;
  final PairwiseOutboundPreparationPort crypto;
  final TimeSource clock;

  /// Commits a locally originated event and records that its recipients are
  /// owed, without touching the network.
  ///
  /// This is the whole of a send, as far as the person who pressed send is
  /// concerned. What used to run first — two authenticated device lookups, a
  /// prekey claim, and one ratchet step per recipient device — is now described
  /// by a durable row and performed by [prepareOwedSend] against a message the
  /// timeline is already showing.
  Future<Result<void>> commitLocalEcho({
    required String operationId,
    required String eventId,
    required String currentUserId,
    required String currentDeviceId,
    required String peerUserId,
    required Uint8List openedOpaquePayload,
    required ApplicationEventCommit applicationEvent,
  }) {
    if (!_isUuid(currentUserId) ||
        !_isUuid(currentDeviceId) ||
        !_isUuid(peerUserId) ||
        eventId != protocolBytesToHex(applicationEvent.event.eventId)) {
      return Future.value(
        const Result.failure(
          ValidationFailure(ValidationFailureKind.invalidInput),
        ),
      );
    }
    return store.commitLocalEcho(
      operationId: operationId,
      eventId: eventId,
      currentUserId: currentUserId,
      currentDeviceId: currentDeviceId,
      peerUserId: peerUserId,
      openedLocalPayload: openedOpaquePayload,
      applicationEvent: applicationEvent,
    );
  }

  /// Runs the fan-out an echoed send still owes.
  ///
  /// Re-entrancy is decided by the outbox rather than by the operation record.
  /// The echo writes that record, so its mere presence no longer means the work
  /// was done; sealed ciphertext does, and finding some means a previous
  /// attempt committed and died before its caller heard about it.
  Future<Result<void>> prepareOwedSend(OwedSendPreparation owed) async {
    if (!_isUuid(owed.currentUserId) ||
        !_isUuid(owed.currentDeviceId) ||
        !_isUuid(owed.peerUserId)) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    final recordResult = await store.readPreparedOperation(owed.operationId);
    if (recordResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final record = (recordResult as Success<DurablePairwiseOperation?>).value;
    if (record == null || record.eventId != owed.eventId) {
      // The message this preparation belonged to is gone, so nothing is owed to
      // anybody. Retiring the row is the only way it stops being asked for.
      return store.settleSendPreparation(owed.operationId);
    }
    if (record.targets.isNotEmpty) {
      return store.settleSendPreparation(owed.operationId);
    }
    final prepared = await _prepare(
      operationId: owed.operationId,
      eventId: owed.eventId,
      currentUserId: owed.currentUserId,
      currentDeviceId: owed.currentDeviceId,
      peerUserId: owed.peerUserId,
      openedOpaquePayload: record.openedLocalPayload,
      // A conversation whose only participant is this device resolves to no
      // recipient at all, which is a settled send and not a failed one.
      settleWithoutTargets: true,
    );
    return prepared.fold(
      onSuccess: (_) => const Result.success(null),
      onFailure: Result.failure,
    );
  }

  Future<Result<bool>> retryFailedSend(String operationId) =>
      store.rearmFailedSend(operationId);

  Future<Result<DurablePairwiseOperation>> prepareAndQueue({
    required String operationId,
    required String eventId,
    required String currentUserId,
    required String currentDeviceId,
    required String peerUserId,
    required Uint8List openedOpaquePayload,

    /// For device-to-device recovery, restrict the audience to this exact
    /// already-authenticated device.  A null value preserves normal fan-out.
    String? onlyRecipientDeviceId,
    bool includeOwnDevices = true,
  }) async {
    if (!_isUuid(currentUserId) ||
        !_isUuid(currentDeviceId) ||
        !_isUuid(peerUserId)) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    final existingResult = await store.readPreparedOperation(operationId);
    if (existingResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final existing =
        (existingResult as Success<DurablePairwiseOperation?>).value;
    if (existing != null) {
      if (existing.eventId != eventId ||
          existing.currentDeviceId != currentDeviceId.toLowerCase() ||
          !_bytesEqual(existing.openedLocalPayload, openedOpaquePayload) ||
          !_matchesRequestedAudience(
            existing,
            currentUserId: currentUserId,
            peerUserId: peerUserId,
          )) {
        return const Result.failure(
          ValidationFailure(ValidationFailureKind.conflict),
        );
      }
      return Result.success(existing);
    }
    return _prepare(
      operationId: operationId,
      eventId: eventId,
      currentUserId: currentUserId,
      currentDeviceId: currentDeviceId,
      peerUserId: peerUserId,
      openedOpaquePayload: openedOpaquePayload,
      onlyRecipientDeviceId: onlyRecipientDeviceId,
      includeOwnDevices: includeOwnDevices,
    );
  }

  Future<Result<DurablePairwiseOperation>> _prepare({
    required String operationId,
    required String eventId,
    required String currentUserId,
    required String currentDeviceId,
    required String peerUserId,
    required Uint8List openedOpaquePayload,
    String? onlyRecipientDeviceId,
    bool includeOwnDevices = true,
    bool settleWithoutTargets = false,
  }) async {
    final peerDevicesResult = await liveDevices.resolveVerifiedLiveDevices(
      peerUserId,
    );
    if (peerDevicesResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final ownDevicesResult = await liveDevices.resolveVerifiedLiveDevices(
      currentUserId,
    );
    if (ownDevicesResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final peerDevices =
        (peerDevicesResult as Success<List<VerifiedPairwiseLiveDevice>>).value;
    final ownDevices =
        (ownDevicesResult as Success<List<VerifiedPairwiseLiveDevice>>).value;
    final targetResult = _canonicalTargets(
      currentUserId: currentUserId,
      currentDeviceId: currentDeviceId,
      peerUserId: peerUserId,
      peerDevices: peerDevices,
      ownDevices: ownDevices,
      includeOwnDevices: includeOwnDevices,
    );
    if (targetResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    var targets =
        (targetResult as Success<List<VerifiedPairwiseLiveDevice>>).value;
    if (onlyRecipientDeviceId != null) {
      final requested = onlyRecipientDeviceId.toLowerCase();
      targets = targets
          .where((target) => target.deviceId.toLowerCase() == requested)
          .toList(growable: false);
      if (targets.length != 1 || targets.single.userId != peerUserId) {
        return const Result.failure(
          SecurityFailure(SecurityFailureKind.unauthenticatedInput),
        );
      }
    }
    final peerReconciled = await store.reconcileRemoteLiveDevices(
      remoteUserId: peerUserId,
      liveDeviceIds: peerDevices.map((device) => device.deviceId).toSet(),
    );
    if (peerReconciled case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final ownReconciled = await store.reconcileRemoteLiveDevices(
      remoteUserId: currentUserId,
      liveDeviceIds: ownDevices
          .where((device) => device.deviceId != currentDeviceId.toLowerCase())
          .map((device) => device.deviceId)
          .toSet(),
    );
    if (ownReconciled case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }

    final contexts = <String, PairwisePreparationContext>{};
    final claimsByUser = <String, List<String>>{};
    for (final target in targets) {
      final contextResult = await store.readPreparationContext(
        localDeviceId: currentDeviceId,
        remoteUserId: target.userId,
        remoteDeviceId: target.deviceId,
      );
      if (contextResult case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      final context =
          (contextResult as Success<PairwisePreparationContext>).value;
      contexts[target.deviceId] = context;
      if (context.requiresClaim) {
        (claimsByUser[target.userId] ??= []).add(target.deviceId);
      }
    }
    final deviceStateVersions = contexts.values
        .map((context) => context.deviceState.stateVersion)
        .toSet();
    if (targets.isEmpty) {
      if (currentUserId != peerUserId) {
        return const Result.failure(
          ValidationFailure(ValidationFailureKind.invalidInput),
        );
      }
      if (settleWithoutTargets) {
        final settled = await store.settleSendPreparation(operationId);
        if (settled case FailureResult(failure: final failure)) {
          return Result.failure(failure);
        }
      }
      return Result.success(
        DurablePairwiseOperation(
          operationId: operationId,
          eventId: eventId,
          currentDeviceId: currentDeviceId.toLowerCase(),
          openedLocalPayload: openedOpaquePayload,
          targets: const [],
        ),
      );
    }
    if (deviceStateVersions.length != 1) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.conflict),
      );
    }
    final migrationUnixDay =
        clock.now().toUtc().millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay;

    final claimedTargets = <String, VerifiedPairwiseClaim>{};
    final expectedLiveByUser = <String, Set<String>>{
      peerUserId: peerDevices.map((device) => device.deviceId).toSet(),
      currentUserId: ownDevices.map((device) => device.deviceId).toSet(),
    };
    for (final entry in claimsByUser.entries) {
      entry.value.sort(_compareUuidBytes);
      final claimedResult = await claims.claimVerifiedDevices(
        userId: entry.key,
        deviceIds: entry.value,
      );
      if (claimedResult case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      final claimed = (claimedResult as Success<VerifiedPairwiseClaims>).value;
      final requested = entry.value.toSet();
      final returned = claimed.claims.keys.toSet();
      final live = claimed.liveDevices
          .where((device) => device.userId == entry.key)
          .map((device) => device.deviceId)
          .toSet();
      final expectedLive = expectedLiveByUser[entry.key]!;
      if (returned.length != requested.length ||
          !returned.containsAll(requested) ||
          !requested.containsAll(returned) ||
          !live.containsAll(requested) ||
          live.length != expectedLive.length ||
          !live.containsAll(expectedLive) ||
          !expectedLive.containsAll(live)) {
        return const Result.failure(
          SecurityFailure(SecurityFailureKind.unauthenticatedInput),
        );
      }
      claimedTargets.addAll(claimed.claims);
    }

    final preparedTargets = <PreparedPairwiseSendTarget>[];
    for (final target in targets) {
      final context = contexts[target.deviceId]!;
      final claim = context.requiresClaim
          ? claimedTargets[target.deviceId]
          : null;
      final recipient = claim?.device ?? target;
      final preparedResult = await crypto.prepareOutbound(
        currentDeviceId: currentDeviceId,
        recipient: recipient,
        openedOpaquePayload: openedOpaquePayload,
        migrationUnixDay: migrationUnixDay,
        context: context,
        claim: claim,
      );
      if (preparedResult case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      final prepared =
          (preparedResult as Success<PairwisePreparedOutbound>).value;
      final previous = context.primary;
      preparedTargets.add(
        PreparedPairwiseSendTarget(
          recipientUserId: target.userId,
          recipientDeviceId: target.deviceId,
          exactCiphertext: prepared.exactCiphertext,
          sessionTransition: PairwiseSessionTransition(
            localDeviceId: currentDeviceId,
            remoteUserId: target.userId,
            remoteDeviceId: target.deviceId,
            sessionId: prepared.sessionId,
            nextOpaqueState: prepared.nextOpaqueSessionState,
            expectedStateVersion: previous?.stateVersion,
            nextStateVersion: (previous?.stateVersion ?? 0) + 1,
            nextSkippedKeyCount: prepared.nextSkippedKeyCount,
            disposition: prepared.disposition,
            repairState: prepared.repairState,
          ),
        ),
      );
    }

    final commit = await store.commitPreparedSend(
      PairwiseSendCommit(
        operationId: operationId,
        eventId: eventId,
        currentDeviceId: currentDeviceId,
        expectedDeviceStateVersion: deviceStateVersions.single,
        openedLocalPayload: openedOpaquePayload,
        targets: preparedTargets,
      ),
    );
    if (commit case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final durableResult = await store.readPreparedOperation(operationId);
    if (durableResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final durable = (durableResult as Success<DurablePairwiseOperation?>).value;
    return durable == null
        ? const Result.failure(
            SecurityFailure(SecurityFailureKind.integrityCheckFailed),
          )
        : Result.success(durable);
  }

  bool _matchesRequestedAudience(
    DurablePairwiseOperation operation, {
    required String currentUserId,
    required String peerUserId,
  }) {
    var hasPeer = false;
    final deviceIds = <String>{};
    for (final target in operation.targets) {
      if (target.recipientUserId == peerUserId) {
        hasPeer = true;
      } else if (target.recipientUserId != currentUserId) {
        return false;
      }
      if (!deviceIds.add(target.recipientDeviceId.toLowerCase())) {
        return false;
      }
    }
    return hasPeer ||
        (operation.targets.isEmpty && peerUserId == currentUserId);
  }

  Result<List<VerifiedPairwiseLiveDevice>> _canonicalTargets({
    required String currentUserId,
    required String currentDeviceId,
    required String peerUserId,
    required List<VerifiedPairwiseLiveDevice> peerDevices,
    required List<VerifiedPairwiseLiveDevice> ownDevices,
    required bool includeOwnDevices,
  }) {
    if (!_isUuid(currentUserId) ||
        !_isUuid(currentDeviceId) ||
        !_isUuid(peerUserId) ||
        peerDevices.isEmpty) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    final byDevice = <String, VerifiedPairwiseLiveDevice>{};
    bool add(
      String userId,
      VerifiedPairwiseLiveDevice device, {
      required bool allowCurrent,
    }) {
      final deviceId = device.deviceId.toLowerCase();
      if (!_isUuid(deviceId)) {
        return false;
      }
      if (deviceId == currentDeviceId.toLowerCase()) {
        return allowCurrent;
      }
      final previous = byDevice[deviceId];
      if (previous != null && previous.userId != userId) {
        return false;
      }
      byDevice[deviceId] = device;
      return true;
    }

    for (final device in peerDevices) {
      if (device.userId != peerUserId ||
          !add(peerUserId, device, allowCurrent: peerUserId == currentUserId)) {
        return const Result.failure(
          SecurityFailure(SecurityFailureKind.unauthenticatedInput),
        );
      }
    }
    var foundCurrentDevice = false;
    for (final device in ownDevices) {
      foundCurrentDevice |=
          device.deviceId.toLowerCase() == currentDeviceId.toLowerCase();
      if (device.userId != currentUserId ||
          !_isUuid(device.deviceId) ||
          (includeOwnDevices &&
              !add(currentUserId, device, allowCurrent: true))) {
        return const Result.failure(
          SecurityFailure(SecurityFailureKind.unauthenticatedInput),
        );
      }
    }
    if (!foundCurrentDevice) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.unauthenticatedInput),
      );
    }
    final targets = byDevice.values.toList(growable: false)
      ..sort((left, right) => _compareUuidBytes(left.deviceId, right.deviceId));
    return Result.success(List.unmodifiable(targets));
  }
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  var difference = 0;
  for (var index = 0; index < left.length; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}

bool _isUuid(String value) => _uuid.hasMatch(value);

int _compareUuidBytes(String left, String right) {
  final leftHex = left.replaceAll('-', '').toLowerCase();
  final rightHex = right.replaceAll('-', '').toLowerCase();
  for (var index = 0; index < 32; index += 2) {
    final leftByte = int.parse(leftHex.substring(index, index + 2), radix: 16);
    final rightByte = int.parse(
      rightHex.substring(index, index + 2),
      radix: 16,
    );
    final comparison = leftByte.compareTo(rightByte);
    if (comparison != 0) {
      return comparison;
    }
  }
  return 0;
}

final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

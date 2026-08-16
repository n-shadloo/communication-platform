import 'dart:typed_data';

import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/groups/application/ports/group_ports.dart';
import 'package:communication_platform/features/groups/domain/group_model.dart';

/// Prepares one authenticated group receive without mutating durable state.
/// The sync store commits the result with the pairwise ratchet transition.
final class GroupMlsInboundCoordinator {
  const GroupMlsInboundCoordinator({
    required this.repository,
    required this.crypto,
    required this.localUserId,
    required this.localDeviceId,
    this.stateMachine = const GroupControlStateMachine(),
    this.clock = DateTime.now,
  });

  final GroupRepositoryPort repository;
  final GroupMlsCryptoPort crypto;
  final String localUserId;
  final String localDeviceId;
  final GroupControlStateMachine stateMachine;
  final DateTime Function() clock;

  Future<Result<PreparedGroupInboxCommit>> inspect(Uint8List mlsObject) async {
    final probeResult = await crypto.probeIncomingTransport(mlsObject);
    if (probeResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final probe = (probeResult as Success<GroupMlsTransportProbe>).value;
    return switch (probe.kind) {
      GroupMlsTransportKind.welcome => _welcome(probe, mlsObject),
      GroupMlsTransportKind.control => _control(probe, mlsObject),
      GroupMlsTransportKind.application => _application(probe, mlsObject),
    };
  }

  Future<Result<PreparedGroupInboxCommit>> _welcome(
    GroupMlsTransportProbe probe,
    Uint8List mlsObject,
  ) async {
    final existingResult = await repository.readGroup(probe.groupId);
    if (existingResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    if ((existingResult as Success<GroupState?>).value != null) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.unauthenticatedInput),
      );
    }
    final inspected = await crypto.inspectIncomingWelcome(
      mlsObject: mlsObject,
      localUserId: localUserId.toLowerCase(),
      localDeviceId: localDeviceId.toLowerCase(),
    );
    if (inspected case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final prepared = (inspected as Success<PreparedGroupTransition>).value;
    GroupState? reconstructed;
    for (final entry in prepared.precedingControlTranscript) {
      final result = stateMachine.apply(
        previous: reconstructed,
        signedControl: entry.signedControl,
        localUserId: localUserId,
      );
      if (result is! GroupControlAccepted) {
        return const Result.failure(
          SecurityFailure(SecurityFailureKind.integrityCheckFailed),
        );
      }
      reconstructed = result.state;
    }
    final applied = stateMachine.apply(
      previous: reconstructed,
      signedControl: prepared.signedControl,
      localUserId: localUserId,
    );
    if (prepared.outbound ||
        prepared.consumedKeyPackageState == null ||
        prepared.signedControl.event.groupId != probe.groupId ||
        applied is! GroupControlAccepted) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.integrityCheckFailed),
      );
    }
    return Result.success(
      PreparedGroupInboxTransition(
        expectedPrevious: null,
        next: applied.state,
        prepared: prepared,
      ),
    );
  }

  Future<Result<PreparedGroupInboxCommit>> _control(
    GroupMlsTransportProbe probe,
    Uint8List mlsObject,
  ) async {
    if (probe.joinCapable) {
      final existing = await repository.readGroup(probe.groupId);
      if (existing case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      if ((existing as Success<GroupState?>).value == null) {
        return _welcome(probe, mlsObject);
      }
    }
    final context = await _currentContext(probe.groupId);
    if (context case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final (current, opaqueState) =
        (context as Success<(GroupState, Uint8List)>).value;
    final inspected = await crypto.inspectIncomingControl(
      current: current,
      currentOpaqueMlsState: opaqueState,
      mlsObject: mlsObject,
      localUserId: localUserId.toLowerCase(),
      localDeviceId: localDeviceId.toLowerCase(),
    );
    if (inspected case FailureResult(failure: final failure)) {
      // A control that does not extend the local chain may still be an
      // authentic sibling another device accepted at the same revision.
      final fork = await _resolveFork(
        current: current,
        opaqueState: opaqueState,
        mlsObject: mlsObject,
        probe: probe,
      );
      return fork ?? Result.failure(failure);
    }
    final prepared = (inspected as Success<PreparedGroupTransition>).value;
    final applied = stateMachine.apply(
      previous: current,
      signedControl: prepared.signedControl,
      localUserId: localUserId,
    );
    if (prepared.outbound ||
        prepared.signedControl.event.groupId != probe.groupId ||
        applied is! GroupControlAccepted) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.integrityCheckFailed),
      );
    }
    return Result.success(
      PreparedGroupInboxTransition(
        expectedPrevious: current,
        next: applied.state,
        prepared: prepared,
      ),
    );
  }

  Future<Result<PreparedGroupInboxCommit>> _application(
    GroupMlsTransportProbe probe,
    Uint8List mlsObject,
  ) async {
    final context = await _currentContext(probe.groupId);
    if (context case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final (current, opaqueState) =
        (context as Success<(GroupState, Uint8List)>).value;
    final inspected = await crypto.inspectIncomingApplication(
      current: current,
      currentOpaqueMlsState: opaqueState,
      mlsObject: mlsObject,
      localUserId: localUserId.toLowerCase(),
      localDeviceId: localDeviceId.toLowerCase(),
    );
    if (inspected case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final prepared = (inspected as Success<PreparedGroupMessage>).value;
    if (prepared.outbound || prepared.groupId != probe.groupId) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.integrityCheckFailed),
      );
    }
    return Result.success(
      PreparedGroupInboxMessage(expectedGroup: current, prepared: prepared),
    );
  }

  /// Returns null when the object is not an orderable sibling, so the caller
  /// keeps the original authentication failure.
  Future<Result<PreparedGroupInboxCommit>?> _resolveFork({
    required GroupState current,
    required Uint8List opaqueState,
    required Uint8List mlsObject,
    required GroupMlsTransportProbe probe,
  }) async {
    if (probe.groupId != current.groupId) return null;
    final resolved = await crypto.reconcileFork(
      current: current,
      currentOpaqueMlsState: opaqueState,
      siblingCommits: [mlsObject],
      localUserId: localUserId.toLowerCase(),
      localDeviceId: localDeviceId.toLowerCase(),
    );
    if (resolved is! Success<GroupForkResolution>) return null;
    final resolution = resolved.value;
    final (eventId, signerUserId, signerDeviceId) = switch (resolution) {
      GroupForkLocalBranchCanonical(:final supersededEventIds) => (
        supersededEventIds.single,
        current.groupId,
        current.groupId,
      ),
      GroupForkLocalBranchSuperseded(
        :final canonicalEventId,
        :final canonicalSignerUserId,
      ) =>
        (canonicalEventId, canonicalSignerUserId, canonicalSignerUserId),
    };
    return Result.success(
      PreparedGroupInboxForkResolution(
        resolution: resolution,
        record: GroupQuarantineRecord(
          groupId: current.groupId,
          reason: GroupQuarantineReason.siblingCommit,
          // The verified sibling event id already identifies the branch
          // uniquely; Dart never computes a digest itself.
          opaqueDigest: _eventIdBytes(eventId),
          receivedAt: clock().toUtc(),
        ),
        siblingEventId: eventId,
        siblingSignerUserId: signerUserId,
        siblingSignerDeviceId: signerDeviceId,
      ),
    );
  }

  Uint8List _eventIdBytes(String eventId) => Uint8List.fromList([
    for (var index = 0; index + 1 < eventId.length; index += 2)
      int.parse(eventId.substring(index, index + 2), radix: 16),
  ]);

  Future<Result<(GroupState, Uint8List)>> _currentContext(
    String groupId,
  ) async {
    final groupResult = await repository.readGroup(groupId);
    if (groupResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final current = (groupResult as Success<GroupState?>).value;
    if (current == null || current.lifecycle != GroupLifecycle.active) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.unauthenticatedInput),
      );
    }
    final stateResult = await repository.readOpaqueMlsState(groupId);
    if (stateResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final opaqueState = (stateResult as Success<Uint8List?>).value;
    if (opaqueState == null || opaqueState.isEmpty) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.integrityCheckFailed),
      );
    }
    return Result.success((current, opaqueState));
  }
}

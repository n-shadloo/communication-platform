import 'dart:typed_data';

import 'package:communication_platform/core/application/ports/pairwise_session_crypto_port.dart';
import 'package:communication_platform/core/protocol/pairwise_crypto_model.dart'
    as native;
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/pairwise/application/ports/pairwise_orchestration_ports.dart';
import 'package:communication_platform/features/pairwise/domain/pairwise_model.dart';

/// Selects only reviewed native pairwise-v1 operations. There is deliberately no
/// classical-only branch and no Dart-side cryptographic construction.
final class NativePairwiseOutboundPreparation
    implements PairwiseOutboundPreparationPort {
  const NativePairwiseOutboundPreparation(this.crypto);

  final PairwiseSessionCryptoPort crypto;

  @override
  Future<Result<PairwisePreparedOutbound>> prepareOutbound({
    required String currentDeviceId,
    required VerifiedPairwiseLiveDevice recipient,
    required Uint8List openedOpaquePayload,
    required int migrationUnixDay,
    required PairwisePreparationContext context,
    required VerifiedPairwiseClaim? claim,
  }) async {
    try {
      final senderDeviceId = _uuidBytes(currentDeviceId);
      final recipientUserId = _uuidBytes(recipient.userId);
      final recipientDeviceId = _uuidBytes(recipient.deviceId);
      final primary = context.primary;

      if (primary != null &&
          primary.disposition !=
              PairwiseSessionDisposition.primaryBidirectional) {
        return _integrityFailure();
      }

      if (primary != null && primary.repairState == PairwiseRepairState.ready) {
        if (claim != null || primary.repairAuthorization != null) {
          return _integrityFailure();
        }
        final encrypted = await crypto.encrypt(
          deviceState: context.deviceState.opaqueState,
          unixDay: migrationUnixDay,
          recipientDeviceId: recipientDeviceId,
          session: _nativeState(primary),
          innerPayload: openedOpaquePayload,
          otherSessionsSkippedKeys: context.otherSessionsSkippedKeyCount,
        );
        if (encrypted case FailureResult(failure: final failure)) {
          return Result.failure(failure);
        }
        return Result.success(
          _prepared(
            (encrypted as Success<native.PreparedPairwiseEnvelope>).value,
          ),
        );
      }

      final isNew = primary == null;
      final isAuthorizedReplacement =
          primary?.repairState == PairwiseRepairState.replacementPending &&
          primary?.repairAuthorization != null;
      if ((!isNew && !isAuthorizedReplacement) || claim == null) {
        return const Result.failure(
          SecurityFailure(SecurityFailureKind.policyBlocked),
        );
      }
      if (!_sameRecipient(recipient, claim.device) ||
          claim.bundle.deviceId.toLowerCase() !=
              recipient.deviceId.toLowerCase() ||
          !claim.bundle.hasPostQuantumSignedPrekey) {
        return _integrityFailure();
      }
      final initiated = await crypto.initiate(
        deviceState: context.deviceState.opaqueState,
        unixDay: migrationUnixDay,
        senderDeviceId: senderDeviceId,
        recipientUserId: recipientUserId,
        recipientDeviceId: recipientDeviceId,
        recipientSelfSigningPublic: recipient.selfSigningPublic,
        verifiedBundle: claim.bundle,
        innerPayload: openedOpaquePayload,
        otherSessionsSkippedKeys: context.otherSessionsSkippedKeyCount,
        repairAuthorization: primary?.repairAuthorization,
      );
      if (initiated case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      final result =
          (initiated as Success<native.PairwiseInitiationResult>).value;
      return Result.success(_prepared(result.prepared));
    } on FormatException {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
  }

  PairwisePreparedOutbound _prepared(
    native.PreparedPairwiseEnvelope envelope,
  ) => PairwisePreparedOutbound(
    exactCiphertext: envelope.ciphertext,
    sessionId: envelope.nextSession.sessionId,
    nextOpaqueSessionState: envelope.nextSession.opaqueState,
    nextSkippedKeyCount: envelope.nextSession.skippedKeyCount,
    disposition: PairwiseSessionDisposition.primaryBidirectional,
  );

  native.PairwiseSessionState _nativeState(PairwiseSessionSnapshot session) =>
      native.PairwiseSessionState(
        sessionId: session.sessionId,
        opaqueState: session.opaqueState,
        skippedKeyCount: session.skippedKeyCount,
      );

  bool _sameRecipient(
    VerifiedPairwiseLiveDevice left,
    VerifiedPairwiseLiveDevice right,
  ) =>
      left.userId == right.userId &&
      left.deviceId.toLowerCase() == right.deviceId.toLowerCase() &&
      _same(left.selfSigningPublic, right.selfSigningPublic) &&
      left.device.registrationId == right.device.registrationId &&
      left.device.bundleVersion == right.device.bundleVersion &&
      _same(left.device.identityPublic, right.device.identityPublic) &&
      left.device.crossSignature != null &&
      right.device.crossSignature != null &&
      _same(left.device.crossSignature!, right.device.crossSignature!);
}

Result<PairwisePreparedOutbound> _integrityFailure() => const Result.failure(
  SecurityFailure(SecurityFailureKind.integrityCheckFailed),
);

Uint8List _uuidBytes(String value) {
  final normalized = value.replaceAll('-', '').toLowerCase();
  if (normalized.length != 32 ||
      !RegExp(r'^[0-9a-f]{32}$').hasMatch(normalized)) {
    throw const FormatException('invalid UUID');
  }
  return Uint8List.fromList([
    for (var offset = 0; offset < normalized.length; offset += 2)
      int.parse(normalized.substring(offset, offset + 2), radix: 16),
  ]);
}

bool _same(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  var difference = 0;
  for (var index = 0; index < left.length; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}

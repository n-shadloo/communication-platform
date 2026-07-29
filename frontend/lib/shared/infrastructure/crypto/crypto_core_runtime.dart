import 'dart:typed_data';

import 'package:communication_platform/core/application/ports/crypto_core_port.dart';
import 'package:communication_platform/core/application/ports/enrollment_crypto_port.dart';
import 'package:communication_platform/core/application/ports/identity_crypto_port.dart';
import 'package:communication_platform/core/application/ports/pairwise_crypto_port.dart';
import 'package:communication_platform/core/protocol/crypto_core_model.dart';
import 'package:communication_platform/core/protocol/enrollment_crypto_model.dart';
import 'package:communication_platform/core/protocol/identity_protocol_model.dart';
import 'package:communication_platform/core/protocol/pairwise_crypto_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';

/// Testable worker boundary. Production implements this in one dedicated isolate.
abstract interface class CryptoCoreWorker {
  Future<Result<CryptoCoreCapabilities>> capabilities();

  Future<Result<void>> selfTest();

  Future<void> close();
}

abstract interface class PairwiseCryptoWorker {
  Future<Result<PairwiseCryptoResponse>> pairwiseOperation({
    required PairwiseCryptoOperation operation,
    required Uint8List payload,
  });
}

/// Scope-owned lifecycle wrapper around the platform crypto worker.
final class CryptoCoreRuntime
    implements
        CryptoCorePort,
        EnrollmentCryptoPort,
        IdentityCryptoPort,
        PairwiseCryptoPort {
  CryptoCoreRuntime({
    required this.worker,
    this.enrollmentWorker,
    this.identityWorker,
    this.pairwiseWorker,
  });

  final CryptoCoreWorker worker;
  final EnrollmentCryptoWorker? enrollmentWorker;
  final IdentityCryptoWorker? identityWorker;
  final PairwiseCryptoWorker? pairwiseWorker;
  bool _closed = false;

  @override
  Future<Result<CryptoCoreCapabilities>> capabilities() {
    if (_closed) {
      return Future<Result<CryptoCoreCapabilities>>.value(
        const Result<CryptoCoreCapabilities>.failure(
          CryptoCoreFailure(CryptoCoreFailureCode.stateViolation),
        ),
      );
    }
    return worker.capabilities();
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await worker.close();
  }

  @override
  Future<Result<void>> selfTest() {
    if (_closed) {
      return Future<Result<void>>.value(
        const Result<void>.failure(
          CryptoCoreFailure(CryptoCoreFailureCode.stateViolation),
        ),
      );
    }
    return worker.selfTest();
  }

  @override
  Future<Result<DeviceKeyPackage>> prepareDevice({required Uint8List userId}) =>
      enrollmentWorker?.prepareDevice(userId: userId) ?? _unsupported();

  @override
  Future<Result<IdentityKeyPackage>> prepareFirstIdentity({
    required Uint8List userId,
  }) =>
      enrollmentWorker?.prepareFirstIdentity(userId: userId) ?? _unsupported();

  @override
  Future<Result<IdentityKeyPackage>> restoreIdentity({
    required Uint8List userId,
    required Uint8List recoverySecret,
    required Uint8List backup,
  }) =>
      enrollmentWorker?.restoreIdentity(
        userId: userId,
        recoverySecret: recoverySecret,
        backup: backup,
      ) ??
      _unsupported();

  @override
  Future<Result<IdentityKeyPackage>> sanitizeIdentity({
    required IdentityKeyPackage package,
  }) => enrollmentWorker?.sanitizeIdentity(package: package) ?? _unsupported();

  @override
  Future<Result<Uint8List>> crossSignDevice({
    required DeviceKeyPackage device,
    required IdentityKeyPackage identity,
    required Uint8List deviceId,
    required int bundleVersion,
  }) =>
      enrollmentWorker?.crossSignDevice(
        device: device,
        identity: identity,
        deviceId: deviceId,
        bundleVersion: bundleVersion,
      ) ??
      _unsupported();

  @override
  Future<Result<Uint8List>> createDeviceLogRecord({
    required IdentityKeyPackage identity,
    required Uint8List userId,
    required int sequence,
    required Uint8List previousHash,
    required Uint8List canonicalLiveSet,
    required int identityVersion,
    required int coarseUnixDay,
  }) =>
      enrollmentWorker?.createDeviceLogRecord(
        identity: identity,
        userId: userId,
        sequence: sequence,
        previousHash: previousHash,
        canonicalLiveSet: canonicalLiveSet,
        identityVersion: identityVersion,
        coarseUnixDay: coarseUnixDay,
      ) ??
      _unsupported();

  @override
  Future<Result<DeviceLogInspection>> inspectDeviceLogRecord({
    required IdentityKeyPackage identity,
    required Uint8List userId,
    required Uint8List record,
  }) =>
      enrollmentWorker?.inspectDeviceLogRecord(
        identity: identity,
        userId: userId,
        record: record,
      ) ??
      _unsupported();

  @override
  Future<Result<void>> verifyIdentity({
    required Uint8List userId,
    required PeerIdentityPublic identity,
  }) =>
      identityWorker?.verifyIdentity(userId: userId, identity: identity) ??
      _unsupported();

  @override
  Future<Result<void>> verifyClaimedBundle({
    required Uint8List userId,
    required Uint8List deviceId,
    required Uint8List selfSigningPublic,
    required ClaimedPrekeyBundle bundle,
  }) =>
      identityWorker?.verifyClaimedBundle(
        userId: userId,
        deviceId: deviceId,
        selfSigningPublic: selfSigningPublic,
        bundle: bundle,
      ) ??
      _unsupported();

  @override
  Future<Result<PeerDeviceLogInspection>> inspectPeerDeviceLog({
    required Uint8List userId,
    required Uint8List selfSigningPublic,
    required List<PeerPublicDevice> liveDevices,
    required bool requireCurrentLiveSet,
    required Uint8List record,
  }) =>
      identityWorker?.inspectPeerDeviceLog(
        userId: userId,
        selfSigningPublic: selfSigningPublic,
        liveDevices: liveDevices,
        requireCurrentLiveSet: requireCurrentLiveSet,
        record: record,
      ) ??
      _unsupported();

  @override
  Future<Result<SafetyFingerprint>> safetyFingerprint({
    required Uint8List localUserId,
    required Uint8List localMasterPublic,
    required Uint8List peerUserId,
    required Uint8List peerMasterPublic,
  }) =>
      identityWorker?.safetyFingerprint(
        localUserId: localUserId,
        localMasterPublic: localMasterPublic,
        peerUserId: peerUserId,
        peerMasterPublic: peerMasterPublic,
      ) ??
      _unsupported();

  @override
  Future<Result<UserSigningAttestation>> attestPeerMaster({
    required IdentityKeyPackage localIdentity,
    required Uint8List peerUserId,
    required Uint8List peerMasterPublic,
  }) =>
      identityWorker?.attestPeerMaster(
        localIdentity: localIdentity,
        peerUserId: peerUserId,
        peerMasterPublic: peerMasterPublic,
      ) ??
      _unsupported();

  @override
  Future<Result<void>> verifyUserAttestation({
    required Uint8List signerUserId,
    required Uint8List signerUserSigningPublic,
    required Uint8List peerUserId,
    required Uint8List peerMasterPublic,
    required UserSigningAttestation attestation,
  }) =>
      identityWorker?.verifyUserAttestation(
        signerUserId: signerUserId,
        signerUserSigningPublic: signerUserSigningPublic,
        peerUserId: peerUserId,
        peerMasterPublic: peerMasterPublic,
        attestation: attestation,
      ) ??
      _unsupported();

  @override
  Future<Result<PairwiseCryptoResponse>> pairwiseOperation({
    required PairwiseCryptoOperation operation,
    required Uint8List payload,
  }) async {
    if (_closed) {
      return const Result.failure(
        CryptoCoreFailure(CryptoCoreFailureCode.stateViolation),
      );
    }
    final pairwise = pairwiseWorker;
    if (pairwise == null) {
      return _unsupported();
    }
    final capabilityResult = await worker.capabilities();
    if (capabilityResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final capabilities =
        (capabilityResult as Success<CryptoCoreCapabilities>).value;
    return capabilities.supportsPairwiseTransportV1
        ? pairwise.pairwiseOperation(operation: operation, payload: payload)
        : _unsupported();
  }

  Future<Result<T>> _unsupported<T>() async => const Result.failure(
    UnsupportedProtocolFailure(UnsupportedProtocolFailureKind.capability),
  );

  @override
  String toString() => 'CryptoCoreRuntime(<redacted>)';
}

/// Fail-closed implementation used when the reviewed native boundary is absent.
final class UnsupportedCryptoCore
    implements
        CryptoCorePort,
        EnrollmentCryptoPort,
        IdentityCryptoPort,
        PairwiseCryptoPort {
  const UnsupportedCryptoCore();

  @override
  Future<Result<CryptoCoreCapabilities>> capabilities() async {
    return const Result<CryptoCoreCapabilities>.failure(
      UnsupportedProtocolFailure(UnsupportedProtocolFailureKind.capability),
    );
  }

  @override
  Future<void> close() async {}

  @override
  Future<Result<void>> selfTest() async {
    return const Result<void>.failure(
      UnsupportedProtocolFailure(UnsupportedProtocolFailureKind.capability),
    );
  }

  @override
  Future<Result<Uint8List>> createDeviceLogRecord({
    required IdentityKeyPackage identity,
    required Uint8List userId,
    required int sequence,
    required Uint8List previousHash,
    required Uint8List canonicalLiveSet,
    required int identityVersion,
    required int coarseUnixDay,
  }) async => const Result.failure(
    UnsupportedProtocolFailure(UnsupportedProtocolFailureKind.capability),
  );

  @override
  Future<Result<Uint8List>> crossSignDevice({
    required DeviceKeyPackage device,
    required IdentityKeyPackage identity,
    required Uint8List deviceId,
    required int bundleVersion,
  }) async => const Result.failure(
    UnsupportedProtocolFailure(UnsupportedProtocolFailureKind.capability),
  );

  @override
  Future<Result<DeviceKeyPackage>> prepareDevice({
    required Uint8List userId,
  }) async => const Result.failure(
    UnsupportedProtocolFailure(UnsupportedProtocolFailureKind.capability),
  );

  @override
  Future<Result<IdentityKeyPackage>> prepareFirstIdentity({
    required Uint8List userId,
  }) async => const Result.failure(
    UnsupportedProtocolFailure(UnsupportedProtocolFailureKind.capability),
  );

  @override
  Future<Result<IdentityKeyPackage>> restoreIdentity({
    required Uint8List userId,
    required Uint8List recoverySecret,
    required Uint8List backup,
  }) async => const Result.failure(
    UnsupportedProtocolFailure(UnsupportedProtocolFailureKind.capability),
  );

  @override
  Future<Result<IdentityKeyPackage>> sanitizeIdentity({
    required IdentityKeyPackage package,
  }) async => const Result.failure(
    UnsupportedProtocolFailure(UnsupportedProtocolFailureKind.capability),
  );

  @override
  Future<Result<DeviceLogInspection>> inspectDeviceLogRecord({
    required IdentityKeyPackage identity,
    required Uint8List userId,
    required Uint8List record,
  }) async => const Result.failure(
    UnsupportedProtocolFailure(UnsupportedProtocolFailureKind.capability),
  );

  @override
  String toString() => 'UnsupportedCryptoCore(<redacted>)';

  @override
  Future<Result<void>> verifyIdentity({
    required Uint8List userId,
    required PeerIdentityPublic identity,
  }) => _identityUnsupported();

  @override
  Future<Result<void>> verifyClaimedBundle({
    required Uint8List userId,
    required Uint8List deviceId,
    required Uint8List selfSigningPublic,
    required ClaimedPrekeyBundle bundle,
  }) => _identityUnsupported();

  @override
  Future<Result<PeerDeviceLogInspection>> inspectPeerDeviceLog({
    required Uint8List userId,
    required Uint8List selfSigningPublic,
    required List<PeerPublicDevice> liveDevices,
    required bool requireCurrentLiveSet,
    required Uint8List record,
  }) => _identityUnsupported();

  @override
  Future<Result<SafetyFingerprint>> safetyFingerprint({
    required Uint8List localUserId,
    required Uint8List localMasterPublic,
    required Uint8List peerUserId,
    required Uint8List peerMasterPublic,
  }) => _identityUnsupported();

  @override
  Future<Result<UserSigningAttestation>> attestPeerMaster({
    required IdentityKeyPackage localIdentity,
    required Uint8List peerUserId,
    required Uint8List peerMasterPublic,
  }) => _identityUnsupported();

  @override
  Future<Result<void>> verifyUserAttestation({
    required Uint8List signerUserId,
    required Uint8List signerUserSigningPublic,
    required Uint8List peerUserId,
    required Uint8List peerMasterPublic,
    required UserSigningAttestation attestation,
  }) => _identityUnsupported();

  @override
  Future<Result<PairwiseCryptoResponse>> pairwiseOperation({
    required PairwiseCryptoOperation operation,
    required Uint8List payload,
  }) => _identityUnsupported();

  Future<Result<T>> _identityUnsupported<T>() => Future<Result<T>>.value(
    const Result.failure(
      UnsupportedProtocolFailure(UnsupportedProtocolFailureKind.capability),
    ),
  );
}

import 'dart:async';
import 'dart:typed_data';

import 'package:communication_platform/app/config/app_environment.dart';
import 'package:communication_platform/core/application/ports/crypto_core_port.dart';
import 'package:communication_platform/core/application/ports/enrollment_crypto_port.dart';
import 'package:communication_platform/core/application/ports/identity_crypto_port.dart';
import 'package:communication_platform/core/application/ports/time_source.dart';
import 'package:communication_platform/core/protocol/enrollment_crypto_model.dart';
import 'package:communication_platform/core/protocol/identity_protocol_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/enrollment_crypto_native_session.dart';
import 'package:communication_platform/shared/infrastructure/crypto/platform_crypto_core.dart';
import 'package:communication_platform/shared/infrastructure/time/system_time_source.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Dependency descriptors are immutable. Their instances are owned by ProviderScope,
/// which lets tests and app roots provide isolated overrides without global mutation.
final timeSourceProvider = Provider<TimeSource>(
  (ref) => const SystemTimeSource(),
);

final appEnvironmentProvider = Provider<AppEnvironment>(
  (ref) => AppEnvironment.development,
);

typedef CryptoCoreFactory = CryptoCorePort Function();

final cryptoCoreFactoryProvider = Provider<CryptoCoreFactory>(
  (ref) => createPlatformCryptoCore,
);

final cryptoCoreProvider = Provider<CryptoCorePort>((ref) {
  final cryptoCore = ref.watch(cryptoCoreFactoryProvider)();
  ref.onDispose(() {
    unawaited(cryptoCore.close());
  });
  return cryptoCore;
});

final enrollmentCryptoProvider = Provider<EnrollmentCryptoPort>((ref) {
  final cryptoCore = ref.watch(cryptoCoreProvider);
  return cryptoCore is EnrollmentCryptoPort
      ? cryptoCore as EnrollmentCryptoPort
      : const UnsupportedEnrollmentCrypto();
});

final identityCryptoProvider = Provider<IdentityCryptoPort>((ref) {
  final cryptoCore = ref.watch(cryptoCoreProvider);
  return cryptoCore is IdentityCryptoPort
      ? cryptoCore as IdentityCryptoPort
      : const UnsupportedIdentityCrypto();
});

final class UnsupportedIdentityCrypto implements IdentityCryptoPort {
  const UnsupportedIdentityCrypto();

  Future<Result<T>> _unsupported<T>() async => const Result.failure(
    UnsupportedProtocolFailure(UnsupportedProtocolFailureKind.capability),
  );

  @override
  Future<Result<UserSigningAttestation>> attestPeerMaster({
    required IdentityKeyPackage localIdentity,
    required Uint8List peerUserId,
    required Uint8List peerMasterPublic,
  }) => _unsupported();
  @override
  Future<Result<PeerDeviceLogInspection>> inspectPeerDeviceLog({
    required Uint8List userId,
    required Uint8List selfSigningPublic,
    required List<PeerPublicDevice> liveDevices,
    required bool requireCurrentLiveSet,
    required Uint8List record,
  }) => _unsupported();
  @override
  Future<Result<SafetyFingerprint>> safetyFingerprint({
    required Uint8List localUserId,
    required Uint8List localMasterPublic,
    required Uint8List peerUserId,
    required Uint8List peerMasterPublic,
  }) => _unsupported();
  @override
  Future<Result<void>> verifyClaimedBundle({
    required Uint8List userId,
    required Uint8List deviceId,
    required Uint8List selfSigningPublic,
    required ClaimedPrekeyBundle bundle,
  }) => _unsupported();
  @override
  Future<Result<void>> verifyIdentity({
    required Uint8List userId,
    required PeerIdentityPublic identity,
  }) => _unsupported();
  @override
  Future<Result<void>> verifyUserAttestation({
    required Uint8List signerUserId,
    required Uint8List signerUserSigningPublic,
    required Uint8List peerUserId,
    required Uint8List peerMasterPublic,
    required UserSigningAttestation attestation,
  }) => _unsupported();
}

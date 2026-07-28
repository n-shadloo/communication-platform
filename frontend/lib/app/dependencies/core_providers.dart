import 'dart:async';

import 'package:communication_platform/core/application/ports/crypto_core_port.dart';
import 'package:communication_platform/core/application/ports/enrollment_crypto_port.dart';
import 'package:communication_platform/core/application/ports/time_source.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/enrollment_crypto_native_session.dart';
import 'package:communication_platform/shared/infrastructure/crypto/platform_crypto_core.dart';
import 'package:communication_platform/shared/infrastructure/time/system_time_source.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Dependency descriptors are immutable. Their instances are owned by ProviderScope,
/// which lets tests and app roots provide isolated overrides without global mutation.
final timeSourceProvider = Provider<TimeSource>(
  (ref) => const SystemTimeSource(),
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

import 'dart:io';

import 'package:communication_platform/app/dependencies/core_providers.dart';
import 'package:communication_platform/core/protocol/crypto_core_model.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Android loads the versioned Rust core in its isolate and self-tests',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final cryptoCore = container.read(cryptoCoreProvider);
      addTearDown(cryptoCore.close);

      final capabilityResult = await cryptoCore.capabilities();
      expect(capabilityResult, isA<Success<CryptoCoreCapabilities>>());
      final capabilities =
          (capabilityResult as Success<CryptoCoreCapabilities>).value;
      expect(capabilities.abiVersion, CryptoCoreProtocolV1.abiVersion);
      expect(capabilities.supportsRequiredFoundation, isTrue);
      expect(capabilities.maxInputBytes, greaterThan(0));
      expect(capabilities.maxCborDepth, greaterThan(0));
      expect(capabilities.maxCborItems, greaterThan(0));

      expect(await cryptoCore.selfTest(), isA<Success<void>>());
    },
    skip: !Platform.isAndroid,
  );
}

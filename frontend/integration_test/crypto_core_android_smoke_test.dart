import 'dart:io';
import 'dart:typed_data';

import 'package:communication_platform/app/dependencies/core_providers.dart';
import 'package:communication_platform/core/protocol/crypto_core_model.dart';
import 'package:communication_platform/core/protocol/identity_protocol_model.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Android loads the versioned Rust core in its isolate and verifies backend protocol vectors',
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

      final identityCrypto = container.read(identityCryptoProvider);
      final localUser = Uint8List.fromList(List<int>.filled(16, 1));
      final localMaster = Uint8List.fromList(List<int>.filled(32, 2));
      final peerUser = Uint8List.fromList(List<int>.filled(16, 3));
      final peerMaster = Uint8List.fromList(List<int>.filled(32, 4));
      final forward = await identityCrypto.safetyFingerprint(
        localUserId: localUser,
        localMasterPublic: localMaster,
        peerUserId: peerUser,
        peerMasterPublic: peerMaster,
      );
      final reverse = await identityCrypto.safetyFingerprint(
        localUserId: peerUser,
        localMasterPublic: peerMaster,
        peerUserId: localUser,
        peerMasterPublic: localMaster,
      );
      expect(forward, isA<Success<SafetyFingerprint>>());
      expect(reverse, isA<Success<SafetyFingerprint>>());
      expect(
        (forward as Success<SafetyFingerprint>).value.digest,
        orderedEquals((reverse as Success<SafetyFingerprint>).value.digest),
      );

      expect(
        await identityCrypto.verifyIdentity(
          userId: peerUser,
          identity: PeerIdentityPublic(
            masterPublic: peerMaster,
            selfSigningPublic: Uint8List.fromList(List<int>.filled(32, 5)),
            userSigningPublic: Uint8List.fromList(List<int>.filled(32, 6)),
            masterSignature: Uint8List(64),
            version: 1,
          ),
        ),
        isA<FailureResult<void>>(),
      );
    },
    skip: !Platform.isAndroid,
  );
}

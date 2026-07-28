import 'package:communication_platform/app/dependencies/core_providers.dart';
import 'package:communication_platform/core/application/ports/crypto_core_port.dart';
import 'package:communication_platform/core/protocol/crypto_core_model.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ProviderScope owns and closes the crypto runtime', () {
    final fake = _FakeCryptoCore();
    final container = ProviderContainer(
      overrides: [cryptoCoreFactoryProvider.overrideWithValue(() => fake)],
    );

    expect(container.read(cryptoCoreProvider), same(fake));
    expect(fake.closeCalls, 0);

    container.dispose();

    expect(fake.closeCalls, 1);
  });
}

final class _FakeCryptoCore implements CryptoCorePort {
  int closeCalls = 0;

  @override
  Future<Result<CryptoCoreCapabilities>> capabilities() async {
    return Result<CryptoCoreCapabilities>.success(
      CryptoCoreCapabilities(
        abiVersion: 1,
        featureBits: CryptoCoreProtocolV1.knownFeatureBits,
        maxInputBytes: 1048576,
        maxCborDepth: 32,
        maxCborItems: 4096,
      ),
    );
  }

  @override
  Future<void> close() {
    closeCalls += 1;
    return Future<void>.value();
  }

  @override
  Future<Result<void>> selfTest() async {
    return const Result<void>.success(null);
  }
}

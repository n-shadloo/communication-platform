import 'package:communication_platform/core/protocol/crypto_core_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/shared/infrastructure/crypto/crypto_core_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runtime delegates to its worker and closes exactly once', () async {
    final worker = _FakeWorker();
    final runtime = CryptoCoreRuntime(worker: worker);

    expect(await runtime.capabilities(), isA<Success<Object?>>());
    expect(await runtime.selfTest(), isA<Success<void>>());

    await runtime.close();
    await runtime.close();

    expect(worker.capabilityCalls, 1);
    expect(worker.selfTestCalls, 1);
    expect(worker.closeCalls, 1);
    final afterClose = await runtime.capabilities();
    expect(
      (afterClose as FailureResult<CryptoCoreCapabilities>).failure,
      isA<CryptoCoreFailure>().having(
        (failure) => failure.code,
        'code',
        CryptoCoreFailureCode.stateViolation,
      ),
    );
    expect(runtime.toString(), isNot(contains(worker.toString())));
  });

  test('unsupported platforms fail closed for every operation', () async {
    const cryptoCore = UnsupportedCryptoCore();

    for (final result in <Result<Object?>>[
      await cryptoCore.capabilities(),
      await cryptoCore.selfTest(),
    ]) {
      expect(
        (result as FailureResult<Object?>).failure,
        isA<UnsupportedProtocolFailure>().having(
          (failure) => failure.kind,
          'kind',
          UnsupportedProtocolFailureKind.capability,
        ),
      );
    }
    await cryptoCore.close();
  });
}

final class _FakeWorker implements CryptoCoreWorker {
  int capabilityCalls = 0;
  int selfTestCalls = 0;
  int closeCalls = 0;

  @override
  Future<Result<CryptoCoreCapabilities>> capabilities() async {
    capabilityCalls += 1;
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
  Future<void> close() async {
    closeCalls += 1;
  }

  @override
  Future<Result<void>> selfTest() async {
    selfTestCalls += 1;
    return const Result<void>.success(null);
  }

  @override
  String toString() => '_FakeWorker(sensitive-debug-marker)';
}

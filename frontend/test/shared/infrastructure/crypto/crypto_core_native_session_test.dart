import 'package:communication_platform/core/protocol/crypto_core_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/crypto_core_ffi.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/crypto_core_native_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts the exact version-1 capability record and self-test', () {
    final api = _FakeNativeApi();
    final session = CryptoCoreNativeSession(api: api);

    final capabilityResult = session.capabilities();
    final capabilities =
        (capabilityResult as Success<CryptoCoreCapabilities>).value;
    expect(capabilities.abiVersion, 1);
    expect(capabilities.supportsRequiredFoundation, isTrue);
    expect(capabilities.maxInputBytes, 1048576);
    expect(session.selfTest(), isA<Success<void>>());
    expect(api.capabilityCalls, 1);
    expect(api.selfTestCalls, 1);
  });

  test('rejects ABI mismatch before reading the output structure', () {
    final api = _FakeNativeApi(abiVersionValue: 2);
    final result = CryptoCoreNativeSession(api: api).capabilities();

    expect(
      (result as FailureResult<CryptoCoreCapabilities>).failure,
      isA<UnsupportedProtocolFailure>().having(
        (failure) => failure.kind,
        'kind',
        UnsupportedProtocolFailureKind.version,
      ),
    );
    expect(api.capabilityCalls, 0);
  });

  test('rejects malformed or incomplete native capability records', () {
    final snapshots = <CryptoCoreNativeCapabilitiesSnapshot>[
      _snapshot(structSize: 31),
      _snapshot(abiVersion: 2),
      _snapshot(reserved: 1),
      _snapshot(featureBits: -1),
      _snapshot(maxInputBytes: 0),
      _snapshot(maxCborDepth: 0),
      _snapshot(maxCborItems: 0),
    ];
    for (final snapshot in snapshots) {
      final result = CryptoCoreNativeSession(
        api: _FakeNativeApi(snapshot: snapshot),
      ).capabilities();
      expect(
        (result as FailureResult<CryptoCoreCapabilities>).failure,
        isA<SecurityFailure>().having(
          (failure) => failure.kind,
          'kind',
          SecurityFailureKind.malformedServerResponse,
        ),
      );
    }

    final incomplete = CryptoCoreNativeSession(
      api: _FakeNativeApi(
        snapshot: _snapshot(
          featureBits: CryptoCoreProtocolV1.knownFeatureBits & ~(1 << 3),
        ),
      ),
    ).capabilities();
    expect(
      (incomplete as FailureResult<CryptoCoreCapabilities>).failure,
      isA<UnsupportedProtocolFailure>().having(
        (failure) => failure.kind,
        'kind',
        UnsupportedProtocolFailureKind.capability,
      ),
    );
  });

  test('maps every native error code without accepting native text', () {
    for (final code in CryptoCoreFailureCode.values) {
      final capabilityResult = CryptoCoreNativeSession(
        api: _FakeNativeApi(snapshot: _snapshot(statusCode: code.wireValue)),
      ).capabilities();
      final failure =
          (capabilityResult as FailureResult<CryptoCoreCapabilities>).failure;
      expect(
        failure,
        isA<CryptoCoreFailure>().having(
          (failure) => failure.code,
          'code',
          code,
        ),
      );
      expect(failure.toString(), isNot(contains('native-sensitive-detail')));
    }

    final unknown = CryptoCoreNativeSession(
      api: _FakeNativeApi(snapshot: _snapshot(statusCode: 999)),
    ).capabilities();
    expect(
      (unknown as FailureResult<CryptoCoreCapabilities>).failure,
      isA<SecurityFailure>().having(
        (failure) => failure.kind,
        'kind',
        SecurityFailureKind.policyBlocked,
      ),
    );
  });

  test('native snapshots and bindings expose no debug payload', () {
    final snapshot = _snapshot(maxInputBytes: 123456, featureBits: 654321);

    expect(
      snapshot.toString(),
      'CryptoCoreNativeCapabilitiesSnapshot(<redacted>)',
    );
    expect(snapshot.toString(), isNot(contains('123456')));
    expect(snapshot.toString(), isNot(contains('654321')));
    expect(cryptoCoreAndroidLibraryName, 'libcommunication_crypto_core.so');
  });
}

CryptoCoreNativeCapabilitiesSnapshot _snapshot({
  int statusCode = 0,
  int structSize = 32,
  int abiVersion = 1,
  int featureBits = CryptoCoreProtocolV1.knownFeatureBits,
  int maxInputBytes = 1048576,
  int maxCborDepth = 32,
  int maxCborItems = 4096,
  int reserved = 0,
}) {
  return CryptoCoreNativeCapabilitiesSnapshot(
    statusCode: statusCode,
    structSize: structSize,
    abiVersion: abiVersion,
    featureBits: featureBits,
    maxInputBytes: maxInputBytes,
    maxCborDepth: maxCborDepth,
    maxCborItems: maxCborItems,
    reserved: reserved,
  );
}

final class _FakeNativeApi implements CryptoCoreNativeApi {
  _FakeNativeApi({
    this.abiVersionValue = 1,
    CryptoCoreNativeCapabilitiesSnapshot? snapshot,
  }) : snapshot = snapshot ?? _snapshot();

  final int abiVersionValue;
  final CryptoCoreNativeCapabilitiesSnapshot snapshot;
  int capabilityCalls = 0;
  int selfTestCalls = 0;

  @override
  int get capabilitiesStructSizeBytes => 32;

  @override
  int abiVersion() => abiVersionValue;

  @override
  CryptoCoreNativeCapabilitiesSnapshot capabilities() {
    capabilityCalls += 1;
    return snapshot;
  }

  @override
  int selfTest() {
    selfTestCalls += 1;
    return 0;
  }
}

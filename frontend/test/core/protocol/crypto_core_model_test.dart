import 'package:communication_platform/core/protocol/crypto_core_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('version-1 capability bits are stable and complete', () {
    expect(CryptoCoreProtocolV1.abiVersion, 1);
    expect(CryptoCoreProtocolV1.capabilitiesStructSizeBytes, 32);
    expect(
      CryptoCoreCapability.values.map((capability) => capability.featureBit),
      <int>[
        for (var bit = 0; bit < CryptoCoreCapability.values.length; bit += 1)
          1 << bit,
      ],
    );

    final capabilities = CryptoCoreCapabilities(
      abiVersion: 1,
      featureBits: CryptoCoreProtocolV1.knownFeatureBits | (1 << 20),
      maxInputBytes: 1048576,
      maxCborDepth: 32,
      maxCborItems: 4096,
    );

    expect(capabilities.supportsRequiredFoundation, isTrue);
    expect(capabilities.unknownFeatureBits, 1 << 20);
    expect(
      capabilities.capabilities,
      containsAll(CryptoCoreProtocolV1.requiredCapabilities),
    );
  });

  test('native failure wire values are stable and safely printable', () {
    expect(
      CryptoCoreFailureCode.values.map((code) => code.wireValue),
      List<int>.generate(14, (index) => index + 1),
    );
    for (final code in CryptoCoreFailureCode.values) {
      expect(CryptoCoreFailureCode.fromWireValue(code.wireValue), same(code));
      final output = CryptoCoreFailure(code).toString();
      expect(output, contains(code.name));
      expect(output, isNot(contains('native error')));
      expect(output, isNot(contains('input bytes')));
    }
    expect(CryptoCoreFailureCode.fromWireValue(0), isNull);
    expect(CryptoCoreFailureCode.fromWireValue(999), isNull);
  });
}

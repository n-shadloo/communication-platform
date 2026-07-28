import 'dart:ffi';

import 'package:communication_platform/core/protocol/crypto_core_model.dart';
import 'package:ffi/ffi.dart';

const String cryptoCoreAndroidLibraryName = 'libcommunication_crypto_core.so';

final class _CpCryptoCapabilitiesV1 extends Struct {
  @Uint32()
  external int structSize;

  @Uint32()
  external int abiVersion;

  @Uint64()
  external int featureBits;

  @Uint32()
  external int maxInputBytes;

  @Uint32()
  external int maxCborDepth;

  @Uint32()
  external int maxCborItems;

  @Uint32()
  external int reserved;
}

typedef _AbiVersionNative = Uint32 Function();
typedef _AbiVersionDart = int Function();
typedef _CapabilitiesNative =
    Int32 Function(Pointer<_CpCryptoCapabilitiesV1>, UintPtr);
typedef _CapabilitiesDart = int Function(Pointer<_CpCryptoCapabilitiesV1>, int);
typedef _SelfTestNative = Int32 Function();
typedef _SelfTestDart = int Function();

/// Injectable low-level API used by the native session and its boundary tests.
abstract interface class CryptoCoreNativeApi {
  int get capabilitiesStructSizeBytes;

  int abiVersion();

  CryptoCoreNativeCapabilitiesSnapshot capabilities();

  int selfTest();
}

/// A copy of public, non-secret native metadata.
final class CryptoCoreNativeCapabilitiesSnapshot {
  const CryptoCoreNativeCapabilitiesSnapshot({
    required this.statusCode,
    required this.structSize,
    required this.abiVersion,
    required this.featureBits,
    required this.maxInputBytes,
    required this.maxCborDepth,
    required this.maxCborItems,
    required this.reserved,
  });

  final int statusCode;
  final int structSize;
  final int abiVersion;
  final int featureBits;
  final int maxInputBytes;
  final int maxCborDepth;
  final int maxCborItems;
  final int reserved;

  @override
  String toString() => 'CryptoCoreNativeCapabilitiesSnapshot(<redacted>)';
}

/// Hand-written binding for the deliberately tiny version-1 C ABI.
final class DynamicCryptoCoreNativeApi implements CryptoCoreNativeApi {
  DynamicCryptoCoreNativeApi._(DynamicLibrary library)
    : _abiVersion = library.lookupFunction<_AbiVersionNative, _AbiVersionDart>(
        'cp_crypto_v1_abi_version',
      ),
      _capabilities = library
          .lookupFunction<_CapabilitiesNative, _CapabilitiesDart>(
            'cp_crypto_v1_capabilities',
          ),
      _selfTest = library.lookupFunction<_SelfTestNative, _SelfTestDart>(
        'cp_crypto_v1_self_test',
      );

  factory DynamicCryptoCoreNativeApi.openAndroid() {
    return DynamicCryptoCoreNativeApi._(
      DynamicLibrary.open(cryptoCoreAndroidLibraryName),
    );
  }

  final _AbiVersionDart _abiVersion;
  final _CapabilitiesDart _capabilities;
  final _SelfTestDart _selfTest;

  @override
  int get capabilitiesStructSizeBytes => sizeOf<_CpCryptoCapabilitiesV1>();

  @override
  int abiVersion() => _abiVersion();

  @override
  CryptoCoreNativeCapabilitiesSnapshot capabilities() {
    final output = calloc<_CpCryptoCapabilitiesV1>();
    try {
      final statusCode = _capabilities(
        output,
        CryptoCoreProtocolV1.capabilitiesStructSizeBytes,
      );
      final value = output.ref;
      return CryptoCoreNativeCapabilitiesSnapshot(
        statusCode: statusCode,
        structSize: value.structSize,
        abiVersion: value.abiVersion,
        featureBits: value.featureBits,
        maxInputBytes: value.maxInputBytes,
        maxCborDepth: value.maxCborDepth,
        maxCborItems: value.maxCborItems,
        reserved: value.reserved,
      );
    } finally {
      calloc.free(output);
    }
  }

  @override
  int selfTest() => _selfTest();

  @override
  String toString() => 'DynamicCryptoCoreNativeApi(<redacted>)';
}

import 'package:communication_platform/core/protocol/crypto_core_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/crypto_core_ffi.dart';

/// Synchronous native calls. Production invokes this session only in the
/// dedicated crypto isolate.
final class CryptoCoreNativeSession {
  const CryptoCoreNativeSession({required this.api});

  final CryptoCoreNativeApi api;

  Result<CryptoCoreCapabilities> capabilities() {
    if (api.capabilitiesStructSizeBytes !=
        CryptoCoreProtocolV1.capabilitiesStructSizeBytes) {
      return const Result<CryptoCoreCapabilities>.failure(
        SecurityFailure(SecurityFailureKind.malformedServerResponse),
      );
    }
    if (api.abiVersion() != CryptoCoreProtocolV1.abiVersion) {
      return const Result<CryptoCoreCapabilities>.failure(
        UnsupportedProtocolFailure(UnsupportedProtocolFailureKind.version),
      );
    }

    final snapshot = api.capabilities();
    if (snapshot.statusCode != 0) {
      return Result<CryptoCoreCapabilities>.failure(
        cryptoCoreFailureFromNativeStatus(snapshot.statusCode),
      );
    }
    if (snapshot.structSize !=
            CryptoCoreProtocolV1.capabilitiesStructSizeBytes ||
        snapshot.abiVersion != CryptoCoreProtocolV1.abiVersion ||
        snapshot.reserved != 0 ||
        snapshot.featureBits < 0 ||
        snapshot.maxInputBytes <= 0 ||
        snapshot.maxCborDepth <= 0 ||
        snapshot.maxCborItems <= 0) {
      return const Result<CryptoCoreCapabilities>.failure(
        SecurityFailure(SecurityFailureKind.malformedServerResponse),
      );
    }

    final capabilities = CryptoCoreCapabilities(
      abiVersion: snapshot.abiVersion,
      featureBits: snapshot.featureBits,
      maxInputBytes: snapshot.maxInputBytes,
      maxCborDepth: snapshot.maxCborDepth,
      maxCborItems: snapshot.maxCborItems,
    );
    if (!capabilities.supportsRequiredFoundation) {
      return const Result<CryptoCoreCapabilities>.failure(
        UnsupportedProtocolFailure(UnsupportedProtocolFailureKind.capability),
      );
    }
    return Result<CryptoCoreCapabilities>.success(capabilities);
  }

  Result<void> selfTest() {
    if (api.abiVersion() != CryptoCoreProtocolV1.abiVersion) {
      return const Result<void>.failure(
        UnsupportedProtocolFailure(UnsupportedProtocolFailureKind.version),
      );
    }
    final statusCode = api.selfTest();
    if (statusCode != 0) {
      return Result<void>.failure(
        cryptoCoreFailureFromNativeStatus(statusCode),
      );
    }
    return const Result<void>.success(null);
  }
}

Failure cryptoCoreFailureFromNativeStatus(int statusCode) {
  final code = CryptoCoreFailureCode.fromWireValue(statusCode);
  if (code == null) {
    return const SecurityFailure(SecurityFailureKind.policyBlocked);
  }
  return CryptoCoreFailure(code);
}

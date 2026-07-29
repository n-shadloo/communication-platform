import 'dart:convert';
import 'dart:typed_data';

import 'package:communication_platform/core/protocol/pairwise_crypto_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/enrollment_crypto_ffi.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/pairwise_crypto_ffi.dart';

final _requestMagic = Uint8List.fromList(ascii.encode('CPPWR001'));
final _responseMagic = Uint8List.fromList(ascii.encode('CPPWO001'));

/// Synchronous native pairwise calls. Production uses this only in the crypto isolate.
final class PairwiseCryptoNativeSession {
  const PairwiseCryptoNativeSession({required this.api});

  final PairwiseCryptoNativeApi api;

  Result<PairwiseCryptoResponse> operation(
    PairwiseCryptoOperation operation,
    Uint8List payload,
  ) {
    if (payload.length > 2 * 1024 * 1024 - _requestMagic.length) {
      return const Result.failure(
        CryptoCoreFailure(CryptoCoreFailureCode.inputTooLarge),
      );
    }
    final request = Uint8List(_requestMagic.length + payload.length)
      ..setRange(0, _requestMagic.length, _requestMagic)
      ..setRange(
        _requestMagic.length,
        _requestMagic.length + payload.length,
        payload,
      );
    final native = api.operation(operation.wireValue, request);
    request.fillRange(0, request.length, 0);
    if (native.statusCode != 0) {
      return Result.failure(
        enrollmentFailureFromNativeStatus(native.statusCode),
      );
    }
    final bytes = native.bytes;
    if (bytes == null ||
        bytes.length < 10 ||
        !_startsWith(bytes, _responseMagic)) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.malformedServerResponse),
      );
    }
    if (bytes[8] != operation.wireValue || bytes[9] > 1) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.malformedServerResponse),
      );
    }
    return Result.success(
      PairwiseCryptoResponse(
        operation: operation,
        outcome: PairwiseCryptoOutcome.values[bytes[9]],
        body: Uint8List.fromList(bytes.sublist(10)),
      ),
    );
  }
}

bool _startsWith(Uint8List value, Uint8List prefix) {
  if (value.length < prefix.length) {
    return false;
  }
  for (var index = 0; index < prefix.length; index += 1) {
    if (value[index] != prefix[index]) {
      return false;
    }
  }
  return true;
}

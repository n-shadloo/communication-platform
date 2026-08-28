import 'dart:ffi';
import 'dart:typed_data';

import 'package:communication_platform/shared/infrastructure/crypto/native/crypto_core_ffi.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/enrollment_crypto_ffi.dart';
import 'package:ffi/ffi.dart';

const _maximumPairwiseBufferBytes = 2 * 1024 * 1024;

typedef _PairwiseOperationNative =
    Int32 Function(
      Uint32,
      Pointer<Uint8>,
      UintPtr,
      Pointer<Uint8>,
      UintPtr,
      Pointer<UintPtr>,
    );
typedef _PairwiseOperationDart =
    int Function(
      int,
      Pointer<Uint8>,
      int,
      Pointer<Uint8>,
      int,
      Pointer<UintPtr>,
    );

abstract interface class PairwiseCryptoNativeApi {
  NativeBufferResult operation(int operation, Uint8List input);
}

final class DynamicPairwiseCryptoNativeApi implements PairwiseCryptoNativeApi {
  DynamicPairwiseCryptoNativeApi._(DynamicLibrary library)
    : _operation = library
          .lookupFunction<_PairwiseOperationNative, _PairwiseOperationDart>(
            'cp_crypto_v1_pairwise_operation',
          );

  factory DynamicPairwiseCryptoNativeApi.openAndroid() =>
      DynamicPairwiseCryptoNativeApi._(
        DynamicLibrary.open(cryptoCoreAndroidLibraryName),
      );

  final _PairwiseOperationDart _operation;

  @override
  NativeBufferResult operation(int operation, Uint8List input) {
    if (input.length > _maximumPairwiseBufferBytes) {
      return const NativeBufferResult(statusCode: 2);
    }
    final inputPointer = _copy(input);
    final output = calloc<Uint8>(_maximumPairwiseBufferBytes);
    final written = calloc<UintPtr>();
    try {
      final status = _operation(
        operation,
        inputPointer,
        input.length,
        output,
        _maximumPairwiseBufferBytes,
        written,
      );
      if (status != 0 || written.value > _maximumPairwiseBufferBytes) {
        return NativeBufferResult(statusCode: status == 0 ? 2 : status);
      }
      return NativeBufferResult(
        statusCode: 0,
        bytes: Uint8List.fromList(output.asTypedList(written.value)),
      );
    } finally {
      _clear(inputPointer, input.length);
      _clear(output, _maximumPairwiseBufferBytes);
      calloc.free(inputPointer);
      calloc.free(output);
      calloc.free(written);
    }
  }
}

Pointer<Uint8> _copy(Uint8List bytes) {
  final pointer = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
  if (bytes.isNotEmpty) {
    pointer.asTypedList(bytes.length).setAll(0, bytes);
  }
  return pointer;
}

void _clear(Pointer<Uint8> pointer, int length) {
  if (length > 0) {
    pointer.asTypedList(length).fillRange(0, length, 0);
  }
}

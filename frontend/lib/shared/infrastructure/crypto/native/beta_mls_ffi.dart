import 'dart:ffi';
import 'dart:typed_data';

import 'package:communication_platform/shared/infrastructure/crypto/native/crypto_core_ffi.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/enrollment_crypto_ffi.dart';
import 'package:ffi/ffi.dart';

const _maximumBetaMlsBufferBytes = 1024 * 1024;

typedef _BetaMlsOperationNative =
    Int32 Function(
      Uint32,
      Pointer<Uint8>,
      UintPtr,
      Pointer<Uint8>,
      UintPtr,
      Pointer<UintPtr>,
    );
typedef _BetaMlsOperationDart =
    int Function(
      int,
      Pointer<Uint8>,
      int,
      Pointer<Uint8>,
      int,
      Pointer<UintPtr>,
    );

abstract interface class BetaMlsNativeApi {
  NativeBufferResult operation(int operation, Uint8List input);
}

final class DynamicBetaMlsNativeApi implements BetaMlsNativeApi {
  DynamicBetaMlsNativeApi._(DynamicLibrary library)
    : _operation = library
          .lookupFunction<_BetaMlsOperationNative, _BetaMlsOperationDart>(
            'cp_crypto_v1_beta_mls_operation',
          );

  factory DynamicBetaMlsNativeApi.openAndroid() => DynamicBetaMlsNativeApi._(
    DynamicLibrary.open(cryptoCoreAndroidLibraryName),
  );

  final _BetaMlsOperationDart _operation;

  @override
  NativeBufferResult operation(int operation, Uint8List input) {
    if (input.length > _maximumBetaMlsBufferBytes) {
      return const NativeBufferResult(statusCode: 2);
    }
    final inputPointer = calloc<Uint8>(input.isEmpty ? 1 : input.length);
    final output = calloc<Uint8>(_maximumBetaMlsBufferBytes);
    final written = calloc<UintPtr>();
    try {
      if (input.isNotEmpty) {
        inputPointer.asTypedList(input.length).setAll(0, input);
      }
      final status = _operation(
        operation,
        inputPointer,
        input.length,
        output,
        _maximumBetaMlsBufferBytes,
        written,
      );
      if (status != 0 || written.value > _maximumBetaMlsBufferBytes) {
        return NativeBufferResult(statusCode: status == 0 ? 2 : status);
      }
      return NativeBufferResult(
        statusCode: 0,
        bytes: Uint8List.fromList(output.asTypedList(written.value)),
      );
    } finally {
      if (input.isNotEmpty) {
        inputPointer.asTypedList(input.length).fillRange(0, input.length, 0);
      }
      output
          .asTypedList(_maximumBetaMlsBufferBytes)
          .fillRange(0, _maximumBetaMlsBufferBytes, 0);
      calloc.free(inputPointer);
      calloc.free(output);
      calloc.free(written);
    }
  }
}

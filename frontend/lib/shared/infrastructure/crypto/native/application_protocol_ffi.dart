import 'dart:ffi';
import 'dart:typed_data';

import 'package:communication_platform/shared/infrastructure/crypto/native/crypto_core_ffi.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/enrollment_crypto_ffi.dart';
import 'package:ffi/ffi.dart';

const _maximumApplicationInputBytes = 262144;
const _maximumApplicationOutputBytes = 266240;

typedef _ApplicationOperationNative =
    Int32 Function(
      Uint32,
      Pointer<Uint8>,
      UintPtr,
      Pointer<Uint8>,
      UintPtr,
      Pointer<UintPtr>,
    );
typedef _ApplicationOperationDart =
    int Function(
      int,
      Pointer<Uint8>,
      int,
      Pointer<Uint8>,
      int,
      Pointer<UintPtr>,
    );

abstract interface class ApplicationProtocolNativeApi {
  NativeBufferResult operation(int operation, Uint8List input);
}

final class DynamicApplicationProtocolNativeApi
    implements ApplicationProtocolNativeApi {
  DynamicApplicationProtocolNativeApi._(DynamicLibrary library)
    : _operation = library
          .lookupFunction<
            _ApplicationOperationNative,
            _ApplicationOperationDart
          >('cp_crypto_v1_application_operation');

  factory DynamicApplicationProtocolNativeApi.openAndroid() =>
      DynamicApplicationProtocolNativeApi._(
        DynamicLibrary.open(cryptoCoreAndroidLibraryName),
      );

  final _ApplicationOperationDart _operation;

  @override
  NativeBufferResult operation(int operation, Uint8List input) {
    if (input.length > _maximumApplicationInputBytes) {
      return const NativeBufferResult(statusCode: 2);
    }
    final inputPointer = calloc<Uint8>(input.isEmpty ? 1 : input.length);
    final output = calloc<Uint8>(_maximumApplicationOutputBytes);
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
        _maximumApplicationOutputBytes,
        written,
      );
      if (status != 0 || written.value > _maximumApplicationOutputBytes) {
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
          .asTypedList(_maximumApplicationOutputBytes)
          .fillRange(0, _maximumApplicationOutputBytes, 0);
      calloc.free(inputPointer);
      calloc.free(output);
      calloc.free(written);
    }
  }
}

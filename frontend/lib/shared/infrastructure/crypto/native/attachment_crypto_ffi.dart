import 'dart:ffi';
import 'dart:typed_data';

import 'package:communication_platform/shared/infrastructure/crypto/native/crypto_core_ffi.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/enrollment_crypto_ffi.dart';
import 'package:ffi/ffi.dart';

const _maximumAttachmentInputBytes = 262144;
const _maximumAttachmentOutputBytes = 266240;

typedef _AttachmentOperationNative =
    Int32 Function(
      Uint32,
      Pointer<Uint8>,
      UintPtr,
      Pointer<Uint8>,
      UintPtr,
      Pointer<UintPtr>,
    );
typedef _AttachmentOperationDart =
    int Function(
      int,
      Pointer<Uint8>,
      int,
      Pointer<Uint8>,
      int,
      Pointer<UintPtr>,
    );

abstract interface class AttachmentCryptoNativeApi {
  NativeBufferResult operation(int operation, Uint8List input);
}

final class DynamicAttachmentCryptoNativeApi
    implements AttachmentCryptoNativeApi {
  DynamicAttachmentCryptoNativeApi._(DynamicLibrary library)
    : _operation = library
          .lookupFunction<_AttachmentOperationNative, _AttachmentOperationDart>(
            'cp_crypto_v1_attachment_operation',
          );

  factory DynamicAttachmentCryptoNativeApi.openAndroid() =>
      DynamicAttachmentCryptoNativeApi._(
        DynamicLibrary.open(cryptoCoreAndroidLibraryName),
      );

  final _AttachmentOperationDart _operation;

  @override
  NativeBufferResult operation(int operation, Uint8List input) {
    if (input.length > _maximumAttachmentInputBytes) {
      return const NativeBufferResult(statusCode: 2);
    }
    final inputPointer = calloc<Uint8>(input.isEmpty ? 1 : input.length);
    final output = calloc<Uint8>(_maximumAttachmentOutputBytes);
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
        _maximumAttachmentOutputBytes,
        written,
      );
      if (status != 0 || written.value > _maximumAttachmentOutputBytes) {
        return NativeBufferResult(statusCode: status == 0 ? 2 : status);
      }
      return NativeBufferResult(
        statusCode: 0,
        bytes: Uint8List.fromList(output.asTypedList(written.value)),
      );
    } finally {
      inputPointer
          .asTypedList(input.isEmpty ? 1 : input.length)
          .fillRange(0, input.isEmpty ? 1 : input.length, 0);
      output
          .asTypedList(_maximumAttachmentOutputBytes)
          .fillRange(0, _maximumAttachmentOutputBytes, 0);
      calloc.free(inputPointer);
      calloc.free(output);
      calloc.free(written);
    }
  }
}

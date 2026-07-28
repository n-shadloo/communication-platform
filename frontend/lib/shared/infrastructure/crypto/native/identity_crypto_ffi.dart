import 'dart:ffi';
import 'dart:typed_data';

import 'package:communication_platform/shared/infrastructure/crypto/native/crypto_core_ffi.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/enrollment_crypto_ffi.dart';
import 'package:ffi/ffi.dart';

typedef _IdentityOperationNative =
    Int32 Function(
      Uint32,
      Pointer<Uint8>,
      UintPtr,
      Pointer<Uint8>,
      UintPtr,
      Pointer<UintPtr>,
    );
typedef _IdentityOperationDart =
    int Function(
      int,
      Pointer<Uint8>,
      int,
      Pointer<Uint8>,
      int,
      Pointer<UintPtr>,
    );
typedef _AttestNative =
    Int32 Function(
      Pointer<Uint8>,
      UintPtr,
      Pointer<Uint8>,
      UintPtr,
      Pointer<Uint8>,
      UintPtr,
      Pointer<Uint8>,
      UintPtr,
      Pointer<UintPtr>,
    );
typedef _AttestDart =
    int Function(
      Pointer<Uint8>,
      int,
      Pointer<Uint8>,
      int,
      Pointer<Uint8>,
      int,
      Pointer<Uint8>,
      int,
      Pointer<UintPtr>,
    );

abstract interface class IdentityCryptoNativeApi {
  NativeBufferResult operation(int operation, Uint8List input);

  NativeBufferResult attest(
    Uint8List identityPackage,
    Uint8List peerUserId,
    Uint8List peerMasterPublic,
  );
}

final class DynamicIdentityCryptoNativeApi implements IdentityCryptoNativeApi {
  DynamicIdentityCryptoNativeApi._(DynamicLibrary library)
    : _operation = library
          .lookupFunction<_IdentityOperationNative, _IdentityOperationDart>(
            'cp_crypto_v1_identity_operation',
          ),
      _attest = library.lookupFunction<_AttestNative, _AttestDart>(
        'cp_crypto_v1_attest_peer_master',
      );

  factory DynamicIdentityCryptoNativeApi.openAndroid() =>
      DynamicIdentityCryptoNativeApi._(
        DynamicLibrary.open(cryptoCoreAndroidLibraryName),
      );

  final _IdentityOperationDart _operation;
  final _AttestDart _attest;

  @override
  NativeBufferResult operation(int operation, Uint8List input) {
    final inputPointer = _copy(input);
    final output = calloc<Uint8>(128);
    final written = calloc<UintPtr>();
    try {
      final status = _operation(
        operation,
        inputPointer,
        input.length,
        output,
        128,
        written,
      );
      if (status != 0 || written.value > 128) {
        return NativeBufferResult(statusCode: status == 0 ? 2 : status);
      }
      return NativeBufferResult(
        statusCode: 0,
        bytes: Uint8List.fromList(output.asTypedList(written.value)),
      );
    } finally {
      _clear(inputPointer, input.length);
      _clear(output, 128);
      calloc.free(inputPointer);
      calloc.free(output);
      calloc.free(written);
    }
  }

  @override
  NativeBufferResult attest(
    Uint8List identityPackage,
    Uint8List peerUserId,
    Uint8List peerMasterPublic,
  ) {
    final identityPointer = _copy(identityPackage);
    final userPointer = _copy(peerUserId);
    final masterPointer = _copy(peerMasterPublic);
    final output = calloc<Uint8>(64);
    final written = calloc<UintPtr>();
    try {
      final status = _attest(
        identityPointer,
        identityPackage.length,
        userPointer,
        peerUserId.length,
        masterPointer,
        peerMasterPublic.length,
        output,
        64,
        written,
      );
      if (status != 0 || written.value != 64) {
        return NativeBufferResult(statusCode: status == 0 ? 2 : status);
      }
      return NativeBufferResult(
        statusCode: 0,
        bytes: Uint8List.fromList(output.asTypedList(64)),
      );
    } finally {
      _clear(identityPointer, identityPackage.length);
      _clear(userPointer, peerUserId.length);
      _clear(masterPointer, peerMasterPublic.length);
      _clear(output, 64);
      calloc.free(identityPointer);
      calloc.free(userPointer);
      calloc.free(masterPointer);
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

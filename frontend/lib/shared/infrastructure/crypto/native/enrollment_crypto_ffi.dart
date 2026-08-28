import 'dart:ffi';
import 'dart:typed_data';

import 'package:communication_platform/core/protocol/enrollment_crypto_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/crypto_core_ffi.dart';
import 'package:ffi/ffi.dart';

typedef _PrepareNative =
    Int32 Function(
      Pointer<Uint8>,
      UintPtr,
      Pointer<Uint8>,
      UintPtr,
      Pointer<UintPtr>,
    );
typedef _PrepareDart =
    int Function(Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<UintPtr>);
typedef _RestoreNative =
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
typedef _RestoreDart =
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
typedef _CrossSignNative =
    Int32 Function(
      Pointer<Uint8>,
      UintPtr,
      Pointer<Uint8>,
      UintPtr,
      Pointer<Uint8>,
      UintPtr,
      Uint32,
      Pointer<Uint8>,
      UintPtr,
      Pointer<UintPtr>,
    );
typedef _CrossSignDart =
    int Function(
      Pointer<Uint8>,
      int,
      Pointer<Uint8>,
      int,
      Pointer<Uint8>,
      int,
      int,
      Pointer<Uint8>,
      int,
      Pointer<UintPtr>,
    );
typedef _LogNative =
    Int32 Function(
      Pointer<Uint8>,
      UintPtr,
      Pointer<Uint8>,
      UintPtr,
      Uint64,
      Pointer<Uint8>,
      UintPtr,
      Pointer<Uint8>,
      UintPtr,
      Uint32,
      Uint32,
      Pointer<Uint8>,
      UintPtr,
      Pointer<UintPtr>,
    );
typedef _LogDart =
    int Function(
      Pointer<Uint8>,
      int,
      Pointer<Uint8>,
      int,
      int,
      Pointer<Uint8>,
      int,
      Pointer<Uint8>,
      int,
      int,
      int,
      Pointer<Uint8>,
      int,
      Pointer<UintPtr>,
    );
typedef _InspectNative =
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
typedef _InspectDart =
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

abstract interface class EnrollmentCryptoNativeApi {
  NativeBufferResult prepareDevice(Uint8List userId);

  NativeBufferResult prepareFirstIdentity(Uint8List userId);

  NativeBufferResult restoreIdentity(
    Uint8List userId,
    Uint8List recoverySecret,
    Uint8List backup,
  );

  NativeBufferResult sanitizeIdentity(Uint8List package);

  NativeBufferResult rotateRecoverySecret(Uint8List package);

  NativeBufferResult crossSignDevice(
    Uint8List devicePackage,
    Uint8List identityPackage,
    Uint8List deviceId,
    int bundleVersion,
  );

  NativeBufferResult createDeviceLogRecord(
    Uint8List identityPackage,
    Uint8List userId,
    int sequence,
    Uint8List previousHash,
    Uint8List canonicalLiveSet,
    int identityVersion,
    int coarseUnixDay,
  );

  NativeBufferResult inspectDeviceLogRecord(
    Uint8List identityPackage,
    Uint8List userId,
    Uint8List record,
  );
}

final class NativeBufferResult {
  const NativeBufferResult({required this.statusCode, this.bytes});

  final int statusCode;
  final Uint8List? bytes;
}

final class DynamicEnrollmentCryptoNativeApi
    implements EnrollmentCryptoNativeApi {
  DynamicEnrollmentCryptoNativeApi._(DynamicLibrary library)
    : _prepareDevice = library.lookupFunction<_PrepareNative, _PrepareDart>(
        'cp_crypto_v1_prepare_device',
      ),
      _prepareFirstIdentity = library
          .lookupFunction<_PrepareNative, _PrepareDart>(
            'cp_crypto_v1_prepare_first_identity',
          ),
      _restoreIdentity = library.lookupFunction<_RestoreNative, _RestoreDart>(
        'cp_crypto_v1_restore_identity',
      ),
      _sanitizeIdentity = library.lookupFunction<_PrepareNative, _PrepareDart>(
        'cp_crypto_v1_sanitize_identity',
      ),
      _rotateRecoverySecret = library
          .lookupFunction<_PrepareNative, _PrepareDart>(
            'cp_crypto_v1_rotate_recovery_secret',
          ),
      _crossSignDevice = library
          .lookupFunction<_CrossSignNative, _CrossSignDart>(
            'cp_crypto_v1_cross_sign_device',
          ),
      _createDeviceLogRecord = library.lookupFunction<_LogNative, _LogDart>(
        'cp_crypto_v1_create_device_log_record',
      ),
      _inspectDeviceLogRecord = library
          .lookupFunction<_InspectNative, _InspectDart>(
            'cp_crypto_v1_inspect_device_log_record',
          );

  factory DynamicEnrollmentCryptoNativeApi.openAndroid() =>
      DynamicEnrollmentCryptoNativeApi._(
        DynamicLibrary.open(cryptoCoreAndroidLibraryName),
      );

  final _PrepareDart _prepareDevice;
  final _PrepareDart _prepareFirstIdentity;
  final _RestoreDart _restoreIdentity;
  final _PrepareDart _sanitizeIdentity;
  final _PrepareDart _rotateRecoverySecret;
  final _CrossSignDart _crossSignDevice;
  final _LogDart _createDeviceLogRecord;
  final _InspectDart _inspectDeviceLogRecord;

  @override
  NativeBufferResult prepareDevice(Uint8List userId) =>
      _invokePrepare(_prepareDevice, userId);

  @override
  NativeBufferResult prepareFirstIdentity(Uint8List userId) =>
      _invokePrepare(_prepareFirstIdentity, userId);

  @override
  NativeBufferResult restoreIdentity(
    Uint8List userId,
    Uint8List recoverySecret,
    Uint8List backup,
  ) => _invokeRestore(_restoreIdentity, userId, recoverySecret, backup);

  @override
  NativeBufferResult sanitizeIdentity(Uint8List package) =>
      _invokePrepare(_sanitizeIdentity, package);

  @override
  NativeBufferResult rotateRecoverySecret(Uint8List package) =>
      _invokePrepare(_rotateRecoverySecret, package);

  @override
  NativeBufferResult crossSignDevice(
    Uint8List devicePackage,
    Uint8List identityPackage,
    Uint8List deviceId,
    int bundleVersion,
  ) => _invokeCrossSign(
    _crossSignDevice,
    devicePackage,
    identityPackage,
    deviceId,
    bundleVersion,
  );

  @override
  NativeBufferResult createDeviceLogRecord(
    Uint8List identityPackage,
    Uint8List userId,
    int sequence,
    Uint8List previousHash,
    Uint8List canonicalLiveSet,
    int identityVersion,
    int coarseUnixDay,
  ) => _invokeLog(
    _createDeviceLogRecord,
    identityPackage,
    userId,
    sequence,
    previousHash,
    canonicalLiveSet,
    identityVersion,
    coarseUnixDay,
  );

  @override
  NativeBufferResult inspectDeviceLogRecord(
    Uint8List identityPackage,
    Uint8List userId,
    Uint8List record,
  ) => _invokeInspect(_inspectDeviceLogRecord, identityPackage, userId, record);
}

NativeBufferResult _invokePrepare(_PrepareDart operation, Uint8List input) {
  final inputPointer = _copyToNative(input);
  final output = calloc<Uint8>(1024 * 1024);
  final written = calloc<UintPtr>();
  try {
    final status = operation(
      inputPointer,
      input.length,
      output,
      1024 * 1024,
      written,
    );
    final length = written.value;
    if (status != 0) {
      return NativeBufferResult(statusCode: status);
    }
    if (length > 1024 * 1024) {
      return const NativeBufferResult(statusCode: 2);
    }
    return NativeBufferResult(
      statusCode: 0,
      bytes: Uint8List.fromList(output.asTypedList(length)),
    );
  } finally {
    _zeroNative(inputPointer, input.length);
    _zeroNative(output, 1024 * 1024);
    calloc.free(inputPointer);
    calloc.free(output);
    calloc.free(written);
  }
}

NativeBufferResult _invokeRestore(
  _RestoreDart operation,
  Uint8List userId,
  Uint8List recoverySecret,
  Uint8List backup,
) {
  final userPointer = _copyToNative(userId);
  final secretPointer = _copyToNative(recoverySecret);
  final backupPointer = _copyToNative(backup);
  final output = calloc<Uint8>(1024 * 1024);
  final written = calloc<UintPtr>();
  try {
    final status = operation(
      userPointer,
      userId.length,
      secretPointer,
      recoverySecret.length,
      backupPointer,
      backup.length,
      output,
      1024 * 1024,
      written,
    );
    if (status != 0) {
      return NativeBufferResult(statusCode: status);
    }
    final length = written.value;
    if (length > 1024 * 1024) {
      return const NativeBufferResult(statusCode: 2);
    }
    return NativeBufferResult(
      statusCode: 0,
      bytes: Uint8List.fromList(output.asTypedList(length)),
    );
  } finally {
    _zeroNative(userPointer, userId.length);
    _zeroNative(secretPointer, recoverySecret.length);
    _zeroNative(backupPointer, backup.length);
    _zeroNative(output, 1024 * 1024);
    calloc.free(userPointer);
    calloc.free(secretPointer);
    calloc.free(backupPointer);
    calloc.free(output);
    calloc.free(written);
  }
}

NativeBufferResult _invokeCrossSign(
  _CrossSignDart operation,
  Uint8List devicePackage,
  Uint8List identityPackage,
  Uint8List deviceId,
  int bundleVersion,
) {
  final devicePointer = _copyToNative(devicePackage);
  final identityPointer = _copyToNative(identityPackage);
  final deviceIdPointer = _copyToNative(deviceId);
  final output = calloc<Uint8>(64);
  final written = calloc<UintPtr>();
  try {
    final status = operation(
      devicePointer,
      devicePackage.length,
      identityPointer,
      identityPackage.length,
      deviceIdPointer,
      deviceId.length,
      bundleVersion,
      output,
      64,
      written,
    );
    if (status != 0) {
      return NativeBufferResult(statusCode: status);
    }
    if (written.value != 64) {
      return const NativeBufferResult(statusCode: 2);
    }
    return NativeBufferResult(
      statusCode: 0,
      bytes: Uint8List.fromList(output.asTypedList(written.value)),
    );
  } finally {
    _zeroNative(devicePointer, devicePackage.length);
    _zeroNative(identityPointer, identityPackage.length);
    _zeroNative(deviceIdPointer, deviceId.length);
    _zeroNative(output, 64);
    calloc.free(devicePointer);
    calloc.free(identityPointer);
    calloc.free(deviceIdPointer);
    calloc.free(output);
    calloc.free(written);
  }
}

NativeBufferResult _invokeLog(
  _LogDart operation,
  Uint8List identityPackage,
  Uint8List userId,
  int sequence,
  Uint8List previousHash,
  Uint8List canonicalLiveSet,
  int identityVersion,
  int coarseUnixDay,
) {
  final identityPointer = _copyToNative(identityPackage);
  final userPointer = _copyToNative(userId);
  final previousPointer = _copyToNative(previousHash);
  final liveSetPointer = _copyToNative(canonicalLiveSet);
  final output = calloc<Uint8>(enrollmentDeviceLogBucketBytes);
  final written = calloc<UintPtr>();
  try {
    final status = operation(
      identityPointer,
      identityPackage.length,
      userPointer,
      userId.length,
      sequence,
      previousPointer,
      previousHash.length,
      liveSetPointer,
      canonicalLiveSet.length,
      identityVersion,
      coarseUnixDay,
      output,
      enrollmentDeviceLogBucketBytes,
      written,
    );
    if (status != 0) {
      return NativeBufferResult(statusCode: status);
    }
    if (written.value != enrollmentDeviceLogBucketBytes) {
      return const NativeBufferResult(statusCode: 2);
    }
    return NativeBufferResult(
      statusCode: 0,
      bytes: Uint8List.fromList(output.asTypedList(written.value)),
    );
  } finally {
    _zeroNative(identityPointer, identityPackage.length);
    _zeroNative(userPointer, userId.length);
    _zeroNative(previousPointer, previousHash.length);
    _zeroNative(liveSetPointer, canonicalLiveSet.length);
    _zeroNative(output, enrollmentDeviceLogBucketBytes);
    calloc.free(identityPointer);
    calloc.free(userPointer);
    calloc.free(previousPointer);
    calloc.free(liveSetPointer);
    calloc.free(output);
    calloc.free(written);
  }
}

NativeBufferResult _invokeInspect(
  _InspectDart operation,
  Uint8List identityPackage,
  Uint8List userId,
  Uint8List record,
) {
  final identityPointer = _copyToNative(identityPackage);
  final userPointer = _copyToNative(userId);
  final recordPointer = _copyToNative(record);
  final output = calloc<Uint8>(72);
  final written = calloc<UintPtr>();
  try {
    final status = operation(
      identityPointer,
      identityPackage.length,
      userPointer,
      userId.length,
      recordPointer,
      record.length,
      output,
      72,
      written,
    );
    if (status != 0) {
      return NativeBufferResult(statusCode: status);
    }
    if (written.value != 72) {
      return const NativeBufferResult(statusCode: 2);
    }
    return NativeBufferResult(
      statusCode: 0,
      bytes: Uint8List.fromList(output.asTypedList(written.value)),
    );
  } finally {
    _zeroNative(identityPointer, identityPackage.length);
    _zeroNative(userPointer, userId.length);
    _zeroNative(recordPointer, record.length);
    _zeroNative(output, 72);
    calloc.free(identityPointer);
    calloc.free(userPointer);
    calloc.free(recordPointer);
    calloc.free(output);
    calloc.free(written);
  }
}

Pointer<Uint8> _copyToNative(Uint8List bytes) {
  final pointer = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
  if (bytes.isNotEmpty) {
    pointer.asTypedList(bytes.length).setAll(0, bytes);
  }
  return pointer;
}

void _zeroNative(Pointer<Uint8> pointer, int length) {
  if (length > 0) {
    pointer.asTypedList(length).fillRange(0, length, 0);
  }
}

Failure enrollmentFailureFromNativeStatus(int statusCode) {
  final code = CryptoCoreFailureCode.fromWireValue(statusCode);
  return code == null
      ? const SecurityFailure(SecurityFailureKind.policyBlocked)
      : CryptoCoreFailure(code);
}

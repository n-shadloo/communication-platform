import 'dart:typed_data';

import 'package:communication_platform/core/protocol/enrollment_crypto_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/enrollment_crypto_ffi.dart';

final class EnrollmentCryptoNativeSession {
  const EnrollmentCryptoNativeSession({required this.api});

  final EnrollmentCryptoNativeApi api;

  Result<DeviceKeyPackage> prepareDevice(Uint8List userId) =>
      _decode(api.prepareDevice(userId), DeviceKeyPackage.fromNative);

  Result<IdentityKeyPackage> prepareFirstIdentity(Uint8List userId) =>
      _decode(api.prepareFirstIdentity(userId), IdentityKeyPackage.fromNative);

  Result<IdentityKeyPackage> restoreIdentity(
    Uint8List userId,
    Uint8List recoverySecret,
    Uint8List backup,
  ) {
    try {
      return _decode(
        api.restoreIdentity(userId, recoverySecret, backup),
        IdentityKeyPackage.fromNative,
      );
    } finally {
      recoverySecret.fillRange(0, recoverySecret.length, 0);
    }
  }

  Result<IdentityKeyPackage> sanitizeIdentity(IdentityKeyPackage package) =>
      _decode(
        api.sanitizeIdentity(package.opaqueBytes),
        IdentityKeyPackage.fromNative,
      );

  Result<Uint8List> crossSignDevice(
    DeviceKeyPackage device,
    IdentityKeyPackage identity,
    Uint8List deviceId,
    int bundleVersion,
  ) => _decodeBytes(
    api.crossSignDevice(
      device.opaqueBytes,
      identity.opaqueBytes,
      deviceId,
      bundleVersion,
    ),
  );

  Result<Uint8List> createDeviceLogRecord({
    required IdentityKeyPackage identity,
    required Uint8List userId,
    required int sequence,
    required Uint8List previousHash,
    required Uint8List canonicalLiveSet,
    required int identityVersion,
    required int coarseUnixDay,
  }) => _decodeBytes(
    api.createDeviceLogRecord(
      identity.opaqueBytes,
      userId,
      sequence,
      previousHash,
      canonicalLiveSet,
      identityVersion,
      coarseUnixDay,
    ),
  );

  Result<DeviceLogInspection> inspectDeviceLogRecord({
    required IdentityKeyPackage identity,
    required Uint8List userId,
    required Uint8List record,
  }) => _decode(
    api.inspectDeviceLogRecord(identity.opaqueBytes, userId, record),
    DeviceLogInspection.fromNative,
  );

  Result<T> _decode<T>(
    NativeBufferResult result,
    T Function(Uint8List) decoder,
  ) {
    if (result.statusCode != 0) {
      return Result.failure(
        enrollmentFailureFromNativeStatus(result.statusCode),
      );
    }
    final bytes = result.bytes;
    if (bytes == null) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.malformedServerResponse),
      );
    }
    try {
      return Result.success(decoder(bytes));
    } on EnrollmentCryptoFormatException {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.malformedServerResponse),
      );
    } on Object {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.policyBlocked),
      );
    }
  }

  Result<Uint8List> _decodeBytes(NativeBufferResult result) {
    if (result.statusCode != 0) {
      return Result.failure(
        enrollmentFailureFromNativeStatus(result.statusCode),
      );
    }
    final bytes = result.bytes;
    if (bytes == null || bytes.isEmpty) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.malformedServerResponse),
      );
    }
    return Result.success(Uint8List.fromList(bytes));
  }
}

import 'dart:typed_data';

import 'package:communication_platform/core/application/ports/port.dart';
import 'package:communication_platform/core/protocol/enrollment_crypto_model.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/devices/domain/device_enrollment_model.dart';

abstract interface class DeviceEnrollmentRepository implements Port {
  Future<Result<DeviceRegistrationResponse>> registerDevice({
    required String userId,
    required DeviceRegistrationPublic public,
  });

  Future<Result<void>> publishIdentity({required PublishedIdentity identity});

  Future<Result<PublishedIdentity>> fetchIdentity({required String userId});

  Future<Result<void>> finishPrekeys({
    required String deviceId,
    required Uint8List crossSignature,
    required int bundleVersion,
  });

  Future<Result<KeyBackup>> fetchBackup();

  Future<Result<void>> uploadBackup({
    required Uint8List blob,
    required int version,
  });

  Future<Result<PublicDeviceList>> fetchPublicDevices({required String userId});

  Future<Result<DeviceLogPage>> fetchDeviceLog({
    required String userId,
    int? after,
  });

  Future<Result<DeviceLogAppendResult>> appendDeviceLog({
    required Uint8List record,
  });

  Future<Result<void>> revokeDevice({required String deviceId});
}

/// Atomic local commit boundary for an assigned device and full-scope tokens.
abstract interface class EnrollmentJournalStore implements Port {
  Future<Result<EnrollmentJournal?>> read({required String userId});

  Future<Result<void>> persistPrepared(EnrollmentJournal journal);

  Future<Result<void>> persistRegistrationResult({
    required EnrollmentJournal journal,
    required DeviceRegistrationResponse response,
  });

  Future<Result<void>> update(EnrollmentJournal journal);

  Future<Result<void>> clear({required String userId});

  Future<Result<void>> markNewAccount({required String userId});

  Future<Result<bool>> isNewAccount({required String userId});

  Future<Result<String?>> currentFullSessionDeviceId();

  Future<Result<IdentityKeyPackage?>> readCompletedIdentity();
}

import 'dart:typed_data';

import 'package:communication_platform/core/application/ports/port.dart';
import 'package:communication_platform/core/protocol/enrollment_crypto_model.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/devices/domain/linked_device_model.dart';

abstract interface class LinkedDeviceRemotePort implements Port {
  Future<Result<OwnDeviceRefresh>> fetchOwnDevices({String? etag});

  Future<Result<void>> relabelDevice({
    required String deviceId,
    required Uint8List encryptedLabel,
  });

  Future<Result<void>> revokeDevice({required String deviceId});
}

abstract interface class LinkedDeviceLocalPort implements RepositoryPort {
  Stream<List<LinkedDevice>> watchOwnDevices(String userId);

  Future<Result<List<LinkedDevice>>> readOwnDevices(String userId);

  Future<Result<String?>> readOwnDevicesEtag(String userId);

  Future<Result<void>> replaceOwnDevices({
    required String userId,
    required String etag,
    required List<LinkedDevice> devices,
  });

  Future<Result<void>> updateEncryptedLabel({
    required String deviceId,
    required String label,
    required Uint8List encryptedLabel,
  });

  Future<Result<void>> markMissingHistorySources(Set<String> liveDeviceIds);

  Future<Result<(String, String, IdentityKeyPackage)>> readLocalIdentity();

  Future<Result<GlobalSecurityState>> readGlobalSecurityState();

  Future<Result<void>> setGlobalSecurityState(
    GlobalSecurityState state, {
    DeviceLogEvidenceKind? evidence,
  });

  Future<Result<PendingDeviceLogMutation?>> readPendingMutation();

  Future<Result<AuthenticatedDeviceLogRecord?>> readAuthenticatedLogHead(
    String userId,
  );

  Future<Result<void>> appendAuthenticatedLogRecords({
    required String userId,
    required List<AuthenticatedDeviceLogRecord> records,
  });

  Future<Result<void>> writePendingMutation(PendingDeviceLogMutation mutation);

  Future<Result<void>> clearPendingMutation(String operationId);
}

abstract interface class SelfRevocationCleanupPort implements Port {
  Future<void> cleanupAfterSelfRevocation();
}

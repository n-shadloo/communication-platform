import 'dart:convert';
import 'dart:typed_data';

import 'package:communication_platform/core/protocol/beta_mls_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/groups/application/ports/group_key_package_ports.dart';
import 'package:communication_platform/features/groups/domain/group_key_package_model.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/drift_repository_base.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:drift/drift.dart';

final class DriftGroupKeyPackageMaintenanceStore extends DriftRepositoryBase
    implements GroupKeyPackageMaintenanceStore {
  const DriftGroupKeyPackageMaintenanceStore(super.database);

  static const _deviceStateSecretId = 'current-device-key-state-v1';
  static const _keyPackageStateSecretId = 'beta-pq-mls-key-packages-v1';
  static const _keyPackageSecretKind = 2;
  static const _keyPackageSecretFormat = 1;
  static const _idleStage = 0;

  @override
  Future<Result<GroupKeyPackageGenerationContext>> readGenerationContext({
    required String deviceId,
  }) async {
    final normalized = deviceId.toLowerCase();
    if (!_isUuid(normalized)) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    try {
      final device =
          await (database.select(database.devices)..where(
                (row) =>
                    row.deviceId.equals(normalized) &
                    row.isCurrentDevice.equals(true),
              ))
              .getSingleOrNull();
      final deviceSecret = await _secret(_deviceStateSecretId);
      final keyPackageSecret = await _secret(_keyPackageStateSecretId);
      final maintenance = await _maintenance(normalized);
      if (device == null ||
          deviceSecret == null ||
          deviceSecret.wrappedCiphertextOrOpaqueHandle.isEmpty ||
          deviceSecret.wrappedCiphertextOrOpaqueHandle.length > 1024 * 1024 ||
          (keyPackageSecret != null &&
              (keyPackageSecret.kind != _keyPackageSecretKind ||
                  keyPackageSecret.formatVersion != _keyPackageSecretFormat ||
                  keyPackageSecret.stateRevision <= 0 ||
                  keyPackageSecret.wrappedCiphertextOrOpaqueHandle.isEmpty ||
                  keyPackageSecret.wrappedCiphertextOrOpaqueHandle.length >
                      1024 * 1024)) ||
          (maintenance != null && maintenance.stage != _idleStage)) {
        throw const _KeyPackageIntegrity();
      }
      return Result.success(
        GroupKeyPackageGenerationContext(
          deviceId: normalized,
          opaqueDeviceState: deviceSecret.wrappedCiphertextOrOpaqueHandle,
          sealedKeyPackageState:
              keyPackageSecret?.wrappedCiphertextOrOpaqueHandle,
          keyPackageStateRevision: keyPackageSecret?.stateRevision ?? 0,
          lastResortUploaded: maintenance?.lastResortUploaded ?? false,
        ),
      );
    } on _KeyPackageIntegrity {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.integrityCheckFailed),
      );
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }

  @override
  Future<Result<GroupKeyPackagePreparedPlan?>> readPending({
    required String deviceId,
  }) async {
    final normalized = deviceId.toLowerCase();
    if (!_isUuid(normalized)) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    try {
      final row = await _maintenance(normalized);
      if (row == null || row.stage == _idleStage) {
        if (row != null &&
            (row.plannedKind != null || row.exactUploadProjection != null)) {
          throw const _KeyPackageIntegrity();
        }
        return const Result.success(null);
      }
      if (row.stage < 1 ||
          row.stage > GroupKeyPackagePlanStage.values.length ||
          row.plannedKind == null ||
          row.exactUploadProjection == null ||
          row.expectedStateRevision < 0) {
        throw const _KeyPackageIntegrity();
      }
      final secret = await _secret(_keyPackageStateSecretId);
      if (secret == null ||
          secret.kind != _keyPackageSecretKind ||
          secret.formatVersion != _keyPackageSecretFormat ||
          secret.stateRevision != row.expectedStateRevision + 1) {
        throw const _KeyPackageIntegrity();
      }
      final kind = MlsKeyPackageKind.values[row.plannedKind!];
      final upload = _decodeUpload(row.exactUploadProjection!, kind);
      return Result.success(
        GroupKeyPackagePreparedPlan(
          deviceId: normalized,
          expectedStateRevision: row.expectedStateRevision,
          nextSealedKeyPackageState: secret.wrappedCiphertextOrOpaqueHandle,
          upload: upload,
          stage: GroupKeyPackagePlanStage.values[row.stage - 1],
        ),
      );
    } on _KeyPackageIntegrity {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.integrityCheckFailed),
      );
    } on GroupKeyPackageFormatException {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.integrityCheckFailed),
      );
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }

  @override
  Future<Result<void>> persistPrepared(GroupKeyPackagePreparedPlan plan) async {
    if (!_validPlan(plan) || plan.stage != GroupKeyPackagePlanStage.prepared) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    try {
      await database.writeTransaction(() async {
        final existingState = await _secret(_keyPackageStateSecretId);
        final existingMaintenance = await _maintenance(plan.deviceId);
        if (existingMaintenance != null &&
            (existingMaintenance.stage != _idleStage ||
                existingMaintenance.plannedKind != null ||
                existingMaintenance.exactUploadProjection != null)) {
          throw const _KeyPackageConflict();
        }
        if (plan.expectedStateRevision == 0) {
          if (existingState != null) throw const _KeyPackageConflict();
          await database
              .into(database.secureSecrets)
              .insert(
                SecureSecretsCompanion.insert(
                  secretId: _keyPackageStateSecretId,
                  kind: _keyPackageSecretKind,
                  wrappedCiphertextOrOpaqueHandle:
                      plan.nextSealedKeyPackageState,
                  formatVersion: _keyPackageSecretFormat,
                  stateRevision: const Value(1),
                ),
              );
        } else {
          if (existingState == null ||
              existingState.kind != _keyPackageSecretKind ||
              existingState.formatVersion != _keyPackageSecretFormat ||
              existingState.stateRevision != plan.expectedStateRevision) {
            throw const _KeyPackageConflict();
          }
          final changed =
              await (database.update(database.secureSecrets)..where(
                    (row) =>
                        row.secretId.equals(_keyPackageStateSecretId) &
                        row.stateRevision.equals(plan.expectedStateRevision),
                  ))
                  .write(
                    SecureSecretsCompanion(
                      wrappedCiphertextOrOpaqueHandle: Value(
                        plan.nextSealedKeyPackageState,
                      ),
                      stateRevision: Value(plan.expectedStateRevision + 1),
                    ),
                  );
          if (changed != 1) throw const _KeyPackageConflict();
        }
        final companion = MlsKeyPackageMaintenanceStatesCompanion(
          deviceId: Value(plan.deviceId),
          stage: const Value(1),
          expectedStateRevision: Value(plan.expectedStateRevision),
          plannedKind: Value(plan.upload.kind.index),
          exactUploadProjection: Value(_encodeUpload(plan.upload)),
          lastResortUploaded: Value(
            existingMaintenance?.lastResortUploaded ?? false,
          ),
          updatedAt: Value(DateTime.now().toUtc()),
        );
        if (existingMaintenance == null) {
          await database
              .into(database.mlsKeyPackageMaintenanceStates)
              .insert(companion);
        } else {
          final changed =
              await (database.update(database.mlsKeyPackageMaintenanceStates)
                    ..where((row) => row.deviceId.equals(plan.deviceId)))
                  .write(companion);
          if (changed != 1) throw const _KeyPackageConflict();
        }
      });
      return const Result.success(null);
    } on _KeyPackageConflict {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.conflict),
      );
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }

  @override
  Future<Result<void>> moveStage({
    required GroupKeyPackagePreparedPlan plan,
    required GroupKeyPackagePlanStage nextStage,
  }) async {
    final allowed =
        (plan.stage == GroupKeyPackagePlanStage.prepared &&
            nextStage == GroupKeyPackagePlanStage.attemptStarted) ||
        (plan.stage == GroupKeyPackagePlanStage.attemptStarted &&
            (nextStage == GroupKeyPackagePlanStage.ambiguous ||
                nextStage == GroupKeyPackagePlanStage.prepared));
    if (!_validPlan(plan) || !allowed) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    try {
      final changed =
          await (database.update(database.mlsKeyPackageMaintenanceStates)
                ..where(
                  (row) =>
                      row.deviceId.equals(plan.deviceId) &
                      row.stage.equals(plan.stage.index + 1) &
                      row.expectedStateRevision.equals(
                        plan.expectedStateRevision,
                      ) &
                      row.plannedKind.equals(plan.upload.kind.index),
                ))
              .write(
                MlsKeyPackageMaintenanceStatesCompanion(
                  stage: Value(nextStage.index + 1),
                  updatedAt: Value(DateTime.now().toUtc()),
                ),
              );
      return changed == 1
          ? const Result.success(null)
          : const Result.failure(
              ValidationFailure(ValidationFailureKind.conflict),
            );
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }

  @override
  Future<Result<void>> complete(GroupKeyPackagePreparedPlan plan) async {
    final validStage = plan.upload.kind == MlsKeyPackageKind.consumable
        ? plan.stage == GroupKeyPackagePlanStage.attemptStarted
        : plan.stage == GroupKeyPackagePlanStage.prepared;
    if (!_validPlan(plan) || !validStage) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    try {
      final changed =
          await (database.update(database.mlsKeyPackageMaintenanceStates)
                ..where(
                  (row) =>
                      row.deviceId.equals(plan.deviceId) &
                      row.stage.equals(plan.stage.index + 1) &
                      row.expectedStateRevision.equals(
                        plan.expectedStateRevision,
                      ) &
                      row.plannedKind.equals(plan.upload.kind.index),
                ))
              .write(
                MlsKeyPackageMaintenanceStatesCompanion(
                  stage: const Value(_idleStage),
                  expectedStateRevision: const Value(0),
                  plannedKind: const Value(null),
                  exactUploadProjection: const Value(null),
                  lastResortUploaded:
                      plan.upload.kind == MlsKeyPackageKind.lastResort
                      ? const Value(true)
                      : const Value.absent(),
                  updatedAt: Value(DateTime.now().toUtc()),
                ),
              );
      return changed == 1
          ? const Result.success(null)
          : const Result.failure(
              ValidationFailure(ValidationFailureKind.conflict),
            );
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }

  Future<SecureSecret?> _secret(String id) => (database.select(
    database.secureSecrets,
  )..where((row) => row.secretId.equals(id))).getSingleOrNull();

  Future<StoredMlsKeyPackageMaintenanceState?> _maintenance(String deviceId) =>
      (database.select(
        database.mlsKeyPackageMaintenanceStates,
      )..where((row) => row.deviceId.equals(deviceId))).getSingleOrNull();
}

Uint8List _encodeUpload(GroupKeyPackageUpload upload) {
  final builder = BytesBuilder(copy: false)..add(ascii.encode('CPMKPU01'));
  final header = ByteData(4)
    ..setUint16(0, 1)
    ..setUint16(2, upload.wrappedKeyPackages.length);
  builder.add(header.buffer.asUint8List());
  for (final package in upload.wrappedKeyPackages) {
    final length = ByteData(4)..setUint32(0, package.length);
    builder
      ..add(length.buffer.asUint8List())
      ..add(package);
  }
  return builder.takeBytes();
}

GroupKeyPackageUpload _decodeUpload(Uint8List bytes, MlsKeyPackageKind kind) {
  if (bytes.length < 12 || bytes.length > 2 * 1024 * 1024) {
    throw const _KeyPackageIntegrity();
  }
  var offset = 0;
  Uint8List take(int length) {
    final end = offset + length;
    if (length < 0 || end < offset || end > bytes.length) {
      throw const _KeyPackageIntegrity();
    }
    final value = Uint8List.fromList(bytes.sublist(offset, end));
    offset = end;
    return value;
  }

  if (!_same(take(8), ascii.encode('CPMKPU01'))) {
    throw const _KeyPackageIntegrity();
  }
  final header = ByteData.sublistView(take(4));
  if (header.getUint16(0) != 1) throw const _KeyPackageIntegrity();
  final count = header.getUint16(2);
  if (count < 1 || count > 100) throw const _KeyPackageIntegrity();
  final packages = <Uint8List>[];
  for (var index = 0; index < count; index += 1) {
    final length = ByteData.sublistView(take(4)).getUint32(0);
    packages.add(take(length));
  }
  if (offset != bytes.length) throw const _KeyPackageIntegrity();
  return GroupKeyPackageUpload(kind: kind, wrappedKeyPackages: packages);
}

bool _validPlan(GroupKeyPackagePreparedPlan plan) =>
    _isUuid(plan.deviceId) &&
    plan.deviceId == plan.deviceId.toLowerCase() &&
    plan.expectedStateRevision >= 0 &&
    plan.nextSealedKeyPackageState.isNotEmpty &&
    plan.nextSealedKeyPackageState.length <= 1024 * 1024;

bool _isUuid(String value) => _uuid.hasMatch(value);

bool _same(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

final class _KeyPackageConflict implements Exception {
  const _KeyPackageConflict();
}

final class _KeyPackageIntegrity implements Exception {
  const _KeyPackageIntegrity();
}

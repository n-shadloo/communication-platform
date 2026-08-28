import 'dart:convert';
import 'dart:typed_data';

import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/devices/application/ports/prekey_maintenance_ports.dart';
import 'package:communication_platform/features/devices/domain/prekey_maintenance_model.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:drift/drift.dart';

/// Transactional owner of native prekey maintenance checkpoints.
///
/// The candidate native state is installed before upload, then held behind a
/// durable exact-retry plan. Initial receives reject while that plan exists, so
/// the final native commit can never resurrect a concurrently consumed OTPK.
final class DriftPrekeyMaintenanceStore implements PrekeyMaintenanceStore {
  const DriftPrekeyMaintenanceStore(this.database);

  static const String _deviceStateSecretId = 'current-device-key-state-v1';
  static const String _identityStateSecretId = 'current-identity-key-state-v1';

  static const int _classicalSignedKind = 0;
  static const int _classicalOneTimeKind = 1;
  static const int _pqSignedKind = 2;
  static const int _pqOneTimeKind = 3;
  static const int _uploadPrepared = 0;
  static const int _uploadAccepted = 1;
  static const int _useAvailable = 0;

  final LocalDatabase database;

  @override
  Future<Result<PrekeyMaintenancePlan?>> readPending({
    required String deviceId,
  }) async {
    if (!_isUuid(deviceId)) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    try {
      final row =
          await (database.select(database.prekeyMaintenancePlans)
                ..where((item) => item.deviceId.equals(deviceId.toLowerCase())))
              .getSingleOrNull();
      if (row == null) {
        return const Result.success(null);
      }
      final secret = await _deviceSecret();
      if (secret == null ||
          secret.stateRevision != row.expectedStateRevision + 1) {
        throw const _PrekeyIntegrity();
      }
      return Result.success(_decodePlan(row, secret));
    } on PrekeyMaintenanceFormatException {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.integrityCheckFailed),
      );
    } on _PrekeyIntegrity {
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
  Future<Result<PrekeyMaintenanceContext>> readContext({
    required String deviceId,
  }) async {
    if (!_isUuid(deviceId)) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    try {
      final normalized = deviceId.toLowerCase();
      final device = await (database.select(
        database.devices,
      )..where((row) => row.deviceId.equals(normalized))).getSingleOrNull();
      final deviceSecret = await _deviceSecret();
      final identitySecret =
          await (database.select(database.secureSecrets)
                ..where((row) => row.secretId.equals(_identityStateSecretId)))
              .getSingleOrNull();
      final bundleVersion = device?.bundleVersion;
      final rawUserId = device == null ? null : _uuidBytes(device.userId);
      if (device == null ||
          device.revocationState != 0 ||
          bundleVersion == null ||
          bundleVersion <= 0 ||
          device.lastSignedPrekeyRotationUnixDay < 0 ||
          deviceSecret == null ||
          deviceSecret.stateRevision <= 0 ||
          identitySecret == null ||
          rawUserId == null) {
        return const Result.failure(
          SecurityFailure(SecurityFailureKind.policyBlocked),
        );
      }
      return Result.success(
        PrekeyMaintenanceContext(
          deviceId: normalized,
          userId: rawUserId,
          rawDeviceId: _uuidBytes(normalized)!,
          opaqueDeviceState: deviceSecret.wrappedCiphertextOrOpaqueHandle,
          opaqueIdentityState: identitySecret.wrappedCiphertextOrOpaqueHandle,
          stateRevision: deviceSecret.stateRevision,
          bundleVersion: bundleVersion,
          lastSignedPrekeyRotationUnixDay:
              device.lastSignedPrekeyRotationUnixDay,
        ),
      );
    } on PrekeyMaintenanceFormatException {
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
  Future<Result<void>> persistPrepared(PrekeyMaintenancePlan plan) async {
    if (!_validPreparedPlan(plan)) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    try {
      await database.writeTransaction(() async {
        final existing =
            await (database.select(database.prekeyMaintenancePlans)..where(
                  (row) => row.deviceId.equals(plan.deviceId.toLowerCase()),
                ))
                .getSingleOrNull();
        if (existing != null) {
          final secret = await _deviceSecret();
          if (secret == null ||
              secret.stateRevision != plan.expectedStateRevision + 1 ||
              !_same(
                secret.wrappedCiphertextOrOpaqueHandle,
                plan.pendingDeviceState,
              ) ||
              !_samePlan(_decodePlan(existing, secret), plan)) {
            throw const _PrekeyConflict();
          }
          return;
        }

        final device =
            await (database.select(database.devices)..where(
                  (row) => row.deviceId.equals(plan.deviceId.toLowerCase()),
                ))
                .getSingleOrNull();
        final currentVersion = device?.bundleVersion;
        final rotation = plan.upload.rotation;
        if (device == null ||
            device.revocationState != 0 ||
            currentVersion == null ||
            (rotation == null
                ? plan.bundleVersion != currentVersion ||
                      plan.currentSignedPrekeyCreatedUnixDay !=
                          device.lastSignedPrekeyRotationUnixDay
                : plan.bundleVersion != currentVersion + 1 ||
                      plan.currentSignedPrekeyCreatedUnixDay !=
                          plan.preparedUnixDay)) {
          throw const _PrekeyConflict();
        }
        final updated =
            await (database.update(database.secureSecrets)..where(
                  (row) =>
                      row.secretId.equals(_deviceStateSecretId) &
                      row.stateRevision.equals(plan.expectedStateRevision),
                ))
                .write(
                  SecureSecretsCompanion(
                    wrappedCiphertextOrOpaqueHandle: Value(
                      plan.pendingDeviceState,
                    ),
                    formatVersion: const Value(2),
                    stateRevision: Value(plan.expectedStateRevision + 1),
                  ),
                );
        if (updated != 1) {
          throw const _PrekeyConflict();
        }
        await database
            .into(database.prekeyMaintenancePlans)
            .insert(
              PrekeyMaintenancePlansCompanion.insert(
                deviceId: plan.deviceId.toLowerCase(),
                stage: plan.stage.index,
                expectedStateRevision: plan.expectedStateRevision,
                preparedUnixDay: plan.preparedUnixDay,
                bundleVersion: plan.bundleVersion,
                currentSignedPrekeyCreatedUnixDay:
                    plan.currentSignedPrekeyCreatedUnixDay,
                batchId: plan.batchId,
                nativeUploadProjection: plan.nativeUploadProjection,
                exactLogRecord: const Value(null),
                expectedLogSequence: const Value(null),
                previousLogHead: const Value(null),
                updatedAt: Value(DateTime.now().toUtc()),
              ),
            );
        await _insertPreparedKeyRows(plan);
      });
      return const Result.success(null);
    } on _PrekeyConflict {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.conflict),
      );
    } on _PrekeyIntegrity {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.integrityCheckFailed),
      );
    } on PrekeyMaintenanceFormatException {
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
  Future<Result<void>> markUploadAccepted({
    required PrekeyMaintenancePlan plan,
  }) => _advancePlan(
    plan,
    expectedStoredStage: PrekeyMaintenanceStage.prepared,
    requirePreparedLog: false,
  );

  @override
  Future<Result<void>> persistRotationLogPrepared({
    required PrekeyMaintenancePlan plan,
  }) => _advancePlan(
    plan,
    expectedStoredStage:
        PrekeyMaintenanceStage.uploadAcceptedAwaitingDeviceLogPreparation,
    requirePreparedLog: true,
  );

  Future<Result<void>> _advancePlan(
    PrekeyMaintenancePlan plan, {
    required PrekeyMaintenanceStage expectedStoredStage,
    required bool requirePreparedLog,
  }) async {
    final log = plan.rotationDeviceLog;
    if (!plan.rotatesSignedPrekeys ||
        plan.stage.index != expectedStoredStage.index + 1 ||
        requirePreparedLog != (log != null)) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    try {
      await database.writeTransaction(() async {
        final row =
            await (database.select(database.prekeyMaintenancePlans)..where(
                  (item) => item.deviceId.equals(plan.deviceId.toLowerCase()),
                ))
                .getSingleOrNull();
        final secret = await _deviceSecret();
        if (row == null ||
            secret == null ||
            secret.stateRevision != plan.expectedStateRevision + 1 ||
            !_same(
              secret.wrappedCiphertextOrOpaqueHandle,
              plan.pendingDeviceState,
            )) {
          throw const _PrekeyConflict();
        }
        final stored = _decodePlan(row, secret);
        if (stored.stage == plan.stage) {
          if (!_samePlan(stored, plan)) {
            throw const _PrekeyConflict();
          }
          return;
        }
        if (stored.stage != expectedStoredStage ||
            !_samePlanImmutable(stored, plan)) {
          throw const _PrekeyConflict();
        }
        final updated =
            await (database.update(database.prekeyMaintenancePlans)..where(
                  (item) =>
                      item.deviceId.equals(plan.deviceId.toLowerCase()) &
                      item.stage.equals(expectedStoredStage.index),
                ))
                .write(
                  PrekeyMaintenancePlansCompanion(
                    stage: Value(plan.stage.index),
                    exactLogRecord: Value(log?.exactRecord),
                    expectedLogSequence: Value(log?.expectedSequence),
                    previousLogHead: Value(log?.previousHeadHash),
                    updatedAt: Value(DateTime.now().toUtc()),
                  ),
                );
        if (updated != 1) {
          throw const _PrekeyConflict();
        }
      });
      return const Result.success(null);
    } on _PrekeyConflict {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.conflict),
      );
    } on _PrekeyIntegrity {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.integrityCheckFailed),
      );
    } on PrekeyMaintenanceFormatException {
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
  Future<Result<void>> persistNativeSummary({
    required String deviceId,
    required int expectedStateRevision,
    required Uint8List nextDeviceState,
    required bool stateChanged,
    required int bundleVersion,
    required int currentSignedPrekeyCreatedUnixDay,
    required List<ErasedSignedPrekeyPair> erasedSignedPrekeys,
  }) async {
    if (!_isUuid(deviceId) ||
        expectedStateRevision <= 0 ||
        nextDeviceState.isEmpty ||
        nextDeviceState.length > 2 * 1024 * 1024 ||
        bundleVersion <= 0 ||
        currentSignedPrekeyCreatedUnixDay < 0 ||
        !_validErasedPairs(erasedSignedPrekeys) ||
        (!stateChanged && erasedSignedPrekeys.isNotEmpty)) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    try {
      await database.writeTransaction(() async {
        final normalized = deviceId.toLowerCase();
        if (await (database.select(database.prekeyMaintenancePlans)
                  ..where((row) => row.deviceId.equals(normalized)))
                .getSingleOrNull() !=
            null) {
          throw const _PrekeyConflict();
        }
        final secret = await _deviceSecret();
        final device = await (database.select(
          database.devices,
        )..where((row) => row.deviceId.equals(normalized))).getSingleOrNull();
        if (secret == null ||
            secret.stateRevision != expectedStateRevision ||
            device == null ||
            device.bundleVersion != bundleVersion ||
            (!stateChanged &&
                !_same(
                  secret.wrappedCiphertextOrOpaqueHandle,
                  nextDeviceState,
                ))) {
          throw const _PrekeyConflict();
        }
        if (stateChanged) {
          final updated =
              await (database.update(database.secureSecrets)..where(
                    (row) =>
                        row.secretId.equals(_deviceStateSecretId) &
                        row.stateRevision.equals(expectedStateRevision),
                  ))
                  .write(
                    SecureSecretsCompanion(
                      wrappedCiphertextOrOpaqueHandle: Value(nextDeviceState),
                      formatVersion: const Value(2),
                      stateRevision: Value(expectedStateRevision + 1),
                    ),
                  );
          if (updated != 1) {
            throw const _PrekeyConflict();
          }
        }
        final deviceUpdated =
            await (database.update(database.devices)..where(
                  (row) =>
                      row.deviceId.equals(normalized) &
                      row.bundleVersion.equals(bundleVersion),
                ))
                .write(
                  DevicesCompanion(
                    lastSignedPrekeyRotationUnixDay: Value(
                      currentSignedPrekeyCreatedUnixDay,
                    ),
                  ),
                );
        if (deviceUpdated != 1) {
          throw const _PrekeyConflict();
        }
        for (final erased in erasedSignedPrekeys) {
          await (database.delete(database.prekeys)..where(
                (row) =>
                    (row.kind.equals(_classicalSignedKind) &
                        row.keyId.equals(erased.classicalSignedPrekeyId)) |
                    (row.kind.equals(_pqSignedKind) &
                        row.keyId.equals(erased.pqSignedPrekeyId)),
              ))
              .go();
          await (database.delete(database.pairwiseReplayMarkers)..where(
                (row) =>
                    row.signedPrekeyId.equals(erased.classicalSignedPrekeyId) &
                    row.pqSignedPrekeyId.equals(erased.pqSignedPrekeyId),
              ))
              .go();
        }
      });
      return const Result.success(null);
    } on _PrekeyConflict {
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
  Future<Result<void>> complete({
    required PrekeyMaintenancePlan plan,
    required PrekeyCounts confirmedCounts,
    required PrekeyCommitResult committed,
  }) async {
    if (!_isUuid(plan.deviceId) ||
        committed.bundleVersion != plan.bundleVersion ||
        committed.currentSignedPrekeyCreatedUnixDay !=
            plan.currentSignedPrekeyCreatedUnixDay ||
        (plan.rotatesSignedPrekeys
            ? plan.stage != PrekeyMaintenanceStage.deviceLogPrepared
            : plan.stage != PrekeyMaintenanceStage.prepared)) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    try {
      await database.writeTransaction(() async {
        final row =
            await (database.select(database.prekeyMaintenancePlans)..where(
                  (item) => item.deviceId.equals(plan.deviceId.toLowerCase()),
                ))
                .getSingleOrNull();
        final secret = await _deviceSecret();
        if (row == null ||
            secret == null ||
            secret.stateRevision != plan.expectedStateRevision + 1 ||
            !_same(
              secret.wrappedCiphertextOrOpaqueHandle,
              plan.pendingDeviceState,
            ) ||
            !_samePlan(_decodePlan(row, secret), plan)) {
          throw const _PrekeyConflict();
        }
        final updated =
            await (database.update(database.secureSecrets)..where(
                  (item) =>
                      item.secretId.equals(_deviceStateSecretId) &
                      item.stateRevision.equals(plan.expectedStateRevision + 1),
                ))
                .write(
                  SecureSecretsCompanion(
                    wrappedCiphertextOrOpaqueHandle: Value(
                      committed.nextDeviceState,
                    ),
                    formatVersion: const Value(2),
                    stateRevision: Value(plan.expectedStateRevision + 2),
                  ),
                );
        if (updated != 1) {
          throw const _PrekeyConflict();
        }
        final deviceUpdated =
            await (database.update(database.devices)..where(
                  (item) => item.deviceId.equals(plan.deviceId.toLowerCase()),
                ))
                .write(
                  DevicesCompanion(
                    bundleVersion: Value(committed.bundleVersion),
                    lastSignedPrekeyRotationUnixDay: Value(
                      committed.currentSignedPrekeyCreatedUnixDay,
                    ),
                  ),
                );
        if (deviceUpdated != 1) {
          throw const _PrekeyConflict();
        }
        await (database.update(database.prekeys)
              ..where((row) => row.privateStateHandle.equals(plan.batchId)))
            .write(const PrekeysCompanion(uploadState: Value(_uploadAccepted)));
        final deleted =
            await (database.delete(database.prekeyMaintenancePlans)..where(
                  (item) =>
                      item.deviceId.equals(plan.deviceId.toLowerCase()) &
                      item.stage.equals(plan.stage.index),
                ))
                .go();
        if (deleted != 1) {
          throw const _PrekeyConflict();
        }
      });
      return const Result.success(null);
    } on _PrekeyConflict {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.conflict),
      );
    } on _PrekeyIntegrity {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.integrityCheckFailed),
      );
    } on PrekeyMaintenanceFormatException {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.integrityCheckFailed),
      );
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }

  Future<SecureSecret?> _deviceSecret() =>
      (database.select(database.secureSecrets)
            ..where((row) => row.secretId.equals(_deviceStateSecretId)))
          .getSingleOrNull();

  Future<void> _insertPreparedKeyRows(PrekeyMaintenancePlan plan) async {
    Future<void> insert(int kind, int keyId) => database
        .into(database.prekeys)
        .insert(
          PrekeysCompanion.insert(
            kind: kind,
            keyId: keyId,
            // Opaque reference to the native batch that owns the private key.
            privateStateHandle: plan.batchId,
            uploadState: _uploadPrepared,
            useState: _useAvailable,
          ),
        );
    for (final entry in plan.upload.classicalOneTimePrekeys) {
      await insert(_classicalOneTimeKind, entry.keyId);
    }
    for (final entry in plan.upload.pqOneTimePrekeys) {
      await insert(_pqOneTimeKind, entry.keyId);
    }
    final rotation = plan.upload.rotation;
    if (rotation != null) {
      await insert(_classicalSignedKind, rotation.classical.keyId);
      await insert(_pqSignedKind, rotation.postQuantum.keyId);
    }
  }

  PrekeyMaintenancePlan _decodePlan(
    StoredPrekeyMaintenancePlan row,
    SecureSecret secret,
  ) {
    if (row.stage < 0 ||
        row.stage >= PrekeyMaintenanceStage.values.length ||
        row.expectedStateRevision <= 0 ||
        row.preparedUnixDay < 0 ||
        row.bundleVersion <= 0 ||
        row.currentSignedPrekeyCreatedUnixDay < 0 ||
        row.currentSignedPrekeyCreatedUnixDay > row.preparedUnixDay ||
        row.batchId.length != 16 ||
        row.nativeUploadProjection.isEmpty ||
        row.nativeUploadProjection.length > 2 * 1024 * 1024) {
      throw const _PrekeyIntegrity();
    }
    final stage = PrekeyMaintenanceStage.values[row.stage];
    final hasRecord = row.exactLogRecord != null;
    if (hasRecord != (row.expectedLogSequence != null) ||
        hasRecord != (row.previousLogHead != null) ||
        hasRecord != (stage == PrekeyMaintenanceStage.deviceLogPrepared)) {
      throw const _PrekeyIntegrity();
    }
    final upload = _decodeProjection(
      row.nativeUploadProjection,
      expectedBatchId: row.batchId,
      expectedBundleVersion: row.bundleVersion,
    );
    if (stage != PrekeyMaintenanceStage.prepared && upload.rotation == null) {
      throw const _PrekeyIntegrity();
    }
    return PrekeyMaintenancePlan(
      deviceId: row.deviceId,
      expectedStateRevision: row.expectedStateRevision,
      preparedUnixDay: row.preparedUnixDay,
      bundleVersion: row.bundleVersion,
      currentSignedPrekeyCreatedUnixDay: row.currentSignedPrekeyCreatedUnixDay,
      batchId: row.batchId,
      nativeUploadProjection: row.nativeUploadProjection,
      pendingDeviceState: secret.wrappedCiphertextOrOpaqueHandle,
      upload: upload,
      stage: stage,
      rotationDeviceLog: hasRecord
          ? PreparedRotationDeviceLog(
              expectedSequence: row.expectedLogSequence!,
              previousHeadHash: row.previousLogHead!,
              exactRecord: row.exactLogRecord!,
            )
          : null,
    );
  }

  bool _validPreparedPlan(PrekeyMaintenancePlan plan) {
    if (!_isUuid(plan.deviceId) ||
        plan.deviceId != plan.deviceId.toLowerCase() ||
        plan.stage != PrekeyMaintenanceStage.prepared ||
        plan.rotationDeviceLog != null) {
      return false;
    }
    try {
      final decoded = _decodeProjection(
        plan.nativeUploadProjection,
        expectedBatchId: plan.batchId,
        expectedBundleVersion: plan.bundleVersion,
      );
      return _sameUpload(decoded, plan.upload);
    } on Object {
      return false;
    }
  }
}

PrekeyUploadProjection _decodeProjection(
  Uint8List bytes, {
  required Uint8List expectedBatchId,
  required int expectedBundleVersion,
}) {
  final reader = _ProjectionReader(bytes);
  if (!_same(reader.take(8), ascii.encode('CPKUV001')) ||
      !_same(reader.take(16), expectedBatchId)) {
    throw const PrekeyMaintenanceFormatException();
  }
  final kind = reader.u8();
  if (reader.u32() != expectedBundleVersion) {
    throw const PrekeyMaintenanceFormatException();
  }
  if (kind == 1) {
    final classical = <PrekeyUploadEntry>[];
    final classicalCount = reader.u16();
    if (classicalCount > PrekeyMaintenancePolicy.maximumClassicalPool) {
      throw const PrekeyMaintenanceFormatException();
    }
    var previous = -1;
    for (var index = 0; index < classicalCount; index += 1) {
      final keyId = reader.u32();
      if (keyId <= previous) {
        throw const PrekeyMaintenanceFormatException();
      }
      previous = keyId;
      classical.add(
        PrekeyUploadEntry.classical(keyId: keyId, publicKey: reader.take(32)),
      );
    }
    final pq = <PrekeyUploadEntry>[];
    final pqCount = reader.u16();
    if (pqCount > PrekeyMaintenancePolicy.maximumPqPool) {
      throw const PrekeyMaintenanceFormatException();
    }
    previous = -1;
    for (var index = 0; index < pqCount; index += 1) {
      final keyId = reader.u32();
      if (keyId <= previous) {
        throw const PrekeyMaintenanceFormatException();
      }
      previous = keyId;
      pq.add(
        PrekeyUploadEntry.postQuantum(
          keyId: keyId,
          publicKey: reader.take(1184),
        ),
      );
    }
    if (!reader.finished) {
      throw const PrekeyMaintenanceFormatException();
    }
    return PrekeyUploadProjection(
      classicalOneTimePrekeys: classical,
      pqOneTimePrekeys: pq,
    );
  }
  if (kind != 2) {
    throw const PrekeyMaintenanceFormatException();
  }
  final classical = SignedPrekeyUpload.classical(
    keyId: reader.u32(),
    publicKey: reader.take(32),
    signature: reader.take(64),
  );
  final pq = SignedPrekeyUpload.postQuantum(
    keyId: reader.u32(),
    publicKey: reader.take(1184),
    signature: reader.take(64),
  );
  final crossSignature = reader.take(64);
  if (!reader.finished) {
    throw const PrekeyMaintenanceFormatException();
  }
  return PrekeyUploadProjection(
    classicalOneTimePrekeys: const [],
    pqOneTimePrekeys: const [],
    rotation: SignedPrekeyRotationUpload(
      classical: classical,
      postQuantum: pq,
      crossSignature: crossSignature,
      bundleVersion: expectedBundleVersion,
    ),
  );
}

bool _samePlan(PrekeyMaintenancePlan left, PrekeyMaintenancePlan right) =>
    _samePlanImmutable(left, right) &&
    left.stage == right.stage &&
    _samePreparedLog(left.rotationDeviceLog, right.rotationDeviceLog);

bool _samePlanImmutable(
  PrekeyMaintenancePlan left,
  PrekeyMaintenancePlan right,
) =>
    left.deviceId == right.deviceId &&
    left.expectedStateRevision == right.expectedStateRevision &&
    left.preparedUnixDay == right.preparedUnixDay &&
    left.bundleVersion == right.bundleVersion &&
    left.currentSignedPrekeyCreatedUnixDay ==
        right.currentSignedPrekeyCreatedUnixDay &&
    _same(left.batchId, right.batchId) &&
    _same(left.nativeUploadProjection, right.nativeUploadProjection) &&
    _same(left.pendingDeviceState, right.pendingDeviceState) &&
    _sameUpload(left.upload, right.upload);

bool _sameUpload(PrekeyUploadProjection left, PrekeyUploadProjection right) {
  if (left.classicalOneTimePrekeys.length !=
          right.classicalOneTimePrekeys.length ||
      left.pqOneTimePrekeys.length != right.pqOneTimePrekeys.length ||
      !_sameRotation(left.rotation, right.rotation)) {
    return false;
  }
  for (var index = 0; index < left.classicalOneTimePrekeys.length; index += 1) {
    if (!_sameEntry(
      left.classicalOneTimePrekeys[index],
      right.classicalOneTimePrekeys[index],
    )) {
      return false;
    }
  }
  for (var index = 0; index < left.pqOneTimePrekeys.length; index += 1) {
    if (!_sameEntry(
      left.pqOneTimePrekeys[index],
      right.pqOneTimePrekeys[index],
    )) {
      return false;
    }
  }
  return true;
}

bool _sameEntry(PrekeyUploadEntry left, PrekeyUploadEntry right) =>
    left.keyId == right.keyId &&
    left.isPostQuantum == right.isPostQuantum &&
    _same(left.publicKey, right.publicKey);

bool _sameRotation(
  SignedPrekeyRotationUpload? left,
  SignedPrekeyRotationUpload? right,
) {
  if (left == null || right == null) {
    return left == right;
  }
  return left.bundleVersion == right.bundleVersion &&
      left.classical.keyId == right.classical.keyId &&
      _same(left.classical.publicKey, right.classical.publicKey) &&
      _same(left.classical.signature, right.classical.signature) &&
      left.postQuantum.keyId == right.postQuantum.keyId &&
      _same(left.postQuantum.publicKey, right.postQuantum.publicKey) &&
      _same(left.postQuantum.signature, right.postQuantum.signature) &&
      _same(left.crossSignature, right.crossSignature);
}

bool _samePreparedLog(
  PreparedRotationDeviceLog? left,
  PreparedRotationDeviceLog? right,
) {
  if (left == null || right == null) {
    return left == right;
  }
  return left.expectedSequence == right.expectedSequence &&
      _same(left.previousHeadHash, right.previousHeadHash) &&
      _same(left.exactRecord, right.exactRecord);
}

bool _validErasedPairs(List<ErasedSignedPrekeyPair> values) {
  final unique = <String>{};
  return values.every(
    (pair) =>
        pair.classicalSignedPrekeyId >= 0 &&
        pair.classicalSignedPrekeyId <= 0x7fffffff &&
        pair.pqSignedPrekeyId >= 0 &&
        pair.pqSignedPrekeyId <= 0x7fffffff &&
        unique.add('${pair.classicalSignedPrekeyId}:${pair.pqSignedPrekeyId}'),
  );
}

Uint8List? _uuidBytes(String value) {
  final compact = value.replaceAll('-', '');
  if (compact.length != 32 || !RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(compact)) {
    return null;
  }
  return Uint8List.fromList([
    for (var index = 0; index < 32; index += 2)
      int.parse(compact.substring(index, index + 2), radix: 16),
  ]);
}

bool _isUuid(String value) => _uuidBytes(value) != null;

bool _same(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  var difference = 0;
  for (var index = 0; index < left.length; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}

final class _ProjectionReader {
  _ProjectionReader(this.bytes);

  final Uint8List bytes;
  var offset = 0;

  bool get finished => offset == bytes.length;

  int u8() => take(1).first;

  int u16() => ByteData.sublistView(take(2)).getUint16(0);

  int u32() => ByteData.sublistView(take(4)).getUint32(0);

  Uint8List take(int length) {
    final end = offset + length;
    if (length < 0 || end < offset || end > bytes.length) {
      throw const PrekeyMaintenanceFormatException();
    }
    final value = Uint8List.fromList(bytes.sublist(offset, end));
    offset = end;
    return value;
  }
}

final class _PrekeyConflict implements Exception {
  const _PrekeyConflict();
}

final class _PrekeyIntegrity implements Exception {
  const _PrekeyIntegrity();
}

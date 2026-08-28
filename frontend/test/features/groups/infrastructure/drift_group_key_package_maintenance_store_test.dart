import 'package:communication_platform/core/protocol/beta_mls_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/groups/domain/group_key_package_model.dart';
import 'package:communication_platform/features/groups/infrastructure/drift_group_key_package_maintenance_store.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LocalDatabase database;
  late DriftGroupKeyPackageMaintenanceStore store;

  setUp(() async {
    database = LocalDatabase(NativeDatabase.memory());
    store = DriftGroupKeyPackageMaintenanceStore(database);
    await database
        .into(database.users)
        .insert(
          UsersCompanion.insert(
            userId: _userId,
            activated: true,
            directoryEntryCiphertext: _bytes(8, 1),
            localState: 0,
          ),
        );
    await database
        .into(database.devices)
        .insert(
          DevicesCompanion.insert(
            deviceId: _deviceId,
            userId: _userId,
            publicBundle: _bytes(8, 2),
            revocationState: 0,
            isCurrentDevice: const Value(true),
          ),
        );
    await database
        .into(database.secureSecrets)
        .insert(
          SecureSecretsCompanion.insert(
            secretId: 'current-device-key-state-v1',
            kind: 0,
            wrappedCiphertextOrOpaqueHandle: _bytes(128, 3),
            formatVersion: 2,
          ),
        );
  });

  tearDown(() => database.close());

  test('persists sealed state and exact last-resort plan atomically', () async {
    final context = await store.readGenerationContext(deviceId: _deviceId);
    expect(context, isA<Success<GroupKeyPackageGenerationContext>>());
    expect(
      (context as Success<GroupKeyPackageGenerationContext>)
          .value
          .keyPackageStateRevision,
      0,
    );
    final plan = _plan(
      kind: MlsKeyPackageKind.lastResort,
      expectedRevision: 0,
      stateValue: 4,
      packageValue: 5,
    );

    final persisted = await store.persistPrepared(plan);
    final restartedStore = DriftGroupKeyPackageMaintenanceStore(database);
    final pending = await restartedStore.readPending(deviceId: _deviceId);

    expect(persisted, isA<Success<void>>());
    expect(pending, isA<Success<GroupKeyPackagePreparedPlan?>>());
    final restored = (pending as Success<GroupKeyPackagePreparedPlan?>).value!;
    expect(restored.upload.kind, MlsKeyPackageKind.lastResort);
    expect(
      restored.upload.wrappedKeyPackages.single,
      orderedEquals(plan.upload.wrappedKeyPackages.single),
    );
    expect(
      restored.nextSealedKeyPackageState,
      orderedEquals(plan.nextSealedKeyPackageState),
    );

    final completed = await restartedStore.complete(restored);
    final nextContext = await restartedStore.readGenerationContext(
      deviceId: _deviceId,
    );
    expect(completed, isA<Success<void>>());
    expect(
      (nextContext as Success<GroupKeyPackageGenerationContext>)
          .value
          .lastResortUploaded,
      isTrue,
    );
  });

  test('transaction failure rolls back the next sealed secret state', () async {
    final initial = _plan(
      kind: MlsKeyPackageKind.lastResort,
      expectedRevision: 0,
      stateValue: 6,
      packageValue: 7,
    );
    expect(await store.persistPrepared(initial), isA<Success<void>>());
    expect(await store.complete(initial), isA<Success<void>>());
    await database.customStatement('''
      CREATE TRIGGER reject_mls_plan_update
      BEFORE UPDATE ON mls_key_package_maintenance_states
      WHEN NEW.stage = 1
      BEGIN
        SELECT RAISE(ABORT, 'injected');
      END
    ''');
    final replacement = _plan(
      kind: MlsKeyPackageKind.consumable,
      expectedRevision: 1,
      stateValue: 8,
      packageValue: 9,
    );

    final result = await store.persistPrepared(replacement);
    final secret =
        await (database.select(database.secureSecrets)..where(
              (row) => row.secretId.equals('beta-pq-mls-key-packages-v1'),
            ))
            .getSingle();
    final row = await database
        .select(database.mlsKeyPackageMaintenanceStates)
        .getSingle();

    expect(result, isA<FailureResult<void>>());
    expect((result as FailureResult<void>).failure, isA<StorageFailure>());
    expect(secret.stateRevision, 1);
    expect(
      secret.wrappedCiphertextOrOpaqueHandle,
      orderedEquals(_bytes(64, 6)),
    );
    expect(row.stage, 0);
    expect(row.plannedKind, isNull);
    expect(row.exactUploadProjection, isNull);
  });

  test('compare-and-swap conflict exposes no prepared plan', () async {
    final stale = _plan(
      kind: MlsKeyPackageKind.consumable,
      expectedRevision: 1,
      stateValue: 10,
      packageValue: 11,
    );

    final result = await store.persistPrepared(stale);
    final pending = await store.readPending(deviceId: _deviceId);

    expect(result, isA<FailureResult<void>>());
    expect(
      (result as FailureResult<void>).failure,
      isA<ValidationFailure>().having(
        (failure) => failure.kind,
        'kind',
        ValidationFailureKind.conflict,
      ),
    );
    expect((pending as Success<GroupKeyPackagePreparedPlan?>).value, isNull);
    expect(
      await (database.select(
            database.secureSecrets,
          )..where((row) => row.secretId.equals('beta-pq-mls-key-packages-v1')))
          .getSingleOrNull(),
      isNull,
    );
  });
}

const _userId = '10000000-0000-4000-8000-000000000001';
const _deviceId = '20000000-0000-4000-8000-000000000002';

GroupKeyPackagePreparedPlan _plan({
  required MlsKeyPackageKind kind,
  required int expectedRevision,
  required int stateValue,
  required int packageValue,
}) => GroupKeyPackagePreparedPlan(
  deviceId: _deviceId,
  expectedStateRevision: expectedRevision,
  nextSealedKeyPackageState: _bytes(64, stateValue),
  upload: GroupKeyPackageUpload(
    kind: kind,
    wrappedKeyPackages: [_bytes(4096, packageValue)],
  ),
);

Uint8List _bytes(int length, int value) =>
    Uint8List(length)..fillRange(0, length, value & 0xff);

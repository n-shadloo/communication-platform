import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/devices/application/ports/recovery_rotation_ports.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:drift/drift.dart';

/// The backup version, in the row enrollment already writes it to.
///
/// Deliberately not a new table and not a new preference key: `account_identity`
/// is where this account's verified identity state lives, the enrollment
/// completion already sets `backup_version` there, and a second place to record
/// the same number is a second place for it to be wrong.
final class DriftRecoveryBackupVersionStore
    implements RecoveryBackupVersionStore {
  const DriftRecoveryBackupVersionStore(this.database);

  final LocalDatabase database;

  @override
  Future<Result<int>> readBackupVersion() async {
    try {
      final row = await database
          .select(database.accountIdentities)
          .getSingleOrNull();
      if (row == null) {
        return const Result.failure(
          StorageFailure(StorageFailureKind.unavailable),
        );
      }
      return Result.success(row.backupVersion);
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }

  @override
  Future<Result<void>> recordBackupVersion(int version) async {
    try {
      await database.writeTransaction<void>(() async {
        final row = await database
            .select(database.accountIdentities)
            .getSingleOrNull();
        if (row == null || row.backupVersion >= version) {
          // Never lowered. A concurrent rotation from this device's other
          // isolate may already have recorded a higher one, and the server's
          // strictly-increasing rule means the higher number is the true one.
          return;
        }
        await (database.update(database.accountIdentities)
              ..where((entry) => entry.singletonId.equals(row.singletonId)))
            .write(AccountIdentitiesCompanion(backupVersion: Value(version)));
      });
      return const Result.success(null);
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }
}

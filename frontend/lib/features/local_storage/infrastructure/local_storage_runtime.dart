import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/local_storage/application/ports/local_storage_ports.dart';
import 'package:communication_platform/features/local_storage/domain/local_storage_model.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:drift/drift.dart';

typedef LocalDatabaseExecutorFactory =
    QueryExecutor Function(PlatformStorageUnlock unlock);

/// Owns the database handle and the order-sensitive cryptographic wipe flow.
final class SecureLocalStorageRuntime {
  factory SecureLocalStorageRuntime({
    required PlatformProtectedStoragePort protectedStorage,
    required LocalArtifactCleanupPort cleanup,
    required LocalDatabaseExecutorFactory executorFactory,
  }) => SecureLocalStorageRuntime._(protectedStorage, cleanup, executorFactory);

  SecureLocalStorageRuntime._(
    this._protectedStorage,
    this._cleanup,
    this._executorFactory,
  );

  final PlatformProtectedStoragePort _protectedStorage;
  final LocalArtifactCleanupPort _cleanup;
  final LocalDatabaseExecutorFactory _executorFactory;
  LocalDatabase? _database;
  Future<Result<LocalDatabase>>? _openInFlight;

  LocalDatabase? get openedDatabase => _database;

  Future<Result<LocalDatabase>> open() async {
    final existing = _database;
    if (existing != null) {
      return Result.success(existing);
    }
    final inFlight = _openInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final opening = _open();
    _openInFlight = opening;
    return opening.whenComplete(() {
      if (identical(_openInFlight, opening)) {
        _openInFlight = null;
      }
    });
  }

  Future<Result<LocalDatabase>> _open() async {
    final unlock = await _protectedStorage.loadOrCreateStorageKey();
    switch (unlock.status) {
      case PlatformStorageKeyStatus.ready:
        break;
      case PlatformStorageKeyStatus.wrappingKeyLost:
        await wipe(LocalWipeReason.wrappingKeyLoss);
        return const Result.failure(
          SecurityFailure(SecurityFailureKind.integrityCheckFailed),
        );
      case PlatformStorageKeyStatus.integrityFailure:
        await wipe(LocalWipeReason.authenticatedStorageTamper);
        return const Result.failure(
          SecurityFailure(SecurityFailureKind.integrityCheckFailed),
        );
      case PlatformStorageKeyStatus.unavailable:
        return const Result.failure(
          StorageFailure(StorageFailureKind.unavailable),
        );
    }

    final database = LocalDatabase(_executorFactory(unlock));
    try {
      await database.customSelect('SELECT 1').getSingle();
      _database = database;
      return Result.success(database);
    } on LocalDatabaseIntegrityException {
      await database.close();
      await wipe(LocalWipeReason.authenticatedStorageTamper);
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.integrityCheckFailed),
      );
    } on Object {
      await database.close();
      return const Result.failure(
        StorageFailure(StorageFailureKind.migrationBlocked),
      );
    }
  }

  Future<CleanupReport> cleanupBounded({required int maximumEntries}) async {
    final database = _database;
    var databaseRemoved = 0;
    var databaseHasMore = false;
    if (database != null) {
      final report = await database.cleanupBounded(
        maximumEntries: maximumEntries,
      );
      databaseRemoved = report.removedEntries;
      databaseHasMore = report.hasMore;
    }
    final artifactBudget = (maximumEntries - databaseRemoved).clamp(
      0,
      maximumEntries,
    );
    final artifactReport = await _cleanup.cleanupBounded(
      maximumEntries: artifactBudget,
    );
    return CleanupReport(
      removedEntries: databaseRemoved + artifactReport.removedEntries,
      hasMore: databaseHasMore || artifactReport.hasMore,
    );
  }

  Future<void> close() async {
    final database = _database;
    _database = null;
    await database?.close();
    await _cleanup.clearVolatilePlaintext();
  }

  Future<void> wipe(LocalWipeReason reason) async {
    // The documented erasure boundary is deliberately order-sensitive: close
    // handles, destroy the wrapping key, then remove persistent artifacts.
    await close();
    await _protectedStorage.destroyWrappingKey();
    await _cleanup.erasePersistentArtifacts();
  }

  Future<void> wipeForLogout() => wipe(LocalWipeReason.logout);

  Future<void> wipeForSelfRevocation() => wipe(LocalWipeReason.selfRevocation);

  Future<void> wipeForRemoteRevocation() =>
      wipe(LocalWipeReason.remoteRevocation);
}

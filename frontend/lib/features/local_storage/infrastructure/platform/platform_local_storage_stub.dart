import 'package:communication_platform/features/local_storage/application/ports/local_storage_ports.dart';
import 'package:communication_platform/features/local_storage/domain/local_storage_model.dart';
import 'package:communication_platform/features/local_storage/infrastructure/local_storage_runtime.dart';
import 'package:drift/drift.dart';

SecureLocalStorageRuntime createPlatformLocalStorageRuntime() {
  return SecureLocalStorageRuntime(
    protectedStorage: const _UnsupportedProtectedStorage(),
    cleanup: const _UnsupportedCleanup(),
    executorFactory: _unsupportedExecutor,
  );
}

QueryExecutor _unsupportedExecutor(PlatformStorageUnlock unlock) {
  throw UnsupportedError(
    'Secure local storage is only available on Android and Web.',
  );
}

final class _UnsupportedProtectedStorage
    implements PlatformProtectedStoragePort {
  const _UnsupportedProtectedStorage();

  @override
  Future<void> destroyWrappingKey() async {}

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<PlatformStorageUnlock> loadOrCreateStorageKey() async {
    return PlatformStorageUnlock(
      status: PlatformStorageKeyStatus.unavailable,
      protection: PlatformStorageProtection.unknown,
    );
  }
}

final class _UnsupportedCleanup implements LocalArtifactCleanupPort {
  const _UnsupportedCleanup();

  @override
  Future<void> clearVolatilePlaintext() async {}

  @override
  Future<CleanupReport> cleanupBounded({required int maximumEntries}) async {
    return const CleanupReport(removedEntries: 0, hasMore: false);
  }

  @override
  Future<void> erasePersistentArtifacts() async {}
}

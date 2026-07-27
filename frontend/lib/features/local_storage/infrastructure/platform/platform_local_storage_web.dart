import 'dart:js_interop';

import 'package:communication_platform/features/local_storage/application/ports/local_storage_ports.dart';
import 'package:communication_platform/features/local_storage/domain/local_storage_model.dart';
import 'package:communication_platform/features/local_storage/infrastructure/local_storage_runtime.dart';
import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:drift_flutter/drift_flutter.dart';

const _databaseName = 'communication_platform_secure_local';
final _sqliteUri = Uri.parse('sqlite3.wasm');
final _workerUri = Uri.parse('drift_worker.js');

@JS('communicationStorage.probe')
external JSPromise<JSString> _probeProtectedStorage();

@JS('communicationStorage.loadOrCreate')
external JSPromise<JSString> _loadOrCreateProtectedStorage();

@JS('communicationStorage.wipe')
external JSPromise<JSString> _wipeProtectedStorage();

@JS('communicationStorage.clearVolatile')
external void _clearVolatileStorage();

SecureLocalStorageRuntime createPlatformLocalStorageRuntime() {
  return SecureLocalStorageRuntime(
    protectedStorage: const WebCryptoProtectedStorage(),
    cleanup: const WebLocalArtifactCleanup(),
    executorFactory: _openWebCiphertextDatabase,
  );
}

QueryExecutor _openWebCiphertextDatabase(PlatformStorageUnlock unlock) {
  return driftDatabase(
    name: _databaseName,
    web: DriftWebOptions(
      sqlite3Wasm: _sqliteUri,
      driftWorker: _workerUri,
      onResult: (result) {
        if (result.chosenImplementation == WasmStorageImplementation.inMemory ||
            result.chosenImplementation ==
                WasmStorageImplementation.unsafeIndexedDb) {
          throw StateError(
            'Browser persistence cannot safely own this device.',
          );
        }
      },
    ),
  );
}

Future<String> _call(JSPromise<JSString> promise) async {
  return (await promise.toDart).toDart;
}

final class WebCryptoProtectedStorage implements PlatformProtectedStoragePort {
  const WebCryptoProtectedStorage();

  @override
  Future<bool> isAvailable() async {
    try {
      return await _call(_probeProtectedStorage()) == 'available';
    } on Object {
      return false;
    }
  }

  @override
  Future<PlatformStorageUnlock> loadOrCreateStorageKey() async {
    try {
      final result = await _call(_loadOrCreateProtectedStorage());
      final status = switch (result) {
        'ready' => PlatformStorageKeyStatus.ready,
        'key_lost' => PlatformStorageKeyStatus.wrappingKeyLost,
        'integrity_failure' => PlatformStorageKeyStatus.integrityFailure,
        _ => PlatformStorageKeyStatus.unavailable,
      };
      return PlatformStorageUnlock(
        status: status,
        protection: PlatformStorageProtection.browser,
      );
    } on Object {
      return PlatformStorageUnlock(
        status: PlatformStorageKeyStatus.unavailable,
        protection: PlatformStorageProtection.browser,
      );
    }
  }

  @override
  Future<void> destroyWrappingKey() async {
    await _call(_wipeProtectedStorage());
  }
}

final class WebLocalArtifactCleanup implements LocalArtifactCleanupPort {
  const WebLocalArtifactCleanup();

  @override
  Future<CleanupReport> cleanupBounded({required int maximumEntries}) async {
    return const CleanupReport(removedEntries: 0, hasMore: false);
  }

  @override
  Future<void> erasePersistentArtifacts() async {
    final probe = await WasmDatabase.probe(
      sqlite3Uri: _sqliteUri,
      driftWorkerUri: _workerUri,
      databaseName: _databaseName,
    );
    for (final database in probe.existingDatabases.where(
      (candidate) => candidate.$2 == _databaseName,
    )) {
      await probe.deleteDatabase(database);
    }
  }

  @override
  Future<void> clearVolatilePlaintext() async {
    _clearVolatileStorage();
  }
}

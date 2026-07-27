import 'package:communication_platform/features/local_storage/application/ports/local_storage_ports.dart';
import 'package:communication_platform/features/local_storage/domain/local_storage_model.dart';
import 'package:communication_platform/features/local_storage/infrastructure/local_storage_runtime.dart';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/services.dart';
import 'package:sqlite3/common.dart';

const _databaseName = 'communication_platform_secure_local';
const _channel = MethodChannel('communication_platform/protected_storage');

SecureLocalStorageRuntime createPlatformLocalStorageRuntime() {
  return SecureLocalStorageRuntime(
    protectedStorage: const AndroidKeystoreProtectedStorage(),
    cleanup: const AndroidLocalArtifactCleanup(),
    executorFactory: _openEncryptedNativeDatabase,
  );
}

QueryExecutor _openEncryptedNativeDatabase(PlatformStorageUnlock unlock) {
  final key = unlock.databaseKey;
  if (key == null || key.length != 32) {
    throw StateError('Android SQLCipher requires a 256-bit database key.');
  }
  final keyHex = key
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return driftDatabase(
    name: _databaseName,
    native: DriftNativeOptions(
      shareAcrossIsolates: true,
      setup: (CommonDatabase database) {
        database
          ..execute('PRAGMA key = "x\'$keyHex\'"')
          ..execute('PRAGMA cipher_memory_security = ON');
      },
    ),
  );
}

final class AndroidKeystoreProtectedStorage
    implements PlatformProtectedStoragePort {
  const AndroidKeystoreProtectedStorage();

  @override
  Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<PlatformStorageUnlock> loadOrCreateStorageKey() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'loadOrCreateStorageKey',
      );
      final status = switch (result?['status']) {
        'ready' => PlatformStorageKeyStatus.ready,
        'key_lost' => PlatformStorageKeyStatus.wrappingKeyLost,
        'integrity_failure' => PlatformStorageKeyStatus.integrityFailure,
        _ => PlatformStorageKeyStatus.unavailable,
      };
      final protection = switch (result?['protection']) {
        'strongbox' => PlatformStorageProtection.strongBox,
        'tee' => PlatformStorageProtection.tee,
        'software' => PlatformStorageProtection.software,
        _ => PlatformStorageProtection.unknown,
      };
      final key = result?['databaseKey'];
      return PlatformStorageUnlock(
        status: status,
        protection: protection,
        databaseKey: key is Uint8List ? key : null,
      );
    } on PlatformException {
      return PlatformStorageUnlock(
        status: PlatformStorageKeyStatus.unavailable,
        protection: PlatformStorageProtection.unknown,
      );
    }
  }

  @override
  Future<void> destroyWrappingKey() async {
    await _channel.invokeMethod<void>('destroyWrappingKey');
  }
}

final class AndroidLocalArtifactCleanup implements LocalArtifactCleanupPort {
  const AndroidLocalArtifactCleanup();

  @override
  Future<CleanupReport> cleanupBounded({required int maximumEntries}) async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'cleanupBounded',
      <String, Object?>{'maximumEntries': maximumEntries},
    );
    return CleanupReport(
      removedEntries: result?['removedEntries'] as int? ?? 0,
      hasMore: result?['hasMore'] as bool? ?? false,
    );
  }

  @override
  Future<void> erasePersistentArtifacts() async {
    await _channel.invokeMethod<void>('erasePersistentArtifacts');
  }

  @override
  Future<void> clearVolatilePlaintext() async {}
}

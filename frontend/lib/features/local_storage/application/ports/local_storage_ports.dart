import 'package:communication_platform/core/application/ports/port.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/local_storage/domain/local_storage_model.dart';

abstract interface class ConversationProjectionRepository implements Port {
  Stream<List<ConversationProjection>> watchConversations();

  Future<Result<bool>> applyAuthenticatedEvent(StoredMessageEvent event);
}

/// Platform key APIs stay behind this port. Implementations must not return raw
/// WebCrypto wrapping keys or Android Keystore keys.
abstract interface class PlatformProtectedStoragePort implements Port {
  Future<bool> isAvailable();

  Future<PlatformStorageUnlock> loadOrCreateStorageKey();

  Future<void> destroyWrappingKey();
}

abstract interface class LocalArtifactCleanupPort implements Port {
  Future<CleanupReport> cleanupBounded({required int maximumEntries});

  Future<void> erasePersistentArtifacts();

  Future<void> clearVolatilePlaintext();
}

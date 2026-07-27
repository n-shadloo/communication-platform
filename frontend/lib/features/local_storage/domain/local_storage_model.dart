import 'dart:typed_data';

/// An immutable ciphertext-only projection safe to expose from Drift streams.
final class ConversationProjection {
  ConversationProjection({
    required this.conversationId,
    required this.kind,
    required Uint8List authenticatedCiphertext,
    required this.sortKey,
  }) : authenticatedCiphertext = Uint8List.fromList(authenticatedCiphertext);

  final String conversationId;
  final int kind;
  final Uint8List authenticatedCiphertext;
  final int sortKey;
}

/// Minimal documented fields needed to atomically apply an authenticated event.
/// Message bodies and metadata remain inside [authenticatedCiphertext].
final class StoredMessageEvent {
  StoredMessageEvent({
    required this.eventId,
    required this.messageId,
    required this.conversationId,
    required this.eventKind,
    required Uint8List authenticatedCiphertext,
    required this.messageStatus,
    required this.revision,
    required this.createdAt,
    required this.conversationKind,
    required Uint8List conversationProjectionCiphertext,
    required this.sortKey,
  }) : authenticatedCiphertext = Uint8List.fromList(authenticatedCiphertext),
       conversationProjectionCiphertext = Uint8List.fromList(
         conversationProjectionCiphertext,
       );

  final String eventId;
  final String messageId;
  final String conversationId;
  final int eventKind;
  final Uint8List authenticatedCiphertext;
  final int messageStatus;
  final int revision;
  final DateTime createdAt;
  final int conversationKind;
  final Uint8List conversationProjectionCiphertext;
  final int sortKey;
}

enum LocalWipeReason {
  logout,
  selfRevocation,
  remoteRevocation,
  wrappingKeyLoss,
  authenticatedStorageTamper,
}

enum PlatformStorageProtection { strongBox, tee, software, browser, unknown }

enum PlatformStorageKeyStatus {
  ready,
  unavailable,
  wrappingKeyLost,
  integrityFailure,
}

/// Android includes a transient SQLCipher key. Web deliberately exposes only an
/// opaque handle because its storage key is managed by WebCrypto page code.
final class PlatformStorageUnlock {
  PlatformStorageUnlock({
    required this.status,
    required this.protection,
    Uint8List? databaseKey,
  }) : databaseKey = databaseKey == null
           ? null
           : Uint8List.fromList(databaseKey);

  final PlatformStorageKeyStatus status;
  final PlatformStorageProtection protection;
  final Uint8List? databaseKey;

  bool get isReady => status == PlatformStorageKeyStatus.ready;
}

final class CleanupReport {
  const CleanupReport({required this.removedEntries, required this.hasMore});

  final int removedEntries;
  final bool hasMore;
}

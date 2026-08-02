import 'dart:convert';
import 'dart:math' as math;

import 'package:communication_platform/core/protocol/application_message_model.dart';
import 'package:communication_platform/core/protocol/attachment_crypto_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/drift_repository_base.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart'
    hide MessageReaction;
import 'package:communication_platform/features/messaging/application/ports/conversation_ports.dart';
import 'package:communication_platform/features/messaging/domain/conversation_model.dart';
import 'package:drift/drift.dart';

final class DriftConversationDomainRepository extends DriftRepositoryBase
    implements ConversationRepositoryPort {
  const DriftConversationDomainRepository(super.database);

  @override
  Stream<List<ConversationSummary>> watchConversations(String currentUserId) {
    final query = database.select(database.conversations)
      ..where((row) => row.tombstoned.equals(false))
      ..orderBy([
        (row) => OrderingTerm.desc(row.sortKey),
        (row) => OrderingTerm.desc(row.lastActivityEventId),
        (row) => OrderingTerm.asc(row.conversationId),
      ]);
    return query.watch().asyncMap((rows) async {
      final projections = <ConversationSummary>[];
      for (final row in rows) {
        final pinned =
            await (database.select(database.messages)..where(
                  (message) =>
                      message.conversationId.equals(row.conversationId) &
                      message.pinned.equals(true) &
                      message.deletedForMe.equals(false),
                ))
                .get();
        projections.add(
          ConversationSummary(
            conversationId: row.conversationId,
            kind: ConversationKind.values[row.kind],
            peerUserId: row.peerUserId,
            lastMessage: _optionalText(row.listProjectionCiphertext),
            lastActivityMs: row.sortKey,
            unreadCount: row.unreadCount,
            mutedUntil: row.mutedUntil?.toUtc(),
            draft: _optionalText(row.draftCiphertext),
            pinnedMessageIds: Set.unmodifiable(
              pinned.map((message) => message.messageId),
            ),
            pinned: row.pinned,
            displayTitle: _optionalText(row.displayTitleCiphertext),
          ),
        );
      }
      return List.unmodifiable(projections);
    });
  }

  @override
  Stream<List<ConversationMessage>> watchMessages({
    required String currentUserId,
    required String conversationId,
  }) {
    final query = database.select(database.messages)
      ..where((row) => row.conversationId.equals(conversationId))
      ..orderBy([
        (row) => OrderingTerm.asc(row.orderingMs),
        (row) => OrderingTerm.asc(row.orderingEventId),
        (row) => OrderingTerm.asc(row.messageId),
      ]);
    return query.watch().asyncMap((rows) async {
      final messages = <ConversationMessage>[];
      for (final row in rows) {
        final reactions =
            await (database.select(database.messageReactions)
                  ..where(
                    (reaction) => reaction.messageId.equals(row.messageId),
                  )
                  ..orderBy([
                    (reaction) => OrderingTerm.asc(reaction.reactingUserId),
                  ]))
                .get();
        final receipts = await (database.select(
          database.receipts,
        )..where((receipt) => receipt.messageId.equals(row.messageId))).get();
        var receiptState = MessageReceiptState.none;
        for (final receipt in receipts) {
          final state = MessageReceiptState.values[receipt.receiptState];
          if (state.index > receiptState.index) {
            receiptState = state;
          }
        }
        final attachmentRows =
            await (database.select(database.attachments)..where(
                  (attachment) => attachment.messageId.equals(row.messageId),
                ))
                .get();
        final attachments = <EncryptedAttachmentDescriptor>[];
        final attachmentStates = <AttachmentTransferState>[];
        for (final attachment in attachmentRows) {
          try {
            final value = jsonDecode(
              utf8.decode(
                attachment.encryptedDescriptor,
                allowMalformed: false,
              ),
            );
            if (value is! Map<String, Object?>) continue;
            attachments.add(
              EncryptedAttachmentDescriptor(
                capabilityId: value['capability']! as String,
                key: base64Url.decode(value['key']! as String),
                header: base64Url.decode(value['header']! as String),
                secretstreamHeader: base64Url.decode(
                  value['stream_header']! as String,
                ),
                encryptedSize: value['encrypted_size']! as int,
                bucketSize: value['bucket_size']! as int,
                plaintextSize: value['plaintext_size']! as int,
                displayName: value['name']! as String,
                mimeType: value['mime']! as String,
                mediaKind:
                    AttachmentMediaKind.values[value['media_kind']! as int],
                width: value['width'] as int?,
                height: value['height'] as int?,
                caption: value['caption'] as String?,
                thumbnail: value['thumbnail'] == null
                    ? null
                    : base64Url.decode(value['thumbnail']! as String),
              ),
            );
            attachmentStates.add(
              AttachmentTransferState.values[math.min(
                math.max(attachment.transferState, 0),
                AttachmentTransferState.values.length - 1,
              )],
            );
          } on Object {
            // Malformed local descriptors remain invisible until the next
            // authenticated event rebuild; they are never presented.
          }
        }
        messages.add(
          ConversationMessage(
            messageId: row.messageId,
            conversationId: row.conversationId,
            senderUserId: row.senderUserId,
            senderDeviceId: row.senderDeviceId,
            text: row.deletedForEveryone
                ? null
                : _optionalText(row.projectionCiphertext),
            attachments: List.unmodifiable(attachments),
            attachmentStates: List.unmodifiable(attachmentStates),
            replyToMessageId: row.replyToMessageId,
            quoteFallback: _optionalText(row.quoteFallbackCiphertext),
            createdMs: row.createdAt.millisecondsSinceEpoch,
            orderingMs: row.orderingMs,
            timestampState: MessageTimestampState.values[row.timestampState],
            revision: row.revision,
            edited: row.revision > 0,
            deletedForEveryone: row.deletedForEveryone,
            deletedForMe: row.deletedForMe,
            pinned: row.pinned,
            starred: row.starred,
            unread: row.unread,
            transportState: MessageTransportState.values[row.status],
            receiptState: receiptState,
            reactions: List.unmodifiable(
              reactions
                  .where((reaction) => reaction.emojiCiphertext != null)
                  .map(
                    (reaction) => MessageReaction(
                      reactingUserId: reaction.reactingUserId,
                      emoji: utf8.decode(
                        reaction.emojiCiphertext!,
                        allowMalformed: false,
                      ),
                    ),
                  ),
            ),
          ),
        );
      }
      return List.unmodifiable(messages);
    });
  }

  @override
  Future<Result<int>> reserveSenderCounter(String deviceId) {
    return runWrite(() async {
      final normalized = deviceId.toLowerCase();
      final existing = await (database.select(
        database.applicationSenderCounters,
      )..where((row) => row.deviceId.equals(normalized))).getSingleOrNull();
      final previous = existing?.lastCounter ?? 0;
      if (previous >= 0x7fffffffffffffff) {
        throw const _CounterExhausted();
      }
      final next = previous + 1;
      await database
          .into(database.applicationSenderCounters)
          .insertOnConflictUpdate(
            ApplicationSenderCountersCompanion.insert(
              deviceId: normalized,
              lastCounter: Value(next),
            ),
          );
      return next;
    });
  }

  @override
  Future<Result<int>> nextEditRevision({
    required String messageId,
    required String senderUserId,
  }) async {
    try {
      final query = database.selectOnly(database.storedApplicationEvents)
        ..addColumns([database.storedApplicationEvents.revision.max()])
        ..where(
          database.storedApplicationEvents.targetMessageId.equals(messageId) &
              database.storedApplicationEvents.senderUserId.equals(
                senderUserId.toLowerCase(),
              ) &
              database.storedApplicationEvents.kind.equals(
                ApplicationEventKind.messageEdit.wireValue,
              ),
        );
      final row = await query.getSingle();
      final current =
          row.read(database.storedApplicationEvents.revision.max()) ?? 0;
      return Result.success(current + 1);
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }

  @override
  Future<Result<void>> requireOriginalSender({
    required String messageId,
    required String senderUserId,
  }) async {
    try {
      final message = await (database.select(
        database.messages,
      )..where((row) => row.messageId.equals(messageId))).getSingleOrNull();
      if (message == null) {
        return const Result.failure(
          ValidationFailure(ValidationFailureKind.invalidInput),
        );
      }
      if (message.senderUserId != senderUserId.toLowerCase()) {
        return const Result.failure(
          SecurityFailure(SecurityFailureKind.policyBlocked),
        );
      }
      return const Result.success(null);
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }

  @override
  Future<Result<ConversationSummary?>> readConversation(
    String conversationId,
  ) async {
    try {
      final row =
          await (database.select(database.conversations)..where(
                (conversation) =>
                    conversation.conversationId.equals(conversationId),
              ))
              .getSingleOrNull();
      if (row == null) {
        return const Result.success(null);
      }
      final pinned =
          await (database.select(database.messages)..where(
                (message) =>
                    message.conversationId.equals(conversationId) &
                    message.pinned.equals(true),
              ))
              .get();
      return Result.success(
        ConversationSummary(
          conversationId: row.conversationId,
          kind: ConversationKind.values[row.kind],
          peerUserId: row.peerUserId,
          lastMessage: _optionalText(row.listProjectionCiphertext),
          lastActivityMs: row.sortKey,
          unreadCount: row.unreadCount,
          mutedUntil: row.mutedUntil?.toUtc(),
          draft: _optionalText(row.draftCiphertext),
          pinnedMessageIds: Set.unmodifiable(
            pinned.map((message) => message.messageId),
          ),
          pinned: row.pinned,
          displayTitle: _optionalText(row.displayTitleCiphertext),
        ),
      );
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }

  @override
  Future<Result<void>> saveDraft({
    required String conversationId,
    required String? text,
  }) {
    if (text != null &&
        (utf8.encode(text).length >
                ApplicationMessageProtocolV1.maximumTextBytes ||
            text.runes.length >
                ApplicationMessageProtocolV1.maximumTextScalars)) {
      return Future.value(
        const Result.failure(
          ValidationFailure(ValidationFailureKind.limitExceeded),
        ),
      );
    }
    return runWrite(() async {
      final updated =
          await (database.update(
            database.conversations,
          )..where((row) => row.conversationId.equals(conversationId))).write(
            ConversationsCompanion(
              draftCiphertext: Value(
                text == null || text.isEmpty
                    ? null
                    : Uint8List.fromList(utf8.encode(text)),
              ),
            ),
          );
      if (updated != 1) {
        throw const _MissingConversation();
      }
    });
  }

  @override
  Future<Result<void>> setMutedUntil({
    required String conversationId,
    required DateTime? mutedUntil,
  }) => runWrite(() async {
    final updated =
        await (database.update(
          database.conversations,
        )..where((row) => row.conversationId.equals(conversationId))).write(
          ConversationsCompanion(mutedUntil: Value(mutedUntil?.toUtc())),
        );
    if (updated != 1) {
      throw const _MissingConversation();
    }
  });

  @override
  Future<Result<void>> setConversationPinned({
    required String conversationId,
    required bool pinned,
  }) => runWrite(() async {
    final updated =
        await (database.update(database.conversations)
              ..where((row) => row.conversationId.equals(conversationId)))
            .write(ConversationsCompanion(pinned: Value(pinned)));
    if (updated != 1) {
      throw const _MissingConversation();
    }
  });

  @override
  Future<Result<void>> deleteForMe(String messageId) => runWrite(() async {
    final updated =
        await (database.update(
          database.messages,
        )..where((row) => row.messageId.equals(messageId))).write(
          const MessagesCompanion(
            deletedForMe: Value(true),
            unread: Value(false),
          ),
        );
    if (updated != 1) {
      throw const _MissingMessage();
    }
    await (database.update(
      database.attachments,
    )..where((row) => row.messageId.equals(messageId))).write(
      const AttachmentsCompanion(
        boundedCacheHandleCiphertext: Value(null),
        cacheExpiresAt: Value(null),
      ),
    );
    await _refreshUnreadCountForMessage(messageId);
  });

  @override
  Future<Result<void>> setStar({
    required String messageId,
    required bool starred,
  }) => runWrite(() async {
    final updated =
        await (database.update(database.messages)
              ..where((row) => row.messageId.equals(messageId)))
            .write(MessagesCompanion(starred: Value(starred)));
    if (updated != 1) {
      throw const _MissingMessage();
    }
  });

  @override
  Future<Result<void>> deleteConversationForMe(String conversationId) =>
      runWrite(() async {
        final updated =
            await (database.update(
              database.conversations,
            )..where((row) => row.conversationId.equals(conversationId))).write(
              const ConversationsCompanion(
                tombstoned: Value(true),
                unreadCount: Value(0),
                draftCiphertext: Value(null),
              ),
            );
        if (updated != 1) {
          throw const _MissingConversation();
        }
        await (database.update(
          database.messages,
        )..where((row) => row.conversationId.equals(conversationId))).write(
          const MessagesCompanion(
            deletedForMe: Value(true),
            unread: Value(false),
          ),
        );
      });

  @override
  Future<Result<List<String>>> markConversationRead(String conversationId) =>
      runWrite(() async {
        final conversation =
            await (database.select(database.conversations)
                  ..where((row) => row.conversationId.equals(conversationId)))
                .getSingleOrNull();
        if (conversation == null) {
          throw const _MissingConversation();
        }
        final unread =
            await (database.select(database.messages)..where(
                  (row) =>
                      row.conversationId.equals(conversationId) &
                      row.unread.equals(true) &
                      row.deletedForMe.equals(false),
                ))
                .get();
        if (unread.isNotEmpty) {
          await (database.update(database.messages)..where(
                (row) =>
                    row.conversationId.equals(conversationId) &
                    row.unread.equals(true),
              ))
              .write(const MessagesCompanion(unread: Value(false)));
        }
        await (database.update(database.conversations)
              ..where((row) => row.conversationId.equals(conversationId)))
            .write(const ConversationsCompanion(unreadCount: Value(0)));
        return List.unmodifiable(unread.map((message) => message.messageId));
      });

  @override
  Future<Result<void>> markConversationUnread({
    required String conversationId,
    required String currentUserId,
  }) => runWrite(() async {
    final conversation =
        await (database.select(database.conversations)
              ..where((row) => row.conversationId.equals(conversationId)))
            .getSingleOrNull();
    if (conversation == null) {
      throw const _MissingConversation();
    }
    if (ConversationKind.values[conversation.kind] == ConversationKind.saved) {
      return;
    }
    final latestIncoming =
        await (database.select(database.messages)
              ..where(
                (row) =>
                    row.conversationId.equals(conversationId) &
                    row.senderUserId.equals(currentUserId.toLowerCase()).not() &
                    row.deletedForMe.equals(false),
              )
              ..orderBy([
                (row) => OrderingTerm.desc(row.orderingMs),
                (row) => OrderingTerm.desc(row.orderingEventId),
              ])
              ..limit(1))
            .getSingleOrNull();
    if (latestIncoming == null) {
      return;
    }
    await (database.update(database.messages)
          ..where((row) => row.messageId.equals(latestIncoming.messageId)))
        .write(const MessagesCompanion(unread: Value(true)));
    await (database.update(database.conversations)
          ..where((row) => row.conversationId.equals(conversationId)))
        .write(const ConversationsCompanion(unreadCount: Value(1)));
  });

  @override
  Future<Result<List<PendingDeliveredReceipt>>> readPendingDeliveredReceipts({
    required int limit,
  }) async {
    if (limit < 1 || limit > ApplicationMessageProtocolV1.maximumReferences) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.limitExceeded),
      );
    }
    try {
      final rows =
          await (database.select(database.pendingApplicationReceipts)
                ..orderBy([
                  (row) => OrderingTerm.asc(row.createdAt),
                  (row) => OrderingTerm.asc(row.messageId),
                ])
                ..limit(limit))
              .get();
      return Result.success(
        List.unmodifiable(
          rows.map(
            (row) => PendingDeliveredReceipt(
              messageId: row.messageId,
              conversationId: row.conversationId,
              targetUserId: row.targetUserId,
              localDeviceId: row.localDeviceId,
            ),
          ),
        ),
      );
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }

  @override
  Future<Result<void>> completePendingDeliveredReceipts({
    required String localDeviceId,
    required List<String> messageIds,
  }) {
    if (messageIds.isEmpty ||
        messageIds.length > ApplicationMessageProtocolV1.maximumReferences) {
      return Future.value(
        const Result.failure(
          ValidationFailure(ValidationFailureKind.invalidInput),
        ),
      );
    }
    return runWrite(() async {
      await (database.delete(database.pendingApplicationReceipts)..where(
            (row) =>
                row.localDeviceId.equals(localDeviceId.toLowerCase()) &
                row.messageId.isIn(messageIds),
          ))
          .go();
    });
  }

  Future<void> _refreshUnreadCountForMessage(String messageId) async {
    final message = await (database.select(
      database.messages,
    )..where((row) => row.messageId.equals(messageId))).getSingle();
    final countExpression = database.messages.messageId.count();
    final countRow =
        await (database.selectOnly(database.messages)
              ..addColumns([countExpression])
              ..where(
                database.messages.conversationId.equals(
                      message.conversationId,
                    ) &
                    database.messages.unread.equals(true) &
                    database.messages.deletedForMe.equals(false),
              ))
            .getSingle();
    await (database.update(
      database.conversations,
    )..where((row) => row.conversationId.equals(message.conversationId))).write(
      ConversationsCompanion(
        unreadCount: Value(countRow.read(countExpression) ?? 0),
      ),
    );
  }
}

String? _optionalText(Uint8List? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  return utf8.decode(value, allowMalformed: false);
}

final class _CounterExhausted implements Exception {
  const _CounterExhausted();
}

final class _MissingConversation implements Exception {
  const _MissingConversation();
}

final class _MissingMessage implements Exception {
  const _MissingMessage();
}

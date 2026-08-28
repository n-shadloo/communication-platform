import 'dart:convert';

import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:drift/drift.dart';

/// Local history, written the shape a projection writes it.
///
/// The read-path tests need conversations of very different lengths and need
/// them cheaply, so this writes the projected rows directly rather than
/// replaying events through the projector. What matters for these tests is the
/// row shape the timeline reads — the ordering key, and one reaction, one
/// receipt and one attachment per message, which is what the per-message
/// queries this change removes used to be issued for.
const historyBaseOrderingMs = 1700000000000;

String conversationMessageId(String conversationId, int index) =>
    '$conversationId-message-${index.toString().padLeft(6, '0')}';

Future<void> seedConversationHistory(
  LocalDatabase database, {
  required String conversationId,
  required int messages,
  int pinnedEvery = 0,
  bool withChildren = true,
}) async {
  await database
      .into(database.conversations)
      .insert(
        ConversationsCompanion.insert(
          conversationId: conversationId,
          kind: 0,
          listProjectionCiphertext: Uint8List.fromList(utf8.encode('preview')),
          sortKey: historyBaseOrderingMs + messages,
        ),
        mode: InsertMode.insertOrReplace,
      );
  await database.batch((batch) {
    for (var index = 0; index < messages; index += 1) {
      final messageId = conversationMessageId(conversationId, index);
      batch
        ..insert(
          database.messages,
          MessagesCompanion.insert(
            messageId: messageId,
            conversationId: conversationId,
            currentEventId: 'event-$messageId',
            projectionCiphertext: Uint8List.fromList(
              utf8.encode('message $index'),
            ),
            status: 3,
            revision: 0,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              historyBaseOrderingMs + index,
              isUtc: true,
            ),
            senderUserId: const Value('peer'),
            orderingMs: Value(historyBaseOrderingMs + index),
            orderingEventId: Value('event-$messageId'),
            pinned: Value(pinnedEvery > 0 && index % pinnedEvery == 0),
          ),
        )
        ..insert(
          database.storedApplicationEvents,
          StoredApplicationEventsCompanion.insert(
            eventId: 'event-$messageId',
            conversationId: conversationId,
            kind: 1,
            senderUserId: 'peer',
            senderDeviceId: 'peer-device',
            senderCounter: index + 1,
            createdMs: historyBaseOrderingMs + index,
            orderingMs: historyBaseOrderingMs + index,
            canonicalEvent: Uint8List.fromList(utf8.encode('canonical')),
            bodyProjection: Uint8List.fromList(utf8.encode('body')),
            applyState: 2,
            targetMessageId: Value(messageId),
          ),
        );
      if (!withChildren) continue;
      batch
        ..insert(
          database.messageReactions,
          MessageReactionsCompanion.insert(
            messageId: messageId,
            reactingUserId: 'peer',
            eventId: 'reaction-$messageId',
            emojiCiphertext: Value(
              Uint8List.fromList(utf8.encode('\u{1F44D}')),
            ),
          ),
        )
        ..insert(
          database.receipts,
          ReceiptsCompanion.insert(
            messageId: messageId,
            userId: 'peer',
            deviceId: 'peer-device',
            receiptState: 1,
            projectionCiphertext: Uint8List.fromList(utf8.encode('receipt')),
          ),
        )
        ..insert(
          database.attachments,
          AttachmentsCompanion.insert(
            attachmentId: 'attachment-$messageId',
            messageId: messageId,
            encryptedDescriptor: Uint8List.fromList(
              utf8.encode(jsonEncode(_descriptor)),
            ),
            transferState: 0,
          ),
        );
    }
  });
}

/// Appends one message newer than everything [seedConversationHistory] wrote.
Future<String> appendConversationMessage(
  LocalDatabase database, {
  required String conversationId,
  required int index,
  String text = 'newly arrived',
}) async {
  final messageId = conversationMessageId(conversationId, index);
  await database
      .into(database.messages)
      .insert(
        MessagesCompanion.insert(
          messageId: messageId,
          conversationId: conversationId,
          currentEventId: 'event-$messageId',
          projectionCiphertext: Uint8List.fromList(utf8.encode(text)),
          status: 3,
          revision: 0,
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            historyBaseOrderingMs + index,
            isUtc: true,
          ),
          senderUserId: const Value('peer'),
          orderingMs: Value(historyBaseOrderingMs + index),
          orderingEventId: Value('event-$messageId'),
        ),
      );
  return messageId;
}

final _descriptor = <String, Object?>{
  'capability': 'capability-1',
  'key': base64Url.encode(List<int>.filled(32, 7)),
  'header': base64Url.encode(List<int>.filled(24, 8)),
  'stream_header': base64Url.encode(List<int>.filled(24, 9)),
  'encrypted_size': 4096,
  'bucket_size': 4096,
  'plaintext_size': 2048,
  'name': 'photo.jpg',
  'mime': 'image/jpeg',
  'media_kind': 0,
};

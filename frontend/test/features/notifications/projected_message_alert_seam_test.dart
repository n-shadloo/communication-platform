import 'dart:typed_data';

import 'package:communication_platform/core/protocol/application_message_model.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:communication_platform/features/messaging/domain/conversation_model.dart';
import 'package:communication_platform/features/messaging/infrastructure/drift_application_event_projector.dart';
import 'package:communication_platform/features/notifications/domain/message_alert_model.dart';
import 'package:communication_platform/features/notifications/infrastructure/drift_message_alert_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The one seam between the messaging projector and the alert path.
///
/// The alert is a projection of `messages.unread`, and nothing else joins the
/// two features. These tests run the *real* projector over authenticated
/// application events and then ask the *real* alert store what is pending, so
/// the join is held by something other than an assumption: an inbound message
/// must be announceable, and everything the projector deliberately does not
/// mark unread must stay silent.
void main() {
  const currentUser = '00000000-0000-0000-0000-000000000001';
  const peerUser = '00000000-0000-0000-0000-000000000002';
  const currentDevice = '00000000-0000-0000-0000-000000000011';
  const peerDevice = '00000000-0000-0000-0000-000000000022';
  final authenticatedAt = DateTime.fromMillisecondsSinceEpoch(
    1700000010000,
    isUtc: true,
  );

  late LocalDatabase database;
  late DriftMessageAlertStore store;

  setUp(() {
    database = LocalDatabase(NativeDatabase.memory());
    store = DriftMessageAlertStore(database);
  });

  tearDown(() => database.close());

  Future<void> apply(ApplicationEventCommit commit) =>
      database.writeTransaction(
        () => DriftApplicationEventProjector(
          database,
        ).applyInsideTransaction(commit),
      );

  Future<List<PendingMessageAlert>> pending() async =>
      (await store.readPending(limit: 32) as Success<List<PendingMessageAlert>>)
          .value;

  test('a message from someone else is announceable', () async {
    await apply(
      _commit(
        eventSeed: 10,
        senderUser: peerUser,
        senderDevice: peerDevice,
        counter: 1,
        messageSeed: 60,
        text: 'hello',
        authenticatedAt: authenticatedAt,
      ),
    );

    final rows = await pending();

    expect(rows, hasLength(1));
    expect(rows.single.alerted, isFalse);
  });

  test('a message this account sent is never announceable', () async {
    await apply(
      _commit(
        eventSeed: 11,
        senderUser: currentUser,
        senderDevice: currentDevice,
        counter: 1,
        messageSeed: 61,
        text: 'mine',
        localOrigin: true,
        authenticatedAt: authenticatedAt,
      ),
    );

    expect(await pending(), isEmpty);
  });

  test('a note to Saved Messages is never announceable', () async {
    await apply(
      _commit(
        eventSeed: 12,
        senderUser: currentUser,
        senderDevice: currentDevice,
        counter: 1,
        messageSeed: 62,
        text: 'note',
        localOrigin: true,
        conversationKind: ConversationKind.saved,
        peerUserId: null,
        authenticatedAt: authenticatedAt,
      ),
    );

    expect(await pending(), isEmpty);
  });

  test('a rebuild triggered by a later event keeps the spent marker', () async {
    // A reaction, an edit or a receipt makes the projector rebuild the whole
    // conversation. If that reset the marker, every one of them would
    // re-announce a message the user was told about already.
    await apply(
      _commit(
        eventSeed: 13,
        senderUser: peerUser,
        senderDevice: peerDevice,
        counter: 1,
        messageSeed: 63,
        text: 'first',
        authenticatedAt: authenticatedAt,
      ),
    );
    final messageId = (await pending()).single.messageId;
    await store.markAlerted([messageId]);

    await apply(
      _commit(
        eventSeed: 14,
        senderUser: peerUser,
        senderDevice: peerDevice,
        counter: 2,
        messageSeed: 63,
        text: 'edited',
        edit: true,
        authenticatedAt: authenticatedAt,
      ),
    );

    final rows = await pending();
    expect(rows, hasLength(1));
    expect(
      rows.single.alerted,
      isTrue,
      reason: 'a rebuild rewrites the projection and leaves the marker alone',
    );
  });

  test('a message its sender withdrew stops being announceable', () async {
    await apply(
      _commit(
        eventSeed: 15,
        senderUser: peerUser,
        senderDevice: peerDevice,
        counter: 1,
        messageSeed: 64,
        text: 'regretted',
        authenticatedAt: authenticatedAt,
      ),
    );
    expect(await pending(), hasLength(1));

    await apply(
      _commit(
        eventSeed: 16,
        senderUser: peerUser,
        senderDevice: peerDevice,
        counter: 2,
        messageSeed: 64,
        text: '',
        deleteForEveryone: true,
        authenticatedAt: authenticatedAt,
      ),
    );

    expect(
      await pending(),
      isEmpty,
      reason:
          'content the sender withdrew must not sit behind an alert saying '
          'something is waiting',
    );
  });

  test(
    'a read receipt from this account stops it being announceable',
    () async {
      // What the user reading on their other device produces here.
      await apply(
        _commit(
          eventSeed: 17,
          senderUser: peerUser,
          senderDevice: peerDevice,
          counter: 1,
          messageSeed: 65,
          text: 'seen elsewhere',
          authenticatedAt: authenticatedAt,
        ),
      );
      expect(await pending(), hasLength(1));

      await apply(
        _commit(
          eventSeed: 18,
          senderUser: currentUser,
          senderDevice: '00000000-0000-0000-0000-000000000012',
          counter: 1,
          messageSeed: 65,
          text: '',
          read: true,
          authenticatedAt: authenticatedAt,
        ),
      );

      expect(await pending(), isEmpty);
    },
  );
}

ApplicationEventCommit _commit({
  required int eventSeed,
  required String senderUser,
  required String senderDevice,
  required int counter,
  required int messageSeed,
  required String text,
  required DateTime authenticatedAt,
  bool localOrigin = false,
  bool edit = false,
  bool deleteForEveryone = false,
  bool read = false,
  ConversationKind conversationKind = ConversationKind.direct,
  String? peerUserId = '00000000-0000-0000-0000-000000000002',
}) {
  final messageId = _id(messageSeed, 16);
  final (kind, body) = switch ((edit, deleteForEveryone, read)) {
    (true, _, _) => (
      ApplicationEventKind.messageEdit,
      MessageEditBody(
            targetMessageId: messageId,
            replacementText: text,
            revision: 2,
          )
          as ApplicationEventBody,
    ),
    (_, true, _) => (
      ApplicationEventKind.messageDelete,
      MessageDeleteBody(targetMessageId: messageId),
    ),
    (_, _, true) => (
      ApplicationEventKind.receiptRead,
      ReceiptBody(messageIds: [messageId]),
    ),
    _ => (
      ApplicationEventKind.messageCreate,
      MessageCreateBody(messageId: messageId, text: text),
    ),
  };
  final event = ApplicationEventRecord(
    version: ApplicationMessageProtocolV1.version,
    eventId: _id(eventSeed, 16),
    conversationId: _id(9, 32),
    kindValue: kind.wireValue,
    senderUserId: protocolUuidBytes(senderUser),
    senderDeviceId: protocolUuidBytes(senderDevice),
    senderCounter: counter,
    createdMs: 1700000000000 + eventSeed,
    references: kind == ApplicationEventKind.messageCreate
        ? const []
        : [messageId],
    body: body,
  );
  return ApplicationEventCommit(
    event: event,
    canonicalBytes: Uint8List.fromList([
      eventSeed,
      kind.wireValue,
      ...event.eventId,
    ]),
    currentUserId: '00000000-0000-0000-0000-000000000001',
    currentDeviceId: '00000000-0000-0000-0000-000000000011',
    conversationKind: conversationKind.index,
    peerUserId: peerUserId,
    localOrigin: localOrigin,
    authenticatedAt: authenticatedAt,
  );
}

Uint8List _id(int seed, int length) => Uint8List.fromList(
  List<int>.generate(length, (index) => (seed + index) & 0xff),
);

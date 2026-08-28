import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:communication_platform/features/messaging/domain/conversation_model.dart';
import 'package:communication_platform/features/notifications/domain/message_alert_model.dart';
import 'package:communication_platform/features/notifications/infrastructure/drift_message_alert_store.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The half of the alert that lives in the database.
///
/// These tests hold two things the design rests on: that the durable marker
/// survives what the messaging projector does to a conversation, and that the
/// stream fires after the transaction commits rather than during it.
void main() {
  late LocalDatabase database;
  late DriftMessageAlertStore store;

  setUp(() {
    database = LocalDatabase(NativeDatabase.memory());
    store = DriftMessageAlertStore(database);
  });

  tearDown(() => database.close());

  test('only unread, displayable, incoming rows are pending', () async {
    await _conversation(database, 'direct');
    await _conversation(database, 'saved', kind: ConversationKind.saved);
    await _message(database, 'unread', 'direct', unread: true);
    await _message(database, 'read', 'direct');
    await _message(
      database,
      'deleted-for-me',
      'direct',
      unread: true,
      deletedForMe: true,
    );
    await _message(
      database,
      'withdrawn',
      'direct',
      unread: true,
      deletedForEveryone: true,
    );
    await _message(database, 'saved-note', 'saved', unread: true);

    final pending = await _pending(store);

    expect(pending.map((row) => row.messageId), ['unread']);
  });

  test('a tombstoned conversation contributes nothing', () async {
    await _conversation(database, 'gone', tombstoned: true);
    await _message(database, 'orphan', 'gone', unread: true);

    expect(await _pending(store), isEmpty);
  });

  test('the mute deadline reaches the caller unevaluated', () async {
    // Evaluating it here would freeze "now" at the moment the query was built.
    // The reconciler compares it against its own clock instead.
    final until = DateTime.utc(2026, 8, 21, 18);
    await _conversation(database, 'muted', mutedUntil: until);
    await _message(database, 'm1', 'muted', unread: true);

    // Compared as an instant, not as a rendering of one: Drift reads a stored
    // timestamp back in the host's local zone, and asserting on the local
    // representation would make this test pass or fail by machine.
    expect((await _pending(store)).single.mutedUntil!.toUtc(), until);
  });

  test('rows with an unspent marker are read first', () async {
    await _conversation(database, 'direct');
    // Newest first is the tie-break, so an ordering that ignored the marker
    // would put the alerted row at the front and starve the other one.
    await _message(
      database,
      'old-unalerted',
      'direct',
      unread: true,
      orderingMs: 1,
    );
    await _message(
      database,
      'new-alerted',
      'direct',
      unread: true,
      alerted: true,
      orderingMs: 9,
    );

    final page = await _pendingLimited(store, 1);

    expect(page.single.messageId, 'old-unalerted');
  });

  test('the marker is spent durably and only for the named rows', () async {
    await _conversation(database, 'direct');
    await _message(database, 'm1', 'direct', unread: true);
    await _message(database, 'm2', 'direct', unread: true);

    expect(await store.markAlerted(['m1']), isA<Success<void>>());

    final pending = await _pending(store);
    expect(
      {for (final row in pending) row.messageId: row.alerted},
      {'m1': true, 'm2': false},
    );
  });

  test('a projection rebuild does not spend or restore the marker', () async {
    // This is what the messaging projector does on every commit that touches a
    // conversation: it re-writes each message row through
    // `insertOnConflictUpdate` with a companion that names the projected
    // columns and nothing else. The marker has to survive that, or every edit,
    // reaction or receipt in a conversation would re-announce its messages.
    await _conversation(database, 'direct');
    await _message(database, 'm1', 'direct', unread: true);
    await store.markAlerted(['m1']);

    await database
        .into(database.messages)
        .insertOnConflictUpdate(
          MessagesCompanion.insert(
            messageId: 'm1',
            conversationId: 'direct',
            currentEventId: 'event-rebuilt',
            projectionCiphertext: Uint8List.fromList([9]),
            status: MessageTransportState.received.index,
            revision: 1,
            createdAt: DateTime.utc(2026, 8, 21),
            unread: const Value(true),
          ),
        );

    expect((await _pending(store)).single.alerted, isTrue);
  });

  test(
    'the signal arrives after the transaction commits, never during it',
    () async {
      await _conversation(database, 'direct');
      final seen = <int>[];
      final subscription = store.changes.listen((_) async {
        seen.add((await _pending(store)).length);
      });
      addTearDown(subscription.cancel);

      await database.writeTransaction(() async {
        await _message(database, 'm1', 'direct', unread: true);
        await _message(database, 'm2', 'direct', unread: true);
      });
      await Future<void>.delayed(Duration.zero);

      expect(
        seen,
        isNotEmpty,
        reason: 'a committed write has to reach the alert path',
      );
      expect(
        seen,
        everyElement(2),
        reason:
            'every observation sees the whole committed transaction; an alert '
            'must never be a projection of a half-written one',
      );
    },
  );

  test('the prompt marker is durable and starts unset', () async {
    expect(await _requested(store), isFalse);

    await store.recordPermissionRequested();

    expect(await _requested(store), isTrue);
    expect(
      await _requested(DriftMessageAlertStore(database)),
      isTrue,
      reason:
          'it is read back from storage, not from the instance that wrote it',
    );
  });
}

Future<List<PendingMessageAlert>> _pending(DriftMessageAlertStore store) =>
    _pendingLimited(store, 64);

Future<List<PendingMessageAlert>> _pendingLimited(
  DriftMessageAlertStore store,
  int limit,
) async {
  final result = await store.readPending(limit: limit);
  return (result as Success<List<PendingMessageAlert>>).value;
}

Future<bool> _requested(DriftMessageAlertStore store) async =>
    (await store.readPermissionRequested() as Success<bool>).value;

Future<void> _conversation(
  LocalDatabase database,
  String id, {
  ConversationKind kind = ConversationKind.direct,
  DateTime? mutedUntil,
  bool tombstoned = false,
}) => database
    .into(database.conversations)
    .insert(
      ConversationsCompanion.insert(
        conversationId: id,
        kind: kind.index,
        listProjectionCiphertext: Uint8List.fromList([1]),
        sortKey: 0,
        mutedUntil: Value(mutedUntil),
        tombstoned: Value(tombstoned),
      ),
    );

Future<void> _message(
  LocalDatabase database,
  String id,
  String conversationId, {
  bool unread = false,
  bool alerted = false,
  bool deletedForMe = false,
  bool deletedForEveryone = false,
  int orderingMs = 0,
}) => database
    .into(database.messages)
    .insert(
      MessagesCompanion.insert(
        messageId: id,
        conversationId: conversationId,
        currentEventId: 'event-$id',
        projectionCiphertext: Uint8List.fromList([1]),
        status: MessageTransportState.received.index,
        revision: 0,
        createdAt: DateTime.utc(2026, 8, 21),
        unread: Value(unread),
        alerted: Value(alerted),
        deletedForMe: Value(deletedForMe),
        deletedForEveryone: Value(deletedForEveryone),
        orderingMs: Value(orderingMs),
      ),
    );

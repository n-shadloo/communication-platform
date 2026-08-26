import 'dart:io';

import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// The one-shot repair the schema-14 upgrade carries.
///
/// A code fix alone leaves the devices that already ran the broken engine
/// broken: their inbox rows are stranded in `inspecting` behind attempt counts
/// large enough to produce a quarter-hour of backoff, their outbox rows are
/// waiting out the same thing, and a conversation whose row was retired while
/// its messages survived is invisible to the list and to the diagnostics report
/// while the chat page renders it. None of that is content, all of it is
/// scheduling and projection state, and all of it is derivable.
void main() {
  late Directory directory;
  late File file;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('delivery-repair-');
    file = File('${directory.path}/repair.sqlite');
  });

  tearDown(() async {
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  /// Builds the state a device running schema 13 is actually in.
  Future<void> seedStrandedVersionThirteen() async {
    final created = LocalDatabase(NativeDatabase(file));
    await created.customSelect('SELECT 1').getSingle();
    await created.close();

    final raw = sqlite3.open(file.path)
      ..execute('PRAGMA foreign_keys = OFF')
      ..execute('ALTER TABLE inbox_envelopes DROP COLUMN inspection_failures')
      // Two envelopes the old engine left mid-inspection, carrying attempt
      // counts high enough that the backoff they produce is capped jitter.
      ..execute(
        'INSERT INTO inbox_envelopes '
        '(envelope_id, sequence, envelope_ciphertext, processing_state, '
        'ready_to_acknowledge, attempt_count, next_attempt_at) VALUES '
        "('${_uuid(1)}', 1, X'0102', 1, 0, 41, 4102444800), "
        "('${_uuid(2)}', 2, X'0304', 0, 0, 37, 4102444800)",
      )
      // One acknowledged envelope, which the repair must not disturb.
      ..execute(
        'INSERT INTO inbox_envelopes '
        '(envelope_id, sequence, envelope_ciphertext, processing_state, '
        'ready_to_acknowledge, attempt_count) VALUES '
        "('${_uuid(3)}', 3, X'0506', 4, 0, 2)",
      )
      ..execute(
        'INSERT INTO outbox_operations '
        '(operation_id, event_id, recipient_device_id, recipient_user_id, '
        'batch_index, exact_recipient_ciphertext, attempt_state, '
        'attempt_count, next_attempt_at) VALUES '
        "('probe1', 'event-probe1', '${_uuid(10)}', 'peer', 0, X'0708', 2, "
        '23, 4102444800)',
      )
      // A conversation whose row was tombstoned while its message survived.
      ..execute(
        'INSERT INTO conversations '
        '(conversation_id, kind, list_projection_ciphertext, sort_key, '
        'tombstoned, pinned, unread_count) VALUES '
        "('conversation-tombstoned', 0, X'', 10, 1, 0, 0)",
      )
      ..execute(
        'INSERT INTO messages '
        '(message_id, conversation_id, current_event_id, '
        'projection_ciphertext, status, revision, created_at, ordering_ms) '
        "VALUES ('message-1', 'conversation-tombstoned', 'event-1', X'09', "
        '0, 0, 1000, 77)',
      )
      // And one whose row is gone entirely, which only a database written with
      // foreign keys disabled can reach — the defensive half of the repair.
      ..execute(
        'INSERT INTO messages '
        '(message_id, conversation_id, current_event_id, '
        'projection_ciphertext, status, revision, created_at, ordering_ms) '
        "VALUES ('message-2', 'conversation-orphaned', 'event-2', X'0A', "
        '0, 0, 2000, 512)',
      )
      ..execute('PRAGMA user_version = 13');
    raw.close();
  }

  Future<Map<String, Object?>> inspect(LocalDatabase database) async {
    final inbox = await database
        .customSelect(
          'SELECT envelope_id, processing_state, attempt_count, '
          'inspection_failures, next_attempt_at FROM inbox_envelopes '
          'ORDER BY sequence',
        )
        .get();
    final outbox = await database
        .customSelect(
          'SELECT attempt_state, attempt_count, next_attempt_at '
          'FROM outbox_operations',
        )
        .get();
    final conversations = await database
        .customSelect(
          'SELECT conversation_id, tombstoned, sort_key FROM conversations '
          'ORDER BY conversation_id',
        )
        .get();
    final messages = await database
        .customSelect('SELECT message_id FROM messages ORDER BY message_id')
        .get();
    return {
      'inbox': inbox.map((row) => row.data).toList(),
      'outbox': outbox.map((row) => row.data).toList(),
      'conversations': conversations.map((row) => row.data).toList(),
      'messages': messages.map((row) => row.data).toList(),
    };
  }

  test(
    'the schema-14 upgrade un-strands the queues and the projection',
    () async {
      await seedStrandedVersionThirteen();

      final database = LocalDatabase(NativeDatabase(file));
      final state = await inspect(database);

      final inbox = state['inbox']! as List<Map<String, Object?>>;
      final pending = inbox
          .where((row) => row['envelope_id'] != _uuid(3))
          .toList();
      expect(pending, hasLength(2));
      expect(
        pending.every((row) => row['processing_state'] == 0),
        isTrue,
        reason: 'nothing is left claimed by a run that is not happening',
      );
      expect(
        pending.every((row) => row['attempt_count'] == 0),
        isTrue,
        reason: 'the backoff these produce starts from one second again',
      );
      expect(
        pending.every((row) => row['next_attempt_at'] == null),
        isTrue,
        reason: 'and they are due now rather than in a quarter of an hour',
      );
      expect(
        pending.every((row) => row['inspection_failures'] == 0),
        isTrue,
        reason: 'the new budget applies from a clean base',
      );
      final acknowledged = inbox.singleWhere(
        (row) => row['envelope_id'] == _uuid(3),
      );
      expect(
        acknowledged['processing_state'],
        4,
        reason: 'an acknowledged envelope is not a stranded one',
      );

      final outbox = (state['outbox']! as List<Map<String, Object?>>).single;
      expect(outbox['attempt_state'], 0);
      expect(outbox['attempt_count'], 0);
      expect(
        outbox['next_attempt_at'],
        isNull,
        reason: 'the stranded probe message is due on the next cycle',
      );

      final conversations =
          state['conversations']! as List<Map<String, Object?>>;
      expect(conversations, hasLength(2));
      expect(
        conversations.every((row) => row['tombstoned'] == 0),
        isTrue,
        reason: 'a conversation with messages in it exists',
      );
      expect(
        conversations.singleWhere(
          (row) => row['conversation_id'] == 'conversation-orphaned',
        )['sort_key'],
        512,
        reason: 'the ordering key is recoverable from the messages themselves',
      );
      expect(
        (state['messages']! as List<Map<String, Object?>>).map(
          (row) => row['message_id'],
        ),
        ['message-1', 'message-2'],
        reason: 'and no message content was touched',
      );

      await database.close();
    },
  );

  test('running the repair a second time changes nothing', () async {
    await seedStrandedVersionThirteen();

    final first = LocalDatabase(NativeDatabase(file));
    final afterFirst = await inspect(first);
    // Something that must survive: a row the engine legitimately claimed
    // between the two runs.
    await first.customStatement(
      "UPDATE inbox_envelopes SET attempt_count = 1 WHERE envelope_id = '"
      "${_uuid(1)}'",
    );
    await first.customStatement('PRAGMA user_version = 13');
    await first.close();

    final second = LocalDatabase(NativeDatabase(file));
    final afterSecond = await inspect(second);

    expect(
      afterSecond['conversations'],
      afterFirst['conversations'],
      reason: 'the projection repair is a no-op once it has been applied',
    );
    expect(afterSecond['messages'], afterFirst['messages']);
    expect(
      afterSecond['inbox'],
      afterFirst['inbox'],
      reason: 'and re-deriving from a clean base is the same clean base',
    );
    expect(afterSecond['outbox'], afterFirst['outbox']);

    await second.close();
  });
}

String _uuid(int value) =>
    '00000000-0000-0000-0000-${value.toRadixString(16).padLeft(12, '0')}';

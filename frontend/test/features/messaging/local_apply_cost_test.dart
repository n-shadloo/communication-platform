import 'package:communication_platform/core/protocol/application_message_model.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:communication_platform/features/messaging/infrastructure/drift_application_event_projector.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_event_harness.dart';
import '../../support/counting_interceptor.dart';
import '../../support/local_send_harness.dart';

/// What applying one event costs, and what it used to cost.
///
/// Every authenticated application event re-projected its whole conversation
/// from the whole event log: read every candidate event, decode every body,
/// re-fold every message in five passes over the fact set, and rewrite every
/// message row along with its reactions and its receipts. So the cost of
/// receiving anything in a conversation was set by how long that conversation
/// was, and the worst case was the cheapest event there is — an inbound
/// receipt, which is one event per batch of messages.
///
/// These are *equal* assertions across two conversations of very different
/// lengths, in the discipline ADR-061 and ADR-062 established, so a rebuild
/// finding its way back onto the event path fails here loudly rather than
/// gradually. The rebuild is measured alongside them, through the recovery path
/// that still runs one, so the before and the after are two numbers this suite
/// produced rather than a number and an estimate.
void main() {
  // Two conversation lengths means two databases in one test.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('applying an event costs the same in a long conversation as in a '
      'short one', () async {
    // Both are long enough to contain the batch the multi-id receipt names, so
    // the comparison is between the same amount of work rather than between
    // thirty-two message ids and however many of them exist.
    final short = await _measure(48);
    final long = await _measure(1200);

    for (final kind in short.statements.keys) {
      expect(
        long.statements[kind],
        short.statements[kind],
        reason:
            '$kind: ${short.statements[kind]} statements at 48 messages, '
            '${long.statements[kind]} at 1200',
      );
    }

    // Absolute bounds as well, so a change that made every kind uniformly
    // expensive would still fail. Each is: read the facts about one message,
    // read the row it already has, write it back, and settle the conversation's
    // four aggregates.
    for (final entry in long.statements.entries) {
      if (entry.key == _receiptBatch) {
        continue;
      }
      expect(entry.value, lessThan(32), reason: entry.key);
    }

    // A receipt is the one kind whose cost is allowed to grow, and it grows
    // with what the receipt carries rather than with the conversation. Thirty
    // two message ids cost more than one, and less than thirty-two of the one.
    expect(
      long.statements[_receiptBatch]!,
      greaterThan(long.statements[_receiptOne]!),
    );
    expect(
      long.statements[_receiptBatch]!,
      lessThan(32 * long.statements[_receiptOne]!),
    );

    // And the comparison the phase is for. One rebuild of the long conversation
    // is what each of these used to be.
    expect(long.rebuild, greaterThan(30 * long.statements['messageCreate']!));
    expect(
      long.rebuildMicroseconds,
      greaterThan(10 * long.slowestSingleMessageMicroseconds),
      reason: long.report,
    );

    // Printed where a failure can be read, because the numbers are the point:
    // this is where ADR-063's table comes from.
    printOnFailure(short.report);
    printOnFailure(long.report);
  }, timeout: const Timeout(Duration(minutes: 6)));

  test('one reaction rewrites one message and nothing else', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await _seed(database, 24);
    // Receipts for every message, so there is something on every other message
    // that a whole-conversation rewrite would visibly disturb.
    final everything = [
      for (var index = 0; index < 24; index += 1) sequentialId(index),
    ];
    await applyCommit(
      database,
      applicationCommit(
        eventId: sequentialId(49000),
        kind: ApplicationEventKind.receiptRead,
        senderUser: localUserId,
        senderDevice: localDeviceId,
        counter: 1,
        references: everything,
        body: ReceiptBody(messageIds: everything),
      ),
    );
    final before = await database.select(database.messages).get();
    final receiptsBefore = await database.select(database.receipts).get();
    expect(receiptsBefore, hasLength(24));

    await applyCommit(
      database,
      applicationCommit(
        eventId: sequentialId(50000),
        kind: ApplicationEventKind.reactionSet,
        senderUser: peerUserId,
        senderDevice: secondPeerDeviceId,
        counter: 1,
        references: [sequentialId(2)],
        body: ReactionSetBody(
          targetMessageId: sequentialId(2),
          emoji: '\u{1F44D}',
        ),
      ),
    );

    // A reaction on one message used to re-delete and re-insert the receipts of
    // every other message in the thread, and rewrite every row that carried
    // them. Nothing moved: a reaction is not on the message row at all, and the
    // receipts are derived from a kind of fact a reaction cannot be.
    final after = await database.select(database.messages).get();
    expect(after, hasLength(before.length));
    for (final row in after) {
      final previous = before.firstWhere(
        (item) => item.messageId == row.messageId,
      );
      expect(row, previous, reason: row.messageId);
    }
    expect(
      await database.select(database.receipts).get(),
      receiptsBefore,
      reason: 'a reaction to one message is not a rewrite of every receipt',
    );
    expect(
      (await database.select(database.messageReactions).get()).single.messageId,
      protocolBytesToHex(sequentialId(2)),
    );
  });
}

const _receiptOne = 'receiptDelivered(1 id)';
const _receiptBatch = 'receiptRead(32 ids)';

/// Leaves [count] real peer messages in one real conversation.
Future<void> _seed(LocalDatabase database, int count) async {
  for (var index = 0; index < count; index += 1) {
    await applyCommit(
      database,
      applicationCommit(
        eventId: sequentialId(index),
        kind: ApplicationEventKind.messageCreate,
        senderUser: peerUserId,
        senderDevice: peerDeviceId,
        counter: index + 1,
        body: MessageCreateBody(
          messageId: sequentialId(index),
          text: 'message $index',
        ),
      ),
    );
  }
}

Future<_ApplyCost> _measure(int history) async {
  final counter = CountingInterceptor();
  final database = LocalDatabase(
    NativeDatabase.memory().interceptWith(counter),
  );
  addTearDown(database.close);
  await _seed(database, history);

  final statements = <String, int>{};
  final microseconds = <String, int>{};

  /// Applies [repetitions] events of one kind, counting the first and timing
  /// all of them.
  ///
  /// The statement count is a property of one apply and does not vary; the
  /// microseconds do, by enough that a single sample says more about when the
  /// process warmed up than about the work. The mean over a dozen is what the
  /// ADR quotes.
  Future<void> measure(
    String label,
    ApplicationEventCommit Function(int index) build, {
    int repetitions = 12,
  }) async {
    counter.reset();
    final clock = Stopwatch();
    for (var index = 0; index < repetitions; index += 1) {
      final commit = build(index);
      clock.start();
      final result = await applyCommit(database, commit);
      clock.stop();
      if (index == 0) {
        statements[label] = counter.statements;
      }
      expect(
        result.disposition,
        ApplicationApplyDisposition.applied,
        reason: '$label #$index',
      );
    }
    microseconds[label] = clock.elapsedMicroseconds ~/ repetitions;
  }

  // Sender counters continue the sequence the seed left, because a repeated
  // counter is a fork rather than a measurement.
  var peerCounter = history;
  int nextPeer() => ++peerCounter;
  var localCounter = 0;
  int nextLocal() => ++localCounter;

  await measure(
    'messageCreate',
    (index) => applicationCommit(
      eventId: sequentialId(10000 + index),
      kind: ApplicationEventKind.messageCreate,
      senderUser: peerUserId,
      senderDevice: peerDeviceId,
      counter: nextPeer(),
      body: MessageCreateBody(
        messageId: sequentialId(10000 + index),
        text: 'one more',
      ),
    ),
  );
  await measure(
    'messageEdit',
    (index) => applicationCommit(
      eventId: sequentialId(11000 + index),
      kind: ApplicationEventKind.messageEdit,
      senderUser: peerUserId,
      senderDevice: peerDeviceId,
      counter: nextPeer(),
      references: [sequentialId(0)],
      body: MessageEditBody(
        targetMessageId: sequentialId(0),
        replacementText: 'edited $index',
        revision: 2 + index,
      ),
    ),
  );
  await measure(
    'reactionSet',
    (index) => applicationCommit(
      eventId: sequentialId(12000 + index),
      kind: ApplicationEventKind.reactionSet,
      senderUser: peerUserId,
      senderDevice: peerDeviceId,
      counter: nextPeer(),
      references: [sequentialId(1)],
      body: ReactionSetBody(
        targetMessageId: sequentialId(1),
        emoji: '\u{1F44D}',
      ),
    ),
  );
  await measure(
    'pinSet',
    (index) => applicationCommit(
      eventId: sequentialId(13000 + index),
      kind: ApplicationEventKind.pinSet,
      senderUser: peerUserId,
      senderDevice: peerDeviceId,
      counter: nextPeer(),
      references: [sequentialId(2)],
      body: PinSetBody(targetMessageId: sequentialId(2), pinned: index.isEven),
    ),
  );
  await measure(
    'messageDelete',
    (index) => applicationCommit(
      eventId: sequentialId(14000 + index),
      kind: ApplicationEventKind.messageDelete,
      senderUser: peerUserId,
      senderDevice: peerDeviceId,
      counter: nextPeer(),
      references: [sequentialId(3 + index)],
      body: MessageDeleteBody(targetMessageId: sequentialId(3 + index)),
    ),
  );

  // Receipts come from this account, because a receipt only counts for a
  // message somebody else sent and every message here is the peer's.
  await measure(
    _receiptOne,
    (index) => applicationCommit(
      eventId: sequentialId(15000 + index),
      kind: ApplicationEventKind.receiptDelivered,
      senderUser: localUserId,
      senderDevice: localDeviceId,
      counter: nextLocal(),
      references: [sequentialId(20 + index)],
      body: ReceiptBody(messageIds: [sequentialId(20 + index)]),
    ),
  );
  final batch = [
    for (var index = 0; index < 32; index += 1) sequentialId(index),
  ];
  await measure(
    _receiptBatch,
    (index) => applicationCommit(
      eventId: sequentialId(16000 + index),
      kind: ApplicationEventKind.receiptRead,
      senderUser: localUserId,
      senderDevice: localDeviceId,
      counter: nextLocal(),
      references: batch,
      body: ReceiptBody(messageIds: batch),
    ),
  );

  // And the fold every one of those used to run.
  counter.reset();
  final clock = Stopwatch()..start();
  await rebuildConversation(database, harnessConversationId);
  clock.stop();

  return _ApplyCost(
    history: history,
    statements: statements,
    microseconds: microseconds,
    rebuild: counter.statements,
    rebuildMicroseconds: clock.elapsedMicroseconds,
  );
}

final class _ApplyCost {
  const _ApplyCost({
    required this.history,
    required this.statements,
    required this.microseconds,
    required this.rebuild,
    required this.rebuildMicroseconds,
  });

  final int history;
  final Map<String, int> statements;
  final Map<String, int> microseconds;

  /// One full projection of the same conversation, which every event ran.
  final int rebuild;
  final int rebuildMicroseconds;

  /// The dearest of the kinds that touch exactly one message.
  int get slowestSingleMessageMicroseconds => [
    for (final entry in microseconds.entries)
      if (entry.key != _receiptBatch) entry.value,
  ].reduce((left, right) => left > right ? left : right);

  String get report => [
    '$history messages:',
    for (final entry in statements.entries)
      '  ${entry.key.padRight(24)} ${entry.value} statements, '
          '${microseconds[entry.key]} us',
    '  ${'full rebuild'.padRight(24)} $rebuild statements, '
        '$rebuildMicroseconds us',
  ].join('\n');
}

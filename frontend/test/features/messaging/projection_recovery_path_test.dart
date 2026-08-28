import 'dart:convert';

import 'package:communication_platform/core/protocol/application_message_model.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:communication_platform/features/messaging/infrastructure/drift_application_event_projector.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_event_harness.dart';
import '../../support/local_send_harness.dart';

/// The full rebuild is still reached, and still right.
///
/// Three dispositions retire a fact the projection already contains — an event
/// id presented twice with different bytes, a sender counter replayed, and an
/// unsupported event claiming an id a stored event already has — and for all
/// three what the projection should now say is not a function of the event in
/// hand. Those keep the recovery path, and this is where that is asserted
/// rather than assumed.
///
/// Each test proves the *whole* conversation was re-derived, not just the
/// message the conflict was about, by tampering with an unrelated row first. A
/// value no fold would ever produce is written straight into `messages`; only a
/// rebuild puts it back. An incremental apply, which touches one message, would
/// leave it exactly where it was.
void main() {
  final first = applicationCommit(
    eventId: sequentialId(1),
    kind: ApplicationEventKind.messageCreate,
    senderUser: peerUserId,
    senderDevice: peerDeviceId,
    counter: 1,
    body: MessageCreateBody(messageId: sequentialId(1), text: 'first'),
  );
  final second = applicationCommit(
    eventId: sequentialId(2),
    kind: ApplicationEventKind.messageCreate,
    senderUser: peerUserId,
    senderDevice: peerDeviceId,
    counter: 2,
    body: MessageCreateBody(messageId: sequentialId(2), text: 'second'),
  );
  final third = applicationCommit(
    eventId: sequentialId(3),
    kind: ApplicationEventKind.messageCreate,
    senderUser: peerUserId,
    senderDevice: peerDeviceId,
    counter: 3,
    body: MessageCreateBody(messageId: sequentialId(3), text: 'third'),
  );

  late LocalDatabase database;

  setUp(() => database = LocalDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  /// Writes a message body no fold produces, so only a rebuild can remove it.
  Future<void> tamperWith(Uint8List messageId) async {
    final updated =
        await (database.update(database.messages)..where(
              (row) => row.messageId.equals(protocolBytesToHex(messageId)),
            ))
            .write(
              MessagesCompanion(
                projectionCiphertext: Value(
                  Uint8List.fromList(utf8.encode('tampered')),
                ),
              ),
            );
    expect(updated, 1);
  }

  Future<String?> textOf(Uint8List messageId) async {
    final row =
        await (database.select(database.messages)..where(
              (item) => item.messageId.equals(protocolBytesToHex(messageId)),
            ))
            .getSingleOrNull();
    return row == null ? null : utf8.decode(row.projectionCiphertext);
  }

  test('an event id presented twice re-derives the conversation', () async {
    for (final commit in [first, second, third]) {
      await applyCommit(database, commit);
    }
    await tamperWith(sequentialId(2));

    final conflict = ApplicationEventCommit(
      event: first.event,
      canonicalBytes: Uint8List.fromList([0xff, ...first.canonicalBytes]),
      currentUserId: first.currentUserId,
      currentDeviceId: first.currentDeviceId,
      conversationKind: first.conversationKind,
      peerUserId: first.peerUserId,
      localOrigin: first.localOrigin,
      authenticatedAt: first.authenticatedAt,
    );
    expect(
      (await applyCommit(database, conflict)).disposition,
      ApplicationApplyDisposition.eventIdConflict,
    );

    // The conflicting event is no longer a candidate, so its message is gone —
    // and the message nothing was said about is back to what the log says,
    // which is the rebuild's doing and nothing else's.
    expect(await textOf(sequentialId(1)), isNull);
    expect(await textOf(sequentialId(2)), 'second');
    expect(await textOf(sequentialId(3)), 'third');
    await expectAggregatesRecomputed(database);
  });

  test('a replayed sender counter re-derives the conversation', () async {
    for (final commit in [first, second, third]) {
      await applyCommit(database, commit);
    }
    await tamperWith(sequentialId(2));

    final replay = applicationCommit(
      eventId: sequentialId(4),
      kind: ApplicationEventKind.messageCreate,
      senderUser: peerUserId,
      senderDevice: peerDeviceId,
      counter: 1,
      body: MessageCreateBody(messageId: sequentialId(4), text: 'replayed'),
    );
    expect(
      (await applyCommit(database, replay)).disposition,
      ApplicationApplyDisposition.senderCounterRollback,
    );

    // Both events at the replayed counter are retired, so neither message is
    // projected; the other two are re-derived from the log.
    expect(await textOf(sequentialId(1)), isNull);
    expect(await textOf(sequentialId(4)), isNull);
    expect(await textOf(sequentialId(2)), 'second');
    expect(await textOf(sequentialId(3)), 'third');
    await expectAggregatesRecomputed(database);
  });

  test('an unsupported event claiming a stored id re-derives the '
      'conversation', () async {
    for (final commit in [first, second, third]) {
      await applyCommit(database, commit);
    }
    await tamperWith(sequentialId(2));

    await database.writeTransaction(
      () => DriftApplicationEventProjector(database)
          .retainUnsupportedInsideTransaction(
            UnsupportedApplicationCommit(
              recordKey: 'unsupported:1',
              version: 1,
              kindValue: 4096,
              senderUserId: peerUserId,
              senderDeviceId: peerDeviceId,
              eventId: sequentialId(1),
              conversationId: harnessConversationId,
              senderCounter: 1,
              currentUserId: localUserId,
              retainedBytes: Uint8List.fromList([0xa1, 0x00, 0x01, 0x01]),
              authenticatedAt: first.authenticatedAt,
            ),
          ),
    );

    expect(await textOf(sequentialId(1)), isNull);
    expect(await textOf(sequentialId(2)), 'second');
    expect(await textOf(sequentialId(3)), 'third');
    await expectAggregatesRecomputed(database);
  });

  test('a rebuild repairs the index the incremental path reads', () async {
    for (final commit in [first, second, third]) {
      await applyCommit(database, commit);
    }
    // As an interrupted back-fill would leave it, or a database written by a
    // build that did not have the table.
    await database.delete(database.applicationEventTargets).go();

    await rebuildConversation(database, harnessConversationId);
    expect(
      (await database.select(database.applicationEventTargets).get()).map(
        (row) => row.messageId,
      ),
      containsAll([
        for (final id in [1, 2, 3]) protocolBytesToHex(sequentialId(id)),
      ]),
    );

    // And the next incremental apply folds the history it just re-indexed.
    await applyCommit(
      database,
      applicationCommit(
        eventId: sequentialId(5),
        kind: ApplicationEventKind.messageEdit,
        senderUser: peerUserId,
        senderDevice: peerDeviceId,
        counter: 4,
        references: [sequentialId(2)],
        body: MessageEditBody(
          targetMessageId: sequentialId(2),
          replacementText: 'edited after repair',
          revision: 2,
        ),
      ),
    );
    expect(await textOf(sequentialId(2)), 'edited after repair');
  });

  test(
    'the recovery path is reachable, and is the projection it defines',
    () async {
      for (final commit in [first, second, third]) {
        await applyCommit(database, commit);
      }
      final before = await projectionSnapshot(database);
      await rebuildConversation(database, harnessConversationId);
      expect(
        await projectionSnapshot(database),
        before,
        reason: 'a rebuild over a correct projection is a no-op',
      );
    },
  );
}

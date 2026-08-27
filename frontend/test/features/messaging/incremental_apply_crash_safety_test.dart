import 'package:communication_platform/core/protocol/application_message_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_event_harness.dart';
import '../../support/local_send_harness.dart';
import '../../support/storage_fault_injection.dart';

/// What a process death inside one incremental apply leaves behind.
///
/// An incremental projection is only sound while it stays in the transaction
/// that stores the event it is a projection of. If the two could ever come
/// apart there would be a durable fact nothing folded, and no sweep to notice:
/// the recovery path is not run on the normal path any more, so nothing else
/// would ever look at that message again.
///
/// The same is true of the target index one layer down. An event whose target
/// rows did not commit with it is invisible to every later fold — a
/// mutation-before-create that never arrives, an edit that never applies —
/// which is worse than an event that is not there at all, because the
/// sender-counter check will refuse to store it a second time.
///
/// Every assertion is made against a reopened file rather than against objects
/// the interrupted run left behind, and the reopen runs the production
/// `beforeOpen` path, whose `PRAGMA quick_check` fails the test if the aborted
/// write left the file inconsistent.
void main() {
  late RestartableDatabase restartable;
  late StorageFaultInjector faults;

  setUp(() async {
    restartable = await RestartableDatabase.create('cp-incremental-apply-');
    faults = StorageFaultInjector(restartable.database);
  });

  tearDown(() => restartable.dispose());

  final create = applicationCommit(
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
  final receipt = applicationCommit(
    eventId: sequentialId(3),
    kind: ApplicationEventKind.receiptRead,
    senderUser: localUserId,
    senderDevice: localDeviceId,
    counter: 1,
    references: [sequentialId(1), sequentialId(2)],
    body: ReceiptBody(messageIds: [sequentialId(1), sequentialId(2)]),
  );

  /// What the same three events produce with nothing interrupting them.
  Future<String> uninterrupted() async {
    final clean = await RestartableDatabase.create('cp-incremental-clean-');
    addTearDown(clean.dispose);
    for (final commit in [create, second, receipt]) {
      await applyCommit(clean.database, commit);
    }
    return projectionSnapshot(clean.database);
  }

  test('a death while projecting leaves neither the event nor its '
      'index', () async {
    final expected = await uninterrupted();
    await applyCommit(restartable.database, create);
    await faults.failOn('messages', InjectedWrite.insert);

    await expectLater(
      applyCommit(restartable.database, second),
      throwsA(anything),
    );

    await faults.repair();
    final reopened = await restartable.restart();
    // Not the event, not its target rows, not the message, and not the
    // conversation's aggregates: one transaction, one outcome.
    expect(
      await (reopened.select(reopened.storedApplicationEvents)..where(
            (row) => row.eventId.equals(protocolBytesToHex(sequentialId(2))),
          ))
          .get(),
      isEmpty,
    );
    expect(
      await (reopened.select(reopened.applicationEventTargets)..where(
            (row) => row.eventId.equals(protocolBytesToHex(sequentialId(2))),
          ))
          .get(),
      isEmpty,
    );
    expect(await reopened.select(reopened.messages).get(), hasLength(1));

    // And re-presenting it converges, which is what the sync engine does after
    // a crash between commit and acknowledgement.
    await applyCommit(reopened, second);
    await applyCommit(reopened, receipt);
    expect(await projectionSnapshot(reopened), expected);
  });

  test(
    'a death while indexing an event rolls the event back with it',
    () async {
      final expected = await uninterrupted();
      await applyCommit(restartable.database, create);
      await applyCommit(restartable.database, second);
      await faults.failOn('application_event_targets', InjectedWrite.insert);

      // A receipt writes one index row per message it names. Failing on them is
      // the one interruption that could leave a stored event no later fold can
      // see — and the sender-counter check would then refuse to store it again.
      await expectLater(
        applyCommit(restartable.database, receipt),
        throwsA(anything),
      );

      await faults.repair();
      final reopened = await restartable.restart();
      expect(
        await (reopened.select(reopened.storedApplicationEvents)..where(
              (row) => row.eventId.equals(protocolBytesToHex(sequentialId(3))),
            ))
            .get(),
        isEmpty,
        reason: 'an event without its index is not an event',
      );
      expect(await reopened.select(reopened.receipts).get(), isEmpty);

      await applyCommit(reopened, receipt);
      expect(await projectionSnapshot(reopened), expected);
    },
  );

  test('a death part way through a multi-message receipt projects none of '
      'it', () async {
    final expected = await uninterrupted();
    await applyCommit(restartable.database, create);
    await applyCommit(restartable.database, second);
    // The second of the two messages the receipt names, so the fault lands
    // between two writes one transaction makes to the same table.
    await faults.failOn(
      'receipts',
      InjectedWrite.insert,
      when: "NEW.message_id = '${protocolBytesToHex(sequentialId(2))}'",
    );

    await expectLater(
      applyCommit(restartable.database, receipt),
      throwsA(anything),
    );

    await faults.repair();
    final reopened = await restartable.restart();
    expect(
      await reopened.select(reopened.receipts).get(),
      isEmpty,
      reason: 'the first message\'s receipt went back with the second',
    );

    await applyCommit(reopened, receipt);
    expect(await reopened.select(reopened.receipts).get(), hasLength(2));
    expect(await projectionSnapshot(reopened), expected);
  });
}

import 'package:communication_platform/core/protocol/application_message_model.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:communication_platform/features/messaging/domain/conversation_model.dart';
import 'package:communication_platform/features/pairwise/infrastructure/drift_pairwise_transport_store.dart';
import 'package:communication_platform/features/synchronization/domain/sync_model.dart';
import 'package:communication_platform/features/synchronization/infrastructure/drift_sync_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/local_send_harness.dart';
import '../../support/storage_fault_injection.dart';

/// The window local echo opens, and what a process death inside it leaves.
///
/// Before this change there was no window: one transaction both projected the
/// message and wrote its ciphertext, so a message the user could see and a
/// message with a route to the wire were the same thing. Now they are two
/// transactions, and the whole of what makes that safe is the durable request
/// between them — which is why every assertion here is made against a
/// reopened file rather than against objects the interrupted run left behind.
void main() {
  late RestartableDatabase restartable;
  late StorageFaultInjector faults;

  setUp(() async {
    restartable = await RestartableDatabase.create('cp-local-echo-');
    faults = StorageFaultInjector(restartable.database);
    await seedDeviceState(restartable.database);
  });

  tearDown(() => restartable.dispose());

  final commit = localMessageCommit(seed: 40, counter: 1);
  final eventId = protocolBytesToHex(commit.event.eventId);
  final operationId = 'application:$eventId';

  Future<void> echo(LocalDatabase database) async {
    expect(
      await DriftPairwiseTransportStore(database).commitLocalEcho(
        operationId: operationId,
        eventId: eventId,
        currentUserId: localUserId,
        currentDeviceId: localDeviceId,
        peerUserId: peerUserId,
        openedLocalPayload: commit.canonicalBytes,
        applicationEvent: commit,
      ),
      isA<Success<void>>(),
    );
  }

  Future<void> expectOwedAndVisible(LocalDatabase database) async {
    final message = await database.select(database.messages).getSingle();
    expect(message.messageId, eventId);
    expect(message.status, MessageTransportState.preparing.index);
    final owed = await database.select(database.pendingSendPreparations).get();
    expect(owed, hasLength(1));
    expect(owed.single.operationId, operationId);
    expect(owed.single.state, 0);
    expect(await database.select(database.outboxOperations).get(), isEmpty);
  }

  test('a death while sealing leaves the message owed, not stranded', () async {
    await echo(restartable.database);
    await faults.failOn('outbox_operations', InjectedWrite.insert);

    final sealed = await DriftPairwiseTransportStore(
      restartable.database,
    ).commitPreparedSend(sealedSendFor(commit));

    expect(sealed, isA<FailureResult<void>>());
    // Nothing the failed attempt touched survived it: no ciphertext, and no
    // ratchet step either, because both were in the transaction that aborted.
    expect(
      await restartable.database
          .select(restartable.database.pairwiseSessions)
          .get(),
      isEmpty,
    );

    final database = await restartable.restart();
    await expectOwedAndVisible(database);

    // And the delivery cycle asks for it again, unprompted, as the work it is.
    final owed = await DriftSyncStore(
      database,
    ).beginNextSendPreparation(now: DateTime.utc(2026));
    final work = (owed as Success<PendingSendPreparation?>).value;
    expect(work, isNotNull);
    expect(work!.operationId, operationId);
    expect(work.peerUserId, peerUserId);
    expect(work.attempt, 1);
  });

  test('a death while retiring the request leaves nothing half done', () async {
    await echo(restartable.database);
    await faults.failOn('pending_send_preparations', InjectedWrite.delete);

    final sealed = await DriftPairwiseTransportStore(
      restartable.database,
    ).commitPreparedSend(sealedSendFor(commit));

    expect(sealed, isA<FailureResult<void>>());

    final database = await restartable.restart();
    // Never both: the ciphertext went back with the request that owed it, so
    // the retry cannot queue a second copy of this message.
    await expectOwedAndVisible(database);
  });

  test(
    'the sealed commit and the retired request are one transaction',
    () async {
      await echo(restartable.database);

      expect(
        await DriftPairwiseTransportStore(
          restartable.database,
        ).commitPreparedSend(sealedSendFor(commit)),
        isA<Success<void>>(),
      );

      final database = await restartable.restart();
      expect(
        await database.select(database.pendingSendPreparations).get(),
        isEmpty,
      );
      expect(
        await database.select(database.outboxOperations).get(),
        hasLength(1),
      );
      final message = await database.select(database.messages).getSingle();
      expect(message.status, MessageTransportState.queued.index);

      // And nothing is owed any more, so the cycle stops asking.
      final owed = await DriftSyncStore(
        database,
      ).beginNextSendPreparation(now: DateTime.utc(2026));
      expect((owed as Success<PendingSendPreparation?>).value, isNull);
    },
  );

  test('a death while projecting leaves no message and no request', () async {
    await faults.failOn('messages', InjectedWrite.insert);

    final echoed = await DriftPairwiseTransportStore(restartable.database)
        .commitLocalEcho(
          operationId: operationId,
          eventId: eventId,
          currentUserId: localUserId,
          currentDeviceId: localDeviceId,
          peerUserId: peerUserId,
          openedLocalPayload: commit.canonicalBytes,
          applicationEvent: commit,
        );

    expect(echoed, isA<FailureResult<void>>());

    final database = await restartable.restart();
    // Never neither, from the other side: a request is only owed for a message
    // that exists, so a failed echo leaves nothing for the cycle to send.
    expect(await database.select(database.messages).get(), isEmpty);
    expect(
      await database.select(database.pendingSendPreparations).get(),
      isEmpty,
    );
    expect(
      await database.select(database.storedApplicationEvents).get(),
      isEmpty,
    );
    expect(
      await database.select(database.pairwiseLocalApplications).get(),
      isEmpty,
    );
  });
}

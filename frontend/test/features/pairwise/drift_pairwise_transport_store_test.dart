import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:communication_platform/features/pairwise/domain/pairwise_model.dart';
import 'package:communication_platform/features/pairwise/infrastructure/drift_pairwise_transport_store.dart';
import 'package:communication_platform/features/synchronization/domain/sync_model.dart';
import 'package:communication_platform/features/synchronization/infrastructure/drift_sync_store.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LocalDatabase database;
  late DriftPairwiseTransportStore store;

  setUp(() async {
    database = LocalDatabase(NativeDatabase.memory());
    store = DriftPairwiseTransportStore(database);
    await database
        .into(database.secureSecrets)
        .insert(
          SecureSecretsCompanion.insert(
            secretId: 'current-device-key-state-v1',
            kind: 0,
            wrappedCiphertextOrOpaqueHandle: bytes(8, 1),
            formatVersion: 2,
          ),
        );
  });

  tearDown(() => database.close());

  test(
    'send commits CAS states, exact targets, and local marker atomically',
    () async {
      final commit = sendCommit(targets: [2, 1]);

      final first = await store.commitPreparedSend(commit);
      final retry = await store.commitPreparedSend(commit);

      expect(first, isA<Success<void>>());
      expect(retry, isA<Success<void>>());
      final sessions = await database.select(database.pairwiseSessions).get();
      expect(sessions, hasLength(2));
      expect(sessions.every((row) => row.stateVersion == 1), isTrue);
      final outbox = await (database.select(
        database.outboxOperations,
      )..orderBy([(row) => OrderingTerm.asc(row.recipientDeviceId)])).get();
      expect(outbox.map((row) => row.recipientDeviceId), [uuid(1), uuid(2)]);
      expect(outbox[0].exactRecipientCiphertext, envelope(1));
      expect(outbox[1].exactRecipientCiphertext, envelope(2));
      expect(
        await database.select(database.pairwiseLocalApplications).get(),
        hasLength(1),
      );

      final changed = sendCommit(targets: [2, 1], ciphertextOffset: 10);
      final conflict = await store.commitPreparedSend(changed);
      expect(
        (conflict as FailureResult<void>).failure,
        isA<ValidationFailure>(),
      );
      expect(
        await database.select(database.pairwiseSessions).get(),
        hasLength(2),
      );
    },
  );

  test('send fault rolls back session, local marker, and all targets', () async {
    await database.customStatement(
      "CREATE TRIGGER fail_pairwise_outbox BEFORE INSERT ON outbox_operations "
      "BEGIN SELECT RAISE(ABORT, 'fault'); END",
    );

    final result = await store.commitPreparedSend(sendCommit(targets: [1, 2]));

    expect(result, isA<FailureResult<void>>());
    expect(await database.select(database.pairwiseSessions).get(), isEmpty);
    expect(await database.select(database.outboxOperations).get(), isEmpty);
    expect(
      await database.select(database.pairwiseLocalApplications).get(),
      isEmpty,
    );
  });

  test('per-session and account skipped-key limits fail closed', () async {
    final invalid = sendCommit(targets: [1], skippedKeyCount: 2001);
    expect(
      (await store.commitPreparedSend(invalid) as FailureResult<void>).failure,
      isA<ValidationFailure>(),
    );

    for (var index = 10; index < 20; index += 1) {
      await database
          .into(database.pairwiseSessions)
          .insert(
            PairwiseSessionsCompanion.insert(
              localDeviceId: uuid(900),
              remoteUserId: const Value('account-limit-user'),
              remoteDeviceId: uuid(index),
              sessionId: Value(sessionId(index)),
              opaqueCryptoStateHandle: bytes(8, index),
              stateVersion: 1,
              skippedKeyCount: const Value(2000),
            ),
          );
    }

    final accountOverflow = await store.commitPreparedSend(
      sendCommit(targets: [30], skippedKeyCount: 1),
    );
    expect(
      (accountOverflow as FailureResult<void>).failure,
      isA<StorageFailure>().having(
        (failure) => failure.kind,
        'kind',
        StorageFailureKind.capacityExceeded,
      ),
    );
    expect(await database.select(database.outboxOperations).get(), isEmpty);
  });

  test(
    'receive atomically advances states, deletes OTPKs, records replay, and readies ack',
    () async {
      final sync = DriftSyncStore(database);
      await inspectEnvelope(sync, 50);
      await database
          .into(database.prekeys)
          .insert(
            PrekeysCompanion.insert(
              kind: 1,
              keyId: 5,
              privateStateHandle: bytes(8, 5),
              uploadState: 1,
              useState: 0,
            ),
          );
      await database
          .into(database.prekeys)
          .insert(
            PrekeysCompanion.insert(
              kind: 3,
              keyId: 7,
              privateStateHandle: bytes(8, 7),
              uploadState: 1,
              useState: 0,
            ),
          );
      final commit = receiveCommit(
        envelopeNumber: 50,
        stateMarker: 2,
        replayMarker: bytes(32, 9),
        deviceState: PairwiseDeviceStateTransition(
          nextOpaqueState: bytes(16, 2),
          expectedStateVersion: 1,
          nextStateVersion: 2,
        ),
        consumed: const [
          ConsumedPairwiseOneTimePrekey(
            kind: PairwiseOneTimePrekeyKind.classicalX25519,
            keyId: 5,
          ),
          ConsumedPairwiseOneTimePrekey(
            kind: PairwiseOneTimePrekeyKind.postQuantumMlKem768,
            keyId: 7,
          ),
        ],
        signedPrekeyId: 20,
        pqSignedPrekeyId: 21,
      );

      final result = await store.commitPreparedReceive(commit);

      expect(result, isA<Success<bool>>());
      expect((result as Success<bool>).value, isTrue);
      expect(
        (await database.select(database.pairwiseSessions).getSingle())
            .stateVersion,
        1,
      );
      final secret = await database.select(database.secureSecrets).getSingle();
      expect(secret.stateRevision, 2);
      expect(secret.wrappedCiphertextOrOpaqueHandle, bytes(16, 2));
      expect(await database.select(database.prekeys).get(), isEmpty);
      expect(
        await database.select(database.pairwiseConsumedPrekeys).get(),
        hasLength(2),
      );
      final replay = await database
          .select(database.pairwiseReplayMarkers)
          .getSingle();
      expect(replay.signedPrekeyId, 20);
      expect(replay.pqSignedPrekeyId, 21);
      expect(
        await database.select(database.pairwiseOpenedPayloads).get(),
        hasLength(1),
      );
      expect(
        (await database.select(database.inboxEnvelopes).getSingle())
            .readyToAcknowledge,
        isTrue,
      );
    },
  );

  test(
    'replay marker rejection does not advance state or ready the envelope',
    () async {
      final sync = DriftSyncStore(database);
      await inspectEnvelope(sync, 60);
      await store.commitPreparedReceive(
        receiveCommit(
          envelopeNumber: 60,
          stateMarker: 1,
          replayMarker: bytes(32, 8),
        ),
      );
      await inspectEnvelope(sync, 61);

      final replay = await store.commitPreparedReceive(
        receiveCommit(
          envelopeNumber: 61,
          stateMarker: 2,
          replayMarker: bytes(32, 8),
          expectedStateVersion: 1,
        ),
      );

      expect(
        (replay as FailureResult<bool>).failure,
        isA<SecurityFailure>().having(
          (failure) => failure.kind,
          'kind',
          SecurityFailureKind.integrityCheckFailed,
        ),
      );
      expect(
        (await database.select(database.pairwiseSessions).getSingle())
            .stateVersion,
        1,
      );
      final envelopeRow = await (database.select(
        database.inboxEnvelopes,
      )..where((row) => row.envelopeId.equals(uuid(61)))).getSingle();
      expect(
        envelopeRow.processingState,
        InboxProcessingState.inspecting.index,
      );
      expect(envelopeRow.readyToAcknowledge, isFalse);
    },
  );

  test(
    'receive fault rolls back ratchet, device state, replay, and OTPK deletion',
    () async {
      final sync = DriftSyncStore(database);
      await inspectEnvelope(sync, 70);
      await database
          .into(database.prekeys)
          .insert(
            PrekeysCompanion.insert(
              kind: 1,
              keyId: 3,
              privateStateHandle: bytes(8, 3),
              uploadState: 1,
              useState: 0,
            ),
          );
      await database.customStatement(
        "CREATE TRIGGER fail_opened BEFORE INSERT ON pairwise_opened_payloads "
        "BEGIN SELECT RAISE(ABORT, 'fault'); END",
      );

      final result = await store.commitPreparedReceive(
        receiveCommit(
          envelopeNumber: 70,
          stateMarker: 3,
          replayMarker: bytes(32, 3),
          deviceState: PairwiseDeviceStateTransition(
            nextOpaqueState: bytes(16, 3),
            expectedStateVersion: 1,
            nextStateVersion: 2,
          ),
          consumed: const [
            ConsumedPairwiseOneTimePrekey(
              kind: PairwiseOneTimePrekeyKind.classicalX25519,
              keyId: 3,
            ),
          ],
        ),
      );

      expect(result, isA<FailureResult<bool>>());
      expect(await database.select(database.pairwiseSessions).get(), isEmpty);
      expect(
        (await database.select(database.secureSecrets).getSingle())
            .stateRevision,
        1,
      );
      expect(await database.select(database.prekeys).get(), hasLength(1));
      expect(
        await database.select(database.pairwiseReplayMarkers).get(),
        isEmpty,
      );
      expect(
        (await database.select(database.inboxEnvelopes).getSingle())
            .processingState,
        InboxProcessingState.inspecting.index,
      );
    },
  );

  test(
    'simultaneous initiation retains one alternate until primary traffic',
    () async {
      await store.commitPreparedSend(sendCommit(targets: [80]));
      final sync = DriftSyncStore(database);
      await inspectEnvelope(sync, 81);
      await store.commitPreparedReceive(
        receiveCommit(
          envelopeNumber: 81,
          remoteDeviceNumber: 80,
          senderUserId: 'peer-user',
          sessionNumber: 81,
          stateMarker: 8,
          replayMarker: bytes(32, 8),
          deviceState: PairwiseDeviceStateTransition(
            nextOpaqueState: bytes(16, 8),
            expectedStateVersion: 1,
            nextStateVersion: 2,
          ),
          signedPrekeyId: 30,
          pqSignedPrekeyId: 31,
        ),
      );

      expect(
        (await database.select(database.pairwiseSessions).getSingle())
            .sessionId,
        sessionId(81),
      );
      expect(
        (await database.select(database.pairwiseSessionAlternates).getSingle())
            .sessionId,
        sessionId(80),
      );

      await inspectEnvelope(sync, 82);
      await store.commitPreparedReceive(
        receiveCommit(
          envelopeNumber: 82,
          remoteDeviceNumber: 80,
          senderUserId: 'peer-user',
          sessionNumber: 81,
          stateMarker: 9,
          replayMarker: bytes(32, 9),
          expectedStateVersion: 1,
        ),
      );
      expect(
        await database.select(database.pairwiseSessionAlternates).get(),
        isEmpty,
      );
    },
  );

  test(
    'authenticated repair replacement erases the exact old session',
    () async {
      await database
          .into(database.pairwiseSessions)
          .insert(
            PairwiseSessionsCompanion.insert(
              localDeviceId: uuid(900),
              remoteUserId: const Value('sender-user'),
              remoteDeviceId: uuid(500),
              sessionId: Value(sessionId(500)),
              opaqueCryptoStateHandle: bytes(32, 5),
              stateVersion: 3,
        repairState: Value(
          PairwiseRepairState.authenticatedRequestPending.index,
        ),
            ),
          );
      final sync = DriftSyncStore(database);
      await inspectEnvelope(sync, 83);

      final result = await store.commitPreparedReceive(
        receiveCommit(
          envelopeNumber: 83,
          sessionNumber: 501,
          stateMarker: 8,
          replayMarker: bytes(32, 8),
          replacedSessionId: sessionId(500),
          deviceState: PairwiseDeviceStateTransition(
            nextOpaqueState: bytes(16, 8),
            expectedStateVersion: 1,
            nextStateVersion: 2,
          ),
          signedPrekeyId: 40,
          pqSignedPrekeyId: 41,
        ),
      );

      expect(result, isA<Success<bool>>());
      expect(
        (await database.select(database.pairwiseSessions).getSingle())
            .sessionId,
        sessionId(501),
      );
      expect(
        await database.select(database.pairwiseSessionAlternates).get(),
        isEmpty,
      );
    },
  );

  test(
    'verified revocation removes sessions and stales pending targets',
    () async {
      await store.commitPreparedSend(sendCommit(targets: [90]));

      final result = await store.reconcileRemoteLiveDevices(
        remoteUserId: 'peer-user',
        liveDeviceIds: const {},
      );

      expect(result, isA<Success<void>>());
      expect(await database.select(database.pairwiseSessions).get(), isEmpty);
      expect(
        (await database.select(database.outboxOperations).getSingle())
            .attemptState,
        OutboxAttemptState.stale.index,
      );
    },
  );

  test(
    'initial replay markers survive TTL until both signed keys are erased',
    () async {
      final old = DateTime.utc(2026, 7, 1);
      await database
          .into(database.pairwiseReplayMarkers)
          .insert(
            PairwiseReplayMarkersCompanion.insert(
              replayMarker: bytes(32, 1),
              sessionId: sessionId(1),
              signedPrekeyId: const Value(10),
              pqSignedPrekeyId: const Value(11),
              firstEnvelopeId: uuid(1),
              committedAt: Value(old),
            ),
          );
      await database
          .into(database.pairwiseReplayMarkers)
          .insert(
            PairwiseReplayMarkersCompanion.insert(
              replayMarker: bytes(32, 2),
              sessionId: sessionId(2),
              firstEnvelopeId: uuid(2),
              committedAt: Value(old),
            ),
          );

      await store.pruneRetainedMetadata(now: DateTime.utc(2026, 7, 29));
      var markers = await database.select(database.pairwiseReplayMarkers).get();
      expect(markers, hasLength(1));
      expect(markers.single.signedPrekeyId, 10);

      await store.pruneRetainedMetadata(
        now: DateTime.utc(2026, 7, 29),
        erasedSignedPrekeys: const [
          ErasedPairwiseSignedPrekeyPair(
            signedPrekeyId: 10,
            pqSignedPrekeyId: 11,
          ),
        ],
      );
      markers = await database.select(database.pairwiseReplayMarkers).get();
      expect(markers, isEmpty);
    },
  );
}

PairwiseSendCommit sendCommit({
  required List<int> targets,
  int ciphertextOffset = 0,
  int skippedKeyCount = 0,
}) => PairwiseSendCommit(
  operationId: 'pairwise-operation',
  eventId: 'pairwise-event',
  currentDeviceId: uuid(900),
  expectedDeviceStateVersion: 1,
  openedLocalPayload: bytes(16, 4),
  targets: [
    for (final number in targets)
      PreparedPairwiseSendTarget(
        recipientUserId: 'peer-user',
        recipientDeviceId: uuid(number),
        exactCiphertext: envelope(number + ciphertextOffset),
        sessionTransition: PairwiseSessionTransition(
          localDeviceId: uuid(900),
          remoteUserId: 'peer-user',
          remoteDeviceId: uuid(number),
          sessionId: sessionId(number),
          nextOpaqueState: bytes(32, number),
          expectedStateVersion: null,
          nextStateVersion: 1,
          nextSkippedKeyCount: skippedKeyCount,
          disposition: PairwiseSessionDisposition.primaryBidirectional,
          repairState: PairwiseRepairState.ready,
        ),
      ),
  ],
);

PairwiseReceiveCommit receiveCommit({
  required int envelopeNumber,
  required int stateMarker,
  required Uint8List replayMarker,
  int remoteDeviceNumber = 500,
  String senderUserId = 'sender-user',
  int? sessionNumber,
  int? expectedStateVersion,
  PairwiseDeviceStateTransition? deviceState,
  List<ConsumedPairwiseOneTimePrekey> consumed = const [],
  int? signedPrekeyId,
  int? pqSignedPrekeyId,
  Uint8List? replacedSessionId,
}) => PairwiseReceiveCommit(
  envelopeId: uuid(envelopeNumber),
  opaqueEventId: 'opaque-event-$envelopeNumber',
  senderUserId: senderUserId,
  senderDeviceId: uuid(remoteDeviceNumber),
  replayMarker: replayMarker,
  openedOpaquePayload: bytes(16, envelopeNumber),
  signedPrekeyId: signedPrekeyId,
  pqSignedPrekeyId: pqSignedPrekeyId,
  replacedSessionId: replacedSessionId,
  sessionTransition: PairwiseSessionTransition(
    localDeviceId: uuid(900),
    remoteUserId: senderUserId,
    remoteDeviceId: uuid(remoteDeviceNumber),
    sessionId: sessionId(sessionNumber ?? remoteDeviceNumber),
    nextOpaqueState: bytes(32, stateMarker),
    expectedStateVersion: expectedStateVersion,
    nextStateVersion: (expectedStateVersion ?? 0) + 1,
    nextSkippedKeyCount: 0,
    disposition: PairwiseSessionDisposition.primaryBidirectional,
    repairState: PairwiseRepairState.ready,
  ),
  deviceStateTransition: deviceState,
  consumedOneTimePrekeys: consumed,
);

Future<void> inspectEnvelope(DriftSyncStore sync, int number) async {
  await sync.persistDrainPage(
    DrainPage(
      envelopes: [
        SyncEnvelope(
          id: uuid(number),
          sequence: number,
          exactCiphertext: envelope(number),
        ),
      ],
      hasMore: false,
      prunedThrough: 0,
    ),
  );
  await sync.beginNextEnvelopeInspection(now: DateTime.utc(2026, 7, 29));
}

String uuid(int value) =>
    '00000000-0000-0000-0000-${value.toRadixString(16).padLeft(12, '0')}';

Uint8List sessionId(int marker) => bytes(16, marker);

Uint8List envelope(int marker) => bytes(1024, marker);

Uint8List bytes(int length, int marker) =>
    Uint8List.fromList(List<int>.filled(length, marker & 0xff));

import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:communication_platform/features/messaging/infrastructure/drift_application_event_projector.dart';
import 'package:communication_platform/features/pairwise/domain/pairwise_model.dart';
import 'package:communication_platform/features/pairwise/infrastructure/drift_pairwise_transport_store.dart';
import 'package:communication_platform/features/synchronization/application/ports/sync_ports.dart';
import 'package:communication_platform/features/synchronization/domain/sync_model.dart';
import 'package:drift/drift.dart';

final class DriftSyncStore implements DurableSyncStore {
  const DriftSyncStore(
    this.database, {
    this.maximumInboxEntries = 10000,
    this.maximumOutboxTargets = 50000,
  }) : assert(maximumInboxEntries > 0),
       assert(maximumOutboxTargets > 0);

  final LocalDatabase database;
  final int maximumInboxEntries;
  final int maximumOutboxTargets;

  @override
  Stream<SyncProjection> watchProjection() async* {
    await _ensureCheckpoint();
    final query = database.customSelect(
      '''
SELECT
  c.highest_contiguous_acked_sequence,
  c.pruned_through,
  c.queue_gap_state,
  c.connection_phase,
  c.reconnect_at,
  c.last_successful_sync_at,
  (SELECT COUNT(*) FROM inbox_envelopes WHERE processing_state != 4) AS inbox_depth,
  (SELECT COUNT(*) FROM outbox_operations WHERE attempt_state IN (0, 1, 2)) AS outbox_depth,
  (SELECT MIN(candidate) FROM (
    SELECT next_attempt_at AS candidate FROM inbox_envelopes
      WHERE processing_state IN (0, 1, 2, 3) AND next_attempt_at IS NOT NULL
    UNION ALL
    SELECT next_attempt_at AS candidate FROM outbox_operations
      WHERE attempt_state IN (0, 1, 2) AND next_attempt_at IS NOT NULL
    UNION ALL
    SELECT reconnect_at AS candidate FROM sync_checkpoint
      WHERE reconnect_at IS NOT NULL
  )) AS next_retry_at
FROM sync_checkpoint c
WHERE c.singleton_id = 1
''',
      readsFrom: {
        database.syncCheckpoints,
        database.inboxEnvelopes,
        database.outboxOperations,
      },
    );
    yield* query.watchSingle().map(_projectionFromRow);
  }

  @override
  Future<Result<SyncProjection>> readProjection() async {
    try {
      await _ensureCheckpoint();
      final row = await database.customSelect('''
SELECT
  c.highest_contiguous_acked_sequence,
  c.pruned_through,
  c.queue_gap_state,
  c.connection_phase,
  c.reconnect_at,
  c.last_successful_sync_at,
  (SELECT COUNT(*) FROM inbox_envelopes WHERE processing_state != 4) AS inbox_depth,
  (SELECT COUNT(*) FROM outbox_operations WHERE attempt_state IN (0, 1, 2)) AS outbox_depth,
  (SELECT MIN(candidate) FROM (
    SELECT next_attempt_at AS candidate FROM inbox_envelopes
      WHERE processing_state IN (0, 1, 2, 3) AND next_attempt_at IS NOT NULL
    UNION ALL
    SELECT next_attempt_at AS candidate FROM outbox_operations
      WHERE attempt_state IN (0, 1, 2) AND next_attempt_at IS NOT NULL
    UNION ALL
    SELECT reconnect_at AS candidate FROM sync_checkpoint
      WHERE reconnect_at IS NOT NULL
  )) AS next_retry_at
FROM sync_checkpoint c
WHERE c.singleton_id = 1
''').getSingle();
      return Result.success(_projectionFromRow(row));
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }

  @override
  Future<Result<void>> queuePreparedOperation({
    required String operationId,
    required String eventId,
    required List<PreparedOutboxTarget> targets,
  }) async {
    if (operationId.isEmpty ||
        eventId.isEmpty ||
        targets.isEmpty ||
        targets.any(
          (target) =>
              !_isUuid(target.recipientDeviceId) ||
              target.recipientUserId.isEmpty ||
              !_isEnvelopeBucket(target.exactCiphertext.length),
        )) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    final sorted = List<PreparedOutboxTarget>.of(targets)
      ..sort(
        (left, right) =>
            _compareUuidBytes(left.recipientDeviceId, right.recipientDeviceId),
      );
    if (sorted
            .map((target) => target.recipientDeviceId.toLowerCase())
            .toSet()
            .length !=
        sorted.length) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.conflict),
      );
    }
    try {
      await database.writeTransaction(() async {
        final existing = await (database.select(
          database.outboxOperations,
        )..where((row) => row.operationId.equals(operationId))).get();
        if (existing.isNotEmpty) {
          if (existing.any((row) => row.eventId != eventId) ||
              !_samePreparedTargets(existing, sorted)) {
            throw const _SyncConflict();
          }
          return;
        }
        final currentCount = await _count(database.outboxOperations);
        if (currentCount + sorted.length > maximumOutboxTargets) {
          throw const _SyncCapacity();
        }
        for (var index = 0; index < sorted.length; index += 1) {
          final target = sorted[index];
          await database
              .into(database.outboxOperations)
              .insert(
                OutboxOperationsCompanion.insert(
                  operationId: operationId,
                  eventId: eventId,
                  recipientDeviceId: target.recipientDeviceId.toLowerCase(),
                  recipientUserId: Value(target.recipientUserId),
                  batchIndex: index ~/ 256,
                  exactRecipientCiphertext: target.exactCiphertext,
                  attemptState: OutboxAttemptState.queued.index,
                ),
              );
        }
      });
      return const Result.success(null);
    } on _SyncConflict {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.conflict),
      );
    } on _SyncCapacity {
      return const Result.failure(
        StorageFailure(StorageFailureKind.capacityExceeded),
      );
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }

  @override
  Future<Result<void>> requestAuthoritativeDrain() => _write(() async {
    await _ensureCheckpointInTransaction();
    await (database.update(database.syncCheckpoints)
          ..where((row) => row.singletonId.equals(1)))
        .write(const SyncCheckpointsCompanion(drainRequested: Value(true)));
  });

  @override
  Future<Result<void>> persistDrainPage(DrainPage page) async {
    if (page.envelopes.length > 100 ||
        page.prunedThrough < 0 ||
        page.envelopes.any(
          (envelope) =>
              !_isUuid(envelope.id) ||
              envelope.sequence < 1 ||
              !_isEnvelopeBucket(envelope.exactCiphertext.length),
        )) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.malformedServerResponse),
      );
    }
    try {
      await database.writeTransaction(() async {
        final checkpoint = await _checkpointInTransaction();
        if (page.prunedThrough < checkpoint.prunedThrough) {
          throw const _ServerInvariant();
        }
        var newEntries = 0;
        for (final envelope in page.envelopes) {
          if (envelope.sequence <= checkpoint.highestContiguousAckedSequence) {
            continue;
          }
          final byId =
              await (database.select(database.inboxEnvelopes)
                    ..where((row) => row.envelopeId.equals(envelope.id)))
                  .getSingleOrNull();
          if (byId != null) {
            if (byId.sequence != envelope.sequence ||
                !_bytesEqual(
                  byId.envelopeCiphertext,
                  envelope.exactCiphertext,
                )) {
              throw const _ServerInvariant();
            }
            continue;
          }
          final bySequence =
              await (database.select(database.inboxEnvelopes)
                    ..where((row) => row.sequence.equals(envelope.sequence)))
                  .getSingleOrNull();
          if (bySequence != null) {
            throw const _ServerInvariant();
          }
          newEntries += 1;
        }
        final currentCount = await _count(database.inboxEnvelopes);
        if (currentCount + newEntries > maximumInboxEntries) {
          throw const _SyncCapacity();
        }
        for (final envelope in page.envelopes) {
          if (envelope.sequence <= checkpoint.highestContiguousAckedSequence) {
            continue;
          }
          await database
              .into(database.inboxEnvelopes)
              .insert(
                InboxEnvelopesCompanion.insert(
                  envelopeId: envelope.id,
                  sequence: envelope.sequence,
                  envelopeCiphertext: envelope.exactCiphertext,
                  processingState: InboxProcessingState.received.index,
                ),
                mode: InsertMode.insertOrIgnore,
              );
        }
        final gapDetected =
            checkpoint.highestContiguousAckedSequence < page.prunedThrough;
        await (database.update(
          database.syncCheckpoints,
        )..where((row) => row.singletonId.equals(1))).write(
          SyncCheckpointsCompanion(
            prunedThrough: Value(page.prunedThrough),
            queueGapState: gapDetected
                ? Value(QueueGapState.recoveryRequired.index)
                : const Value.absent(),
            drainRequested: Value(page.hasMore),
          ),
        );
        if (gapDetected) {
          await database
              .update(database.mlsGroups)
              .write(const MlsGroupsCompanion(queueGapRecoveryState: Value(1)));
        }
      });
      return const Result.success(null);
    } on _ServerInvariant {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.malformedServerResponse),
      );
    } on _SyncCapacity {
      return const Result.failure(
        StorageFailure(StorageFailureKind.capacityExceeded),
      );
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }

  @override
  Future<Result<SyncEnvelope?>> beginNextEnvelopeInspection({
    required DateTime now,
  }) async {
    try {
      final envelope = await database.writeTransaction(() async {
        final query = database.select(database.inboxEnvelopes)
          ..where(
            (row) =>
                (row.processingState.equals(
                      InboxProcessingState.received.index,
                    ) |
                    row.processingState.equals(
                      InboxProcessingState.inspecting.index,
                    )) &
                (row.nextAttemptAt.isNull() |
                    row.nextAttemptAt.isSmallerOrEqualValue(now)),
          )
          ..orderBy([(row) => OrderingTerm.asc(row.sequence)])
          ..limit(1);
        final row = await query.getSingleOrNull();
        if (row == null) {
          return null;
        }
        final attempt = row.attemptCount + 1;
        await (database.update(
          database.inboxEnvelopes,
        )..where((item) => item.envelopeId.equals(row.envelopeId))).write(
          InboxEnvelopesCompanion(
            processingState: Value(InboxProcessingState.inspecting.index),
            attemptCount: Value(attempt),
            nextAttemptAt: const Value(null),
          ),
        );
        return SyncEnvelope(
          id: row.envelopeId,
          sequence: row.sequence,
          attempt: attempt,
          exactCiphertext: row.envelopeCiphertext,
        );
      });
      return Result.success(envelope);
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }

  @override
  Future<Result<bool>> commitOpaqueInspection({
    required String envelopeId,
    required OpaqueEnvelopeInspection inspection,
  }) async {
    if (inspection.opaqueEventId.isEmpty) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    final pairwise = inspection.pairwiseCommit;
    if (pairwise != null) {
      if (inspection.dependency != EnvelopeDependency.directOrLocal ||
          pairwise.envelopeId != envelopeId ||
          pairwise.opaqueEventId != inspection.opaqueEventId ||
          pairwise.sessionTransition.disposition < 0 ||
          pairwise.sessionTransition.disposition >=
              PairwiseSessionDisposition.values.length ||
          pairwise.sessionTransition.repairState < 0 ||
          pairwise.sessionTransition.repairState >=
              PairwiseRepairState.values.length ||
          pairwise.consumedOneTimePrekeys.any(
            (key) =>
                key.algorithm < 0 ||
                key.algorithm >= PairwiseOneTimePrekeyKind.values.length,
          )) {
        return const Result.failure(
          SecurityFailure(SecurityFailureKind.malformedServerResponse),
        );
      }
      return DriftPairwiseTransportStore(database).commitPreparedReceive(
        PairwiseReceiveCommit(
          envelopeId: pairwise.envelopeId,
          opaqueEventId: pairwise.opaqueEventId,
          senderUserId: pairwise.senderUserId,
          senderDeviceId: pairwise.senderDeviceId,
          replayMarker: pairwise.replayMarker,
          openedOpaquePayload: pairwise.openedOpaquePayload,
          signedPrekeyId: pairwise.signedPrekeyId,
          pqSignedPrekeyId: pairwise.pqSignedPrekeyId,
          sessionTransition: PairwiseSessionTransition(
            localDeviceId: pairwise.sessionTransition.localDeviceId,
            remoteUserId: pairwise.sessionTransition.remoteUserId,
            remoteDeviceId: pairwise.sessionTransition.remoteDeviceId,
            sessionId: pairwise.sessionTransition.sessionId,
            nextOpaqueState: pairwise.sessionTransition.nextOpaqueState,
            expectedStateVersion:
                pairwise.sessionTransition.expectedStateVersion,
            nextStateVersion: pairwise.sessionTransition.nextStateVersion,
            nextSkippedKeyCount: pairwise.sessionTransition.nextSkippedKeyCount,
            disposition: PairwiseSessionDisposition
                .values[pairwise.sessionTransition.disposition],
            repairState: PairwiseRepairState
                .values[pairwise.sessionTransition.repairState],
            repairAuthorization: pairwise.sessionTransition.repairAuthorization,
          ),
          demotedExistingSessionTransition:
              pairwise.demotedExistingSessionTransition == null
              ? null
              : PairwiseSessionTransition(
                  localDeviceId:
                      pairwise.demotedExistingSessionTransition!.localDeviceId,
                  remoteUserId:
                      pairwise.demotedExistingSessionTransition!.remoteUserId,
                  remoteDeviceId:
                      pairwise.demotedExistingSessionTransition!.remoteDeviceId,
                  sessionId:
                      pairwise.demotedExistingSessionTransition!.sessionId,
                  nextOpaqueState: pairwise
                      .demotedExistingSessionTransition!
                      .nextOpaqueState,
                  expectedStateVersion: pairwise
                      .demotedExistingSessionTransition!
                      .expectedStateVersion,
                  nextStateVersion: pairwise
                      .demotedExistingSessionTransition!
                      .nextStateVersion,
                  nextSkippedKeyCount: pairwise
                      .demotedExistingSessionTransition!
                      .nextSkippedKeyCount,
                  disposition:
                      PairwiseSessionDisposition.values[pairwise
                          .demotedExistingSessionTransition!
                          .disposition],
                  repairState:
                      PairwiseRepairState.values[pairwise
                          .demotedExistingSessionTransition!
                          .repairState],
                  repairAuthorization: pairwise
                      .demotedExistingSessionTransition!
                      .repairAuthorization,
                ),
          replacedSessionId: pairwise.replacedSessionId,
          deviceStateTransition: pairwise.deviceStateTransition == null
              ? null
              : PairwiseDeviceStateTransition(
                  nextOpaqueState:
                      pairwise.deviceStateTransition!.nextOpaqueState,
                  expectedStateVersion:
                      pairwise.deviceStateTransition!.expectedStateVersion,
                  nextStateVersion:
                      pairwise.deviceStateTransition!.nextStateVersion,
                ),
          consumedOneTimePrekeys: [
            for (final key in pairwise.consumedOneTimePrekeys)
              ConsumedPairwiseOneTimePrekey(
                kind: PairwiseOneTimePrekeyKind.values[key.algorithm],
                keyId: key.keyId,
              ),
          ],
          applicationEvent: pairwise.applicationEvent,
          unsupportedApplicationEvent: pairwise.unsupportedApplicationEvent,
          deviceControlEvent: pairwise.deviceControlEvent,
          historyApplicationEvents: pairwise.historyApplicationEvents,
        ),
      );
    }
    try {
      final applied = await database.writeTransaction(() async {
        final envelope = await (database.select(
          database.inboxEnvelopes,
        )..where((row) => row.envelopeId.equals(envelopeId))).getSingleOrNull();
        if (envelope == null ||
            envelope.processingState != InboxProcessingState.inspecting.index) {
          throw const _SyncConflict();
        }
        final inserted = await database
            .into(database.inboxEventDeduplications)
            .insert(
              InboxEventDeduplicationsCompanion.insert(
                opaqueEventId: inspection.opaqueEventId,
                firstEnvelopeId: envelopeId,
                dependencyClass: inspection.dependency.index,
              ),
              mode: InsertMode.insertOrIgnore,
            );
        await (database.update(
          database.inboxEnvelopes,
        )..where((row) => row.envelopeId.equals(envelopeId))).write(
          InboxEnvelopesCompanion(
            opaqueEventId: Value(inspection.opaqueEventId),
            dependencyClass: Value(inspection.dependency.index),
            processingState: Value(
              InboxProcessingState.readyToAcknowledge.index,
            ),
            readyToAcknowledge: const Value(true),
            nextAttemptAt: const Value(null),
          ),
        );
        return inserted > 0;
      });
      return Result.success(applied);
    } on _SyncConflict {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.conflict),
      );
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }

  @override
  Future<Result<void>> blockEnvelopeForQueueGap(String envelopeId) => _write(
    () async {
      await (database.update(
        database.inboxEnvelopes,
      )..where((row) => row.envelopeId.equals(envelopeId))).write(
        InboxEnvelopesCompanion(
          processingState: Value(InboxProcessingState.blockedByQueueGap.index),
          nextAttemptAt: const Value(null),
        ),
      );
    },
  );

  @override
  Future<Result<void>> recordEnvelopeInspectionRetry({
    required String envelopeId,
    required DateTime retryAt,
  }) => _write(() async {
    await (database.update(
      database.inboxEnvelopes,
    )..where((row) => row.envelopeId.equals(envelopeId))).write(
      InboxEnvelopesCompanion(
        processingState: Value(InboxProcessingState.received.index),
        nextAttemptAt: Value(retryAt),
      ),
    );
  });

  @override
  Future<Result<void>> recordEnvelopeRejection({
    required String envelopeId,
    required int reasonCode,
  }) => _write(() async {
    await database
        .into(database.quarantineRecords)
        .insert(
          QuarantineRecordsCompanion.insert(
            reasonCode: reasonCode,
            opaqueDigest: Uint8List(0),
          ),
        );
    await (database.update(
      database.inboxEnvelopes,
    )..where((row) => row.envelopeId.equals(envelopeId))).write(
      InboxEnvelopesCompanion(
        processingState: Value(InboxProcessingState.readyToAcknowledge.index),
        readyToAcknowledge: const Value(true),
        nextAttemptAt: const Value(null),
      ),
    );
    await database.customStatement(
      'DELETE FROM quarantine WHERE id NOT IN '
      '(SELECT id FROM quarantine ORDER BY received_at DESC, id DESC LIMIT 256)',
    );
  });

  @override
  Future<Result<AcknowledgementBatch?>> beginAcknowledgementBatch({
    required DateTime now,
    required int maximumIds,
  }) async {
    if (maximumIds < 1 || maximumIds > 200) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.limitExceeded),
      );
    }
    try {
      final batch = await database.writeTransaction(() async {
        final interrupted = database.select(database.inboxEnvelopes)
          ..where(
            (row) =>
                row.processingState.equals(
                  InboxProcessingState.acknowledgementSending.index,
                ) &
                (row.nextAttemptAt.isNull() |
                    row.nextAttemptAt.isSmallerOrEqualValue(now)),
          )
          ..orderBy([(row) => OrderingTerm.asc(row.sequence)])
          ..limit(maximumIds);
        var rows = await interrupted.get();
        if (rows.isEmpty) {
          final ready = database.select(database.inboxEnvelopes)
            ..where(
              (row) =>
                  row.processingState.equals(
                    InboxProcessingState.readyToAcknowledge.index,
                  ) &
                  (row.nextAttemptAt.isNull() |
                      row.nextAttemptAt.isSmallerOrEqualValue(now)),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.sequence)])
            ..limit(maximumIds);
          rows = await ready.get();
        }
        if (rows.isEmpty) {
          return null;
        }
        final ids = rows.map((row) => row.envelopeId).toList(growable: false);
        final attempt =
            rows
                .map((row) => row.attemptCount)
                .fold<int>(0, (left, right) => left > right ? left : right) +
            1;
        await (database.update(
          database.inboxEnvelopes,
        )..where((row) => row.envelopeId.isIn(ids))).write(
          InboxEnvelopesCompanion(
            processingState: Value(
              InboxProcessingState.acknowledgementSending.index,
            ),
            attemptCount: Value(attempt),
            nextAttemptAt: const Value(null),
          ),
        );
        return AcknowledgementBatch(envelopeIds: ids, attempt: attempt);
      });
      return Result.success(batch);
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }

  @override
  Future<Result<void>> recordAcknowledgementSuccess({
    required AcknowledgementBatch batch,
    required DateTime now,
  }) => _write(() async {
    await (database.update(
      database.inboxEnvelopes,
    )..where((row) => row.envelopeId.isIn(batch.envelopeIds))).write(
      InboxEnvelopesCompanion(
        processingState: Value(InboxProcessingState.acknowledged.index),
        readyToAcknowledge: const Value(false),
        nextAttemptAt: const Value(null),
      ),
    );
    final checkpoint = await _checkpointInTransaction();
    var contiguous = checkpoint.highestContiguousAckedSequence;
    final acknowledgedRows =
        await (database.select(database.inboxEnvelopes)
              ..where(
                (row) =>
                    row.processingState.equals(
                      InboxProcessingState.acknowledged.index,
                    ) &
                    row.sequence.isBiggerThanValue(contiguous),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.sequence)]))
            .get();
    for (final row in acknowledgedRows) {
      if (row.sequence != contiguous + 1) {
        break;
      }
      contiguous = row.sequence;
    }
    await (database.update(
      database.syncCheckpoints,
    )..where((row) => row.singletonId.equals(1))).write(
      SyncCheckpointsCompanion(
        highestContiguousAckedSequence: Value(contiguous),
      ),
    );
    await (database.delete(database.inboxEnvelopes)..where(
          (row) =>
              row.processingState.equals(
                InboxProcessingState.acknowledged.index,
              ) &
              row.sequence.isSmallerOrEqualValue(contiguous),
        ))
        .go();
  });

  @override
  Future<Result<void>> recordAcknowledgementFailure({
    required AcknowledgementBatch batch,
    required DateTime retryAt,
  }) => _write(() async {
    await (database.update(
      database.inboxEnvelopes,
    )..where((row) => row.envelopeId.isIn(batch.envelopeIds))).write(
      InboxEnvelopesCompanion(
        processingState: Value(InboxProcessingState.readyToAcknowledge.index),
        nextAttemptAt: Value(retryAt),
      ),
    );
  });

  @override
  Future<Result<OutboxBatch?>> beginNextOutboxBatch({
    required DateTime now,
  }) async {
    try {
      final batch = await database.writeTransaction(() async {
        var first =
            await (database.select(database.outboxOperations)
                  ..where(
                    (row) => row.attemptState.equals(
                      OutboxAttemptState.sending.index,
                    ),
                  )
                  ..orderBy([
                    (row) => OrderingTerm.asc(row.operationId),
                    (row) => OrderingTerm.asc(row.batchIndex),
                    (row) => OrderingTerm.asc(row.recipientDeviceId),
                  ])
                  ..limit(1))
                .getSingleOrNull();
        first ??=
            await (database.select(database.outboxOperations)
                  ..where(
                    (row) =>
                        (row.attemptState.equals(
                              OutboxAttemptState.queued.index,
                            ) |
                            row.attemptState.equals(
                              OutboxAttemptState.retryWait.index,
                            )) &
                        (row.nextAttemptAt.isNull() |
                            row.nextAttemptAt.isSmallerOrEqualValue(now)),
                  )
                  ..orderBy([
                    (row) => OrderingTerm.asc(row.operationId),
                    (row) => OrderingTerm.asc(row.batchIndex),
                    (row) => OrderingTerm.asc(row.recipientDeviceId),
                  ])
                  ..limit(1))
                .getSingleOrNull();
        if (first == null) {
          return null;
        }
        final rows =
            await (database.select(database.outboxOperations)
                  ..where(
                    (row) =>
                        row.operationId.equals(first!.operationId) &
                        row.batchIndex.equals(first.batchIndex) &
                        (row.attemptState.equals(
                              OutboxAttemptState.queued.index,
                            ) |
                            row.attemptState.equals(
                              OutboxAttemptState.sending.index,
                            ) |
                            row.attemptState.equals(
                              OutboxAttemptState.retryWait.index,
                            )),
                  )
                  ..orderBy([(row) => OrderingTerm.asc(row.recipientDeviceId)]))
                .get();
        final dueRows = rows
            .where(
              (row) =>
                  row.attemptState == OutboxAttemptState.sending.index ||
                  row.nextAttemptAt == null ||
                  !row.nextAttemptAt!.isAfter(now),
            )
            .toList(growable: false);
        if (dueRows.isEmpty) {
          return null;
        }
        final ids = dueRows
            .map((row) => row.recipientDeviceId)
            .toList(growable: false);
        final attempt =
            dueRows
                .map((row) => row.attemptCount)
                .fold<int>(0, (left, right) => left > right ? left : right) +
            1;
        await (database.update(database.outboxOperations)..where(
              (row) =>
                  row.operationId.equals(first!.operationId) &
                  row.recipientDeviceId.isIn(ids),
            ))
            .write(
              OutboxOperationsCompanion(
                attemptState: Value(OutboxAttemptState.sending.index),
                attemptCount: Value(attempt),
                nextAttemptAt: const Value(null),
                lastAttemptAt: Value(now),
              ),
            );
        await DriftApplicationEventProjector(
          database,
        ).refreshTransportForEventInsideTransaction(first.eventId);
        return OutboxBatch(
          operationId: first.operationId,
          eventId: first.eventId,
          batchIndex: first.batchIndex,
          attempt: attempt,
          targets: dueRows
              .map(
                (row) => OutboxTarget(
                  recipientUserId: row.recipientUserId,
                  recipientDeviceId: row.recipientDeviceId,
                  exactCiphertext: row.exactRecipientCiphertext,
                ),
              )
              .toList(growable: false),
        );
      });
      return Result.success(batch);
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }

  @override
  Future<Result<void>> recordOutboxAcceptance({
    required OutboxBatch batch,
    required OutboxAcceptance acceptance,
    required DateTime now,
  }) => _write(() async {
    for (final target in batch.targets) {
      final stale = acceptance.staleDeviceIds.contains(
        target.recipientDeviceId,
      );
      await (database.update(database.outboxOperations)..where(
            (row) =>
                row.operationId.equals(batch.operationId) &
                row.recipientDeviceId.equals(target.recipientDeviceId),
          ))
          .write(
            OutboxOperationsCompanion(
              attemptState: Value(
                stale
                    ? OutboxAttemptState.stale.index
                    : OutboxAttemptState.accepted.index,
              ),
              nextAttemptAt: const Value(null),
              terminalAt: Value(now),
            ),
          );
      if (!stale) {
        continue;
      }
      await (database.delete(database.pairwiseSessions)..where(
            (row) => row.remoteDeviceId.equals(target.recipientDeviceId),
          ))
          .go();
      await (database.delete(database.pairwiseSessionAlternates)..where(
            (row) => row.remoteDeviceId.equals(target.recipientDeviceId),
          ))
          .go();
      await database
          .into(database.staleDeviceRefreshRequests)
          .insert(
            StaleDeviceRefreshRequestsCompanion.insert(
              userId: target.recipientUserId,
              staleDeviceId: target.recipientDeviceId,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
    await DriftApplicationEventProjector(
      database,
    ).refreshTransportForEventInsideTransaction(batch.eventId);
  });

  @override
  Future<Result<void>> recordOutboxRetry({
    required OutboxBatch batch,
    required DateTime retryAt,
  }) => _updateOutboxBatch(
    batch,
    OutboxOperationsCompanion(
      attemptState: Value(OutboxAttemptState.retryWait.index),
      nextAttemptAt: Value(retryAt),
    ),
  );

  @override
  Future<Result<void>> recordOutboxPermanentFailure({
    required OutboxBatch batch,
    required DateTime now,
  }) => _updateOutboxBatch(
    batch,
    OutboxOperationsCompanion(
      attemptState: Value(OutboxAttemptState.permanentlyFailed.index),
      nextAttemptAt: const Value(null),
      terminalAt: Value(now),
    ),
  );

  @override
  Future<Result<List<StaleDeviceRefreshWork>>> pendingStaleDeviceRefreshes({
    required DateTime now,
  }) async {
    try {
      final work = await database.writeTransaction(() async {
        final rows =
            await (database.select(database.staleDeviceRefreshRequests)
                  ..where(
                    (row) =>
                        row.state.isIn(const [0, 1, 2]) &
                        (row.nextAttemptAt.isNull() |
                            row.nextAttemptAt.isSmallerOrEqualValue(now)),
                  )
                  ..orderBy([(row) => OrderingTerm.asc(row.userId)]))
                .get();
        final attempts = <String, int>{};
        for (final row in rows) {
          final attempt = row.attemptCount + 1;
          final previous = attempts[row.userId] ?? 0;
          if (attempt > previous) {
            attempts[row.userId] = attempt;
          }
          await (database.update(database.staleDeviceRefreshRequests)..where(
                (item) =>
                    item.userId.equals(row.userId) &
                    item.staleDeviceId.equals(row.staleDeviceId),
              ))
              .write(
                StaleDeviceRefreshRequestsCompanion(
                  state: const Value(1),
                  attemptCount: Value(attempt),
                  nextAttemptAt: const Value(null),
                ),
              );
        }
        return attempts.entries
            .map(
              (entry) => StaleDeviceRefreshWork(
                userId: entry.key,
                attempt: entry.value,
              ),
            )
            .toList(growable: false);
      });
      return Result.success(List.unmodifiable(work));
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }

  @override
  Future<Result<void>> completeStaleDeviceRefresh(String userId) =>
      _write(() async {
        await (database.delete(
          database.staleDeviceRefreshRequests,
        )..where((row) => row.userId.equals(userId))).go();
      });

  @override
  Future<Result<void>> retryStaleDeviceRefresh({
    required String userId,
    required DateTime retryAt,
  }) => _write(() async {
    await (database.update(
      database.staleDeviceRefreshRequests,
    )..where((row) => row.userId.equals(userId))).write(
      StaleDeviceRefreshRequestsCompanion(
        state: const Value(2),
        nextAttemptAt: Value(retryAt),
      ),
    );
  });

  @override
  Future<Result<void>> markConnectionPhase(SyncConnectionPhase phase) => _write(
    () async {
      await _ensureCheckpointInTransaction();
      await (database.update(database.syncCheckpoints)
            ..where((row) => row.singletonId.equals(1)))
          .write(SyncCheckpointsCompanion(connectionPhase: Value(phase.index)));
    },
  );

  @override
  Future<Result<DurableReconnectState>> scheduleReconnect({
    required DateTime dueAt,
  }) async {
    try {
      final state = await database.writeTransaction(() async {
        final checkpoint = await _checkpointInTransaction();
        final attempt = checkpoint.reconnectAttempt + 1;
        await (database.update(
          database.syncCheckpoints,
        )..where((row) => row.singletonId.equals(1))).write(
          SyncCheckpointsCompanion(
            connectionPhase: Value(SyncConnectionPhase.reconnectWaiting.index),
            reconnectAttempt: Value(attempt),
            reconnectAt: Value(dueAt),
          ),
        );
        return DurableReconnectState(
          attempt: attempt,
          dueAt: dueAt,
          phase: SyncConnectionPhase.reconnectWaiting,
        );
      });
      return Result.success(state);
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }

  @override
  Future<Result<DurableReconnectState>> readReconnectState() async {
    try {
      final checkpoint = await _checkpoint();
      return Result.success(
        DurableReconnectState(
          attempt: checkpoint.reconnectAttempt,
          dueAt: checkpoint.reconnectAt,
          phase: _connectionPhase(checkpoint.connectionPhase),
        ),
      );
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }

  @override
  Future<Result<void>> clearReconnect({required DateTime? syncedAt}) =>
      _write(() async {
        await _ensureCheckpointInTransaction();
        await (database.update(
          database.syncCheckpoints,
        )..where((row) => row.singletonId.equals(1))).write(
          SyncCheckpointsCompanion(
            reconnectAttempt: const Value(0),
            reconnectAt: const Value(null),
            lastSuccessfulSyncAt: syncedAt == null
                ? const Value.absent()
                : Value(syncedAt),
          ),
        );
      });

  @override
  Future<Result<void>> recordSuccessfulSync(DateTime syncedAt) =>
      _write(() async {
        await _ensureCheckpointInTransaction();
        await (database.update(
          database.syncCheckpoints,
        )..where((row) => row.singletonId.equals(1))).write(
          SyncCheckpointsCompanion(lastSuccessfulSyncAt: Value(syncedAt)),
        );
      });

  @override
  Future<Result<void>> markGroupRecovered(String groupId) =>
      _completeGroupRecovery(groupId, left: false);

  @override
  Future<Result<void>> markGroupLeft(String groupId) =>
      _completeGroupRecovery(groupId, left: true);

  Future<Result<void>> _completeGroupRecovery(
    String groupId, {
    required bool left,
  }) => _write(() async {
    if (left) {
      await (database.delete(
        database.mlsGroups,
      )..where((row) => row.groupId.equals(groupId))).go();
    } else {
      await (database.update(database.mlsGroups)
            ..where((row) => row.groupId.equals(groupId)))
          .write(const MlsGroupsCompanion(queueGapRecoveryState: Value(0)));
    }
    final remaining =
        await (database.selectOnly(database.mlsGroups)
              ..addColumns([database.mlsGroups.groupId.count()])
              ..where(database.mlsGroups.queueGapRecoveryState.equals(1)))
            .getSingle();
    final count = remaining.read(database.mlsGroups.groupId.count()) ?? 0;
    if (count == 0) {
      final checkpoint = await _checkpointInTransaction();
      await (database.update(
        database.syncCheckpoints,
      )..where((row) => row.singletonId.equals(1))).write(
        SyncCheckpointsCompanion(
          highestContiguousAckedSequence: Value(
            checkpoint.prunedThrough > checkpoint.highestContiguousAckedSequence
                ? checkpoint.prunedThrough
                : checkpoint.highestContiguousAckedSequence,
          ),
          queueGapState: Value(QueueGapState.clear.index),
          drainRequested: const Value(true),
        ),
      );
      await (database.update(database.inboxEnvelopes)..where(
            (row) => row.processingState.equals(
              InboxProcessingState.blockedByQueueGap.index,
            ),
          ))
          .write(
            InboxEnvelopesCompanion(
              processingState: Value(InboxProcessingState.received.index),
            ),
          );
    }
  });

  Future<Result<void>> _updateOutboxBatch(
    OutboxBatch batch,
    OutboxOperationsCompanion companion,
  ) => _write(() async {
    final ids = batch.targets
        .map((target) => target.recipientDeviceId)
        .toList(growable: false);
    await (database.update(database.outboxOperations)..where(
          (row) =>
              row.operationId.equals(batch.operationId) &
              row.recipientDeviceId.isIn(ids),
        ))
        .write(companion);
    await DriftApplicationEventProjector(
      database,
    ).refreshTransportForEventInsideTransaction(batch.eventId);
  });

  Future<Result<void>> _write(Future<void> Function() operation) async {
    try {
      await database.writeTransaction(operation);
      return const Result.success(null);
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }

  Future<void> _ensureCheckpoint() async {
    await database
        .into(database.syncCheckpoints)
        .insert(
          SyncCheckpointsCompanion.insert(
            etagsCiphertext: Uint8List(0),
            retryState: 0,
            protocolVersion: 1,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> _ensureCheckpointInTransaction() => _ensureCheckpoint();

  Future<SyncCheckpoint> _checkpoint() async {
    await _ensureCheckpoint();
    return (database.select(
      database.syncCheckpoints,
    )..where((row) => row.singletonId.equals(1))).getSingle();
  }

  Future<SyncCheckpoint> _checkpointInTransaction() => _checkpoint();

  SyncProjection _projectionFromRow(QueryRow row) => SyncProjection(
    connectionPhase: _connectionPhase(row.read<int>('connection_phase')),
    queueGapState: row.read<int>('queue_gap_state') == 0
        ? QueueGapState.clear
        : QueueGapState.recoveryRequired,
    highestContiguousAcknowledgedSequence: row.read<int>(
      'highest_contiguous_acked_sequence',
    ),
    prunedThrough: row.read<int>('pruned_through'),
    inboxDepth: row.read<int>('inbox_depth'),
    outboxDepth: row.read<int>('outbox_depth'),
    nextRetryAt: row.readNullable<DateTime>('next_retry_at'),
    lastSuccessfulSyncAt: row.readNullable<DateTime>('last_successful_sync_at'),
  );

  SyncConnectionPhase _connectionPhase(int index) =>
      index >= 0 && index < SyncConnectionPhase.values.length
      ? SyncConnectionPhase.values[index]
      : SyncConnectionPhase.protocolCircuitOpen;

  Future<int> _count(TableInfo<Table, Object?> table) async {
    final count = table.$columns.first.count();
    final row = await (database.selectOnly(
      table,
    )..addColumns([count])).getSingle();
    return row.read(count) ?? 0;
  }

  bool _samePreparedTargets(
    List<OutboxOperation> existing,
    List<PreparedOutboxTarget> prepared,
  ) {
    if (existing.length != prepared.length) {
      return false;
    }
    final sortedExisting = List<OutboxOperation>.of(existing)
      ..sort(
        (left, right) =>
            _compareUuidBytes(left.recipientDeviceId, right.recipientDeviceId),
      );
    for (var index = 0; index < prepared.length; index += 1) {
      final row = sortedExisting[index];
      final target = prepared[index];
      if (row.recipientDeviceId != target.recipientDeviceId.toLowerCase() ||
          row.recipientUserId != target.recipientUserId ||
          !_bytesEqual(row.exactRecipientCiphertext, target.exactCiphertext)) {
        return false;
      }
    }
    return true;
  }
}

final class _SyncConflict implements Exception {
  const _SyncConflict();
}

final class _SyncCapacity implements Exception {
  const _SyncCapacity();
}

final class _ServerInvariant implements Exception {
  const _ServerInvariant();
}

const _envelopeBuckets = {1024, 4096, 16384, 65536, 262144};

bool _isEnvelopeBucket(int length) => _envelopeBuckets.contains(length);

bool _bytesEqual(Uint8List left, Uint8List right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

bool _isUuid(String value) => _uuid.hasMatch(value);

int _compareUuidBytes(String left, String right) {
  final leftHex = left.replaceAll('-', '').toLowerCase();
  final rightHex = right.replaceAll('-', '').toLowerCase();
  for (var index = 0; index < 32; index += 2) {
    final leftByte = int.parse(leftHex.substring(index, index + 2), radix: 16);
    final rightByte = int.parse(
      rightHex.substring(index, index + 2),
      radix: 16,
    );
    final comparison = leftByte.compareTo(rightByte);
    if (comparison != 0) {
      return comparison;
    }
  }
  return 0;
}

final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

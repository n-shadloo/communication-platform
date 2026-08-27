import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:communication_platform/features/synchronization/domain/sync_model.dart';
import 'package:communication_platform/features/synchronization/infrastructure/drift_sync_store.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/counting_interceptor.dart';

/// What one page of an authoritative drain costs when nothing on it is new.
///
/// A server keeps serving an envelope until this device acknowledges it, so a
/// re-served page is the ordinary case during any backlog, not an edge one.
/// Establishing that a hundred already-present rows are already present used to
/// take two statements each plus a `COUNT(*)` over the whole inbox — roughly
/// two hundred round trips inside one write transaction, on every page of every
/// drain, forever.
void main() {
  late CountingInterceptor counter;
  late LocalDatabase database;
  late DriftSyncStore store;

  setUp(() {
    counter = CountingInterceptor();
    database = LocalDatabase(NativeDatabase.memory().interceptWith(counter));
    store = DriftSyncStore(database, projectionWindow: Duration.zero);
  });

  tearDown(() async {
    await database.close();
  });

  DrainPage pageOf(int count, {int ciphertextMarker = 1}) => DrainPage(
    envelopes: [
      for (var sequence = 1; sequence <= count; sequence += 1)
        SyncEnvelope(
          id: uuid(sequence),
          sequence: sequence,
          exactCiphertext: blob(ciphertextMarker),
        ),
    ],
    hasMore: false,
    prunedThrough: 0,
  );

  test(
    'a fully re-served page of a hundred costs a bounded few statements',
    () async {
      expect(await store.persistDrainPage(pageOf(100)), isA<Success<void>>());
      expect(
        await database.select(database.inboxEnvelopes).get(),
        hasLength(100),
      );

      counter.reset();
      final again = await store.persistDrainPage(pageOf(100));

      expect(again, isA<Success<void>>());
      expect(
        counter.statements,
        lessThan(20),
        reason:
            'the page is answered by set-based reads, not by asking about each '
            'envelope twice and then counting the table',
      );
      expect(
        await database.select(database.inboxEnvelopes).get(),
        hasLength(100),
        reason: 'and nothing was duplicated',
      );
    },
  );

  test(
    'a re-served envelope whose ciphertext changed is still refused',
    () async {
      expect(await store.persistDrainPage(pageOf(4)), isA<Success<void>>());

      final tampered = await store.persistDrainPage(
        pageOf(4, ciphertextMarker: 2),
      );

      expect(tampered, isA<FailureResult<void>>());
      expect(
        (tampered as FailureResult<void>).failure,
        isA<SecurityFailure>().having(
          (failure) => failure.kind,
          'kind',
          SecurityFailureKind.malformedServerResponse,
        ),
      );
    },
  );

  test(
    'a second envelope claiming a taken sequence is still refused',
    () async {
      expect(await store.persistDrainPage(pageOf(4)), isA<Success<void>>());

      final collided = await store.persistDrainPage(
        DrainPage(
          envelopes: [
            // A sequence already held by envelope 3, under a new identifier.
            SyncEnvelope(id: uuid(99), sequence: 3, exactCiphertext: blob(1)),
          ],
          hasMore: false,
          prunedThrough: 0,
        ),
      );

      expect(collided, isA<FailureResult<void>>());
      expect(
        (collided as FailureResult<void>).failure,
        isA<SecurityFailure>().having(
          (failure) => failure.kind,
          'kind',
          SecurityFailureKind.malformedServerResponse,
        ),
      );
    },
  );

  test(
    'the inbox ceiling still refuses a page that would overflow it',
    () async {
      final bounded = DriftSyncStore(
        database,
        maximumInboxEntries: 3,
        projectionWindow: Duration.zero,
      );

      final overflowing = await bounded.persistDrainPage(pageOf(4));

      expect(overflowing, isA<FailureResult<void>>());
      expect(
        (overflowing as FailureResult<void>).failure,
        isA<StorageFailure>().having(
          (failure) => failure.kind,
          'kind',
          StorageFailureKind.capacityExceeded,
        ),
      );
      expect(await database.select(database.inboxEnvelopes).get(), isEmpty);
      expect(await bounded.persistDrainPage(pageOf(3)), isA<Success<void>>());
    },
  );
}

String uuid(int value) =>
    '00000000-0000-0000-0000-${value.toRadixString(16).padLeft(12, '0')}';

Uint8List blob(int marker) =>
    Uint8List.fromList(List<int>.filled(1024, marker));

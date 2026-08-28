import 'dart:convert';
import 'dart:typed_data';

import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/devices/application/acknowledge_deployment_disclosure.dart';
import 'package:communication_platform/features/devices/application/ports/disclosure_acknowledgement_ports.dart';
import 'package:communication_platform/features/devices/infrastructure/drift_disclosure_acknowledgement_store.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the application remembers about a statement somebody agreed to.
///
/// ADR-045 made re-acknowledgement content-triggered and stopped there: the
/// revision moved three times with nothing on the device recording what had
/// been accepted, so an existing recipient's install could not tell that it was
/// carrying a corrected statement. These tests hold the record that ADR-052
/// added, and the two directions in which it deliberately fails.
void main() {
  late LocalDatabase database;
  late DriftDisclosureAcknowledgementStore store;

  setUp(() {
    database = LocalDatabase(NativeDatabase.memory());
    store = DriftDisclosureAcknowledgementStore(database);
  });

  tearDown(() => database.close());

  group('the durable record', () {
    test('an installation that has recorded nothing reads as zero', () async {
      final read = await store.readAcknowledgedRevision();

      expect(read, isA<Success<int>>());
      expect((read as Success<int>).value, 0);
    });

    test('what was accepted survives a round trip', () async {
      await store.recordAcknowledgedRevision(5);

      expect((await store.readAcknowledgedRevision() as Success<int>).value, 5);
    });

    test('it never goes backwards', () async {
      // A downgrade would silently re-present a statement the user has already
      // answered, which is the failure ADR-045 rejected periodic re-consent to
      // avoid.
      await store.recordAcknowledgedRevision(5);
      await store.recordAcknowledgedRevision(3);

      expect((await store.readAcknowledgedRevision() as Success<int>).value, 5);
    });

    test('recording the same revision twice changes nothing', () async {
      await store.recordAcknowledgedRevision(5);
      final second = await store.recordAcknowledgedRevision(5);

      expect(second, isA<Success<void>>());
      expect((await store.readAcknowledgedRevision() as Success<int>).value, 5);
    });

    test('a row it cannot parse reads as no record, not as current', () async {
      // The safe failure direction is the one that shows the notice again.
      await database
          .into(database.localPreferences)
          .insertOnConflictUpdate(
            LocalPreferencesCompanion.insert(
              preferenceKey: DriftDisclosureAcknowledgementStore.revisionKey,
              valueCiphertext: Uint8List.fromList(utf8.encode('not a number')),
              valueVersion: 1,
            ),
          );

      expect((await store.readAcknowledgedRevision() as Success<int>).value, 0);
    });

    test('it stores the integer and nothing about the person', () async {
      await store.recordAcknowledgedRevision(5);

      final row =
          await (database.select(database.localPreferences)..where(
                (entry) => entry.preferenceKey.equals(
                  DriftDisclosureAcknowledgementStore.revisionKey,
                ),
              ))
              .getSingle();

      expect(utf8.decode(row.valueCiphertext), '5');
      final everything = await database.select(database.localPreferences).get();
      expect(
        everything.length,
        1,
        reason: 'no timestamp, no identifier, no second row',
      );
    });
  });

  group('what the application concludes from it', () {
    test('a reader who is current is owed nothing', () async {
      await store.recordAcknowledgedRevision(5);
      final useCase = AcknowledgeDeploymentDisclosure(store: store);

      final state = await useCase.state(currentRevision: 5);

      expect(state.outstanding, isFalse);
      expect(state.acknowledgedRevision, 5);
    });

    test('a reader from an older revision is owed a showing', () async {
      await store.recordAcknowledgedRevision(4);
      final useCase = AcknowledgeDeploymentDisclosure(store: store);

      final state = await useCase.state(currentRevision: 5);

      expect(state.outstanding, isTrue);
      expect(state.acknowledgedRevision, 4);
    });

    test('a build carrying no statement asks nothing of anyone', () async {
      final useCase = AcknowledgeDeploymentDisclosure(store: store);

      expect((await useCase.state(currentRevision: 0)).outstanding, isFalse);
    });

    test('an unreadable record withholds the gate, not the app', () async {
      // Blocking somebody out of their messages because a preference row would
      // not open is a worse outcome for that person than showing them a notice
      // they have read. This is the only case where the mechanism gives up.
      final useCase = AcknowledgeDeploymentDisclosure(
        store: _UnavailableStore(),
      );

      final state = await useCase.state(currentRevision: 5);

      expect(state.outstanding, isFalse);
    });

    test('a failed write is reported rather than swallowed', () async {
      // The caller dismisses the screen either way; what it must not do is
      // believe the acceptance is durable when it is not.
      final useCase = AcknowledgeDeploymentDisclosure(
        store: _UnavailableStore(),
      );

      expect(await useCase.accept(revision: 5), isFalse);
      expect(
        await AcknowledgeDeploymentDisclosure(store: store).accept(revision: 5),
        isTrue,
      );
    });
  });
}

final class _UnavailableStore implements DisclosureAcknowledgementStore {
  @override
  Future<Result<int>> readAcknowledgedRevision() async =>
      const Result.failure(StorageFailure(StorageFailureKind.unavailable));

  @override
  Future<Result<void>> recordAcknowledgedRevision(int revision) async =>
      const Result.failure(StorageFailure(StorageFailureKind.unavailable));
}

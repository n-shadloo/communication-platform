import 'dart:io';

import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory temporaryDirectory;
  late File databaseFile;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'local-db-migration-',
    );
    databaseFile = File('${temporaryDirectory.path}/representative.sqlite');
    final legacy = sqlite3.open(databaseFile.path)
      ..execute('CREATE TABLE legacy_marker (value TEXT NOT NULL)')
      ..execute("INSERT INTO legacy_marker VALUES ('recoverable')")
      ..execute('PRAGMA user_version = 0');
    legacy.close();
  });

  tearDown(() async {
    if (temporaryDirectory.existsSync()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test(
    'initial migration upgrades a representative version-zero database',
    () async {
      final database = LocalDatabase(NativeDatabase(databaseFile));

      await database.customSelect('SELECT 1').getSingle();

      expect(
        await database.customSelect('SELECT * FROM legacy_marker').get(),
        hasLength(1),
      );
      expect(
        await database
            .customSelect('PRAGMA user_version')
            .map((row) => row.read<int>('user_version'))
            .getSingle(),
        LocalDatabase.currentSchemaVersion,
      );
      await database.close();
    },
  );

  test(
    'version-one upgrade preserves data and adds the enrollment journal',
    () async {
      final current = LocalDatabase(NativeDatabase(databaseFile));
      await current.customSelect('SELECT 1').getSingle();
      await current.customStatement(
        "INSERT INTO local_preferences "
        "(preference_key, value_ciphertext, value_version) "
        "VALUES ('preserved', X'010203', 1)",
      );
      await current.close();

      final versionOne = sqlite3.open(databaseFile.path)
        ..execute('DROP TABLE enrollment_intent')
        ..execute('DROP TABLE inbox_event_deduplication')
        ..execute('DROP TABLE stale_device_refresh_requests')
        ..execute('DROP TABLE pairwise_session_alternates')
        ..execute('DROP TABLE pairwise_replay_markers')
        ..execute('DROP TABLE pairwise_opened_payloads')
        ..execute('DROP TABLE pairwise_local_applications')
        ..execute('DROP TABLE pairwise_consumed_prekeys')
        ..execute('DROP TABLE prekey_maintenance_plans')
        ..execute('ALTER TABLE secure_secrets DROP COLUMN state_revision')
        ..execute(
          'ALTER TABLE devices DROP COLUMN last_signed_prekey_rotation_unix_day',
        )
        ..execute('ALTER TABLE pairwise_sessions DROP COLUMN remote_user_id')
        ..execute('ALTER TABLE pairwise_sessions DROP COLUMN session_id')
        ..execute('ALTER TABLE pairwise_sessions DROP COLUMN skipped_key_count')
        ..execute('ALTER TABLE pairwise_sessions DROP COLUMN disposition')
        ..execute('ALTER TABLE pairwise_sessions DROP COLUMN repair_state')
        ..execute(
          'ALTER TABLE pairwise_sessions DROP COLUMN repair_authorization',
        )
        ..execute(
          'ALTER TABLE pairwise_sessions DROP COLUMN last_authenticated_at',
        )
        ..execute('ALTER TABLE mls_groups DROP COLUMN queue_gap_recovery_state')
        ..execute('ALTER TABLE inbox_envelopes DROP COLUMN opaque_event_id')
        ..execute('ALTER TABLE inbox_envelopes DROP COLUMN dependency_class')
        ..execute('ALTER TABLE inbox_envelopes DROP COLUMN attempt_count')
        ..execute('ALTER TABLE inbox_envelopes DROP COLUMN next_attempt_at')
        ..execute('ALTER TABLE outbox_operations DROP COLUMN recipient_user_id')
        ..execute('ALTER TABLE outbox_operations DROP COLUMN next_attempt_at')
        ..execute('ALTER TABLE outbox_operations DROP COLUMN last_attempt_at')
        ..execute('ALTER TABLE outbox_operations DROP COLUMN terminal_at')
        ..execute('ALTER TABLE sync_checkpoint DROP COLUMN queue_gap_state')
        ..execute('ALTER TABLE sync_checkpoint DROP COLUMN drain_requested')
        ..execute('ALTER TABLE sync_checkpoint DROP COLUMN connection_phase')
        ..execute('ALTER TABLE sync_checkpoint DROP COLUMN reconnect_attempt')
        ..execute('ALTER TABLE sync_checkpoint DROP COLUMN reconnect_at')
        ..execute(
          'ALTER TABLE sync_checkpoint DROP COLUMN last_successful_sync_at',
        );
      _dropPieceFourteenSchema(versionOne);
      _dropPieceEighteenSchema(versionOne);
      _dropPieceNineteenSchema(versionOne);
      versionOne.execute('PRAGMA user_version = 1');
      versionOne.close();

      final upgraded = LocalDatabase(NativeDatabase(databaseFile));
      await upgraded.customSelect('SELECT 1').getSingle();

      expect(
        await upgraded
            .customSelect(
              "SELECT preference_key FROM local_preferences "
              "WHERE preference_key = 'preserved'",
            )
            .getSingle(),
        isNotNull,
      );
      expect(
        await upgraded
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' "
              "AND name = 'inbox_event_deduplication'",
            )
            .getSingle(),
        isNotNull,
      );
      expect(
        await upgraded
            .customSelect(
              "SELECT name FROM sqlite_master "
              "WHERE type = 'table' AND name = 'enrollment_intent'",
            )
            .getSingle(),
        isNotNull,
      );
      expect(
        await upgraded
            .customSelect('PRAGMA user_version')
            .map((row) => row.read<int>('user_version'))
            .getSingle(),
        LocalDatabase.currentSchemaVersion,
      );
      await upgraded.close();
    },
  );

  test(
    'version-three upgrade adds bounded pairwise transaction state',
    () async {
      final current = LocalDatabase(NativeDatabase(databaseFile));
      await current.customSelect('SELECT 1').getSingle();
      await current.customStatement(
        "INSERT INTO pairwise_sessions "
        "(local_device_id, remote_device_id, opaque_crypto_state_handle, "
        "state_version) VALUES "
        "('00000000-0000-0000-0000-000000000001', "
        "'00000000-0000-0000-0000-000000000002', X'01', 1)",
      );
      await current.close();

      final versionThree = sqlite3.open(databaseFile.path)
        ..execute('DROP TABLE pairwise_session_alternates')
        ..execute('DROP TABLE pairwise_replay_markers')
        ..execute('DROP TABLE pairwise_opened_payloads')
        ..execute('DROP TABLE pairwise_local_applications')
        ..execute('DROP TABLE pairwise_consumed_prekeys')
        ..execute('DROP TABLE prekey_maintenance_plans')
        ..execute('ALTER TABLE secure_secrets DROP COLUMN state_revision')
        ..execute(
          'ALTER TABLE devices DROP COLUMN last_signed_prekey_rotation_unix_day',
        )
        ..execute('ALTER TABLE pairwise_sessions DROP COLUMN remote_user_id')
        ..execute('ALTER TABLE pairwise_sessions DROP COLUMN session_id')
        ..execute('ALTER TABLE pairwise_sessions DROP COLUMN skipped_key_count')
        ..execute('ALTER TABLE pairwise_sessions DROP COLUMN disposition')
        ..execute('ALTER TABLE pairwise_sessions DROP COLUMN repair_state')
        ..execute(
          'ALTER TABLE pairwise_sessions DROP COLUMN repair_authorization',
        )
        ..execute(
          'ALTER TABLE pairwise_sessions DROP COLUMN last_authenticated_at',
        );
      _dropPieceFourteenSchema(versionThree);
      _dropPieceEighteenSchema(versionThree);
      _dropPieceNineteenSchema(versionThree);
      versionThree.execute('PRAGMA user_version = 3');
      versionThree.close();

      final upgraded = LocalDatabase(NativeDatabase(databaseFile));
      await upgraded.customSelect('SELECT 1').getSingle();

      final legacy = await upgraded
          .customSelect(
            'SELECT session_id, skipped_key_count, repair_state '
            'FROM pairwise_sessions',
          )
          .getSingle();
      expect(legacy.data['session_id'], isNull);
      expect(legacy.read<int>('skipped_key_count'), 0);
      expect(legacy.read<int>('repair_state'), 0);
      for (final table in const [
        'pairwise_session_alternates',
        'pairwise_replay_markers',
        'pairwise_opened_payloads',
        'pairwise_local_applications',
        'pairwise_consumed_prekeys',
        'prekey_maintenance_plans',
      ]) {
        expect(
          await upgraded
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'table' "
                "AND name = '$table'",
              )
              .getSingle(),
          isNotNull,
        );
      }
      expect(
        await upgraded
            .customSelect('PRAGMA user_version')
            .map((row) => row.read<int>('user_version'))
            .getSingle(),
        LocalDatabase.currentSchemaVersion,
      );
      await upgraded.close();
    },
  );

  test(
    'failed migration rolls back and leaves the old database recoverable',
    () async {
      final database = LocalDatabase(
        NativeDatabase(databaseFile),
        migrationHooks: _FailAfterSchemaCreation(),
      );

      await expectLater(
        database.customSelect('SELECT 1').getSingle(),
        throwsA(anything),
      );
      await database.close();

      final recovered = sqlite3.open(databaseFile.path);
      final marker = recovered
          .select('SELECT value FROM legacy_marker')
          .single['value'];
      final newTables = recovered.select(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'messages'",
      );
      final version = recovered
          .select('PRAGMA user_version')
          .single['user_version'];
      recovered.close();

      expect(marker, 'recoverable');
      expect(newTables, isEmpty);
      expect(version, 0);
    },
  );

  test('version-five upgrade adds piece-fifteen local flags safely', () async {
    final current = LocalDatabase(NativeDatabase(databaseFile));
    await current.customSelect('SELECT 1').getSingle();
    await current.customStatement(
      "INSERT INTO conversations "
      "(conversation_id, kind, list_projection_ciphertext, sort_key) "
      "VALUES ('conversation', 0, X'01', 1)",
    );
    await current.customStatement(
      "INSERT INTO messages "
      "(message_id, conversation_id, current_event_id, "
      "projection_ciphertext, status, revision, created_at) "
      "VALUES ('message', 'conversation', 'event', X'01', 0, 0, 0)",
    );
    await current.close();

    final versionFive = sqlite3.open(databaseFile.path)
      ..execute('ALTER TABLE conversations DROP COLUMN pinned')
      ..execute('ALTER TABLE messages DROP COLUMN starred');
    _dropPieceEighteenSchema(versionFive);
    _dropPieceNineteenSchema(versionFive);
    versionFive.execute('PRAGMA user_version = 5');
    versionFive.close();

    final upgraded = LocalDatabase(NativeDatabase(databaseFile));
    final row = await upgraded
        .customSelect(
          "SELECT starred FROM messages WHERE message_id = 'message'",
        )
        .getSingle();
    expect(row.read<int>('starred'), 0);
    final conversation = await upgraded
        .customSelect(
          "SELECT pinned FROM conversations "
          "WHERE conversation_id = 'conversation'",
        )
        .getSingle();
    expect(conversation.read<int>('pinned'), 0);
    await upgraded.close();
  });

  test(
    'version-eight upgrade preserves data and adds MLS maintenance state',
    () async {
      final current = LocalDatabase(NativeDatabase(databaseFile));
      await current.customSelect('SELECT 1').getSingle();
      await current.customStatement(
        "INSERT INTO local_preferences "
        "(preference_key, value_ciphertext, value_version) "
        "VALUES ('piece-19-preserved', X'09', 1)",
      );
      await current.close();

      final versionEight = sqlite3.open(databaseFile.path);
      _dropPieceNineteenSchema(versionEight);
      versionEight.execute('PRAGMA user_version = 8');
      versionEight.close();

      final upgraded = LocalDatabase(NativeDatabase(databaseFile));
      await upgraded.customSelect('SELECT 1').getSingle();

      expect(
        await upgraded
            .customSelect(
              "SELECT preference_key FROM local_preferences "
              "WHERE preference_key = 'piece-19-preserved'",
            )
            .getSingle(),
        isNotNull,
      );
      expect(
        await upgraded
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' "
              "AND name = 'mls_key_package_maintenance_states'",
            )
            .getSingle(),
        isNotNull,
      );
      expect(
        await upgraded
            .customSelect('PRAGMA user_version')
            .map((row) => row.read<int>('user_version'))
            .getSingle(),
        LocalDatabase.currentSchemaVersion,
      );
      await upgraded.close();
    },
  );

  test('version-nine upgrade adds exact group outbound recipients', () async {
    final current = LocalDatabase(NativeDatabase(databaseFile));
    await current.customSelect('SELECT 1').getSingle();
    await current.customStatement(
      "INSERT INTO local_preferences "
      "(preference_key, value_ciphertext, value_version) "
      "VALUES ('piece-19-v10-preserved', X'0A', 1)",
    );
    await current.close();

    final versionNine = sqlite3.open(databaseFile.path);
    versionNine.execute(
      'ALTER TABLE group_outbound_objects '
      'DROP COLUMN recipient_user_ids_json',
    );
    versionNine.execute('PRAGMA user_version = 9');
    versionNine.close();

    final upgraded = LocalDatabase(NativeDatabase(databaseFile));
    await upgraded.customSelect('SELECT 1').getSingle();
    expect(
      await upgraded
          .customSelect(
            "SELECT preference_key FROM local_preferences "
            "WHERE preference_key = 'piece-19-v10-preserved'",
          )
          .getSingle(),
      isNotNull,
    );
    final columns = await upgraded
        .customSelect('PRAGMA table_info(group_outbound_objects)')
        .map((row) => row.read<String>('name'))
        .get();
    expect(columns, contains('recipient_user_ids_json'));
    expect(
      await upgraded
          .customSelect('PRAGMA user_version')
          .map((row) => row.read<int>('user_version'))
          .getSingle(),
      LocalDatabase.currentSchemaVersion,
    );
    await upgraded.close();
  });

  test(
    'version-ten upgrade adds fail-closed control transcript evidence',
    () async {
      final current = LocalDatabase(NativeDatabase(databaseFile));
      await current.customSelect('SELECT 1').getSingle();
      await current.close();

      final versionTen = sqlite3.open(databaseFile.path)
        ..execute(
          'ALTER TABLE group_control_events '
          'DROP COLUMN deterministic_projection',
        )
        ..execute('ALTER TABLE group_control_events DROP COLUMN signed_payload')
        ..execute(
          'ALTER TABLE group_control_events '
          'DROP COLUMN signer_authentication_proof',
        )
        ..execute('PRAGMA user_version = 10');
      versionTen.close();

      final upgraded = LocalDatabase(NativeDatabase(databaseFile));
      await upgraded.customSelect('SELECT 1').getSingle();
      final columns = await upgraded
          .customSelect('PRAGMA table_info(group_control_events)')
          .map((row) => row.read<String>('name'))
          .get();
      expect(
        columns,
        containsAll(<String>[
          'deterministic_projection',
          'signed_payload',
          'signer_authentication_proof',
        ]),
      );
      await upgraded.close();
    },
  );
}

void _dropPieceFourteenSchema(Database database) {
  for (final table in const [
    'application_events',
    'unsupported_application_events',
    'application_sender_counters',
    'message_reactions',
    'pending_application_receipts',
  ]) {
    database.execute('DROP TABLE $table');
  }
  for (final column in const [
    'peer_user_id',
    'last_activity_event_id',
    'unread_count',
    'muted_until',
    'draft_ciphertext',
    'pinned',
  ]) {
    database.execute('ALTER TABLE conversations DROP COLUMN $column');
  }
  for (final column in const [
    'sender_user_id',
    'sender_device_id',
    'reply_to_message_id',
    'quote_fallback_ciphertext',
    'ordering_ms',
    'ordering_event_id',
    'timestamp_state',
    'deleted_for_everyone',
    'deleted_for_me',
    'pinned',
    'starred',
    'unread',
  ]) {
    database.execute('ALTER TABLE messages DROP COLUMN $column');
  }
}

void _dropPieceEighteenSchema(Database database) {
  database
    ..execute('DROP TABLE group_outbound_objects')
    ..execute('DROP TABLE group_control_events')
    ..execute(
      'ALTER TABLE mls_groups DROP COLUMN control_projection_ciphertext',
    )
    ..execute('ALTER TABLE mls_groups DROP COLUMN control_revision')
    ..execute('ALTER TABLE mls_groups DROP COLUMN control_state_hash')
    ..execute('ALTER TABLE mls_groups DROP COLUMN lifecycle')
    ..execute('ALTER TABLE mls_groups DROP COLUMN pending_mutation_id')
    ..execute('ALTER TABLE conversations DROP COLUMN display_title_ciphertext');
}

void _dropPieceNineteenSchema(Database database) {
  database.execute('DROP TABLE mls_key_package_maintenance_states');
}

final class _FailAfterSchemaCreation extends StorageMigrationHooks {
  @override
  Future<void> afterUpgrade(int from, int to) {
    throw StateError('fault-injected migration failure');
  }
}

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
        )
        ..execute('PRAGMA user_version = 1');
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
        )
        ..execute('PRAGMA user_version = 3');
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
}

final class _FailAfterSchemaCreation extends StorageMigrationHooks {
  @override
  Future<void> afterUpgrade(int from, int to) {
    throw StateError('fault-injected migration failure');
  }
}

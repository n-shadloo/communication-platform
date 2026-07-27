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

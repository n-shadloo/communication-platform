import 'dart:io';

import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// The write kinds [StorageFaultInjector] can interrupt.
enum InjectedWrite {
  insert('BEFORE INSERT'),
  update('BEFORE UPDATE'),
  delete('BEFORE DELETE');

  const InjectedWrite(this.clause);

  final String clause;
}

/// Fails one exact statement inside an otherwise real Drift transaction.
///
/// A temporary SQLite trigger raises `ABORT`, so production code sees the same
/// exception a failing platform storage layer raises and runs its own rollback
/// against a real database. Nothing under `lib/` is stubbed, subclassed, or
/// given a test-only seam, which is what makes the result evidence about the
/// shipped commit boundary rather than about a fake.
///
/// The trigger is temporary, so it lives on the connection and not in the
/// schema: a simulated process restart reopens healthy storage, exactly as a
/// device does after the transient failure that killed the previous run.
final class StorageFaultInjector {
  StorageFaultInjector(this._database);

  final LocalDatabase _database;
  final _installed = <String>[];

  /// Aborts every [write] against [table] until [repair] is called.
  ///
  /// [when] is an optional SQLite predicate over the trigger's `NEW`/`OLD`
  /// rows. It selects one row out of several written to the same table in one
  /// transaction, so a failure point can be placed between two writes that a
  /// table-wide trigger could not distinguish.
  Future<void> failOn(String table, InjectedWrite write, {String? when}) async {
    final name = 'cp_injected_fault_${_installed.length}';
    final guard = when == null ? '' : ' WHEN $when';
    await _database.customStatement(
      'CREATE TEMP TRIGGER $name ${write.clause} ON $table$guard '
      "BEGIN SELECT RAISE(ABORT, 'injected storage fault: $table'); END;",
    );
    _installed.add(name);
  }

  /// Removes every installed fault, as a restart onto healthy storage does.
  Future<void> repair() async {
    for (final name in _installed) {
      await _database.customStatement('DROP TRIGGER $name');
    }
    _installed.clear();
  }
}

/// A file-backed [LocalDatabase] that can be dropped and reopened.
///
/// Process death is modelled by discarding every Dart object in the stack and
/// reopening the same file. Anything the next run needs must therefore be in
/// durable storage, and the reopen runs the production `beforeOpen` path,
/// whose `PRAGMA quick_check` fails the test if the interrupted write left the
/// file inconsistent.
///
/// This models a process that dies between transactions, not a power cut in
/// the middle of an fsync; the latter needs the physical-device matrix.
final class RestartableDatabase {
  RestartableDatabase._(this._directory, this.database);

  static Future<RestartableDatabase> create(String prefix) async {
    // Reopening the same file is the point of this helper, so drift's
    // duplicate-instance warning is expected rather than a signal.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final directory = await Directory.systemTemp.createTemp(prefix);
    final database = LocalDatabase(
      NativeDatabase(File('${directory.path}/local.sqlite')),
    );
    return RestartableDatabase._(directory, database);
  }

  final Directory _directory;

  /// The currently open database. Replaced by [restart].
  LocalDatabase database;

  /// Closes the open connection and opens a new one over the same file.
  Future<LocalDatabase> restart() async {
    await database.close();
    database = LocalDatabase(
      NativeDatabase(File('${_directory.path}/local.sqlite')),
    );
    return database;
  }

  Future<void> dispose() async {
    await database.close();
    await _directory.delete(recursive: true);
  }
}

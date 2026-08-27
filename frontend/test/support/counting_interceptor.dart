import 'package:drift/drift.dart';

/// Counts every statement that reaches the database, transactions included.
///
/// Shared because more than one cost is worth a regression test, and because a
/// second copy of this would be a second definition of what "one statement"
/// means. Attach it with `NativeDatabase.memory().interceptWith(counter)`.
final class CountingInterceptor extends QueryInterceptor {
  int statements = 0;

  void reset() => statements = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    statements += 1;
    return super.runSelect(executor, statement, args);
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    statements += 1;
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    statements += 1;
    return super.runUpdate(executor, statement, args);
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    statements += 1;
    return super.runDelete(executor, statement, args);
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    statements += 1;
    return super.runCustom(executor, statement, args);
  }
}

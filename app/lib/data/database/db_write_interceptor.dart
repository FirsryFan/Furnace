import 'package:drift/drift.dart';

import '../../core/state/data_change_bus.dart';

/// Reports every committed write to [DataChangeBus].
///
/// Installed once, in `_openConnection`, through drift's own `interceptWith`.
/// It is deliberately the only write hook in the app: repositories, raw
/// `customStatement` calls, batches and the AI tool layer all go through the
/// executor, so none of them can forget to announce a change.
///
/// Reads ([runSelect]) are never reported; a statement that both reads and
/// writes (a `PRAGMA`, a self-heal `CREATE INDEX IF NOT EXISTS`) costs one extra
/// refresh at most, and those run before the first listener exists.
class DbWriteInterceptor extends QueryInterceptor {
  DbWriteInterceptor();

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final inserted = await executor.runInsert(statement, args);
    DataChangeBus.instance.recordChange();
    return inserted;
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final updated = await executor.runUpdate(statement, args);
    DataChangeBus.instance.recordChange();
    return updated;
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final deleted = await executor.runDelete(statement, args);
    DataChangeBus.instance.recordChange();
    return deleted;
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    await executor.runCustom(statement, args);
    DataChangeBus.instance.recordChange();
  }

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements,
  ) async {
    await executor.runBatched(statements);
    DataChangeBus.instance.recordChange();
  }
}

import 'package:drift/drift.dart';

import '../../domain/services/thread/thread_flow_writer.dart';
import '../../domain/services/thread/thread_node_kind.dart';
import '../../domain/services/thread/thread_status.dart';
import '../database/database.dart';
import '../ids.dart';

/// Repository for tasks, subtasks, dependencies and task-time links.
///
/// `tasks` is the Thread node table (contract §3.1): **status transitions are
/// written by [ThreadFlowWriter]**, never by a bare `UPDATE tasks.status`.
/// Creation, start, complete, submit, stuck, skip and reopen all funnel through
/// the writer so the append-only `thread_events` flow gets one row per fact.
/// `updateTask(status:)` is a routing convenience over the same writer: it has
/// **no direct status write** left (v47's `reopened` event landed in task-90, so
/// the old `todo` direct-write exception is gone).
class TaskRepository {
  TaskRepository(this._db);

  final AppDatabase _db;

  /// The single status write port (v47). Kept lazy so constructing the
  /// repository stays cheap.
  late final ThreadFlowWriter _flow = ThreadFlowWriter(_db);

  Future<Task> createTask({
    required String title,
    String? parentId,
    String description = '',
    String status = 'todo',
    int priority = 1,
    int? estimateMinutes,
    int? dueAt,
    int? remindAt,
    int? expectedAt,
    int? energyRequired,
    int? startedAt,
    ThreadNodeKind kind = ThreadNodeKind.task,
    String? sourceKey,
  }) async {
    // Creation also goes through the writer: a node is born with a `created`
    // event, and `source_key` makes materialisation idempotent (paper/week/day/
    // review nodes). Without a source key every call inserts a new row, exactly
    // like the old `createTask`.
    return _flow.ensureTask(
      title: title,
      kind: kind,
      sourceKey: sourceKey,
      parentId: parentId,
      description: description,
      status: status,
      priority: priority,
      estimateMinutes: estimateMinutes,
      dueAt: dueAt,
      remindAt: remindAt,
      expectedAt: expectedAt,
      energyRequired: energyRequired,
      startedAt: startedAt,
    );
  }

  Future<List<Task>> getTasks({
    String? parentId,
    bool includeDone = true,
  }) {
    final query = _db.select(_db.tasks);
    if (parentId != null) {
      query.where((t) => t.parentId.equals(parentId));
    }
    if (!includeDone) {
      // v47: open means exactly `todo|doing`. `blocked`/`skipped` are neither
      // 待办 nor 完成 — they must not leak into ready lists or the scheduler.
      query.where(
        (t) => t.status.isIn(
          <String>[ThreadStatus.todo.id, ThreadStatus.doing.id],
        ),
      );
    }
    query.orderBy([
      (t) => OrderingTerm.desc(t.priority),
      (t) => OrderingTerm.asc(t.createdAt),
    ]);
    return query.get();
  }

  Future<List<Task>> getOpenTasks() => getTasks(includeDone: false);

  Future<Task?> getTaskById(String id) {
    return (_db.select(_db.tasks)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// 按 id 批量取任务（只读；标签知识入口一次取回标签挂着的全部 Thread 节点）。
  ///
  /// 去空、去重后按 500 分块（SQLite 绑定变量上限）。只返回仍然存在的行：
  /// `object_tags` 没有指向 `tasks` 的外键，删任务后的残留链接由调用方计数，
  /// 这里不伪造行。顺序不保证，调用方自己排。
  Future<List<Task>> byIds(Iterable<String> ids) async {
    final clean = <String>[];
    final seen = <String>{};
    for (final raw in ids) {
      final id = raw.trim();
      if (id.isEmpty || !seen.add(id)) {
        continue;
      }
      clean.add(id);
    }
    if (clean.isEmpty) {
      return const <Task>[];
    }
    final result = <Task>[];
    const chunkSize = 500;
    for (var start = 0; start < clean.length; start += chunkSize) {
      final end =
          start + chunkSize < clean.length ? start + chunkSize : clean.length;
      result.addAll(
        await (_db.select(_db.tasks)
              ..where((t) => t.id.isIn(clean.sublist(start, end))))
            .get(),
      );
    }
    return result;
  }

  Future<void> updateTask(
    String id, {
    String? title,
    String? description,
    String? status,
    int? priority,
    int? estimateMinutes,
    int? dueAt,
    int? remindAt,
    int? expectedAt,
    int? energyRequired,
    int? startedAt,
    bool clearDueAt = false,
    bool clearRemindAt = false,
    bool clearExpectedAt = false,
    bool clearEnergyRequired = false,
    bool clearStartedAt = false,
  }) async {
    // A status change is a ThreadFlow transition, not a column edit: all five
    // v47 statuses have an event (todo goes through `reopened` since task-90),
    // so they are routed through the writer and `status` is **never** written
    // by the UPDATE below. An unknown value is a caller bug and throws; an
    // unknown id stays the old silent no-op (routing is skipped, and every
    // other field's UPDATE simply matches no row).
    if (status != null) {
      final current = await getTaskById(id);
      if (current != null && current.status != status) {
        await _routeStatus(id, status);
      }
    }

    await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        title: title == null ? const Value.absent() : Value(title),
        description:
            description == null ? const Value.absent() : Value(description),
        priority: priority == null ? const Value.absent() : Value(priority),
        estimateMinutes: estimateMinutes == null
            ? const Value.absent()
            : Value(estimateMinutes),
        dueAt: clearDueAt
            ? Value<int?>(null)
            : (dueAt == null ? const Value.absent() : Value(dueAt)),
        remindAt: clearRemindAt
            ? Value<int?>(null)
            : (remindAt == null ? const Value.absent() : Value(remindAt)),
        expectedAt: clearExpectedAt
            ? Value<int?>(null)
            : (expectedAt == null ? const Value.absent() : Value(expectedAt)),
        energyRequired: clearEnergyRequired
            ? Value<int?>(null)
            : (energyRequired == null
                ? const Value.absent()
                : Value(energyRequired)),
        startedAt: clearStartedAt
            ? Value<int?>(null)
            : (startedAt == null ? const Value.absent() : Value(startedAt)),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// Stamps the moment the user starts working on [id].
  ///
  /// This is the only "start" bookkeeping there is: no ticking timer runs, the
  /// actual duration is derived later from start/completion stamps
  /// (blueprint 2.6). v47: it is a `todo|doing|blocked → doing` transition, so
  /// the started stamp and the `started` event are written in one transaction.
  ///
  /// An unknown id stays a silent no-op, matching the pre-v47 behaviour.
  Future<void> startTask(String id, {DateTime? at}) async {
    final existing = await getTaskById(id);
    if (existing == null) {
      return;
    }
    await _flow.start(id, at: at);
  }

  /// Marks [id] done and writes a completion-history snapshot
  /// (Thread -> History, spec 2). [tagIds]/[tagPaths] must be the task's tag
  /// snapshot at completion time; they feed the fatigue penalty.
  ///
  /// v3 (blueprint 2.6): when the event has a `started_at` stamp, the actual
  /// duration is computed as `completed - started` in whole minutes - nothing
  /// is ever timed in the background. A suspiciously long record is excluded
  /// from the duration model by default ([useActualTime] mirrors the global
  /// switch) while remaining visible and switchable.
  ///
  /// v47: one transaction writes `status=done` + `completed_at` + the
  /// `completed` thread event + the completion-log snapshot (only `completed`
  /// writes history; see [ThreadFlowWriter]). An unknown id stays a silent
  /// no-op, matching the pre-v47 behaviour.
  Future<void> completeTask(
    String id, {
    List<String>? tagIds,
    List<String>? tagPaths,
    int? estimateMinutes,
    int? energyRequired,
    String? title,
    bool useActualTime = true,
    DateTime? completedAt,
  }) async {
    final task = await getTaskById(id);
    if (task == null) {
      return;
    }
    await _flow.complete(
      id,
      at: completedAt,
      tagIds: tagIds,
      tagPaths: tagPaths,
      title: title,
      estimateMinutes: estimateMinutes,
      energyRequired: energyRequired,
      useActualTime: useActualTime,
    );
  }

  /// 提交答案/交卷（状态不变；只追加 `submitted` 事实，不写完成历史）。
  Future<ThreadTransitionResult> submitTask(
    String id, {
    Map<String, Object?> payload = const <String, Object?>{},
    String? sourceKey,
    DateTime? at,
  }) =>
      _flow.submit(id, at: at, payload: payload, sourceKey: sourceKey);

  /// 卡住（todo/doing → blocked；不写完成历史、不写正确性）。
  Future<ThreadTransitionResult> markTaskStuck(
    String id, {
    String? reason,
    Map<String, Object?> payload = const <String, Object?>{},
    String? sourceKey,
    DateTime? at,
  }) =>
      _flow.markStuck(
        id,
        reason: reason,
        at: at,
        payload: payload,
        sourceKey: sourceKey,
      );

  /// 跳过（todo/doing/blocked → skipped；行与引用保留）。
  Future<ThreadTransitionResult> skipTask(
    String id, {
    String? reason,
    Map<String, Object?> payload = const <String, Object?>{},
    String? sourceKey,
    DateTime? at,
  }) =>
      _flow.skip(
        id,
        reason: reason,
        at: at,
        payload: payload,
        sourceKey: sourceKey,
      );

  /// 重开/恢复（blocked/skipped/done → todo；写一条 `reopened` 事件）。
  ///
  /// 只清 `tasks.completed_at`，**不回滚** `completion_logs`；`started_at` 按
  /// 契约 §3.4 保持原样。状态机拒绝来源状态（例如 `todo → todo`、`doing →
  /// todo`）时抛 [StateError]，与其它迁移入口一致。
  Future<ThreadTransitionResult> reopenTask(
    String id, {
    String? reason,
    Map<String, Object?> payload = const <String, Object?>{},
    String? sourceKey,
    DateTime? at,
  }) =>
      _flow.reopen(
        id,
        reason: reason,
        at: at,
        payload: payload,
        sourceKey: sourceKey,
      );

  /// Routes a status value through the writer.
  ///
  /// All five [ThreadStatus] ids are accepted here and nowhere else writes
  /// `tasks.status`; anything else is a caller bug and throws [ArgumentError]
  /// instead of silently writing an unknown string (that silent path was the
  /// old `directStatus` fallback removed in task-90).
  Future<void> _routeStatus(String id, String status) async {
    if (status == ThreadStatus.todo.id) {
      await reopenTask(id);
    } else if (status == ThreadStatus.done.id) {
      await completeTask(id);
    } else if (status == ThreadStatus.doing.id) {
      await startTask(id);
    } else if (status == ThreadStatus.blocked.id) {
      await _flow.markStuck(id);
    } else if (status == ThreadStatus.skipped.id) {
      await _flow.skip(id);
    } else {
      throw ArgumentError.value(status, 'status', 'not a ThreadStatus id');
    }
  }

  /// Flips the "may this record feed the duration model" flag on one
  /// completion record (blueprint 2.6 - the user stays in control per record).
  Future<void> setCompletionInModel(String completionId, bool include) async {
    await (_db.update(_db.completionLogs)
          ..where((c) => c.id.equals(completionId)))
        .write(CompletionLogsCompanion(includeInModel: Value(include)));
  }

  /// Completion records that the user allowed to inform the duration model.
  Future<List<CompletionLog>> getModelCompletionLogs() {
    return (_db.select(_db.completionLogs)
          ..where((c) => c.includeInModel.equals(true))
          ..orderBy([(c) => OrderingTerm.desc(c.completedAt)]))
        .get();
  }

  /// Mean estimate error over the model-eligible completion records, as a
  /// multiplier (`actual / estimate`). Returns null until there are records
  /// with both a positive estimate and a recorded actual duration.
  Future<double?> getDurationCalibration() async {
    final logs = await getModelCompletionLogs();
    var sum = 0.0;
    var count = 0;
    for (final log in logs) {
      final estimate = log.estimateMinutes;
      final actualMinutes = log.actualMinutes;
      if (estimate == null || estimate <= 0 || actualMinutes == null) {
        continue;
      }
      sum += actualMinutes / estimate;
      count++;
    }
    if (count == 0) {
      return null;
    }
    return sum / count;
  }

  /// Completion history rows, newest first; [sinceMs] filters by
  /// completion moment.
  Future<List<CompletionLog>> getCompletionLogs({int? sinceMs}) async {
    final query = _db.select(_db.completionLogs);
    if (sinceMs != null) {
      query.where((c) => c.completedAt.isBiggerOrEqualValue(sinceMs));
    }
    query.orderBy([(c) => OrderingTerm.desc(c.completedAt)]);
    return query.get();
  }

  Future<void> deleteTask(String id) async {
    await _db.transaction(() async {
      // Delete subtask links and dependencies that reference this task.
      await (_db.delete(_db.taskDependencies)
            ..where(
              (t) => t.taskId.equals(id) | t.dependsOnTaskId.equals(id),
            ))
          .go();
      await (_db.delete(_db.taskTimeBlocks)..where((t) => t.taskId.equals(id)))
          .go();
      // Delete descendant tasks recursively.
      await _deleteSubtree(id);
    });
  }

  Future<void> addDependency({
    required String taskId,
    required String dependsOnTaskId,
  }) async {
    await _db.into(_db.taskDependencies).insert(
          TaskDependenciesCompanion.insert(
            id: _newId('dep'),
            taskId: taskId,
            dependsOnTaskId: dependsOnTaskId,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> removeDependency({
    required String taskId,
    required String dependsOnTaskId,
  }) async {
    await (_db.delete(_db.taskDependencies)
          ..where(
            (t) =>
                t.taskId.equals(taskId) &
                t.dependsOnTaskId.equals(dependsOnTaskId),
          ))
        .go();
  }

  Future<List<String>> getDependencyIds(String taskId) async {
    final rows = await (_db.select(_db.taskDependencies)
          ..where((t) => t.taskId.equals(taskId)))
        .get();
    return rows.map((r) => r.dependsOnTaskId).toList();
  }

  Future<List<Task>> getTasksForTimeBlock(String timeBlockId) async {
    final query = _db.select(_db.tasks).join([
      innerJoin(
        _db.taskTimeBlocks,
        _db.taskTimeBlocks.taskId.equalsExp(_db.tasks.id),
      ),
    ])
      ..where(_db.taskTimeBlocks.timeBlockId.equals(timeBlockId));
    final rows = await query.get();
    return rows.map((row) => row.readTable(_db.tasks)).toList();
  }

  Future<void> linkTaskToTimeBlock({
    required String taskId,
    required String timeBlockId,
    bool isSuggestion = true,
  }) async {
    await _db.into(_db.taskTimeBlocks).insert(
          TaskTimeBlocksCompanion.insert(
            id: _newId('tt'),
            taskId: taskId,
            timeBlockId: timeBlockId,
            isSuggestion: Value(isSuggestion),
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> _deleteSubtree(String parentId) async {
    final children = await (_db.select(_db.tasks)
          ..where((t) => t.parentId.equals(parentId)))
        .get();
    for (final child in children) {
      await _deleteSubtree(child.id);
    }
    await (_db.delete(_db.taskDependencies)
          ..where(
            (t) => t.taskId.equals(parentId) | t.dependsOnTaskId.equals(parentId),
          ))
        .go();
    await (_db.delete(_db.taskTimeBlocks)
          ..where((t) => t.taskId.equals(parentId)))
        .go();
    // Thread events belong to the node's scheduling history (contract §8), not
    // to learning history: deleting the node deletes its flow. Completion logs
    // are learning history and are deliberately NOT deleted with the task.
    await (_db.delete(_db.threadEvents)
          ..where((e) => e.taskId.equals(parentId)))
        .go();
    await (_db.delete(_db.tasks)..where((t) => t.id.equals(parentId))).go();
  }

  String _newId(String prefix) => Ids.next(prefix);
}

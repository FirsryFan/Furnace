import 'package:drift/drift.dart';

import '../../domain/services/time/actual_time.dart';
import '../database/database.dart';
import '../ids.dart';

/// Repository for tasks, subtasks, dependencies and task-time links.
class TaskRepository {
  TaskRepository(this._db);

  final AppDatabase _db;

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
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _newId('task');
    await _db.into(_db.tasks).insert(
          TasksCompanion.insert(
            id: id,
            parentId: Value(parentId),
            title: title,
            description: Value(description),
            status: Value(status),
            priority: Value(priority),
            estimateMinutes: Value(estimateMinutes),
            dueAt: Value(dueAt),
            remindAt: Value(remindAt),
            expectedAt: Value(expectedAt),
            energyRequired: Value(energyRequired),
            startedAt: Value(startedAt),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (await _db.select(_db.tasks)..where((t) => t.id.equals(id)))
        .getSingle();
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
      query.where((t) => t.status.equals('done').not());
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
    await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        title: title == null ? const Value.absent() : Value(title),
        description:
            description == null ? const Value.absent() : Value(description),
        status: status == null ? const Value.absent() : Value(status),
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
  /// (blueprint 2.6).
  Future<void> startTask(String id, {DateTime? at}) async {
    final now = (at ?? DateTime.now()).millisecondsSinceEpoch;
    await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        startedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
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
    final now = (completedAt ?? DateTime.now()).millisecondsSinceEpoch;
    final task = await getTaskById(id);
    if (task == null) {
      return;
    }

    final startedAt = task.startedAt;
    ActualTimeRecord? actual;
    if (startedAt != null) {
      actual = ActualTime.compute(
        startedAt: DateTime.fromMillisecondsSinceEpoch(startedAt),
        completedAt: DateTime.fromMillisecondsSinceEpoch(now),
        estimateMinutes: estimateMinutes ?? task.estimateMinutes,
      );
    }

    await _db.transaction(() async {
      await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
        TasksCompanion(
          status: const Value('done'),
          completedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      await _db.into(_db.completionLogs).insert(
            CompletionLogsCompanion.insert(
              id: _newId('cl'),
              taskId: id,
              title: title ?? task.title,
              tagIds: Value(_encodeList(tagIds)),
              tagPaths: Value(_encodeList(tagPaths)),
              estimateMinutes: Value(estimateMinutes ?? task.estimateMinutes),
              energyRequired: Value(energyRequired ?? task.energyRequired),
              completedAt: now,
              actualMinutes: Value(actual?.actualMinutes),
              includeInModel:
                  Value(useActualTime && (actual?.includeInModel ?? true)),
              durationSuspicious: Value(actual?.suspicious ?? false),
              createdAt: now,
            ),
          );
    });
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

  static String? _encodeList(List<String>? values) {
    if (values == null || values.isEmpty) {
      return null;
    }
    return values.join('\u0001');
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
    await (_db.delete(_db.tasks)..where((t) => t.id.equals(parentId))).go();
  }

  String _newId(String prefix) => Ids.next(prefix);
}

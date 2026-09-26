import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/database/database.dart';
import '../../../data/repositories/task_repository.dart';
import '../domain/ai_tool.dart';

/// Task operations exposed to the model.
///
/// Two tools rather than one per repository method: the task repository has a
/// dozen methods, and offering a dozen tools makes the *choice* of tool the
/// hard part for the model. Grouping by module with an explicit `action`
/// argument keeps the list short, and the description spells out each action's
/// required arguments (AI_DESIGN D6).
///
/// Every call goes through [TaskRepository], never through SQL, so the AI
/// inherits the same rules the UI has and the Thread screen refreshes on its
/// own (D2).
class QueryTasksTool extends AiTool {
  QueryTasksTool(this._tasks, this._db);

  final TaskRepository _tasks;
  final AppDatabase _db;

  /// The model gets a bounded answer, not the whole table: dumping every row
  /// crowds out the conversation and burns tokens. It can page with [limit].
  static const int defaultLimit = 20;
  static const int maxLimit = 200;

  @override
  String get name => 'query_tasks';

  @override
  String get description =>
      '查询用户的任务/事件列表。用于回答"我有什么任务""哪些快到期了""这个任务的状态"等问题，'
      '或在创建任务前先确认是否已存在。返回按优先级与创建时间排序的摘要。'
      '只读，不会修改任何数据。';

  @override
  Map<String, Object?> get parameters => {
        'type': 'object',
        'properties': {
          'status': {
            'type': 'string',
            'description': '按状态过滤：todo（未完成，默认）| done（已完成）| all（全部）',
            'enum': ['todo', 'done', 'all'],
          },
          'search': {
            'type': 'string',
            'description': '在标题与描述里做不区分大小写的包含匹配',
          },
          'due_before': {
            'type': 'string',
            'description': '只返回该时刻之前到期的任务，ISO-8601 字符串或毫秒时间戳',
          },
          'due_after': {
            'type': 'string',
            'description': '只返回该时刻之后到期的任务，ISO-8601 字符串或毫秒时间戳',
          },
          'limit': {
            'type': 'integer',
            'description': '最多返回几条，默认 $defaultLimit，上限 $maxLimit',
          },
        },
        'required': <String>[],
      };

  @override
  ToolRisk riskFor(String action) => ToolRisk.write; // unused: no actions

  @override
  bool reversibleFor(String action) => true;

  @override
  bool get availableOnCurrentPlatform => true;

  @override
  Future<ToolResult> run(ToolInvocation invocation) async {
    // `action` is absent for single-purpose tools, so validate what exists and
    // ignore an unknown action instead of failing a read.
    final args = ToolArgs(invocation.arguments);
    final status = args.optString('status') ?? 'todo';
    final search = args.optString('search')?.toLowerCase();
    final dueBefore = args.optEpochMs('due_before');
    final dueAfter = args.optEpochMs('due_after');
    final limit = (args.optInt('limit') ?? defaultLimit).clamp(1, maxLimit);

    final all = await _tasks.getTasks(includeDone: true);
    final filtered = all.where((task) {
      if (status == 'todo' && task.status == 'done') {
        return false;
      }
      if (status == 'done' && task.status != 'done') {
        return false;
      }
      if (search != null) {
        final haystack =
            '${task.title} ${task.description ?? ''}'.toLowerCase();
        if (!haystack.contains(search)) {
          return false;
        }
      }
      if (dueBefore != null && (task.dueAt == null || task.dueAt! > dueBefore)) {
        return false;
      }
      if (dueAfter != null && (task.dueAt == null || task.dueAt! < dueAfter)) {
        return false;
      }
      return true;
    }).toList();

    final page = filtered.take(limit).toList();
    final rows = await Future.wait(page.map(_summarise));

    return ToolResult(
      ok: true,
      summary: filtered.isEmpty
          ? '没有符合条件的任务'
          : '找到 ${filtered.length} 个任务，返回前 ${page.length} 个',
      modelResult: {
        'total_matching': filtered.length,
        'returned': page.length,
        'truncated': filtered.length > page.length,
        'tasks': rows,
      },
    );
  }

  Future<Map<String, Object?>> _summarise(Task task) async {
    final dependencyRows = await (_db.select(_db.taskDependencies)
          ..where((t) => t.taskId.equals(task.id)))
        .get();
    return {
      'id': task.id,
      'title': task.title,
      if (task.description != null && task.description!.isNotEmpty)
        'description': task.description,
      'status': task.status,
      'priority': task.priority,
      if (task.estimateMinutes != null) 'estimate_minutes': task.estimateMinutes,
      if (task.dueAt != null) 'due_at_ms': task.dueAt,
      if (task.expectedAt != null) 'expected_at_ms': task.expectedAt,
      if (task.startedAt != null) 'started_at_ms': task.startedAt,
      if (task.completedAt != null) 'completed_at_ms': task.completedAt,
      if (task.parentId != null) 'parent_id': task.parentId,
      'depends_on': [for (final d in dependencyRows) d.dependsOnTaskId],
    };
  }
}

/// Create / update / complete / start / delete / link tasks.
class ManageTaskTool extends AiTool {
  ManageTaskTool(this._tasks, this._db);

  final TaskRepository _tasks;
  final AppDatabase _db;

  static const Set<String> actions = {
    'create',
    'update',
    'complete',
    'start',
    'delete',
    'add_dependency',
  };

  @override
  String get name => 'manage_task';

  @override
  String get description =>
      '创建、修改、完成、开始、删除任务，或给任务加依赖。'
      'create 需要 title；update/complete/start/delete/add_dependency 需要 id。'
      '时间字段用 ISO-8601 字符串或毫秒时间戳。'
      '删除是破坏性操作，无论什么权限模式都需要用户逐条确认。';

  @override
  Map<String, Object?> get parameters => {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': actions.toList(),
            'description': '要执行的操作',
          },
          'id': {'type': 'string', 'description': '任务 id（update/complete/start/delete 必填，可从 query_tasks 得到）'},
          'title': {'type': 'string', 'description': '标题（create 必填；update 可选）'},
          'description': {'type': 'string', 'description': '描述'},
          'priority': {'type': 'integer', 'description': '优先级，1 最低；默认 1'},
          'estimate_minutes': {'type': 'integer', 'description': '预估分钟数'},
          'due_at': {'type': 'string', 'description': '截止时刻'},
          'expected_at': {'type': 'string', 'description': '期望完成时刻（软约束）'},
          'remind_at': {'type': 'string', 'description': '提醒时刻'},
          'energy_required': {'type': 'integer', 'description': '所需精力 1-10'},
          'depends_on_task_id': {
            'type': 'string',
            'description': 'add_dependency 时：必须先完成的那个任务 id',
          },
        },
        'required': ['action'],
      };

  @override
  ToolRisk riskFor(String action) =>
      action == 'delete' ? ToolRisk.destructive : ToolRisk.write;

  @override
  bool reversibleFor(String action) {
    // Every action here can be undone: create by deleting, update and complete
    // because the whole previous row is snapshotted, delete because the row
    // (plus its dependency edges) is snapshotted before removal.
    return true;
  }

  @override
  bool get availableOnCurrentPlatform => true;

  @override
  Future<ToolResult> run(ToolInvocation invocation) async {
    final args = ToolArgs(invocation.arguments);
    // A validation failure is caused by the model, so it becomes a tool result
    // the model can read and correct - never an exception that loses the turn.
    try {
      final action = args.requireAction(actions);
      return switch (action) {
        'create' => await _create(args),
        'update' => await _update(args),
        'complete' => await _complete(args),
        'start' => await _start(args),
        'delete' => await _delete(args),
        'add_dependency' => await _addDependency(args),
        _ => ToolResult.failure('不支持的 action: $action'),
      };
    } on ToolArgError catch (e) {
      return ToolResult.failure(e.message);
    }
  }

  Future<ToolResult> _create(ToolArgs args) async {
    final title = args.requireString('title');
    final task = await _tasks.createTask(
      title: title,
      description: args.optString('description') ?? '',
      priority: args.optInt('priority') ?? 1,
      estimateMinutes: args.optInt('estimate_minutes'),
      dueAt: args.optEpochMs('due_at'),
      remindAt: args.optEpochMs('remind_at'),
      expectedAt: args.optEpochMs('expected_at'),
      energyRequired: args.optInt('energy_required'),
    );
    return ToolResult(
      ok: true,
      summary: '已创建任务「${task.title}」',
      modelResult: {'id': task.id, 'title': task.title},
      // A create is undone by deleting the row it produced.
      afterJson: jsonEncode(await snapshotTask(_db, task.id)),
    );
  }

  Future<ToolResult> _update(ToolArgs args) async {
    final id = args.requireString('id');
    final before = await snapshotTask(_db, id);
    if (before == null) {
      return const ToolResult.failure('找不到任务');
    }
    final title = args.optString('title');
    if (title == null &&
        args.optString('description') == null &&
        args.optInt('priority') == null &&
        args.optInt('estimate_minutes') == null &&
        args.optEpochMs('due_at') == null &&
        args.optEpochMs('expected_at') == null &&
        args.optEpochMs('remind_at') == null &&
        args.optInt('energy_required') == null) {
      return const ToolResult.failure('update 至少要给一个要改的字段');
    }

    await _tasks.updateTask(
      id,
      title: title,
      description: args.optString('description'),
      priority: args.optInt('priority'),
      estimateMinutes: args.optInt('estimate_minutes'),
      dueAt: args.optEpochMs('due_at'),
      expectedAt: args.optEpochMs('expected_at'),
      remindAt: args.optEpochMs('remind_at'),
      energyRequired: args.optInt('energy_required'),
    );
    return ToolResult(
      ok: true,
      summary: '已更新任务「${before['title']}」',
      modelResult: {'id': id},
      beforeJson: jsonEncode(before),
      afterJson: jsonEncode(await snapshotTask(_db, id)),
    );
  }

  Future<ToolResult> _complete(ToolArgs args) async {
    final id = args.requireString('id');
    final before = await snapshotTask(_db, id);
    if (before == null) {
      return const ToolResult.failure('找不到任务');
    }
    await _tasks.completeTask(id);
    return ToolResult(
      ok: true,
      summary: '已完成任务「${before['title']}」',
      modelResult: {'id': id},
      beforeJson: jsonEncode(before),
      afterJson: jsonEncode(await snapshotTask(_db, id)),
    );
  }

  Future<ToolResult> _start(ToolArgs args) async {
    final id = args.requireString('id');
    final before = await snapshotTask(_db, id);
    if (before == null) {
      return const ToolResult.failure('找不到任务');
    }
    await _tasks.startTask(id);
    return ToolResult(
      ok: true,
      summary: '已开始任务「${before['title']}」',
      modelResult: {'id': id},
      beforeJson: jsonEncode(before),
      afterJson: jsonEncode(await snapshotTask(_db, id)),
    );
  }

  Future<ToolResult> _delete(ToolArgs args) async {
    final id = args.requireString('id');
    final before = await snapshotTask(_db, id);
    if (before == null) {
      return const ToolResult.failure('找不到任务');
    }
    await _tasks.deleteTask(id);
    return ToolResult(
      ok: true,
      summary: '已删除任务「${before['title']}」',
      modelResult: {'id': id, 'deleted': true},
      // The whole row plus its dependency edges, so undo can put it back.
      beforeJson: jsonEncode(before),
    );
  }

  Future<ToolResult> _addDependency(ToolArgs args) async {
    final id = args.requireString('id');
    final dependsOn = args.requireString('depends_on_task_id');
    if (id == dependsOn) {
      return const ToolResult.failure('任务不能依赖自己');
    }
    final before = await snapshotTask(_db, id);
    if (before == null) {
      return const ToolResult.failure('找不到任务');
    }
    if (await snapshotTask(_db, dependsOn) == null) {
      return const ToolResult.failure('找不到要依赖的任务');
    }
    await _tasks.addDependency(taskId: id, dependsOnTaskId: dependsOn);
    return ToolResult(
      ok: true,
      summary: '已让「${before['title']}」依赖另一项任务',
      modelResult: {'id': id, 'depends_on': dependsOn},
      beforeJson: jsonEncode(before),
      afterJson: jsonEncode(await snapshotTask(_db, id)),
    );
  }
}

/// Reads everything needed to restore a task, or null when it does not exist.
///
/// Deliberately captures the dependency edges as well as the row: `deleteTask`
/// removes them, and an undo that restored the task but not its dependencies
/// would silently change the user's plan.
Future<Map<String, Object?>?> snapshotTask(AppDatabase db, String id) async {
  final rows = await (db.select(db.tasks)..where((t) => t.id.equals(id))).get();
  if (rows.isEmpty) {
    return null;
  }
  final task = rows.first;
  final outgoing = await (db.select(db.taskDependencies)
        ..where((t) => t.taskId.equals(id)))
      .get();
  final incoming = await (db.select(db.taskDependencies)
        ..where((t) => t.dependsOnTaskId.equals(id)))
      .get();
  return {
    'task': {
      'id': task.id,
      'parent_id': task.parentId,
      'title': task.title,
      'description': task.description,
      'status': task.status,
      'priority': task.priority,
      'estimate_minutes': task.estimateMinutes,
      'due_at': task.dueAt,
      'remind_at': task.remindAt,
      'expected_at': task.expectedAt,
      'started_at': task.startedAt,
      'energy_required': task.energyRequired,
      'completed_at': task.completedAt,
      'created_at': task.createdAt,
      'updated_at': task.updatedAt,
    },
    'depends_on': [for (final d in outgoing) d.dependsOnTaskId],
    'depended_on_by': [for (final d in incoming) d.taskId],
  };
}

/// Puts a snapshotted task back, used by undo.
///
/// Kept next to [snapshotTask] so the two cannot drift apart.
Future<void> restoreTask(AppDatabase db, Map<String, Object?> snapshot) async {
  final raw = (snapshot['task'] as Map).cast<String, Object?>();
  final id = raw['id'] as String;
  await db.into(db.tasks).insert(
        TasksCompanion.insert(
          id: id,
          parentId: Value(raw['parent_id'] as String?),
          title: raw['title'] as String,
          description: Value(raw['description'] as String?),
          status: Value(raw['status'] as String),
          priority: Value(raw['priority'] as int),
          estimateMinutes: Value(raw['estimate_minutes'] as int?),
          dueAt: Value(raw['due_at'] as int?),
          remindAt: Value(raw['remind_at'] as int?),
          expectedAt: Value(raw['expected_at'] as int?),
          startedAt: Value(raw['started_at'] as int?),
          energyRequired: Value(raw['energy_required'] as int?),
          completedAt: Value(raw['completed_at'] as int?),
          createdAt: raw['created_at'] as int,
          updatedAt: raw['updated_at'] as int,
        ),
        mode: InsertMode.insertOrReplace,
      );

  // Dependency edges are remove-then-insert: the snapshot is the truth.
  await (db.delete(db.taskDependencies)
        ..where((t) => t.taskId.equals(id) | t.dependsOnTaskId.equals(id)))
      .go();
  final now = DateTime.now().millisecondsSinceEpoch;
  // Edges where this task is the dependent one.
  for (final dep in (snapshot['depends_on'] as List?) ?? const []) {
    await db.into(db.taskDependencies).insert(
          TaskDependenciesCompanion.insert(
            id: 'dep-$id-$dep',
            taskId: id,
            dependsOnTaskId: dep as String,
            createdAt: now,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }
  // ...and edges where this task is the prerequisite. Missing these would
  // silently drop "B waits for A" when A is restored, which is exactly the kind
  // of quiet change to the user's plan an undo must not make.
  for (final dependent in (snapshot['depended_on_by'] as List?) ?? const []) {
    await db.into(db.taskDependencies).insert(
          TaskDependenciesCompanion.insert(
            id: 'dep-$dependent-$id',
            taskId: dependent as String,
            dependsOnTaskId: id,
            createdAt: now,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }
}

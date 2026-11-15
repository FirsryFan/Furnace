import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/database/database.dart';
import '../../../data/repositories/task_repository.dart';
import '../../../domain/services/thread/thread_event_kind.dart';
import '../../../domain/services/thread/thread_flow_writer.dart';
import '../../../domain/services/thread/thread_status.dart';
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
            'description':
                '按状态过滤：todo（未完成待办，含 todo/doing，默认）| done（已完成）| all（全部，含卡住/跳过）',
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
  bool get readOnly => true;

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
      // v47 读侧：todo 只含 `todo|doing`；blocked/skipped 既不是待办也不是
      // 完成，只在 all 里出现。
      final taskStatus = ThreadStatus.fromStorage(task.status);
      if (status == 'todo' && !taskStatus.isSchedulable) {
        return false;
      }
      if (status == 'done' && taskStatus != ThreadStatus.done) {
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

/// 提交 / 卡住 / 跳过 / 恢复的共用实现（task-76；`reopen_task` 于 task-90 追加）。
///
/// 四个动作在 writer 里是四条同形状的迁移：校验来源状态 → 写一次状态/事件 →
/// 不写完成历史。所以这里只写一次公共骨架，具体动作只决定"调仓储的哪个方法"。
///
/// 四个工具都声明 `reversibleFor == false`：`reopened` 是**显式的向前恢复**
/// 事件，不是快照回滚——它不会撤销已经写过的提交/卡住/跳过事件，也不会回滚
/// 完成历史，所以 `ApprovalEngine` 在**任何权限模式**下都逐条确认（与删除同一
/// 档），而不是靠"可撤销"自动执行。
abstract class _TaskStatusTool extends AiTool {
  _TaskStatusTool(this._tasks);

  final TaskRepository _tasks;

  /// 落库事件种类（同时决定状态机里允许的来源状态）。
  ThreadEventKind get eventKind;

  /// 用户可读的动作名（"提交" / "标记卡住" / "跳过"）。
  String get actionLabel;

  /// 是否接受 `reason`（卡住/跳过带原因；提交不带）。
  bool get acceptsReason => false;

  @override
  Map<String, Object?> get parameters => {
        'type': 'object',
        'properties': {
          'id': {
            'type': 'string',
            'description': '任务 id（可从 query_tasks 得到）',
          },
          if (acceptsReason)
            'reason': {
              'type': 'string',
              'description': '可选：卡住/跳过/恢复的原因，作为事件的 payload 落库',
            },
          'source_key': {
            'type': 'string',
            'description':
                '可选：幂等键。同一 (task, 事件种类, source_key) 重复调用不会写第二条事件',
          },
        },
        'required': ['id'],
      };

  @override
  ToolRisk riskFor(String action) => ToolRisk.write;

  /// 状态迁移不能靠快照回滚（`reopened` 只是显式恢复，不撤销已写事件），所以
  /// 永远逐条确认。
  @override
  bool reversibleFor(String action) => false;

  @override
  bool get availableOnCurrentPlatform => true;

  /// 具体动作：调用 `TaskRepository` 对应的仓储方法（内部走 ThreadFlowWriter）。
  Future<ThreadTransitionResult> write(
    String id, {
    String? reason,
    String? sourceKey,
  });

  @override
  Future<ToolResult> run(ToolInvocation invocation) async {
    final args = ToolArgs(invocation.arguments);
    final String id;
    try {
      id = args.requireString('id');
    } on ToolArgError catch (e) {
      return ToolResult.failure(e.message);
    }
    final reason = acceptsReason ? args.optString('reason') : null;
    final sourceKey = args.optString('source_key');

    final before = await _tasks.getTaskById(id);
    if (before == null) {
      return ToolResult.failure('找不到任务：$id');
    }

    try {
      final result = await write(id, reason: reason, sourceKey: sourceKey);
      final event = result.event;
      return ToolResult(
        ok: true,
        summary: result.applied
            ? '已$actionLabel「${before.title}」，当前状态 ${result.task.status}'
            : '这条「$actionLabel」记录已经存在（source_key 幂等），没有重复写入',
        modelResult: {
          'task_id': id,
          'title': before.title,
          'status': result.task.status,
          'applied': result.applied,
          'event': event == null
              ? null
              : {
                  'id': event.id,
                  'kind': event.kind,
                  'occurred_at_ms': event.occurredAt,
                  'source_key': event.sourceKey,
                },
        },
      );
    } on StateError catch (error) {
      // writer 的非法迁移消息已经写明 from 状态与 task id，原样带出，模型/用户
      // 都能据此判断"不是 bug，是状态不允许"。
      return ToolResult.failure('任务当前状态不允许$actionLabel：${error.message}');
    } on ArgumentError catch (error) {
      return ToolResult.failure('参数不合法：${error.message}');
    }
  }
}

/// 提交答案/交卷：状态不变，只追加 `submitted` 事实（不写完成历史）。
class SubmitTaskTool extends _TaskStatusTool {
  SubmitTaskTool(super.tasks);

  @override
  String get name => 'submit_task';

  @override
  String get description =>
      '提交一条任务/题目的答案或交卷：只记录“已提交”这一流程事实，不改变任务状态、'
      '不写入完成历史、不判对错。返回 task_id、当前状态与事件。'
      '允许从 todo/doing 提交；blocked/skipped 会被状态机拒绝。';
  @override
  ThreadEventKind get eventKind => ThreadEventKind.submitted;

  @override
  String get actionLabel => '提交';

  @override
  Future<ThreadTransitionResult> write(
    String id, {
    String? reason,
    String? sourceKey,
  }) =>
      _tasks.submitTask(id, sourceKey: sourceKey);
}

/// 卡住：todo/doing → blocked；不写完成历史、不写正确性。
class MarkTaskStuckTool extends _TaskStatusTool {
  MarkTaskStuckTool(super.tasks);

  @override
  String get name => 'mark_task_stuck';

  @override
  String get description =>
      '把任务标记为卡住（todo/doing → blocked）：只记流程事实，不判对错、不降能力、'
      '不写完成历史。卡住的任务退出待办；之后可以重新开始，或跳过。'
      '返回 task_id、当前状态与事件。';
  @override
  ThreadEventKind get eventKind => ThreadEventKind.stuck;

  @override
  String get actionLabel => '标记为卡住';

  @override
  bool get acceptsReason => true;

  @override
  Future<ThreadTransitionResult> write(
    String id, {
    String? reason,
    String? sourceKey,
  }) =>
      _tasks.markTaskStuck(id, reason: reason, sourceKey: sourceKey);
}

/// 跳过：todo/doing/blocked → skipped；行与内容引用都保留。
class SkipTaskTool extends _TaskStatusTool {
  SkipTaskTool(super.tasks);

  @override
  String get name => 'skip_task';

  @override
  String get description =>
      '跳过任务（todo/doing/blocked → skipped）：不是删除，任务行与它引用的内容都'
      '保留，只是退出待办与时间窗投影。之后可以用 reopen_task 恢复到待办。'
      '返回 task_id、当前状态与事件。';
  @override
  ThreadEventKind get eventKind => ThreadEventKind.skipped;

  @override
  String get actionLabel => '跳过';

  @override
  bool get acceptsReason => true;

  @override
  Future<ThreadTransitionResult> write(
    String id, {
    String? reason,
    String? sourceKey,
  }) =>
      _tasks.skipTask(id, reason: reason, sourceKey: sourceKey);
}

/// 恢复/重开：blocked/skipped/done → todo；写 `reopened`，不回滚完成历史。
class ReopenTaskTool extends _TaskStatusTool {
  ReopenTaskTool(super.tasks);

  @override
  String get name => 'reopen_task';

  @override
  String get description =>
      '把卡住 / 跳过 / 已完成的任务恢复成待办（blocked/skipped/done → todo）：'
      '写一条 reopened 流程事件、清空 completed_at，但**不回滚**完成历史'
      '（completion_logs 是"做过"的事实，恢复只让任务回到待办）。'
      'todo/doing 的任务不需要恢复，会被状态机拒绝。'
      '返回 task_id、当前状态与事件。';
  @override
  ThreadEventKind get eventKind => ThreadEventKind.reopened;

  @override
  String get actionLabel => '恢复';

  @override
  bool get acceptsReason => true;

  @override
  Future<ThreadTransitionResult> write(
    String id, {
    String? reason,
    String? sourceKey,
  }) =>
      _tasks.reopenTask(id, reason: reason, sourceKey: sourceKey);
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

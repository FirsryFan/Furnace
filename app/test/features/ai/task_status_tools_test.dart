import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/data/repositories/time_block_repository.dart';
import 'package:furnace/domain/services/thread/thread_event_kind.dart';
import 'package:furnace/domain/services/thread/thread_status.dart';
import 'package:furnace/features/ai/domain/ai_tool.dart';
import 'package:furnace/features/ai/domain/approval_engine.dart';
import 'package:furnace/features/ai/domain/tool_registry.dart';
import 'package:furnace/features/ai/tools/task_tools.dart';

/// task-76 / task-90：提交 / 卡住 / 跳过 / 恢复的 AI 写工具。
///
/// 要钉住的五件事：
///  1. 四个工具都经 `TaskRepository` → `ThreadFlowWriter`，事件种类正确，且
///     **不写完成历史**（只有 completed 写；`reopen_task` 也不回滚它）；
///  2. 状态机拒绝的动作返回可读失败，不把异常丢给循环；
///  3. `source_key` 幂等：重试不会记第二遍；
///  4. 声明为不可撤销的写工具，所以在「自动」与「按计划」两种模式下都要逐条确认；
///  5. 四个工具都在注册表里可达。
void main() {
  late AppDatabase db;
  late TaskRepository tasks;
  late SubmitTaskTool submit;
  late MarkTaskStuckTool stuck;
  late SkipTaskTool skip;
  late ReopenTaskTool reopen;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tasks = TaskRepository(db);
    submit = SubmitTaskTool(tasks);
    stuck = MarkTaskStuckTool(tasks);
    skip = SkipTaskTool(tasks);
    reopen = ReopenTaskTool(tasks);
  });

  tearDown(() async {
    await db.close();
  });

  ToolInvocation invoke(String tool, Map<String, Object?> args) =>
      ToolInvocation(toolName: tool, action: tool, arguments: args);

  Future<List<String>> eventKindsOf(String taskId) async {
    final rows = await (db.select(db.threadEvents)
          ..where((e) => e.taskId.equals(taskId)))
        .get();
    return [for (final row in rows) row.kind]..sort();
  }

  group('成功路径：事件与状态', () {
    test('submit_task 只追加 submitted，状态不变、不写完成历史', () async {
      final task = await tasks.createTask(title: '交卷');
      final result = await submit.run(invoke('submit_task', {'id': task.id}));

      expect(result.ok, isTrue);
      final payload = result.modelResult as Map<String, Object?>;
      expect(payload['task_id'], task.id);
      expect(payload['status'], ThreadStatus.todo.id);
      expect((payload['event'] as Map)['kind'], ThreadEventKind.submitted.id);

      expect((await tasks.getTaskById(task.id))!.status, ThreadStatus.todo.id);
      expect(await eventKindsOf(task.id),
          contains(ThreadEventKind.submitted.id));
      expect(await db.select(db.completionLogs).get(), isEmpty);
    });

    test('mark_task_stuck 迁到 blocked，并带 reason payload', () async {
      final task = await tasks.createTask(title: '卡住了');
      final result = await stuck.run(invoke('mark_task_stuck', {
        'id': task.id,
        'reason': '卡在第二问',
      }));

      expect(result.ok, isTrue);
      expect((result.modelResult as Map)['status'], ThreadStatus.blocked.id);
      expect((await tasks.getTaskById(task.id))!.status, ThreadStatus.blocked.id);
      expect(await eventKindsOf(task.id), contains(ThreadEventKind.stuck.id));
      expect(await db.select(db.completionLogs).get(), isEmpty);

      final event = (await (db.select(db.threadEvents)
                ..where((e) => e.taskId.equals(task.id)))
              .get())
          .firstWhere((e) => e.kind == ThreadEventKind.stuck.id);
      expect(event.payloadJson, contains('卡在第二问'));
    });

    test('skip_task 从 blocked 迁到 skipped，行与事件都保留', () async {
      final task = await tasks.createTask(title: '跳过它');
      await tasks.markTaskStuck(task.id);

      final result = await skip.run(invoke('skip_task', {'id': task.id}));
      expect(result.ok, isTrue);
      expect((await tasks.getTaskById(task.id))!.status, ThreadStatus.skipped.id);
      expect(
        await eventKindsOf(task.id),
        containsAll(<String>[
          ThreadEventKind.stuck.id,
          ThreadEventKind.skipped.id,
        ]),
      );
      expect(await db.select(db.completionLogs).get(), isEmpty);
    });

    test('skip_task 也可以从 todo 直接触发', () async {
      final task = await tasks.createTask(title: '直接跳过');
      final result = await skip.run(invoke('skip_task', {'id': task.id}));
      expect(result.ok, isTrue);
      expect((await tasks.getTaskById(task.id))!.status, ThreadStatus.skipped.id);
    });

    test('reopen_task 把 blocked/skipped 恢复到 todo，写 reopened 事件', () async {
      final blocked = await tasks.createTask(title: '卡住后恢复');
      await tasks.markTaskStuck(blocked.id);
      final blockedResult =
          await reopen.run(invoke('reopen_task', {'id': blocked.id}));
      expect(blockedResult.ok, isTrue);
      final blockedPayload = blockedResult.modelResult as Map<String, Object?>;
      expect(blockedPayload['status'], ThreadStatus.todo.id);
      expect(
        (blockedPayload['event'] as Map<String, Object?>)['kind'],
        ThreadEventKind.reopened.id,
      );
      expect((await tasks.getTaskById(blocked.id))!.status,
          ThreadStatus.todo.id);

      final skipped = await tasks.createTask(title: '跳过后恢复');
      await tasks.skipTask(skipped.id);
      final skippedResult =
          await reopen.run(invoke('reopen_task', {'id': skipped.id}));
      expect(skippedResult.ok, isTrue);
      expect((await tasks.getTaskById(skipped.id))!.status,
          ThreadStatus.todo.id);
      expect(await db.select(db.completionLogs).get(), isEmpty);
    });

    test('reopen_task 从 done 恢复：清 completed_at，但完成历史不回滚', () async {
      final task = await tasks.createTask(title: '做完又恢复');
      await tasks.completeTask(task.id);
      expect(await db.select(db.completionLogs).get(), hasLength(1));

      final result = await reopen.run(invoke('reopen_task', {'id': task.id}));
      expect(result.ok, isTrue);
      expect((await tasks.getTaskById(task.id))!.status, ThreadStatus.todo.id);
      expect((await tasks.getTaskById(task.id))!.completedAt, isNull);
      expect(await db.select(db.completionLogs).get(), hasLength(1),
          reason: 'reopened 不回滚完成历史');
    });
  });

  group('错误清晰', () {
    test('未知任务返回“找不到”，不抛异常', () async {
      for (final tool in <AiTool>[submit, stuck, skip, reopen]) {
        final result = await tool.run(invoke(tool.name, {'id': 'nope'}));
        expect(result.ok, isFalse, reason: tool.name);
        expect(result.error, contains('找不到'), reason: tool.name);
      }
    });

    test('缺少 id 是模型可读的参数错误', () async {
      final result = await submit.run(invoke('submit_task', {}));
      expect(result.ok, isFalse);
      expect(result.error, contains('id'));
    });

    test('状态机拒绝时返回可读失败（completed 之后不能提交）', () async {
      final task = await tasks.createTask(title: '已完成');
      await tasks.completeTask(task.id);
      final before = await eventKindsOf(task.id);

      final result = await submit.run(invoke('submit_task', {'id': task.id}));
      expect(result.ok, isFalse);
      expect(result.error, contains('不允许'));
      expect(await eventKindsOf(task.id), before,
          reason: '被拒绝的调用不能留下事件');
    });

    test('todo 的任务不需要恢复：状态机拒绝且不写事件', () async {
      final task = await tasks.createTask(title: '本来就待办');
      final before = await eventKindsOf(task.id);

      final result = await reopen.run(invoke('reopen_task', {'id': task.id}));
      expect(result.ok, isFalse);
      expect(result.error, contains('不允许'));
      expect(await eventKindsOf(task.id), before);
      expect((await tasks.getTaskById(task.id))!.status, ThreadStatus.todo.id);
    });
  });

  group('幂等', () {
    test('同一 source_key 重试只写一条事件，第二次 applied=false', () async {
      final task = await tasks.createTask(title: '重试');
      final first = await submit.run(invoke('submit_task', {
        'id': task.id,
        'source_key': 'attempt-1',
      }));
      final second = await submit.run(invoke('submit_task', {
        'id': task.id,
        'source_key': 'attempt-1',
      }));

      expect(first.ok, isTrue);
      expect((first.modelResult as Map)['applied'], isTrue);
      expect(second.ok, isTrue);
      expect((second.modelResult as Map)['applied'], isFalse);
      expect(second.summary, contains('幂等'));

      final submitted = (await eventKindsOf(task.id))
          .where((kind) => kind == ThreadEventKind.submitted.id);
      expect(submitted, hasLength(1));
    });

    test('reopen_task 的 source_key 幂等：同一恢复只写一条事件', () async {
      final task = await tasks.createTask(title: '恢复幂等');
      await tasks.skipTask(task.id);

      final first = await reopen.run(invoke('reopen_task', {
        'id': task.id,
        'source_key': 'restore-1',
      }));
      final second = await reopen.run(invoke('reopen_task', {
        'id': task.id,
        'source_key': 'restore-1',
      }));

      expect(first.ok, isTrue);
      expect((first.modelResult as Map)['applied'], isTrue);
      expect(second.ok, isTrue);
      expect((second.modelResult as Map)['applied'], isFalse);
      expect(second.summary, contains('幂等'));
      final reopened = (await eventKindsOf(task.id))
          .where((kind) => kind == ThreadEventKind.reopened.id);
      expect(reopened, hasLength(1));
    });
  });

  group('审批：写工具逐条确认', () {
    test('四个工具都是 write 且不可撤销', () {
      for (final tool in <AiTool>[submit, stuck, skip, reopen]) {
        expect(tool.riskFor(tool.name), ToolRisk.write, reason: tool.name);
        expect(tool.reversibleFor(tool.name), isFalse, reason: tool.name);
        expect(tool.readOnly, isFalse, reason: tool.name);
      }
    });

    test('两种权限模式下都不是自动执行', () {
      for (final mode in AiPermissionMode.values) {
        final engine = ApprovalEngine(mode: mode);
        for (final tool in <AiTool>[submit, stuck, skip, reopen]) {
          final decision =
              engine.forInvocation(tool, <String, Object?>{'id': 'task-1'});
          expect(decision.disposition, ToolDisposition.individualApproval,
              reason: '${tool.name} in $mode');
        }
      }
    });
  });

  group('注册与可达', () {
    test('四个工具都在 ToolRegistry.forApp 里，且声明非只读', () {
      final registry = ToolRegistry.forApp(
        db: db,
        tasks: tasks,
        blocks: TimeBlockRepository(db),
        anki: AnkiRepository(db),
        tags: TagRepository(db),
      );
      for (final name in <String>[
        'submit_task',
        'mark_task_stuck',
        'skip_task',
        'reopen_task',
      ]) {
        expect(registry.byName(name), isNotNull, reason: name);
        expect(registry.isReadOnly(name), isFalse, reason: name);
      }
    });
  });
}

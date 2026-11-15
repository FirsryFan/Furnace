import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/domain/services/thread/thread_event_kind.dart';
import 'package:furnace/domain/services/thread/thread_status.dart';
import 'package:furnace/features/ai/domain/ai_tool.dart';
import 'package:furnace/features/ai/tools/task_tools.dart';

/// AI 工具的完成/开始/创建路径也走唯一写口（task-72）：工具只能经
/// `TaskRepository` 写库，所以它产生的事件必须与 UI 路径同一形状；
/// 只读的 `query_tasks` 也不再按 `!= done` 把 blocked/skipped 当待办。
void main() {
  late AppDatabase db;
  late TaskRepository tasks;
  late QueryTasksTool query;
  late ManageTaskTool manage;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tasks = TaskRepository(db);
    query = QueryTasksTool(tasks, db);
    manage = ManageTaskTool(tasks, db);
  });

  tearDown(() async {
    await db.close();
  });

  ToolInvocation invoke(String tool, Map<String, Object?> args) => ToolInvocation(
        toolName: tool,
        action: args['action']?.toString() ?? tool,
        arguments: args,
      );

  Future<List<String>> eventsOf(String taskId) async {
    final rows = await (db.select(db.threadEvents)
          ..where((e) => e.taskId.equals(taskId)))
        .get();
    return [for (final row in rows) row.kind]..sort();
  }

  test('manage_task create/start/complete 写 created/started/completed 事件',
      () async {
    final created = await manage.run(invoke('manage_task', {
      'action': 'create',
      'title': 'AI 建的任务',
      'estimate_minutes': 20,
    }));
    expect(created.ok, isTrue);
    final id = ((created.modelResult as Map)['id']) as String;
    expect(await eventsOf(id), [ThreadEventKind.created.id]);

    final started = await manage.run(
      invoke('manage_task', {'action': 'start', 'id': id}),
    );
    expect(started.ok, isTrue);

    final completed = await manage.run(
      invoke('manage_task', {'action': 'complete', 'id': id}),
    );
    expect(completed.ok, isTrue);

    expect(
      await eventsOf(id),
      [
        ThreadEventKind.completed.id,
        ThreadEventKind.created.id,
        ThreadEventKind.started.id,
      ],
    );
    expect((await tasks.getTaskById(id))!.status, ThreadStatus.done.id);
    expect(await db.select(db.completionLogs).get(), hasLength(1));
  });

  test('query_tasks 的 todo 不含 blocked/skipped；all 仍能看到它们', () async {
    final todo = await tasks.createTask(title: '待办');
    final blocked = await tasks.createTask(title: '卡住');
    await tasks.markTaskStuck(blocked.id);
    final skipped = await tasks.createTask(title: '跳过');
    await tasks.skipTask(skipped.id);

    final open = await query.run(invoke('query_tasks', {}));
    final openPayload = open.modelResult as Map<String, Object?>;
    expect(openPayload['total_matching'], 1);
    expect(
      ((openPayload['tasks'] as List).single as Map)['id'],
      todo.id,
    );

    final all = await query.run(invoke('query_tasks', {'status': 'all'}));
    expect((all.modelResult as Map)['total_matching'], 3);

    final done = await query.run(invoke('query_tasks', {'status': 'done'}));
    expect((done.modelResult as Map)['total_matching'], 0);
  });
}

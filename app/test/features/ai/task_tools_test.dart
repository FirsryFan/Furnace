import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/features/ai/domain/ai_tool.dart';
import 'package:furnace/features/ai/tools/task_tools.dart';

/// The tools are the AI's only way to touch user data, so two properties matter
/// more than anything else:
///
///  1. They go **through the repositories** (never SQL), which is what makes the
///     main UI refresh on its own and keeps business rules in one place.
///  2. They carry a **risk level and a before/after snapshot**, which is what
///     makes automatic execution safe enough to offer.
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

  group('risk classification', () {
    test('delete is destructive, everything else is a write', () {
      for (final action in ManageTaskTool.actions) {
        final expected =
            action == 'delete' ? ToolRisk.destructive : ToolRisk.write;
        expect(manage.riskFor(action), expected, reason: 'action $action');
      }
    });

    test('every manage action claims to be reversible', () {
      // This claim is what allows auto-execution (AI_DESIGN D13b). If an action
      // could not snapshot its prior state it would have to return false here.
      for (final action in ManageTaskTool.actions) {
        expect(manage.reversibleFor(action), isTrue, reason: 'action $action');
      }
    });
  });

  group('query_tasks', () {
    test('an empty database answers rather than failing', () async {
      final result = await query.run(invoke('query_tasks', {}));
      expect(result.ok, isTrue);
      expect(result.summary, contains('没有'));
    });

    test('it goes through the repository, so the data matches', () async {
      await tasks.createTask(title: '写作业', priority: 3);
      final result = await query.run(invoke('query_tasks', {}));
      final payload = result.modelResult as Map<String, Object?>;
      expect(payload['total_matching'], 1);
      final row = (payload['tasks'] as List).single as Map;
      expect(row['title'], '写作业');
      expect(row['priority'], 3);
      expect(row['status'], 'todo');
      // The id is what the model needs to act on it later.
      expect(row['id'], isA<String>());
    });

    test('status defaults to open tasks only', () async {
      await tasks.createTask(title: '未完成');
      final done = await tasks.createTask(title: '已完成');
      await tasks.completeTask(done.id);

      final open = await query.run(invoke('query_tasks', {}));
      expect(((open.modelResult as Map)['tasks'] as List).length, 1);

      final all = await query.run(invoke('query_tasks', {'status': 'all'}));
      expect(((all.modelResult as Map)['tasks'] as List).length, 2);

      final onlyDone = await query.run(invoke('query_tasks', {'status': 'done'}));
      final doneRow = ((onlyDone.modelResult as Map)['tasks'] as List).single as Map;
      expect(doneRow['title'], '已完成');
    });

    test('search matches the title case-insensitively', () async {
      await tasks.createTask(title: 'Physics homework');
      await tasks.createTask(title: '数学作业');
      final hit = await query.run(invoke('query_tasks', {'search': 'physics'}));
      expect(((hit.modelResult as Map)['total_matching']), 1);
      final miss = await query.run(invoke('query_tasks', {'search': '化学'}));
      expect(((miss.modelResult as Map)['total_matching']), 0);
    });

    test('the answer is bounded and says when it was truncated', () async {
      // A model that gets 500 rows at once wastes the conversation; a model that
      // gets 20 with no "there are more" lies by omission.
      for (var i = 0; i < 25; i++) {
        await tasks.createTask(title: '任务 $i');
      }
      final result = await query.run(invoke('query_tasks', {}));
      final payload = result.modelResult as Map<String, Object?>;
      expect(payload['total_matching'], 25);
      expect(payload['returned'], QueryTasksTool.defaultLimit);
      expect(payload['truncated'], isTrue);
    });

    test('an explicit limit is honoured and clamped', () async {
      for (var i = 0; i < 5; i++) {
        await tasks.createTask(title: '任务 $i');
      }
      final small = await query.run(invoke('query_tasks', {'limit': 2}));
      expect(((small.modelResult as Map)['returned']), 2);
      final huge = await query.run(invoke('query_tasks', {'limit': 100000}));
      expect(((huge.modelResult as Map)['returned']), 5);
    });

    test('due_at bounds filter correctly', () async {
      final soon = await tasks.createTask(
          title: '快到期', dueAt: DateTime(2026, 1, 2).millisecondsSinceEpoch);
      await tasks.createTask(
          title: '很晚', dueAt: DateTime(2026, 6, 1).millisecondsSinceEpoch);
      await tasks.createTask(title: '没有截止');

      final before = await query.run(invoke('query_tasks', {
        'due_before': DateTime(2026, 2, 1).millisecondsSinceEpoch,
      }));
      expect(((before.modelResult as Map)['total_matching']), 1);

      final after = await query.run(invoke('query_tasks', {
        'due_after': DateTime(2026, 2, 1).millisecondsSinceEpoch,
      }));
      expect(((after.modelResult as Map)['total_matching']), 1);

      // A task with no deadline is excluded from both, rather than treated as
      // "always due".
      expect(soon.id, isNotEmpty);
    });

    test('ISO-8601 and epoch input are both accepted', () async {
      await tasks.createTask(
          title: 'x', dueAt: DateTime(2026, 3, 4).millisecondsSinceEpoch);
      final iso = await query.run(invoke('query_tasks', {
        'due_before': '2026-05-01T00:00:00Z',
      }));
      expect(((iso.modelResult as Map)['total_matching']), 1);
    });
  });

  group('manage_task create', () {
    test('it creates a real task through the repository', () async {
      final result = await manage.run(invoke('manage_task', {
        'action': 'create',
        'title': '买书',
        'priority': 5,
        'estimate_minutes': 30,
      }));
      expect(result.ok, isTrue);
      expect(result.summary, contains('买书'));

      // Read back through the repository, not the tool: this is the assertion
      // that proves the tool did not bypass the data layer.
      final stored = await tasks.getTasks();
      expect(stored.single.title, '买书');
      expect(stored.single.priority, 5);
      expect(stored.single.estimateMinutes, 30);
    });

    test('a missing title is a readable failure, not an exception', () async {
      final result = await manage.run(invoke('manage_task', {'action': 'create'}));
      expect(result.ok, isFalse);
      expect(result.error, contains('title'));
    });

    test('an unknown action lists what is allowed', () async {
      final result =
          await manage.run(invoke('manage_task', {'action': 'explode'}));
      expect(result.ok, isFalse);
      // The model needs to be told the options, not just that it was wrong.
      expect(result.error, contains('create'));
    });

    test('a missing action says so', () async {
      final result = await manage.run(invoke('manage_task', {}));
      expect(result.ok, isFalse);
      expect(result.error, contains('action'));
    });

    test('a create carries an after-snapshot so it can be undone', () async {
      final result = await manage.run(
          invoke('manage_task', {'action': 'create', 'title': '可撤销'}));
      expect(result.isUndoable, isTrue);
      final snapshot = jsonDecode(result.afterJson!) as Map<String, Object?>;
      expect((snapshot['task'] as Map)['title'], '可撤销');
    });

    test('dates can be given as ISO strings', () async {
      await manage.run(invoke('manage_task', {
        'action': 'create',
        'title': '带截止',
        'due_at': '2026-04-01T09:00:00Z',
      }));
      final stored = (await tasks.getTasks()).single;
      expect(stored.dueAt, DateTime.utc(2026, 4, 1, 9).millisecondsSinceEpoch);
    });
  });

  group('manage_task update / complete / start', () {
    test('update keeps the previous row so it can be rolled back', () async {
      final task = await tasks.createTask(title: '原名', priority: 1);
      final result = await manage.run(invoke('manage_task', {
        'action': 'update',
        'id': task.id,
        'title': '新名',
        'priority': 7,
      }));
      expect(result.ok, isTrue);
      expect((await tasks.getTasks()).single.title, '新名');

      final before = jsonDecode(result.beforeJson!) as Map<String, Object?>;
      expect((before['task'] as Map)['title'], '原名');
      expect((before['task'] as Map)['priority'], 1,
          reason: 'the pre-change value is what makes undo possible');
    });

    test('update with nothing to change is refused clearly', () async {
      final task = await tasks.createTask(title: 'x');
      final result =
          await manage.run(invoke('manage_task', {'action': 'update', 'id': task.id}));
      expect(result.ok, isFalse);
      expect(result.error, contains('字段'));
    });

    test('update on an unknown id fails without touching anything', () async {
      final result = await manage.run(invoke('manage_task', {
        'action': 'update',
        'id': 'does-not-exist',
        'title': 'x',
      }));
      expect(result.ok, isFalse);
      expect(result.error, contains('找不到'));
    });

    test('complete marks the task done', () async {
      final task = await tasks.createTask(title: '做完它');
      final result =
          await manage.run(invoke('manage_task', {'action': 'complete', 'id': task.id}));
      expect(result.ok, isTrue);
      expect((await tasks.getTasks()).single.status, 'done');
      expect(result.beforeJson, isNotNull);
    });

    test('start stamps the started moment', () async {
      final task = await tasks.createTask(title: '开始');
      await manage.run(invoke('manage_task', {'action': 'start', 'id': task.id}));
      expect((await tasks.getTasks()).single.startedAt, isNotNull);
    });
  });

  group('manage_task delete', () {
    test('it deletes through the repository', () async {
      final task = await tasks.createTask(title: '要删的');
      final result =
          await manage.run(invoke('manage_task', {'action': 'delete', 'id': task.id}));
      expect(result.ok, isTrue);
      expect(await tasks.getTasks(), isEmpty);
    });

    test('the snapshot is complete enough to restore the row', () async {
      final task = await tasks.createTask(
        title: '重要的',
        priority: 4,
        description: '别丢',
        estimateMinutes: 45,
      );
      final result =
          await manage.run(invoke('manage_task', {'action': 'delete', 'id': task.id}));
      final snapshot =
          (jsonDecode(result.beforeJson!) as Map).cast<String, Object?>();
      final row = (snapshot['task'] as Map).cast<String, Object?>();
      expect(row['title'], '重要的');
      expect(row['description'], '别丢');
      expect(row['priority'], 4);
      expect(row['estimate_minutes'], 45);

      // And the snapshot actually restores it.
      await restoreTask(db, snapshot);
      final restored = (await tasks.getTasks()).single;
      expect(restored.title, '重要的');
      expect(restored.description, '别丢');
      expect(restored.priority, 4);
      expect(restored.estimateMinutes, 45);
      expect(restored.id, task.id, reason: 'the id must survive, or undo would '
          'break every reference the user already made');
    });

    test('deleting twice reports the second attempt clearly', () async {
      final task = await tasks.createTask(title: 'x');
      await manage.run(invoke('manage_task', {'action': 'delete', 'id': task.id}));
      final again =
          await manage.run(invoke('manage_task', {'action': 'delete', 'id': task.id}));
      expect(again.ok, isFalse);
      expect(again.error, contains('找不到'));
    });
  });

  group('manage_task add_dependency', () {
    test('it links two tasks and snapshots the edges', () async {
      final first = await tasks.createTask(title: '先做');
      final second = await tasks.createTask(title: '后做');
      final result = await manage.run(invoke('manage_task', {
        'action': 'add_dependency',
        'id': second.id,
        'depends_on_task_id': first.id,
      }));
      expect(result.ok, isTrue);
      final links = await db.select(db.taskDependencies).get();
      expect(links.single.taskId, second.id);
      expect(links.single.dependsOnTaskId, first.id);
      // The snapshot captures the edges, so undo can put the graph back too.
      final after = jsonDecode(result.afterJson!) as Map<String, Object?>;
      expect(after['depends_on'], [first.id]);
    });

    test('self-dependency is refused', () async {
      final task = await tasks.createTask(title: 'x');
      final result = await manage.run(invoke('manage_task', {
        'action': 'add_dependency',
        'id': task.id,
        'depends_on_task_id': task.id,
      }));
      expect(result.ok, isFalse);
      expect(result.error, contains('自己'));
    });

    test('an unknown dependency target is refused', () async {
      final task = await tasks.createTask(title: 'x');
      final result = await manage.run(invoke('manage_task', {
        'action': 'add_dependency',
        'id': task.id,
        'depends_on_task_id': 'nope',
      }));
      expect(result.ok, isFalse);
      expect(result.error, contains('找不到'));
    });
  });

  group('snapshots survive a dependency graph', () {
    test('restoring a deleted task brings its edges back', () async {
      final first = await tasks.createTask(title: 'A');
      final second = await tasks.createTask(title: 'B');
      await tasks.addDependency(taskId: second.id, dependsOnTaskId: first.id);

      // Deleting A removes the edge that referenced it; restoring A must not
      // silently lose the relationship the user set up.
      final snapshot = await snapshotTask(db, first.id);
      await tasks.deleteTask(first.id);
      expect(await db.select(db.taskDependencies).get(), isEmpty);

      // The edge pointed taskId=second -> dependsOn=first, i.e. it is recorded
      // in A's *incoming* list.
      expect((snapshot!['depended_on_by'] as List), [second.id]);
      await restoreTask(db, snapshot);
      final edges = await db.select(db.taskDependencies).get();
      expect(edges.map((e) => e.dependsOnTaskId), contains(first.id));
    });
  });
}

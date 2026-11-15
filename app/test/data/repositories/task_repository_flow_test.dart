import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/data/repositories/thread_rank_repository.dart';
import 'package:furnace/data/repositories/thread_state_repository.dart';
import 'package:furnace/data/repositories/time_block_repository.dart';
import 'package:furnace/domain/services/thread/thread_event_kind.dart';
import 'package:furnace/domain/services/thread/thread_node_kind.dart';
import 'package:furnace/domain/services/thread/thread_status.dart';
import 'package:furnace/features/thread/application/thread_rank_service.dart';

/// ThreadFlow 接线（task-72，2026-11-15）：`TaskRepository` 的创建/开始/提交/
/// 卡住/跳过/完成六条路径必须落到唯一写口 `ThreadFlowWriter`，读侧只把显式
/// `todo|doing` 当待办。
///
/// 每条行为都单独可失败：
///
///  * 创建写 `created`，`kind`/`source_key` 落库，同 key 幂等；
///  * start/complete/submit/stuck/skip 各写对应事件；
///  * **只有 completed** 写 `completion_logs`；
///  * 完成快照口径（actualMinutes / estimate 覆盖 / 可疑记录）保持旧行为；
///  * 未知 task 的 start/complete 仍是静默 no-op；
///  * `getOpenTasks` 与 Thread ready 列表排除 done/blocked/skipped 与容器节点；
///  * `updateTask(status:)` 的五个状态全部走写口（`todo` 走 `reopened`，
///    task-90 起不再直写 `tasks.status`）；
///  * `reopenTask`：blocked/skipped/done → todo，清 `completed_at`，不回滚完成
///    历史；非法来源抛错。
void main() {
  late AppDatabase db;
  late TaskRepository tasks;

  final t0 = DateTime.fromMillisecondsSinceEpoch(1700000000000);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tasks = TaskRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  /// Event kinds of one node, sorted: several actions in one test can land in
  /// the same millisecond, so flow order is not asserted here (the writer test
  /// covers the per-transition order). What matters is which facts exist.
  Future<List<String>> eventsOf(String taskId) async {
    final rows = await (db.select(db.threadEvents)
          ..where((e) => e.taskId.equals(taskId)))
        .get();
    return [for (final row in rows) row.kind]..sort();
  }

  Future<int> completionCount() async =>
      (await db.select(db.completionLogs).get()).length;

  group('creation goes through the writer', () {
    test('createTask 写一条 created 事件，默认 kind=task', () async {
      final task = await tasks.createTask(title: '普通任务');

      expect(task.status, ThreadStatus.todo.id);
      expect(task.kind, ThreadNodeKind.task.id);
      expect(task.sourceKey, isNull);
      expect(await eventsOf(task.id), [ThreadEventKind.created.id]);
    });

    test('组卷/周/日/复习节点写自己的 kind 与 source_key', () async {
      final paper = await tasks.createTask(
        title: '物理套卷',
        kind: ThreadNodeKind.paper,
        sourceKey: 'paper:QSET-20261115-01',
      );
      final day = await tasks.createTask(
        title: '2026-11-15 日计划',
        kind: ThreadNodeKind.day,
        parentId: paper.id,
        sourceKey: 'day:2026-11-15',
      );
      final review = await tasks.createTask(
        title: '今日到期卡',
        kind: ThreadNodeKind.review,
        parentId: day.id,
        sourceKey: 'review:2026-11-15',
      );

      expect(paper.kind, ThreadNodeKind.paper.id);
      expect(day.kind, ThreadNodeKind.day.id);
      expect(review.kind, ThreadNodeKind.review.id);
      expect(paper.sourceKey, 'paper:QSET-20261115-01');
      expect(day.parentId, paper.id);
      expect(review.parentId, day.id);
      expect(await eventsOf(paper.id), [ThreadEventKind.created.id]);
      expect(await eventsOf(day.id), [ThreadEventKind.created.id]);
      expect(await eventsOf(review.id), [ThreadEventKind.created.id]);
    });

    test('同 source_key 再建一次复用同一节点，不写第二条 created', () async {
      final first = await tasks.createTask(
        title: '第 47 周',
        kind: ThreadNodeKind.week,
        sourceKey: 'week:2026-W47',
      );
      final second = await tasks.createTask(
        title: '第 47 周',
        kind: ThreadNodeKind.week,
        sourceKey: 'week:2026-W47',
      );

      expect(second.id, first.id);
      expect(await db.select(db.tasks).get(), hasLength(1));
      expect(await eventsOf(first.id), [ThreadEventKind.created.id]);
    });

    test('同 source_key 换 kind 直接抛错，不留第二条节点', () async {
      await tasks.createTask(
        title: '日计划',
        kind: ThreadNodeKind.day,
        sourceKey: 'day:2026-11-15',
      );
      await expectLater(
        tasks.createTask(
          title: '冒充日计划',
          kind: ThreadNodeKind.paper,
          sourceKey: 'day:2026-11-15',
        ),
        throwsA(isA<StateError>()),
      );
      expect(await db.select(db.tasks).get(), hasLength(1));
    });
  });

  group('start / complete through the writer', () {
    test('started → doing；completed → done，且只有完成写完成历史', () async {
      final task = await tasks.createTask(title: '背单词', estimateMinutes: 30);

      await tasks.startTask(task.id, at: t0);
      expect((await tasks.getTaskById(task.id))!.status,
          ThreadStatus.doing.id);

      await tasks.completeTask(
        task.id,
        completedAt: t0.add(const Duration(minutes: 25)),
        estimateMinutes: 30,
        tagPaths: const ['英语/单词'],
      );

      final done = await tasks.getTaskById(task.id);
      expect(done!.status, ThreadStatus.done.id);
      expect(done.completedAt,
          t0.add(const Duration(minutes: 25)).millisecondsSinceEpoch);
      expect(
        await eventsOf(task.id),
        [
          ThreadEventKind.completed.id,
          ThreadEventKind.created.id,
          ThreadEventKind.started.id,
        ],
      );

      final logs = await db.select(db.completionLogs).get();
      expect(logs, hasLength(1));
      expect(logs.single.actualMinutes, 25);
      expect(logs.single.estimateMinutes, 30);
      expect(logs.single.includeInModel, isTrue);
      expect(logs.single.tagPaths, '英语/单词');
    });

    test('完成快照保留旧口径：没 start 就没有 actual，可疑记录默认不进模型',
        () async {
      final plain = await tasks.createTask(title: '直接完成', estimateMinutes: 20);
      await tasks.completeTask(plain.id, estimateMinutes: 20);
      final plainLog = (await db.select(db.completionLogs).get()).single;
      expect(plainLog.actualMinutes, isNull);
      expect(plainLog.includeInModel, isTrue);

      final forgotten = await tasks.createTask(title: '忘关了', estimateMinutes: 10);
      await tasks.startTask(
        forgotten.id,
        at: DateTime.now().subtract(const Duration(minutes: 100)),
      );
      await tasks.completeTask(forgotten.id, estimateMinutes: 10);
      final forgottenLog = (await db.select(db.completionLogs).get())
          .singleWhere((log) => log.taskId == forgotten.id);
      expect(forgottenLog.actualMinutes, greaterThanOrEqualTo(100));
      expect(forgottenLog.durationSuspicious, isTrue);
      expect(forgottenLog.includeInModel, isFalse);
    });

    test('未知 task 的 start/complete 保持静默 no-op，不写事件', () async {
      await tasks.startTask('task-does-not-exist');
      await tasks.completeTask('task-does-not-exist');
      expect(await db.select(db.threadEvents).get(), isEmpty);
      expect(await completionCount(), 0);
    });

    test('跳过之后不能直接完成：非法迁移抛错且不写完成历史', () async {
      final task = await tasks.createTask(title: '先跳过');
      await tasks.skipTask(task.id, reason: '时间不够');

      await expectLater(
        tasks.completeTask(task.id),
        throwsA(isA<StateError>()),
      );
      expect((await tasks.getTaskById(task.id))!.status,
          ThreadStatus.skipped.id);
      expect(await completionCount(), 0);
    });
  });

  group('submit / stuck / skip through the writer', () {
    test('submit 不改状态、不写完成历史；stuck/skip 迁状态、不写完成历史', () async {
      final task = await tasks.createTask(title: '物理卷子');
      await tasks.startTask(task.id, at: t0);

      final submitted = await tasks.submitTask(
        task.id,
        at: t0.add(const Duration(minutes: 20)),
        payload: const <String, Object?>{
          'verdict': 'pass',
          'attempt_ids': <String>['qa-1'],
        },
      );
      expect(submitted.applied, isTrue);
      expect(submitted.task.status, ThreadStatus.doing.id);
      expect(await completionCount(), 0);

      final stuck = await tasks.markTaskStuck(
        task.id,
        reason: '卡在第 2 步',
        at: t0,
      );
      expect(stuck.task.status, ThreadStatus.blocked.id);

      final skipped = await tasks.skipTask(
        task.id,
        reason: '时间不够',
        at: t0,
      );
      expect(skipped.task.status, ThreadStatus.skipped.id);

      expect(
        await eventsOf(task.id),
        [
          ThreadEventKind.created.id,
          ThreadEventKind.skipped.id,
          ThreadEventKind.started.id,
          ThreadEventKind.stuck.id,
          ThreadEventKind.submitted.id,
        ],
      );
      expect(await completionCount(), 0, reason: '提交/卡住/跳过都不写学习历史');
    });

    test('卡住后可以重新开始（blocked → doing）', () async {
      final task = await tasks.createTask(title: '重新开始');
      await tasks.markTaskStuck(task.id, reason: '卡住');
      await tasks.startTask(task.id, at: t0);
      expect((await tasks.getTaskById(task.id))!.status,
          ThreadStatus.doing.id);
    });
  });

  group('read side only treats todo|doing as open', () {
    test('getOpenTasks 排除 done/blocked/skipped', () async {
      final todo = await tasks.createTask(title: '待办');
      final doing = await tasks.createTask(title: '在做');
      await tasks.startTask(doing.id);
      final blocked = await tasks.createTask(title: '卡住');
      await tasks.markTaskStuck(blocked.id);
      final skipped = await tasks.createTask(title: '跳过');
      await tasks.skipTask(skipped.id);
      final done = await tasks.createTask(title: '完成');
      await tasks.completeTask(done.id);

      final open = await tasks.getOpenTasks();
      expect(open.map((t) => t.id).toSet(), {todo.id, doing.id});
      expect((await tasks.getTasks()).length, 5, reason: '全量读仍能看到全部');
    });

    test('Thread ready 列表不含 blocked/skipped，也不含 week/day 容器', () async {
      final todo = await tasks.createTask(title: '待办', estimateMinutes: 15);
      final doing = await tasks.createTask(title: '在做', estimateMinutes: 15);
      await tasks.startTask(doing.id);
      final blocked = await tasks.createTask(title: '卡住', estimateMinutes: 15);
      await tasks.markTaskStuck(blocked.id);
      final skipped = await tasks.createTask(title: '跳过', estimateMinutes: 15);
      await tasks.skipTask(skipped.id);
      final week = await tasks.createTask(
        title: '第 47 周',
        kind: ThreadNodeKind.week,
        sourceKey: 'week:2026-W47',
      );
      final day = await tasks.createTask(
        title: '今天',
        kind: ThreadNodeKind.day,
        parentId: week.id,
        sourceKey: 'day:2026-11-15',
      );

      final service = ThreadRankService(
        taskRepository: tasks,
        timeBlockRepository: TimeBlockRepository(db),
        tagRepository: TagRepository(db),
        threadRankRepository: ThreadRankRepository(db),
        threadStateRepository: ThreadStateRepository(db),
      );
      final feed = await service.build();

      expect(feed.readyTasks.map((t) => t.id).toSet(), {todo.id, doing.id});
      expect(feed.completedTasks, isEmpty);
      expect(feed.taskFor(day.id), isNotNull,
          reason: '容器仍在任务表里，只是不进 ready');
    });
  });

  group('updateTask status routing', () {
    test('status=done 走完成写口；status=todo 走 reopened，不再直写', () async {
      final task = await tasks.createTask(title: '勾选框');
      await tasks.updateTask(task.id, status: ThreadStatus.done.id);

      expect((await tasks.getTaskById(task.id))!.status,
          ThreadStatus.done.id);
      expect(
        await eventsOf(task.id),
        [ThreadEventKind.completed.id, ThreadEventKind.created.id],
      );
      expect(await completionCount(), 1);

      await tasks.updateTask(task.id, status: ThreadStatus.todo.id);
      final reopened = await tasks.getTaskById(task.id);
      expect(reopened!.status, ThreadStatus.todo.id);
      expect(reopened.completedAt, isNull, reason: '重开清 completed_at');
      expect(
        await eventsOf(task.id),
        [
          ThreadEventKind.completed.id,
          ThreadEventKind.created.id,
          ThreadEventKind.reopened.id,
        ],
        reason: 'task-90：重开不再直写 tasks.status，必须留一条 reopened 事件',
      );
      expect(await completionCount(), 1, reason: '重开不回滚完成历史');
    });

    test('blocked/skipped 的 updateTask(status:todo) 也走 reopened 事件', () async {
      final blocked = await tasks.createTask(title: '卡住后恢复');
      await tasks.markTaskStuck(blocked.id);
      await tasks.updateTask(blocked.id, status: ThreadStatus.todo.id);
      expect((await tasks.getTaskById(blocked.id))!.status,
          ThreadStatus.todo.id);
      expect(await eventsOf(blocked.id), contains(ThreadEventKind.reopened.id));

      final skipped = await tasks.createTask(title: '跳过后恢复');
      await tasks.skipTask(skipped.id);
      await tasks.updateTask(skipped.id, status: ThreadStatus.todo.id);
      expect((await tasks.getTaskById(skipped.id))!.status,
          ThreadStatus.todo.id);
      expect(await eventsOf(skipped.id), contains(ThreadEventKind.reopened.id));
    });

    test('非法状态来源抛错：卡住后直接 updateTask(status:done) 不写半个事实',
        () async {
      final task = await tasks.createTask(title: '卡住不能直接完成');
      await tasks.markTaskStuck(task.id);
      final before = await eventsOf(task.id);

      await expectLater(
        tasks.updateTask(task.id, status: ThreadStatus.done.id),
        throwsA(isA<StateError>()),
      );
      expect((await tasks.getTaskById(task.id))!.status,
          ThreadStatus.blocked.id);
      expect(await eventsOf(task.id), before);
      expect(await completionCount(), 0);
    });

    test('未知状态值抛 ArgumentError，而不是顺手直写一个陌生字符串', () async {
      final task = await tasks.createTask(title: 'x');
      final before = await eventsOf(task.id);

      await expectLater(
        tasks.updateTask(task.id, status: 'nope'),
        throwsA(isA<ArgumentError>()),
      );
      expect((await tasks.getTaskById(task.id))!.status, ThreadStatus.todo.id);
      expect(await eventsOf(task.id), before);
    });

    test('非状态字段编辑不产生事件', () async {
      final task = await tasks.createTask(title: 'x');
      await tasks.updateTask(task.id, title: 'y', energyRequired: 7);
      expect(await eventsOf(task.id), [ThreadEventKind.created.id]);
    });
  });

  group('reopenTask through the writer', () {
    test('blocked/skipped/done → todo：各写一条 reopened，不写完成历史', () async {
      final blocked = await tasks.createTask(title: '卡住');
      await tasks.markTaskStuck(blocked.id);
      final blockedResult = await tasks.reopenTask(blocked.id);
      expect(blockedResult.applied, isTrue);
      expect(blockedResult.task.status, ThreadStatus.todo.id);
      expect(blockedResult.event!.kind, ThreadEventKind.reopened.id);

      final skipped = await tasks.createTask(title: '跳过');
      await tasks.skipTask(skipped.id);
      await tasks.reopenTask(skipped.id);
      expect((await tasks.getTaskById(skipped.id))!.status,
          ThreadStatus.todo.id);

      final done = await tasks.createTask(title: '完成过');
      await tasks.completeTask(done.id);
      expect(await completionCount(), 1);
      final doneResult = await tasks.reopenTask(done.id);
      expect(doneResult.task.status, ThreadStatus.todo.id);
      expect(doneResult.task.completedAt, isNull);
      expect(await completionCount(), 1, reason: '完成历史不回滚');
      expect(await eventsOf(done.id), contains(ThreadEventKind.reopened.id));
    });

    test('todo 不需要恢复（非法来源抛错）；未知 task 也抛错', () async {
      final task = await tasks.createTask(title: '还是待办');
      await expectLater(
        tasks.reopenTask(task.id),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        tasks.reopenTask('task-does-not-exist'),
        throwsA(isA<StateError>()),
      );
      expect(await eventsOf(task.id), [ThreadEventKind.created.id]);
    });

    test('source_key 幂等：同一恢复只记一次', () async {
      final task = await tasks.createTask(title: '幂等恢复');
      await tasks.skipTask(task.id);

      final first = await tasks.reopenTask(task.id, sourceKey: 'restore-1');
      final second = await tasks.reopenTask(task.id, sourceKey: 'restore-1');

      expect(first.applied, isTrue);
      expect(second.applied, isFalse);
      final reopened = (await eventsOf(task.id))
          .where((kind) => kind == ThreadEventKind.reopened.id);
      expect(reopened, hasLength(1));
    });
  });

  test('删除任务删掉该节点的 thread_events，但保留完成历史', () async {
    final task = await tasks.createTask(title: '删我');
    await tasks.startTask(task.id);
    await tasks.completeTask(task.id);
    expect(await eventsOf(task.id), hasLength(3));

    await tasks.deleteTask(task.id);

    expect(await db.select(db.threadEvents).get(), isEmpty);
    expect(await completionCount(), 1,
        reason: '完成记录是学习历史，不随调度节点删除');
  });
}

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/thread/thread_event_kind.dart';
import 'package:furnace/domain/services/thread/thread_flow_writer.dart';
import 'package:furnace/domain/services/thread/thread_node_kind.dart';
import 'package:furnace/domain/services/thread/thread_status.dart';

/// `ThreadFlowWriter`（schema v47，2026-11-15）：契约
/// `INTEGRATION-CONTRACT-2026-11-15.md` §3.4 的唯一状态写口。
///
/// 要锁的行为（每条都能单独失败）：
///
///  * 创建按 `tasks.source_key` 幂等：同 key 跑两次只有一行、一条 created；
///  * 开始/提交/卡住/跳过/完成/重开各写一条事件，状态按词表迁移；
///  * **只有完成**写 `completion_logs`；提交/卡住/跳过/重开都不写；
///  * 重开（blocked/skipped/done → todo）清 `completed_at`，但不回滚完成历史；
///  * 事件 append-only：不给 sourceKey 时每次调用追加一行；
///  * 给了 sourceKey 的重试幂等：同 (task, kind, sourceKey) 只有一行；
///  * 非法迁移（skipped → completed、todo → reopened、未知 task）直接抛错，
///    不写半个事实；
///  * payload 上限 4 KB。
void main() {
  late AppDatabase db;
  late ThreadFlowWriter writer;

  final t0 = DateTime.fromMillisecondsSinceEpoch(1700000000000);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    writer = ThreadFlowWriter(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<Task> seedTask({
    String title = '平抛练习',
    ThreadNodeKind kind = ThreadNodeKind.task,
    String? sourceKey,
  }) {
    return writer.ensureTask(
      title: title,
      kind: kind,
      sourceKey: sourceKey,
      at: t0,
    );
  }

  test('ensureTask 按 source_key 幂等：跑两次只有一行、一条 created 事件', () async {
    final first = await seedTask(sourceKey: 'practice:Q-PH0001:2026-11-15');
    final second = await seedTask(sourceKey: 'practice:Q-PH0001:2026-11-15');

    expect(second.id, first.id);
    final rows = await db.select(db.tasks).get();
    expect(rows, hasLength(1));
    expect(rows.single.kind, ThreadNodeKind.task.id);
    expect(rows.single.sourceKey, 'practice:Q-PH0001:2026-11-15');
    expect(rows.single.status, ThreadStatus.todo.id);

    final events = await writer.eventsFor(first.id);
    expect(events, hasLength(1));
    expect(events.single.kind, ThreadEventKind.created.id);
    expect(events.single.occurredAt, t0.millisecondsSinceEpoch);
  });

  test('ensureTask 复用 source_key 但 kind 不同：抛错而不是悄悄返回', () async {
    await seedTask(kind: ThreadNodeKind.day, sourceKey: 'day:2026-11-15');
    await expectLater(
      seedTask(kind: ThreadNodeKind.paper, sourceKey: 'day:2026-11-15'),
      throwsA(isA<StateError>()),
    );
  });

  test('started：todo → doing，stamp started_at，追加 started 事件', () async {
    final task = await seedTask();
    final result = await writer.start(task.id, at: t0.add(const Duration(minutes: 5)));

    expect(result.applied, isTrue);
    expect(result.task.status, ThreadStatus.doing.id);
    expect(result.task.startedAt, t0.add(const Duration(minutes: 5)).millisecondsSinceEpoch);
    expect(result.event!.kind, ThreadEventKind.started.id);

    final events = await writer.eventsFor(task.id);
    expect(events.map((e) => e.kind), [ThreadEventKind.created.id, ThreadEventKind.started.id]);
  });

  test('planned：不改状态，写调度字段并追加 planned 事件', () async {
    final task = await seedTask();
    final result = await writer.plan(
      task.id,
      at: t0,
      dueAt: 123,
      expectedAt: 456,
      estimateMinutes: 20,
      energyRequired: 6,
    );

    expect(result.task.status, ThreadStatus.todo.id);
    expect(result.task.dueAt, 123);
    expect(result.task.expectedAt, 456);
    expect(result.task.estimateMinutes, 20);
    expect(result.task.energyRequired, 6);
    expect(result.event!.kind, ThreadEventKind.planned.id);
  });

  test('submitted：状态不变、写 submitted 事件、不写完成记录', () async {
    final task = await seedTask();
    await writer.start(task.id, at: t0);
    final result = await writer.submit(
      task.id,
      at: t0.add(const Duration(minutes: 10)),
      payload: const <String, Object?>{
        'verdict': 'pass',
        'attempt_ids': <String>['qa-1', 'qa-2'],
      },
    );

    expect(result.task.status, ThreadStatus.doing.id);
    final payload = jsonDecode(result.event!.payloadJson!) as Map<String, Object?>;
    expect(payload['verdict'], 'pass');
    expect(payload['attempt_ids'], ['qa-1', 'qa-2']);
    expect(await db.select(db.completionLogs).get(), isEmpty);
  });

  test('stuck / skipped：状态迁到 blocked / skipped，都不写完成记录', () async {
    final task = await seedTask();
    await writer.start(task.id, at: t0);

    final stuck = await writer.markStuck(task.id, reason: '卡在第 2 步', at: t0);
    expect(stuck.task.status, ThreadStatus.blocked.id);
    expect(stuck.event!.kind, ThreadEventKind.stuck.id);
    expect(
      (jsonDecode(stuck.event!.payloadJson!) as Map<String, Object?>)['reason'],
      '卡在第 2 步',
    );

    final skipped = await writer.skip(task.id, reason: '时间不够', at: t0);
    expect(skipped.task.status, ThreadStatus.skipped.id);
    expect(skipped.event!.kind, ThreadEventKind.skipped.id);
    expect(await db.select(db.completionLogs).get(), isEmpty);
  });

  test('completed：todo/doing → done，写完成快照（actualMinutes 由起止时刻推）',
      () async {
    final task = await seedTask();
    await writer.start(task.id, at: t0);
    final completedAt = t0.add(const Duration(minutes: 30));
    final result = await writer.complete(
      task.id,
      at: completedAt,
      tagIds: const ['tag-a', 'tag-b'],
      tagPaths: const ['物理/力学', '能力/A4'],
    );

    expect(result.task.status, ThreadStatus.done.id);
    expect(result.task.completedAt, completedAt.millisecondsSinceEpoch);
    expect(result.event!.kind, ThreadEventKind.completed.id);

    final logs = await db.select(db.completionLogs).get();
    expect(logs, hasLength(1));
    final log = logs.single;
    expect(log.taskId, task.id);
    expect(log.completedAt, completedAt.millisecondsSinceEpoch);
    expect(log.actualMinutes, 30);
    expect(log.tagIds, 'tag-a\u0001tag-b');
    expect(log.tagPaths, '物理/力学\u0001能力/A4');
    expect(log.includeInModel, isTrue);
  });

  test('完成重试幂等：同一 sourceKey 只有一条 completed 事件、一份完成记录', () async {
    final task = await seedTask(sourceKey: 'paper:QSET-20261115-01');
    await writer.start(task.id, at: t0);

    final first = await writer.complete(
      task.id,
      at: t0.add(const Duration(minutes: 40)),
      sourceKey: 'QSET-20261115-01:completed',
    );
    final second = await writer.complete(
      task.id,
      at: t0.add(const Duration(minutes: 41)),
      sourceKey: 'QSET-20261115-01:completed',
    );

    expect(first.applied, isTrue);
    expect(second.applied, isFalse);
    expect(second.event!.id, first.event!.id);
    final completedEvents =
        (await writer.eventsFor(task.id)).where((e) => e.kind == 'completed');
    expect(completedEvents, hasLength(1));
    expect(await db.select(db.completionLogs).get(), hasLength(1));
  });

  test('事件 append-only：不给 sourceKey 时每次调用都追加一行', () async {
    final task = await seedTask();
    await writer.start(task.id, at: t0);
    await writer.start(task.id, at: t0.add(const Duration(minutes: 1)));

    final started =
        (await writer.eventsFor(task.id)).where((e) => e.kind == 'started');
    expect(started, hasLength(2));
  });

  test('非法迁移直接抛错：skipped 不能直接 completed，未知 task 不存在', () async {    final task = await seedTask();
    await writer.skip(task.id, reason: '先跳过', at: t0);

    await expectLater(
      writer.complete(task.id, at: t0),
      throwsA(isA<StateError>()),
    );
    // 失败的迁移没有留下第二个事实：状态还是 skipped，完成记录仍是 0。
    final reloaded = await (db.select(db.tasks)..where((t) => t.id.equals(task.id)))
        .getSingle();
    expect(reloaded.status, ThreadStatus.skipped.id);
    expect(await db.select(db.completionLogs).get(), isEmpty);

    await expectLater(
      writer.start('task-does-not-exist'),
      throwsA(isA<StateError>()),
    );
  });

  test('payload 超过 4 KB 直接拒绝，不写半个事件', () async {
    final task = await seedTask();
    await expectLater(
      writer.submit(
        task.id,
        payload: <String, Object?>{'blob': 'x' * 5000},
      ),
      throwsA(isA<ArgumentError>()),
    );
    final events = await writer.eventsFor(task.id);
    expect(events.map((e) => e.kind), [ThreadEventKind.created.id]);
  });

  group('reopened（重开/恢复，task-90）', () {
    test('blocked → todo：写 reopened 事件、不改完成历史', () async {
      final task = await seedTask();
      await writer.markStuck(task.id, reason: '卡住', at: t0);

      final result = await writer.reopen(task.id, at: t0);

      expect(result.applied, isTrue);
      expect(result.task.status, ThreadStatus.todo.id);
      expect(result.task.completedAt, isNull);
      expect(result.event!.kind, ThreadEventKind.reopened.id);
      expect(await db.select(db.completionLogs).get(), isEmpty);
      expect(
        (await writer.eventsFor(task.id)).map((e) => e.kind),
        unorderedEquals(<String>[
          ThreadEventKind.created.id,
          ThreadEventKind.stuck.id,
          ThreadEventKind.reopened.id,
        ]),
      );
    });

    test('skipped → todo：行保留、写 reopened 事件', () async {
      final task = await seedTask();
      await writer.skip(task.id, reason: '时间不够', at: t0);

      final result = await writer.reopen(task.id, at: t0);

      expect(result.task.status, ThreadStatus.todo.id);
      expect(result.event!.kind, ThreadEventKind.reopened.id);
      // 同一毫秒内写入时 `eventsFor` 按 id 兜底排序，不保证流程次序；这里只认
      // "三种事实都在、各一条"。
      final events = await writer.eventsFor(task.id);
      expect(
        events.map((e) => e.kind),
        unorderedEquals(<String>[
          ThreadEventKind.created.id,
          ThreadEventKind.skipped.id,
          ThreadEventKind.reopened.id,
        ]),
      );
      expect(await db.select(db.tasks).get(), hasLength(1),
          reason: '跳过不是删除，恢复更不是重建');
      expect(await db.select(db.completionLogs).get(), isEmpty);
    });

    test('done → todo：清 completed_at，但 completion_logs 不回滚', () async {
      final task = await seedTask();
      await writer.start(task.id, at: t0);
      final completedAt = t0.add(const Duration(minutes: 30));
      await writer.complete(
        task.id,
        at: completedAt,
        tagPaths: const ['物理/力学'],
      );

      final result = await writer.reopen(task.id, at: t0);
      final reloaded =
          await (db.select(db.tasks)..where((t) => t.id.equals(task.id)))
              .getSingle();

      expect(reloaded.status, ThreadStatus.todo.id);
      expect(reloaded.completedAt, isNull, reason: '契约 §3.4：重开清 completed_at');
      expect(reloaded.startedAt, t0.millisecondsSinceEpoch,
          reason: '契约 §3.4 只清 completed_at：started_at 保持原样');
      expect(result.event!.kind, ThreadEventKind.reopened.id);
      expect(await db.select(db.completionLogs).get(), hasLength(1),
          reason: '历史即事实：重开不删完成记录');
    });

    test('非法来源（todo/doing）直接抛错，状态不变、不写事件', () async {
      final todoTask = await seedTask(title: '还在待办');
      await expectLater(
        writer.reopen(todoTask.id, at: t0),
        throwsA(isA<StateError>()),
      );
      expect(
        (await writer.eventsFor(todoTask.id)).map((e) => e.kind),
        [ThreadEventKind.created.id],
      );

      final doingTask = await seedTask(title: '正在做');
      await writer.start(doingTask.id, at: t0);
      await expectLater(
        writer.reopen(doingTask.id, at: t0),
        throwsA(isA<StateError>()),
      );
      final reloaded =
          await (db.select(db.tasks)..where((t) => t.id.equals(doingTask.id)))
              .getSingle();
      expect(reloaded.status, ThreadStatus.doing.id);
      // 同一毫秒内写入时 `eventsFor` 按 id 兜底排序，不保证流程次序。
      expect(
        (await writer.eventsFor(doingTask.id)).map((e) => e.kind),
        unorderedEquals(<String>[
          ThreadEventKind.created.id,
          ThreadEventKind.started.id,
        ]),
        reason: '被拒绝的迁移不能留下半个事实',
      );
    });

    test('同一 source_key 重试幂等：只有一条 reopened 事件', () async {
      final task = await seedTask(sourceKey: 'practice:Q-PH0001:2026-11-15');
      await writer.skip(task.id, at: t0);

      final first = await writer.reopen(
        task.id,
        at: t0,
        sourceKey: 'Q-PH0001:reopened',
      );
      final second = await writer.reopen(
        task.id,
        at: t0.add(const Duration(minutes: 1)),
        sourceKey: 'Q-PH0001:reopened',
      );

      expect(first.applied, isTrue);
      expect(second.applied, isFalse);
      expect(second.event!.id, first.event!.id);
      final reopened =
          (await writer.eventsFor(task.id)).where((e) => e.kind == 'reopened');
      expect(reopened, hasLength(1));
    });

    test('不给 sourceKey 时每次重开都追加一行（append-only）', () async {
      final task = await seedTask();
      await writer.skip(task.id, at: t0);
      await writer.reopen(task.id, at: t0);
      await writer.skip(task.id, at: t0);
      await writer.reopen(task.id, at: t0);

      final reopened =
          (await writer.eventsFor(task.id)).where((e) => e.kind == 'reopened');
      expect(reopened, hasLength(2));
    });

    test('reason 进 payload（流程事实，不是判分）', () async {
      final task = await seedTask();
      await writer.skip(task.id, at: t0);

      final result = await writer.reopen(
        task.id,
        reason: '误点跳过',
        at: t0,
      );

      final payload =
          jsonDecode(result.event!.payloadJson!) as Map<String, Object?>;
      expect(payload['reason'], '误点跳过');
      expect(await db.select(db.completionLogs).get(), isEmpty);
    });
  });

  test('词表默认值：NULL 读作 task / todo，未知值不崩', () {
    expect(ThreadNodeKind.fromStorage(null), ThreadNodeKind.task);
    expect(ThreadNodeKind.fromStorage('nope'), ThreadNodeKind.task);
    expect(ThreadStatus.fromStorage(null), ThreadStatus.todo);
    expect(ThreadStatus.fromStorage('nope'), ThreadStatus.todo);
    expect(ThreadEventKind.fromId('stuck'), ThreadEventKind.stuck);
    expect(ThreadEventKind.fromId('reopened'), ThreadEventKind.reopened);
    expect(ThreadEventKind.fromId(null), isNull);
    expect(ThreadEventKind.reopened.targetStatus, ThreadStatus.todo);
    expect(
      ThreadEventKind.reopened.allowedFrom,
      {ThreadStatus.blocked, ThreadStatus.skipped, ThreadStatus.done},
    );
    expect(ThreadNodeKind.week.isContainer, isTrue);
    expect(ThreadNodeKind.paper.isContainer, isFalse);
    expect(ThreadStatus.blocked.isSchedulable, isFalse);
    expect(ThreadStatus.doing.isSchedulable, isTrue);
    expect(ThreadStatus.blocked.appearsInWindow, isTrue);
    expect(ThreadStatus.skipped.appearsInWindow, isFalse);
  });
}

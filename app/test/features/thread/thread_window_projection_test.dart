import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/domain/services/thread/thread_node_kind.dart';
import 'package:furnace/features/thread/application/thread_rank_service.dart';
import 'package:furnace/features/thread/application/thread_window_projection.dart';

/// `threadWindowBucketsProvider`：从**已经排好序的** ThreadFeed 派生本周/本日分类。
///
/// 钉三件事：
///  1. 分类只过滤、次序照抄 `ThreadFeed.readyTasks`（不重排）；
///  2. `expectedAt ?? dueAt` 的成员关系、未排期归 unscheduled、done/skipped 不出现；
///  3. 还没排序时返回 null（页面显示"需要重新排序"，而不是自己排一遍）。
void main() {
  late AppDatabase db;
  late TaskRepository tasks;
  final now = DateTime(2026, 11, 15, 12); // 2026-W46 的周日中午

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tasks = TaskRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  ProviderContainer container() {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        threadWindowNowProvider.overrideWithValue(now),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('还没排序（ThreadFeed == null）→ 投影是 null', () {
    final c = container();

    expect(c.read(threadWindowBucketsProvider), isNull);
  });

  test('分类来自同一份排序：顺序照抄 readyTasks，未排期/终态分开', () async {
    final today = await tasks.createTask(
      title: '今天做的',
      expectedAt: DateTime(2026, 11, 15, 9).millisecondsSinceEpoch,
    );
    final tuesday = await tasks.createTask(
      title: '周二做的',
      expectedAt: DateTime(2026, 11, 10, 10).millisecondsSinceEpoch,
    );
    final nextMonday = await tasks.createTask(
      title: '下周一才做',
      dueAt: DateTime(2026, 11, 16).millisecondsSinceEpoch,
    );
    final noDate = await tasks.createTask(title: '还没排时间');
    final done = await tasks.createTask(
      title: '已经做完',
      status: 'done',
      expectedAt: DateTime(2026, 11, 15, 9).millisecondsSinceEpoch,
    );
    final blocked = await tasks.createTask(
      title: '卡住的那道',
      status: 'blocked',
      expectedAt: DateTime(2026, 11, 15, 10).millisecondsSinceEpoch,
    );
    // 物化器建的周容器（带 windowStart），应该出现在本周桶里。
    final weekContainer = await tasks.createTask(
      title: '组卷 · 2026-W46',
      kind: ThreadNodeKind.week,
      sourceKey: 'paper:week:2026-W46:plan',
      expectedAt: DateTime(2026, 11, 9).millisecondsSinceEpoch,
    );

    final c = container();
    await c.read(threadFeedProvider.notifier).sort();
    final feed = c.read(threadFeedProvider).value!;
    final buckets = c.read(threadWindowBucketsProvider)!;

    expect(buckets.isEmpty, isFalse);
    expect(buckets.weekWindow.start, DateTime(2026, 11, 9));
    expect(buckets.dayWindow.start, DateTime(2026, 11, 15));

    // readyTasks 里的本周成员，顺序必须原样保留。
    final readyWeekIds = [
      for (final task in feed.readyTasks)
        if (task.id == today.id || task.id == tuesday.id) task.id,
    ];
    expect(
      buckets.week.take(readyWeekIds.length).map((n) => n.id),
      readyWeekIds,
      reason: '分类不重排：本周桶前段就是 readyTasks 的相对顺序',
    );
    expect(
      buckets.week.map((n) => n.id),
      containsAll([today.id, tuesday.id, weekContainer.id]),
    );
    expect(
      buckets.week.map((n) => n.id),
      isNot(contains(nextMonday.id)),
      reason: '下周一 00:00 不在本周半开区间里',
    );
    expect(
      buckets.week.map((n) => n.id),
      isNot(contains(noDate.id)),
    );

    // 本日桶：今天 + blocked（blocked 不进 ready，但契约要求出现在窗口里）。
    expect(
      buckets.day.map((n) => n.id),
      containsAll([today.id, blocked.id]),
    );
    expect(
      buckets.day.map((n) => n.id),
      isNot(contains(tuesday.id)),
    );

    // 未排期单独一桶，且不进任何时间窗。
    expect(buckets.unscheduled.map((n) => n.id), [noDate.id]);

    // done 完全不出现（不是"未排期"，是归档）。
    final allIds = [
      ...buckets.week.map((n) => n.id),
      ...buckets.day.map((n) => n.id),
      ...buckets.unscheduled.map((n) => n.id),
    ];
    expect(allIds, isNot(contains(done.id)));
  });
}

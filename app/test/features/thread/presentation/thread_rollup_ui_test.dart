import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/domain/services/thread/thread_node_kind.dart';
import 'package:furnace/features/thread/application/thread_rank_service.dart';
import 'package:furnace/features/thread/application/thread_window_projection.dart';
import 'package:furnace/features/thread/presentation/event_properties_page.dart';
import 'package:furnace/features/thread/presentation/thread_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// Thread 里的父容器子任务汇总（只读，2026-11-15）。
///
/// 要锁的行为（UI 层）：
///
///  * 本周/本日 chips 上出现同类容器的 `done/total` 进度，没有可汇总容器时
///    完全不出现（不显示假的 0/0）；
///  * 容器行在列表里显示 `子任务 1/2 · 50% · 跳过 1` 一行；
///  * 事件属性页显示只读「子任务汇总」卡（状态/计数/合计估时/进度）；
///  * **显示这些不会写父容器状态**（父行仍是 todo，tasks/thread_events 行数不变）。
void main() {
  final zh = lookupAppLocalizations(const Locale('zh'));
  // 2026-11-15 是周日；本周 = 2026-11-09（周一）.. 2026-11-16。
  final now = DateTime(2026, 11, 15, 12);

  Future<(ProviderContainer, AppDatabase, _RollupFixture)> pumpThread(
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = TaskRepository(db);
    final fixture = await _seed(repo);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        threadWindowNowProvider.overrideWithValue(now),
      ],
    );
    addTearDown(container.dispose);
    await container.read(threadFeedProvider.notifier).sort();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ThreadPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (container, db, fixture);
  }

  testWidgets('本周/本日 chips 显示同类容器的子任务进度，容器行显示汇总', (tester) async {
    final (_, db, fixture) = await pumpThread(tester);
    final repo = TaskRepository(db);
    final tasksBefore = await _taskSnapshot(db);
    final eventsBefore = await _eventSnapshot(db);

    // 两个窗口都有内容：chips 出现，并带上各自的汇总进度。
    expect(find.text(zh.threadWindowWeek), findsOneWidget);
    expect(find.text(zh.threadWindowDay), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('thread-window-rollup-week')),
          )
          .data,
      '1/2',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('thread-window-rollup-day')),
          )
          .data,
      '0/2',
    );

    // 本周：周容器 + 日容器都在列表里；周容器的汇总行 1/2 → 50%，跳过 1。
    await tester.tap(find.text(zh.threadWindowWeek));
    await tester.pumpAndSettle();
    expect(find.text('第 46 周组卷'), findsOneWidget);
    expect(find.text('今日组卷'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(
          ValueKey('thread-rollup-line-${fixture.weekContainerId}'),
        ),
        matching: find.textContaining('子任务 1/2 · 50%'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(
          ValueKey('thread-rollup-line-${fixture.dayContainerId}'),
        ),
        matching: find.textContaining('子任务 0/2 · 0% · 卡住 1'),
      ),
      findsOneWidget,
    );

    // 本日：只剩日容器（周容器锚点在周一 0:00，不进日窗口）。
    await tester.tap(find.text(zh.threadWindowDay));
    await tester.pumpAndSettle();
    expect(find.text('第 46 周组卷'), findsNothing);
    expect(find.text('今日组卷'), findsOneWidget);

    // 显示汇总没有写任何东西：父容器仍是 todo，任务/事件行完全没变。
    expect((await repo.getTaskById(fixture.weekContainerId))!.status, 'todo');
    expect((await repo.getTaskById(fixture.dayContainerId))!.status, 'todo');
    expect(await _taskSnapshot(db), tasksBefore);
    expect(await _eventSnapshot(db), eventsBefore);
  });

  testWidgets('事件属性页显示只读子任务汇总卡（父状态不被写回）', (tester) async {
    final (container, db, fixture) = await pumpThread(tester);
    final repo = TaskRepository(db);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: EventPropertiesPage(taskId: fixture.weekContainerId),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('thread-rollup-card')), findsOneWidget);
    expect(find.text(zh.threadRollupSection), findsOneWidget);
    expect(find.text(zh.threadRollupStatus), findsOneWidget);
    expect(find.text(zh.tasksStatusDone), findsOneWidget);
    // 周容器：done 1 / skipped 1，没有 todo/doing/blocked。
    expect(find.text(zh.threadRollupCountsLine(0, 0, 1, 0, 1)), findsOneWidget);
    expect(find.text(zh.threadRollupEstimate(15)), findsOneWidget);
    expect(find.text(zh.threadRollupReadOnly), findsOneWidget);

    expect((await repo.getTaskById(fixture.weekContainerId))!.status, 'todo');
  });

  testWidgets('没有容器（也就没有子任务）时不显示任何 rollup 进度', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await TaskRepository(db).createTask(
      title: '今天做的',
      expectedAt: DateTime(2026, 11, 15, 9).millisecondsSinceEpoch,
    );
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        threadWindowNowProvider.overrideWithValue(now),
      ],
    );
    addTearDown(container.dispose);
    await container.read(threadFeedProvider.notifier).sort();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ThreadPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // chips 在（本周有任务），但没有可汇总的容器 → chips 上不出现进度数字。
    expect(find.text(zh.threadWindowWeek), findsOneWidget);
    expect(
      find.byKey(const ValueKey('thread-window-rollup-week')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('thread-window-rollup-day')),
      findsNothing,
    );
  });
}

class _RollupFixture {
  const _RollupFixture({
    required this.weekContainerId,
    required this.dayContainerId,
  });

  final String weekContainerId;
  final String dayContainerId;
}

/// 两棵独立的容器树（与 `PaperTaskMaterializer` 的形状一致：容器 + 逐题子节点）：
///
///  * 周容器：2 个子任务（1 done、1 skipped，估时 10 + 5 = 15）→ 1/2 = 50%；
///  * 日容器：2 个子任务（1 todo、1 blocked，估时 7 + 3 = 10）→ 0/2 = 0%。
///
/// 子任务状态直接写在 `createTask(status:)` 的初始行上（测试夹具口径，不经过
/// 状态机），因为这里要钉的是"读侧汇总"，不是迁移合法性。
Future<_RollupFixture> _seed(TaskRepository repo) async {
  final week = await repo.createTask(
    title: '第 46 周组卷',
    kind: ThreadNodeKind.week,
    sourceKey: 'paper:week:2026-W46:rollup-ui',
    expectedAt: DateTime(2026, 11, 9).millisecondsSinceEpoch,
  );
  await repo.createTask(
    title: '周·第 1 题',
    parentId: week.id,
    status: 'done',
    estimateMinutes: 10,
    expectedAt: DateTime(2026, 11, 9).millisecondsSinceEpoch,
  );
  await repo.createTask(
    title: '周·第 2 题',
    parentId: week.id,
    status: 'skipped',
    estimateMinutes: 5,
    expectedAt: DateTime(2026, 11, 9).millisecondsSinceEpoch,
  );

  final day = await repo.createTask(
    title: '今日组卷',
    kind: ThreadNodeKind.day,
    sourceKey: 'paper:day:2026-11-15:rollup-ui',
    expectedAt: DateTime(2026, 11, 15, 9).millisecondsSinceEpoch,
  );
  await repo.createTask(
    title: '日·第 1 题',
    parentId: day.id,
    estimateMinutes: 7,
    expectedAt: DateTime(2026, 11, 15, 9).millisecondsSinceEpoch,
  );
  await repo.createTask(
    title: '日·第 2 题',
    parentId: day.id,
    status: 'blocked',
    estimateMinutes: 3,
    expectedAt: DateTime(2026, 11, 15, 9).millisecondsSinceEpoch,
  );

  return _RollupFixture(
    weekContainerId: week.id,
    dayContainerId: day.id,
  );
}

Future<List<String>> _taskSnapshot(AppDatabase db) async {
  final rows = await db.select(db.tasks).get();
  return [
    for (final row in rows) '${row.id}:${row.status}:${row.updatedAt}',
  ];
}

Future<List<String>> _eventSnapshot(AppDatabase db) async {
  final rows = await db.select(db.threadEvents).get();
  return [for (final row in rows) '${row.id}:${row.taskId}:${row.kind}'];
}

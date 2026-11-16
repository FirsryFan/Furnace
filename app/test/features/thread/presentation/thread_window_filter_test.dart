import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/features/thread/application/thread_rank_service.dart';
import 'package:furnace/features/thread/application/thread_window_projection.dart';
import 'package:furnace/features/thread/presentation/thread_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// Thread 页顶部的「全部 / 本周任务 / 本日任务」临时分类（契约 §3.5）。
///
/// 产品没有任务侧边栏（契约 §3.5 已确认）；窗口派生做成 Thread 页的临时过滤，
/// 语义与契约一致：只过滤已排好的列表、不改排序、不写库；两个窗口都空时整条分类栏
/// 不出现；还没排序时仍显示"需要重新排序"。
void main() {
  final zh = lookupAppLocalizations(const Locale('zh'));
  final now = DateTime(2026, 11, 15, 12); // 2026-W46 周日中午

  Future<(ProviderContainer, AppDatabase)> pumpThread(
    WidgetTester tester, {
    required Future<void> Function(TaskRepository tasks) seed,
    bool sort = true,
  }) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await seed(TaskRepository(db));
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        threadWindowNowProvider.overrideWithValue(now),
        threadRankNowProvider.overrideWithValue(now),
      ],
    );
    addTearDown(container.dispose);
    if (sort) {
      await container.read(threadFeedProvider.notifier).sort();
    }

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
    return (container, db);
  }

  testWidgets('本周 / 本日过滤只收敛列表，不改变"全部"的次序', (tester) async {
    late String todayId;
    late String tuesdayId;
    await pumpThread(
      tester,
      seed: (tasks) async {
        todayId = (await tasks.createTask(
          title: '今天做的',
          expectedAt: DateTime(2026, 11, 15, 9).millisecondsSinceEpoch,
        ))
            .id;
        tuesdayId = (await tasks.createTask(
          title: '周二做的',
          expectedAt: DateTime(2026, 11, 10, 10).millisecondsSinceEpoch,
        ))
            .id;
        await tasks.createTask(
          title: '下周一才做',
          dueAt: DateTime(2026, 11, 16).millisecondsSinceEpoch,
        );
        await tasks.createTask(title: '还没排时间');
      },
    );

    // 分类栏出现，默认选中「全部」。
    expect(find.text(zh.threadWindowAll), findsOneWidget);
    expect(find.text(zh.threadWindowWeek), findsOneWidget);
    expect(find.text(zh.threadWindowDay), findsOneWidget);
    expect(find.text('今天做的'), findsOneWidget);
    expect(find.text('周二做的'), findsOneWidget);
    expect(find.text('下周一才做'), findsOneWidget);
    expect(find.text('还没排时间'), findsOneWidget);

    // 本日任务：只剩今天那道（blocked/未排期/下周一都不在）。
    await tester.tap(find.text(zh.threadWindowDay));
    await tester.pumpAndSettle();
    expect(find.text('今天做的'), findsOneWidget);
    expect(find.text('周二做的'), findsNothing);
    expect(find.text('下周一才做'), findsNothing);
    expect(find.text('还没排时间'), findsNothing);

    // 本周任务：今天 + 周二；下周一（窗口外）与未排期都不在。
    await tester.tap(find.text(zh.threadWindowWeek));
    await tester.pumpAndSettle();
    expect(find.text('今天做的'), findsOneWidget);
    expect(find.text('周二做的'), findsOneWidget);
    expect(find.text('下周一才做'), findsNothing);
    expect(find.text('还没排时间'), findsNothing);

    // 全部：恢复原来的四行。
    await tester.tap(find.text(zh.threadWindowAll));
    await tester.pumpAndSettle();
    expect(find.text('今天做的'), findsOneWidget);
    expect(find.text('周二做的'), findsOneWidget);
    expect(find.text('下周一才做'), findsOneWidget);
    expect(find.text('还没排时间'), findsOneWidget);

    expect(todayId, isNotEmpty);
    expect(tuesdayId, isNotEmpty);
  });

  testWidgets('两个时间窗都没有任务时，不显示"本周/本日"分类', (tester) async {
    await pumpThread(
      tester,
      seed: (tasks) async {
        await tasks.createTask(title: '还没排时间');
        await tasks.createTask(
          title: '下周一才做',
          dueAt: DateTime(2026, 11, 16).millisecondsSinceEpoch,
        );
      },
    );

    expect(find.text(zh.threadWindowAll), findsNothing);
    expect(find.text(zh.threadWindowWeek), findsNothing);
    expect(find.text(zh.threadWindowDay), findsNothing);
    // 原来的列表照常显示（没有时间窗任务不等于没有任务）。
    expect(find.text('还没排时间'), findsOneWidget);
    expect(find.text('下周一才做'), findsOneWidget);
  });

  testWidgets('还没排序：仍然只说"需要重新排序"，分类栏不出现', (tester) async {
    await pumpThread(
      tester,
      sort: false,
      seed: (tasks) async {
        await tasks.createTask(
          title: '今天做的',
          expectedAt: DateTime(2026, 11, 15, 9).millisecondsSinceEpoch,
        );
      },
    );

    expect(find.text(zh.threadNeedsSort), findsOneWidget);
    expect(find.text(zh.threadWindowWeek), findsNothing);
    expect(find.text(zh.threadWindowDay), findsNothing);
  });
}

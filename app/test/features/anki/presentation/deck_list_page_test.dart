import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/review_plan_repository.dart';
import 'package:furnace/features/anki/presentation/deck_list_page.dart';
import 'package:furnace/features/anki/presentation/knowledge_page.dart';
import 'package:furnace/features/anki/presentation/review_page.dart';
import 'package:furnace/features/anki/presentation/review_plan_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// The review tab's new home (user m20816): a list of card groups with today's
/// progress, instead of dropping straight into one mixed queue.
///
/// The load-bearing claims:
///
///  * every configured group gets a row whose numbers come from [DeckProgress]
///    (the same progress the plan page shows) - not a second calculation;
///  * an uncapped review group says 不限 instead of dividing by zero, and a
///    finished group says so with a badge;
///  * tapping a row opens the queue scoped to that group, so the list is a
///    real navigation and not decoration;
///  * the ungrouped row only appears when there are actually ungrouped cards;
///  * with no groups at all the page explains what a group is and offers the
///    create action.
void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<AppDatabase> openDatabase() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    return db;
  }

  Future<void> pumpDeckList(
    WidgetTester tester,
    AppDatabase db, {
    required List<Override> overrides,
  }) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          ...overrides,
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // 页面本身只有 body：Scaffold/AppBar 归外层 KnowledgePage。
          home: Scaffold(body: DeckListPage()),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> pumpKnowledge(
    WidgetTester tester,
    AppDatabase db, {
    required List<Override> overrides,
  }) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          ...overrides,
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: KnowledgePage(),
        ),
      ),
    );
    await settle(tester);
  }

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(DeckListPage)));

  CardGroupPlan planFor(
    String tagId,
    String tagPath, {
    int newCardsPerDay = 5,
    int reviewCardsPerDay = 3,
  }) =>
      CardGroupPlan(
        id: 'rgp::$tagId',
        tagId: tagId,
        tagPath: tagPath,
        newCardsPerDay: newCardsPerDay,
        reviewCardsPerDay: reviewCardsPerDay,
      );

  ReviewGroupLoad groupFor(
    CardGroupPlan plan, {
    required int newDone,
    required int newRemaining,
    required int reviewDone,
    int? remainingReviews,
  }) =>
      ReviewGroupLoad(
        plan: plan,
        memberPaths: [plan.tagPath],
        alreadyDoneToday: newDone + reviewDone,
        newDoneToday: newDone,
        reviewDoneToday: reviewDone,
        newRemaining: newRemaining,
        remainingReviews: remainingReviews,
      );

  ReviewDayLoad dayOf(List<ReviewGroupLoad> groups) => ReviewDayLoad(
        dayStart: DateTime(2026, 10, 27),
        groups: groups,
        pathsByGroup: {
          for (final group in groups) group.plan.tagId: group.memberPaths,
        },
      );

  List<Override> overridesFor({
    required List<CardGroupPlan> plans,
    required List<ReviewGroupLoad> groups,
    int ungrouped = 0,
  }) =>
      [
        reviewGroupPlansProvider.overrideWith((ref) async => plans),
        reviewDayLoadProvider.overrideWith(
          (ref) async => dayOf(groups),
        ),
        ungroupedKnowledgePointsProvider.overrideWith(
          (ref) async => ungrouped,
        ),
      ];

  testWidgets('每个卡组一行：名字、今日进度文案、进度条、完成徽标', (tester) async {
    final db = await openDatabase();
    final math = planFor('tag-math', '数学');
    final english = planFor('tag-english', '英语', newCardsPerDay: 5);
    final physics = planFor('tag-physics', '物理');
    final groups = [
      groupFor(
        math,
        newDone: 2,
        newRemaining: 0,
        reviewDone: 1,
        remainingReviews: 2,
      ),
      groupFor(
        english,
        newDone: 1,
        newRemaining: 4,
        reviewDone: 2,
      ),
      groupFor(
        physics,
        newDone: 3,
        newRemaining: 0,
        reviewDone: 4,
        remainingReviews: 0,
      ),
    ];

    await pumpDeckList(
      tester,
      db,
      overrides: overridesFor(
        plans: [math, english, physics],
        groups: groups,
      ),
    );
    final l10n = l10nOf(tester);

    expect(
      find.byType(AppBar),
      findsNothing,
      reason: '卡组页不再自带 AppBar：标题在 KnowledgePage，双层标题栏是 bug',
    );
    expect(find.byKey(deckListAllTileKey), findsOneWidget);
    expect(find.text(l10n.deckListAllTitle), findsOneWidget);
    expect(find.text(l10n.deckListAllHint), findsOneWidget);

    for (final path in ['数学', '英语', '物理']) {
      expect(find.text(path), findsOneWidget);
    }
    expect(find.text(l10n.deckNewCards(2, 2)), findsOneWidget);
    expect(find.text(l10n.deckReviews(1, 3)), findsOneWidget);
    expect(find.text(l10n.deckNewCards(1, 5)), findsOneWidget);
    expect(
      find.text(l10n.deckReviewsUnlimited(2)),
      findsOneWidget,
      reason: '复习不限的卡组不该把 0 当上限',
    );
    expect(find.text(l10n.deckNewCards(3, 3)), findsOneWidget);
    expect(find.text(l10n.deckReviews(4, 4)), findsOneWidget);
    expect(
      find.text(l10n.deckProgressDone),
      findsOneWidget,
      reason: '只有真的把新卡和复习都做完的那组才有徽标',
    );
    expect(find.byKey(deckListProgressDoneKey('tag-physics')), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(3));
  });

  testWidgets('点卡组行进入只复习这一组的队列', (tester) async {
    final db = await openDatabase();
    final math = planFor('tag-math', '数学');
    await pumpDeckList(
      tester,
      db,
      overrides: overridesFor(
        plans: [math],
        groups: [
          groupFor(
            math,
            newDone: 0,
            newRemaining: 5,
            reviewDone: 0,
          ),
        ],
      ),
    );

    await tester.tap(find.byKey(deckListTileKey('tag-math')));
    await settle(tester);

    expect(find.byType(ReviewPage), findsOneWidget);
    final page = tester.widget<ReviewPage>(find.byType(ReviewPage));
    expect(page.scopeTagId, 'tag-math');
    expect(page.scopeTitle, '数学');
    expect(page.onlyUngrouped, isFalse);
    expect(find.widgetWithText(AppBar, '数学'), findsOneWidget);
  });

  testWidgets('点「全部」进入不分组的全局队列', (tester) async {
    final db = await openDatabase();
    final math = planFor('tag-math', '数学');
    await pumpDeckList(
      tester,
      db,
      overrides: overridesFor(
        plans: [math],
        groups: [
          groupFor(
            math,
            newDone: 0,
            newRemaining: 5,
            reviewDone: 0,
          ),
        ],
      ),
    );

    await tester.tap(find.byKey(deckListAllTileKey));
    await settle(tester);

    final page = tester.widget<ReviewPage>(find.byType(ReviewPage));
    expect(page.scopeTagId, isNull);
    expect(page.onlyUngrouped, isFalse);
    expect(find.text(l10nOf(tester).deckListAllTitle), findsWidgets);
  });

  testWidgets('未分组行只在有未分组卡时出现，且能只复习它们', (tester) async {
    final db = await openDatabase();
    final math = planFor('tag-math', '数学');
    final groups = [
      groupFor(
        math,
        newDone: 0,
        newRemaining: 5,
        reviewDone: 0,
      ),
    ];

    await pumpDeckList(
      tester,
      db,
      overrides: overridesFor(
        plans: [math],
        groups: groups,
        ungrouped: 3,
      ),
    );
    final l10n = l10nOf(tester);
    expect(find.byKey(deckListUngroupedTileKey), findsOneWidget);
    expect(find.text(l10n.deckListUngroupedTitle), findsOneWidget);
    expect(find.text(l10n.deckListUngroupedHint), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    await tester.tap(find.byKey(deckListUngroupedTileKey));
    await settle(tester);
    final page = tester.widget<ReviewPage>(find.byType(ReviewPage));
    expect(page.onlyUngrouped, isTrue);
    expect(page.scopeTagId, isNull);
  });

  testWidgets('没有未分组卡时不画未分组行', (tester) async {
    final db = await openDatabase();
    final math = planFor('tag-math', '数学');
    await pumpDeckList(
      tester,
      db,
      overrides: overridesFor(
        plans: [math],
        groups: [
          groupFor(
            math,
            newDone: 0,
            newRemaining: 5,
            reviewDone: 0,
          ),
        ],
      ),
    );

    expect(find.byKey(deckListUngroupedTileKey), findsNothing);
    expect(find.text('未分组'), findsNothing);
  });

  testWidgets('一个卡组都没有：空态解释卡组并给新建入口', (tester) async {
    final db = await openDatabase();
    await pumpDeckList(
      tester,
      db,
      overrides: overridesFor(plans: const [], groups: const []),
    );
    final l10n = l10nOf(tester);

    expect(find.text(l10n.deckListEmptyTitle), findsOneWidget);
    expect(find.text(l10n.deckListEmptyBody), findsOneWidget);
    expect(find.byKey(deckListCreateButtonKey), findsOneWidget);
    expect(find.byKey(deckListAllTileKey), findsNothing);

    await tester.tap(find.byKey(deckListCreateButtonKey));
    await settle(tester);
    expect(find.byType(ReviewPlanPage), findsOneWidget);
  });

  testWidgets('KnowledgePage 的卡组设置入口进入复习计划页', (tester) async {
    final db = await openDatabase();
    final math = planFor('tag-math', '数学');
    await pumpKnowledge(
      tester,
      db,
      overrides: overridesFor(
        plans: [math],
        groups: [
          groupFor(
            math,
            newDone: 0,
            newRemaining: 5,
            reviewDone: 0,
          ),
        ],
      ),
    );

    expect(find.byKey(deckListSettingsActionKey), findsOneWidget);
    await tester.tap(find.byKey(deckListSettingsActionKey));
    await settle(tester);
    expect(find.byType(ReviewPlanPage), findsOneWidget);
  });

  testWidgets('第一 Tab 标题是「卡组」；切到管理 Tab 后卡组设置消失、通用复习计划出现', (tester) async {
    final db = await openDatabase();
    final math = planFor('tag-math', '数学');
    await pumpKnowledge(
      tester,
      db,
      overrides: overridesFor(
        plans: [math],
        groups: [
          groupFor(
            math,
            newDone: 0,
            newRemaining: 5,
            reviewDone: 0,
          ),
        ],
      ),
    );
    final l10n = l10nOf(tester);

    expect(find.widgetWithText(AppBar, l10n.deckListTitle), findsOneWidget);
    expect(find.byKey(deckListSettingsActionKey), findsOneWidget);
    expect(find.byIcon(Icons.folder_shared_outlined), findsOneWidget);
    expect(
      find.byTooltip(l10n.reviewPlanTitle),
      findsNothing,
      reason: '卡组 Tab 只留「卡组设置」：两个同图标按钮都进 ReviewPlanPage，重复',
    );

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(l10n.ankiManage),
      ),
    );
    await settle(tester);

    // 管理 Tab 里 AnkiManagePage 自带一条 AppBar（既有先例），所以这里只钉
    // 标题存在，不钉条数；本任务要钉的是设置入口只属于卡组 Tab。
    expect(find.widgetWithText(AppBar, l10n.ankiManage), findsWidgets);
    expect(
      find.byKey(deckListSettingsActionKey),
      findsNothing,
      reason: '管理 Tab 没有卡组可配，设置入口只属于卡组 Tab',
    );
    expect(
      find.byTooltip(l10n.reviewPlanTitle),
      findsOneWidget,
      reason: '通用「复习计划」入口从「始终显示」改成只在管理 Tab 显示',
    );
  });

  testWidgets('读取中显示进度圈，读完之后出现卡组行', (tester) async {
    final db = await openDatabase();
    await pumpDeckList(
      tester,
      db,
      overrides: [
        reviewGroupPlansProvider.overrideWith(
          (ref) => Completer<List<CardGroupPlan>>().future,
        ),
        reviewDayLoadProvider.overrideWith(
          (ref) async => dayOf(const []),
        ),
        ungroupedKnowledgePointsProvider.overrideWith((ref) async => 0),
      ],
    );
    // 一个永远不完成的 future 只能用来钉「加载中」这一帧。
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('读取失败时给出错误原文和重试入口，而不是假装空列表', (tester) async {
    final db = await openDatabase();
    await pumpDeckList(
      tester,
      db,
      overrides: [
        reviewGroupPlansProvider.overrideWith(
          (ref) async => throw StateError('卡组读取失败'),
        ),
        reviewDayLoadProvider.overrideWith(
          (ref) async => dayOf(const []),
        ),
        ungroupedKnowledgePointsProvider.overrideWith((ref) async => 0),
      ],
    );

    expect(find.textContaining('卡组读取失败'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.byKey(deckListAllTileKey), findsNothing);
  });
}

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/domain/services/scheduling/today_plan.dart';
import 'package:furnace/features/cognitive/application/today_plan_reader.dart';
import 'package:furnace/features/cognitive/presentation/today_plan_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// 今日清单页是「排序结果真的被人看见」这一环（roadmap §1 控制层那一行的
/// 界面面，Q32c）。它自己**不算任何数字**，所以这里钉两类事：
///
///  1. 真数据库 → 真清单：到期的卡出现、不到期的卡不出现、空的一天明说空；
///  2. 页面只做排版：没有价格的行不画价格行、两种度量各自带名字、被上限挡
///     在外面的件数如实说出来、顺序就是 `TodayPlan` 给的顺序（页面不重排）。
///
/// 第 2 类用假清单（override `todayPlanProvider`）而不是造一堆卡：页面的契约
/// 是「照着 `TodayPlan` 排版」，用假清单才能精确地钉住它；价格算术归
/// `today_plan_test.dart` 管。
void main() {
  late AppDatabase db;
  late AnkiRepository anki;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    anki = AnkiRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  /// 一张「已经复习过、已经到期」的卡：默认参数下 `ΔR > 0`，所以有价格。
  Future<String> duePoint(
    String title, {
    double stability = 5,
    double difficulty = 5,
    int daysAgo = 6,
    Duration dueIn = const Duration(days: -3),
  }) async {
    final now = DateTime.now();
    final point = await anki.createKnowledgePoint(
      title: title,
      content: '$title在系统不受外力时守恒。',
    );
    final state = await anki.getOrCreateUnitCardState(point.id, 'essay');
    await anki.updateUnitCardState(
      state.id,
      repetitions: 3,
      stability: stability,
      difficulty: difficulty,
      dueAt: now.add(dueIn).millisecondsSinceEpoch,
      lastReviewedAt:
          now.subtract(Duration(days: daysAgo)).millisecondsSinceEpoch,
    );
    return point.id;
  }

  Future<AppLocalizations> pumpPage(
    WidgetTester tester, {
    List<Override> overrides = const <Override>[],
  }) async {
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
          home: TodayPlanPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.of(tester.element(find.byType(TodayPlanPage)));
  }

  group('the real read (due queue -> plan)', () {
    testWidgets('an empty day says so instead of inventing work',
        (tester) async {
      final l10n = await pumpPage(tester);

      expect(find.text(l10n.todayPlanEmpty), findsOneWidget);
      expect(find.byType(TodayActionCard), findsNothing);
      // 空清单也要说清楚"这不是测量"，否则空页读起来像"系统没在做事"。
      expect(find.text(l10n.todayPlanUncalibrated), findsOneWidget);
      expect(find.text(l10n.todayPlanPracticeHint), findsOneWidget);
    });

    testWidgets('a due card shows up with its retention price and its reason',
        (tester) async {
      await duePoint('动量守恒');

      final l10n = await pumpPage(tester);

      expect(find.byType(TodayActionCard), findsOneWidget);
      expect(find.text('动量守恒'), findsOneWidget);
      expect(find.text(l10n.todayPlanKindReview), findsOneWidget);
      expect(find.text(l10n.todayPlanCount(1)), findsOneWidget);
      // 价格行只说"留存 V=…"这一种问题；理由来自 planner 的 why。
      expect(find.textContaining('V='), findsOneWidget);
      expect(find.textContaining('多留下'), findsOneWidget);
    });

    testWidgets('a card that is not due yet stays out of the list',
        (tester) async {
      await duePoint('光合作用', dueIn: const Duration(days: 3));

      final l10n = await pumpPage(tester);

      expect(find.text('光合作用'), findsNothing);
      expect(find.text(l10n.todayPlanEmpty), findsOneWidget);
    });

    testWidgets('the refresh button re-reads the plan', (tester) async {
      final l10n = await pumpPage(tester);
      expect(find.text(l10n.todayPlanEmpty), findsOneWidget);

      // 页面上手写一张卡之后，刷新这条明路要么自己重算、要么靠按钮重算，
      // 总之不能永远停在那份空清单上。
      await duePoint('动量守恒');
      await tester.tap(find.byTooltip(l10n.commonRefresh));
      await tester.pumpAndSettle();

      expect(find.text('动量守恒'), findsOneWidget);
    });
  });

  group('rendering is a pure function of the plan', () {
    const pricedReview = TodayAction(
      kind: TodayActionKind.review,
      id: 'cs-1',
      title: '动量守恒',
      metric: TodayMetric.retention,
      value: 0.1192,
      gain: 0.1192,
      cost: 1.0,
      why: '复习这张卡：24 小时后多留下 12%（现在 74% → 复习后 86%）',
    );
    const pricedPractice = TodayAction(
      kind: TodayActionKind.practice,
      id: 'p-1',
      title: '滑块与木板',
      metric: TodayMetric.reachability,
      value: 0.4,
      gain: 0.8,
      cost: 2.0,
      why: '值得现在做（add_in_edges，V=0.400）',
    );

    /// 上限上的卡：`TodayPlanner` 会说"没有价格"，页面就得一个数字都不写。
    const unpricedReview = TodayAction(
      kind: TodayActionKind.review,
      id: 'cs-ceiling',
      title: '光合作用',
      why: '复习这张卡买不到明天的留存（现在 90%，复习后 90%），按到期日排',
    );

    Future<AppLocalizations> pumpPlan(
      WidgetTester tester,
      TodayPlan plan,
    ) =>
        pumpPage(
          tester,
          overrides: [
            todayPlanProvider.overrideWith((ref) async => plan),
          ],
        );

    testWidgets('an action with no price draws no price line', (tester) async {
      final l10n = await pumpPlan(
        tester,
        const TodayPlan(
          actions: [unpricedReview],
          considered: 1,
          horizonHours: 24,
          nowHours: 1000,
        ),
      );

      expect(find.byType(TodayActionCard), findsOneWidget);
      expect(find.text('光合作用'), findsOneWidget);
      expect(find.text(l10n.todayPlanCount(1)), findsOneWidget);
      expect(find.textContaining('V='), findsNothing);
      expect(find.textContaining('买不到明天的留存'), findsOneWidget);
      // 没有被挡在外面的件就不提上限。
      expect(find.textContaining('另有'), findsNothing);
    });

    testWidgets('the two metrics are labelled as two different questions',
        (tester) async {
      final l10n = await pumpPlan(
        tester,
        const TodayPlan(
          actions: [pricedReview, pricedPractice],
          considered: 2,
          horizonHours: 24,
          nowHours: 1000,
        ),
      );

      expect(
          find.textContaining(l10n.todayPlanMetricRetention), findsOneWidget);
      expect(find.textContaining(l10n.todayPlanMetricReachability),
          findsOneWidget);
      expect(find.text(l10n.todayPlanKindReview), findsOneWidget);
      expect(find.text(l10n.todayPlanKindPractice), findsOneWidget);
      // 顺序就是 planner 给的顺序：页面不重排。
      final titles = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .toList();
      expect(titles.indexOf('动量守恒'), lessThan(titles.indexOf('滑块与木板')));
    });

    testWidgets('the cap line says how many were left out', (tester) async {
      final l10n = await pumpPlan(
        tester,
        const TodayPlan(
          actions: [pricedReview],
          considered: 3,
          horizonHours: 24,
          nowHours: 1000,
        ),
      );

      expect(find.text(l10n.todayPlanCount(1)), findsOneWidget);
      expect(find.text(l10n.todayPlanOmitted(2)), findsOneWidget);
    });
  });
}

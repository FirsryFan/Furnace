import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/domain/services/reasoning/chain_insights.dart';
import 'package:furnace/domain/services/reasoning/daily_study_plan.dart';
import 'package:furnace/domain/services/reasoning/learning_advice.dart';
import 'package:furnace/domain/services/scheduling/today_plan.dart';
import 'package:furnace/features/cognitive/application/daily_study_plan_reader.dart';
import 'package:furnace/features/cognitive/application/today_plan_reader.dart';
import 'package:furnace/features/cognitive/presentation/today_plan_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// 今日清单页是「排序结果真的被人看见」这一环（roadmap §1 控制层那一行的
/// 界面面，Q32c）。它自己**不算任何数字**，所以这里钉两类事：
///
///  1. 真数据库 → 真清单：到期的卡出现、不到期的卡不出现、空的一天明说空；
///  2. 页面只做排版：没有价格的行不画价格行、两种度量各自带名字、被上限挡
///     在外面的件数如实说出来、顺序就是 `TodayPlan` 给的顺序（页面不重排）。
///  3. 页顶「今天做什么」读推理层的 `DailyStudyPlan`：步骤/理由/分钟照抄，
///     被预算跳过的条数如实说，读失败给原文与重试，刷新同时重读两个 provider。
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

  /// 一份「今天做什么」计划：词表外的动作换一条「补词表」步骤，到期的 3 张
  /// 卡换一条复习步骤；`maxSteps` 用来制造「被预算跳过」的条数。
  DailyStudyPlan studyPlan({int maxSteps = DailyStudyPlan.defaultMaxSteps}) {
    final insights = ChainInsights.aggregate(
      chains: const [
        ChainInsightChain(
          chainId: 'c-1',
          questionId: 'q-1',
          steps: [
            ChainInsightStep(actionType: 'first_principles', stuckRisk: 0.2),
            ChainInsightStep(actionType: 'made_up_move', stuckRisk: 0.8),
          ],
        ),
      ],
    );
    return DailyStudyPlan.build(
      insights: insights,
      advices: LearningAdvicePlan.build(insights: insights),
      dueCardCount: 3,
      maxSteps: maxSteps,
    );
  }

  /// 什么依据都没有的一天：数据层会给一条 noData 步骤，页面照常展示。
  DailyStudyPlan emptyStudyPlan() {
    final insights = ChainInsights.aggregate(chains: const []);
    return DailyStudyPlan.build(
      insights: insights,
      advices: LearningAdvicePlan.build(insights: insights),
    );
  }

  Future<AppLocalizations> pumpStudyPlan(
    WidgetTester tester,
    Future<DailyStudyPlan> Function() load,
  ) =>
      pumpPage(
        tester,
        overrides: [
          dailyStudyPlanProvider.overrideWith((ref) => load()),
        ],
      );

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

  group('the study plan reads as steps, not numbers', () {
    testWidgets('the plan lists its steps with reasons and minutes',
        (tester) async {
      final plan = studyPlan();
      final l10n = await pumpStudyPlan(tester, () async => plan);

      expect(find.byKey(todayStudyPlanSectionKey), findsOneWidget);
      expect(find.text(l10n.todayStudyPlanTitle), findsOneWidget);
      expect(
        find.text(l10n.todayStudyPlanTotal(plan.totalMinutes)),
        findsOneWidget,
      );
      expect(find.text(l10n.todayStudyPlanSkipped(1)), findsNothing);
      expect(plan.steps.length, greaterThan(1));

      for (var index = 0; index < plan.steps.length; index++) {
        final step = plan.steps[index];
        expect(find.byKey(todayStudyPlanStepKey(index)), findsOneWidget);
        expect(find.text(step.titleZh), findsOneWidget);
        expect(find.text(step.detailZh), findsOneWidget);
        expect(
          find.text(
            l10n.todayStudyPlanStepMinutes(step.estimatedMinutes),
          ),
          findsWidgets,
        );
      }

      // 顺序就是 `DailyStudyPlan.steps` 的顺序：页面不重排。
      expect(
        tester.getTopLeft(find.byKey(todayStudyPlanStepKey(1))).dy,
        greaterThan(
          tester.getTopLeft(find.byKey(todayStudyPlanStepKey(0))).dy,
        ),
      );
      // 旧的复习侧清单还留在同一页：两份计划不合并。
      expect(find.text(l10n.todayPlanUncalibrated), findsOneWidget);
    });

    testWidgets('steps skipped by the budget are counted, not silently dropped',
        (tester) async {
      final full = studyPlan();
      final limited = studyPlan(maxSteps: 1);
      expect(full.steps.length, greaterThan(1));

      final l10n = await pumpStudyPlan(tester, () async => limited);

      expect(limited.steps, hasLength(1));
      expect(limited.skippedStepCount, full.steps.length - 1);
      expect(
        find.text(l10n.todayStudyPlanSkipped(limited.skippedStepCount)),
        findsOneWidget,
      );
      expect(find.byKey(todayStudyPlanStepKey(0)), findsOneWidget);
      expect(find.byKey(todayStudyPlanStepKey(1)), findsNothing);
    });

    testWidgets('no evidence shows the plan\'s own noData step',
        (tester) async {
      final plan = emptyStudyPlan();
      expect(plan.steps, hasLength(1));
      expect(plan.steps.single.kind, DailyPlanStepKind.noData);

      final l10n = await pumpStudyPlan(tester, () async => plan);

      expect(find.text(l10n.todayStudyPlanTitle), findsOneWidget);
      expect(find.byKey(todayStudyPlanStepKey(0)), findsOneWidget);
      // 数据层的话原样显示：页面不另外造一句空态把它盖掉。
      expect(find.text(plan.steps.single.titleZh), findsOneWidget);
      expect(find.text(plan.steps.single.detailZh), findsOneWidget);
      expect(find.byType(TodayActionCard), findsNothing);
    });

    testWidgets('a failed read says the error and offers a retry',
        (tester) async {
      var calls = 0;
      var failing = true;
      final l10n = await pumpPage(
        tester,
        overrides: [
          dailyStudyPlanProvider.overrideWith((ref) async {
            calls += 1;
            if (failing) {
              throw StateError('boom');
            }
            return studyPlan();
          }),
        ],
      );

      expect(find.byKey(todayStudyPlanErrorKey), findsOneWidget);
      expect(
        find.text(l10n.todayStudyPlanFailed('Bad state: boom')),
        findsOneWidget,
      );

      failing = false;
      await tester.tap(find.byKey(todayStudyPlanRetryKey));
      await tester.pumpAndSettle();

      expect(find.byKey(todayStudyPlanErrorKey), findsNothing);
      expect(
        find.text(l10n.todayStudyPlanTotal(studyPlan().totalMinutes)),
        findsOneWidget,
      );
      expect(calls, greaterThan(1));
    });

    testWidgets('the refresh button refreshes both providers', (tester) async {
      var studyLoads = 0;
      var oldLoads = 0;
      final l10n = await pumpPage(
        tester,
        overrides: [
          dailyStudyPlanProvider.overrideWith((ref) async {
            studyLoads += 1;
            return studyPlan();
          }),
          todayPlanProvider.overrideWith((ref) async {
            oldLoads += 1;
            return const TodayPlan(
              actions: [],
              considered: 0,
              horizonHours: 24,
              nowHours: 1000,
            );
          }),
        ],
      );

      final beforeStudy = studyLoads;
      final beforeOld = oldLoads;
      await tester.tap(find.byTooltip(l10n.commonRefresh));
      await tester.pumpAndSettle();

      // 两个区块各自取数：刷新必须两边都重读，不能只刷一个。
      expect(studyLoads, greaterThan(beforeStudy));
      expect(oldLoads, greaterThan(beforeOld));
    });

    testWidgets('the section shows a loading line until the plan arrives',
        (tester) async {
      final gate = Completer<DailyStudyPlan>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            dailyStudyPlanProvider.overrideWith((ref) => gate.future),
          ],
          child: const MaterialApp(
            locale: Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: TodayPlanPage(),
          ),
        ),
      );
      await tester.pump();

      final l10n =
          AppLocalizations.of(tester.element(find.byType(TodayPlanPage)));
      expect(find.text(l10n.todayStudyPlanLoading), findsOneWidget);

      gate.complete(studyPlan());
      await tester.pumpAndSettle();

      expect(find.text(l10n.todayStudyPlanLoading), findsNothing);
      expect(
        find.text(l10n.todayStudyPlanTotal(studyPlan().totalMinutes)),
        findsOneWidget,
      );
    });
  });
}

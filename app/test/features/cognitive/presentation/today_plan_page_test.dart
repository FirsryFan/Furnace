import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/domain/services/reasoning/chain_insights.dart';
import 'package:furnace/domain/services/reasoning/daily_plan_step_destination.dart';
import 'package:furnace/domain/services/reasoning/daily_study_plan.dart';
import 'package:furnace/domain/services/reasoning/learning_advice.dart';
import 'package:furnace/domain/services/reasoning/practice_recommendation.dart';
import 'package:furnace/domain/services/scheduling/today_plan.dart';
import 'package:furnace/features/anki/presentation/review_page.dart';
import 'package:furnace/features/cognitive/application/daily_study_plan_reader.dart';
import 'package:furnace/features/cognitive/application/today_plan_reader.dart';
import 'package:furnace/features/cognitive/presentation/today_plan_page.dart';
import 'package:furnace/features/questions/presentation/question_bank_page.dart';
import 'package:furnace/features/settings/presentation/capability_vocabulary_page.dart';
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
    List<NavigatorObserver> navigatorObservers = const <NavigatorObserver>[],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          ...overrides,
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          navigatorObservers: navigatorObservers,
          home: const TodayPlanPage(),
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

  group('navigation mapping', () {
    DailyPlanStep stepOf(
      DailyPlanStepKind kind, {
      List<String> questionIds = const <String>[],
      int? cardCount,
      String? actionType,
    }) =>
        DailyPlanStep(
          kind: kind,
          priority: 1,
          titleZh: '标题',
          detailZh: '理由',
          estimatedMinutes: 1,
          questionIds: questionIds,
          cardCount: cardCount,
          actionType: actionType,
        );

    test('only steps with a real target are navigable', () {
      // 练习步骤：没有题号就没有可练的对象，不能点。
      expect(
        destinationOf(stepOf(DailyPlanStepKind.practiceQuestions)).isNavigable,
        isFalse,
      );
      final practice = destinationOf(
        stepOf(
          DailyPlanStepKind.practiceQuestions,
          questionIds: ['q-2', 'q-1'],
        ),
      );
      expect(practice.isNavigable, isTrue);
      expect(practice.kind, DailyPlanDestinationKind.practiceQuestions);
      expect(practice.questionIds, ['q-2', 'q-1']);

      // 复习步骤：没有到期卡（null / 0）也没有地方可去。
      expect(
        destinationOf(stepOf(DailyPlanStepKind.reviewDueCards)).isNavigable,
        isFalse,
      );
      expect(
        destinationOf(stepOf(DailyPlanStepKind.reviewDueCards, cardCount: 0))
            .isNavigable,
        isFalse,
      );
      final review = destinationOf(
        stepOf(DailyPlanStepKind.reviewDueCards, cardCount: 3),
      );
      expect(review.isNavigable, isTrue);
      expect(review.kind, DailyPlanDestinationKind.ankiReview);

      final chains = destinationOf(
        stepOf(DailyPlanStepKind.collectChains, actionType: 'first_principles'),
      );
      expect(chains.isNavigable, isTrue);
      expect(chains.actionType, 'first_principles');
      expect(
        destinationOf(stepOf(DailyPlanStepKind.reviewVocabulary)).isNavigable,
        isTrue,
      );
      expect(
        destinationOf(stepOf(DailyPlanStepKind.keepGoing)).isNavigable,
        isFalse,
      );
      final noData = destinationOf(stepOf(DailyPlanStepKind.noData));
      expect(noData.kind, DailyPlanDestinationKind.none);
      expect(noData.isNavigable, isFalse);
    });

    test('every navigable kind gets its own label, dead ends get none',
        () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
      final labels = <DailyPlanDestinationKind, String>{
        DailyPlanDestinationKind.practiceQuestions:
            l10n.todayStudyPlanGoPractice,
        DailyPlanDestinationKind.ankiReview: l10n.todayStudyPlanGoReview,
        DailyPlanDestinationKind.collectChains: l10n.todayStudyPlanGoChains,
        DailyPlanDestinationKind.vocabulary: l10n.todayStudyPlanGoVocabulary,
      };
      for (final entry in labels.entries) {
        expect(todayStudyPlanGoLabel(l10n, entry.key), entry.value);
        expect(entry.value, isNotEmpty);
      }
      expect(labels.values.toSet(), hasLength(4));
      expect(
        todayStudyPlanGoLabel(l10n, DailyPlanDestinationKind.keepGoing),
        isEmpty,
      );
      expect(
        todayStudyPlanGoLabel(l10n, DailyPlanDestinationKind.none),
        isEmpty,
      );
    });

    test('the default mapping only points at pages that already exist', () {
      Widget pageFor(
        DailyPlanDestinationKind kind, {
        List<String> questionIds = const <String>[],
        int? cardCount,
        String? actionType,
      }) =>
          buildTodayStudyPlanDestinationPage(
            DailyPlanStepDestination(
              kind: kind,
              questionIds: questionIds,
              cardCount: cardCount,
              actionType: actionType,
            ),
          );

      // 题库还没有「按题号开练」的入口：练习/补链都退回题库页（已写进报告）。
      expect(
        pageFor(
          DailyPlanDestinationKind.practiceQuestions,
          questionIds: ['q-1'],
        ),
        isA<QuestionBankPage>(),
      );
      expect(
        pageFor(
          DailyPlanDestinationKind.collectChains,
          actionType: 'first_principles',
        ),
        isA<QuestionBankPage>(),
      );
      expect(
        pageFor(DailyPlanDestinationKind.ankiReview, cardCount: 2),
        isA<ReviewPage>(),
      );
      expect(
        pageFor(DailyPlanDestinationKind.vocabulary),
        isA<CapabilityVocabularyPage>(),
      );
      expect(pageFor(DailyPlanDestinationKind.keepGoing), isA<SizedBox>());
      expect(pageFor(DailyPlanDestinationKind.none), isA<SizedBox>());
    });
  });

  group('a step with a target is a button; the rest are static', () {
    DailyStudyPlan practicePlan() {
      final insights = ChainInsights.aggregate(
        chains: const [
          ChainInsightChain(
            chainId: 'c-9',
            questionId: 'q-1',
            steps: [
              ChainInsightStep(actionType: 'first_principles', stuckRisk: 0.9),
              ChainInsightStep(actionType: 'first_principles', stuckRisk: 0.9),
              ChainInsightStep(actionType: 'first_principles', stuckRisk: 0.9),
            ],
          ),
        ],
      );
      final advices = LearningAdvicePlan.build(insights: insights);
      final recommendations = PracticeRecommendationPlan.build(
        insights: insights,
        advicePlan: advices,
        candidates: const [PracticeQuestionCandidate(questionId: 'q-2')],
      );
      return DailyStudyPlan.build(
        insights: insights,
        advices: advices,
        recommendations: recommendations,
      );
    }

    Future<AppLocalizations> pumpNavigable(
      WidgetTester tester,
      DailyStudyPlan plan, {
      required _RecordingObserver observer,
      required List<DailyPlanStepDestination> opened,
    }) =>
        pumpPage(
          tester,
          navigatorObservers: [observer],
          overrides: [
            dailyStudyPlanProvider.overrideWith((ref) async => plan),
            // 真推复习页/词表页会带出 DB 与路径插件依赖；这里把目标页换成
            // 探针页，只验证「点了会推一条到领域层给的目标」。
            todayStudyPlanPageBuilderProvider.overrideWithValue(
              (DailyPlanStepDestination destination) {
                opened.add(destination);
                return const Scaffold(key: _probePageKey);
              },
            ),
          ],
        );

    Finder semanticsOf(int index) => find.ancestor(
          of: find.byKey(todayStudyPlanStepKey(index)),
          matching: find.byWidgetPredicate(
            (widget) => widget is Semantics && widget.properties.button == true,
          ),
        );

    testWidgets(
        'navigable steps show a chevron, a target line and button semantics',
        (tester) async {
      final plan = studyPlan();
      final observer = _RecordingObserver();
      final opened = <DailyPlanStepDestination>[];
      final l10n = await pumpNavigable(
        tester,
        plan,
        observer: observer,
        opened: opened,
      );

      expect(
        plan.steps.map((step) => step.kind),
        containsAll([
          DailyPlanStepKind.reviewDueCards,
          DailyPlanStepKind.reviewVocabulary,
        ]),
      );
      for (var index = 0; index < plan.steps.length; index++) {
        expect(
          find.descendant(
            of: find.byKey(todayStudyPlanStepKey(index)),
            matching: find.byIcon(Icons.chevron_right),
          ),
          findsOneWidget,
        );
        expect(semanticsOf(index), findsOneWidget);
      }
      expect(find.text(l10n.todayStudyPlanGoReview), findsOneWidget);
      expect(find.text(l10n.todayStudyPlanGoVocabulary), findsOneWidget);

      final semantics = tester.widget<Semantics>(semanticsOf(0));
      expect(
        semantics.properties.label,
        startsWith(l10n.todayStudyPlanGoReview),
      );
      expect(semantics.properties.label, contains(plan.steps[0].titleZh));
    });

    testWidgets('tapping the review step opens the review destination',
        (tester) async {
      final plan = studyPlan();
      final observer = _RecordingObserver();
      final opened = <DailyPlanStepDestination>[];
      await pumpNavigable(tester, plan, observer: observer, opened: opened);
      final routesBefore = observer.pushed.length;

      await tester.tap(find.byKey(todayStudyPlanStepKey(0)));
      await tester.pumpAndSettle();

      expect(opened, hasLength(1));
      expect(opened.single.kind, DailyPlanDestinationKind.ankiReview);
      expect(observer.pushed, hasLength(routesBefore + 1));
      expect(find.byKey(_probePageKey), findsOneWidget);
    });

    testWidgets('tapping the vocabulary step opens the vocabulary destination',
        (tester) async {
      final plan = studyPlan();
      final observer = _RecordingObserver();
      final opened = <DailyPlanStepDestination>[];
      await pumpNavigable(tester, plan, observer: observer, opened: opened);
      await tester.ensureVisible(find.byKey(todayStudyPlanStepKey(1)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(todayStudyPlanStepKey(1)));
      await tester.pumpAndSettle();

      expect(opened, hasLength(1));
      expect(opened.single.kind, DailyPlanDestinationKind.vocabulary);
      expect(find.byKey(_probePageKey), findsOneWidget);
    });

    testWidgets('a practice step carries the recommended question ids',
        (tester) async {
      final plan = practicePlan();
      expect(plan.steps, hasLength(1));
      expect(plan.steps.single.kind, DailyPlanStepKind.practiceQuestions);
      final observer = _RecordingObserver();
      final opened = <DailyPlanStepDestination>[];
      final l10n = await pumpNavigable(
        tester,
        plan,
        observer: observer,
        opened: opened,
      );

      expect(find.text(l10n.todayStudyPlanGoPractice), findsOneWidget);
      await tester.tap(find.byKey(todayStudyPlanStepKey(0)));
      await tester.pumpAndSettle();

      expect(opened, hasLength(1));
      expect(opened.single.kind, DailyPlanDestinationKind.practiceQuestions);
      expect(opened.single.questionIds, contains('q-2'));
    });

    testWidgets('a step without a target stays static and never navigates',
        (tester) async {
      final plan = emptyStudyPlan();
      final observer = _RecordingObserver();
      final opened = <DailyPlanStepDestination>[];
      final l10n = await pumpNavigable(
        tester,
        plan,
        observer: observer,
        opened: opened,
      );
      expect(plan.steps.single.kind, DailyPlanStepKind.noData);

      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(semanticsOf(0), findsNothing);
      for (final label in [
        l10n.todayStudyPlanGoPractice,
        l10n.todayStudyPlanGoReview,
        l10n.todayStudyPlanGoChains,
        l10n.todayStudyPlanGoVocabulary,
      ]) {
        expect(find.text(label), findsNothing);
      }

      final routesBefore = observer.pushed.length;
      await tester.tap(find.byKey(todayStudyPlanStepKey(0)));
      await tester.pumpAndSettle();

      expect(opened, isEmpty);
      expect(observer.pushed, hasLength(routesBefore));
      expect(find.byKey(_probePageKey), findsNothing);
    });
  });
}

/// 记录 Navigator 推了哪些路由（初始 home 也记一条）。
class _RecordingObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }
}

/// 测试用的「目标页」：只证明点进去的是 builder 给的那一页。
const Key _probePageKey = Key('today-study-plan-probe-page');

/// 学习洞察页「下一步练什么」区块的测试：把推荐行的展示口径钉住。
///
/// 关注四件事：
///  1. **理由不丢**：最多展示 3 条，其余折叠成「另有 N 条理由」；
///  2. **题号是稳定的**：行上的题号来自 `questions.serialNo`（TR-00001 式）；
///  3. **截断要如实说**：`skippedQuestionIds` 非空时显示「还有 N 道没显示」；
///  4. **降级不崩页**：provider 加载失败只降级一行，点击行能进详情页。
library;

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/reasoning/capability_action.dart';
import 'package:furnace/domain/services/reasoning/chain_insights.dart';
import 'package:furnace/domain/services/reasoning/learning_advice.dart';
import 'package:furnace/domain/services/reasoning/practice_recommendation.dart';
import 'package:furnace/features/ai/application/ai_providers.dart';
import 'package:furnace/features/questions/application/practice_recommendation_provider.dart';
import 'package:furnace/features/questions/application/question_media_providers.dart';
import 'package:furnace/features/questions/presentation/practice_recommendation_view.dart';
import 'package:furnace/features/questions/presentation/question_detail_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

import 'support/question_media_fakes.dart';

const int _ts = 1700000000000;

late AppLocalizations _zh;

/// 能力动作中文名：和页面一样走 [CapabilityAction.catalog]。
final Map<String, CapabilityAction> _actionCatalog = <String, CapabilityAction>{
  for (final action in CapabilityAction.catalog) action.key: action,
};

/// 一条链：3 步已知高危动作 + 1 步词表外动作（都指向 kp-1）。
ChainInsights _insights() {
  final steps = <ChainInsightStep>[
    for (var i = 1; i <= 3; i++)
      ChainInsightStep(
        actionType: 'first_principles',
        index: i,
        stuckRisk: 0.9,
        knowledgeHints: const <String>['kp-1'],
      ),
    const ChainInsightStep(
      actionType: 'made_up_move',
      index: 4,
      stuckRisk: 0.8,
      knowledgeHints: <String>['kp-1'],
    ),
  ];
  return ChainInsights.aggregate(
    chains: <ChainInsightChain>[
      ChainInsightChain(
        chainId: 'c-1',
        questionId: 'q-1',
        steps: steps,
      ),
    ],
  );
}

List<PracticeQuestionCandidate> _candidates() => <PracticeQuestionCandidate>[
      const PracticeQuestionCandidate(
        questionId: 'q-1',
        serialNo: 1,
        actionTypes: <String>['first_principles'],
        knowledgePointIds: <String>['kp-1'],
        hasAnswer: true,
        hasSolution: true,
        difficulty: 3,
      ),
      const PracticeQuestionCandidate(
        questionId: 'q-2',
        serialNo: 2,
        actionTypes: <String>['made_up_move'],
        hasAnswer: true,
        hasSolution: false,
      ),
      const PracticeQuestionCandidate(
        questionId: 'q-3',
        serialNo: 3,
        actionTypes: <String>['first_principles', 'made_up_move'],
        knowledgePointIds: <String>['kp-1'],
        hasAnswer: true,
        hasSolution: false,
        difficulty: 5,
      ),
    ];

/// 推荐计划（只能用 [PracticeRecommendationPlan.build] 构造）。
PracticeRecommendationPlan _plan({
  double? targetDifficulty = 3,
  int maxQuestions = 10,
  List<PracticeQuestionCandidate>? candidates,
}) =>
    PracticeRecommendationPlan.build(
      insights: _insights(),
      advicePlan: LearningAdvicePlan.build(insights: _insights()),
      candidates: candidates ?? _candidates(),
      maxQuestions: maxQuestions,
      preferredActionTypes: const <String>{'first_principles'},
      preferredKnowledgePointIds: const <String>{'kp-1'},
      targetDifficulty: targetDifficulty,
    );

Future<void> _seedQuestion(AppDatabase db, String id, int serialNo) =>
    db.into(db.questions).insert(
          QuestionsCompanion.insert(
            id: id,
            stem: '题干 $id',
            createdAt: _ts,
            updatedAt: _ts,
            serialNo: Value(serialNo),
          ),
        );

/// 等某个 finder 出现（题号徽章、卡片要等 provider 的 future 回来）。
Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  int rounds = 40,
}) async {
  for (var i = 0; i < rounds; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _pumpSection(
  WidgetTester tester, {
  required AppDatabase db,
  required Future<PracticeRecommendationPlan> Function() load,
}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
        modelAdapterProvider.overrideWithValue(null),
        questionMediaStoreProvider
            .overrideWithValue(FakeQuestionMediaStore(database: db)),
        practiceRecommendationProvider.overrideWith((ref) => load()),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: PracticeRecommendationSection(
              actionCatalog: _actionCatalog,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(() async {
    _zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('纯逻辑', () {
    test('9 种理由都映射成非空且互不相同的文案', () {
      final labels = <String>{
        for (final reason in PracticeRecommendationReason.values)
          practiceRecommendationReasonLabel(_zh, reason),
      };
      expect(labels, hasLength(9));
      expect(labels.any((label) => label.trim().isEmpty), isFalse);
    });

    test('理由最多展示 3 条，其余计入折叠条数', () {
      final plan = _plan();
      final folded = plan.recommendations.firstWhere(
        (recommendation) => recommendation.questionId == 'q-3',
      );
      expect(folded.reasons, hasLength(5));
      expect(
        practiceRecommendationVisibleReasons(folded.reasons),
        hasLength(3),
      );
      expect(
        practiceRecommendationHiddenReasonCount(folded.reasons),
        2,
      );
      expect(
        practiceRecommendationVisibleReasons(folded.reasons, limit: 0),
        isEmpty,
      );
      expect(
        practiceRecommendationHiddenReasonCount(folded.reasons, limit: 0),
        5,
      );
    });

    test('命中动作按词表翻中文，词表外动作显示 key', () {
      const recommendation = PracticeRecommendation(
        questionId: 'q-1',
        score: 1,
        rank: 1,
        reasons: <PracticeRecommendationReason>[],
        matchedActionTypes: <String>['first_principles', 'made_up_move'],
        matchedKnowledgePointIds: <String>[],
      );
      expect(
        practiceRecommendationActionLabels(recommendation, _actionCatalog),
        '从定义出发、made_up_move',
      );
    });

    test('skipped 名单非空才算「还有 N 道没显示」', () {
      expect(practiceRecommendationShowsSkipped(_plan()), isFalse);
      final truncated = _plan(maxQuestions: 2);
      expect(practiceRecommendationShowsSkipped(truncated), isTrue);
      expect(truncated.skippedQuestionIds, hasLength(1));
    });
  });

  group('widget', () {
    testWidgets('就绪时渲染名次、题号、理由与命中动作', (tester) async {
      await _seedQuestion(db, 'q-1', 1);
      await _seedQuestion(db, 'q-2', 2);
      await _seedQuestion(db, 'q-3', 3);
      await _pumpSection(tester, db: db, load: () async => _plan());
      await _waitFor(
        tester,
        find.byKey(practiceRecommendationRowKey('q-1')),
      );
      expect(find.byKey(practiceRecommendationSectionKey), findsOneWidget);
      expect(find.byKey(practiceRecommendationRowKey('q-1')), findsOneWidget);
      expect(find.byKey(practiceRecommendationRowKey('q-2')), findsOneWidget);
      expect(find.byKey(practiceRecommendationRowKey('q-3')), findsOneWidget);
      await _waitFor(tester, find.text('TR-00001'));
      expect(find.text('TR-00001'), findsOneWidget);
      expect(
        find.textContaining(_zh.practiceRecommendationRank(1)),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          _zh.practiceRecommendationReasonMatchedHighRiskKnowledgePoint,
        ),
        findsWidgets,
      );
      expect(
        find.textContaining(
          _zh.practiceRecommendationActions('从定义出发'),
        ),
        findsWidgets,
      );
    });

    testWidgets('理由超过 3 条只显示前 3 条并折叠其余', (tester) async {
      await _seedQuestion(db, 'q-1', 1);
      await _seedQuestion(db, 'q-2', 2);
      await _seedQuestion(db, 'q-3', 3);
      await _pumpSection(tester, db: db, load: () async => _plan());
      final foldedRow = find.byKey(practiceRecommendationRowKey('q-3'));
      await _waitFor(tester, foldedRow);
      expect(
        find.descendant(
          of: foldedRow,
          matching: find.textContaining(
            _zh.practiceRecommendationMoreReasons(2),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: foldedRow,
          matching: find.textContaining(
            _zh.practiceRecommendationReasonMissingSolution,
          ),
        ),
        findsNothing,
      );
    });

    testWidgets('空推荐显示一句空文案', (tester) async {
      await _pumpSection(
        tester,
        db: db,
        load: () async =>
            _plan(candidates: const <PracticeQuestionCandidate>[]),
      );
      await _waitFor(tester, find.byKey(practiceRecommendationEmptyKey));
      expect(
        find.text(_zh.practiceRecommendationEmpty),
        findsOneWidget,
      );
      expect(find.byKey(practiceRecommendationSectionKey), findsOneWidget);
    });

    testWidgets('provider 报错只降级一行，不显示区块卡片', (tester) async {
      await _pumpSection(
        tester,
        db: db,
        load: () async => throw StateError('boom'),
      );
      await _waitFor(tester, find.byKey(practiceRecommendationErrorKey));
      expect(
        find.text(_zh.practiceRecommendationFailed),
        findsOneWidget,
      );
      expect(find.byKey(practiceRecommendationSectionKey), findsNothing);
    });

    testWidgets('被上限截断时显示还有 N 道没显示', (tester) async {
      await _seedQuestion(db, 'q-1', 1);
      await _pumpSection(
        tester,
        db: db,
        load: () async => _plan(maxQuestions: 1),
      );
      await _waitFor(tester, find.byKey(practiceRecommendationSkippedKey));
      expect(
        find.text(_zh.practiceRecommendationSkipped(2)),
        findsOneWidget,
      );
    });

    testWidgets('加载中安静不占高，完成后出现区块', (tester) async {
      final gate = Completer<PracticeRecommendationPlan>();
      await _pumpSection(tester, db: db, load: () => gate.future);
      expect(find.byKey(practiceRecommendationSectionKey), findsNothing);
      expect(find.byKey(practiceRecommendationErrorKey), findsNothing);
      gate.complete(_plan());
      await _waitFor(tester, find.byKey(practiceRecommendationSectionKey));
      expect(find.byKey(practiceRecommendationSectionKey), findsOneWidget);
    });

    testWidgets('点击推荐行进入题目详情页', (tester) async {
      await _seedQuestion(db, 'q-1', 1);
      await _pumpSection(tester, db: db, load: () async => _plan());
      final row = find.byKey(practiceRecommendationRowKey('q-1'));
      await _waitFor(tester, row);
      await tester.tap(row);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(QuestionDetailPage), findsOneWidget);
    });
  });
}

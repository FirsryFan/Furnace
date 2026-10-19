import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/data/repositories/settings_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/domain/services/reasoning/daily_study_plan.dart';
import 'package:furnace/features/cognitive/application/daily_study_plan_reader.dart';

/// 今日学习计划**接线**（`daily_study_plan_reader.dart`）的验收点：
///
///  * 到期卡片张数由调用方注入，本层不读时钟、不自己判断"什么叫到期"；
///  * 洞察 / 画像 / 建议 / 配题推荐四层读数真的被拼进 `DailyStudyPlan.build`；
///  * 空库如实给 noData（不虚构题数 / 知识点），不抛异常；
///  * 每日预算与步骤上限这两个参数真的透传（截断、跳过都如实计数）；
///  * 词表 overlay 里的自定义动作被认出来（不进 unknownActions）。
void main() {
  late AppDatabase db;
  late QuestionRepository questions;
  late TagRepository tags;
  late AnkiRepository anki;
  late SettingsRepository settings;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    questions = QuestionRepository(db);
    tags = TagRepository(db);
    anki = AnkiRepository(db);
    settings = SettingsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<String> seedQuestion({String stem = '已知函数求单调区间'}) async {
    final ingested = await questions.ingest(
      QuestionDraft(
        stem: stem,
        answer: 'B',
        solution: '先求导再判号',
        subjectKey: '数学',
        sourceLevel: 'gaokao',
      ),
    );
    return ingested.question.id;
  }

  Future<String> seedKnowledgePoint(String title) async =>
      (await anki.createKnowledgePoint(title: title, content: '')).id;

  /// 题目覆盖某个知识点的方式：两者挂**同一个**标签。
  Future<void> linkKnowledgePoint({
    required String pointId,
    required String questionId,
  }) async {
    final tagId = (await tags.createTag(name: '标签-$pointId')).id;
    await tags.addTagToObject(
      tagId: tagId,
      objectType: 'knowledge_point',
      objectId: pointId,
    );
    await tags.addTagToObject(
      tagId: tagId,
      objectType: 'question',
      objectId: questionId,
    );
  }

  Future<void> seedChain({
    required String chainId,
    required String questionId,
    int createdAt = 1,
    List<({String action, double? risk, List<String> hints})> steps = const [],
  }) async {
    await db.into(db.reasoningChains).insert(
          ReasoningChainsCompanion.insert(
            id: chainId,
            questionId: questionId,
            createdAt: createdAt,
            summary: const Value(''),
            stepCount: Value(steps.length),
          ),
        );
    for (var i = 0; i < steps.length; i++) {
      await db.into(db.reasoningSteps).insert(
            ReasoningStepsCompanion.insert(
              id: '$chainId-step-$i',
              chainId: chainId,
              idx: i,
              goal: '第 $i 步',
              actionType: Value(steps[i].action),
              stuckRisk: Value(steps[i].risk),
              knowledgeHints: Value(
                '[${steps[i].hints.map((hint) => '"$hint"').join(',')}]',
              ),
              createdAt: createdAt,
            ),
          );
    }
  }

  Future<void> writeOverlay(List<Map<String, Object?>> customActions) async {
    await settings.ensureSettings();
    await settings.updateCapabilityActionOverlayJson(
      jsonEncode(<String, Object?>{
        'version': 1,
        'customActions': customActions,
      }),
    );
  }

  ProviderContainer container() {
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('空库 / 到期卡片', () {
    test('空库没有到期卡片：如实给一条 noData，0 分钟', () async {
      final plan = await readDailyStudyPlan(database: db, dueCardCount: 0);

      expect(plan.steps, hasLength(1));
      final step = plan.steps.single;
      expect(step.kind, DailyPlanStepKind.noData);
      expect(step.estimatedMinutes, 0);
      expect(step.cardCount, isNull);
      expect(plan.totalMinutes, 0);
      expect(plan.skippedStepCount, 0);
      expect(plan.focusKnowledgePointIds, isEmpty);
      expect(plan.isEmpty, isFalse);
    });

    test('只有到期卡片：ceil(5/2)=3 分钟，卡片张数如实', () async {
      final plan = await readDailyStudyPlan(database: db, dueCardCount: 5);

      final step = plan.steps.single;
      expect(step.kind, DailyPlanStepKind.reviewDueCards);
      expect(step.cardCount, 5);
      expect(step.estimatedMinutes, 3);
      expect(plan.totalMinutes, 3);
    });

    test('到期卡片很多时按每日预算截断（100 张 → 30 分钟）', () async {
      final plan = await readDailyStudyPlan(database: db, dueCardCount: 100);

      final step = plan.steps.single;
      expect(step.kind, DailyPlanStepKind.reviewDueCards);
      expect(step.estimatedMinutes, DailyStudyPlan.defaultDailyMinutes);
      expect(plan.totalMinutes, DailyStudyPlan.defaultDailyMinutes);
    });

    test('dailyMinutes 参数真的透传：2 分钟预算 → 只排 2 分钟', () async {
      final plan = await readDailyStudyPlan(
        database: db,
        dueCardCount: 7,
        dailyMinutes: 2,
      );

      expect(plan.steps.single.estimatedMinutes, 2);
      expect(plan.totalMinutes, 2);
    });
  });

  group('洞察 / 画像 / 建议 / 推荐四层接线', () {
    test('种子链的三步高危动作：读数、画像、练习步骤都对上', () async {
      final questionId = await seedQuestion();
      final pointId = await seedKnowledgePoint('函数单调性');
      await linkKnowledgePoint(pointId: pointId, questionId: questionId);
      await seedChain(
        chainId: 'chain-1',
        questionId: questionId,
        steps: const [
          (action: 'case_split', risk: 0.8, hints: <String>[]),
          (action: 'case_split', risk: 0.8, hints: <String>[]),
          (action: 'case_split', risk: 0.8, hints: <String>[]),
        ],
      );

      final insights = await readDailyStudyPlanInsights(db);
      expect(insights.stepCount, 3);
      expect(insights.unknownActions, isEmpty);
      expect(insights.actions.single.actionType, 'case_split');
      expect(insights.actions.single.highRiskStepCount, 3);
      expect(insights.highRiskByKnowledgePoint, isEmpty);

      final profile = await readDailyStudyPlanProfile(db);
      expect(profile, hasLength(1));
      expect(profile.single.actionType, 'case_split');
      expect(profile.single.known, isTrue);
      expect(profile.single.riskyStepCount, 3);
      expect(profile.single.avgStuckRisk, closeTo(0.8, 1e-9));

      final plan = await readDailyStudyPlan(database: db, dueCardCount: 3);
      expect(
        plan.steps.map((step) => step.kind),
        [DailyPlanStepKind.reviewDueCards, DailyPlanStepKind.practiceQuestions],
      );
      final practice = plan.steps.last;
      expect(practice.questionIds, [questionId]);
      expect(practice.actionType, 'case_split');
      expect(practice.estimatedMinutes, 2);
      expect(plan.totalMinutes, 4);
      expect(plan.skippedStepCount, 0);
    });

    test('链步骤的 knowledgeHints 进了交叉读数，练习步骤带上知识点', () async {
      final questionId = await seedQuestion();
      final pointId = await seedKnowledgePoint('导数与单调性');
      await linkKnowledgePoint(pointId: pointId, questionId: questionId);
      await seedChain(
        chainId: 'chain-2',
        questionId: questionId,
        steps: [
          (action: 'case_split', risk: 0.9, hints: <String>[pointId]),
          (action: 'case_split', risk: 0.9, hints: <String>[pointId]),
          (action: 'case_split', risk: 0.9, hints: <String>[pointId]),
        ],
      );

      final insights = await readDailyStudyPlanInsights(db);
      expect(insights.highRiskByKnowledgePoint, hasLength(1));
      expect(insights.highRiskByKnowledgePoint.single.key, pointId);
      expect(insights.highRiskByKnowledgePoint.single.highRiskStepCount, 3);

      final plan = await readDailyStudyPlan(database: db, dueCardCount: 0);
      final practice = plan.steps.single;
      expect(practice.kind, DailyPlanStepKind.practiceQuestions);
      expect(practice.knowledgePointIds, [pointId]);
      expect(practice.questionIds, [questionId]);
      expect(plan.focusKnowledgePointIds, [pointId]);
    });

    test('题库有题但没有链：补链建议进计划，不虚构练习重点', () async {
      await seedQuestion();

      final insights = await readDailyStudyPlanInsights(db);
      expect(insights.isEmpty, isTrue);

      final plan = await readDailyStudyPlan(database: db, dueCardCount: 0);
      final collect = plan.steps
          .where((step) => step.kind == DailyPlanStepKind.collectChains)
          .toList();
      expect(collect, hasLength(1));
      expect(collect.single.estimatedMinutes, 5);
      expect(plan.focusKnowledgePointIds, isEmpty);
    });

    test('maxSteps 参数真的透传：只留一步，另一条如实计入跳过', () async {
      final questionId = await seedQuestion();
      final pointId = await seedKnowledgePoint('函数单调性');
      await linkKnowledgePoint(pointId: pointId, questionId: questionId);
      await seedChain(
        chainId: 'chain-3',
        questionId: questionId,
        steps: const [
          (action: 'case_split', risk: 0.8, hints: <String>[]),
          (action: 'case_split', risk: 0.8, hints: <String>[]),
          (action: 'case_split', risk: 0.8, hints: <String>[]),
        ],
      );

      final plan = await readDailyStudyPlan(
        database: db,
        dueCardCount: 50,
        maxSteps: 1,
      );

      expect(plan.steps, hasLength(1));
      expect(plan.steps.single.kind, DailyPlanStepKind.reviewDueCards);
      expect(plan.steps.single.estimatedMinutes, 25);
      expect(plan.skippedStepCount, 1);
    });
  });

  group('词表 overlay', () {
    test('overlay 自定义动作被认出来：不进 unknownActions，不出补词表步骤', () async {
      await writeOverlay([
        {
          'key': 'my_move',
          'labelZh': '我的动作',
          'subjectHints': <String>['数学'],
        },
      ]);
      final questionId = await seedQuestion();
      await seedChain(
        chainId: 'chain-custom',
        questionId: questionId,
        steps: const [
          (action: 'my_move', risk: 0.8, hints: <String>[]),
          (action: 'my_move', risk: 0.8, hints: <String>[]),
          (action: 'my_move', risk: 0.8, hints: <String>[]),
        ],
      );

      final insights = await readDailyStudyPlanInsights(db);
      expect(insights.unknownActions, isEmpty);
      expect(insights.customActions.single.actionType, 'my_move');
      expect(insights.customActions.single.known, isTrue);
      expect(insights.customActions.single.label, '我的动作');

      final plan = await readDailyStudyPlan(database: db, dueCardCount: 0);
      expect(
        plan.steps.map((step) => step.kind),
        isNot(contains(DailyPlanStepKind.reviewVocabulary)),
      );
      expect(plan.steps.single.actionType, 'my_move');
    });

    test('词表外的动作：单独一条补词表步骤，动作名原样写出来', () async {
      final questionId = await seedQuestion();
      await seedChain(
        chainId: 'chain-unknown',
        questionId: questionId,
        steps: const [
          (action: 'mystery_move', risk: 0.9, hints: <String>[]),
        ],
      );

      final insights = await readDailyStudyPlanInsights(db);
      expect(insights.unknownActions, hasLength(1));
      expect(insights.unknownActions.single.actionType, 'mystery_move');

      final plan = await readDailyStudyPlan(database: db, dueCardCount: 0);
      final vocabulary = plan.steps
          .where((step) => step.kind == DailyPlanStepKind.reviewVocabulary)
          .toList();
      expect(vocabulary, hasLength(1));
      expect(vocabulary.single.estimatedMinutes, 3);
      expect(vocabulary.single.detailZh, contains('mystery_move'));
      expect(vocabulary.single.detailZh, contains('词表还不认识 1 个动作'));
    });
  });

  group('provider', () {
    test('空库：provider 给出 noData 计划，不抛异常', () async {
      final plan = await container().read(dailyStudyPlanProvider.future);

      expect(plan.steps, hasLength(1));
      expect(plan.steps.single.kind, DailyPlanStepKind.noData);
      expect(plan.totalMinutes, 0);
    });
  });
}

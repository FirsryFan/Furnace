import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/domain/services/reasoning/capability_action_overlay.dart';
import 'package:furnace/domain/services/reasoning/learning_advice.dart';
import 'package:furnace/features/questions/application/capability_vocabulary_store.dart';
import 'package:furnace/features/questions/application/learning_advice_provider.dart';

/// 学习建议接线（`learning_advice_provider.dart`）的验收点：
///
///  * 题库题数是一次真实 COUNT，跟库变化走；
///  * 三个输入真的被拼进 `LearningAdvicePlan.build`：有题没链说收链、
///    高风险动作说练、词表外动作说补词表、只有画像（孤立步骤）也不丢；
///  * 词表 overlay 生效后，自定义动作能进练习建议（known 由当前词表判定）；
///  * 空库不虚构数字。
void main() {
  late AppDatabase db;
  late QuestionRepository questions;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    questions = QuestionRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  ProviderContainer containerWith({CapabilityActionOverlay? overlay}) {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        if (overlay != null)
          capabilityActionOverlayProvider.overrideWith((ref) async => overlay),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<String> seedQuestion(String stem) async {
    final ingested = await questions.ingest(
      QuestionDraft(stem: stem, subjectKey: '数学'),
    );
    return ingested.question.id;
  }

  /// 给一道题落一条链；action/risk 序列与 paper_plan_provider_test 同款夹具。
  Future<void> seedChain({
    required String chainId,
    required String questionId,
    required List<({String action, double? risk})> steps,
  }) async {
    await db.into(db.reasoningChains).insert(
          ReasoningChainsCompanion.insert(
            id: chainId,
            questionId: questionId,
            createdAt: 1,
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
              createdAt: 1,
            ),
          );
    }
  }

  /// 孤立步骤：链不存在，只能进能力动作画像（allReasoningSteps），不进洞察。
  Future<void> seedOrphanStep({
    required String id,
    required String action,
    required double risk,
  }) async {
    await db.into(db.reasoningSteps).insert(
          ReasoningStepsCompanion.insert(
            id: id,
            chainId: 'missing-chain',
            idx: 0,
            goal: '孤立步骤',
            actionType: Value(action),
            stuckRisk: Value(risk),
            createdAt: 1,
          ),
        );
  }

  group('题库题数', () {
    test('空库是 0', () async {
      final container = containerWith();
      expect(await container.read(questionCorpusCountProvider.future), 0);
    });

    test('收题后跟着变', () async {
      final container = containerWith();
      await seedQuestion('题一');
      await seedQuestion('题二');
      expect(await container.read(questionCorpusCountProvider.future), 2);

      await seedQuestion('题三');
      container.invalidate(questionCorpusCountProvider);
      expect(await container.read(questionCorpusCountProvider.future), 3);
    });
  });

  group('接线', () {
    test('空库给 noData，不虚构题数', () async {
      final container = containerWith();
      final plan = await container.read(learningAdviceProvider.future);
      expect(plan.length, 1);
      final advice = plan.advices.single;
      expect(advice.kind, LearningAdviceKind.noData);
      expect(advice.priority, 500);
      expect(advice.titleZh, '还没有学习数据');
      expect(advice.detailZh, contains('题库里也还没有题目'));
      expect(advice.toJson()['kind'], 'noData');
      expect(plan.toJson()['advice_count'], 1);
    });

    test('有题没链提醒去收链', () async {
      await seedQuestion('题一');
      await seedQuestion('题二');
      final container = containerWith();
      final plan = await container.read(learningAdviceProvider.future);
      expect(plan.length, 1);
      final advice = plan.advices.single;
      expect(advice.kind, LearningAdviceKind.collectChains);
      expect(advice.priority, 200);
      expect(advice.questionCount, 2);
      expect(advice.detailZh, contains('题库里有 2 道题'));
      expect(advice.detailZh, contains('但当前还没有任何解题链'));
    });

    test('部分题有链时，缺口按题数算', () async {
      final first = await seedQuestion('题一');
      await seedQuestion('题二');
      await seedChain(chainId: 'c1', questionId: first, steps: const [
        (action: 'first_principles', risk: 0.8),
      ]);
      final container = containerWith();
      final plan = await container.read(learningAdviceProvider.future);
      expect(plan.length, 1);
      final advice = plan.advices.single;
      expect(advice.kind, LearningAdviceKind.collectChains);
      expect(advice.questionCount, 2);
      expect(advice.detailZh, contains('当前洞察只覆盖 1 道题'));
      expect(advice.detailZh, contains('还有 1 道题没有解题链'));
    });

    test('已知动作 3 步高风险给练习建议，题数来自洞察', () async {
      final id = await seedQuestion('题一');
      await seedChain(chainId: 'c1', questionId: id, steps: const [
        (action: 'first_principles', risk: 0.8),
        (action: 'first_principles', risk: 0.9),
        (action: 'first_principles', risk: 0.7),
      ]);
      final container = containerWith();
      final plan = await container.read(learningAdviceProvider.future);
      expect(plan.length, 1);
      final advice = plan.advices.single;
      expect(advice.kind, LearningAdviceKind.practiceAction);
      expect(advice.priority, 100);
      expect(advice.actionType, 'first_principles');
      expect(advice.actionLabelZh, '从定义出发');
      expect(advice.questionCount, 1);
      expect(advice.stepCount, 3);
      expect(advice.highRiskStepCount, 3);
    });

    test('两步高风险不够阈值，返回继续练', () async {
      final id = await seedQuestion('题一');
      await seedChain(chainId: 'c1', questionId: id, steps: const [
        (action: 'first_principles', risk: 0.8),
        (action: 'first_principles', risk: 0.9),
      ]);
      final container = containerWith();
      final plan = await container.read(learningAdviceProvider.future);
      expect(plan.length, 1);
      expect(plan.advices.single.kind, LearningAdviceKind.keepGoing);
      expect(plan.advices.single.priority, 400);
    });

    test('词表外动作提醒补词表，不吞', () async {
      final id = await seedQuestion('题一');
      await seedChain(chainId: 'c1', questionId: id, steps: const [
        (action: 'made_up_move', risk: 0.9),
      ]);
      final container = containerWith();
      final plan = await container.read(learningAdviceProvider.future);
      expect(plan.length, 1);
      final advice = plan.advices.single;
      expect(advice.kind, LearningAdviceKind.reviewVocabulary);
      expect(advice.priority, 300);
      expect(advice.stepCount, 1);
      expect(advice.detailZh, contains('made_up_move'));
    });

    test('overlay 自定义动作被当前词表认识后进练习建议', () async {
      final id = await seedQuestion('题一');
      await seedChain(chainId: 'c1', questionId: id, steps: const [
        (action: 'draw_force_diagram', risk: 0.8),
        (action: 'draw_force_diagram', risk: 0.8),
        (action: 'draw_force_diagram', risk: 0.8),
      ]);
      final container = containerWith(
        overlay: const CapabilityActionOverlay(
          customActions: [
            CustomCapabilityAction(key: 'draw_force_diagram', labelZh: '画受力图'),
          ],
        ),
      );
      final plan = await container.read(learningAdviceProvider.future);
      expect(plan.length, 1);
      final advice = plan.advices.single;
      expect(advice.kind, LearningAdviceKind.practiceAction);
      expect(advice.actionType, 'draw_force_diagram');
      expect(advice.actionLabelZh, '画受力图');
    });

    test('只有能力动作画像（孤立步骤）也能给练习建议，题数不虚构', () async {
      await seedQuestion('题一');
      await seedQuestion('题二');
      await seedOrphanStep(id: 's1', action: 'first_principles', risk: 0.8);
      await seedOrphanStep(id: 's2', action: 'first_principles', risk: 0.9);
      await seedOrphanStep(id: 's3', action: 'first_principles', risk: 0.7);
      final container = containerWith();
      final plan = await container.read(learningAdviceProvider.future);
      expect(plan.length, 2);
      final practice = plan.advices[0];
      expect(practice.kind, LearningAdviceKind.practiceAction);
      expect(practice.actionType, 'first_principles');
      expect(practice.questionCount, isNull);
      expect(practice.stepCount, 3);
      expect(practice.highRiskStepCount, 3);
      final collect = plan.advices[1];
      expect(collect.kind, LearningAdviceKind.collectChains);
      expect(collect.questionCount, 2);
    });
  });
}

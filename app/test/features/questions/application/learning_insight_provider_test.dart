import 'dart:convert';

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
import 'package:furnace/features/questions/application/learning_insight_provider.dart';

/// 学习洞察页 provider（`learning_insight_provider.dart`）的验收点：
///
///  * 洞察 / 建议 / 词表 / 知识点中文名四份输入真被拼进同一份快照；
///  * 动作分布与卡点行保留洞察层的确定性顺序，风险读数缺失不插补 0；
///  * 未知动作、自定义动作按当前词表判定；词表读失败退回内置词表并标记；
///  * 知识点标题读不到时回退 id，不编造；
///  * 空库 / 无链 / 孤立步骤不虚构活动。
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

  ProviderContainer containerWith({
    CapabilityActionOverlay? overlay,
    bool throwOnOverlay = false,
  }) {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        if (throwOnOverlay)
          capabilityActionOverlayProvider.overrideWith(
            (ref) async => throw StateError('词表坏了'),
          )
        else if (overlay != null)
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

  Future<void> seedChain({
    required String chainId,
    required String questionId,
    required List<_StepSeed> steps,
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
      final step = steps[i];
      await db.into(db.reasoningSteps).insert(
            ReasoningStepsCompanion.insert(
              id: '$chainId-step-$i',
              chainId: chainId,
              idx: i,
              goal: '第 $i 步',
              actionType: Value(step.action),
              stuckRisk: Value(step.risk),
              knowledgeHints: Value(jsonEncode(step.hints)),
              createdAt: 1,
            ),
          );
    }
  }

  Future<void> seedKnowledgePoint(String id, String title) async {
    await db.into(db.knowledgePoints).insert(
          KnowledgePointsCompanion.insert(
            id: id,
            title: title,
            content: '',
            createdAt: 1,
            updatedAt: 1,
          ),
        );
  }

  group('空库与无活动', () {
    test('空库：没有任何活动，只有一条 noData 建议', () async {
      final container = containerWith();
      final data = await container.read(learningInsightDataProvider.future);

      expect(data.hasActivity, isFalse);
      expect(data.isEmpty, isFalse);
      expect(data.actionRows, isEmpty);
      expect(data.unknownRows, isEmpty);
      expect(data.stuckRows, isEmpty);
      expect(data.actionKnowledgeRows, isEmpty);
      expect(data.neverUsedActions, isEmpty);
      expect(data.knowledgePointTitles, isEmpty);
      expect(data.vocabOverlayFallback, isFalse);
      expect(data.adviceCards, hasLength(1));
      expect(data.adviceCards.single.kind, LearningAdviceKind.noData);
    });

    test('有题没链：不建议练动作，建议先收链', () async {
      await seedQuestion('题一');
      await seedQuestion('题二');
      final container = containerWith();
      final data = await container.read(learningInsightDataProvider.future);

      expect(data.hasActivity, isFalse);
      expect(data.isEmpty, isFalse);
      expect(data.actionRows, isEmpty);
      expect(data.adviceCards.first.kind, LearningAdviceKind.collectChains);
      expect(data.adviceCards.first.questionCount, 2);
    });

    test('孤立步骤只进能力画像，不算洞察活动', () async {
      await db.into(db.reasoningSteps).insert(
            ReasoningStepsCompanion.insert(
              id: 'orphan-1',
              chainId: 'missing-chain',
              idx: 0,
              goal: '孤立步骤',
              actionType: const Value('first_principles'),
              stuckRisk: const Value(0.9),
              createdAt: 1,
            ),
          );
      await seedQuestion('孤步题');
      final container = containerWith();
      final data = await container.read(learningInsightDataProvider.future);

      expect(data.hasActivity, isFalse);
      expect(data.actionRows, isEmpty);
      expect(data.adviceCards.first.kind, LearningAdviceKind.collectChains);
    });
  });

  group('动作分布与建议', () {
    test('高风险动作进练习建议，平均风险按真实读数', () async {
      final qid = await seedQuestion('题一');
      await seedChain(
        chainId: 'c1',
        questionId: qid,
        steps: const [
          _StepSeed('first_principles', risk: 0.8),
          _StepSeed('first_principles', risk: 0.9),
          _StepSeed('first_principles', risk: 0.7)
        ],
      );
      final container = containerWith();
      final data = await container.read(learningInsightDataProvider.future);

      expect(data.hasActivity, isTrue);
      final row = data.actionRows.single;
      expect(row.actionType, 'first_principles');
      expect(row.labelZh, '从定义出发');
      expect(row.known, isTrue);
      expect(row.custom, isFalse);
      expect(row.stepCount, 3);
      expect(row.questionCount, 1);
      expect(row.highRiskStepCount, 3);
      expect(row.averageStuckRisk, closeTo(0.8, 1e-9));
      expect(row.hasRiskReading, isTrue);

      final advice = data.adviceCards.first;
      expect(advice.kind, LearningAdviceKind.practiceAction);
      expect(advice.actionLabelZh, '从定义出发');
      expect(advice.questionCount, 1);
      expect(advice.stepCount, 3);
      expect(advice.highRiskStepCount, 3);
    });

    test('无风险读数的动作不插补 0', () async {
      final qid = await seedQuestion('题一');
      await seedChain(
        chainId: 'c1',
        questionId: qid,
        steps: const [
          _StepSeed('analogy_transfer'),
          _StepSeed('analogy_transfer')
        ],
      );
      final container = containerWith();
      final data = await container.read(learningInsightDataProvider.future);

      final row = data.actionRows.single;
      expect(row.averageStuckRisk, isNull);
      expect(row.hasRiskReading, isFalse);
      expect(row.highRiskStepCount, 0);
    });

    test('动作顺序沿用洞察层：步数多的在前', () async {
      final qid = await seedQuestion('题一');
      await seedChain(
        chainId: 'c1',
        questionId: qid,
        steps: const [
          _StepSeed('first_principles'),
          _StepSeed('analogy_transfer'),
          _StepSeed('first_principles')
        ],
      );
      final container = containerWith();
      final data = await container.read(learningInsightDataProvider.future);

      expect(data.actionRows.map((row) => row.actionType).toList(),
          ['first_principles', 'analogy_transfer']);
    });

    test('未知动作单列并建议补词表', () async {
      final qid = await seedQuestion('题一');
      await seedChain(
        chainId: 'c1',
        questionId: qid,
        steps: const [_StepSeed('made_up_move', risk: 0.8)],
      );
      final container = containerWith();
      final data = await container.read(learningInsightDataProvider.future);

      final unknown = data.unknownRows.single;
      expect(unknown.actionType, 'made_up_move');
      expect(unknown.known, isFalse);
      expect(data.hasUnknownActions, isTrue);
      expect(data.adviceCards.first.kind, LearningAdviceKind.reviewVocabulary);
    });
  });

  group('知识点标题与卡点', () {
    test('知识点中文名真被读出来并进卡点行与建议', () async {
      await seedKnowledgePoint('kp1', '动量守恒');
      final qid = await seedQuestion('题一');
      await seedChain(
        chainId: 'c1',
        questionId: qid,
        steps: const [
          _StepSeed('first_principles', risk: 0.8, hints: ['kp1']),
          _StepSeed('first_principles', risk: 0.9, hints: ['kp1']),
          _StepSeed('first_principles', risk: 0.7, hints: ['kp1'])
        ],
      );
      final container = containerWith();
      final data = await container.read(learningInsightDataProvider.future);

      expect(data.knowledgePointTitles, {'kp1': '动量守恒'});
      expect(data.hasKnowledgePointGaps, isTrue);
      final stuck = data.stuckRows.single;
      expect(stuck.knowledgePointId, 'kp1');
      expect(stuck.titleZh, '动量守恒');
      expect(stuck.highRiskStepCount, 3);
      expect(stuck.questionCount, 1);

      final cross = data.actionKnowledgeRows.single;
      expect(cross.actionType, 'first_principles');
      expect(cross.actionLabelZh, '从定义出发');
      expect(cross.knowledgePointId, 'kp1');
      expect(cross.knowledgePointTitleZh, '动量守恒');
      expect(cross.highRiskStepCount, 3);

      final advice = data.adviceCards.first;
      expect(advice.kind, LearningAdviceKind.practiceAction);
      expect(advice.knowledgePointIds, ['kp1']);
      expect(advice.knowledgePointTitles, ['动量守恒']);
      expect(advice.hasKnowledgePoints, isTrue);
    });

    test('知识点读不到标题时回退 id，不编造', () async {
      final qid = await seedQuestion('题一');
      await seedChain(
        chainId: 'c1',
        questionId: qid,
        steps: const [
          _StepSeed('first_principles', risk: 0.8, hints: ['ghost'])
        ],
      );
      final container = containerWith();
      final data = await container.read(learningInsightDataProvider.future);

      expect(data.knowledgePointTitles, isEmpty);
      expect(data.stuckRows.single.titleZh, 'ghost');
      expect(data.actionKnowledgeRows.single.knowledgePointTitleZh, 'ghost');
    });

    test('readKnowledgePointTitles 只返回存在的 id，空标题丢弃', () async {
      await seedKnowledgePoint('kp1', '动量守恒');
      await seedKnowledgePoint('kp2', '   ');

      final titles =
          await readKnowledgePointTitles(db, {'kp1', 'kp2', 'missing'});

      expect(titles, {'kp1': '动量守恒'});
    });
  });

  group('词表 overlay', () {
    test('自定义动作按当前词表判定 known/custom', () async {
      final qid = await seedQuestion('题一');
      await seedChain(
        chainId: 'c1',
        questionId: qid,
        steps: const [_StepSeed('draw_force_diagram', risk: 0.8)],
      );
      final overlay = CapabilityActionOverlay.fromJson({
        'version': 1,
        'customActions': [
          {'key': 'draw_force_diagram', 'labelZh': '画受力图'},
        ],
      });
      final container = containerWith(overlay: overlay);
      final data = await container.read(learningInsightDataProvider.future);

      final row = data.actionRows.single;
      expect(row.actionType, 'draw_force_diagram');
      expect(row.labelZh, '画受力图');
      expect(row.known, isTrue);
      expect(row.custom, isTrue);
      expect(data.unknownRows, isEmpty);
      expect(data.actionCatalog['draw_force_diagram']?.labelZh, '画受力图');
      expect(data.vocabOverlayFallback, isFalse);
    });

    test('词表读失败退回内置词表并标记 fallback', () async {
      final qid = await seedQuestion('题一');
      await seedChain(
        chainId: 'c1',
        questionId: qid,
        steps: const [_StepSeed('draw_force_diagram', risk: 0.8)],
      );
      final container = containerWith(throwOnOverlay: true);
      final data = await container.read(learningInsightDataProvider.future);

      expect(data.vocabOverlayFallback, isTrue);
      final row = data.actionRows.single;
      expect(row.known, isFalse);
      expect(row.custom, isFalse);
      expect(data.unknownRows.single.actionType, 'draw_force_diagram');
    });
  });
}

class _StepSeed {
  const _StepSeed(this.action, {this.risk, this.hints = const <String>[]});

  final String action;
  final double? risk;
  final List<String> hints;
}

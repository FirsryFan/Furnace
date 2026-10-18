import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/domain/services/reasoning/capability_action.dart';
import 'package:furnace/domain/services/reasoning/capability_action_overlay.dart';
import 'package:furnace/features/questions/application/capability_vocabulary_store.dart';
import 'package:furnace/features/questions/application/chain_insights_reader.dart';

void main() {
  late AppDatabase db;
  late QuestionRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = QuestionRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<String> seedQuestion(String stem) async {
    final result = await repo.ingest(QuestionDraft(stem: stem));
    return result.question.id;
  }

  Future<String> seedChain({
    required String questionId,
    required List<ReasoningStepDraft> steps,
    DateTime? now,
    String summary = '',
  }) {
    return repo.saveChain(
      questionId,
      ReasoningChainDraft(summary: summary, steps: steps),
      now: now,
    );
  }

  Future<void> insertRawChain({
    required String id,
    required String questionId,
    required int createdAt,
    int stepCount = 0,
  }) async {
    await db.into(db.reasoningChains).insert(
          ReasoningChainsCompanion.insert(
            id: id,
            questionId: questionId,
            stepCount: Value(stepCount),
            createdAt: createdAt,
          ),
        );
  }

  Future<void> insertRawStep({
    required String id,
    required String chainId,
    required int idx,
    required String goal,
    required int createdAt,
    String actionType = 'unknown',
    String knowledgeHints = '[]',
    double? stuckRisk,
  }) async {
    await db.into(db.reasoningSteps).insert(
          ReasoningStepsCompanion.insert(
            id: id,
            chainId: chainId,
            idx: idx,
            goal: goal,
            actionType: Value(actionType),
            knowledgeHints: Value(knowledgeHints),
            stuckRisk: Value(stuckRisk),
            createdAt: createdAt,
          ),
        );
  }

  group('readChainInsightCorpus 读表投影', () {
    test('空库读成空快照且不抛', () async {
      final corpus = await readChainInsightCorpus(db);
      expect(corpus.isEmpty, isTrue);
      expect(corpus.chainCount, 0);
      expect(corpus.stepCount, 0);
      expect(corpus.orphanStepCount, 0);
      expect(corpus.invalidKnowledgeHintsSteps, 0);
    });

    test('单链：链与步骤字段原样投影，knownAction 留空交给当前词表', () async {
      final questionId = await seedQuestion('已知函数 f(x)=x^2，求单调区间。');
      final chainId = await seedChain(
        questionId: questionId,
        summary: '先配方再求导',
        now: DateTime.fromMillisecondsSinceEpoch(5000),
        steps: const <ReasoningStepDraft>[
          ReasoningStepDraft(
            goal: '读题并标出已知条件',
            actionType: 'condition_extraction',
            stuckRisk: 0.8,
            knowledgeHints: <String>['kp-quadratic', 'kp-derivative'],
          ),
          ReasoningStepDraft(
            goal: '求导',
            actionType: 'derivative_sign_analysis',
          ),
        ],
      );

      final corpus = await readChainInsightCorpus(db);
      expect(corpus.chainCount, 1);
      expect(corpus.stepCount, 2);

      final chain = corpus.chains.single;
      expect(chain.chainId, chainId);
      expect(chain.questionId, questionId);
      expect(chain.occurredAt, DateTime.fromMillisecondsSinceEpoch(5000));

      final steps = chain.steps;
      expect(steps.map((step) => step.actionType).toList(),
          <String>['condition_extraction', 'derivative_sign_analysis']);
      expect(steps.map((step) => step.index).toList(), <int>[0, 1]);
      expect(steps.first.stuckRisk, 0.8);
      expect(steps.first.knownAction, isNull);
      expect(steps.first.knowledgeHints,
          <String>['kp-quadratic', 'kp-derivative']);
      expect(steps.first.occurredAt, DateTime.fromMillisecondsSinceEpoch(5000));
      expect(steps.last.stuckRisk, isNull);
      expect(steps.last.knowledgeHints, isEmpty);
    });

    test('链按 createdAt 升序，同一时刻按 id 升序', () async {
      final questionId = await seedQuestion('链排序用的题目');

      final late = await seedChain(
        questionId: questionId,
        now: DateTime.fromMillisecondsSinceEpoch(2000),
        steps: const <ReasoningStepDraft>[
          ReasoningStepDraft(goal: '后来的链'),
        ],
      );
      final early = await seedChain(
        questionId: questionId,
        now: DateTime.fromMillisecondsSinceEpoch(1000),
        steps: const <ReasoningStepDraft>[
          ReasoningStepDraft(goal: '更早的链'),
        ],
      );
      final sameA = await seedChain(
        questionId: questionId,
        now: DateTime.fromMillisecondsSinceEpoch(3000),
        steps: const <ReasoningStepDraft>[],
      );
      final sameB = await seedChain(
        questionId: questionId,
        now: DateTime.fromMillisecondsSinceEpoch(3000),
        steps: const <ReasoningStepDraft>[],
      );

      // 同一毫秒的两条链按 id 升序；Ids.next 生成的是 uuid，不保证创建顺序。
      final tied = <String>[sameA, sameB]..sort();

      final corpus = await readChainInsightCorpus(db);
      expect(corpus.chains.map((chain) => chain.chainId).toList(),
          <String>[early, late, tied[0], tied[1]]);
    });

    test('链内步骤按 idx 升序，重复 idx 按 id 升序', () async {
      final questionId = await seedQuestion('步骤排序用的题目');
      await insertRawChain(
        id: 'rc-order',
        questionId: questionId,
        createdAt: 3000,
        stepCount: 4,
      );
      await insertRawStep(
        id: 'rs-c',
        chainId: 'rc-order',
        idx: 2,
        goal: '第三步',
        createdAt: 3000,
      );
      await insertRawStep(
        id: 'rs-b',
        chainId: 'rc-order',
        idx: 0,
        goal: '第二步的外壳',
        createdAt: 3000,
      );
      await insertRawStep(
        id: 'rs-a',
        chainId: 'rc-order',
        idx: 0,
        goal: '第一步',
        createdAt: 3000,
      );
      await insertRawStep(
        id: 'rs-d',
        chainId: 'rc-order',
        idx: 1,
        goal: '第二步',
        createdAt: 3000,
      );

      final corpus = await readChainInsightCorpus(db);
      final steps = corpus.chains.single.steps;
      expect(steps.map((step) => step.index).toList(), <int>[0, 0, 1, 2]);
      expect(steps.first.knowledgeHints, isEmpty);
    });

    test('没有步骤的链保留（链可以先建、步骤后补）', () async {
      final questionId = await seedQuestion('空链用的题目');
      await insertRawChain(
        id: 'rc-empty',
        questionId: questionId,
        createdAt: 7000,
      );

      final corpus = await readChainInsightCorpus(db);
      expect(corpus.chainCount, 1);
      expect(corpus.stepCount, 0);
      expect(corpus.chains.single.steps, isEmpty);
      expect(corpus.chains.single.chainId, 'rc-empty');
    });

    test('孤立步骤（chainId 找不到链）计数但不挂进任何链', () async {
      final questionId = await seedQuestion('孤立步骤用的题目');
      await insertRawChain(
        id: 'rc-ok',
        questionId: questionId,
        createdAt: 4000,
        stepCount: 1,
      );
      await insertRawStep(
        id: 'rs-ok',
        chainId: 'rc-ok',
        idx: 0,
        goal: '正常步骤',
        createdAt: 4000,
      );
      await insertRawStep(
        id: 'rs-ghost',
        chainId: 'rc-ghost',
        idx: 0,
        goal: '找不到链的步骤',
        createdAt: 4000,
      );

      final corpus = await readChainInsightCorpus(db);
      expect(corpus.chainCount, 1);
      expect(corpus.stepCount, 1);
      expect(corpus.orphanStepCount, 1);
      expect(corpus.chains.single.steps.single.actionType, 'unknown');
    });

    test('knowledgeHints：坏 JSON 计数并读空，合法数组过滤非法项', () async {
      final questionId = await seedQuestion('知识点提示解析用的题目');
      await insertRawChain(
        id: 'rc-hints',
        questionId: questionId,
        createdAt: 5000,
        stepCount: 4,
      );
      await insertRawStep(
        id: 'rs-hints-bad',
        chainId: 'rc-hints',
        idx: 0,
        goal: '坏 JSON',
        createdAt: 5000,
        knowledgeHints: 'not json at all',
      );
      await insertRawStep(
        id: 'rs-hints-empty',
        chainId: 'rc-hints',
        idx: 1,
        goal: '空数组',
        createdAt: 5000,
        knowledgeHints: '[]',
      );
      await insertRawStep(
        id: 'rs-hints-mixed',
        chainId: 'rc-hints',
        idx: 2,
        goal: '混入数字',
        createdAt: 5000,
        knowledgeHints: '[" kp-a ", 42, "kp-b", ""]',
      );
      await insertRawStep(
        id: 'rs-hints-object',
        chainId: 'rc-hints',
        idx: 3,
        goal: '不是数组',
        createdAt: 5000,
        knowledgeHints: '{"kp": true}',
      );

      final corpus = await readChainInsightCorpus(db);
      expect(corpus.invalidKnowledgeHintsSteps, 2);
      final steps = corpus.chains.single.steps;
      expect(steps[0].knowledgeHints, isEmpty);
      expect(steps[1].knowledgeHints, isEmpty);
      expect(steps[2].knowledgeHints, <String>['kp-a', 'kp-b']);
      expect(steps[3].knowledgeHints, isEmpty);
    });
  });

  group('洞察 provider', () {
    test('corpus provider 与直接读表一致', () async {
      final questionId = await seedQuestion('provider 一致性用的题目');
      await seedChain(
        questionId: questionId,
        now: DateTime.fromMillisecondsSinceEpoch(9000),
        steps: const <ReasoningStepDraft>[
          ReasoningStepDraft(goal: '一步', actionType: 'condition_extraction'),
        ],
      );

      final container = ProviderContainer(
        overrides: <Override>[appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      final fromProvider =
          await container.read(chainInsightCorpusProvider.future);
      final direct = await readChainInsightCorpus(db);
      expect(fromProvider.chainCount, direct.chainCount);
      expect(fromProvider.stepCount, direct.stepCount);
      expect(fromProvider.chains.single.chainId, direct.chains.single.chainId);
    });

    test('无链时聚合结果为空且不抛', () async {
      final container = ProviderContainer(
        overrides: <Override>[appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      final insights = await container.read(chainInsightsProvider.future);
      expect(insights.isEmpty, isTrue);
      expect(insights.chainCount, 0);
      expect(insights.neverUsedActions, isEmpty);
    });

    test('聚合：内置动作按词表认名，词表外原串进 unknownActions', () async {
      final questionId = await seedQuestion('聚合读数用的题目');
      final builtInKey = CapabilityAction.catalog.first.key;
      await seedChain(
        questionId: questionId,
        now: DateTime.fromMillisecondsSinceEpoch(10000),
        steps: <ReasoningStepDraft>[
          ReasoningStepDraft(
            goal: '读条件',
            actionType: builtInKey,
            stuckRisk: 0.7,
            knowledgeHints: const <String>['kp-1'],
          ),
          const ReasoningStepDraft(
            goal: '模型自造的动作',
            actionType: 'made_up_action',
            stuckRisk: 0.2,
          ),
        ],
      );

      final container = ProviderContainer(
        overrides: <Override>[appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      final insights = await container.read(chainInsightsProvider.future);
      expect(insights.chainCount, 1);
      expect(insights.stepCount, 2);
      expect(insights.questionCount, 1);
      expect(insights.unknownActions, hasLength(1));
      expect(insights.unknownActions.single.actionType, 'made_up_action');
      expect(insights.unknownActions.single.known, isFalse);

      final builtIn = insights.actions
          .firstWhere((action) => action.actionType == builtInKey);
      expect(builtIn.known, isTrue);
      expect(builtIn.stepCount, 1);
      expect(builtIn.highRiskStepCount, 1);
      expect(insights.neverUsedActions, isNotEmpty);
      expect(
        insights.neverUsedActions.any((action) => action.key == builtInKey),
        isFalse,
      );
    });

    test('注入自定义词表后，自定义动作被认作 known+custom', () async {
      final questionId = await seedQuestion('自定义词表用的题目');
      await seedChain(
        questionId: questionId,
        now: DateTime.fromMillisecondsSinceEpoch(11000),
        steps: const <ReasoningStepDraft>[
          ReasoningStepDraft(
            goal: '先画受力图',
            actionType: 'force_diagram_analysis',
          ),
        ],
      );

      const overlay = CapabilityActionOverlay(
        customActions: <CustomCapabilityAction>[
          CustomCapabilityAction(
            key: 'force_diagram_analysis',
            labelZh: '受力图分析',
            subjectHints: <String>['physics'],
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          capabilityActionOverlayProvider.overrideWith((ref) async => overlay),
        ],
      );
      addTearDown(container.dispose);

      final insights = await container.read(chainInsightsProvider.future);
      expect(insights.unknownActions, isEmpty);
      final custom = insights.customActions.single;
      expect(custom.actionType, 'force_diagram_analysis');
      expect(custom.label, '受力图分析');
      expect(custom.known, isTrue);
      expect(custom.custom, isTrue);
    });

    test('词表读取失败时退回内置词表继续聚合', () async {
      final questionId = await seedQuestion('词表失败用的题目');
      await seedChain(
        questionId: questionId,
        now: DateTime.fromMillisecondsSinceEpoch(12000),
        steps: const <ReasoningStepDraft>[
          ReasoningStepDraft(
            goal: '画受力图',
            actionType: 'force_diagram_analysis',
          ),
        ],
      );

      final container = ProviderContainer(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          capabilityActionOverlayProvider.overrideWith(
            (ref) => Future<CapabilityActionOverlay>.error(
              StateError('词表 JSON 坏了'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final insights = await container.read(chainInsightsProvider.future);
      expect(insights.chainCount, 1);
      expect(
          insights.unknownActions.single.actionType, 'force_diagram_analysis');
      expect(insights.customActions, isEmpty);
    });
  });
}

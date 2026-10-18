import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/domain/services/reasoning/capability_action_overlay.dart';
import 'package:furnace/domain/services/reasoning/chain_quality.dart';
import 'package:furnace/features/questions/application/capability_vocabulary_store.dart';
import 'package:furnace/features/questions/application/chain_quality_reader.dart';

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
  }) {
    return repo.saveChain(
      questionId,
      ReasoningChainDraft(steps: steps),
      now: now,
    );
  }

  Future<void> insertRawChain({
    required String id,
    required String questionId,
    required int createdAt,
  }) async {
    await db.into(db.reasoningChains).insert(
          ReasoningChainsCompanion.insert(
            id: id,
            questionId: questionId,
            createdAt: createdAt,
          ),
        );
  }

  Future<void> insertRawStep({
    required String id,
    required String chainId,
    required int idx,
    required int createdAt,
    String actionType = 'unknown',
    String justification = '',
    String checkMethod = '',
    String knowledgeHints = '[]',
    double? stuckRisk,
  }) async {
    await db.into(db.reasoningSteps).insert(
          ReasoningStepsCompanion.insert(
            id: id,
            chainId: chainId,
            idx: idx,
            goal: '第 $idx 步',
            actionType: Value(actionType),
            justification: Value(justification),
            checkMethod: Value(checkMethod),
            knowledgeHints: Value(knowledgeHints),
            stuckRisk: Value(stuckRisk),
            createdAt: createdAt,
          ),
        );
  }

  ProviderContainer containerWith({CapabilityActionOverlay? overlay}) {
    final container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
        if (overlay != null)
          capabilityActionOverlayProvider.overrideWith((ref) async => overlay),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('readChainQualityCorpus 读表投影', () {
    test('空库读成空快照且不抛', () async {
      final corpus = await readChainQualityCorpus(db);
      expect(corpus.isEmpty, isTrue);
      expect(corpus.chainCount, 0);
      expect(corpus.stepCount, 0);
      expect(corpus.orphanStepCount, 0);
      expect(corpus.invalidKnowledgeHintsSteps, 0);
    });

    test('单链：动作/序号/风险/理由/检验/知识点提示原样投影，knownAction 留空', () async {
      final questionId = await seedQuestion('已知函数 f(x)=x^2，求单调区间。');
      final chainId = await seedChain(
        questionId: questionId,
        steps: const <ReasoningStepDraft>[
          ReasoningStepDraft(
            goal: '读条件',
            actionType: 'condition_extraction',
            justification: '题干给出了区间端点',
            checkMethod: '回代 x=0',
            stuckRisk: 0.8,
            knowledgeHints: <String>['kp-quadratic', 'kp-derivative'],
          ),
          ReasoningStepDraft(
              goal: '求导', actionType: 'derivative_sign_analysis'),
        ],
      );

      final corpus = await readChainQualityCorpus(db);
      expect(corpus.chainCount, 1);
      expect(corpus.stepCount, 2);
      final chain = corpus.chains.single;
      expect(chain.chainId, chainId);
      expect(chain.questionId, questionId);

      final first = chain.steps.first;
      expect(first.actionType, 'condition_extraction');
      expect(first.index, 0);
      expect(first.stuckRisk, 0.8);
      expect(first.knownAction, isNull);
      expect(first.justification, '题干给出了区间端点');
      expect(first.checkMethod, '回代 x=0');
      expect(first.knowledgeHints, <String>['kp-quadratic', 'kp-derivative']);

      final second = chain.steps.last;
      expect(second.index, 1);
      expect(second.stuckRisk, isNull);
      expect(second.justification, isNull);
      expect(second.checkMethod, isNull);
      expect(second.knowledgeHints, isEmpty);
    });

    test('空白 justification / checkMethod 读作 null（不当作写了理由）', () async {
      final questionId = await seedQuestion('空白理由用的题目');
      await insertRawChain(id: 'c-blank', questionId: questionId, createdAt: 1);
      await insertRawStep(
        id: 's-blank',
        chainId: 'c-blank',
        idx: 0,
        createdAt: 1,
        justification: '   ',
        checkMethod: ' 回代 ',
      );

      final step =
          (await readChainQualityCorpus(db)).chains.single.steps.single;
      expect(step.justification, isNull);
      expect(step.checkMethod, '回代');
    });

    test('知识点提示：坏 JSON / 非数组读空并计数，非法项与空白项丢弃', () async {
      final questionId = await seedQuestion('坏提示用的题目');
      await insertRawChain(id: 'c-hints', questionId: questionId, createdAt: 1);
      await insertRawStep(
        id: 's-hints-0',
        chainId: 'c-hints',
        idx: 0,
        createdAt: 1,
        knowledgeHints: 'not json',
      );
      await insertRawStep(
        id: 's-hints-1',
        chainId: 'c-hints',
        idx: 1,
        createdAt: 1,
        knowledgeHints: '{"a":1}',
      );
      await insertRawStep(
        id: 's-hints-2',
        chainId: 'c-hints',
        idx: 2,
        createdAt: 1,
        knowledgeHints: '["kp-a", "  ", 42, "kp-b"]',
      );

      final corpus = await readChainQualityCorpus(db);
      expect(corpus.invalidKnowledgeHintsSteps, 2);
      final steps = corpus.chains.single.steps;
      expect(steps[0].knowledgeHints, isEmpty);
      expect(steps[1].knowledgeHints, isEmpty);
      expect(steps[2].knowledgeHints, <String>['kp-a', 'kp-b']);
    });

    test('链按 createdAt 升序、同时间按 id 升序；步骤按 idx 升序、同 idx 按 id 升序', () async {
      final questionId = await seedQuestion('顺序用的题目');
      await insertRawChain(id: 'c-b', questionId: questionId, createdAt: 2);
      await insertRawChain(id: 'c-a', questionId: questionId, createdAt: 1);
      await insertRawStep(id: 's-b-0', chainId: 'c-b', idx: 1, createdAt: 1);
      await insertRawStep(id: 's-b-1', chainId: 'c-b', idx: 0, createdAt: 1);
      await insertRawStep(id: 's-a-0', chainId: 'c-a', idx: 0, createdAt: 1);

      final corpus = await readChainQualityCorpus(db);
      expect(corpus.chains.map((chain) => chain.chainId).toList(),
          <String>['c-a', 'c-b']);
      expect(corpus.chains[1].steps.map((step) => step.index).toList(),
          <int>[0, 1]);
    });

    test('孤立步骤计 orphanStepCount 不挂链；无步骤的链保留', () async {
      final questionId = await seedQuestion('孤立步骤用的题目');
      await insertRawChain(id: 'c-empty', questionId: questionId, createdAt: 1);
      await insertRawStep(
          id: 's-orphan', chainId: 'missing', idx: 0, createdAt: 1);

      final corpus = await readChainQualityCorpus(db);
      expect(corpus.chainCount, 1);
      expect(corpus.chains.single.steps, isEmpty);
      expect(corpus.stepCount, 0);
      expect(corpus.orphanStepCount, 1);
    });
  });

  group('体检 provider', () {
    test('corpus provider 与直接读表一致；空库报告为空', () async {
      final questionId = await seedQuestion('provider 用的题目');
      await seedChain(
        questionId: questionId,
        steps: const <ReasoningStepDraft>[
          ReasoningStepDraft(goal: '读条件', actionType: 'condition_extraction'),
        ],
      );
      final container = containerWith();

      final fromProvider =
          await container.read(chainQualityCorpusProvider.future);
      final direct = await readChainQualityCorpus(db);
      expect(fromProvider.chainCount, direct.chainCount);
      expect(fromProvider.stepCount, direct.stepCount);
      expect(fromProvider.chains.single.chainId, direct.chains.single.chainId);

      final report = await container.read(chainQualityReportProvider.future);
      expect(report.chainCount, 1);
      expect(report.stepCount, 1);
      expect(report.isClean, isFalse);
      // 一步都不到的链会同时命中 too_few_steps 与 single_action。
      expect(report.findingsFor(ChainQualityCodes.tooFewSteps), isNotEmpty);
    });

    test('空库：体检报告为空且不抛', () async {
      final report =
          await containerWith().read(chainQualityReportProvider.future);
      expect(report.chainCount, 0);
      expect(report.findings, isEmpty);
      expect(report.isClean, isTrue);
    });

    test('词表外的动作命中 unknown_action_ratio_high；注入自定义词表后不再命中', () async {
      final questionId = await seedQuestion('未知动作用的题目');
      await seedChain(
        questionId: questionId,
        steps: const <ReasoningStepDraft>[
          ReasoningStepDraft(goal: '一步', actionType: 'made_up_action'),
          ReasoningStepDraft(goal: '二步', actionType: 'made_up_action'),
          ReasoningStepDraft(goal: '三步', actionType: 'made_up_action'),
        ],
      );

      final plain =
          await containerWith().read(chainQualityReportProvider.future);
      expect(
        plain.findingsFor(ChainQualityCodes.unknownActionRatioHigh),
        isNotEmpty,
      );
      expect(plain.findingsFor(ChainQualityCodes.noKnownAction), isNotEmpty);

      const overlay = CapabilityActionOverlay(
        customActions: <CustomCapabilityAction>[
          CustomCapabilityAction(
            key: 'made_up_action',
            labelZh: '自造动作',
          ),
        ],
      );
      final withOverlay = await containerWith(overlay: overlay)
          .read(chainQualityReportProvider.future);
      expect(
        withOverlay.findingsFor(ChainQualityCodes.unknownActionRatioHigh),
        isEmpty,
      );
      expect(
        withOverlay.findingsFor(ChainQualityCodes.noKnownAction),
        isEmpty,
      );
    });

    test('词表读失败时退回内置词表继续体检，不阻塞', () async {
      final questionId = await seedQuestion('词表失败用的题目');
      await seedChain(
        questionId: questionId,
        steps: const <ReasoningStepDraft>[
          ReasoningStepDraft(
            goal: '读条件',
            actionType: 'condition_extraction',
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          capabilityActionOverlayProvider.overrideWith(
            (ref) async => throw StateError('词表坏了'),
          ),
        ],
      );
      addTearDown(container.dispose);

      final report = await container.read(chainQualityReportProvider.future);
      expect(report.chainCount, 1);
      expect(report.stepCount, 1);
    });

    test('单题 provider 只出该题 findings；没有链时返回空报告', () async {
      final q1 = await seedQuestion('第一道题');
      final q2 = await seedQuestion('第二道题');
      await seedChain(
        questionId: q1,
        steps: const <ReasoningStepDraft>[
          ReasoningStepDraft(goal: '读条件', actionType: 'condition_extraction'),
        ],
      );
      await seedChain(
        questionId: q2,
        steps: const <ReasoningStepDraft>[
          ReasoningStepDraft(goal: '读条件', actionType: 'condition_extraction'),
          ReasoningStepDraft(
              goal: '求导', actionType: 'derivative_sign_analysis'),
          ReasoningStepDraft(goal: '写结论', actionType: 'conclusion_writing'),
        ],
      );
      final container = containerWith();

      final onlyQ1 = await container.read(
        chainQualityForQuestionProvider(q1).future,
      );
      expect(onlyQ1.chainCount, 1);
      expect(onlyQ1.stepCount, 1);
      expect(
        onlyQ1.findings.every((finding) => finding.questionId == q1),
        isTrue,
      );

      final onlyQ2 = await container.read(
        chainQualityForQuestionProvider(q2).future,
      );
      expect(onlyQ2.chainCount, 1);
      expect(onlyQ2.stepCount, 3);
      expect(
        onlyQ2.findings.every((finding) => finding.questionId == q2),
        isTrue,
      );

      final missing = await container.read(
        chainQualityForQuestionProvider('no-such-question').future,
      );
      expect(missing.chainCount, 0);
      expect(missing.findings, isEmpty);
    });
  });
}

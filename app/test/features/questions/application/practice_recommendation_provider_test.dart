import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/domain/services/reasoning/practice_recommendation.dart';
import 'package:furnace/features/questions/application/capability_vocabulary_store.dart';
import 'package:furnace/features/questions/application/practice_recommendation_provider.dart';

/// 配题推荐接线（`practice_recommendation_provider.dart`）的验收点：
///
///  * 题库行 → `PracticeQuestionCandidate` 字段一一对应（题号 / 难度 /
///    AI 质量 / 答案解析是否齐全 / 知识点 / 最新链动作）；
///  * 非有限读数（NaN / ±inf）读作「没有读数」，不把脏数带进打分；
///  * provider 把洞察 + 学习建议 + 候选投影真的拼进
///    `PracticeRecommendationPlan.build`（卡点知识点、未知动作补习）；
///  * 空库 / 词表读取失败都不抛异常。
void main() {
  late AppDatabase db;
  late QuestionRepository questions;
  late TagRepository tags;
  late AnkiRepository anki;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    questions = QuestionRepository(db);
    tags = TagRepository(db);
    anki = AnkiRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  ProviderContainer containerWith({bool overlayFails = false}) {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        if (overlayFails)
          capabilityActionOverlayProvider.overrideWith(
            (ref) async => throw StateError('词表读不出来'),
          ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<String> seedQuestion({
    required String stem,
    String subjectKey = '数学',
    String sourceLevel = 'gaokao',
    String? answer,
    String? solution,
    double? difficulty,
    double? aiQuality,
  }) async {
    final ingested = await questions.ingest(
      QuestionDraft(
        stem: stem,
        answer: answer,
        solution: solution,
        subjectKey: subjectKey,
        sourceLevel: sourceLevel,
        difficulty: difficulty,
        aiQuality: aiQuality,
      ),
    );
    return ingested.question.id;
  }

  Future<String> seedKnowledgePoint(String title) async =>
      (await anki.createKnowledgePoint(title: title, content: '')).id;

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

  group('读表投影', () {
    test('字段一一对应；题号由入库时自动分配', () async {
      final id = await seedQuestion(
        stem: '已知函数求单调区间',
        subjectKey: '物理',
        sourceLevel: 'elite_school',
        answer: 'B',
        solution: '先求导再判号',
        difficulty: 6.5,
        aiQuality: 0.8,
      );
      final candidates = await readPracticeQuestionCandidates(db);
      expect(candidates, hasLength(1));
      final candidate = candidates.single;
      expect(candidate.questionId, id);
      expect(candidate.serialNo, 1);
      expect(candidate.subjectKey, '物理');
      expect(candidate.sourceLevel, 'elite_school');
      expect(candidate.difficulty, 6.5);
      expect(candidate.aiQuality, 0.8);
      expect(candidate.hasAnswer, isTrue);
      expect(candidate.hasSolution, isTrue);
      expect(candidate.knowledgePointIds, isEmpty);
      expect(candidate.actionTypes, isEmpty);
    });

    test('缺答案 / 解析读作 false，空白也算缺', () async {
      await seedQuestion(stem: '题一');
      await seedQuestion(stem: '题二', answer: '   ', solution: '');
      final candidates = await readPracticeQuestionCandidates(db);
      expect(candidates, hasLength(2));
      for (final candidate in candidates) {
        expect(candidate.hasAnswer, isFalse);
        expect(candidate.hasSolution, isFalse);
      }
    });

    test('难度 / AI 质量非有限数读作没有读数', () async {
      await seedQuestion(
        stem: '脏读数题',
        difficulty: double.nan,
        aiQuality: double.infinity,
      );
      final candidate = (await readPracticeQuestionCandidates(db)).single;
      expect(candidate.difficulty, isNull);
      expect(candidate.aiQuality, isNull);
    });

    test('没有链时动作列表为空；多条链只认最新一条', () async {
      final withChain = await seedQuestion(stem: '有链的题');
      final withoutChain = await seedQuestion(stem: '没链的题');
      await seedChain(
        chainId: 'old',
        questionId: withChain,
        steps: const [
          (action: 'case_split', risk: 0.2, hints: <String>[]),
          (action: 'verify_by_substitution', risk: 0.1, hints: <String>[]),
        ],
      );
      await seedChain(
        chainId: 'new',
        questionId: withChain,
        createdAt: 2,
        steps: const [
          (action: 'construct_function', risk: null, hints: <String>[]),
        ],
      );
      final byId = {
        for (final candidate in await readPracticeQuestionCandidates(db))
          candidate.questionId: candidate,
      };
      expect(byId[withChain]!.actionTypes, ['construct_function']);
      expect(byId[withoutChain]!.actionTypes, isEmpty);
    });

    test('知识点按「同一个标签同时挂题与知识点」口径收集', () async {
      final pointId = await seedKnowledgePoint('条件概率');
      final linked = await seedQuestion(stem: '挂了知识点的题');
      final alone = await seedQuestion(stem: '没挂的题');
      await linkKnowledgePoint(pointId: pointId, questionId: linked);
      final byId = {
        for (final candidate in await readPracticeQuestionCandidates(db))
          candidate.questionId: candidate,
      };
      expect(byId[linked]!.knowledgePointIds, [pointId]);
      expect(byId[alone]!.knowledgePointIds, isEmpty);
    });

    test('空库返回空列表', () async {
      expect(await readPracticeQuestionCandidates(db), isEmpty);
    });
  });

  group('provider 端到端', () {
    test('空库给空 plan，不抛', () async {
      final container = containerWith();
      final plan = await container.read(practiceRecommendationProvider.future);
      expect(plan.recommendations, isEmpty);
      expect(plan.requestCount, 0);
      expect(plan.maxQuestions, PracticeRecommendationPlan.defaultMaxQuestions);
      expect(plan.toJson()['recommendation_count'], 0);
    });

    test('卡点知识点的题排第一，并给出命中理由', () async {
      final pointId = await seedKnowledgePoint('函数单调性');
      final risky = await seedQuestion(
        stem: '高卡点题',
        answer: 'A',
        solution: '先求导',
      );
      final other = await seedQuestion(stem: '普通题');
      await linkKnowledgePoint(pointId: pointId, questionId: risky);
      await seedChain(
        chainId: 'chain-risky',
        questionId: risky,
        steps: [
          (action: 'case_split', risk: 0.9, hints: <String>[pointId]),
          (action: 'solve_equation', risk: 0.8, hints: <String>[pointId]),
        ],
      );
      final container = containerWith();
      final plan = await container.read(practiceRecommendationProvider.future);
      expect(plan.requestCount, 2);
      final first = plan.recommendations.first;
      expect(first.questionId, risky);
      expect(first.rank, 1);
      expect(
        first.reasons,
        contains(PracticeRecommendationReason.matchedHighRiskKnowledgePoint),
      );
      expect(first.matchedKnowledgePointIds, [pointId]);
      expect(
        plan.recommendations.map((item) => item.questionId),
        containsAll(<String>[risky, other]),
      );
    });

    test('词表外的动作给补习加分并标 unknownActionScaffold', () async {
      final questionId = await seedQuestion(
        stem: '模型自己造了动作的题',
        answer: 'C',
        solution: '先翻译再套公式',
      );
      await seedChain(
        chainId: 'chain-unknown',
        questionId: questionId,
        steps: const [
          (action: 'mystery_move', risk: 0.9, hints: <String>[]),
        ],
      );
      final container = containerWith();
      final plan = await container.read(practiceRecommendationProvider.future);
      final recommendation = plan.recommendations.single;
      expect(
        recommendation.reasons,
        contains(PracticeRecommendationReason.unknownActionScaffold),
      );
      expect(recommendation.score, greaterThan(0));
    });

    test('答案与解析齐全留下 upToDate 理由', () async {
      await seedQuestion(
        stem: '资料齐全的题',
        answer: 'B',
        solution: '代入检验',
      );
      final container = containerWith();
      final plan = await container.read(practiceRecommendationProvider.future);
      final recommendation = plan.recommendations.single;
      expect(
        recommendation.reasons,
        contains(PracticeRecommendationReason.upToDate),
      );
      expect(
        recommendation.reasons,
        contains(PracticeRecommendationReason.unrelated),
      );
    });

    test('词表读取失败不阻塞推荐', () async {
      await seedQuestion(stem: '题一');
      await seedQuestion(stem: '题二');
      final container = containerWith(overlayFails: true);
      final plan = await container.read(practiceRecommendationProvider.future);
      expect(plan.requestCount, 2);
      expect(plan.recommendations, hasLength(2));
    });

    test('重新读 plan 能看到刚收的题', () async {
      await seedQuestion(stem: '先有的题');
      final container = containerWith();
      expect(
        (await container.read(practiceRecommendationProvider.future))
            .requestCount,
        1,
      );
      await seedQuestion(stem: '后收的题');
      container.invalidate(practiceCandidatesProvider);
      container.invalidate(practiceRecommendationProvider);
      expect(
        (await container.read(practiceRecommendationProvider.future))
            .requestCount,
        2,
      );
    });
  });
}

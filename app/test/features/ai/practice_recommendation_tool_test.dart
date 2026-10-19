import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/domain/services/reasoning/capability_action.dart';
import 'package:furnace/features/ai/domain/ai_tool.dart';
import 'package:furnace/features/ai/domain/approval_engine.dart';
import 'package:furnace/features/ai/tools/practice_recommendation_tools.dart';

/// `recommend_practice` 是对话里「下一步练哪几道题」的工具面，验收点：
///
///  1. **只读**：任何权限模式都不逐条询问，一次调用不改任何表；
///  2. **只排序库里已有的题**：题号、分数、理由都来自真实读数，不生成题目；
///  3. **偏好与阈值同源**：卡点知识点 / 练习动作来自洞察与学习建议，
///     难度目标只在 1..10 内生效，非法参数报错而不是静默退回默认值；
///  4. 边界：空库、学科过滤无候选、截断计数、未知动作、缺答案/解析扣分。
void main() {
  late AppDatabase db;
  late QuestionRepository questions;
  late TagRepository tags;
  late AnkiRepository anki;
  late RecommendPracticeTool tool;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    questions = QuestionRepository(db);
    tags = TagRepository(db);
    anki = AnkiRepository(db);
    tool = RecommendPracticeTool(db: db);
  });

  tearDown(() async {
    await db.close();
  });

  ToolInvocation invoke(Map<String, Object?> args) => ToolInvocation(
        toolName: tool.name,
        action: tool.name,
        arguments: args,
      );

  Future<String> seedQuestion({
    required String stem,
    String subjectKey = '数学',
    double? difficulty,
    String? answer = 'B',
    String? solution = '由定义可直接判断。',
  }) async {
    final ingested = await questions.ingest(
      QuestionDraft(
        stem: stem,
        answer: answer,
        solution: solution,
        subjectKey: subjectKey,
        difficulty: difficulty,
      ),
    );
    return ingested.question.id;
  }

  Future<String> seedKnowledgePoint(String title) async =>
      (await anki.createKnowledgePoint(title: title, content: '')).id;

  Future<void> link({
    required String questionId,
    required String pointId,
    required String tagName,
  }) async {
    final tagId = (await tags.createTag(name: tagName)).id;
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
    required String questionId,
    required List<ReasoningStepDraft> steps,
  }) async {
    await questions.saveChain(
      questionId,
      ReasoningChainDraft(
        model: 'test-model',
        summary: '测试链',
        steps: steps,
      ),
    );
  }

  Map<String, Object?> resultMap(ToolResult result) =>
      result.modelResult! as Map<String, Object?>;

  List<Map<String, Object?>> recommendations(ToolResult result) => [
        for (final item
            in resultMap(result)['recommendations']! as List<Object?>)
          item! as Map<String, Object?>,
      ];

  List<String> reasonKeys(Map<String, Object?> recommendation) => [
        for (final item in recommendation['reasons']! as List<Object?>)
          (item! as Map<String, Object?>)['key']! as String,
      ];

  group('read-only by construction', () {
    test('ApprovalEngine never asks per call, in any mode', () {
      for (final mode in AiPermissionMode.values) {
        final decision =
            ApprovalEngine(mode: mode).forInvocation(tool, const {});
        expect(decision.risk, ToolRisk.write);
        expect(decision.reversible, isTrue);
        expect(
          decision.disposition,
          isNot(ToolDisposition.individualApproval),
          reason: 'mode ${mode.name} must not ask one by one for a read',
        );
      }
      expect(tool.readOnly, isTrue);
      expect(tool.riskFor(''), ToolRisk.write);
      expect(tool.reversibleFor(''), isTrue);
      expect(tool.availableOnCurrentPlatform, isTrue);
      expect(tool.name, 'recommend_practice');
    });

    test('a call leaves every table untouched', () async {
      final pointId = await seedKnowledgePoint('函数单调性');
      final questionId = await seedQuestion(stem: '讨论函数的单调区间。');
      await link(
        questionId: questionId,
        pointId: pointId,
        tagName: '函数单调性',
      );
      await seedChain(
        questionId: questionId,
        steps: [
          ReasoningStepDraft(
            goal: '先求导',
            actionType: 'classify_discussion',
            stuckRisk: 0.8,
            knowledgeHints: [pointId],
          ),
        ],
      );

      Future<List<String>> snapshot() async {
        final questionRows = await db.select(db.questions).get();
        final chainRows = await db.select(db.reasoningChains).get();
        final stepRows = await db.select(db.reasoningSteps).get();
        final tagRows = await db.select(db.tags).get();
        final linkRows = await db.select(db.objectTags).get();
        return [
          for (final row in questionRows)
            'q:${row.id}:${row.stem}:${row.updatedAt}',
          for (final row in chainRows) 'c:${row.id}:${row.createdAt}',
          for (final row in stepRows) 's:${row.id}:${row.actionType}',
          for (final row in tagRows) 't:${row.id}:${row.name}',
          for (final row in linkRows)
            'l:${row.tagId}:${row.objectType}:${row.objectId}',
        ];
      }

      final before = await snapshot();
      final result = await tool.run(invoke(const {}));
      expect(result.ok, isTrue);
      expect(await snapshot(), before);
    });
  });

  group('空库与学科过滤', () {
    test('empty library: ok with no recommendations and an honest summary',
        () async {
      final result = await tool.run(invoke(const {}));
      expect(result.ok, isTrue);
      expect(recommendations(result), isEmpty);
      expect(resultMap(result)['candidate_count'], 0);
      expect(result.summary, contains('还没有能推荐的题'));
    });

    test('subject_key only picks that subject', () async {
      await seedQuestion(stem: '数学题', subjectKey: '数学');
      final physicsId = await seedQuestion(stem: '物理题', subjectKey: '物理');
      final result = await tool.run(invoke(const {'subject_key': '物理'}));
      expect(result.ok, isTrue);
      final rows = recommendations(result);
      expect(rows, hasLength(1));
      expect(rows.single['question_id'], physicsId);
      expect(rows.single['subject'], '物理');
      expect(rows.single['subject_key'], '物理');
    });

    test('subject_key with no candidates says so', () async {
      await seedQuestion(stem: '数学题', subjectKey: '数学');
      final result = await tool.run(invoke(const {'subject_key': '化学'}));
      expect(result.ok, isTrue);
      expect(recommendations(result), isEmpty);
      expect(result.summary, contains('没有学科'));
    });
  });

  group('偏好与排序', () {
    test('high-risk knowledge point candidate comes first', () async {
      final riskyPoint = await seedKnowledgePoint('圆锥曲线');
      final safePoint = await seedKnowledgePoint('集合');
      final riskyId = await seedQuestion(stem: '圆锥曲线综合题。');
      final safeId = await seedQuestion(stem: '集合的表示。');
      await link(
        questionId: riskyId,
        pointId: riskyPoint,
        tagName: '圆锥曲线',
      );
      await link(
        questionId: safeId,
        pointId: safePoint,
        tagName: '集合',
      );
      await seedChain(
        questionId: riskyId,
        steps: [
          ReasoningStepDraft(
            goal: '联立方程',
            actionType: 'link_conditions',
            stuckRisk: 0.9,
            knowledgeHints: [riskyPoint],
          ),
        ],
      );
      await seedChain(
        questionId: safeId,
        steps: [
          ReasoningStepDraft(
            goal: '直接列举',
            actionType: 'link_conditions',
            stuckRisk: 0.1,
            knowledgeHints: [safePoint],
          ),
        ],
      );

      final result = await tool.run(invoke(const {}));
      final rows = recommendations(result);
      expect(rows, hasLength(2));
      expect(rows.first['question_id'], riskyId);
      expect(
        reasonKeys(rows.first),
        contains('matchedHighRiskKnowledgePoint'),
      );
      expect(rows.first['matched_knowledge_point_ids'], contains(riskyPoint));
    });

    test('target_difficulty pulls the closer question up', () async {
      final easyId = await seedQuestion(stem: '简单题。', difficulty: 1);
      final hardId = await seedQuestion(stem: '困难题。', difficulty: 9);
      final result = await tool.run(
        invoke(const {'target_difficulty': 9}),
      );
      final rows = recommendations(result);
      expect(rows, hasLength(2));
      expect(rows.first['question_id'], hardId);
      final easyRow = rows.firstWhere((row) => row['question_id'] == easyId);
      expect(reasonKeys(easyRow), contains('tooEasy'));
      expect(resultMap(result)['filters'], isA<Map<String, Object?>>());
    });

    test('known action matching advice shows Chinese label', () async {
      final known = CapabilityAction.catalog.first;
      final pointId = await seedKnowledgePoint('函数');
      final questionId = await seedQuestion(stem: '函数综合题。');
      await link(questionId: questionId, pointId: pointId, tagName: '函数');
      await seedChain(
        questionId: questionId,
        steps: [
          for (var i = 0; i < 3; i++)
            ReasoningStepDraft(
              goal: '第 ${i + 1} 步',
              actionType: known.key,
              stuckRisk: 0.8,
              knowledgeHints: [pointId],
            ),
        ],
      );

      final result = await tool.run(invoke(const {}));
      final rows = recommendations(result);
      expect(rows, hasLength(1));
      expect(reasonKeys(rows.single), contains('matchedAdviceAction'));
      expect(rows.single['matched_action_types'], [known.key]);
      expect(
        rows.single['matched_action_labels_zh'],
        [known.labelZh],
      );
      expect(resultMap(result)['advices'], isNotEmpty);
    });

    test('unknown action is scaffolding, not practice advice', () async {
      final questionId = await seedQuestion(stem: '怪题。');
      await seedChain(
        questionId: questionId,
        steps: [
          const ReasoningStepDraft(
            goal: '先猜',
            actionType: 'mystery_move',
            stuckRisk: 0.2,
          ),
        ],
      );
      final result = await tool.run(invoke(const {}));
      final rows = recommendations(result);
      expect(rows, hasLength(1));
      expect(
        reasonKeys(rows.single),
        contains('unknownActionScaffold'),
      );
      expect(rows.single['matched_action_types'], isEmpty);
      expect(rows.single['matched_action_labels_zh'], isEmpty);
      final scaffoldReason = [
        for (final item in rows.single['reasons']! as List<Object?>)
          item! as Map<String, Object?>,
      ].firstWhere((reason) => reason['key'] == 'unknownActionScaffold');
      expect(scaffoldReason['label_zh'], contains('词表外动作'));
    });
  });

  group('参数与边界', () {
    test('max_questions truncates and counts skipped', () async {
      await seedQuestion(stem: '第一题。');
      await seedQuestion(stem: '第二题。');
      await seedQuestion(stem: '第三题。');
      final result = await tool.run(
        invoke(const {'max_questions': 2}),
      );
      final rows = recommendations(result);
      expect(rows, hasLength(2));
      expect(resultMap(result)['request_count'], 3);
      expect(resultMap(result)['skipped_count'], 1);
      expect(
        resultMap(result)['skipped_question_ids'],
        hasLength(1),
      );
    });

    test('serial label and score are present', () async {
      await seedQuestion(stem: '第一题。');
      final result = await tool.run(invoke(const {}));
      final row = recommendations(result).single;
      expect(row['serial_label'], 'TR-00001');
      expect(row['serial_no'], 1);
      expect(row['score'], isA<double>());
      expect(result.summary, contains('TR-00001'));
    });

    test('missing answer and solution are penalized with reasons', () async {
      final id = await seedQuestion(
        stem: '没有答案的题。',
        answer: null,
        solution: null,
      );
      final result = await tool.run(invoke(const {}));
      final row = recommendations(result).single;
      expect(row['question_id'], id);
      expect(reasonKeys(row), contains('missingSolution'));
      expect(reasonKeys(row), contains('missingAnswer'));
      expect(row['score'] as double, lessThan(0));
    });

    test('invalid arguments fail instead of silently defaulting', () async {
      final cases = <Map<String, Object?>>[
        const {'max_questions': 0},
        const {'max_questions': 'abc'},
        const {'target_difficulty': 0},
        const {'target_difficulty': 11},
        const {'target_difficulty': 'abc'},
      ];
      for (final args in cases) {
        final result = await tool.run(invoke(args));
        expect(result.ok, isFalse, reason: 'args $args');
        expect(result.error, isNotNull, reason: 'args $args');
      }
    });

    test('max_questions above the limit is clamped, not rejected', () async {
      await seedQuestion(stem: '唯一一道题。');
      final result = await tool.run(
        invoke(const {'max_questions': 999}),
      );
      expect(result.ok, isTrue);
      expect(
        resultMap(result)['filters'],
        containsPair('max_questions', RecommendPracticeTool.maxQuestionsLimit),
      );
    });
  });
}

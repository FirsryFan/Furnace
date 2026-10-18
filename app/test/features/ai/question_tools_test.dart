import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/data/repositories/time_block_repository.dart';
import 'package:furnace/features/ai/domain/ai_tool.dart';
import 'package:furnace/features/ai/domain/approval_engine.dart';
import 'package:furnace/features/ai/domain/tool_registry.dart';
import 'package:furnace/features/ai/tools/question_tools.dart';
import 'package:furnace/domain/services/paper/question_quality.dart';

/// `find_similar_questions` 是"找相似题"（Q12）的工具面，验收点：
///
///  1. **只读**：一次调用不改任何表，`ApprovalEngine` 在任何权限模式下都不逐条询问；
///  2. **只排序、不出题**：结果全是库里已有的题；题干由 `QuestionRepository` 落库的
///     原文截断而来，库里没有就说"没有"；
///  3. **两种问法都能用**：给 `question_id`（题在库里）或给条件
///     （知识点/动作序列）——后者是对话里"给我两道同型题"的自然说法；
///  4. 边界：题库空、没有基准、id 不存在、题干为空的脏行、`limit` 钳位。
void main() {
  late AppDatabase db;
  late QuestionRepository questions;
  late TagRepository tags;
  late AnkiRepository anki;
  late FindSimilarQuestionsTool tool;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    questions = QuestionRepository(db);
    tags = TagRepository(db);
    anki = AnkiRepository(db);
    tool = FindSimilarQuestionsTool(db: db);
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
    String sourceLevel = 'gaokao',
    double? difficulty,
  }) async {
    final ingested = await questions.ingest(
      QuestionDraft(
        stem: stem,
        subjectKey: subjectKey,
        sourceLevel: sourceLevel,
        difficulty: difficulty,
      ),
    );
    return ingested.question.id;
  }

  Future<String> seedKnowledgePoint(String title) async =>
      (await anki.createKnowledgePoint(title: title, content: '')).id;

  /// 题目覆盖知识点：两者挂**同一个**标签（`TaskKnowledgePointResolver` 的规则）。
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
    required List<String> actionTypes,
    DateTime? now,
  }) async {
    await questions.saveChain(
      questionId,
      ReasoningChainDraft(
        model: 'test-model',
        summary: '测试链',
        steps: [
          for (var index = 0; index < actionTypes.length; index++)
            ReasoningStepDraft(
              goal: '第 ${index + 1} 步',
              actionType: actionTypes[index],
            ),
        ],
      ),
      now: now,
    );
  }

  /// 题目 + 链 + 标签挂载的整库指纹：只读工具不该让任何一行变化。
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
      expect(tool.riskFor(''), ToolRisk.write); // unused: no actions
      expect(tool.reversibleFor(''), isTrue);
      expect(tool.availableOnCurrentPlatform, isTrue);
    });

    test('a call leaves every table untouched', () async {
      final pointId = await seedKnowledgePoint('动量守恒');
      final focusId = await seedQuestion(stem: '碰撞后速度各是多少？');
      final similarId = await seedQuestion(stem: '另一道动量题。');
      await link(questionId: focusId, pointId: pointId, tagName: '力学');
      await link(questionId: similarId, pointId: pointId, tagName: '力学');
      await seedChain(
        questionId: focusId,
        actionTypes: ['first_principles', 'sanity_check'],
      );
      await seedChain(
        questionId: similarId,
        actionTypes: ['first_principles', 'sanity_check'],
      );

      final before = await snapshot();
      final result = await tool.run(invoke({'question_id': focusId}));

      expect(result.ok, isTrue);
      expect(await snapshot(), before,
          reason: 'the tool must not write: same rows, same values');
    });
  });

  group('给 question_id：按库里的题找邻居', () {
    test('共用知识点 + 同型步骤 → 返回题干摘要、理由与中文动作名', () async {
      final pointId = await seedKnowledgePoint('动量守恒');
      final focusId = await seedQuestion(stem: '碰撞后两球速度各是多少？');
      final similarId = await seedQuestion(stem: '冰面上两滑块相碰。');
      await seedQuestion(stem: '完全无关的题。', subjectKey: '语文');
      await link(questionId: focusId, pointId: pointId, tagName: '力学');
      await link(questionId: similarId, pointId: pointId, tagName: '力学');
      await seedChain(
        questionId: focusId,
        actionTypes: ['first_principles', 'sanity_check'],
      );
      await seedChain(
        questionId: similarId,
        actionTypes: ['first_principles', 'sanity_check'],
      );

      final result = await tool.run(invoke({'question_id': focusId}));
      final payload = result.modelResult! as Map<String, Object?>;
      final rows = payload['questions']! as List<Object?>;

      expect(result.ok, isTrue);
      expect(payload['bank_size'], 3);
      expect(payload['returned'], 1);
      expect(result.summary, contains('找到 1 道相似题'));

      final first = rows.single! as Map<String, Object?>;
      expect(first['id'], similarId);
      expect(first['stem'], '冰面上两滑块相碰。');
      expect(first['reason'] as String, contains('同型步骤'));
      expect(first['shared_knowledge_point_ids'], [pointId]);
      expect(first['shared_knowledge_points'], ['动量守恒']);
      expect(
          first['shared_action_types'], ['first_principles', 'sanity_check']);
      // 动作 key 在给用户看的字段里是中文（词表外的 key 原样保留）。
      expect(first['shared_actions_zh'], isNotEmpty);
      // 四个基础分量 + 第五个可选分量 `quality`（MindNet 有效性）。这个工具没接
      // 认知读数、权重默认 0，所以 quality 恒为中性 0.5——它存在但不参与排序。
      final components = first['components']! as Map<String, Object?>;
      expect(components.keys.toSet(),
          {'knowledge_point', 'action_type', 'subject', 'difficulty', 'quality'});
      expect(components['quality'], kNeutralQuestionQuality);
      expect(first['score'] as double, greaterThanOrEqualTo(0.25));
    });

    test('长题干截断到上限，末尾有省略号', () async {
      final pointId = await seedKnowledgePoint('电场');
      final focusId = await seedQuestion(stem: '基准题。');
      final longStem = '很长的题干${'啊' * 300}';
      final similarId = await seedQuestion(stem: longStem);
      await link(questionId: focusId, pointId: pointId, tagName: '电场');
      await link(questionId: similarId, pointId: pointId, tagName: '电场');

      final result = await tool.run(invoke({'question_id': focusId}));
      final rows = (result.modelResult! as Map<String, Object?>)['questions']!
          as List<Object?>;
      final stem = (rows.single! as Map<String, Object?>)['stem'] as String;

      expect(stem.endsWith('…'), isTrue);
      expect(stem.length, FindSimilarQuestionsTool.stemPreviewLength + 1);
    });

    test('id 不存在 → 失败并说明，不是空结果', () async {
      await seedQuestion(stem: '库里唯一的题。');

      final result = await tool.run(invoke({'question_id': 'q-nope'}));

      expect(result.ok, isFalse);
      expect(result.error, contains('没有 id 为 `q-nope` 的题'));
    });

    test('题干为空的脏行仍能当基准（回落读题目行），但弱信号不入榜', () async {
      const blankId = 'q-blank';
      final at = DateTime(2026, 1, 1).millisecondsSinceEpoch;
      await db.into(db.questions).insert(
            QuestionsCompanion.insert(
              id: blankId,
              stem: '   ',
              subjectKey: const Value('数学'),
              sourceLevel: const Value('gaokao'),
              difficulty: const Value(5),
              createdAt: at,
              updatedAt: at,
            ),
          );
      await seedQuestion(stem: '另一道题。');

      final result = await tool.run(invoke({'question_id': blankId}));

      expect(result.ok, isTrue, reason: '查得到这行就不该失败');
      expect((result.modelResult! as Map<String, Object?>)['returned'], 0);
      expect(result.summary, contains('没有一道够像'));
      expect(result.summary, contains('我不会自己出题'));
    });
  });

  group('只给条件：对话里"给我两道同型题"', () {
    test('知识点 + 动作序列 → 找到库里同型的题', () async {
      final pointId = await seedKnowledgePoint('数列');
      final firstId = await seedQuestion(stem: '求通项公式。');
      final secondId = await seedQuestion(stem: '求和。');
      await link(questionId: firstId, pointId: pointId, tagName: '数列');
      await link(questionId: secondId, pointId: pointId, tagName: '数列');
      await seedChain(questionId: firstId, actionTypes: ['induction']);
      await seedChain(questionId: secondId, actionTypes: ['induction']);

      final result = await tool.run(invoke({
        'knowledge_point_ids': [pointId],
        'action_types': ['induction'],
      }));
      final payload = result.modelResult! as Map<String, Object?>;
      final ids = [
        for (final row in payload['questions']! as List<Object?>)
          (row! as Map<String, Object?>)['id'],
      ];

      expect(result.ok, isTrue);
      expect(ids, unorderedEquals([firstId, secondId]));
      expect(payload['focus'], isA<Map<String, Object?>>());
    });

    test('没有基准 → 失败，错误里列出可给哪些参数', () async {
      await seedQuestion(stem: '库里唯一的题。');

      final result = await tool.run(invoke(const {}));

      expect(result.ok, isFalse);
      expect(result.error, contains('缺少基准'));
      expect(result.error, contains('knowledge_point_ids'));
    });

    test('题库为空 → 成功但 0 条，并明说不会自己出题', () async {
      final result = await tool.run(invoke({'subject_key': '数学'}));

      expect(result.ok, isTrue);
      expect(result.summary, contains('还没有题'));
      expect(result.summary, contains('不会自己出题'));
      expect((result.modelResult! as Map<String, Object?>)['bank_size'], 0);
    });

    test('limit 生效：默认 5、钳到 1..20', () async {
      final pointId = await seedKnowledgePoint('集合');
      final focusId = await seedQuestion(stem: '基准题。');
      await link(questionId: focusId, pointId: pointId, tagName: '集合');
      for (var index = 0; index < 4; index++) {
        final id = await seedQuestion(stem: '同型题 $index。');
        await link(questionId: id, pointId: pointId, tagName: '集合');
      }

      int returnedOf(ToolResult result) =>
          (result.modelResult! as Map<String, Object?>)['returned']! as int;

      expect(returnedOf(await tool.run(invoke({'question_id': focusId}))), 4);
      expect(
        returnedOf(await tool.run(invoke({
          'question_id': focusId,
          'limit': 2,
        }))),
        2,
      );
      // 0 / 负数走默认值；超大值被钳到上限。库里只有 4 道同知识点的题，
      // 但这一问没有 question_id，所以基准题自己不排除 → 5 道都在候选里。
      expect(
        returnedOf(await tool.run(invoke({
          'question_id': focusId,
          'limit': 0,
        }))),
        4,
      );
      expect(
        returnedOf(await tool.run(invoke({
          'knowledge_point_ids': [pointId],
          'limit': 999,
        }))),
        5,
      );
    });
  });

  group('注册与 schema', () {
    test('在 ToolRegistry.forApp 里可达，且声明是只读的', () {
      final registry = ToolRegistry.forApp(
        db: db,
        tasks: TaskRepository(db),
        blocks: TimeBlockRepository(db),
        anki: anki,
        tags: tags,
      );

      expect(registry.byName('find_similar_questions'),
          isA<FindSimilarQuestionsTool>());
      expect(
        registry.forCurrentPlatform.map((t) => t.name),
        contains('find_similar_questions'),
      );

      final spec = registry.modelSpecs.firstWhere((s) => s.name == tool.name);
      expect(spec.description, contains('只读'));
      expect(spec.parameters['type'], 'object');
      expect(
        (spec.parameters['properties']! as Map<String, Object?>).keys,
        containsAll([
          'question_id',
          'knowledge_point_ids',
          'action_types',
          'subject_key',
          'question_type',
          'difficulty',
          'limit',
        ]),
      );
    });
  });
}

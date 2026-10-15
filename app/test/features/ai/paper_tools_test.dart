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
import 'package:furnace/features/ai/tools/paper_tools.dart';

/// `compose_paper` 是"现在该练什么"（Q9/Q11）的工具面，验收点：
///
///  1. **只读**：一次调用不改任何表，`ApprovalEngine` 在任何权限模式下都不逐条询问；
///  2. **AI 不出题**：卷子上的每道题都是题库里已有的行；凑不齐时如实说缺什么，
///     绝不生成题干填空；
///  3. **诚实**：诊断快层这轮没跑 → 所有知识点按"没有读数"处理，并在摘要里
///     **明说"不是健康"**（Q13 之前工具不敢做，正是怕"没跑"被当成"学得好"）；
///  4. 入参边界：学科/来源筛选、`target_count` 钳位、不认识的来源分级、
///     难度与配额越界 → 失败并说明。
void main() {
  late AppDatabase db;
  late QuestionRepository questions;
  late TagRepository tags;
  late AnkiRepository anki;
  late ComposePaperTool tool;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    questions = QuestionRepository(db);
    tags = TagRepository(db);
    anki = AnkiRepository(db);
    tool = ComposePaperTool(db: db);
  });

  tearDown(() async {
    await db.close();
  });

  ToolInvocation invoke(Map<String, Object?> args) => ToolInvocation(
        toolName: tool.name,
        action: tool.name,
        arguments: args,
      );

  Map<String, Object?> payloadOf(ToolResult result) =>
      result.modelResult! as Map<String, Object?>;

  List<Map<String, Object?>> itemsOf(ToolResult result) => [
        for (final item in payloadOf(result)['items']! as List<Object?>)
          item! as Map<String, Object?>,
      ];

  Future<String> seedQuestion({
    required String stem,
    String subjectKey = 'math',
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

  /// 一道题 + 一个知识点 + 挂载，一次到位；返回 (questionId, pointId)。
  Future<(String, String)> seedLinked({
    required String stem,
    required String pointTitle,
    String subjectKey = 'math',
    String sourceLevel = 'gaokao',
    double? difficulty,
  }) async {
    final pointId = await seedKnowledgePoint(pointTitle);
    final questionId = await seedQuestion(
      stem: stem,
      subjectKey: subjectKey,
      sourceLevel: sourceLevel,
      difficulty: difficulty,
    );
    await link(
      questionId: questionId,
      pointId: pointId,
      tagName: pointTitle,
    );
    return (questionId, pointId);
  }

  /// 整库指纹：只读工具不该让任何一行变化（drift 自己的 dump 帮手）。
  Future<Map<String, Object?>> snapshot() async {
    final dump = <String, Object?>{};
    for (final table in await db.userTables()) {
      dump[table] = await db.dumpTable(table);
    }
    return dump;
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

    test('组一次卷不改任何表（含标签挂载）', () async {
      await seedLinked(stem: '碰撞后速度各是多少？', pointTitle: '动量守恒');
      await seedLinked(
        stem: '第二道动量题。',
        pointTitle: '动量守恒',
        sourceLevel: 'school',
      );

      final before = await snapshot();
      final result = await tool.run(invoke({'target_count': 3}));

      expect(result.ok, isTrue);
      expect(await snapshot(), before,
          reason: 'the tool must not write: same rows, same values');
    });
  });

  group('题库不够时说实话', () {
    test('题库为空 → 成功但 0 道，并明说不会自己出题', () async {
      final result = await tool.run(invoke(const {}));

      expect(result.ok, isTrue);
      expect(payloadOf(result)['bank_size'], 0);
      expect(payloadOf(result)['item_count'], 0);
      expect(result.summary, contains('还没有任何可用的题'));
      expect(result.summary, contains('我不会自己出题'));
    });

    test('题干为空的脏行不算候选：题库"看起来有题"也照样空', () async {
      final at = DateTime(2026, 1, 1).millisecondsSinceEpoch;
      await db.into(db.questions).insert(
            QuestionsCompanion.insert(
              id: 'q-blank',
              stem: '   ',
              subjectKey: const Value('math'),
              sourceLevel: const Value('gaokao'),
              createdAt: at,
              updatedAt: at,
            ),
          );

      final result = await tool.run(invoke(const {}));

      expect(result.ok, isTrue);
      expect(payloadOf(result)['bank_size'], 0);
      expect(result.summary, contains('还没有任何可用的题'));
    });

    test('有题但学科筛掉了全部 → 0 道，摘要说明排不出来', () async {
      await seedLinked(stem: '一道数学题。', pointTitle: '数列');

      final result = await tool.run(invoke({
        'subject_keys': ['physics'],
      }));

      expect(result.ok, isTrue);
      expect(payloadOf(result)['item_count'], 0);
      expect(payloadOf(result)['bank_size'], 1);
      expect(result.summary, contains('一道都排不出来'));
    });
  });

  group('凑出一份卷子：读数来自与页面同源的诊断', () {
    test('没有诊断结论时按"没有读数"处理，并在摘要里明说不是健康', () async {
      final (_, pointId) = await seedLinked(
        stem: '碰撞后速度各是多少？',
        pointTitle: '动量守恒',
      );

      final result = await tool.run(invoke({'target_count': 1}));
      final payload = payloadOf(result);
      final items = itemsOf(result);

      expect(result.ok, isTrue);
      expect(payload['item_count'], 1);
      expect(payload['bank_size'], 1);
      expect(payload['diagnosis_ran'], isFalse, reason: '没有卡片观测/标签时快层不该假装跑过');
      expect(payload['readings_used'], 0);
      expect(payload['is_short'], isFalse);

      final item = items.single;
      expect(item['knowledge_point_id'], pointId);
      expect(item['knowledge_point_name'], '动量守恒');
      expect(item['zone'], 'unknown');
      expect(item['zone_zh'], '没有读数');
      expect(item['reason'] as String, isNotEmpty);
      expect(item['improvement_note'] as String, isNotEmpty);
      expect(item['background'] as String, isNotEmpty);
      expect(item['score'] as double, greaterThan(0));

      expect(result.summary, contains('凑出 1 道'));
      expect(result.summary, contains('没有读数'));
      expect(result.summary, contains('不是'), reason: '必须明说"没有读数 ≠ 健康"');
      expect(result.summary, contains('认知快层'));
    });

    test('来源分级下限只放行够高的来源', () async {
      await seedLinked(
        stem: '高考真题。',
        pointTitle: '电场',
        sourceLevel: 'gaokao',
      );
      await seedLinked(
        stem: '校内测题。',
        pointTitle: '磁场',
        sourceLevel: 'school',
      );

      final gaokaoOnly = itemsOf(await tool.run(invoke({
        'target_count': 5,
        'min_source_level': 'gaokao',
      })));
      expect(
          gaokaoOnly.map((item) => item['source_level']).toSet(), {'gaokao'});

      final schoolAndUp = itemsOf(await tool.run(invoke({
        'target_count': 5,
        'min_source_level': 'school',
      })));
      expect(
        schoolAndUp.map((item) => item['source_level']).toSet(),
        {'gaokao', 'school'},
      );
    });

    test('学科筛选：只要物理时数学题不进卷', () async {
      await seedLinked(stem: '一道数学题。', pointTitle: '数列');
      await seedLinked(
        stem: '一道物理题。',
        pointTitle: '动量守恒',
        subjectKey: 'physics',
      );

      final physicsOnly = itemsOf(await tool.run(invoke({
        'target_count': 5,
        'subject_keys': ['physics'],
      })));

      expect(physicsOnly, hasLength(1));
      expect(physicsOnly.single['subject_key'], 'physics');
    });

    test('target_count 钳在 1..50，实际值在 requested_count 里可见', () async {
      await seedLinked(stem: '一道题。', pointTitle: '数列');

      final huge = await tool.run(invoke({'target_count': 999}));
      expect(
          payloadOf(huge)['requested_count'], ComposePaperTool.maxTargetCount);

      final zero = await tool.run(invoke({'target_count': 0}));
      expect(payloadOf(zero)['requested_count'], 1);
    });
  });

  group('参数越界 → 失败并说明，而不是悄悄忽略', () {
    test('不认识的来源分级列出可用值', () async {
      final result = await tool.run(invoke({'min_source_level': 'nonsense'}));

      expect(result.ok, isFalse);
      expect(result.error, contains('不认识的来源分级'));
      expect(result.error, contains('gaokao'));
    });

    test('难度与配额越界各自报错', () async {
      final badDifficulty = await tool.run(invoke({'target_difficulty': 99}));
      expect(badDifficulty.ok, isFalse);
      expect(badDifficulty.error, contains('必须在 1..10'));

      final badCap = await tool.run(invoke({'per_knowledge_point_cap': 0}));
      expect(badCap.ok, isFalse);
      expect(badCap.error, contains('至少是 1'));
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

      expect(registry.byName('compose_paper'), isA<ComposePaperTool>());
      expect(
        registry.forCurrentPlatform.map((t) => t.name),
        contains('compose_paper'),
      );

      final spec = registry.modelSpecs.firstWhere((s) => s.name == tool.name);
      expect(spec.description, contains('只读'));
      expect(spec.description, contains('不生成题干'));
      expect(spec.parameters['type'], 'object');
      expect(
        (spec.parameters['properties']! as Map<String, Object?>).keys,
        containsAll([
          'target_count',
          'subject_keys',
          'min_source_level',
          'per_knowledge_point_cap',
          'target_difficulty',
        ]),
      );
    });
  });
}

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

  group('能力动作画像（与页面同源）', () {
    /// 给一道题落一条链：这是 `reasoning_steps` 里的真行，工具和页面读的是同一张表。
    Future<void> seedChain({
      required String questionId,
      required List<({String action, double? risk})> steps,
    }) async {
      await db.into(db.reasoningChains).insert(
            ReasoningChainsCompanion.insert(
              id: 'chain-$questionId',
              questionId: questionId,
              createdAt: 1,
              summary: const Value(''),
              stepCount: Value(steps.length),
            ),
          );
      for (var i = 0; i < steps.length; i++) {
        await db.into(db.reasoningSteps).insert(
              ReasoningStepsCompanion.insert(
                id: 'step-$questionId-$i',
                chainId: 'chain-$questionId',
                idx: i,
                goal: '第 $i 步',
                actionType: Value(steps[i].action),
                stuckRisk: Value(steps[i].risk),
                createdAt: 1,
              ),
            );
      }
    }

    test('工具挑卷子也用同一份动作画像：命中项排在前面、payload 里摆出来', () async {
      final (withChain, pointId) = await seedLinked(
        stem: '有链的那道动量题。',
        pointTitle: '动量守恒',
      );
      final (withoutChain, _) = await seedLinked(
        stem: '没链的那道动量题。',
        pointTitle: '动量守恒',
      );
      await seedChain(
        questionId: withChain,
        steps: <({String action, double? risk})>[
          (action: 'case_split', risk: 0.9),
        ],
      );

      final result = await tool.run(invoke(<String, Object?>{
        'target_count': 2,
      }));

      expect(result.ok, isTrue, reason: result.summary);
      final payload = payloadOf(result);
      expect(payload['preferred_action_types'], <String>['case_split']);
      final items = itemsOf(result);
      expect(items, hasLength(2));
      expect(items.first['question_id'], withChain);
      expect(items.first['matched_preferred_actions'], <String>['case_split']);
      expect(items.first['reason'], contains('分类讨论'));
      // 没链的题照样进卷，只是没有命中项（不因为"没解过"被排除）。
      expect(items.last['question_id'], withoutChain);
      expect(
        items.last.containsKey('matched_preferred_actions'),
        isFalse,
      );
      // 只读：整库指纹不变（含 reasoning_steps）。
      expect(pointId, isNotEmpty);
    });

    test('use_capability_profile: false：不参考画像，payload 里也不再声称用过', () async {
      final (withChain, pointId) = await seedLinked(
        stem: '有链的那道题。',
        pointTitle: '机械能守恒',
      );
      await seedLinked(
        stem: '没链的那道题。',
        pointTitle: '机械能守恒',
      );
      await seedChain(
        questionId: withChain,
        steps: <({String action, double? risk})>[
          (action: 'case_split', risk: 0.9),
        ],
      );

      final result = await tool.run(invoke(<String, Object?>{
        'target_count': 2,
        'use_capability_profile': false,
      }));

      expect(result.ok, isTrue, reason: result.summary);
      final payload = payloadOf(result);
      expect(payload['preferred_action_types'], isEmpty);
      expect(payload['capability_profile_used'], isFalse);
      final items = itemsOf(result);
      expect(items, hasLength(2));
      expect(
        items.every((item) => !item.containsKey('matched_preferred_actions')),
        isTrue,
      );
      expect(
        items.every((item) => !'${item['reason']}'.contains('能力动作画像')),
        isTrue,
      );
      expect(pointId, isNotEmpty);
    });
  });

  group('学科配额 subject_quota（可选，不启用时输出不变）', () {
    test('不传 subject_quota：payload 里没有配额四键，卷子与旧行为一致', () async {
      await seedLinked(stem: '一道数学题。', pointTitle: '数列');
      await seedLinked(
        stem: '一道物理题。',
        pointTitle: '动量守恒',
        subjectKey: 'physics',
      );

      final result = await tool.run(invoke({'target_count': 5}));
      final payload = payloadOf(result);

      expect(result.ok, isTrue, reason: result.summary);
      expect(payload['item_count'], 2);
      for (final key in [
        'by_subject',
        'quota_blocked_questions',
        'subject_shortfalls',
        'subject_quota',
      ]) {
        expect(payload.containsKey(key), isFalse, reason: '没启用配额时不该出现 $key');
      }
      expect(result.summary, isNot(contains('学科分布')));
    });

    test('上限生效：数学最多 1 道，物理照常进卷，摘要报学科分布', () async {
      for (var i = 0; i < 3; i++) {
        await seedLinked(stem: '数学题 $i。', pointTitle: '数列');
      }
      await seedLinked(
        stem: '一道物理题。',
        pointTitle: '动量守恒',
        subjectKey: 'physics',
      );

      final result = await tool.run(invoke(<String, Object?>{
        'target_count': 5,
        'subject_quota': <String, Object?>{
          'math': <String, Object?>{'max': 1},
        },
      }));
      final payload = payloadOf(result);
      final items = itemsOf(result);

      expect(result.ok, isTrue, reason: result.summary);
      expect(payload['by_subject'], <String, Object?>{'math': 1, 'physics': 1});
      expect(
        items.map((item) => item['subject_key']).toSet(),
        <String>{'math', 'physics'},
      );
      final blocked = payload['quota_blocked_questions']! as List<Object?>;
      expect(blocked, hasLength(2));
      final blockedJson = blocked.first! as Map<String, Object?>;
      expect(blockedJson['subject_key'], 'math');
      expect(blockedJson['subject_limit'], 1);
      expect(result.summary, contains('学科分布'));
      expect(result.summary, contains('被学科上限挡下'));
      final echo = payload['subject_quota']! as Map<String, Object?>;
      expect(echo['max_per_subject'], <String, Object?>{'math': 1});
    });

    test('保底缺口：数学要 3 道只有 1 道，如实报 selected/available', () async {
      await seedLinked(stem: '只有一道数学题。', pointTitle: '数列');

      final result = await tool.run(invoke(<String, Object?>{
        'target_count': 5,
        'subject_quota': <String, Object?>{
          'math': <String, Object?>{'min': 3},
        },
      }));
      final payload = payloadOf(result);

      expect(result.ok, isTrue, reason: result.summary);
      final shortfalls = payload['subject_shortfalls']! as List<Object?>;
      expect(shortfalls, hasLength(1));
      final shortfall = shortfalls.single! as Map<String, Object?>;
      expect(shortfall['subject_key'], 'math');
      expect(shortfall['minimum_count'], 3);
      expect(shortfall['selected_count'], 1);
      expect(shortfall['available_count'], 1);
      expect(shortfall['is_uncovered'], isFalse);
      expect(result.summary, contains('学科保底没凑够'));
      expect(result.summary, contains('可用候选 1 道'));
    });

    test('保底学科题库里没有题：缺口在收题，不在配额', () async {
      await seedLinked(stem: '一道数学题。', pointTitle: '数列');

      final result = await tool.run(invoke(<String, Object?>{
        'target_count': 3,
        'subject_quota': <String, Object?>{
          'math': <String, Object?>{'min': 1},
          'physics': <String, Object?>{'min': 2},
        },
      }));
      final payload = payloadOf(result);

      expect(result.ok, isTrue, reason: result.summary);
      final shortfalls = payload['subject_shortfalls']! as List<Object?>;
      expect(shortfalls, hasLength(1));
      final missing = shortfalls.single! as Map<String, Object?>;
      expect(missing['subject_key'], 'physics');
      expect(missing['is_uncovered'], isTrue);
      expect(missing['available_count'], 0);
      expect(result.summary, contains('题库里这一科没有可用题'));
    });

    test('max = 0：这一科一道都不取（不是忽略该键）', () async {
      await seedLinked(stem: '数学题。', pointTitle: '数列');
      await seedLinked(
        stem: '物理题。',
        pointTitle: '动量守恒',
        subjectKey: 'physics',
      );

      final result = await tool.run(invoke(<String, Object?>{
        'target_count': 5,
        'subject_quota': <String, Object?>{
          'math': <String, Object?>{'max': 0},
        },
      }));
      final payload = payloadOf(result);
      final items = itemsOf(result);

      expect(result.ok, isTrue, reason: result.summary);
      expect(
        items.map((item) => item['subject_key']).toSet(),
        <String>{'physics'},
      );
      final blocked = payload['quota_blocked_questions']! as List<Object?>;
      expect(
        blocked
            .map((row) => (row! as Map<String, Object?>)['subject_key'])
            .toSet(),
        <String>{'math'},
      );
    });

    test('空对象 = 没启用：不出现配额键', () async {
      await seedLinked(stem: '一道题。', pointTitle: '数列');

      final result = await tool.run(invoke(<String, Object?>{
        'target_count': 1,
        'subject_quota': <String, Object?>{},
      }));

      expect(result.ok, isTrue, reason: result.summary);
      expect(payloadOf(result).containsKey('subject_quota'), isFalse);
    });

    test('形状不对 → 失败并指出具体哪里错，而不是悄悄忽略', () async {
      Future<String> errorOf(Object? quota) async {
        final result = await tool.run(invoke(<String, Object?>{
          'subject_quota': quota,
        }));
        expect(result.ok, isFalse);
        return result.error!;
      }

      expect(await errorOf('math'), contains('必须是对象'));

      expect(
        await errorOf(<String, Object?>{
          ' ': <String, Object?>{'max': 1},
        }),
        contains('不能为空白'),
      );

      expect(
        await errorOf(<String, Object?>{'math': 1}),
        contains('必须是对象 {max, min}'),
      );

      expect(
        await errorOf(<String, Object?>{
          'math': <String, Object?>{'limit': 1},
        }),
        contains('只认识 max / min'),
      );

      expect(
        await errorOf(<String, Object?>{
          'math': <String, Object?>{'max': -1},
        }),
        contains('必须是非负整数'),
      );

      expect(
        await errorOf(<String, Object?>{
          ' math': <String, Object?>{'max': 1},
          'math': <String, Object?>{'max': 2},
        }),
        contains('重复学科键'),
      );

      expect(
        await errorOf(<String, Object?>{
          'math': <String, Object?>{'max': '不是数字'},
        }),
        contains('必须是非负整数'),
      );
    });

    test('schema 里声明了 subject_quota 对象', () {
      final registry = ToolRegistry.forApp(
        db: db,
        tasks: TaskRepository(db),
        blocks: TimeBlockRepository(db),
        anki: anki,
        tags: tags,
      );
      final spec = registry.modelSpecs.firstWhere((s) => s.name == tool.name);
      final properties = spec.parameters['properties']! as Map<String, Object?>;
      expect(properties.keys, contains('subject_quota'));
      final schema = properties['subject_quota']! as Map<String, Object?>;
      expect(schema['type'], 'object');
      expect(schema['description'] as String, contains('max'));
    });
  });

  group('领域配额 domain_quota（可选，不启用时输出不变）', () {
    /// 领域 = 标签路径第一段。顶层领域标签只建一次；每题一个子标签（同名
    /// 顶层标签第二次会变 `物理-2`，多题同域必须共用同一个父标签）。
    Future<String> seedDomainTag(String domain) async =>
        (await tags.createTag(name: domain)).id;

    Future<void> seedDomainLinked({
      required String domainTagId,
      required String childTag,
      required String stem,
      required String pointTitle,
      String subjectKey = 'math',
    }) async {
      final questionId = await seedQuestion(stem: stem, subjectKey: subjectKey);
      final pointId = await seedKnowledgePoint(pointTitle);
      final tagId =
          (await tags.createTag(name: childTag, parentId: domainTagId)).id;
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

    test('不传 domain_quota：payload 里没有领域四键，摘要不提领域', () async {
      final physics = await seedDomainTag('物理');
      final math = await seedDomainTag('数学');
      await seedDomainLinked(
        domainTagId: physics,
        childTag: '力学',
        stem: '一道物理题。',
        pointTitle: '动量守恒',
        subjectKey: 'physics',
      );
      await seedDomainLinked(
        domainTagId: math,
        childTag: '数列',
        stem: '一道数学题。',
        pointTitle: '等差数列',
      );

      final result = await tool.run(invoke({'target_count': 5}));
      final payload = payloadOf(result);

      expect(result.ok, isTrue, reason: result.summary);
      expect(payload['item_count'], 2);
      for (final key in [
        'by_domain',
        'quota_blocked_by_domain',
        'domain_shortfalls',
        'domain_quota',
      ]) {
        expect(payload.containsKey(key), isFalse, reason: '没启用领域配额不该出现 $key');
      }
      expect(result.summary, isNot(contains('领域分布')));
    });

    test('上限生效：物理最多 1 道，被挡的候选进清单，摘要报领域分布', () async {
      final physics = await seedDomainTag('物理');
      final math = await seedDomainTag('数学');
      await seedDomainLinked(
        domainTagId: physics,
        childTag: '力学',
        stem: '物理题 A',
        pointTitle: '动量守恒',
        subjectKey: 'physics',
      );
      await seedDomainLinked(
        domainTagId: physics,
        childTag: '电磁学',
        stem: '物理题 B',
        pointTitle: '电磁感应',
        subjectKey: 'physics',
      );
      await seedDomainLinked(
        domainTagId: physics,
        childTag: '光学',
        stem: '物理题 C',
        pointTitle: '光的折射',
        subjectKey: 'physics',
      );
      await seedDomainLinked(
        domainTagId: math,
        childTag: '数列',
        stem: '数学题 A',
        pointTitle: '等差数列',
      );

      final result = await tool.run(invoke(<String, Object?>{
        'target_count': 5,
        'domain_quota': <String, Object?>{
          '物理': <String, Object?>{'max': 1},
        },
      }));
      final payload = payloadOf(result);
      final items = itemsOf(result);

      expect(result.ok, isTrue, reason: result.summary);
      expect(payload['by_domain'], <String, Object?>{'物理': 1, '数学': 1});
      expect(items, hasLength(2));
      final blocked = payload['quota_blocked_by_domain']! as List<Object?>;
      expect(blocked, hasLength(2));
      final blockedJson = blocked.first! as Map<String, Object?>;
      expect(blockedJson['domain'], '物理');
      expect(blockedJson['domain_limit'], 1);
      expect(result.summary, contains('领域分布'));
      expect(result.summary, contains('被领域上限挡下'));
      final echo = payload['domain_quota']! as Map<String, Object?>;
      expect(echo['max_per_domain'], <String, Object?>{'物理': 1});
    });

    test('保底缺口：物理要 3 道只有 1 道，如实报 selected/available', () async {
      final physics = await seedDomainTag('物理');
      final math = await seedDomainTag('数学');
      await seedDomainLinked(
        domainTagId: physics,
        childTag: '力学',
        stem: '唯一一道物理题。',
        pointTitle: '动量守恒',
        subjectKey: 'physics',
      );
      await seedDomainLinked(
        domainTagId: math,
        childTag: '数列',
        stem: '一道数学题。',
        pointTitle: '等差数列',
      );

      final result = await tool.run(invoke(<String, Object?>{
        'target_count': 5,
        'domain_quota': <String, Object?>{
          '物理': <String, Object?>{'min': 3},
        },
      }));
      final payload = payloadOf(result);

      expect(result.ok, isTrue, reason: result.summary);
      final shortfalls = payload['domain_shortfalls']! as List<Object?>;
      expect(shortfalls, hasLength(1));
      final shortfall = shortfalls.single! as Map<String, Object?>;
      expect(shortfall['domain'], '物理');
      expect(shortfall['minimum_count'], 3);
      expect(shortfall['selected_count'], 1);
      expect(shortfall['available_count'], 1);
      expect(shortfall['is_uncovered'], isFalse);
      expect(result.summary, contains('领域保底没凑够'));
      expect(result.summary, contains('可用候选 1 道'));
    });

    test('保底领域题库里没有题：缺口在收题，不在配额', () async {
      final math = await seedDomainTag('数学');
      await seedDomainLinked(
        domainTagId: math,
        childTag: '数列',
        stem: '一道数学题。',
        pointTitle: '等差数列',
      );

      final result = await tool.run(invoke(<String, Object?>{
        'target_count': 3,
        'domain_quota': <String, Object?>{
          '化学': <String, Object?>{'min': 1},
        },
      }));
      final payload = payloadOf(result);

      expect(result.ok, isTrue, reason: result.summary);
      final shortfalls = payload['domain_shortfalls']! as List<Object?>;
      expect(shortfalls, hasLength(1));
      final missing = shortfalls.single! as Map<String, Object?>;
      expect(missing['domain'], '化学');
      expect(missing['is_uncovered'], isTrue);
      expect(missing['available_count'], 0);
      expect(result.summary, contains('题库里这一领域没有可用题'));
    });

    test('max = 0：这一领域一道都不取（不是忽略该键）', () async {
      final physics = await seedDomainTag('物理');
      final math = await seedDomainTag('数学');
      await seedDomainLinked(
        domainTagId: physics,
        childTag: '力学',
        stem: '物理题。',
        pointTitle: '动量守恒',
        subjectKey: 'physics',
      );
      await seedDomainLinked(
        domainTagId: math,
        childTag: '数列',
        stem: '数学题。',
        pointTitle: '等差数列',
      );

      final result = await tool.run(invoke(<String, Object?>{
        'target_count': 5,
        'domain_quota': <String, Object?>{
          '物理': <String, Object?>{'max': 0},
        },
      }));
      final payload = payloadOf(result);
      final items = itemsOf(result);

      expect(result.ok, isTrue, reason: result.summary);
      expect(items, hasLength(1));
      final blocked = payload['quota_blocked_by_domain']! as List<Object?>;
      expect(
        blocked.map((row) => (row! as Map<String, Object?>)['domain']).toSet(),
        <String>{'物理'},
      );
      expect(payload['by_domain'], <String, Object?>{'数学': 1});
    });

    test('空对象 = 没启用：不出现领域键', () async {
      await seedLinked(stem: '一道题。', pointTitle: '数列');

      final result = await tool.run(invoke(<String, Object?>{
        'target_count': 1,
        'domain_quota': <String, Object?>{},
      }));

      expect(result.ok, isTrue, reason: result.summary);
      expect(payloadOf(result).containsKey('domain_quota'), isFalse);
    });

    test('形状不对 → 失败并指出具体哪里错，而不是悄悄忽略', () async {
      Future<String> errorOf(Object? quota) async {
        final result = await tool.run(invoke(<String, Object?>{
          'domain_quota': quota,
        }));
        expect(result.ok, isFalse);
        return result.error!;
      }

      expect(await errorOf('物理'), contains('必须是对象'));

      expect(
        await errorOf(<String, Object?>{
          ' ': <String, Object?>{'max': 1},
        }),
        contains('不能为空白'),
      );

      expect(
        await errorOf(<String, Object?>{'物理': 1}),
        contains('必须是对象 {max, min}'),
      );

      expect(
        await errorOf(<String, Object?>{
          '物理': <String, Object?>{'limit': 1},
        }),
        contains('只认识 max / min'),
      );

      expect(
        await errorOf(<String, Object?>{
          '物理': <String, Object?>{'max': -1},
        }),
        contains('必须是非负整数'),
      );

      expect(
        await errorOf(<String, Object?>{
          ' 物理': <String, Object?>{'max': 1},
          '物理': <String, Object?>{'max': 2},
        }),
        contains('重复领域键'),
      );

      expect(
        await errorOf(<String, Object?>{
          '物理': <String, Object?>{'max': '不是数字'},
        }),
        contains('必须是非负整数'),
      );
    });

    test('schema 里声明了 domain_quota 对象', () {
      final registry = ToolRegistry.forApp(
        db: db,
        tasks: TaskRepository(db),
        blocks: TimeBlockRepository(db),
        anki: anki,
        tags: tags,
      );
      final spec = registry.modelSpecs.firstWhere((s) => s.name == tool.name);
      final properties = spec.parameters['properties']! as Map<String, Object?>;
      expect(properties.keys, contains('domain_quota'));
      final schema = properties['domain_quota']! as Map<String, Object?>;
      expect(schema['type'], 'object');
      expect(schema['description'] as String, contains('第一段'));
    });
  });

  group('手工指定/排除（manual_include_question_ids / manual_exclude_question_ids）',
      () {
    test('不传时四个手工键缺席，摘要不提手工选择', () async {
      await seedLinked(stem: '一道题。', pointTitle: '数列');

      final result =
          await tool.run(invoke(<String, Object?>{'target_count': 1}));

      expect(result.ok, isTrue, reason: result.summary);
      final payload = payloadOf(result);
      for (final key in <String>[
        'manual_included_count',
        'manual_missing_question_ids',
        'manual_skipped_question_ids',
        'manual_conflict_question_ids',
      ]) {
        expect(payload.containsKey(key), isFalse, reason: '没启用手工选择不该出现 $key');
      }
      expect(result.summary, isNot(contains('手工指定')));
    });

    test('必收绕过学科过滤、排除优先、冲突如实报', () async {
      final mathId = await seedLinked(stem: '数学必收题。', pointTitle: '数列');
      final physicsId = await seedLinked(
        stem: '物理必收题。',
        pointTitle: '动量',
        subjectKey: 'physics',
      );
      final excludedId = await seedLinked(stem: '被排除的题。', pointTitle: '概率');

      final result = await tool.run(invoke(<String, Object?>{
        'target_count': 10,
        'subject_keys': <String>['math'],
        'manual_include_question_ids': <String>[
          physicsId.$1,
          excludedId.$1,
          mathId.$1,
        ],
        'manual_exclude_question_ids': <String>[excludedId.$1],
      }));

      expect(result.ok, isTrue, reason: result.summary);
      final payload = payloadOf(result);
      expect(payload['manual_included_count'], 2);
      expect(
        payload['manual_conflict_question_ids'],
        <String>[excludedId.$1],
      );
      final ids = itemsOf(result).map((item) => item['question_id']).toSet();
      expect(ids, contains(mathId.$1));
      expect(ids, contains(physicsId.$1), reason: '必收绕过 subject_keys 过滤');
      expect(ids, isNot(contains(excludedId.$1)), reason: '排除优先于必收');
      expect(result.summary, contains('手工指定'));
      expect(result.summary, contains('按排除处理'));
    });

    test('target_count 装不下必收题：其余进 skipped 并写进摘要', () async {
      final a = await seedQuestion(stem: '必收题 A。');
      final b = await seedQuestion(stem: '必收题 B。');

      final result = await tool.run(invoke(<String, Object?>{
        'target_count': 1,
        'manual_include_question_ids': <String>[a, b],
      }));

      expect(result.ok, isTrue, reason: result.summary);
      final payload = payloadOf(result);
      expect(payload['manual_included_count'], 1);
      expect(payload['manual_skipped_question_ids'], hasLength(1));
      expect(result.summary, contains('装不下'));
    });

    test('候选池里没有的 id 进 missing 并如实说找不到', () async {
      await seedQuestion(stem: '唯一一道题。');

      final result = await tool.run(invoke(<String, Object?>{
        'manual_include_question_ids': <String>['q-does-not-exist'],
      }));

      expect(result.ok, isTrue, reason: result.summary);
      final payload = payloadOf(result);
      expect(
          payload['manual_missing_question_ids'], <String>['q-does-not-exist']);
      expect(result.summary, contains('找不到'));
    });

    test('形状不对 → 失败并指出具体哪里错', () async {
      Future<String> errorOf(Object? ids) async {
        final result = await tool.run(invoke(<String, Object?>{
          'manual_include_question_ids': ids,
        }));
        expect(result.ok, isFalse);
        return result.error!;
      }

      expect(await errorOf('q-1'), contains('必须是题目 id 的数组'));
      expect(await errorOf(<Object?>['q-1', 2]), contains('元素必须是字符串'));
      expect(await errorOf(<Object?>['q-1', '   ']), contains('不能有空字符串'));
    });

    test('空数组按不启用处理：四个手工键缺席', () async {
      await seedQuestion(stem: '一道题。');

      final result = await tool.run(invoke(<String, Object?>{
        'manual_include_question_ids': <String>[],
        'manual_exclude_question_ids': <String>[],
      }));

      expect(result.ok, isTrue, reason: result.summary);
      expect(payloadOf(result).containsKey('manual_included_count'), isFalse);
      expect(result.summary, isNot(contains('手工指定')));
    });

    test('schema 里声明了两个手工参数', () {
      final registry = ToolRegistry.forApp(
        db: db,
        tasks: TaskRepository(db),
        blocks: TimeBlockRepository(db),
        anki: anki,
        tags: tags,
      );
      final spec = registry.modelSpecs.firstWhere((s) => s.name == tool.name);
      final properties = spec.parameters['properties']! as Map<String, Object?>;
      for (final key in <String>[
        'manual_include_question_ids',
        'manual_exclude_question_ids',
      ]) {
        final schema = properties[key]! as Map<String, Object?>;
        expect(schema['type'], 'array');
        expect((schema['items']! as Map<String, Object?>)['type'], 'string');
      }
    });
  });

  group('质量体检（model_result.quality，轮次一百二十五）', () {
    Map<String, Object?> qualityOf(ToolResult result) =>
        payloadOf(result)['quality']! as Map<String, Object?>;

    List<String> qualityCodes(ToolResult result) => [
          for (final warning in qualityOf(result)['warnings']! as List<Object?>)
            (warning! as Map<String, Object?>)['code']! as String,
        ];

    test('空库：quality 是 empty_plan，摘要先说实话（题库里没题）', () async {
      final result = await tool.run(invoke(<String, Object?>{}));

      expect(result.ok, isTrue, reason: result.summary);
      final quality = qualityOf(result);
      expect(quality['schema'], 'mindnet.paper_quality/1');
      expect(quality['question_count'], 0);
      expect(qualityCodes(result), <String>['empty_plan']);
      expect(result.summary, contains('题库里还没有任何可用的题'));
    });

    test('凑不齐：fill_short 进 quality，摘要报质量体检三档计数', () async {
      await seedQuestion(stem: '第一道题。');
      await seedQuestion(stem: '第二道题。');

      final result = await tool.run(invoke(<String, Object?>{}));

      expect(result.ok, isTrue, reason: result.summary);
      expect(qualityCodes(result), contains('fill_short'));
      expect(qualityOf(result)['question_count'], 2);
      expect(result.summary, contains('质量体检：'));
      expect(result.summary, contains('最该看：'));
    });

    test('难度读数从题库候选回填：target_difficulty 拉远时出 far_from_target', () async {
      await seedQuestion(stem: '简单题一。', difficulty: 2);
      await seedQuestion(stem: '简单题二。', difficulty: 2);
      await seedQuestion(stem: '简单题三。', difficulty: 2);

      final result = await tool.run(invoke(<String, Object?>{
        'target_difficulty': 9,
      }));

      expect(result.ok, isTrue, reason: result.summary);
      final quality = qualityOf(result);
      final distribution = quality['difficulty_distribution']! as List<Object?>;
      expect(
        [
          for (final bucket in distribution)
            (bucket! as Map<String, Object?>)['key'],
        ],
        <String>['2.0'],
        reason: 'Plan 不保留难度，这条分布只能来自题库候选的 difficulty',
      );
      final far = (quality['warnings']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .singleWhere(
            (warning) => warning['code'] == 'difficulty_far_from_target',
          );
      expect((far['evidence']! as Map<String, Object?>)['mean'], '2.00');
      expect((far['evidence']! as Map<String, Object?>)['target'], '9.00');
      expect(result.summary, contains('难度偏离目标'));
    });

    test('学科中文名与题数同源：math 显示数学，question_count 与 item_count 一致', () async {
      await seedLinked(stem: '数学题一。', pointTitle: '数列');
      await seedLinked(
        stem: '物理题。',
        pointTitle: '动量',
        subjectKey: 'physics',
      );

      final result = await tool.run(invoke(<String, Object?>{}));

      expect(result.ok, isTrue, reason: result.summary);
      final payload = payloadOf(result);
      final quality = qualityOf(result);
      expect(quality['question_count'], payload['item_count']);
      final subjects = <String, String>{
        for (final bucket in quality['subject_distribution']! as List<Object?>)
          (bucket! as Map<String, Object?>)['key']! as String:
              (bucket as Map<String, Object?>)['label_zh']! as String,
      };
      expect(subjects['math'], '数学');
      expect(subjects['physics'], '物理');
    });
  });
}

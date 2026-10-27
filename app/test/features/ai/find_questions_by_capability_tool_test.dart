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

/// `find_questions_by_capability` 是"按能力动作找题"（轮次一百零六）的工具面，验收点：
///
///  1. **只读**：一次调用不改任何表，`ApprovalEngine` 在任何权限模式下都不逐条询问；
///  2. **口径与页面同源**：只认每道题**最新一条链**的动作序列；
///  3. **不出题**：结果全是库里已有的题，找不到就如实说没有；
///  4. 边界：不认识的 action key 失败并列出可用值、`limit` 钳位、空动作参数。
void main() {
  late AppDatabase db;
  late QuestionRepository questions;
  late FindQuestionsByCapabilityTool tool;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    questions = QuestionRepository(db);
    tool = FindQuestionsByCapabilityTool(db: db);
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
    String subjectKey = 'math',
    String sourceLevel = 'gaokao',
  }) async {
    final ingested = await questions.ingest(
      QuestionDraft(
        stem: stem,
        subjectKey: subjectKey,
        sourceLevel: sourceLevel,
      ),
    );
    return ingested.question.id;
  }

  Future<void> seedChain({
    required String questionId,
    required String chainId,
    required int createdAt,
    required List<String> actions,
  }) async {
    await db.into(db.reasoningChains).insert(
          ReasoningChainsCompanion.insert(
            id: chainId,
            questionId: questionId,
            createdAt: createdAt,
            summary: const Value(''),
            stepCount: Value(actions.length),
          ),
        );
    for (var i = 0; i < actions.length; i++) {
      await db.into(db.reasoningSteps).insert(
            ReasoningStepsCompanion.insert(
              id: '$chainId-step-$i',
              chainId: chainId,
              idx: i,
              goal: '第 $i 步',
              actionType: Value(actions[i]),
              createdAt: createdAt,
            ),
          );
    }
  }

  /// 整库指纹：只读工具不该让任何一行变化。
  Future<Map<String, Object?>> snapshot() async {
    final dump = <String, Object?>{};
    for (final table in await db.userTables()) {
      dump[table] = await db.dumpTable(table);
    }
    return dump;
  }

  test('在 ToolRegistry.forApp 里可达，且是只读工具（审批不逐条询问）', () {
    final registry = ToolRegistry.forApp(
      db: db,
      tasks: TaskRepository(db),
      blocks: TimeBlockRepository(db),
      anki: AnkiRepository(db),
      tags: TagRepository(db),
    );
    expect(
      registry.byName('find_questions_by_capability'),
      isA<FindQuestionsByCapabilityTool>(),
    );
    for (final mode in AiPermissionMode.values) {
      final decision = ApprovalEngine(mode: mode).forInvocation(tool, const {});
      expect(
        decision.disposition,
        isNot(ToolDisposition.individualApproval),
        reason: 'mode ${mode.name} 不该为只读工具逐条询问',
      );
    }
    expect(tool.readOnly, isTrue);
  });

  test('不认识的能力动作：失败并列出可用 key', () async {
    final result = await tool.run(invoke({'action_type': 'not_a_move'}));

    expect(result.ok, isFalse);
    expect(result.error, contains('不认识的能力动作'));
    expect(result.error, contains('case_split'));
  });

  test('缺 action_type / 空串：参数错（模型能读懂的硬错）', () async {
    expect(
      () => tool.run(invoke(const <String, Object?>{})),
      throwsA(isA<ToolArgError>()),
    );
    expect(
      () => tool.run(invoke({'action_type': '   '})),
      throwsA(isA<ToolArgError>()),
    );
  });

  test('命中：题干摘要 + 学科 + 链上动作中文名；只认最新一条链', () async {
    final hit = await seedQuestion(stem: '抽取两次，求条件概率。', subjectKey: 'math');
    final other = await seedQuestion(stem: '另一道题的题干。', subjectKey: 'physics');
    await seedChain(
      questionId: hit,
      chainId: 'chain-hit',
      createdAt: 10,
      actions: const <String>['case_split', 'sanity_check'],
    );
    await seedChain(
      questionId: other,
      chainId: 'chain-other',
      createdAt: 10,
      actions: const <String>['induction'],
    );
    // hit 的旧链里有 induction，但最新一条没有 → 不该被 induction 查到。
    await seedChain(
      questionId: hit,
      chainId: 'chain-old',
      createdAt: 1,
      actions: const <String>['induction'],
    );

    final result = await tool.run(invoke({'action_type': 'case_split'}));

    expect(result.ok, isTrue, reason: result.summary);
    expect(result.summary, contains('分类讨论'));
    expect(result.summary, contains('抽取两次，求条件概率。'));
    expect(result.summary, contains('数学'));

    final payload = result.modelResult! as Map<String, Object?>;
    final query = payload['query']! as Map<String, Object?>;
    expect(query['action_types'], <String>['case_split']);
    expect(query['action_labels_zh'], <String>['分类讨论']);
    expect(query['match'], 'any');
    expect(payload['returned'], 1);
    expect(payload['candidates'], 1);
    expect(payload['rule'], 'latest_chain_only');
    final rows = payload['questions']! as List<Object?>;
    expect(rows, hasLength(1));
    final row = rows.single! as Map<String, Object?>;
    expect(row['stem'], '抽取两次，求条件概率。');
    expect(row['subject'], '数学');
    expect(row['source_level'], 'gaokao');
    expect(row['matched_action_types'], <String>['case_split']);
    expect(row['matched_actions_zh'], <String>['分类讨论']);
    expect(row['action_labels_zh'], <String>['分类讨论', '回代检验']);

    // 旧链里出现过 induction，但最新链没有 → 不被算作命中。
    final induction = await tool.run(invoke({'action_type': 'induction'}));
    final inductionPayload = induction.modelResult! as Map<String, Object?>;
    final inductionRows = inductionPayload['questions']! as List<Object?>;
    expect(
      [for (final row in inductionRows) (row! as Map<String, Object?>)['id']],
      isNot(contains(hit)),
    );
  });

  test('没有解过含这个动作的题：如实说没有，不编题', () async {
    final result = await tool.run(invoke({'action_type': 'induction'}));

    expect(result.ok, isTrue);
    expect(result.summary, contains('还没有解过含「归纳」的题'));
    expect(result.summary, contains('不凭空出题'));
    final payload = result.modelResult! as Map<String, Object?>;
    expect(payload['returned'], 0);
    expect(payload['questions'], isEmpty);
  });

  test('limit 钳位：默认 10，超上限按 50，0/负按默认；摘要说明只给前几条', () async {
    for (var i = 0; i < 3; i++) {
      final id = await seedQuestion(stem: '第 $i 道分类讨论题。');
      await seedChain(
        questionId: id,
        chainId: 'chain-$i',
        createdAt: 10,
        actions: const <String>['case_split'],
      );
    }

    final result =
        await tool.run(invoke({'action_type': 'case_split', 'limit': 2}));
    final payload = result.modelResult! as Map<String, Object?>;
    expect(payload['returned'], 2);
    expect(payload['candidates'], 3);
    expect(result.summary, contains('共 3 道'));

    final zero =
        await tool.run(invoke({'action_type': 'case_split', 'limit': 0}));
    expect(
      (zero.modelResult! as Map<String, Object?>)['returned'],
      3,
      reason: '0 钳回默认值 10，比 3 大 → 全给',
    );
  });

  test('一次调用不改任何表：整库指纹前后相同', () async {
    final id = await seedQuestion(stem: '只读验证用的题。');
    await seedChain(
      questionId: id,
      chainId: 'chain-ro',
      createdAt: 10,
      actions: const <String>['case_split'],
    );
    final before = await snapshot();

    final result = await tool.run(invoke({'action_type': 'case_split'}));

    expect(result.ok, isTrue);
    expect(await snapshot(), before);
  });

  test('组合查询：match=all 要求每个动作都在最新链里，subject_key 再筛学科', () async {
    final both = await seedQuestion(stem: '两个动作都用上的数学题。');
    final splitOnly = await seedQuestion(stem: '只用分类讨论的数学题。');
    final physics =
        await seedQuestion(stem: '只用分类讨论的物理题。', subjectKey: 'physics');
    await seedChain(
      questionId: both,
      chainId: 'chain-both',
      createdAt: 10,
      actions: const <String>['case_split', 'sanity_check'],
    );
    await seedChain(
      questionId: splitOnly,
      chainId: 'chain-split',
      createdAt: 10,
      actions: const <String>['case_split'],
    );
    await seedChain(
      questionId: physics,
      chainId: 'chain-phys',
      createdAt: 10,
      actions: const <String>['case_split'],
    );

    // all：两个动作都得在最新链里 → 只有 both。
    final all = await tool.run(invoke({
      'action_types': <String>['case_split', 'sanity_check'],
      'match': 'all',
    }));
    final allPayload = all.modelResult! as Map<String, Object?>;
    expect(
      [
        for (final row in allPayload['questions']! as List<Object?>)
          (row! as Map<String, Object?>)['id']
      ],
      <String>[both],
    );
    expect(all.summary, contains('同时含'));
    expect(allPayload['candidates'], 1);

    // any（默认）：三道都算。
    final any = await tool.run(invoke({
      'action_types': <String>['case_split', 'sanity_check'],
    }));
    expect(
      (any.modelResult! as Map<String, Object?>)['candidates'],
      3,
    );

    // 动作 + 学科：只剩物理那道。
    final bySubject = await tool.run(invoke({
      'action_type': 'case_split',
      'subject_key': 'physics',
    }));
    final subjectPayload = bySubject.modelResult! as Map<String, Object?>;
    expect(
      [
        for (final row in subjectPayload['questions']! as List<Object?>)
          (row! as Map<String, Object?>)['id']
      ],
      <String>[physics],
    );
    expect((subjectPayload['query']! as Map<String, Object?>)['subject'], '物理');

    // 只按学科（不按动作）：数学两道都解过链，都算。
    final mathOnly = await tool.run(invoke({'subject_key': 'math'}));
    expect((mathOnly.modelResult! as Map<String, Object?>)['candidates'], 2);
    expect(mathOnly.summary, contains('解过链的「数学」'));

    // 两个条件都空 → 参数错；match 非法 → 参数错。
    expect(
      () => tool.run(invoke(const <String, Object?>{})),
      throwsA(isA<ToolArgError>()),
    );
    expect(
      () => tool.run(invoke({
        'action_type': 'case_split',
        'match': 'sometimes',
      })),
      throwsA(isA<ToolArgError>()),
    );
  });

  test('subject_keys 多学科：任一命中、归一化、与 subject_key 兼容别名', () async {
    final math = await seedQuestion(stem: '数学分类讨论题。', subjectKey: 'math');
    final physics = await seedQuestion(stem: '物理分类讨论题。', subjectKey: 'physics');
    final chemistry =
        await seedQuestion(stem: '化学分类讨论题。', subjectKey: 'chemistry');
    for (final id in <String>[math, physics, chemistry]) {
      await seedChain(
        questionId: id,
        chainId: 'chain-$id',
        createdAt: 10,
        actions: const <String>['case_split'],
      );
    }

    List<String> idsOf(ToolResult result) => <String>[
          for (final row in (result.modelResult!
              as Map<String, Object?>)['questions']! as List<Object?>)
            (row! as Map<String, Object?>)['id']! as String,
        ];
    Map<String, Object?> queryOf(ToolResult result) =>
        (result.modelResult! as Map<String, Object?>)['query']!
            as Map<String, Object?>;

    // 多个学科 = 任一命中（数学 + 物理），化学不在结果里。
    final multi = await tool.run(invoke({
      'action_types': <String>['case_split'],
      'subject_keys': <String>[' physics ', 'math', 'physics'],
    }));
    expect(multi.ok, isTrue, reason: multi.summary);
    expect(idsOf(multi).toSet(), <String>{math, physics});
    final multiQuery = queryOf(multi);
    expect(multiQuery['subject_keys'], <String>['math', 'physics']);
    expect(multiQuery['subjects'], <String>['数学', '物理']);
    expect(multiQuery['subject_key'], '', reason: '多学科时兼容字段留空');
    expect(multiQuery['subject'], '');
    expect(multi.summary, contains('数学'));
    expect(multi.summary, contains('物理'));
    expect(multi.summary, isNot(contains('化学')));

    // 只按学科（不按动作）：多学科集合同样可用，摘要给中文名。
    final subjectsOnly = await tool.run(invoke({
      'subject_keys': <String>['chemistry', 'physics'],
    }));
    expect(subjectsOnly.ok, isTrue, reason: subjectsOnly.summary);
    expect(idsOf(subjectsOnly).toSet(), <String>{physics, chemistry});
    expect(subjectsOnly.summary, contains('物理'));
    expect(subjectsOnly.summary, contains('化学'));

    // 兼容别名：只给 subject_key 时按单学科走，旧调用不破。
    final alias = await tool.run(invoke({
      'action_type': 'case_split',
      'subject_key': 'physics',
    }));
    expect(idsOf(alias), <String>[physics]);
    final aliasQuery = queryOf(alias);
    expect(aliasQuery['subject_key'], 'physics');
    expect(aliasQuery['subject'], '物理');
    expect(aliasQuery['subject_keys'], <String>['physics']);

    // 两者都给：subject_keys 为准，subject_key 被忽略，并如实回报实际用的学科。
    final precedence = await tool.run(invoke({
      'action_type': 'case_split',
      'subject_keys': <String>['math'],
      'subject_key': 'physics',
    }));
    expect(idsOf(precedence), <String>[math]);
    final precedenceQuery = queryOf(precedence);
    expect(precedenceQuery['subject_keys'], <String>['math']);
    expect(precedenceQuery['subject_key'], 'math');

    // subject_keys 全空白 = 没给：回落到 subject_key 别名。
    final blankArray = await tool.run(invoke({
      'action_type': 'case_split',
      'subject_keys': <String>['', '  '],
      'subject_key': 'chemistry',
    }));
    expect(queryOf(blankArray)['subject_keys'], <String>['chemistry']);
    expect(idsOf(blankArray).toSet(), <String>{chemistry});

    // 动作与学科都空（只给空白 subject_keys）→ 参数错，不导库。
    expect(
      () => tool.run(invoke({
        'subject_keys': <String>['', '  ']
      })),
      throwsA(isA<ToolArgError>()),
    );

    // 参数 schema 暴露 subject_keys 数组与 subject_key 兼容别名。
    final properties = tool.parameters['properties']! as Map<String, Object?>;
    final subjectKeysSchema =
        properties['subject_keys']! as Map<String, Object?>;
    expect(subjectKeysSchema['type'], 'array');
    expect(properties['subject_key'], isA<Map<String, Object?>>());
  });
}

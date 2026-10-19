import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/data/repositories/settings_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/data/repositories/time_block_repository.dart';
import 'package:furnace/features/ai/domain/ai_tool.dart';
import 'package:furnace/features/ai/domain/approval_engine.dart';
import 'package:furnace/features/ai/domain/tool_registry.dart';
import 'package:furnace/features/ai/tools/today_tools.dart';

/// `plan_today` is the caller that turns the plan core (Q32a) into something the
/// model can ask for, so these tests are about three properties:
///
///  1. it is **read-only** - it writes nothing and `ApprovalEngine` never asks
///     per call for it;
///  2. it only **formats** - the ordering and the prices come from
///     `TodayPlanner` / `ProblemEvaluator`;
///  3. it survives the boundaries (an empty day, a card that is not due, a
///     problem with nothing to price).
void main() {
  late AppDatabase db;
  late AnkiRepository anki;
  late TagRepository tags;
  late PlanTodayTool tool;

  final moment = DateTime.fromMillisecondsSinceEpoch(1700000000000);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    anki = AnkiRepository(db);
    tags = TagRepository(db);
    tool = PlanTodayTool(
      ankiRepository: anki,
      tagRepository: tags,
      database: db,
      clock: () => moment,
    );
  });

  tearDown(() async {
    await db.close();
  });

  ToolInvocation invoke(Map<String, Object?> args) => ToolInvocation(
        toolName: tool.name,
        action: tool.name,
        arguments: args,
      );

  Map<String, Object?> problem(String id, {List<String> kps = const []}) => {
        'id': id,
        'stem': '题干 $id',
        'knowledge_point_ids': kps,
      };

  /// A knowledge point with a reviewed unit (so the model has history to read)
  /// and a due date in the past - i.e. a card that is due right now.
  Future<String> duePoint(
    String title, {
    double stability = 5,
    double difficulty = 5,
    int daysAgo = 6,
    Duration dueIn = const Duration(days: -3),
  }) async {
    final point = await anki.createKnowledgePoint(
      title: title,
      content: '$title在系统不受外力时守恒。',
    );
    final state = await anki.getOrCreateUnitCardState(point.id, 'essay');
    await anki.updateUnitCardState(
      state.id,
      repetitions: 3,
      stability: stability,
      difficulty: difficulty,
      dueAt: moment.add(dueIn).millisecondsSinceEpoch,
      lastReviewedAt:
          moment.subtract(Duration(days: daysAgo)).millisecondsSinceEpoch,
    );
    return point.id;
  }

  /// 题库里的一道真题（有答案、有解析，配题推荐的候选）。
  Future<String> seedQuestion({String stem = '已知函数求单调区间'}) async {
    final ingested = await QuestionRepository(db).ingest(
      QuestionDraft(
        stem: stem,
        answer: 'B',
        solution: '先求导再判号',
        subjectKey: '数学',
        sourceLevel: 'gaokao',
      ),
    );
    return ingested.question.id;
  }

  Future<String> seedKnowledgePoint(String title) async =>
      (await anki.createKnowledgePoint(title: title, content: '')).id;

  /// 题目覆盖某个知识点的方式：两者挂**同一个**标签（与题库其它读表同一口径）。
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

  /// 一条已落库的思维链：goal/action/stuckRisk 都按真实表结构写。
  Future<void> seedChain({
    required String chainId,
    required String questionId,
    List<({String action, double? risk, List<String> hints})> steps = const [],
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
              knowledgeHints: Value(jsonEncode(steps[i].hints)),
              createdAt: 1,
            ),
          );
    }
  }

  Map<String, Object?>? studyPlanPayloadOf(ToolResult result) {
    final raw = (result.modelResult! as Map<String, Object?>)['study_plan'];
    if (raw == null) return null;
    return (raw as Map).cast<String, Object?>();
  }

  List<Map<String, Object?>> studyStepsOf(ToolResult result) {
    final plan = studyPlanPayloadOf(result);
    if (plan == null) return const <Map<String, Object?>>[];
    return [
      for (final raw in plan['steps']! as List)
        (raw as Map).cast<String, Object?>(),
    ];
  }

  Map<String, Object?> payloadOf(ToolResult result) =>
      result.modelResult! as Map<String, Object?>;

  List<Map<String, Object?>> actionsOf(ToolResult result) => [
        for (final raw in payloadOf(result)['actions']! as List)
          (raw as Map).cast<String, Object?>(),
      ];

  group('read-only by construction', () {
    test('ApprovalEngine never asks per call, in any mode', () {
      for (final mode in AiPermissionMode.values) {
        final decision = ApprovalEngine(mode: mode)
            .forInvocation(tool, {'problems': <Object?>[]});
        expect(decision.risk, ToolRisk.write);
        expect(decision.reversible, isTrue);
        expect(decision.disposition, isNot(ToolDisposition.individualApproval),
            reason: 'mode ${mode.name} must not ask one by one for a read');
      }
      expect(tool.riskFor(''), ToolRisk.write); // unused: no actions
      expect(tool.readOnly, isTrue);
      expect(tool.name, 'plan_today');
    });

    test('the app registry actually offers it (a tool not in the list is dead)',
        () {
      final registry = ToolRegistry.forApp(
        db: db,
        tasks: TaskRepository(db),
        blocks: TimeBlockRepository(db),
        anki: anki,
        tags: tags,
      );
      expect(registry.byName('plan_today'), isNotNull);
    });
  });

  test('an empty day is an empty list, and it says so', () async {
    final result = await tool.run(invoke(const {}));

    expect(result.ok, isTrue);
    expect(result.summary, contains('清单是空的'));
    final payload = payloadOf(result);
    expect(payload['actions'], isEmpty);
    expect(payload['uncalibrated'], isTrue);
    expect(payload['considered'], 0);
  });

  test('a card you are about to forget is on the list, priced in retention',
      () async {
    await duePoint('动量守恒');

    final result = await tool.run(invoke(const {}));
    final actions = actionsOf(result);

    expect(actions, hasLength(1));
    final action = actions.single;
    expect(action['kind'], 'review');
    expect(action['title'], '动量守恒');
    expect(action['metric'], 'retention');
    expect(action['value'], isA<double>());
    expect((action['gain']! as num).toDouble(), greaterThan(0));
    expect((action['why']! as String), contains('复习这张卡'));
    // The summary is what the model reads back to the user.
    expect(result.summary, contains('今天做这几件事（1 件）'));
    expect(result.summary, contains('动量守恒'));
    expect(result.summary, contains('未标定'));
  });

  test('a card that is not due yet is not on today\'s list', () async {
    await duePoint('下周期中范围', dueIn: const Duration(days: 3));

    final result = await tool.run(invoke(const {}));
    expect(actionsOf(result), isEmpty);
  });

  test('candidate problems are evaluated and can be priced by reachability',
      () async {
    // Same fixture as `evaluate_problem_fit`'s "priced dead end": the labels are
    // inserted with ordered ids because rule 4 of `CognitiveGraph.fromTags` gives
    // each pair of top-level tags one sibling edge, direction decided by id
    // ascending - with generated ids the island would land downstream of the lit
    // label and be diagnosed `weak` instead of `empty`.
    const islandTagId = 'tag-a-island';
    const litTagId = 'tag-b-lit';
    final litId = await duePoint('动量守恒');
    final islandId = await duePoint('孤立知识点');
    await db.into(db.tags).insert(
          TagsCompanion.insert(
            id: islandTagId,
            name: '光学',
            createdAt: 1,
            updatedAt: 1,
          ),
        );
    await db.into(db.tags).insert(
          TagsCompanion.insert(
            id: litTagId,
            name: '力学',
            createdAt: 1,
            updatedAt: 1,
          ),
        );
    await tags.addTagToObject(
      tagId: litTagId,
      objectType: 'knowledge_point',
      objectId: litId,
    );
    await tags.addTagToObject(
      tagId: islandTagId,
      objectType: 'knowledge_point',
      objectId: islandId,
    );

    final result = await tool.run(invoke({
      'problems': [
        problem('p1', kps: [islandId]),
      ],
      // The lit label: `add_in_edges` can only price an island when *something*
      // is lit to link from, so the model says which card is in mind.
      'start_knowledge_point_ids': [litId],
    }));
    final actions = actionsOf(result);

    final practice = actions.singleWhere((a) => a['kind'] == 'practice');
    expect(practice['id'], 'p1');
    expect(practice['title'], '题干 p1');
    expect(practice['metric'], 'reachability');
    expect((practice['value']! as num).toDouble(), greaterThan(0));
    expect((practice['cost']! as num).toDouble(), 2.0);
    expect(result.summary, contains('练习'));
    final payload = payloadOf(result);
    expect(payload['mixes_metrics'], isTrue); // retention cards + a
    // reachability problem in one list: the plan says so instead of pretending
    // the two prices are the same unit.
  });

  test('max_actions keeps the top of the list and reports the rest', () async {
    await duePoint('动量守恒');
    await duePoint('电磁感应');

    final result = await tool.run(invoke({'max_actions': 1}));
    final payload = payloadOf(result);

    expect(actionsOf(result), hasLength(1));
    expect(payload['considered'], 2);
    expect(result.summary, contains('另有 1 件排在清单外'));
  });

  test('用户拖过的定价参数（§3 第 8 行第一个滑块）在 plan_today 里也算数', () async {
    await duePoint('动量守恒');
    final settings = SettingsRepository(db);
    await settings.ensureSettings(language: 'zh');
    await settings.updateGoalBeta(1.2);

    final result = await tool.run(invoke({
      'problems': [problem('p1')],
    }));

    // 定价这一跑与 `evaluate_problem_fit` 走的是同一条装配，用户拖的值
    // 就在这里生效；摘要里说清它是谁定的，别把用户调过的数当出厂值。
    expect(result.summary, contains('用户调过的参数'));
    expect(result.summary, contains('context.goal.beta_goal=1.2'));
  });

  group('今日学习计划（study_plan）', () {
    test('空库：单步 noData、0 分钟，不虚构计划', () async {
      final result = await tool.run(invoke(const {}));

      final plan = studyPlanPayloadOf(result)!;
      expect(plan['is_empty'], isFalse, reason: 'noData 也是一条计划，不是空计划');
      expect(plan['total_minutes'], 0);
      expect(plan['skipped_step_count'], 0);
      expect(plan['focus_knowledge_point_ids'], isEmpty);
      final steps = studyStepsOf(result);
      expect(steps, hasLength(1));
      expect(steps.single['kind'], 'noData');
      expect(steps.single['estimated_minutes'], 0);
      expect(steps.single['priority'], 600);
      // 摘要句如实说「今天没有可依据的数据」，不写空话。
      expect(result.summary, contains('今天没有可依据的数据'));
      expect(result.summary, contains('今天预计 0 分钟、1 步'));
      // 旧清单字段一个不少。
      expect(payloadOf(result)['actions'], isEmpty);
    });

    test('有题 + 三步高危链：练习步骤真的带上 question_ids', () async {
      final questionId = await seedQuestion();
      final pointId = await seedKnowledgePoint('函数单调性');
      await linkKnowledgePoint(pointId: pointId, questionId: questionId);
      await seedChain(
        chainId: 'chain-1',
        questionId: questionId,
        steps: [
          (action: 'case_split', risk: 0.8, hints: <String>[pointId]),
          (action: 'case_split', risk: 0.8, hints: <String>[pointId]),
          (action: 'case_split', risk: 0.8, hints: <String>[pointId]),
        ],
      );

      final result = await tool.run(invoke(const {}));
      final plan = studyPlanPayloadOf(result)!;
      final steps = studyStepsOf(result);
      final practice =
          steps.singleWhere((s) => s['kind'] == 'practiceQuestions');

      expect(practice['question_ids'], [questionId]);
      expect(practice['action_type'], 'case_split');
      expect(practice['knowledge_point_ids'], [pointId]);
      expect(practice['estimated_minutes'], 2);
      expect(plan['total_minutes'], 2);
      expect(plan['focus_knowledge_point_ids'], [pointId]);
      // 摘要句：真实的分钟数 + 第一步标题，不重排、不改数字。
      expect(result.summary, contains('今天预计 2 分钟、'));
      expect(result.summary, contains(practice['title_zh']! as String));
      // 旧清单口径不变：没有到期卡，也没有模型这次给的候选题。
      expect(actionsOf(result), isEmpty);
    });

    test('到期读数为 0 时没有 reviewDueCards；真有到期卡时才出现', () async {
      await seedQuestion();
      final none = await tool.run(invoke(const {}));
      expect(
        studyStepsOf(none).map((s) => s['kind']),
        isNot(contains('reviewDueCards')),
      );

      await duePoint('动量守恒');
      final withCards = await tool.run(invoke(const {}));
      final steps = studyStepsOf(withCards);
      final cards = steps.where((s) => s['kind'] == 'reviewDueCards').toList();
      expect(cards, hasLength(1));
      expect(cards.single['card_count'], 1);
      expect(cards.single['estimated_minutes'], 1);
      expect(cards.single['priority'], 100);
      expect(studyPlanPayloadOf(withCards)!['total_minutes'],
          greaterThanOrEqualTo(1));
    });

    test('modelResult 键齐全：旧清单字段保留，study_plan 键序固定', () async {
      await duePoint('动量守恒');
      final result = await tool.run(invoke(const {}));
      final payload = payloadOf(result);

      expect(
        payload.keys,
        containsAll(<String>[
          'uncalibrated',
          'now_hours',
          'horizon_hours',
          'considered',
          'mixes_metrics',
          'actions',
          'study_plan',
        ]),
      );
      final plan = studyPlanPayloadOf(result)!;
      expect(
        plan.keys,
        orderedEquals(<String>[
          'steps',
          'total_minutes',
          'focus_knowledge_point_ids',
          'skipped_step_count',
          'is_empty',
        ]),
      );
      final step = studyStepsOf(result).first;
      expect(
        step.keys,
        orderedEquals(<String>[
          'kind',
          'priority',
          'title_zh',
          'detail_zh',
          'estimated_minutes',
          'action_type',
          'knowledge_point_ids',
          'question_ids',
          'card_count',
        ]),
      );
      expect(result.summary, contains('今天预计'));
      expect(result.summary, contains('先做：'));
    });
  });
}

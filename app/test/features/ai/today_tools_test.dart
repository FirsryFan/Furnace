import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
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
}

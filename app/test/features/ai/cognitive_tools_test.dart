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
import 'package:furnace/features/ai/tools/cognitive_tools.dart';

/// `evaluate_problem_fit` is the caller that keeps 用途 1 from being dead code,
/// so three properties are what these tests are about:
///
///  1. it is **read-only** - it writes nothing, and `ApprovalEngine` never asks
///     per call for it;
///  2. it only **formats** - the verdicts come from `ProblemEvaluator`, and the
///     wire names are the contract's;
///  3. it survives the boundaries (no candidates, unknown tags, missing
///     knowledge points, a single candidate).
void main() {
  late AppDatabase db;
  late AnkiRepository anki;
  late TagRepository tags;
  late EvaluateProblemFitTool tool;

  final moment = DateTime.fromMillisecondsSinceEpoch(1700000000000);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    anki = AnkiRepository(db);
    tags = TagRepository(db);
    tool = EvaluateProblemFitTool(
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

  Map<String, Object?> problem(
    String id, {
    List<String> kps = const [],
    double? hint,
  }) =>
      {
        'id': id,
        'stem': '题干 $id',
        'knowledge_point_ids': kps,
        if (hint != null) 'difficulty_hint': hint,
      };

  /// A knowledge point with a reviewed unit (so the model has history to read).
  Future<String> reviewedPoint(
    String title, {
    double stability = 5,
    double difficulty = 5,
    int daysAgo = 6,
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
      dueAt: moment.subtract(const Duration(days: 3)).millisecondsSinceEpoch,
      lastReviewedAt:
          moment.subtract(Duration(days: daysAgo)).millisecondsSinceEpoch,
    );
    return point.id;
  }

  group('read-only by construction', () {
    test('ApprovalEngine never asks per call, in any mode', () {
      for (final mode in AiPermissionMode.values) {
        final decision = const ApprovalEngine(mode: AiPermissionMode.plan)
            .forInvocation(tool, {'problems': <Object?>[]});
        final inMode =
            ApprovalEngine(mode: mode).forInvocation(tool, const {});
        expect(inMode.risk, ToolRisk.write);
        expect(inMode.reversible, isTrue);
        expect(inMode.disposition,
            isNot(ToolDisposition.individualApproval),
            reason: 'mode ${mode.name} must not ask one by one for a read');
        expect(decision.disposition,
            isNot(ToolDisposition.individualApproval));
      }
      expect(tool.riskFor(''), ToolRisk.write); // unused: no actions
      expect(tool.reversibleFor(''), isTrue);
      expect(tool.availableOnCurrentPlatform, isTrue);
    });

    test('a call leaves every table untouched', () async {
      final point = await reviewedPoint('动量');
      await tags.createTag(name: '力学');
      final before = await _snapshot(db);

      final result = await tool.run(invoke({
        'problems': [problem('p1', kps: [point])],
      }));

      expect(result.ok, isTrue);
      expect(await _snapshot(db), before,
          reason: 'the tool must not write: same rows, same values');
    });
  });

  group('output contract', () {
    test('verdicts use the contract wire names and carry a reason', () async {
      final strong = await reviewedPoint('动量', stability: 300);
      // MindNet's forgetting curve is a power curve, so "almost gone"
      // (R <= 0.25) needs a large `t / S`: 90 days against a stability of
      // 0.002 days puts R near 0.19, while 6 days would still read ~0.29.
      final gone = await reviewedPoint(
        '冲量',
        stability: 0.002,
        difficulty: 8.5,
        daysAgo: 90,
      );

      final result = await tool.run(invoke({
        'problems': [
          problem('strong', kps: [strong]),
          problem('gone', kps: [gone]),
        ],
      }));

      final payload = result.modelResult! as Map<String, Object?>;
      final problems = payload['problems']! as List;
      final byId = {
        for (final entry in problems)
          (entry as Map)['id'] as String: entry,
      };
      expect(byId.keys.toSet(), {'strong', 'gone'});
      expect(byId['strong']!['verdict'], 'too_easy');
      expect(byId['gone']!['verdict'], 'too_hard');
      expect(byId['strong']!['reason'], isA<String>());
      expect((byId['strong']!['reason'] as String).isNotEmpty, isTrue);
      expect(byId['strong']!['rank_key'], isA<double>());
      expect(result.summary, contains('too_easy'));
      // The list is ranked, not merely returned.
      final ranks = [
        for (final entry in problems) (entry as Map)['rank_key'] as double,
      ];
      expect(ranks, orderedEquals([...ranks]..sort((a, b) => b.compareTo(a))));
    });

    test('the fast layer runs from the tag tree and reports its gaps',
        () async {
      // The graph's nodes come from *tags*, while the memory rows come from
      // *knowledge points*; the diffusion can only speak about a candidate
      // whose id is in both spaces, so this test aligns them explicitly (two
      // rows sharing one id) and thereby exercises the tierB path end to end.
      // A tag with no edges is a node nothing can drive into - the fast layer's
      // `empty`, i.e. a dead end for 用途 1.
      const sharedId = 'kp_and_tag';
      await db.into(db.knowledgePoints).insert(
            KnowledgePointsCompanion.insert(
              id: sharedId,
              title: '孤立知识点',
              content: '孤立知识点在系统不受外力时守恒。',
              createdAt: 1,
              updatedAt: 1,
            ),
          );
      await db.into(db.tags).insert(
            TagsCompanion.insert(
              id: sharedId,
              name: '孤立知识点',
              createdAt: 1,
              updatedAt: 1,
            ),
          );
      final state = await anki.getOrCreateUnitCardState(sharedId, 'essay');
      await anki.updateUnitCardState(
        state.id,
        repetitions: 3,
        stability: 5,
        difficulty: 5,
        lastReviewedAt:
            moment.subtract(const Duration(days: 6)).millisecondsSinceEpoch,
      );

      final result = await tool.run(invoke({
        'problems': [problem('p1', kps: [sharedId])],
      }));

      final payload = result.modelResult! as Map<String, Object?>;
      expect(payload['fast_layer_ran'], isTrue);
      final entry = (payload['problems']! as List).single as Map;
      expect(entry['verdict'], 'out_of_scope');
      expect((entry['diagnosis'] as Map)[sharedId], 'empty');
      // The node got its ms from the card row (R0), so it is not reported as
      // "not provided".
      expect(payload['nodes_without_ms'], isNot(contains(sharedId)));
    });

    test('difficulty_hint is a prior, never the model difficulty', () async {
      final strong = await reviewedPoint('动量', stability: 300);

      final result = await tool.run(invoke({
        'problems': [
          // Same knowledge point, an extremely hard self-reported hint: with
          // history present the model's numbers decide (§6.3).
          problem('hinted', kps: [strong], hint: 0.99),
        ],
      }));

      final payload = result.modelResult! as Map<String, Object?>;
      final entry = (payload['problems']! as List).single as Map;
      expect(entry['verdict'], 'too_easy');
    });
  });

  group('boundaries', () {
    test('an empty candidate list answers instead of failing', () async {
      final result = await tool.run(invoke({'problems': <Object?>[]}));
      expect(result.ok, isTrue);
      expect((result.modelResult! as Map)['returned'], 0);
      expect(result.summary, contains('没有可评估的题'));
    });

    test('tags outside the graph do not crash the diffusion', () async {
      final point = await reviewedPoint('动量');
      await tags.createTag(name: '力学');

      final result = await tool.run(invoke({
        'problems': [
          problem('p1', kps: [point, 'not-a-tag']),
        ],
        'start_knowledge_point_ids': ['not-a-tag'],
      }));

      expect(result.ok, isTrue);
      final entry = ((result.modelResult! as Map)['problems']! as List).single
          as Map;
      expect(entry['knowledge_point_ids'], [point, 'not-a-tag']);
      expect(entry['judged_knowledge_point_ids'], [point]);
    });

    test('a knowledge point with no history is judged without a crash',
        () async {
      final point = await anki.createKnowledgePoint(
        title: '从未复习',
        content: '从未复习在系统不受外力时守恒。',
      );

      final result = await tool.run(invoke({
        'problems': [problem('p1', kps: [point.id])],
      }));

      expect(result.ok, isTrue);
      final entry = ((result.modelResult! as Map)['problems']! as List).single
          as Map;
      expect(entry['judged_knowledge_point_ids'], isEmpty);
      expect(entry['verdict'], 'zpd');
    });

    test('a single candidate works and the limit is respected', () async {
      final point = await reviewedPoint('动量');
      final result = await tool.run(invoke({
        'problems': [
          problem('p1', kps: [point]),
          problem('p2', kps: [point]),
        ],
        'limit': 1,
      }));

      final payload = result.modelResult! as Map<String, Object?>;
      expect(payload['returned'], 1);
      expect(payload['truncated'], isTrue);
    });
  });

  group('registration', () {
    test('the tool is in the app tool list, with its schema', () async {
      // The app's own list, assembled the way the provider assembles it: a tool
      // that is missing here is unreachable by the model, i.e. dead code.
      final appRegistry = ToolRegistry.forApp(
        db: db,
        tasks: TaskRepository(db),
        blocks: TimeBlockRepository(db),
        anki: anki,
        tags: tags,
        clock: () => moment,
      );

      expect(appRegistry.byName('evaluate_problem_fit'),
          isA<EvaluateProblemFitTool>());
      expect(appRegistry.forCurrentPlatform.map((registered) => registered.name),
          contains('evaluate_problem_fit'));
      final spec = appRegistry.modelSpecs
          .firstWhere((s) => s.name == 'evaluate_problem_fit');
      expect(spec.description, contains('只读'));
      final parameters = spec.parameters;
      expect(parameters['type'], 'object');
      expect(parameters['required'], ['problems']);
      final properties = parameters['properties']! as Map;
      expect(properties.keys.toSet(),
          {'problems', 'start_knowledge_point_ids', 'now', 'limit'});
      // …and the pre-existing tools are still registered.
      expect(appRegistry.byName('query_tasks'), isNotNull);
      expect(appRegistry.byName('manage_task'), isNotNull);
    });

    test('the tool shows up in the model-facing list with its schema',
        () async {
      final registry = ToolRegistry([tool]);

      expect(registry.byName('evaluate_problem_fit'), same(tool));
      expect(registry.forCurrentPlatform, contains(tool));
      final spec = registry.modelSpecs.single;
      expect(spec.name, 'evaluate_problem_fit');
      expect(spec.description, contains('只读'));
      final parameters = spec.parameters;
      expect(parameters['type'], 'object');
      expect(parameters['required'], ['problems']);
      final properties = parameters['properties']! as Map;
      expect(properties.keys.toSet(),
          {'problems', 'start_knowledge_point_ids', 'now', 'limit'});
    });
  });
}

/// A cheap "did anything change" fingerprint: row counts plus the full card
/// state table rendered deterministically. Reading it does not write.
Future<String> _snapshot(AppDatabase db) async {
  final cards = await db.select(db.cardStates).get();
  final points = await db.select(db.knowledgePoints).get();
  final tagRows = await db.select(db.tags).get();
  final buffer = StringBuffer()
    ..writeln('kp=${points.length}')
    ..writeln('tags=${tagRows.length}');
  for (final card in cards) {
    buffer.writeln([
      card.id,
      card.knowledgePointId,
      card.repetitions,
      card.lapses,
      card.dueAt,
      card.lastReviewedAt,
      card.stability,
      card.difficulty,
      card.encodingStrength,
      card.savings,
      card.forced,
      card.forcedStreak,
      card.updatedAt,
    ].join('|'));
  }
  return buffer.toString();
}

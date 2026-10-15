import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/cognitive/cognitive_graph.dart';
import 'package:furnace/domain/services/cognitive/cognitive_model.dart';
import 'package:furnace/domain/services/cognitive/fast_diagnosis.dart'
    show BottleneckType;
import 'package:furnace/domain/services/cognitive/problem_evaluator.dart';

/// 用途 1's glue is a pure function of its inputs, so these tests need no
/// database: rows and tags are plain values.
void main() {
  const model = MindNetCognitiveModel();
  const nowHours = 1000.0;

  CardState rowOf({
    double? stability = 5,
    double? difficulty = 5,
    double? encodingStrength = 1.0,
    int? lastReviewedAt = 990000,
    int repetitions = 4,
    String? knowledgePointId,
  }) =>
      CardState(
        id: 'cs-${knowledgePointId ?? 'x'}-$stability-$difficulty',
        knowledgePointId: knowledgePointId,
        unitKey: 'u',
        dueAt: 995000,
        intervalDays: 5,
        ease: 2.5,
        repetitions: repetitions,
        lapses: 0,
        state: 'review',
        lastReviewedAt: lastReviewedAt,
        createdAt: 1,
        updatedAt: 2,
        stability: stability,
        difficulty: difficulty,
        encodingStrength: encodingStrength,
        savings: 0.8,
        forced: 0,
        forcedStreak: 0,
      );

  CognitiveTag tag(String id) => CognitiveTag(id: id, name: id);

  ProblemCandidate problem(
    String id, {
    List<String> kps = const [],
    double? hint,
  }) =>
      ProblemCandidate(
        id: id,
        stem: '题干 $id',
        knowledgePointIds: kps,
        difficultyHint: hint,
      );

  List<String> verdictsOf(ProblemEvaluationReport report) => [
        for (final evaluation in report.evaluations)
          '${evaluation.problemId}:${evaluation.verdict.name}',
      ];

  group('tierA alone (no graph, no fast layer)', () {
    test('a strong knowledge point reads as too easy', () {
      final report = ProblemEvaluator.evaluate(
        candidates: [
          problem('p1', kps: const ['kp-strong'])
        ],
        tags: const [],
        rowsByKnowledgePoint: {
          'kp-strong': rowOf(
            knowledgePointId: 'kp-strong',
            stability: 300,
            encodingStrength: 1.0,
          ),
        },
        model: model,
        nowHours: nowHours,
      );

      expect(report.fastLayerRan, isFalse);
      expect(report.evaluations.single.verdict, ProblemVerdict.tooEasy);
    });

    test('barely-retrievable and hard reads as too hard', () {
      final report = ProblemEvaluator.evaluate(
        candidates: [
          problem('p1', kps: const ['kp-gone'])
        ],
        tags: const [],
        rowsByKnowledgePoint: {
          // MindNet's forgetting curve is a power curve, so "almost gone"
          // (R <= 0.25) needs a very small stability: 0.002 days against ~1000
          // hours of elapsed time puts R at ~0.2. 0.05 days would still read
          // ~0.36, which is *not* below the threshold.
          'kp-gone': rowOf(
            knowledgePointId: 'kp-gone',
            stability: 0.002,
            difficulty: 8.5,
          ),
        },
        model: model,
        nowHours: nowHours,
      );

      expect(report.evaluations.single.verdict, ProblemVerdict.tooHard);
    });

    test('no knowledge points at all is out of scope, not a guess', () {
      final report = ProblemEvaluator.evaluate(
        candidates: [problem('p1')],
        tags: const [],
        rowsByKnowledgePoint: const {},
        model: model,
        nowHours: nowHours,
      );

      expect(report.evaluations.single.verdict, ProblemVerdict.outOfScope);
      expect(report.evaluations.single.rankKey, 0);
    });

    test('difficulty_hint is only a prior when there is no history', () {
      final rows = {
        'kp-strong': rowOf(knowledgePointId: 'kp-strong', stability: 300),
      };

      // With history, a "very hard" hint must not move the verdict: the model's
      // own numbers decide (§6.3 - the hint is never the model's `D`).
      final withHistory = ProblemEvaluator.evaluate(
        candidates: [
          problem('p1', kps: const ['kp-strong'], hint: 0.99)
        ],
        tags: const [],
        rowsByKnowledgePoint: rows,
        model: model,
        nowHours: nowHours,
      );
      expect(withHistory.evaluations.single.verdict, ProblemVerdict.tooEasy,
          reason: 'the hint must not turn a known card into a hard problem');

      // Without history the hint *is* the only signal we have, and it is used
      // as a prior - which the verdict says out loud.
      final noHistory = ProblemEvaluator.evaluate(
        candidates: [
          problem('p1', kps: const ['kp-unknown'], hint: 0.99)
        ],
        tags: const [],
        rowsByKnowledgePoint: rows,
        model: model,
        nowHours: nowHours,
      );
      expect(noHistory.evaluations.single.verdict, ProblemVerdict.tooHard);
      expect(noHistory.evaluations.single.reason, contains('未标定'));
    });
  });

  group('the fast layer', () {
    test('an isolated knowledge point is a dead end -> out of scope', () {
      // One tag, no edges: nothing can drive into it, which is exactly
      // `empty` / `no_entry` (fast_diagnosis.dart's in-degree branch).
      final report = ProblemEvaluator.evaluate(
        candidates: [
          problem('p1', kps: const ['kp-island'])
        ],
        tags: [tag('kp-island')],
        rowsByKnowledgePoint: {
          'kp-island': rowOf(knowledgePointId: 'kp-island'),
        },
        model: model,
        nowHours: nowHours,
      );

      expect(report.fastLayerRan, isTrue);
      final evaluation = report.evaluations.single;
      expect(evaluation.diagnosisByKnowledgePoint['kp-island'],
          BottleneckType.empty);
      expect(evaluation.verdict, ProblemVerdict.outOfScope);
      expect(evaluation.reason, contains('死角'));
    });

    test('tags without a card row are reported, never given 0.8', () {
      final report = ProblemEvaluator.evaluate(
        candidates: [
          problem('p1', kps: const ['kp-has-row'])
        ],
        tags: [tag('kp-has-row'), tag('kp-no-row')],
        rowsByKnowledgePoint: {
          'kp-has-row': rowOf(knowledgePointId: 'kp-has-row'),
        },
        model: model,
        nowHours: nowHours,
      );

      expect(report.nodesWithoutMs, contains('kp-no-row'));
      expect(report.nodesWithoutMs, isNot(contains('kp-has-row')));
    });

    test('ids outside the graph are dropped instead of throwing', () {
      // `startDiffusion` throws ArgumentError for a node that does not exist,
      // so both lists must be filtered first (empty lists are legal).
      final report = ProblemEvaluator.evaluate(
        candidates: [
          problem('p1', kps: const ['kp-in-graph', 'kp-not-a-tag']),
        ],
        tags: [tag('kp-in-graph')],
        rowsByKnowledgePoint: {
          'kp-in-graph': rowOf(knowledgePointId: 'kp-in-graph'),
        },
        model: model,
        nowHours: nowHours,
        startKnowledgePointIds: const ['kp-not-a-tag', 'also-missing'],
      );

      expect(report.evaluations, hasLength(1));
      expect(report.evaluations.single.knowledgePointIds,
          ['kp-in-graph', 'kp-not-a-tag']);
      expect(
          report.evaluations.single.judgedKnowledgePointIds, ['kp-in-graph']);
    });

    test('runFastLayer: false keeps tierA usable with a graph present', () {
      final report = ProblemEvaluator.evaluate(
        candidates: [
          problem('p1', kps: const ['kp-in-graph'])
        ],
        tags: [tag('kp-in-graph')],
        rowsByKnowledgePoint: {
          'kp-in-graph': rowOf(knowledgePointId: 'kp-in-graph', stability: 300),
        },
        model: model,
        nowHours: nowHours,
        runFastLayer: false,
      );

      expect(report.fastLayerRan, isFalse);
      expect(report.evaluations.single.verdict, ProblemVerdict.tooEasy);
      expect(report.evaluations.single.diagnosisByKnowledgePoint, isEmpty);
    });
  });

  group('batch behaviour', () {
    test('a problem whose knowledge points another covers is redundant', () {
      final report = ProblemEvaluator.evaluate(
        candidates: [
          problem('narrow', kps: const ['kp-a']),
          problem('wide', kps: const ['kp-a', 'kp-b']),
        ],
        tags: const [],
        rowsByKnowledgePoint: {
          'kp-a': rowOf(knowledgePointId: 'kp-a'),
          'kp-b': rowOf(knowledgePointId: 'kp-b'),
        },
        model: model,
        nowHours: nowHours,
      );

      final byId = {
        for (final evaluation in report.evaluations)
          evaluation.problemId: evaluation,
      };
      expect(byId['narrow']!.verdict, ProblemVerdict.redundant);
      expect(byId['wide']!.verdict, isNot(ProblemVerdict.redundant));
      // Ranked, and the redundant one is behind the wider one.
      expect(report.evaluations.first.problemId, 'wide');
    });

    test('same input, same ranking, whatever the input order', () {
      final candidates = [
        problem('p1', kps: const ['kp-a']),
        problem('p2', kps: const ['kp-b']),
        problem('p3', kps: const ['kp-a', 'kp-b']),
      ];
      final rows = {
        'kp-a': rowOf(knowledgePointId: 'kp-a'),
        'kp-b': rowOf(knowledgePointId: 'kp-b', stability: 20),
      };

      final forward = ProblemEvaluator.evaluate(
        candidates: candidates,
        tags: const [],
        rowsByKnowledgePoint: rows,
        model: model,
        nowHours: nowHours,
      );
      final reversed = ProblemEvaluator.evaluate(
        candidates: candidates.reversed.toList(),
        tags: const [],
        rowsByKnowledgePoint: rows,
        model: model,
        nowHours: nowHours,
      );

      expect(verdictsOf(forward), verdictsOf(reversed));
      final keys = [for (final e in forward.evaluations) e.rankKey];
      expect(keys, orderedEquals([...keys]..sort((a, b) => b.compareTo(a))),
          reason: 'sorted by rankKey descending');
    });
  });

  group('the counterfactual price (§2-A 缺①)', () {
    test('a dead end carries the price of opening it, with its metric', () {
      // Two nodes: `kp-lit` is what the user is holding in mind, `kp-island`
      // has no in-edge at all (`empty`). `add_in_edges` is the planner's
      // preferred instruction for `empty` and it *is* simulatable, so this
      // candidate gets a reachability price instead of a bare "dead end".
      final report = ProblemEvaluator.evaluate(
        candidates: [
          problem('p1', kps: const ['kp-island'])
        ],
        tags: [tag('kp-lit'), tag('kp-island')],
        rowsByKnowledgePoint: {
          'kp-lit': rowOf(knowledgePointId: 'kp-lit'),
          'kp-island': rowOf(knowledgePointId: 'kp-island'),
        },
        model: model,
        nowHours: nowHours,
        startKnowledgePointIds: const ['kp-lit'],
      );

      final evaluation = report.evaluations.single;
      expect(report.fastLayerRan, isTrue);
      expect(evaluation.verdict, ProblemVerdict.outOfScope,
          reason: 'a node nothing can drive into is still a dead end');
      expect(evaluation.counterfactualMetric, 'reachability');
      expect(evaluation.counterfactualValue, isNotNull);
      expect(evaluation.counterfactualValue!, greaterThan(0),
          reason: 'adding the missing in-edge must buy something measurable');
      expect(evaluation.counterfactualInstruction, 'add_in_edges');
      expect(evaluation.counterfactualWhy, isNotEmpty);
      expect(evaluation.reason, contains('反事实'));
      expect(evaluation.reason, contains('reachability'));
    });

    test('tierA alone carries no price and appends no clause', () {
      final report = ProblemEvaluator.evaluate(
        candidates: [
          problem('p1', kps: const ['kp-island'])
        ],
        tags: [tag('kp-lit'), tag('kp-island')],
        rowsByKnowledgePoint: {
          'kp-lit': rowOf(knowledgePointId: 'kp-lit'),
          'kp-island': rowOf(knowledgePointId: 'kp-island'),
        },
        model: model,
        nowHours: nowHours,
        startKnowledgePointIds: const ['kp-lit'],
        runFastLayer: false,
      );

      final evaluation = report.evaluations.single;
      expect(report.fastLayerRan, isFalse);
      expect(evaluation.counterfactualValue, isNull);
      expect(evaluation.counterfactualMetric, isNull);
      expect(evaluation.counterfactualInstruction, isNull);
      expect(evaluation.reason, isNot(contains('反事实')));
    });

    test('the price is a tie-break: rankKey first, then value, then id', () {
      ProblemEvaluation built({
        required String id,
        double rankKey = 1.0,
        double? value,
      }) =>
          ProblemEvaluation(
            problemId: id,
            stem: '题干 $id',
            verdict: ProblemVerdict.zpd,
            rankKey: rankKey,
            reason: '同分',
            knowledgePointIds: const ['kp-a'],
            judgedKnowledgePointIds: const ['kp-a'],
            diagnosisByKnowledgePoint: const {},
            counterfactualValue: value,
          );

      List<String> orderOf(List<ProblemEvaluation> evaluations) {
        final sorted = [...evaluations]..sort(ProblemEvaluator.compareByRank);
        return [for (final evaluation in sorted) evaluation.problemId];
      }

      // Equal rankKey: the price decides, and "no price" comes last.
      expect(
        orderOf([
          built(id: 'none'),
          built(id: 'small', value: 0.5),
          built(id: 'big', value: 2.0),
        ]),
        ['big', 'small', 'none'],
      );
      // Same price: the id decides, so the order stays total.
      expect(
        orderOf([built(id: 'b', value: 1.0), built(id: 'a', value: 1.0)]),
        ['a', 'b'],
      );
      // A price never outranks a higher rankKey.
      expect(
        orderOf([
          built(id: 'paid', rankKey: 0.5, value: 9.0),
          built(id: 'plain', rankKey: 2.0),
        ]),
        ['plain', 'paid'],
      );
    });

    test('a point with a way in but no momentum is priced in retention', () {
      // Q31b: the evaluator installs `memory.dsr` and hands the planner the
      // production probe, so the one bottleneck the planner answers with a
      // *retention* instruction (`weak`) now gets a real "how much does
      // reviewing buy by tomorrow" price instead of "not simulated".
      //
      // The encoding strength is 0.5 on purpose: at 1.0 (the ceiling) the
      // simulated gain is exactly zero, so no price is reported at all (next
      // test) and this one could not tell "priced" from "not priced".
      final report = ProblemEvaluator.evaluate(
        candidates: [
          problem('p1', kps: const ['kp-child'])
        ],
        tags: const [
          CognitiveTag(id: 'kp-parent', name: 'kp-parent'),
          CognitiveTag(id: 'kp-child', name: 'kp-child', parentId: 'kp-parent'),
        ],
        rowsByKnowledgePoint: {
          'kp-parent':
              rowOf(knowledgePointId: 'kp-parent', encodingStrength: 0.5),
          'kp-child':
              rowOf(knowledgePointId: 'kp-child', encodingStrength: 0.5),
        },
        model: model,
        nowHours: nowHours,
        startKnowledgePointIds: const ['kp-parent'],
      );

      final evaluation = report.evaluations.single;
      expect(evaluation.diagnosisByKnowledgePoint, isNotEmpty,
          reason: 'a parent -> child edge is a way in, so this is not a '
              'no-entry dead end');
      expect(evaluation.counterfactualMetric, 'retention');
      expect(evaluation.counterfactualInstruction, 'strengthen_impression');
      expect(evaluation.counterfactualValue, isNotNull);
      expect(evaluation.counterfactualValue!, greaterThan(0),
          reason: 'why was: ${evaluation.counterfactualWhy}');
      expect(evaluation.counterfactualWhy, isNotEmpty);
      expect(evaluation.reason, contains('retention'));
    });

    test('a review at the retrievability ceiling carries no price at all', () {
      // R0 = 1.0 with S = legacy_k * R0: psi(24 / 24) = 0.9 exactly, and a
      // success at R = 1 buys no stability at all, so the simulated gain is
      // exactly zero. That is not a price: a `0.0` in the output would read like
      // a measurement of worthlessness, and it can never reorder anything. The
      // key is absent - the same way it is absent when the memory layer is not
      // installed at all, which is why the planner's own `simulated` flag, not
      // the presence of a price, is what says "this question was asked".
      final report = ProblemEvaluator.evaluate(
        candidates: [
          problem('p1', kps: const ['kp-child'])
        ],
        tags: const [
          CognitiveTag(id: 'kp-parent', name: 'kp-parent'),
          CognitiveTag(id: 'kp-child', name: 'kp-child', parentId: 'kp-parent'),
        ],
        rowsByKnowledgePoint: {
          'kp-parent': rowOf(knowledgePointId: 'kp-parent'),
          'kp-child': rowOf(knowledgePointId: 'kp-child'),
        },
        model: model,
        nowHours: nowHours,
        startKnowledgePointIds: const ['kp-parent'],
      );

      final evaluation = report.evaluations.single;
      expect(evaluation.counterfactualValue, isNull);
      expect(evaluation.counterfactualMetric, isNull);
      expect(evaluation.reason, isNot(contains('反事实')));
    });
  });
}

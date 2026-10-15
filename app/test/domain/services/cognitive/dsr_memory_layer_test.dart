/// Q31a: the `memory.dsr` layer, opt-in on the fast engine, plus the
/// production retention probe that lets the counterfactual planner price a
/// `retention` instruction.
///
/// What is pinned here: with no memory mechanism installed a review records
/// nothing (the tierB default, and what the conformance vectors were generated
/// with), an installed layer advances the node's DSR state the way
/// `mechanisms/memory.dsr.js` does, a clone carries its own copy of the bag,
/// and the probe reads the bag rather than `ms` once one exists.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/cognitive/dsr_retention_probe.dart';
import 'package:furnace/domain/services/cognitive/fast_diagnosis.dart';
import 'package:furnace/domain/services/cognitive/fast_engine.dart';
import 'package:furnace/domain/services/srs/dsr_memory.dart';

/// One knowledge-point node at `ms` (the model's current retrievability) with
/// the review time `fixLastReviewTime` would have set.
FastEngine engineWith({
  required bool memory,
  double ms = 0.8,
  double hours = 1000,
}) {
  final graph = FastGraph();
  graph.addNode(FastNode(
    id: 'kp',
    name: '牛顿定律',
    type: 'knowledge_point',
    ms: ms,
    lastReviewTime: hours,
  ));
  return FastEngine(
    graph: graph,
    mechanisms: FastMechanisms.fromModuleDefaults(
      const <String, Object?>{},
      ids: memory ? const <String>[FastMechanisms.memory] : const <String>[],
    ),
    hours: hours,
  );
}

const Map<String, Object?> success = <String, Object?>{
  'type': 'retrieval_success',
  'grade': 3,
};

const Map<String, Object?> lapse = <String, Object?>{
  'type': 'lapse',
  'grade': 1,
};

double bagNumber(FastNode node, String key) =>
    (FastEngine.dsrBagOf(node)![key]! as num).toDouble();

void main() {
  group('the memory.dsr layer', () {
    test('is off by default, so a review records nothing', () {
      final engine = engineWith(memory: false);
      final node = engine.graph.nodes['kp']!;

      expect(engine.memoryInstalled, isFalse);
      expect(engine.review('kp', success), isEmpty);
      expect(node.m, isEmpty);

      // The diagnostic facts report the memory layer by its absence: null, not
      // 0 - "not installed" and "zero strength" are different statements.
      final facts = engine.diagnosticFacts()['kp']!;
      expect(facts.r0, isNull);
      expect(facts.s, isNull);
      expect(facts.d, isNull);
    });

    test('an installed layer advances the state on review', () {
      final engine = engineWith(memory: true);
      final node = engine.graph.nodes['kp']!;

      expect(engine.memoryInstalled, isTrue);
      final hooks = engine.review('kp', success);

      expect(hooks, hasLength(1));
      expect(hooks.single['mechanism'], FastMechanisms.memory);
      expect(hooks.single['kind'], 'review');

      final bag = FastEngine.dsrBagOf(node)!;
      expect(bag['N'], 1);
      // R0 = min(1, ms) = 0.8, then one success adds c_R0 * (1 - R0).
      expect(bagNumber(node, 'R0'), closeTo(0.81, 1e-9));
      // ensureState's S = legacy_k * R0 = 19.2; a success only grows S.
      expect(bagNumber(node, 'S'), greaterThan(19.2));
      expect(bagNumber(node, 'Sigma'), greaterThan(0.8));
      expect(bag['history'], hasLength(1));

      // synced(): the node's ms and review time follow the bag, so the facts
      // and the memory layer cannot disagree.
      expect(node.ms, closeTo(hooks.single['R_after']! as double, 1e-9));
      expect(node.lastReviewTime, 1000);
      final facts = engine.diagnosticFacts()['kp']!;
      expect(facts.r0, closeTo(0.81, 1e-6));
      expect(facts.s, isNotNull);
    });

    test('a second success raises S again, a lapse drops S but keeps Sigma', () {
      final engine = engineWith(memory: true);
      final node = engine.graph.nodes['kp']!;

      engine.review('kp', success);
      final afterFirst = bagNumber(node, 'S');
      engine.review('kp', success);
      final afterSecond = bagNumber(node, 'S');
      expect(afterSecond, greaterThan(afterFirst));

      engine.review('kp', lapse);
      expect(bagNumber(node, 'S'), lessThan(afterSecond));
      // The savings effect: a lapse may cost stability, never storage strength.
      expect(bagNumber(node, 'Sigma'), greaterThan(0.8));
      expect(bagNumber(node, 'F'), greaterThan(0));
      expect(FastEngine.dsrBagOf(node)!['lastFail'], 1000);
    });

    test('a clone reviews its own copy of the bag', () {
      final engine = engineWith(memory: true);
      final node = engine.graph.nodes['kp']!;
      engine.review('kp', success);

      final clone = engine.clone();
      expect(clone.memoryInstalled, isTrue);
      final cloneNode = clone.graph.nodes['kp']!;
      final originalS = bagNumber(node, 'S');

      clone.review('kp', success);

      expect(FastEngine.dsrBagOf(node)!['N'], 1);
      expect(FastEngine.dsrBagOf(cloneNode)!['N'], 2);
      // A counterfactual review must not reach back into the original.
      expect(bagNumber(node, 'S'), originalS);
    });
  });

  group('the retention probe', () {
    test('prices a review by comparing R at the horizon', () {
      final engine = engineWith(memory: true);
      final node = engine.graph.nodes['kp']!;
      final probe = dsrRetentionProbe(params: engine.memoryParams!);
      final clone = engine.clone();
      clone.review('kp', success);

      final before = probe(engine, 'kp', 1024);
      final after = probe(clone, 'kp', 1024);

      expect(before, isNotNull);
      expect(after, isNotNull);
      expect(after!, greaterThan(before!));

      // psi(0) = 1, so at the state's own review time R is R0 again.
      expect(probe(engine, 'kp', 1000), closeTo(0.8, 1e-9));
      expect(probe(engine, 'kp', 1100), lessThan(probe(engine, 'kp', 1024)!));

      // synced(): the read moves the node's cached ms to R(u), and leaves the
      // state's own review time alone.
      expect(node.ms, closeTo(probe(engine, 'kp', 1024)!, 1e-9));
      expect(node.lastReviewTime, 1000);
    });

    test('an unknown node is null for the probe and an error for review', () {
      final engine = engineWith(memory: true);
      final probe = dsrRetentionProbe();

      expect(probe(engine, 'missing', 1000), isNull);
      expect(() => engine.review('missing', success), throwsArgumentError);
    });

    test('a seeded card state wins over the ms fallback', () {
      final engine = engineWith(memory: true);
      final node = engine.graph.nodes['kp']!;

      // A card whose own R0 (0.2) is far below what ms would suggest.
      seedDsrState(node, DsrState.initial(now: 1000, ms: 0.2));

      expect(bagNumber(node, 'R0'), 0.2);
      expect(bagNumber(node, 'S'), closeTo(24 * 0.2, 1e-9));
      expect(dsrRetentionProbe()(engine, 'kp', 1000), closeTo(0.2, 1e-9));
    });
  });

  group('the production probe prices a retention instruction', () {
    // `weak` is the one bottleneck the planner answers with a retention
    // instruction, and the planner only needs the bottleneck - not a real
    // diffusion run - to decide what to simulate.
    const bottleneck = FastBottleneck(
      node: 'kp',
      name: '牛顿定律',
      type: BottleneckType.weak,
      label: '弱',
      note: 'almost had it',
      severity: 1,
      prescriptions: <String>['strengthen_impression'],
      evidence: <String, Object?>{},
    );

    FastPlanEntry entryFor(List<FastPlanEntry> plan, String instruction) =>
        plan.firstWhere((entry) => entry.instruction == instruction);

    test('with the probe: simulated, priced in retention, positive gain', () {
      final engine = engineWith(memory: true);
      const params = FastPlannerParams();
      final plan = FastPlanner.plan(
        engine: engine,
        bottlenecks: const <FastBottleneck>[bottleneck],
        params: params,
        retentionProbe: dsrRetentionProbe(params: engine.memoryParams),
      );

      final priced = entryFor(plan, 'strengthen_impression');
      expect(priced.simulated, isTrue);
      expect(priced.metric, 'retention',
          reason: 'retention is the metric only a probe can measure');
      expect(priced.gain, greaterThan(0),
          reason: 'reviewing must raise R at the horizon');
      expect(priced.cost, params.costRetrieval);
      expect(priced.value, greaterThan(0));
      expect(priced.why, contains('留存'));
    });

    test('without the probe: not simulated, and never a zero gain', () {
      final engine = engineWith(memory: true);
      final plan = FastPlanner.plan(
        engine: engine,
        bottlenecks: const <FastBottleneck>[bottleneck],
      );

      final bare = entryFor(plan, 'strengthen_impression');
      expect(bare.simulated, isFalse);
      expect(bare.why, contains('未装载记忆模块'));
      expect(bare.value, 0);
    });
  });
}

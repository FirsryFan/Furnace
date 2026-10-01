import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/cognitive/fast_diagnosis.dart';
import 'package:furnace/domain/services/cognitive/fast_engine.dart';
import 'package:furnace/domain/services/srs/dsr_memory.dart';

/// Conformance test for the diagnosis + counterfactual half of the tierB port.
///
/// ## Where the expectations come from
///
/// `test/fixtures/mindnet_tierb_diagnosis.json` is generated **from the real JS
/// implementation** by `app/tool/gen_mindnet_tierb_diagnosis.cjs`:
///
/// ```
/// cd E:/FirsryOS/Memory/一THREADRIPPER一/class-productivity
/// node app/tool/gen_mindnet_tierb_diagnosis.cjs
/// ```
///
/// The agreed snapshot (`mindnet_vectors.json`) has no vectors for
/// `diagnosis.bottleneck` / `control.planner`, so without this generator the
/// expectations would be "whatever the port happens to do". The generator
/// `require`s MindNet's own modules and never writes to that repository.
///
/// ## A note on the reference's counterfactual engine
///
/// `control.planner` prices an intervention by cloning the engine. The JS
/// `FastEngine.clone()` rebuilds the mechanism list from the *assembly options it
/// was given* and falls back to `PROFILES.v2` when those are missing - so an
/// engine built as `new FastEngine(graph, config, {kernel})` (which is how
/// `tools/conformance.js` builds it) hands every counterfactual a different model
/// than the one being planned: memory layer, rhythm gate and metacognition
/// included. The generator passes the assembly options through, which is what the
/// JS comment says they are for ("供克隆（反事实模拟）复用"), and the Dart port's
/// `clone()` reuses the engine's own mechanism set. Both sides therefore price
/// "the same model, one intervention", which is the only reading that makes the
/// number meaningful.
void main() {
  final file = File('test/fixtures/mindnet_tierb_diagnosis.json');
  if (!file.existsSync()) {
    test('mindnet tierb diagnosis vectors', () {
      fail('missing ${file.path} - regenerate it with '
          '`node app/tool/gen_mindnet_tierb_diagnosis.cjs` (read-only on MindNet)');
    });
    return;
  }

  final vectors = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final tolerances = (vectors['tolerances'] as Map).cast<String, Object?>();
  final rel = (tolerances['rel'] as num).toDouble();
  final abs = (tolerances['abs'] as num).toDouble();
  final scenarios = (vectors['scenarios'] as Map).cast<String, Object?>();

  Map<String, Object?> asMap(Object? value) =>
      (value as Map).cast<String, Object?>();

  /// Compares one published number.
  ///
  /// The generator rounds some values (`severity`, `gain`, `value`, `a`, `q`, …)
  /// and publishes others raw (`closeness`, `weight`, `belief`), so a value
  /// passes if either the rounded or the raw comparison holds. Both are the
  /// contract's `rel <= 1e-12`, so this cannot hide a real difference.
  void expectNumber(String where, num actual, num expectedValue) {
    final want = expectedValue.toDouble();
    final raw = actual.toDouble();
    for (final candidate in [raw, FastEngine.round6(raw)]) {
      final diff = (candidate - want).abs();
      final scale = want.abs() > 1 ? want.abs() : 1.0;
      if (diff <= abs || diff / scale <= rel) {
        return;
      }
    }
    final rounded = FastEngine.round6(raw);
    final diff = (rounded - want).abs();
    fail('$where: actual=$raw (rounded=$rounded) expected=$want '
        'diff=$diff (rel=${diff / (want.abs() > 1 ? want.abs() : 1.0)}, '
        'allowed rel=$rel abs=$abs)');
  }

  /// Recursive comparison against the generator's output: same keys, same list
  /// lengths, numbers by tolerance, everything else exactly.
  void expectDeep(String where, Object? actual, Object? expected) {
    if (expected is Map) {
      expect(actual, isA<Map>(), reason: '$where: expected a map');
      final actualMap = asMap(actual);
      final expectedMap = expected.cast<String, Object?>();
      expect(actualMap.keys.toSet(), expectedMap.keys.toSet(),
          reason: '$where: field set drifted');
      for (final entry in expectedMap.entries) {
        expectDeep('$where.${entry.key}', actualMap[entry.key], entry.value);
      }
      return;
    }
    if (expected is List) {
      expect(actual, isA<List>(), reason: '$where: expected a list');
      final actualList = actual! as List;
      expect(actualList, hasLength(expected.length),
          reason: '$where: list length');
      for (var i = 0; i < expected.length; i += 1) {
        expectDeep('$where[$i]', actualList[i], expected[i]);
      }
      return;
    }
    if (expected is num) {
      expect(actual, isA<num>(), reason: '$where: expected a number');
      expectNumber(where, actual! as num, expected);
      return;
    }
    // Strings, booleans and nulls are compared exactly - this is where the
    // notes, labels and `simulated` flags are pinned.
    expect(actual, expected, reason: where);
  }

  FastEngine buildEngine(Map<String, Object?> spec) {
    final ids = [for (final id in (spec['mechanisms'] as List)) id as String];
    final mechanisms = FastMechanisms.fromModuleDefaults(
      asMap(spec['module_defaults']),
      ids: ids,
      overrides: asMap(spec['overrides']),
    );
    final graph = FastGraph.fromSpec(
      asMap(spec['graph']),
      currentRealTime: (spec['hours'] as num?)?.toDouble() ?? 0,
    );
    final config = spec['config'] == null
        ? const FastConfig()
        : FastConfig.fromJson(asMap(spec['config']));
    return FastEngine(
      graph: graph,
      config: config,
      mechanisms: mechanisms,
      overrides: asMap(spec['overrides']),
      seed: (spec['seed'] as num?)?.toInt() ?? 11,
      hours: (spec['hours'] as num?)?.toDouble() ?? 0,
    )..startDiffusion(
        [for (final id in (spec['initial_nodes'] as List)) id as String],
        [for (final id in (spec['target_nodes'] as List)) id as String],
      );
  }

  /// The generator's loop: `rounds` steps, stopping early if the engine did.
  void runRounds(FastEngine engine, int rounds) {
    for (var i = 0; i < rounds && !engine.stopped; i += 1) {
      engine.step();
    }
  }

  Map<String, Object?> runSummary(FastEngine engine) => {
        'rounds_run': engine.rounds,
        'stopped': engine.stopped,
        'stop_reason': engine.stopReason,
        'final_states': engine.finalStates(),
        'target_steps': engine.targetStepsOf(),
        'ever_activated': engine.everActivated.toList()..sort(),
        'reachability': engine.reachability(),
      };

  FastDiagnosisParams diagnosisParams(Map<String, Object?> spec) =>
      spec['diagnosis_defaults'] == null
          ? const FastDiagnosisParams()
          : FastDiagnosisParams.fromJson(asMap(spec['diagnosis_defaults']));

  FastPlannerParams plannerParams(Map<String, Object?> spec) =>
      spec['planner_defaults'] == null
          ? const FastPlannerParams()
          : FastPlannerParams.fromJson(asMap(spec['planner_defaults']));

  group('classify (pure function, 20 cases)', () {
    final cases = (vectors['classify'] as List).cast<Map<String, Object?>>();

    test('every published verdict is reproduced', () {
      expect(cases, hasLength(20));
      for (final entry in cases) {
        final id = entry['id'] as String;
        final input = asMap(entry['input']);
        final factJson = asMap(input['fact']);
        final params = FastDiagnosisParams.fromJson(asMap(input['options']));
        final verdict = FastDiagnosis.classify(
          FastDiagnosticFact.fromJson(factJson),
          params,
          reachesGoal: factJson['reaches_goal'] as bool?,
        );
        final expected = entry['expected'];
        if (expected == null) {
          expect(verdict, isNull, reason: '$id: expected no verdict');
          continue;
        }
        expect(verdict, isNotNull, reason: '$id: expected a verdict');
        // `classify` always produces exactly these five keys (including explicit
        // nulls), and `expectDeep` requires the key sets to match.
        expectDeep(id, {
          'type': verdict!.type.id,
          'subtype': verdict.subtype,
          'closeness': verdict.closeness,
          'note': verdict.note,
          'also': verdict.also,
        }, asMap(expected));
      }
    });

    test('the types the classifier can and cannot produce', () {
      final produced = <String>{};
      for (final entry in cases) {
        final expected = entry['expected'];
        if (expected is Map) {
          produced.add(expected['type'] as String);
        }
      }
      // `danger` never comes out of `classify`: it is published by the
      // metacognition module and folded in by the hook (see the danger group).
      expect(produced, {
        'overload',
        'empty',
        'weak',
        'slow',
        'off_goal',
        'dead_end',
      });
      expect(produced, isNot(contains('danger')));

      // And `dead_end` only shows up with no goal set: with targets present a
      // node with no out-edges can never reach one, so it is reported off_goal.
      final base = FastDiagnosticFact.fromJson({
        'state': 'CONSCIOUS',
        'ct': 0.3,
        'st': 0.05,
        'score': 0.5,
        'peak_drive': 0.5,
        'in_degree': 1,
        'out_degree': 0,
      });
      expect(
        FastDiagnosis.classify(base, const FastDiagnosisParams(),
                reachesGoal: false)!
            .type,
        BottleneckType.offGoal,
      );
      expect(
        FastDiagnosis.classify(base, const FastDiagnosisParams())!.type,
        BottleneckType.deadEnd,
      );
    });
  });

  group('the remaining verdicts have end-to-end scenarios too', () {
    /// Runs a scenario the way the generator does, including the optional
    /// mid-run step ("late" edges + a new start), which is the only way the
    /// engine can produce a *sudden* activation change.
    FastEngine runScenario(Map<String, Object?> scenario) {
      final spec = asMap(scenario['input']);
      final engine = buildEngine(spec);
      runRounds(engine, (spec['rounds'] as num).toInt());
      final late = spec['late'];
      if (late is Map) {
        final lateSpec = asMap(late);
        for (final raw in (lateSpec['edges'] as List? ?? const [])) {
          final edge = asMap(raw);
          engine.graph.addEdge(FastEdge(
            id: edge['id']! as String,
            from: edge['from']! as String,
            to: edge['to']! as String,
            ls: (edge['ls'] as num?)?.toDouble() ?? 0.8,
          ));
        }
        engine.addInitialNodes(
            [for (final id in (lateSpec['nodes'] as List)) id as String]);
        for (var i = 0;
            i < ((spec['extra_rounds'] as num?)?.toInt() ?? 0) &&
                !engine.stopped;
            i += 1) {
          engine.step();
        }
      }
      return engine;
    }

    test('weak: a node that almost came back is the development zone', () {
      final scenario = asMap(scenarios['weak_node']);
      final spec = asMap(scenario['input']);
      final expected = asMap(scenario['expected']);
      final engine = runScenario(scenario);

      expectDeep('run', runSummary(engine), expected['run']);
      for (final entry in asMap(expected['facts']).entries) {
        expectDeep('facts.${entry.key}',
            engine.diagnosticFacts()[entry.key]!.toJson(), entry.value);
      }
      final bottlenecks = FastDiagnosis.bottlenecks(
        engine: engine,
        params: diagnosisParams(spec),
      );
      expectDeep(
        'diagnosis',
        [for (final b in bottlenecks) b.toJson()],
        expected['diagnosis'],
      );
      expect(bottlenecks.single.type, BottleneckType.weak);
      expect(bottlenecks.single.closeness, closeTo(0.75, 1e-12),
          reason: 'peak drive 0.225 against ct 0.3: "almost", not "no idea"');
      expect(bottlenecks.single.note, contains('已到阈值的 75%'));
    });

    test('slow: a goal that only lights up in round 5', () {
      final scenario = asMap(scenarios['slow_target']);
      final spec = asMap(scenario['input']);
      final expected = asMap(scenario['expected']);
      final engine = runScenario(scenario);

      expectDeep('run', runSummary(engine), expected['run']);
      expect(engine.rounds, 5);
      expect(engine.firstActivation['t'], 5,
          reason: 'the late start is what pushed it over ct');
      final bottlenecks = FastDiagnosis.bottlenecks(
        engine: engine,
        params: diagnosisParams(spec),
      );
      expectDeep(
        'diagnosis',
        [for (final b in bottlenecks) b.toJson()],
        expected['diagnosis'],
      );
      final slow = bottlenecks.single;
      expect(slow.type, BottleneckType.slow);
      expect(slow.note, '第 5 轮才亮');
      expect(slow.also, isEmpty,
          reason: 'once the verdict is `slow` the JS drops the `also` list');

      // Why the cue edge has to be added at the same moment as the late start:
      // the goal bias alone lifts a one-hop node past `st`, which activates the
      // target early and ends the run. Pinned so the scenario does not look
      // arbitrary.
      final early = buildEngine(spec);
      early.graph.addEdge(
          const FastEdge(id: 'l_e1', from: 's2', to: 't', ls: 1.0));
      runRounds(early, 4);
      expect(early.stopped, isTrue,
          reason: 'the bias leaked s2 → t and activated the target');
      expect(early.firstActivation['t']!, lessThan(5));
    });
  });

  group('engine-level diagnosis', () {
    test('the multi-type scenario matches fact for fact and verdict for verdict',
        () {
      final scenario = asMap(scenarios['engine_diagnosis']);
      final spec = asMap(scenario['input']);
      final expected = asMap(scenario['expected']);
      final engine = buildEngine(spec);
      runRounds(engine, (spec['rounds'] as num).toInt());

      expectDeep('run', runSummary(engine), expected['run']);

      final facts = engine.diagnosticFacts();
      expect(facts.keys.toSet(),
          asMap(expected['facts']).keys.toSet(),
          reason: 'fact table drifted');
      for (final entry in asMap(expected['facts']).entries) {
        expectDeep('facts.${entry.key}',
            facts[entry.key]!.toJson(), entry.value);
      }

      final bottlenecks = FastDiagnosis.bottlenecks(
        engine: engine,
        params: diagnosisParams(spec),
      );
      expectDeep(
        'diagnosis',
        [for (final b in bottlenecks) b.toJson()],
        expected['diagnosis'],
      );
      expectNumber('baseline_reachability', engine.reachability(),
          expected['baseline_reachability']! as num);

      // The scenario is only useful if it really produced several types.
      expect(bottlenecks.map((b) => b.type.id).toSet().length,
          greaterThanOrEqualTo(3));
    });

    test('a run with no targets reports dead ends', () {
      final scenario = asMap(scenarios['dead_end']);
      final spec = asMap(scenario['input']);
      final expected = asMap(scenario['expected']);
      final engine = buildEngine(spec);
      runRounds(engine, (spec['rounds'] as num).toInt());

      expectDeep('run', runSummary(engine), expected['run']);
      final bottlenecks = FastDiagnosis.bottlenecks(
        engine: engine,
        params: diagnosisParams(spec),
      );
      expectDeep(
        'diagnosis',
        [for (final b in bottlenecks) b.toJson()],
        expected['diagnosis'],
      );
      expect(bottlenecks.map((b) => b.type).toSet(),
          {BottleneckType.deadEnd});
      for (final entry in asMap(expected['facts']).entries) {
        expectDeep('facts.${entry.key}',
            engine.diagnosticFacts()[entry.key]!.toJson(), entry.value);
      }
    });

    test('the danger rows are folded in exactly like the JS hook', () {
      final scenario = asMap(scenarios['danger']);
      final spec = asMap(scenario['input']);
      final expected = asMap(scenario['expected']);
      final engine = buildEngine(spec);
      runRounds(engine, (spec['rounds'] as num).toInt());

      expectDeep('run', runSummary(engine), expected['run']);
      expectDeep('facts.d1', engine.diagnosticFacts()['d1']!.toJson(),
          expected['facts_d1']);

      final rows = [
        for (final raw in (spec['danger_rows'] as List))
          FastDangerRow.fromJson(asMap(raw)),
      ];
      expect(rows, hasLength(1),
          reason: 'the scenario is built to publish exactly one danger row');

      final bottlenecks = FastDiagnosis.bottlenecks(
        engine: engine,
        params: diagnosisParams(spec),
        dangerRows: rows,
      );
      expectDeep(
        'diagnosis',
        [for (final b in bottlenecks) b.toJson()],
        expected['diagnosis'],
      );

      // The JS guard: a row whose node already carries a danger verdict is not
      // added twice.
      final doubled = FastDiagnosis.bottlenecks(
        engine: engine,
        params: diagnosisParams(spec),
        dangerRows: [...rows, ...rows],
      );
      expect(doubled.where((b) => b.type == BottleneckType.danger), hasLength(1));
      expect(doubled, hasLength(bottlenecks.length));
    });
  });

  group('counterfactual plan', () {
    late Map<String, Object?> spec;
    late Map<String, Object?> expected;

    setUp(() {
      final scenario = asMap(scenarios['counterfactual']);
      spec = asMap(scenario['input']);
      expected = asMap(scenario['expected']);
    });

    test('every planned instruction, its gain, its cost and its wording match',
        () {
      final engine = buildEngine(spec);
      runRounds(engine, (spec['rounds'] as num).toInt());

      final bottlenecks = FastDiagnosis.bottlenecks(
        engine: engine,
        params: diagnosisParams(spec),
      );
      expectDeep(
        'diagnosis',
        [for (final b in bottlenecks) b.toJson()],
        expected['diagnosis'],
      );
      expectNumber('baseline_reachability', engine.reachability(),
          expected['baseline_reachability']! as num);

      final plan = FastPlanner.plan(
        engine: engine,
        bottlenecks: bottlenecks,
        params: plannerParams(spec),
        retentionProbe: dsrRetentionProbe,
      );
      expectDeep(
        'plan',
        [for (final entry in plan) entry.toJson()],
        expected['plan'],
      );

      // The scenario must actually price something, otherwise this test would
      // pass on a port that never simulated anything.
      final priced = plan.where((p) => p.simulated).toList();
      expect(priced, isNotEmpty);
      expect(priced.any((p) => p.metric == 'reachability' && p.gain != 0), isTrue,
          reason: 'add_in_edges must show a non-zero reachability gain');
    });

    test('without a retention probe the retention entries are not priced', () {
      // The JS words this case "memory module not loaded"; the port must use the
      // same wording and must NOT report a confident zero.
      final engine = buildEngine(spec);
      runRounds(engine, (spec['rounds'] as num).toInt());
      final bottlenecks = FastDiagnosis.bottlenecks(
        engine: engine,
        params: diagnosisParams(spec),
      );
      final plan = FastPlanner.plan(
        engine: engine,
        bottlenecks: bottlenecks,
        params: plannerParams(spec),
      );
      final retention = plan.where((p) => p.instruction == 'lower_threshold');
      expect(retention, isNotEmpty);
      for (final entry in retention) {
        expect(entry.simulated, isFalse,
            reason: 'nothing can be priced without the memory layer');
        expect(entry.why, '未装载记忆模块，无法预测留存增益');
        expect(entry.metric, isNull);
      }
      // Meanwhile the reachability entries still work without any tierA wiring.
      final reachability =
          plan.where((p) => p.metric == 'reachability' && p.simulated);
      expect(reachability, isNotEmpty);
      expect(reachability.any((p) => p.instruction == 'add_in_edges'), isTrue);
    });

    test('a counterfactual never leaks back into the engine being planned', () {
      final engine = buildEngine(spec);
      runRounds(engine, (spec['rounds'] as num).toInt());
      final edgesBefore = engine.graph.edges.length;
      final wDarBefore = engine.numberParam('attention.capacity.W_DAR');

      final plan = FastPlanner.plan(
        engine: engine,
        bottlenecks: FastDiagnosis.bottlenecks(
          engine: engine,
          params: diagnosisParams(spec),
        ),
        params: plannerParams(spec),
        retentionProbe: dsrRetentionProbe,
      );

      expect(plan, isNotEmpty);
      expect(engine.graph.edges.length, edgesBefore,
          reason: 'the hypothetical edge belongs to the clone');
      expect(
        engine.graph.edges.any((e) => e.id.startsWith('hypo_')),
        isFalse,
      );
      expect(engine.numberParam('attention.capacity.W_DAR'), wDarBefore,
          reason: "offload_working_memory writes to the clone's override map");
      // The probe does write the memory bag it is asked about (that is what
      // `retrievabilityOf` does), which is why the facts are read before it runs.
      expect(engine.diagnosticFacts()['lonely']!.r0, isNotNull);
    });

    test('instructions the engine cannot express say so instead of scoring zero',
        () {
      final engine = buildEngine(spec);
      runRounds(engine, (spec['rounds'] as num).toInt());
      final plan = FastPlanner.plan(
        engine: engine,
        bottlenecks: FastDiagnosis.bottlenecks(
          engine: engine,
          params: diagnosisParams(spec),
        ),
        params: plannerParams(spec),
      );
      for (final entry in plan.where((p) => !p.simulated)) {
        if (entry.instruction == 'lower_threshold') {
          continue; // the retention case, covered above
        }
        expect(entry.why, '该指令改变的是执行层用法，本引擎没有对应状态，未做模拟',
            reason: '${entry.instruction} must not pretend to have been priced');
        expect(FastPlanner.instructions[entry.instruction]!.simulatable, isFalse);
        expect(entry.cost, 0);
      }
    });

    test('the plan keeps at most three instructions per node', () {
      final engine = buildEngine(spec);
      runRounds(engine, (spec['rounds'] as num).toInt());
      final bottlenecks = FastDiagnosis.bottlenecks(
        engine: engine,
        params: diagnosisParams(spec),
      );
      final plan = FastPlanner.plan(
        engine: engine,
        bottlenecks: bottlenecks,
        params: plannerParams(spec),
      );
      final perNode = <String, int>{};
      for (final entry in plan) {
        perNode.update(entry.node, (v) => v + 1, ifAbsent: () => 1);
      }
      for (final entry in perNode.entries) {
        expect(entry.value, lessThanOrEqualTo(3),
            reason: 'node ${entry.key} got too many alternatives');
      }
      // The preferred instruction leads its node's list before the sort.
      for (final bottleneck in bottlenecks) {
        final preferred = FastPlanner.primary[bottleneck.type]!;
        expect(bottleneck.prescriptions, contains(preferred),
            reason: 'the preferred instruction must be in the prescription list');
      }
    });

    test('barely different severities keep the graph order (stable sort)', () {
      // Two nodes with the same weight and verdict have identical severity, and
      // JS `Array.prototype.sort` is stable - so the order follows the graph.
      // Dart's `List.sort` is not stable, which is why the port has its own.
      final engine = FastEngine(
        graph: FastGraph.fromSpec({
          'nodes': [
            {'id': 's1', 'name': '起点', 'type': 'knowledge', 'ms': 0.9},
            {'id': 'b', 'name': '乙', 'type': 'knowledge', 'ms': 0.8},
            {'id': 'a', 'name': '甲', 'type': 'knowledge', 'ms': 0.8},
            {'id': 'c', 'name': '丙', 'type': 'knowledge', 'ms': 0.8},
          ],
          'edges': [
            {'id': 'q1', 'from': 's1', 'to': 'b', 'ls': 0.3},
            {'id': 'q2', 'from': 's1', 'to': 'a', 'ls': 0.3},
            {'id': 'q3', 'from': 's1', 'to': 'c', 'ls': 0.3},
          ],
        }, currentRealTime: 0),
        mechanisms: FastMechanisms.fromModuleDefaults(
          {'dynamics.shunting': {}, 'context.goal': {}},
          ids: const [FastMechanisms.shunting, FastMechanisms.goal],
        ),
      )..startDiffusion(const ['s1'], const []);
      runRounds(engine, 2);
      final bottlenecks = FastDiagnosis.bottlenecks(engine: engine);
      final severities = bottlenecks.map((b) => b.severity).toSet();
      expect(severities, hasLength(1),
          reason: 'the scenario needs three equally severe bottlenecks');
      expect(bottlenecks.map((b) => b.node).toList(), ['b', 'a', 'c'],
          reason: 'ties keep the graph insertion order');
    });
  });
}

/// A [RetentionProbe] built on the already-ported tierA math.
///
/// It mirrors `mechanisms/memory.dsr.js`'s lazy `ensureState` and
/// `retrievabilityOf`: the bag lives in `node.m['memory_dsr']` (so a clone
/// deep-copies it, exactly like the JS), `R0 = min(1, ms)`, `S = legacy_k·R0`,
/// and `R = R0·Ψ((u − lastReview)/S)`.
///
/// The integration task is expected to wire the *real* card state here instead
/// of a bag created from `ms`; this test only needs the reference semantics to
/// compare against.
double? dsrRetentionProbe(FastEngine engine, String nodeId, double u) {
  final node = engine.graph.getNode(nodeId);
  if (node == null) {
    return null;
  }
  var bag = node.m['memory_dsr'];
  if (bag is! Map) {
    final r0 = node.ms > 0 ? math.min(1.0, node.ms) : 0.8;
    final lastReview =
        node.lastReviewTime == null || node.lastReviewTime == 0
            ? u
            : node.lastReviewTime!;
    bag = <String, Object?>{
      'R0': r0,
      'S': 24.0 * r0,
      'Sigma': r0,
      'D': 5.1618,
      'N': 0,
      'F': 0.0,
      'lastFail': null,
      'lastReview': lastReview,
      'history': <Object?>[],
      'initializedAt': u,
    };
    node.m['memory_dsr'] = bag;
  }
  final state = DsrState.fromJson((bag as Map<String, Object?>));
  final r = DsrMemory.retrievability(state, u).r;
  // `synced()` in the JS keeps node.ms / last_review_time in step with the bag.
  node.ms = r;
  node.lastReviewTime = state.lastReview;
  return r;
}

#!/usr/bin/env node
/**
 * Generates `app/test/fixtures/mindnet_tierb_diagnosis.json` — expected values for the
 * **diagnosis + counterfactual** half of the tierB port.
 *
 *   node app/tool/gen_mindnet_tierb_diagnosis.cjs            # writes the fixture
 *   node app/tool/gen_mindnet_tierb_diagnosis.cjs --dry-run   # prints the summary only
 *
 * Why this script exists: `mindnet_vectors.json` (the agreed contract snapshot) has a
 * tierB block for the *round pipeline* only. `diagnosis.bottleneck` and
 * `control.planner` have no published vectors, so the Dart port needs expectations that
 * are still produced by the **real JS implementation** rather than written by hand —
 * otherwise the expectations would just be "whatever the port does".
 *
 * Hard constraint (user, non-negotiable): MindNet is **read-only**. This script
 * `require`s MindNet modules, calls them, and writes **only** into the Furnace repo.
 * It never creates, modifies or deletes anything under `E:/Document/MindNet`.
 * Recommended check after running: `git -C E:/Document/MindNet status --porcelain`.
 *
 * The Dart side that consumes this file: `test/domain/services/cognitive/fast_diagnosis_conformance_test.dart`.
 */
'use strict';

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

/** Read-only reference checkout (absolute path; the repo is never written to). */
const MINDNET = 'E:/Document/MindNet';

const { Graph, Config, createKernel, Edge } = require(`${MINDNET}/src/index.js`);
const { FastEngine } = require(`${MINDNET}/src/v2/engine.js`);
const diagnosis = require(`${MINDNET}/mechanisms/diagnosis.bottleneck.js`);
const planner = require(`${MINDNET}/mechanisms/control.planner.js`);

const OUT = path.join(__dirname, '..', 'test', 'fixtures', 'mindnet_tierb_diagnosis.json');

const FAST = ['dynamics.shunting', 'attention.capacity', 'attention.ignition', 'context.goal'];

function round6(x) {
  if (typeof x !== 'number' || !Number.isFinite(x)) return x;
  return Math.round(x * 1e6) / 1e6;
}

/** The `module_defaults` block the Dart side must build its parameters from (§6.6). */
function moduleDefaults(ids) {
  const out = {};
  for (const id of ids) {
    const mod = require(`${MINDNET}/mechanisms/${id}.js`);
    out[id] = Object.assign({}, mod.DEFAULTS);
  }
  return out;
}

function buildEngine(spec) {
  const graph = Graph.from_object(spec.graph, 0);
  const options = {
    seed: spec.seed === undefined ? 11 : spec.seed,
    hours: spec.hours === undefined ? 0 : spec.hours,
    mechanisms: spec.mechanisms,
    overrides: spec.overrides || {},
  };
  const kernel = createKernel(graph, new Config(spec.config || {}), options);
  // The *assembly* options are passed to the engine as well, not just the kernel:
  // `FastEngine.clone()` rebuilds the mechanism list from `this._options.mechanisms`
  // and falls back to `PROFILES.v2` when it is missing. Constructing the engine with
  // only `{kernel}` (as `tools/conformance.js` does) therefore makes every
  // counterfactual run the **full v2 profile** - memory layer, rhythm gate,
  // metacognition - while the engine being planned has four mechanisms. That is a
  // real sharp edge on the reference side; passing the same options keeps the
  // counterfactual "the same model, one intervention" as intended, and the Dart port
  // (where the assembly parameters live on the engine) can only behave that way.
  // Recorded here so the difference is visible rather than papered over.
  const engine = new FastEngine(graph, kernel.config, Object.assign({ kernel }, options));
  engine.start_diffusion(spec.initial_nodes, spec.target_nodes);
  return engine;
}

/** A compact run summary (the fixture's `expected.run`). */
function runSummary(engine) {
  return {
    rounds_run: engine.rounds,
    stopped: engine.stopped,
    stop_reason: engine.stop_reason,
    final_states: engine.final_states(),
    target_steps: engine.target_steps(),
    ever_activated: engine.ever_activated.slice().sort(),
    reachability: engine.reachability(),
  };
}

/** Runs `rounds` steps (stopping early if the engine did) and summarizes. */
function runRounds(engine, rounds) {
  for (let i = 0; i < rounds && !engine.stopped; i += 1) engine.step();
  return runSummary(engine);
}

// ------------------------------------------------------------------ classify

/**
 * Facts for the pure classifier. Shapes match `engine.diagnostic_facts()`, and every
 * case is handed to the real `diagnosis.bottleneck.classify`.
 */
function classifyCases() {
  const base = {
    id: 'n', name: 'n', state: 'INACTIVE', a: 0, q: 0, drive: 0, score: 0,
    peak_drive: 0, ct: 0.3, st: 0.05, in_degree: 1, out_degree: 1,
    ever_activated: false, first_activation_round: null, activated_at_round: null,
    outcompeted: false, is_target: false, is_start: false, R: 0.8, R0: null, S: null, D: null, F: 0,
  };
  const cases = [
    ['C01-start-is-skipped', { is_start: true }],
    ['C02-overload-outcompeted-above-ct', { outcompeted: true, score: 0.4 }],
    ['C03-outcompeted-below-ct-is-not-overload', { outcompeted: true, score: 0.2, peak_drive: 0.2 }],
    ['C04-empty-no-entry', { in_degree: 0 }],
    ['C05-empty-no-entry-beats-weak', { in_degree: 0, peak_drive: 0.29 }],
    ['C06-weak-at-the-closeness-floor', { peak_drive: 0.18 }],
    ['C07-weak-just-below-the-closeness-floor', { peak_drive: 0.179 }],
    ['C08-weak-used-to-be-lit', { peak_drive: 0.25, ever_activated: true, a: 0.0 }],
    ['C09-empty-too-faint', { peak_drive: 0.05 }],
    ['C10-weak-from-score-not-peak', { score: 0.21, a: 0.21 }],
    ['C11-slow-target-late', { state: 'CONSCIOUS', is_target: true, first_activation_round: 5 }],
    ['C12-slow-beats-off-goal', { state: 'CONSCIOUS', is_target: true, first_activation_round: 5, reaches_goal: true }],
    ['C13-off-goal', { state: 'CONSCIOUS', reaches_goal: false }],
    ['C14-dead-end', { state: 'CONSCIOUS', out_degree: 0 }],
    ['C15-target-dead-end-is-not-dead-end', { state: 'CONSCIOUS', out_degree: 0, is_target: true }],
    ['C16-healthy-node-is-not-a-bottleneck', { state: 'CONSCIOUS', reaches_goal: true }],
    ['C17-no-target-means-reaches-goal-null', { state: 'CONSCIOUS', reaches_goal: null }],
    ['C18-weak-threshold-ablation', { peak_drive: 0.25 }, { closeness_weak: 1 }],
    ['C19-slow-rounds-ablation', { state: 'CONSCIOUS', is_target: true, first_activation_round: 3 }, { slow_rounds: 3 }],
    ['C20-weak-note-rounds-to-percent', { peak_drive: 0.2534, ever_activated: true }],
  ];
  return cases.map(([id, patch, options]) => {
    const fact = Object.assign({}, base, patch);
    return {
      id,
      input: { fact, options: options || {} },
      expected: diagnosis.classify(fact, options || {}),
    };
  });
}

// ------------------------------------------------------- engine-level diagnosis

/**
 * A graph built to produce several bottleneck types at once. The parameters are
 * the fast-layer ones (no `memory.dsr`, no `rhythm.gate`), plus `diagnosis.bottleneck`
 * so `control_report()` has something to report.
 */
function engineScenario() {
  const mechanisms = FAST.concat(['diagnosis.bottleneck']);
  const graph = {
    nodes: [
      { id: 's1', name: '起点一', type: 'knowledge', ms: 0.9, weight: 1 },
      { id: 's2', name: '起点二', type: 'knowledge', ms: 0.8, weight: 1 },
      { id: 'hub', name: '枢纽', type: 'knowledge', ms: 0.8, weight: 1.2 },
      { id: 'dead', name: '死路', type: 'knowledge', ms: 0.8, weight: 0.9 },
      { id: 'offg', name: '跑偏', type: 'knowledge', ms: 0.75, weight: 1.1 },
      { id: 'weakish', name: '差点', type: 'knowledge', ms: 0.65, weight: 1 },
      { id: 'weak2', name: '很弱但有点响', type: 'knowledge', ms: 0.7, weight: 1 },
      { id: 'faint', name: '太弱', type: 'knowledge', ms: 0.6, weight: 0.7 },
      { id: 'iso', name: '孤点', type: 'knowledge', ms: 0.5, weight: 0.6 },
      { id: 't', name: '目标', type: 'knowledge', ms: 0.7, weight: 2, ct: 0.9, st: 0.5 },
    ],
    edges: [
      { id: 'e1', from: 's1', to: 'hub', ls: 0.9 },
      { id: 'e2', from: 's2', to: 'hub', ls: 0.7 },
      { id: 'e3', from: 's1', to: 'dead', ls: 1.0 },
      { id: 'e4', from: 's2', to: 'offg', ls: 0.95 },
      { id: 'e5', from: 's2', to: 'weakish', ls: 0.35 },
      { id: 'e8', from: 's2', to: 'weak2', ls: 0.25 },
      { id: 'e6', from: 's1', to: 'faint', ls: 0.15 },
      { id: 'e7', from: 'hub', to: 't', ls: 0.8 },
    ],
  };
  const spec = {
    graph,
    initial_nodes: ['s1', 's2'],
    target_nodes: ['t'],
    seed: 11,
    hours: 0,
    mechanisms,
    overrides: { 'attention.ignition.T_ign': 0 },
    rounds: 6,
  };

  const engine = buildEngine(spec);
  const run = runRounds(engine, spec.rounds);
  // Facts first: this is exactly what the diagnose payload is built from.
  const facts = engine.diagnostic_facts();
  const report = engine.control_report();

  return {
    input: Object.assign({}, spec, {
      module_defaults: moduleDefaults(mechanisms),
      diagnosis_defaults: Object.assign({}, diagnosis.DEFAULTS),
    }),
    expected: {
      run,
      facts,
      diagnosis: report.diagnosis,
      baseline_reachability: report.baseline_reachability,
    },
  };
}

// ------------------------------------------------------- weak (development zone)

/**
 * The `weak` verdict — "it almost came back", the development zone the contract's
 * §6.3 recipe is built around — only survives while the node is still below `ct`:
 * the sub-threshold accumulator feeds back into the drive, so a weak node that is
 * given enough rounds climbs into consciousness and is then reported as something
 * else (in the multi-type scenario exactly that happens to `weak2`). Hence a
 * one-round scenario: the weakest thing the engine can still call a bottleneck.
 */
function weakScenario() {
  const mechanisms = FAST.concat(['diagnosis.bottleneck']);
  const graph = {
    nodes: [
      { id: 's1', name: '起点', type: 'knowledge', ms: 0.9, weight: 1 },
      { id: 'w', name: '差点想起', type: 'knowledge', ms: 0.8, weight: 1.5 },
    ],
    edges: [{ id: 'w_e1', from: 's1', to: 'w', ls: 0.25 }],
  };
  const spec = {
    graph,
    initial_nodes: ['s1'],
    target_nodes: [],
    seed: 11,
    hours: 0,
    mechanisms,
    overrides: { 'attention.ignition.T_ign': 0 },
    rounds: 1,
  };

  const engine = buildEngine(spec);
  const run = runRounds(engine, spec.rounds);
  const facts = engine.diagnostic_facts();
  const report = engine.control_report();

  return {
    input: Object.assign({}, spec, {
      module_defaults: moduleDefaults(mechanisms),
      diagnosis_defaults: Object.assign({}, diagnosis.DEFAULTS),
    }),
    expected: {
      run,
      facts,
      diagnosis: report.diagnosis,
      baseline_reachability: report.baseline_reachability,
    },
  };
}

// ------------------------------------------------------------- slow (late target)

/**
 * `slow` needs a target that first lights up **after** `slow_rounds` (3) *and* is
 * conscious at that moment. A target's activation cannot jump like that through
 * the drive alone:
 *
 * * the sources converge smoothly, and
 * * the sub-threshold accumulator only builds *after* a node is already active
 *   (`a >= st`), which is the same point at which it counts as activated;
 *
 * so the only path to a sudden change is a start added mid-run
 * (`add_initial_nodes`): it is pinned to `a = 1` at the beginning of the round it
 * appears in, **before** the drive is computed. The cue edge is added at the same
 * moment, because the goal bias is itself enough to lift a waiting node past `st`
 * and would end the run early otherwise (measured: a node one hop from the goal
 * gets `beta_goal * kappa_reach = 0.15` of drive every round).
 *
 * `stable_rounds` is raised in the config because the waiting rounds really are
 * quiet: with the default 2 the run would stop as "cooling" before the late start
 * can be added - which is exactly what the fixture records.
 */
function slowScenario() {
  const mechanisms = FAST.concat(['diagnosis.bottleneck']);
  const graph = {
    nodes: [
      { id: 's1', name: '起点一', type: 'knowledge', ms: 0.9, weight: 1 },
      { id: 's2', name: '后来才按住的起点', type: 'knowledge', ms: 1.0, weight: 1 },
      { id: 't', name: '很晚才亮的目标', type: 'knowledge', ms: 1.0, weight: 1.2 },
    ],
    edges: [],
  };
  const spec = {
    graph,
    initial_nodes: ['s1'],
    target_nodes: ['t'],
    seed: 11,
    hours: 0,
    mechanisms,
    overrides: { 'attention.ignition.T_ign': 0 },
    config: { stable_rounds: 10, max_rounds: 8 },
    rounds: 4,
    late: {
      describe: '第 5 轮开始时：先补 s2 → t 这条线索，再把 s2 按成起点（a=1）。',
      edges: [{ id: 'l_e1', from: 's2', to: 't', ls: 1.0 }],
      nodes: ['s2'],
    },
    extra_rounds: 1,
  };

  const engine = buildEngine(spec);
  for (let i = 0; i < spec.rounds && !engine.stopped; i += 1) engine.step();
  for (const edge of spec.late.edges) engine.graph.add_edge(new Edge(edge));
  engine.add_initial_nodes(spec.late.nodes);
  for (let i = 0; i < spec.extra_rounds && !engine.stopped; i += 1) engine.step();
  const run = runSummary(engine);
  const facts = engine.diagnostic_facts();
  const report = engine.control_report();

  return {
    input: Object.assign({}, spec, {
      module_defaults: moduleDefaults(mechanisms),
      diagnosis_defaults: Object.assign({}, diagnosis.DEFAULTS),
    }),
    expected: {
      run,
      facts,
      diagnosis: report.diagnosis,
      baseline_reachability: report.baseline_reachability,
    },
  };
}

// ------------------------------------------------- multi-round progression

/**
 * The blind spot of B01, closed from the other side.
 *
 * B01's five snapshots are identical because the target lights up in round 1 and
 * `_all_targets_active()` then stops the engine (`src/v2/engine.js` L282/L404),
 * so a diff over them cannot tell "it stopped correctly" from "it never
 * advanced". This scenario puts the target at the end of a long, weak chain so it
 * does **not** light in round 1: every captured round is one the pipeline really
 * executed, `round` increments, and drive/activation evolve.
 *
 * `stable_rounds` is raised in the config because this graph is deliberately slow
 * to warm up; with the default 2 quiet rounds the run would stop as "cooling"
 * before the chain gets going, and later snapshots would be no-ops again.
 *
 * The per-round shape is the one `tools/conformance.js` publishes for B01, so the
 * Dart test can run **one** field-by-field comparator over both.
 */
function multiroundScenario() {
  const mechanisms = FAST;
  const graph = {
    nodes: [
      { id: 'n0', name: '起点', type: 'knowledge', ms: 1.0, weight: 1 },
      { id: 'n1', name: '第一跳', type: 'knowledge', ms: 0.5, weight: 1 },
      { id: 'n2', name: '第二跳', type: 'knowledge', ms: 0.5, weight: 1 },
      { id: 'n3', name: '第三跳', type: 'knowledge', ms: 0.5, weight: 1 },
      { id: 'n4', name: '第四跳', type: 'knowledge', ms: 0.5, weight: 1 },
      // Note for anyone tempted to "make the target fainter" here: a node's `ms`
      // scales **its own outgoing** contribution (`drive = Σ al · ms_source · ls`),
      // so the target's own ms does not delay its lighting at all. The knob that
      // matters is the link strength into it.
      { id: 't', name: '远处的目标', type: 'knowledge', ms: 0.35, weight: 1 },
    ],
    edges: [
      { id: 'm1', from: 'n0', to: 'n1', ls: 0.6 },
      { id: 'm2', from: 'n1', to: 'n2', ls: 0.6 },
      { id: 'm3', from: 'n2', to: 'n3', ls: 0.7 },
      { id: 'm4', from: 'n3', to: 'n4', ls: 0.8 },
      // Weak enough that the goal stays below `st = 0.05` well past the captured
      // window: its drive only reaches that once `n4` is near its asymptote.
      { id: 'm5', from: 'n4', to: 't', ls: 0.3 },
    ],
  };
  const spec = {
    graph,
    initial_nodes: ['n0'],
    target_nodes: ['t'],
    seed: 11,
    hours: 0,
    mechanisms,
    overrides: { 'attention.ignition.T_ign': 0 },
    config: { stable_rounds: 10, max_rounds: 20 },
    // Exactly the rounds the pipeline really executes: the far goal crosses `st`
    // in round 6, which is where `_all_targets_active()` stops the run. Asking
    // for more would just append no-op repeats of round 6 (the B01 shape).
    rounds: 6,
  };

  const engine = buildEngine(spec);
  const rounds = [];
  const mapToObj = (map) => {
    const out = {};
    if (!map) return out;
    for (const [key, value] of map) out[key] = round6(value);
    return out;
  };
  let targetLitInRound1 = null;
  for (let i = 0; i < spec.rounds; i += 1) {
    engine.step();
    if (i === 0) targetLitInRound1 = engine.ever_activated.includes('t');
    const p = engine._lastRound || {};
    rounds.push({
      round: p.round,
      cycle_ticks: p.cycleTicks,
      availability: round6(p.availability),
      drive: mapToObj(p.drive),
      drive_edges: (p.drive_edges || []).map((e) => Object.assign({}, e)),
      scores: mapToObj(p.scores),
      admitted: (p.admitted || []).slice(),
      focus: p.focus === undefined ? null : p.focus,
      dar_used: p.dar_used === undefined ? null : p.dar_used,
      outcompeted: (p.outcompeted || []).slice(),
      conscious: (p.conscious || []).slice(),
      subconscious: (p.subconscious || []).slice(),
      states: (p.state_changes || []).map((s) => ({
        id: s.id,
        state_after: s.state_after,
        al: s.al,
      })),
      a: (() => {
        const out = {};
        for (const node of graph.nodes) out[node.id] = round6(engine.core(node.id).a);
        return out;
      })(),
      q: (() => {
        const out = {};
        for (const node of graph.nodes) out[node.id] = round6(engine.core(node.id).q);
        return out;
      })(),
    });
  }
  const run = runSummary(engine);

  return {
    input: Object.assign({}, spec, {
      module_defaults: moduleDefaults(mechanisms),
    }),
    expected: {
      run,
      rounds,
      // Recorded so the Dart side can assert the *reason* the rounds differ
      // rather than only that they do.
      target_lit_in_round_1: targetLitInRound1,
      round_numbers: rounds.map((r) => r.round),
    },
  };
}

// ------------------------------------------------------- dead end (no goal set)

/**
 * `dead_end` deserves its own scenario because it is **unreachable when targets
 * exist**: with a goal set, `reaches_goal` is `false` for any node with no outgoing
 * edge, and the off_goal branch is checked before the dead-end branch. So a "walked
 * into a corner" node is reported as `off_goal` whenever the caller asked for a
 * goal, and only shows up as `dead_end` when the run has no goal at all. Pinning
 * both keeps that from looking like a port bug later.
 */
function deadEndScenario() {
  const mechanisms = FAST.concat(['diagnosis.bottleneck']);
  const graph = {
    nodes: [
      { id: 's1', name: '起点', type: 'knowledge', ms: 0.9, weight: 1 },
      { id: 'corner', name: '死路', type: 'knowledge', ms: 0.8, weight: 1.3 },
      { id: 'pad', name: '陪跑', type: 'knowledge', ms: 0.7, weight: 1 },
    ],
    edges: [
      { id: 'h_e1', from: 's1', to: 'corner', ls: 1.0 },
      { id: 'h_e2', from: 's1', to: 'pad', ls: 0.9 },
    ],
  };
  const spec = {
    graph,
    initial_nodes: ['s1'],
    target_nodes: [],
    seed: 11,
    hours: 0,
    mechanisms,
    overrides: { 'attention.ignition.T_ign': 0 },
    rounds: 3,
  };

  const engine = buildEngine(spec);
  const run = runRounds(engine, spec.rounds);
  const facts = engine.diagnostic_facts();
  const report = engine.control_report();

  return {
    input: Object.assign({}, spec, {
      module_defaults: moduleDefaults(mechanisms),
      diagnosis_defaults: Object.assign({}, diagnosis.DEFAULTS),
    }),
    expected: {
      run,
      facts,
      diagnosis: report.diagnosis,
      baseline_reachability: report.baseline_reachability,
    },
  };
}

// --------------------------------------------------------------------- danger

/**
 * `danger` is the one bottleneck type `classify` never returns: the metacognition
 * module publishes it (`kernel.m.metacognition.danger`) and the diagnosis hook folds
 * the rows in. So the expectation here is generated with `metacognition.belief`
 * installed, and the fixture carries the published rows as *input* - the Dart port
 * takes them as an argument (it does not port metacognition).
 */
function dangerScenario() {
  const mechanisms = FAST.concat(['metacognition.belief', 'diagnosis.bottleneck']);
  const graph = {
    nodes: [
      { id: 's1', name: '起点', type: 'knowledge', ms: 0.9, weight: 1 },
      { id: 'd1', name: '自信的死角', type: 'knowledge', ms: 0.3, weight: 1.4 },
      { id: 'safe', name: '正常点', type: 'knowledge', ms: 0.95, weight: 1 },
      { id: 't', name: '目标', type: 'knowledge', ms: 0.7, weight: 1, ct: 0.9, st: 0.5 },
    ],
    edges: [
      { id: 'd_e1', from: 's1', to: 'd1', ls: 0.9 },
      { id: 'd_e2', from: 's1', to: 'safe', ls: 0.9 },
      { id: 'd_e3', from: 'd1', to: 't', ls: 0.8 },
    ],
  };
  const spec = {
    graph,
    initial_nodes: ['s1'],
    target_nodes: ['t'],
    seed: 11,
    hours: 0,
    mechanisms,
    overrides: { 'attention.ignition.T_ign': 0 },
    rounds: 3,
  };

  const engine = buildEngine(spec);
  const run = runRounds(engine, spec.rounds);
  const facts = engine.diagnostic_facts();
  const report = engine.control_report();

  return {
    input: Object.assign({}, spec, {
      module_defaults: moduleDefaults(mechanisms),
      diagnosis_defaults: Object.assign({}, diagnosis.DEFAULTS),
      // The rows the port must fold in, published by the real metacognition module.
      danger_rows: (report.metacognition || {}).danger || [],
      anxiety_rows: (report.metacognition || {}).anxiety || [],
      metacognition_calibration: (report.metacognition || {}).calibration,
    }),
    expected: {
      run,
      diagnosis: report.diagnosis,
      danger_entries: report.diagnosis.filter((b) => b.type === 'danger'),
      facts_d1: facts.d1,
    },
  };
}

// ------------------------------------------------------------- counterfactual

/**
 * A scenario the planner can actually price: the target has no incoming edge at all
 * (type `empty`), so its primary instruction is `add_in_edges`, whose metric is
 * **reachability**; a second node is outcompeted by the capacity budget (type
 * `overload`), whose primary is `offload_working_memory`, also reachability.
 *
 * The plan itself is the real `control.planner` hook output, so the retention-metric
 * entries (`lower_threshold`, `strengthen_impression`, `interval_retrieval`) are in
 * there too. They come out at gain 0 because the tierB profile installs no
 * `memory.dsr` - `kernel.review()` has no hook to run - which is exactly what the
 * Dart port reproduces when it is given a retention probe.
 */
function counterfactualScenario() {
  const mechanisms = FAST.concat(['diagnosis.bottleneck', 'control.planner']);
  const graph = {
    nodes: [
      { id: 's1', name: '起点一', type: 'knowledge', ms: 0.9, weight: 1 },
      { id: 's2', name: '起点二', type: 'knowledge', ms: 0.8, weight: 1 },
      { id: 's3', name: '起点三', type: 'knowledge', ms: 0.7, weight: 1 },
      { id: 'n1', name: '高活跃', type: 'knowledge', ms: 0.85, weight: 1 },
      { id: 'n2', name: '中活跃', type: 'knowledge', ms: 0.8, weight: 1 },
      { id: 'n3', name: '被挤出', type: 'knowledge', ms: 0.75, weight: 1 },
      { id: 'lonely', name: '没有入口的目标', type: 'knowledge', ms: 0.6, weight: 2, ct: 0.9, st: 0.5 },
    ],
    edges: [
      { id: 'f1', from: 's1', to: 'n1', ls: 0.95 },
      { id: 'f2', from: 's2', to: 'n1', ls: 0.8 },
      { id: 'f3', from: 's1', to: 'n2', ls: 0.55 },
      { id: 'f4', from: 's3', to: 'n2', ls: 0.5 },
      { id: 'f5', from: 's2', to: 'n3', ls: 0.5 },
      { id: 'f6', from: 's3', to: 'n3', ls: 0.45 },
    ],
  };
  const spec = {
    graph,
    initial_nodes: ['s1', 's2', 's3'],
    target_nodes: ['lonely'],
    seed: 11,
    hours: 0,
    mechanisms,
    overrides: { 'attention.ignition.T_ign': 0 },
    rounds: 4,
    config: { max_rounds: 8 },
  };

  const engine = buildEngine(spec);
  const run = runRounds(engine, spec.rounds);
  const report = engine.control_report();

  return {
    input: Object.assign({}, spec, {
      module_defaults: moduleDefaults(mechanisms),
      diagnosis_defaults: Object.assign({}, diagnosis.DEFAULTS),
      planner_defaults: Object.assign({}, planner.DEFAULTS),
    }),
    expected: {
      run,
      diagnosis: report.diagnosis,
      baseline_reachability: report.baseline_reachability,
      plan: report.plan,
    },
  };
}

// ------------------------------------------------------------------- assemble

function build() {
  const scenarios = {
    engine_diagnosis: engineScenario(),
    weak_node: weakScenario(),
    slow_target: slowScenario(),
    dead_end: deadEndScenario(),
    danger: dangerScenario(),
    counterfactual: counterfactualScenario(),
    multiround_progression: multiroundScenario(),
  };
  let commit = null;
  try {
    commit = execSync('git rev-parse HEAD', { cwd: MINDNET }).toString().trim();
  } catch (err) {
    commit = null;
  }
  return {
    protocol: 'mindnet.tierb-diagnosis/1',
    generated_from: {
      repo: 'https://github.com/FirsryFan/MindNet',
      commit,
      package_version: require(`${MINDNET}/package.json`).version,
      generator: 'app/tool/gen_mindnet_tierb_diagnosis.cjs',
      command: 'node app/tool/gen_mindnet_tierb_diagnosis.cjs',
      note: 'MindNet 侧只读：脚本只 require 其模块，不写任何文件。',
    },
    how_to_use: [
      'Dart 侧读 classify / engine_diagnosis / danger / counterfactual，用 input 调自己的实现，与 expected 逐字段比对。',
      '集合与枚举（state/type/subtype/label/note/also/prescriptions/state_after/instruction/kind）必须完全相等。',
      '浮点先按 tolerances 判"是否一致"，再判"round6 后是否相同"。',
      'engine_diagnosis.expected.facts 是 diagnose 执行**之前**的事实表；diagnosis 是 control_report() 的输出。',
      'counterfactual.expected.plan 是真实 control.planner 的输出；留存类指令（metric=retention）在 tierB 侧需要接线 tierA 才能算出非零增益。',
    ],
    tolerances: {
      rel: 1e-12,
      abs: 1e-15,
      rounded_decimals: 6,
      note: '与 mindnet_vectors.json 同一口径；severity/closeness/gain/value 由 JS 侧 round6 后写出。',
      must_be_exact: ['type', 'subtype', 'label', 'note', 'also', 'prescriptions', 'state', 'instruction', 'simulated', 'stopped', 'stop_reason', 'final_states'],
    },
    classify: classifyCases(),
    scenarios,
  };
}

function main(argv) {
  const args = argv || [];
  const payload = build();
  const text = `${JSON.stringify(payload, null, 2)}\n`;
  if (!args.includes('--dry-run')) {
    fs.mkdirSync(path.dirname(OUT), { recursive: true });
    fs.writeFileSync(OUT, text, 'utf8');
    process.stdout.write(`已写入 ${OUT}\n`);
  }
  const s = payload.scenarios;
  process.stdout.write(
    `classify ${payload.classify.length} 条\n`
    + `engine_diagnosis: rounds_run=${s.engine_diagnosis.expected.run.rounds_run} `
    + `stop=${s.engine_diagnosis.expected.run.stop_reason} `
    + `bottlenecks=${s.engine_diagnosis.expected.diagnosis.map((b) => `${b.node}:${b.type}`).join(',')}\n`
    + `dead_end: bottlenecks=${s.dead_end.expected.diagnosis.map((b) => `${b.node}:${b.type}`).join(',')}\n`
    + `weak_node: bottlenecks=${s.weak_node.expected.diagnosis.map((b) => `${b.node}:${b.type}`).join(',')}\n`
    + `slow_target: rounds_run=${s.slow_target.expected.run.rounds_run} `
    + `bottlenecks=${s.slow_target.expected.diagnosis.map((b) => `${b.node}:${b.type}`).join(',')}\n`
    + `danger: rows=${s.danger.input.danger_rows.length} entries=${s.danger.expected.danger_entries.map((b) => b.node).join(',')}\n`
    + `counterfactual: baseline=${s.counterfactual.expected.baseline_reachability} `
    + `bottlenecks=${s.counterfactual.expected.diagnosis.map((b) => `${b.node}:${b.type}`).join(',')} `
    + `plan=${s.counterfactual.expected.plan.map((p) => `${p.instruction}${p.simulated ? `=${p.gain}` : '(rule)'}`).join(',')}\n`
    + `multiround: round_numbers=[${s.multiround_progression.expected.round_numbers}] `
    + `rounds_run=${s.multiround_progression.expected.run.rounds_run} `
    + `stopped=${s.multiround_progression.expected.run.stopped} `
    + `target_lit_in_round_1=${s.multiround_progression.expected.target_lit_in_round_1} `
    + `distinct_rounds=${new Set(s.multiround_progression.expected.rounds.map((r) => JSON.stringify(r))).size}\n`,
  );
  return 0;
}

if (require.main === module) {
  process.exitCode = main(process.argv.slice(2));
}

module.exports = { build, main, OUT };

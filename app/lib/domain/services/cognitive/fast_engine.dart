/// Pure Dart port of MindNet's **fast layer** (tierB): the round pipeline plus
/// the four deterministic mechanisms it runs.
///
/// Provenance: the reference implementation is the read-only MindNet checkout
/// at `f4eec9b` (`src/model.js`, `src/config.js`, `src/v2/engine.js`,
/// `mechanisms/dynamics.shunting.js`, `mechanisms/attention.capacity.js`,
/// `mechanisms/attention.ignition.js`, `mechanisms/context.goal.js`). The
/// conformance vectors in `test/fixtures/mindnet_vectors.json` were generated
/// by MindNet's own `tools/conformance.js`; `mindnet_fast_conformance_test.dart`
/// fails if this port drifts from them.
///
/// ## What is deliberately *not* ported (and why that is not a shortcut)
///
/// `docs/MINDNET_CONTRACT.md` §6.1 recommends cutting the random sources for the
/// first port so the layer is bit-for-bit comparable, and team decision D3
/// adopts that:
///
/// * `rhythm.gate` is **not** installed, so `availability` is always 1 - the
///   pipeline still computes it through the tick loop, there is simply no gate
///   to close it;
/// * `attention.ignition` is ported whole, but when a temperature `T_ign > 0`
///   makes the ignition probability strictly between 0 and 1, this port
///   **throws** instead of drawing a number: MindNet uses a seeded mulberry32
///   PRNG (`src/core/rng.js`) which is out of scope for this round, and a
///   silent deterministic substitute would be a different model wearing the
///   same name. `T_ign = 0` is the hard threshold and consumes no randomness.
///
/// Everything else the JS engine offers that is **not** here, so a reader can
/// tell "not ported" from "forgotten":
///
/// * `memory.dsr`, `rhythm.gate`, `attention.inhibition`, `legacy_v1.js`
///   (the contract §6.1 lists these as out of scope for tierB);
/// * `metacognition.belief` - its danger rows are *input* to
///   `fast_diagnosis.dart`, not computed here;
/// * the v1.1 compatibility names (`update_memory`, `update_global_memory`,
///   `kc_breakdown`) and `export_state` (file I/O);
/// * the mechanism **registry** (`mechanisms/index.js` is Node-only, and §6.1
///   notes Dart does not need it): the installed set is the `mechanisms` field
///   on [FastEngine], so the pipeline is a fixed sequence of four hooks rather
///   than a plugin lookup.
///
/// ## Units and ownership
///
/// Like the JS, `hours` is an explicit constructor input: there is no clock
/// here, no database and no Flutter. `ms` (a node's current retrievability) is
/// a *state* the fast layer rewrites; it is never durable data (§6.3/§6.4).
///
/// ## Parameter defaults
///
/// `docs/MINDNET_CONTRACT.md` §6.6 singles out default parameter values as the
/// one thing allowed to change between MindNet versions, so they must not be
/// baked into call sites. [FastMechanisms.fromModuleDefaults] reads them from
/// the vectors' `module_defaults` block, and [FastEngine.param] resolves the
/// same "`<mechanism id>.<key>`" paths the JS kernel does, overrides included.
library;

import 'dart:math' as math;

/// Node state, mirroring `STATE` in MindNet's `src/model.js`.
enum FastNodeState {
  conscious('CONSCIOUS'),
  subconscious('SUBCONSCIOUS'),
  inactive('INACTIVE');

  const FastNodeState(this.id);

  /// The wire value; the conformance vectors compare these strings exactly.
  final String id;

  static FastNodeState fromId(Object? id) => switch (id) {
        'CONSCIOUS' => FastNodeState.conscious,
        'SUBCONSCIOUS' => FastNodeState.subconscious,
        _ => FastNodeState.inactive,
      };
}

/// `DEFAULT_CONFIG` from `src/config.js`.
///
/// These are *engine* settings, not mechanism parameters, so they are not part
/// of `module_defaults`; they are collected here once rather than repeated at
/// call sites (§6.6).
class FastConfig {
  const FastConfig({
    this.ctDefault = 0.3,
    this.stDefault = 0.05,
    this.stateCoeffConscious = 1.0,
    this.stateCoeffSubconscious = 0.3,
    this.stateCoeffInactive = 0.0,
    this.maxRounds = 100,
    this.stableRounds = 2,
    this.forgettingK = 24.0,
    this.forgetUpdateThresholdHours = 1.0,
    this.gapConstant = 1.2,
  });

  factory FastConfig.fromJson(Map<String, Object?> json) {
    double d(String key, double fallback) {
      final value = json[key];
      return value is num ? value.toDouble() : fallback;
    }

    return FastConfig(
      ctDefault: d('ct_default', 0.3),
      stDefault: d('st_default', 0.05),
      stateCoeffConscious: d('state_coeff_conscious', 1.0),
      stateCoeffSubconscious: d('state_coeff_subconscious', 0.3),
      stateCoeffInactive: d('state_coeff_inactive', 0.0),
      maxRounds: (json['max_rounds'] as num?)?.toInt() ?? 100,
      stableRounds: (json['stable_rounds'] as num?)?.toInt() ?? 2,
      forgettingK: d('forgetting_k', 24.0),
      forgetUpdateThresholdHours: d('forget_update_threshold_hours', 1.0),
      gapConstant: d('gap_constant', 1.2),
    );
  }

  /// Default consciousness threshold (`ct`).
  final double ctDefault;

  /// Default subconscious threshold (`st`).
  final double stDefault;

  final double stateCoeffConscious;
  final double stateCoeffSubconscious;
  final double stateCoeffInactive;

  /// Round budget.
  final int maxRounds;

  /// Consecutive unchanged rounds that count as "cooling down".
  final int stableRounds;

  /// Stability coefficient; only the memory layer (tierA) uses it. Carried here
  /// because it is part of the same frozen config block.
  final double forgettingK;

  final double forgetUpdateThresholdHours;

  /// Development-zone gap constant (KC impact).
  final double gapConstant;
}

/// One mechanism parameter, with the calibration honesty MindNet demands.
///
/// MindNet's kernel refuses to load a manifest whose parameters do not declare
/// `calibrated` explicitly (`src/core/kernel.js`), because "未标定" is the whole
/// point: these numbers are magnitude-plausible placeholders, not measurements
/// (§6.7 item 4). The port keeps that flag instead of flattening it away.
class FastParamSpec {
  const FastParamSpec({
    required this.mechanism,
    required this.key,
    required this.defaultValue,
    required this.calibrated,
    this.min,
    this.max,
    this.unit = '-',
    this.desc = '',
    this.evidence = '',
  });

  final String mechanism;
  final String key;
  final double defaultValue;

  /// `false` means **未标定 / NOT CALIBRATED**: no calibration source exists.
  final bool calibrated;

  final double? min;
  final double? max;
  final String unit;
  final String desc;
  final String evidence;

  /// The kernel's parameter path, e.g. `attention.capacity.W_DAR`.
  String get path => '$mechanism.$key';

  FastParamSpec withDefault(double value) => FastParamSpec(
        mechanism: mechanism,
        key: key,
        defaultValue: value,
        min: min,
        max: max,
        unit: unit,
        calibrated: calibrated,
        desc: desc,
        evidence: evidence,
      );
}

/// The mechanism parameters (and overrides) one engine run uses.
///
/// Built either from the conformance vectors' `module_defaults` block or
/// explicitly. The parameter *tables* mirror the `PARAMS` arrays of the four
/// ported mechanisms, including which entries MindNet marks calibrated.
class FastMechanisms {
  const FastMechanisms._(this.ids, this.specs, this.overrides);

  /// Builds the parameter set for [ids] (a subset of the four ported
  /// mechanisms) from a `module_defaults` map.
  ///
  /// A key missing from [moduleDefaults] falls back to the transcribed MindNet
  /// default; a mechanism absent from [ids] is simply not installed, and the
  /// pipeline then degenerates exactly as the JS does without that module.
  factory FastMechanisms.fromModuleDefaults(
    Map<String, Object?> moduleDefaults, {
    required List<String> ids,
    Map<String, Object?> overrides = const {},
  }) {
    final specs = <FastParamSpec>[];
    for (final spec in _allSpecs) {
      if (!ids.contains(spec.mechanism)) {
        continue;
      }
      final forMechanism =
          (moduleDefaults[spec.mechanism] as Map?)?.cast<String, Object?>();
      final fromVectors = forMechanism?[spec.key];
      specs.add(fromVectors is num
          ? spec.withDefault(fromVectors.toDouble())
          : spec);
    }
    return FastMechanisms._(List<String>.unmodifiable(ids), specs, overrides);
  }

  /// An empty set: no mechanism is installed, so the engine degenerates to the
  /// JS's "static field" (activation never changes, hard thresholds, no
  /// capacity limit).
  static const FastMechanisms none =
      FastMechanisms._(<String>[], <FastParamSpec>[], <String, Object?>{});

  /// Enabled mechanism ids, in installation order (the JS kernel's `_order`).
  final List<String> ids;

  final List<FastParamSpec> specs;
  final Map<String, Object?> overrides;

  static const String shunting = 'dynamics.shunting';
  static const String capacity = 'attention.capacity';
  static const String ignition = 'attention.ignition';
  static const String goal = 'context.goal';

  bool isEnabled(String id) => ids.contains(id);

  FastParamSpec? specOf(String path) {
    for (final spec in specs) {
      if (spec.path == path) {
        return spec;
      }
    }
    return null;
  }

  /// Every declared parameter that is **未标定**, for the docs/UI that must
  /// say so (§6.4, §6.7 item 4).
  List<FastParamSpec> get uncalibrated =>
      [for (final spec in specs) if (!spec.calibrated) spec];

  /// The transcribed `PARAMS` tables of the four ported mechanisms.
  ///
  /// `calibrated: true` here means "MindNet cites a source for the value"
  /// (Cowan/Oberauer for the capacity budgets); everything else is a
  /// magnitude-plausible default and says so.
  static const List<FastParamSpec> _allSpecs = [
    FastParamSpec(
      mechanism: shunting,
      key: 'alpha_a',
      defaultValue: 0.5,
      min: 0.001,
      max: 5,
      calibrated: false,
      desc: '驱动对激活的增益',
      evidence: '未标定（分流方程形式取自 Cognitive_Architecture §3.6）',
    ),
    FastParamSpec(
      mechanism: shunting,
      key: 'lambda_a',
      defaultValue: 0.2,
      min: 0,
      max: 1,
      unit: '1/轮',
      calibrated: false,
      desc: '每轮激活衰减',
      evidence: '未标定',
    ),
    FastParamSpec(
      mechanism: shunting,
      key: 'eta_q',
      defaultValue: 0.5,
      min: 0,
      max: 2,
      unit: '1/轮',
      calibrated: false,
      desc: '亚阈累积速率',
      evidence: '未标定',
    ),
    FastParamSpec(
      mechanism: shunting,
      key: 'lambda_q',
      defaultValue: 0.3,
      min: 0,
      max: 1,
      unit: '1/轮',
      calibrated: false,
      desc: '亚阈累积的衰减',
      evidence: '未标定',
    ),
    FastParamSpec(
      mechanism: capacity,
      key: 'W_DAR',
      defaultValue: 4.0,
      min: 0.1,
      max: 100,
      unit: '激活单位',
      calibrated: true,
      desc: '直接访问区容量预算（以激活量计，不是个数）',
      evidence: 'Cowan 3–5 组块 / Oberauer DAR≈4（PMC4500897）',
    ),
    FastParamSpec(
      mechanism: capacity,
      key: 'W_FA',
      defaultValue: 1.0,
      min: 0.1,
      max: 10,
      unit: '激活单位',
      calibrated: true,
      desc: '注意焦点容量预算（窄焦点一次一个）',
      evidence: 'Oberauer 窄焦点 = 1 项（PMC4500897）',
    ),
    FastParamSpec(
      mechanism: ignition,
      key: 'T_ign',
      defaultValue: 0.05,
      min: 0,
      max: 1,
      calibrated: false,
      desc: '点火温度：0 = 硬阈值（v1.1 行为）',
      evidence: '未标定（sigmoid 阈值形式取自 Cognitive_Architecture §3.4）',
    ),
    FastParamSpec(
      mechanism: goal,
      key: 'beta_goal',
      defaultValue: 0.3,
      min: 0,
      max: 3,
      calibrated: false,
      desc: '目标偏置强度',
      evidence: '未标定（Application_Protocol §15）',
    ),
    FastParamSpec(
      mechanism: goal,
      key: 'kappa_reach',
      defaultValue: 0.5,
      min: 0.05,
      max: 0.95,
      calibrated: false,
      desc: '每远离目标一跳，相关性的折扣',
      evidence: '未标定',
    ),
    FastParamSpec(
      mechanism: goal,
      key: 'fan_k',
      defaultValue: 0,
      min: 0,
      max: 1,
      calibrated: false,
      desc: 'fan 效应修正（0 = 关闭）',
      evidence: '未标定',
    ),
  ];
}

/// One node, mirroring MindNet's `Node` (`src/model.js`) minus the
/// serialization extras the fast layer never reads.
class FastNode {
  FastNode({
    required this.id,
    required this.name,
    required this.type,
    this.weight = 1.0,
    this.ms = 0.8,
    this.ct,
    this.st,
    this.state = FastNodeState.inactive,
    this.al = 0.0,
    this.visitCount = 0,
    this.lastReviewTime,
    this.stm = 0.0,
    Map<String, Object?>? m,
    Map<String, double>? core,
  })  : m = m ?? <String, Object?>{},
        core = core ?? <String, double>{'a': 0, 'q': 0};

  /// Node id (a tag id, once projected: §6.4).
  final String id;

  /// Display name.
  final String name;

  /// `knowledge` / `logic` / `technique`.
  final String type;

  /// Importance / influence. **Not** memory strength (§6.4).
  final double weight;

  /// A *state*: the current retrievability `R = R0·Ψ(t/S)` evaluated now. The
  /// fast layer rewrites it every round, so it is never durable data (§6.3).
  double ms;

  /// Per-node consciousness threshold override, or null for
  /// [FastConfig.ctDefault].
  final double? ct;

  /// Per-node subconscious threshold override, or null for
  /// [FastConfig.stDefault].
  final double? st;

  FastNodeState state;
  double al;
  final int visitCount;
  double? lastReviewTime;
  final double stm;

  /// Mechanism-private per-node state, keyed by mechanism namespace
  /// (`memory_dsr`, …). Deep-copied on [FastEngine.clone], like the JS does.
  final Map<String, Object?> m;

  /// Shared fast state: `a` (activation) and `q` (sub-threshold accumulation).
  final Map<String, double> core;

  double get activation => core['a'] ?? 0;

  double get subthreshold => core['q'] ?? 0;

  double ctOf(FastConfig config) => ct ?? config.ctDefault;

  double stOf(FastConfig config) => st ?? config.stDefault;

  void resetRuntime() {
    state = FastNodeState.inactive;
    al = 0.0;
  }

  FastNode copy() => FastNode(
        id: id,
        name: name,
        type: type,
        weight: weight,
        ms: ms,
        ct: ct,
        st: st,
        state: state,
        al: al,
        visitCount: visitCount,
        lastReviewTime: lastReviewTime,
        stm: stm,
        m: deepCopyMap(m),
        core: {'a': core['a'] ?? 0, 'q': core['q'] ?? 0},
      );

  /// The JS `to_object` subset the fast layer and its facts table read.
  Map<String, Object?> toJson(FastConfig config) => {
        'id': id,
        'name': name,
        'type': type,
        'weight': weight,
        'ms': ms,
        'ct': ct,
        'st': st,
        'state': state.id,
        'al': al,
        'visit_count': visitCount,
        'last_review_time': lastReviewTime,
        'stm': stm,
        'effective_ct': ctOf(config),
        'effective_st': stOf(config),
        if (m.isNotEmpty) 'm': deepCopyMap(m),
      };
}

/// One directed cue: "thinking of [from] brings [to] to mind".
class FastEdge {
  const FastEdge({
    required this.id,
    required this.from,
    required this.to,
    this.ls = 0.8,
  });

  final String id;
  final String from;
  final String to;

  /// Link strength. **未标定 / NOT CALIBRATED** when it comes from the tag-tree
  /// projection (§6.4); the vectors supply their own values.
  final double ls;

  Map<String, Object?> toJson() =>
      {'id': id, 'from': from, 'to': to, 'ls': ls};
}

/// MindNet's graph for the fast layer: insertion-ordered nodes, in/out edge
/// indexes, and the load-time validation `Graph.from_object` performs.
class FastGraph {
  FastGraph();

  final Map<String, FastNode> nodes = <String, FastNode>{};
  final List<FastEdge> edges = <FastEdge>[];
  final Map<String, List<FastEdge>> _out = <String, List<FastEdge>>{};
  final Map<String, List<FastEdge>> _in = <String, List<FastEdge>>{};

  /// Builds a graph from the frozen input format
  /// `{nodes: [{id,name,type,ms?,weight?,ct?,st?,m?}], edges: [{id,from,to,ls}]}`
  /// (§6.6), fixing `last_review_time` exactly as the JS does.
  ///
  /// This is also the bridge from `cognitive_graph.dart`: that projection's
  /// `CognitiveGraph.toJson()` emits this same shape, so
  /// `FastGraph.fromSpec(cognitiveGraph.toJson(), currentRealTime: 0)` is the
  /// whole adapter - one direction, no second graph model.
  factory FastGraph.fromSpec(
    Map<String, Object?> spec, {
    double? currentRealTime,
  }) {
    var rawNodes = spec['nodes'];
    if (rawNodes is Map) {
      // The engine's own `state()` export uses the {id: node} form; accept it
      // the way `Graph.from_object` does.
      rawNodes = [
        for (final entry in rawNodes.entries)
          if (entry.value is Map)
            {...(entry.value! as Map).cast<String, Object?>(), 'id': entry.key}
          else
            entry.value,
      ];
    }
    if (rawNodes is! List) {
      throw ArgumentError('图数据缺少 "nodes" 数组');
    }
    final rawEdges = spec['edges'] ?? const <Object?>[];
    if (rawEdges is! List) {
      throw ArgumentError('图数据的 "edges" 必须是数组');
    }

    final graph = FastGraph();
    for (final raw in rawNodes) {
      if (raw is! Map) {
        throw ArgumentError('节点必须是对象，实际为 $raw');
      }
      graph.addNode(FastNode(
        id: _requiredString(raw, 'id', '节点'),
        name: _requiredString(raw, 'name', '节点'),
        type: _requiredString(raw, 'type', '节点'),
        weight: _optionalNumber(raw, 'weight') ?? 1.0,
        ms: _optionalNumber(raw, 'ms') ?? 0.8,
        ct: raw['ct'] == null ? null : _optionalNumber(raw, 'ct'),
        st: raw['st'] == null ? null : _optionalNumber(raw, 'st'),
        state: FastNodeState.fromId(raw['state']),
        al: _optionalNumber(raw, 'al') ?? 0.0,
        visitCount: (_optionalNumber(raw, 'visit_count') ?? 0).toInt(),
        lastReviewTime: _optionalNumber(raw, 'last_review_time'),
        stm: _optionalNumber(raw, 'stm') ?? 0.0,
        m: raw['m'] is Map
            ? deepCopyMap((raw['m']! as Map).cast<String, Object?>())
            : null,
      ));
    }
    for (final raw in rawEdges) {
      if (raw is! Map) {
        throw ArgumentError('边必须是对象，实际为 $raw');
      }
      graph.addEdge(FastEdge(
        id: _requiredString(raw, 'id', '边'),
        from: _requiredString(raw, 'from', '边'),
        to: _requiredString(raw, 'to', '边'),
        ls: _optionalNumber(raw, 'ls') ?? 0.8,
      ));
    }

    graph.fixLastReviewTime(currentRealTime ?? 0);
    return graph;
  }

  int get size => nodes.length;

  bool hasNode(String id) => nodes.containsKey(id);

  FastNode? getNode(String id) => nodes[id];

  List<FastEdge> outEdges(String id) => _out[id] ?? const <FastEdge>[];

  List<FastEdge> inEdges(String id) => _in[id] ?? const <FastEdge>[];

  List<String> nodeIds() => nodes.keys.toList();

  FastNode addNode(FastNode node) {
    if (nodes.containsKey(node.id)) {
      throw ArgumentError('节点 id 重复："${node.id}"');
    }
    nodes[node.id] = node;
    _out[node.id] = <FastEdge>[];
    _in[node.id] = <FastEdge>[];
    return node;
  }

  FastEdge addEdge(FastEdge edge) {
    if (!nodes.containsKey(edge.from)) {
      throw ArgumentError('边 "${edge.id}" 的起点 "${edge.from}" 不存在于图中');
    }
    if (!nodes.containsKey(edge.to)) {
      throw ArgumentError('边 "${edge.id}" 的终点 "${edge.to}" 不存在于图中');
    }
    edges.add(edge);
    _out[edge.from]!.add(edge);
    _in[edge.to]!.add(edge);
    return edge;
  }

  /// `last_review_time` of 0 / missing becomes the current real time (§3.1).
  void fixLastReviewTime(double currentRealTime) {
    for (final node in nodes.values) {
      if (node.lastReviewTime == null || node.lastReviewTime == 0) {
        node.lastReviewTime = currentRealTime;
      }
    }
  }

  /// Deep copy: nodes (identity + state + `m` bag + `core`) and edges.
  FastGraph copy() {
    final graph = FastGraph();
    for (final node in nodes.values) {
      graph.addNode(node.copy());
    }
    for (final edge in edges) {
      graph.addEdge(
          FastEdge(id: edge.id, from: edge.from, to: edge.to, ls: edge.ls));
    }
    return graph;
  }

  Map<String, Object?> toJson() => {
        'nodes': [
          for (final node in nodes.values) node.toJson(const FastConfig()),
        ],
        'edges': [for (final edge in edges) edge.toJson()],
      };
}

/// One term of a round's drive: an in-edge contribution, the sub-threshold
/// accumulator, or a module's rewrite (the goal bias).
class FastDriveEdge {
  const FastDriveEdge({
    required this.from,
    required this.to,
    this.edgeId,
    required this.kind,
    this.module,
    this.ls,
    this.al,
    this.ms,
    required this.contribution,
  });

  final String? from;
  final String to;
  final String? edgeId;

  /// `edge` / `subthreshold` / `module`; the vectors compare this exactly.
  final String kind;

  final String? module;
  final double? ls;
  final double? al;
  final double? ms;

  /// Rounded to 6 decimals, exactly as the JS records it.
  final double contribution;

  Map<String, Object?> toJson() => {
        'from': from,
        'to': to,
        'edge_id': edgeId,
        'kind': kind,
        if (module != null) 'module': module,
        'ls': ls,
        'al': al,
        'ms': ms,
        'contribution': contribution,
      };
}

/// The per-node ignition trace (`payload.ignition` in the JS): the record that
/// answers "why did this node not light up this round".
class FastIgnitionRecord {
  const FastIgnitionRecord({
    required this.node,
    required this.score,
    required this.ct,
    required this.st,
    required this.tIgn,
    required this.p,
    required this.draw,
    required this.hit,
  });

  final String node;
  final double score;
  final double ct;
  final double st;
  final double tIgn;
  final double p;

  /// Always null in this round: a hard threshold (`T_ign = 0`) draws nothing.
  final double? draw;

  final bool hit;

  Map<String, Object?> toJson() => {
        'node': node,
        'score': score,
        'ct': ct,
        'st': st,
        't_ign': tIgn,
        'p': p,
        'draw': draw,
        'hit': hit,
      };
}

/// One node's state transition in a round, with the activation *after*
/// `state.after` ran (the JS only fills `rec.al` then).
class FastStateChange {
  FastStateChange({
    required this.id,
    required this.stateBefore,
    required this.stateAfter,
    this.al = 0,
  });

  final String id;
  final FastNodeState stateBefore;
  FastNodeState stateAfter;

  /// Rounded to 6 decimals, like the JS.
  double al;
}

/// Everything one round produced. The generator reads exactly these fields off
/// `engine._lastRound`, which is why they are this port's public shape.
class FastRoundSnapshot {
  FastRoundSnapshot({
    required this.round,
    required this.cycleTicks,
    required this.availability,
    required this.drive,
    required this.driveEdges,
    required this.scores,
    required this.admitted,
    required this.focus,
    required this.darUsed,
    required this.outcompeted,
    required this.conscious,
    required this.subconscious,
    required this.states,
    required this.a,
    required this.q,
    required this.ignition,
  });

  final int round;
  final int cycleTicks;
  final double availability;

  /// Raw drive, per node.
  final Map<String, double> drive;
  final List<FastDriveEdge> driveEdges;
  final Map<String, double> scores;
  final List<String>? admitted;
  final String? focus;
  final double? darUsed;
  final List<String>? outcompeted;
  final List<String> conscious;
  final List<String> subconscious;
  final List<FastStateChange> states;

  /// Raw activation / sub-threshold accumulation at the end of the round.
  final Map<String, double> a;
  final Map<String, double> q;
  final List<FastIgnitionRecord> ignition;

  /// The published form: the same rounding `tools/conformance.js` applies.
  Map<String, Object?> toJson() => {
        'round': round,
        'cycle_ticks': cycleTicks,
        'availability': FastEngine.round6(availability),
        'drive': {
          for (final entry in drive.entries)
            entry.key: FastEngine.round6(entry.value),
        },
        'drive_edges': [for (final edge in driveEdges) edge.toJson()],
        'scores': {
          for (final entry in scores.entries)
            entry.key: FastEngine.round6(entry.value),
        },
        'admitted': admitted,
        'focus': focus,
        'dar_used': darUsed,
        'outcompeted': outcompeted,
        'conscious': conscious,
        'subconscious': subconscious,
        'states': [
          for (final change in states)
            {
              'id': change.id,
              'state_after': change.stateAfter.id,
              'al': change.al,
            },
        ],
        'a': {
          for (final entry in a.entries)
            entry.key: FastEngine.round6(entry.value),
        },
        'q': {
          for (final entry in q.entries)
            entry.key: FastEngine.round6(entry.value),
        },
      };
}

/// The payload one `step()` builds; it mirrors `engine.js`'s `payload` for the
/// fields the ported mechanisms read or write.
class _RoundPayload {
  _RoundPayload({required this.round});

  final int round;
  int cycleTicks = 1;
  double availability = 1;
  List<String> targets = const <String>[];
  Map<String, double> drive = <String, double>{};
  final List<FastDriveEdge> driveEdges = <FastDriveEdge>[];
  Map<String, double> scores = <String, double>{};
  Map<String, double>? next;
  List<String>? admitted;
  String? focus;
  double? darUsed;
  List<String>? outcompeted;
  List<String>? conscious;
  List<String>? subconscious;
  final List<FastIgnitionRecord> ignition = <FastIgnitionRecord>[];
  final List<FastStateChange> stateChanges = <FastStateChange>[];
}

/// What one `step()` reports (`engine._status`).
class FastStatus {
  const FastStatus({
    required this.round,
    required this.activated,
    required this.stopped,
    required this.stopReason,
  });

  final int round;
  final List<Map<String, Object?>> activated;
  final bool stopped;
  final String? stopReason;
}

/// Stop reasons, mirroring `STOP` in `engine.js`.
abstract final class FastStop {
  static const String allTargetsReached = 'all_targets_reached';
  static const String cooling = 'cooling';
  static const String maxRounds = 'max_rounds';
}

/// The four outputs of `engine.result()`.
class FastResult {
  const FastResult({
    required this.gap,
    required this.penalty,
    required this.targetSteps,
    required this.targetsAllReached,
    required this.finalStates,
  });

  final double gap;
  final double penalty;
  final Map<String, int> targetSteps;
  final bool targetsAllReached;
  final Map<String, String> finalStates;

  Map<String, Object?> toJson() => {
        'kc': {'gap': gap, 'penalty': penalty},
        'target_steps': targetSteps,
        'targets_all_reached': targetsAllReached,
        'final_states': finalStates,
      };
}

/// The flat fact table `engine.diagnostic_facts()` produces: everything the
/// control layer needs to answer "why did this node not light up".
class FastDiagnosticFact {
  const FastDiagnosticFact({
    required this.id,
    required this.name,
    required this.state,
    required this.a,
    required this.q,
    required this.drive,
    required this.score,
    required this.peakDrive,
    required this.ct,
    required this.st,
    required this.inDegree,
    required this.outDegree,
    required this.everActivated,
    required this.firstActivationRound,
    required this.activatedAtRound,
    required this.outcompeted,
    required this.isTarget,
    required this.isStart,
    required this.r,
    required this.r0,
    required this.s,
    required this.d,
    required this.f,
  });

  final String id;
  final String name;
  final FastNodeState state;
  final double a;
  final double q;
  final double drive;
  final double score;
  final double peakDrive;
  final double ct;
  final double st;
  final int inDegree;
  final int outDegree;
  final bool everActivated;
  final int? firstActivationRound;
  final int? activatedAtRound;
  final bool outcompeted;
  final bool isTarget;
  final bool isStart;

  /// `node.ms` - the exported retrievability (§6.3).
  final double r;

  /// Memory-layer state: null/0 while `memory.dsr` is not installed, which is
  /// the case for the tierB profile.
  final double? r0;
  final double? s;
  final double? d;
  final double f;

  /// Reads the JS fact-object shape (used by the diagnosis vectors, whose
  /// `classify` cases carry the JS facts verbatim).
  factory FastDiagnosticFact.fromJson(Map<String, Object?> json) {
    double d(String key, [double fallback = 0]) {
      final value = json[key];
      return value is num ? value.toDouble() : fallback;
    }

    final r0 = json['R0'];
    final s = json['S'];
    final dd = json['D'];
    return FastDiagnosticFact(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      state: FastNodeState.fromId(json['state']),
      a: d('a'),
      q: d('q'),
      drive: d('drive'),
      score: d('score'),
      peakDrive: d('peak_drive'),
      ct: d('ct'),
      st: d('st'),
      inDegree: (json['in_degree'] as num?)?.toInt() ?? 0,
      outDegree: (json['out_degree'] as num?)?.toInt() ?? 0,
      everActivated: json['ever_activated'] == true,
      firstActivationRound: (json['first_activation_round'] as num?)?.toInt(),
      activatedAtRound: (json['activated_at_round'] as num?)?.toInt(),
      outcompeted: json['outcompeted'] == true,
      isTarget: json['is_target'] == true,
      isStart: json['is_start'] == true,
      r: d('R'),
      r0: r0 is num ? r0.toDouble() : null,
      s: s is num ? s.toDouble() : null,
      d: dd is num ? dd.toDouble() : null,
      f: d('F'),
    );
  }

  /// The JS field names, with the JS's rounding.
  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'state': state.id,
        'a': FastEngine.round6(a),
        'q': FastEngine.round6(q),
        'drive': FastEngine.round6(drive),
        'score': FastEngine.round6(score),
        'peak_drive': FastEngine.round6(peakDrive),
        'ct': ct,
        'st': st,
        'in_degree': inDegree,
        'out_degree': outDegree,
        'ever_activated': everActivated,
        'first_activation_round': firstActivationRound,
        'activated_at_round': activatedAtRound,
        'outcompeted': outcompeted,
        'is_target': isTarget,
        'is_start': isStart,
        'R': FastEngine.round6(r),
        'R0': r0 == null ? null : FastEngine.round6(r0!),
        'S': s == null ? null : FastEngine.round6(s!),
        'D': d == null ? null : FastEngine.round6(d!),
        'F': f,
      };
}

/// `get_kc()`'s two numbers.
class FastKc {
  const FastKc({required this.gap, required this.penalty});

  final double gap;

  /// Dead-end penalty. The memory-layer branch of the JS `_penalty()` is not
  /// ported (the tierB profile does not install `memory.dsr`, and the JS falls
  /// back to this same v1.1 count-based rule in that case).
  final double penalty;
}

/// Dart port of `src/v2/engine.js`'s `FastEngine`, restricted to the tierB
/// mechanism set.
///
/// The pipeline order is the JS's, step for step:
/// `round.before` → tick loop (`tick.before`/`tick.gate`) → `drive.compute`
/// → `activation.update` → starts pinned back to `a = 1` → `attention.select`
/// → `ignite.check` → state landing → `state.after` → peak-drive bookkeeping
/// → `round.after` → stop checks. Deviating from that order silently changes
/// the numbers, so it is spelled out here rather than "tidied up".
class FastEngine {
  FastEngine({
    required this.graph,
    this.config = const FastConfig(),
    this.mechanisms = FastMechanisms.none,
    Map<String, Object?> overrides = const <String, Object?>{},
    this.seed = 11,
    this.hours = 0,
  }) : overrides = <String, Object?>{
          ...mechanisms.overrides,
          ...overrides,
        } {
    _maxRounds = config.maxRounds;
  }

  /// The graph under simulation. Its `core['a']`/`core['q']` and node states
  /// are the shared fast state the pipeline writes.
  final FastGraph graph;

  final FastConfig config;

  /// Parameter table + which mechanisms are installed.
  final FastMechanisms mechanisms;

  /// Parameter overrides keyed by full path (`attention.ignition.T_ign`), per
  /// engine: the counterfactual planner mutates a *clone's* overrides, never
  /// the original's (the JS kernel copies defensively for the same reason).
  final Map<String, Object?> overrides;

  /// Recorded for provenance (the vectors pin `seed`); unused this round:
  /// with `T_ign = 0` and no `rhythm.gate` there is no random draw to seed
  /// (D3, §6.1).
  final int seed;

  /// Simulated "now" in hours; passed in, never read from a clock.
  double hours;

  /// Ticks consumed so far (the JS kernel's `tick`).
  int tick = 0;

  int _rounds = 0;
  final Set<String> _starts = <String>{};
  List<String> _startOrder = <String>[];
  List<String> _targets = <String>[];
  final Set<String> _targetSet = <String>{};
  Map<String, int> _targetSteps = <String, int>{};
  Set<String> _everActivated = <String>{};
  Map<String, int> _firstActivation = <String, int>{};
  Map<String, double> _peakDrive = <String, double>{};
  Set<String> _attempted = <String>{};
  List<String> _pendingStarts = <String>[];
  String? _prevSnapshot;
  int _quiet = 0;
  bool _running = false;
  bool _stopped = false;
  String? _stopReason;
  bool _targetsAllReached = false;
  late int _maxRounds;

  /// The last *completed* round. Retained across no-op `step()` calls exactly
  /// like the JS, which is why the B01 vectors repeat round 1 five times: the
  /// diffusion stops after round 1 (the target was activated) and the generator
  /// keeps reading `_lastRound`.
  FastRoundSnapshot? lastRound;

  // --------------------------------------------------------------- read-only

  int get rounds => _rounds;
  bool get running => _running;
  bool get stopped => _stopped;
  String? get stopReason => _stopReason;
  bool get targetsAllReached => _targetsAllReached;
  List<String> get starts => List<String>.unmodifiable(_startOrder);
  List<String> get targets => List<String>.unmodifiable(_targets);
  Set<String> get everActivated => Set<String>.unmodifiable(_everActivated);
  Set<String> get attemptedThisDiffusion =>
      Set<String>.unmodifiable(_attempted);
  Map<String, int> get targetSteps =>
      Map<String, int>.unmodifiable(_targetSteps);
  Map<String, int> get firstActivation =>
      Map<String, int>.unmodifiable(_firstActivation);
  Map<String, double> get peakDrive =>
      Map<String, double>.unmodifiable(_peakDrive);

  double activationOf(String nodeId) => _node(nodeId).activation;

  double subthresholdOf(String nodeId) => _node(nodeId).subthreshold;

  FastNode _node(String nodeId) {
    final node = graph.nodes[nodeId];
    if (node == null) {
      throw ArgumentError('节点 "$nodeId" 不存在');
    }
    return node;
  }

  /// The JS `kernel.param(path, fallback)`: longest-prefix match over the
  /// installed mechanisms, overrides first.
  Object? param(String path, [Object? fallback]) {
    for (final id in mechanisms.ids) {
      if (!path.startsWith('$id.')) {
        continue;
      }
      final spec = mechanisms.specOf(path);
      if (spec == null) {
        continue;
      }
      if (overrides.containsKey(path)) {
        return overrides[path];
      }
      return spec.defaultValue;
    }
    if (fallback != null) {
      return fallback;
    }
    throw ArgumentError('找不到参数 "$path"');
  }

  /// [param] as a `double` (the JS `ctx.param` shape for numeric parameters).
  double numberParam(String path, [double? fallback]) {
    final value = param(path, fallback);
    if (value is num) {
      return value.toDouble();
    }
    throw ArgumentError('参数 "$path" 不是数字：$value');
  }

  // -------------------------------------------------------------- lifecycle

  FastEngine startDiffusion(
    List<String> initialNodes,
    List<String> targetNodes,
  ) {
    _requireNodes(initialNodes, '起点');
    _requireNodes(targetNodes, '目标节点');

    _resetRuntime();
    for (final node in graph.nodes.values) {
      node.resetRuntime();
      node.core['a'] = 0;
      node.core['q'] = 0;
    }
    _maxRounds = config.maxRounds;
    _running = true;
    _stopped = false;
    _stopReason = null;
    _targetsAllReached = false;

    for (final id in initialNodes) {
      if (_starts.contains(id)) {
        continue;
      }
      _starts.add(id);
      _startOrder.add(id);
      final node = _node(id);
      node.core['a'] = 1; // 注意焦点：被维持在意识里的东西
      node.state = FastNodeState.conscious;
      node.al = 1;
    }
    for (final id in targetNodes) {
      if (_targetSet.contains(id)) {
        continue;
      }
      _targets.add(id);
      _targetSet.add(id);
      if (_starts.contains(id)) {
        _targetSteps[id] = 0;
      }
    }
    _prevSnapshot = _snapshot();
    if (_targets.isNotEmpty && _allTargetsActive()) {
      _stop(FastStop.allTargetsReached, true);
    }
    return this;
  }

  /// Queues extra starting points; they become active at the next `step()`.
  ({List<String> queued, List<String> skipped}) addInitialNodes(
    List<String> ids,
  ) {
    if (!_running) {
      throw StateError('尚未调用 startDiffusion()，无法追加起点');
    }
    if (_stopped) {
      throw StateError('扩散已停止（$_stopReason），无法追加起点；请重新 startDiffusion()');
    }
    _requireNodes(ids, '追加起点');
    final queued = <String>[];
    final skipped = <String>[];
    for (final id in ids) {
      if (_starts.contains(id) || _pendingStarts.contains(id)) {
        skipped.add(id);
        continue;
      }
      _pendingStarts.add(id);
      queued.add(id);
    }
    return (queued: queued, skipped: skipped);
  }

  // --------------------------------------------------------------- one round

  /// One round of the pipeline. After [stopped] this is a no-op that leaves
  /// [lastRound] untouched - a detail the vectors depend on.
  FastStatus step() {
    if (!_running) {
      throw StateError('尚未调用 startDiffusion()');
    }
    if (_stopped) {
      return _status(<Map<String, Object?>>[]);
    }

    _rounds += 1;
    final nodes = graph.nodes.values.toList();
    final activated = <Map<String, Object?>>[];

    // 0) appended starting points take effect at the start of the next round
    if (_pendingStarts.isNotEmpty) {
      final pending = _pendingStarts;
      _pendingStarts = <String>[];
      for (final id in pending) {
        _starts.add(id);
        _startOrder.add(id);
        _node(id).core['a'] = 1;
        activated.add({
          'id': id,
          'state': FastNodeState.conscious.id,
          'drive': null,
          'reason': 'added_start',
        });
      }
    }

    final payload = _RoundPayload(round: _rounds)
      ..targets = List<String>.of(_targets);

    // 1) round.before: tick length, budget, targets/context. No ported
    //    mechanism hooks this slot, so cycleTicks stays 1 (rhythm.gate is not
    //    installed, D3).
    payload.cycleTicks = math.max(1, payload.cycleTicks.round());

    // 2) tick loop: with no rhythm.gate every tick is open, so availability is
    //    exactly 1 - computed through the loop, not assumed.
    var openTicks = 0;
    for (var i = 0; i < payload.cycleTicks; i += 1) {
      tick += 1;
      openTicks += 1; // tick.gate is not installed: never blocked
    }
    payload.availability = openTicks / payload.cycleTicks;

    // 3) drive: in-edge sum + sub-threshold accumulation, then modules may
    //    rewrite it (context.goal). Every rewrite is recorded per node so that
    //    "sum of the terms == drive" stays checkable.
    payload.drive = _rawDrive(payload.driveEdges);
    final driveBeforeHook = Map<String, double>.of(payload.drive);
    if (mechanisms.isEnabled(FastMechanisms.goal)) {
      _goalDriveCompute(payload);
    }
    for (final entry in payload.drive.entries) {
      final previous = driveBeforeHook[entry.key] ?? 0;
      if ((entry.value - previous).abs() > 1e-12) {
        payload.driveEdges.add(FastDriveEdge(
          from: null,
          to: entry.key,
          kind: 'module',
          module: 'drive.compute',
          contribution: round6(entry.value - previous),
        ));
      }
    }

    // 4) activation update (shunting: exact integral, not an Euler step)
    if (mechanisms.isEnabled(FastMechanisms.shunting)) {
      payload.next = _shuntingActivationUpdate(payload);
    }
    if (payload.next != null) {
      _applyActivation(payload.next!);
    }
    // 4b) the start nodes are held in consciousness every round: the mechanism
    //     behind "keep the question in your head" (the v2 form of v1.1's
    //     "starts stay lit forever").
    for (final id in _startOrder) {
      _node(id).core['a'] = 1;
    }

    // 5) competition scores and two-level capacity admission
    payload.scores = _scores();
    final candidates = _candidates(payload.scores);
    if (mechanisms.isEnabled(FastMechanisms.capacity)) {
      _capacitySelect(payload);
    }
    final Set<String> admitted = payload.admitted != null
        ? payload.admitted!.toSet()
        : <String>{...candidates};

    // 6) ignition: defaults first, then the module may override
    final fallback = _defaultIgnition(admitted, payload.scores);
    payload.conscious = fallback.conscious;
    payload.subconscious = fallback.subconscious;
    if (mechanisms.isEnabled(FastMechanisms.ignition)) {
      _ignitionCheck(payload);
    }
    final conscious = <String>{...?payload.conscious};
    final subconscious = <String>{...?payload.subconscious};
    for (final id in _startOrder) {
      conscious.add(id);
    }

    // 7) land the states (`al` is synced after state.after, so a module that
    //    adjusts activation there is reflected).
    for (final node in nodes) {
      final before = node.state;
      if (conscious.contains(node.id)) {
        node.state = FastNodeState.conscious;
      } else if (subconscious.contains(node.id)) {
        node.state = FastNodeState.subconscious;
      } else {
        node.state = FastNodeState.inactive;
      }
      final change = FastStateChange(
        id: node.id,
        stateBefore: before,
        stateAfter: node.state,
      );
      payload.stateChanges.add(change);
      final drive = payload.drive[node.id] ?? 0;
      if (node.state != FastNodeState.inactive) {
        _recordActivation(node.id, drive);
        if (before == FastNodeState.inactive) {
          activated.add({
            'id': node.id,
            'state': node.state.id,
            'drive': round6(drive),
            'reason': 'ignite',
          });
        }
      } else if (drive > 0) {
        _attempted.add(node.id);
      }
    }

    if (mechanisms.isEnabled(FastMechanisms.shunting)) {
      _shuntingStateAfter();
    }
    for (final node in nodes) {
      node.al = clamp01(node.activation);
    }
    for (final change in payload.stateChanges) {
      change.al = round6(_node(change.id).activation);
    }
    // Peak drive covers **all** nodes (not only the lit ones): the diagnosis
    // needs to know how much input a node received, otherwise "too faint" would
    // be reported as 0%.
    for (final node in nodes) {
      final drive = payload.drive[node.id] ?? 0;
      final previous = _peakDrive[node.id];
      if (previous == null || drive > previous) {
        _peakDrive[node.id] = drive;
      }
    }

    lastRound = _snapshotOf(payload);

    // 8) stop checks, in the JS's order: targets → cooling → round budget
    if (_targets.isNotEmpty && _allTargetsActive()) {
      _stop(FastStop.allTargetsReached, true);
      return _status(activated);
    }
    final snapshot = _snapshot();
    if (snapshot == _prevSnapshot) {
      _quiet += 1;
    } else {
      _quiet = 0;
    }
    _prevSnapshot = snapshot;
    if (_quiet >= config.stableRounds) {
      _stop(FastStop.cooling, false);
      return _status(activated);
    }
    if (_rounds >= _maxRounds) {
      _stop(FastStop.maxRounds, _targets.isNotEmpty && _allTargetsActive());
      return _status(activated);
    }
    return _status(activated);
  }

  /// Runs until the engine stops (targets reached / cooling / round budget).
  FastResult runUntilStop({int? maxRounds}) {
    if (!_running) {
      throw StateError('尚未调用 startDiffusion()');
    }
    if (maxRounds != null) {
      if (maxRounds <= 0) {
        throw ArgumentError('maxRounds 必须是正数');
      }
      _maxRounds = maxRounds;
    }
    var guard = 0;
    while (!_stopped) {
      step();
      guard += 1;
      if (guard > 1000000) {
        throw StateError('扩散轮次异常（超过 1000000 轮），已中断');
      }
    }
    return result();
  }

  /// Exactly the generator's loop: `n` calls to [step], snapshotting after
  /// each. A stopped engine yields the repeated last round, which is what B01
  /// records for rounds 2..5.
  List<FastRoundSnapshot> runRounds(int n) {
    final out = <FastRoundSnapshot>[];
    for (var i = 0; i < n; i += 1) {
      step();
      out.add(lastRound!);
    }
    return out;
  }

  // ------------------------------------------------------------------- hooks

  /// `dynamics.shunting`'s `activation.update`.
  Map<String, double> _shuntingActivationUpdate(_RoundPayload payload) {
    final alpha = numberParam('${FastMechanisms.shunting}.alpha_a');
    final lambda = numberParam('${FastMechanisms.shunting}.lambda_a');
    final etaQ = numberParam('${FastMechanisms.shunting}.eta_q');
    final lambdaQ = numberParam('${FastMechanisms.shunting}.lambda_q');
    final next = <String, double>{};
    for (final node in graph.nodes.values) {
      final result = shuntingActivation(
        a: node.activation,
        q: node.subthreshold,
        drive: payload.drive[node.id] ?? 0,
        theta: node.stOf(config),
        alpha: alpha,
        lambda: lambda,
        etaQ: etaQ,
        lambdaQ: lambdaQ,
        availability: payload.availability,
      );
      next[node.id] = result.a;
      node.core['a'] = result.a;
    }
    return next;
  }

  /// `dynamics.shunting`'s `state.after`: sub-threshold accumulation runs
  /// *after* the states land, so it can tell "made it into consciousness"
  /// (reset to 0) from "did not" (keep accumulating).
  void _shuntingStateAfter() {
    final etaQ = numberParam('${FastMechanisms.shunting}.eta_q');
    final lambdaQ = numberParam('${FastMechanisms.shunting}.lambda_q');
    for (final node in graph.nodes.values) {
      node.core['q'] = shuntingSubthreshold(
        q: node.subthreshold,
        a: node.activation,
        theta: node.stOf(config),
        conscious: node.state == FastNodeState.conscious,
        etaQ: etaQ,
        lambdaQ: lambdaQ,
      );
    }
  }

  /// `attention.capacity`'s `attention.select`.
  void _capacitySelect(_RoundPayload payload) {
    final result = capacityAdmit(
      [
        for (final node in graph.nodes.values)
          (id: node.id, score: payload.scores[node.id] ?? 0, a: node.activation),
      ],
      wDar: numberParam('${FastMechanisms.capacity}.W_DAR'),
      wFa: numberParam('${FastMechanisms.capacity}.W_FA'),
    );
    payload.admitted = result.dar;
    payload.focus = result.fa.isEmpty ? null : result.fa.first;
    payload.darUsed = result.used;
    payload.outcompeted = [
      for (final node in graph.nodes.values)
        if (!result.dar.contains(node.id) &&
            (payload.scores[node.id] ?? 0) > 0)
          node.id,
    ];
  }

  /// `attention.ignition`'s `ignite.check`.
  void _ignitionCheck(_RoundPayload payload) {
    final tIgn = numberParam('${FastMechanisms.ignition}.T_ign');
    final conscious = <String>[];
    final subconscious = <String>[];
    final admitted = payload.admitted ?? const <String>[];
    payload.ignition.clear();
    // Completely absent (availability = 0): no cue is strong enough. No ported
    // module can produce this state (no rhythm.gate), but the branch is kept
    // because it is the JS's semantics, not an implementation detail.
    if (payload.availability <= 0) {
      for (final id in admitted) {
        final node = graph.nodes[id];
        if (node != null && (payload.scores[id] ?? 0) >= node.stOf(config)) {
          subconscious.add(id);
        }
      }
      payload.conscious = conscious;
      payload.subconscious = subconscious;
      return;
    }
    for (final id in admitted) {
      final node = graph.nodes[id];
      if (node == null) {
        continue;
      }
      final score = payload.scores[id] ?? 0;
      final ct = node.ctOf(config);
      final st = node.stOf(config);
      final p = ignitionProbability(score, ct, tIgn);
      final hit = _ignitionHit(p, id, score, ct);
      if (hit) {
        conscious.add(id);
      } else if (score >= st) {
        subconscious.add(id);
      }
      payload.ignition.add(FastIgnitionRecord(
        node: id,
        score: round6(score),
        ct: round6(ct),
        st: round6(st),
        tIgn: tIgn,
        p: round6(p),
        draw: null,
        hit: hit,
      ));
    }
    payload.conscious = conscious;
    payload.subconscious = subconscious;
  }

  /// `context.goal`'s `drive.compute`: the goal bias.
  ///
  /// The target nodes themselves are **excluded**: the bias is meant to lift
  /// the candidates that lead *to* a goal, and biasing the goal itself would
  /// light it up in round 1 (an error MindNet's own comments record as having
  /// been hit for real).
  void _goalDriveCompute(_RoundPayload payload) {
    final beta = numberParam('${FastMechanisms.goal}.beta_goal');
    final kappa = numberParam('${FastMechanisms.goal}.kappa_reach');
    final fanK = numberParam('${FastMechanisms.goal}.fan_k');
    final targets = payload.targets;
    final targetSet = targets.toSet();
    final distances = distanceToGoals(graph, targets);
    for (final node in graph.nodes.values) {
      var value = payload.drive[node.id] ?? 0;
      if (fanK > 0) {
        final degree = graph.inEdges(node.id).length;
        value = value / (1 + fanK * math.log(1 + degree));
      }
      final gamma = targetSet.contains(node.id)
          ? 0.0
          : goalRelevance(distances[node.id], kappa);
      if (gamma > 0 && targets.isNotEmpty) {
        value += beta * gamma;
      }
      payload.drive[node.id] = value;
    }
  }

  // ------------------------------------------------------------ pure helpers

  /// One exact-integration step of the shunting equation.
  ///
  /// `k = α·x + λ`, `a* = α·x/k`, `a₁ = a* + (a − a*)·e^(−k·availability)`.
  /// An explicit Euler step would oscillate under strong drive (MindNet's
  /// comment records `x = 100` bouncing between 1 and 0.8); the exact integral
  /// converges monotonically for any drive.
  static ({double a, double q, double aStar, double k}) shuntingActivation({
    required double a,
    required double q,
    required double drive,
    required double theta,
    required double alpha,
    required double lambda,
    required double etaQ,
    required double lambdaQ,
    double availability = 1,
  }) {
    final av = clamp01(availability);
    final x = math.max(0, drive);
    final k = alpha * x + lambda;
    final aStar = k > 0 ? (alpha * x) / k : 0.0;
    final a1 = clamp01(k > 0 ? aStar + (a - aStar) * math.exp(-k * av) : a);
    final add = a1 >= theta ? etaQ * a1 : 0.0;
    final q1 = clamp01((1 - lambdaQ) * q + add);
    return (a: a1, q: q1, aStar: aStar, k: k);
  }

  /// Sub-threshold accumulation after the states land.
  static double shuntingSubthreshold({
    required double q,
    required double a,
    required double theta,
    required bool conscious,
    required double etaQ,
    required double lambdaQ,
  }) {
    if (conscious) {
      return 0;
    }
    if (a >= theta) {
      return clamp01((1 - lambdaQ) * q + etaQ * a);
    }
    return clamp01((1 - lambdaQ) * q);
  }

  /// Two-level admission: the direct-access region (a budget in *activation
  /// units*, not item count) and the narrow focus (one item).
  ///
  /// Candidates that do not fit are **outcompeted, not forgotten** - that
  /// distinction is the whole point of the mechanism.
  static ({List<String> dar, List<String> fa, double used}) capacityAdmit(
    List<({String id, double score, double a})> candidates, {
    required double wDar,
    required double wFa,
  }) {
    final sorted = [...candidates]..sort((x, y) {
        final byScore = y.score.compareTo(x.score);
        return byScore != 0 ? byScore : x.id.compareTo(y.id);
      });
    final dar = <({String id, double score, double a})>[];
    var used = 0.0;
    for (final candidate in sorted) {
      final cost = candidate.a;
      if (used + cost > wDar) {
        continue;
      }
      used += cost;
      dar.add(candidate);
    }
    final fa = <String>[];
    var faUsed = 0.0;
    for (final candidate in dar) {
      if (faUsed + candidate.a > wFa) {
        continue;
      }
      faUsed += candidate.a;
      fa.add(candidate.id);
      break; // the narrow focus holds one item at a time
    }
    return (dar: [for (final candidate in dar) candidate.id], fa: fa, used: used);
  }

  /// `P(ignite) = σ((score − ct) / T)`; `T = 0` degrades to the hard threshold
  /// and consumes no randomness (§6.1).
  static double ignitionProbability(double score, double ct, double tIgn) {
    if (!(tIgn > 0)) {
      return score >= ct ? 1 : 0;
    }
    return sigmoid((score - ct) / tIgn);
  }

  static double sigmoid(double x) {
    if (x >= 0) {
      return 1 / (1 + math.exp(-x));
    }
    final e = math.exp(x);
    return e / (1 + e);
  }

  /// Reverse BFS: each node's directed distance to the nearest goal.
  static Map<String, int> distanceToGoals(FastGraph graph, List<String> goals) {
    final dist = <String, int>{};
    final queue = <String>[];
    for (final goal in goals) {
      if (!graph.hasNode(goal)) {
        continue;
      }
      dist[goal] = 0;
      queue.add(goal);
    }
    for (var head = 0; head < queue.length; head += 1) {
      final current = queue[head];
      final d = dist[current]!;
      for (final edge in graph.inEdges(current)) {
        if (dist.containsKey(edge.from)) {
          continue;
        }
        dist[edge.from] = d + 1;
        queue.add(edge.from);
      }
    }
    return dist;
  }

  /// `γ_v = κ^d`; unreachable nodes get 0.
  static double goalRelevance(int? dist, double kappa) {
    if (dist == null) {
      return 0;
    }
    return math.pow(kappa, dist).toDouble();
  }

  /// The float rounding the whole contract is written in terms of.
  ///
  /// `roundToDouble()` rounds half **away from zero**; the JS `Math.round`
  /// rounds half towards `+∞`, so the two differ only for a negative value that
  /// lands exactly on a half. That shape does not occur in the vectors, and it is
  /// the same rule `DsrMemory.round6` (tierA) already uses, so the port keeps
  /// them identical rather than diverging by five-hundred-nanosecond cases.
  static double round6(double x) => (x * 1e6).roundToDouble() / 1e6;

  static double clamp01(double x) {
    if (!x.isFinite) {
      return 0;
    }
    return x < 0 ? 0 : (x > 1 ? 1 : x);
  }

  // ---------------------------------------------------------------- internal

  /// The `T_ign > 0` branch needs a seeded draw; this round deliberately has
  /// no RNG, so it fails loudly instead of quietly inventing a value.
  bool _ignitionHit(double p, String id, double score, double ct) {
    if (p >= 1) {
      return true;
    }
    if (p <= 0) {
      return false;
    }
    throw UnsupportedError(
      '点火概率 $p（节点 $id，score=$score，ct=$ct）落在 (0,1) 内：'
      '随机点火在本轮被有意掐掉（D3 / 契约 §6.1），'
      'mulberry32 RNG 尚未移植，因此不做确定性替代。'
      '请把 attention.ignition.T_ign 设为 0 走硬阈值分支。',
    );
  }

  Map<String, double> _rawDrive(List<FastDriveEdge> sink) {
    final drive = <String, double>{
      for (final node in graph.nodes.values) node.id: 0,
    };
    for (final source in graph.nodes.values) {
      final au = source.activation;
      if (!(au > 0)) {
        continue;
      }
      final strength = source.ms;
      if (!(strength > 0)) {
        continue;
      }
      for (final edge in graph.outEdges(source.id)) {
        final contribution = au * strength * edge.ls;
        drive[edge.to] = (drive[edge.to] ?? 0) + contribution;
        sink.add(FastDriveEdge(
          from: source.id,
          to: edge.to,
          edgeId: edge.id,
          kind: 'edge',
          ls: edge.ls,
          al: au,
          ms: strength,
          contribution: round6(contribution),
        ));
      }
    }
    for (final node in graph.nodes.values) {
      final q = node.subthreshold;
      if (q > 0) {
        drive[node.id] = (drive[node.id] ?? 0) + q;
        sink.add(FastDriveEdge(
          from: null,
          to: node.id,
          kind: 'subthreshold',
          contribution: round6(q),
        ));
      }
    }
    return drive;
  }

  Map<String, double> _scores() => {
        for (final node in graph.nodes.values) node.id: node.activation,
      };

  /// Sorted by score descending, id ascending (the JS comparator, ties
  /// included: it is what makes `admitted` deterministic).
  List<String> _candidates(Map<String, double> scores) {
    final entries = scores.entries.toList()
      ..sort((a, b) {
        final byScore = b.value.compareTo(a.value);
        return byScore != 0 ? byScore : a.key.compareTo(b.key);
      });
    return [for (final entry in entries) entry.key];
  }

  void _applyActivation(Map<String, double> next) {
    for (final node in graph.nodes.values) {
      final value = next[node.id];
      if (value == null) {
        continue;
      }
      node.core['a'] = clamp01(value);
    }
  }

  ({List<String> conscious, List<String> subconscious}) _defaultIgnition(
    Set<String> admitted,
    Map<String, double> scores,
  ) {
    final conscious = <String>[];
    final subconscious = <String>[];
    for (final id in admitted) {
      final node = graph.nodes[id];
      if (node == null) {
        continue;
      }
      final score = scores[id] ?? 0;
      if (score >= node.ctOf(config)) {
        conscious.add(id);
      } else if (score >= node.stOf(config)) {
        subconscious.add(id);
      }
    }
    return (conscious: conscious, subconscious: subconscious);
  }

  void _recordActivation(String id, double drive) {
    _everActivated.add(id);
    _firstActivation.putIfAbsent(id, () => _rounds);
    final previous = _peakDrive[id];
    if (previous == null || drive > previous) {
      _peakDrive[id] = drive;
    }
    if (_targetSet.contains(id) && !_targetSteps.containsKey(id)) {
      _targetSteps[id] = _rounds;
    }
  }

  bool _allTargetsActive() {
    for (final id in _targets) {
      if (!_everActivated.contains(id)) {
        return false;
      }
    }
    return true;
  }

  String _snapshot() {
    final ids = graph.nodes.keys.toList()..sort();
    return ids.map((id) => '$id:${graph.nodes[id]!.state.id}').join('|');
  }

  void _requireNodes(List<String> ids, String label) {
    final missing = [
      for (final id in ids)
        if (!graph.hasNode(id)) id,
    ];
    if (missing.isNotEmpty) {
      throw ArgumentError('$label不存在于图中：${missing.join(', ')}');
    }
  }

  void _resetRuntime() {
    _rounds = 0;
    _starts.clear();
    _startOrder = <String>[];
    _targets = <String>[];
    _targetSet.clear();
    _targetSteps = <String, int>{};
    _everActivated = <String>{};
    _firstActivation = <String, int>{};
    _peakDrive = <String, double>{};
    _attempted = <String>{};
    _pendingStarts = <String>[];
    _prevSnapshot = null;
    _quiet = 0;
    _stopped = false;
    _stopReason = null;
    _targetsAllReached = false;
    _maxRounds = config.maxRounds;
  }

  void _stop(String reason, bool targetsAllReached) {
    _stopped = true;
    _stopReason = reason;
    _targetsAllReached = targetsAllReached;
  }

  FastStatus _status(List<Map<String, Object?>> activated) => FastStatus(
        round: _rounds,
        activated: activated,
        stopped: _stopped,
        stopReason: _stopReason,
      );

  FastRoundSnapshot _snapshotOf(_RoundPayload payload) => FastRoundSnapshot(
        round: payload.round,
        cycleTicks: payload.cycleTicks,
        availability: payload.availability,
        drive: Map<String, double>.of(payload.drive),
        driveEdges: List<FastDriveEdge>.of(payload.driveEdges),
        scores: Map<String, double>.of(payload.scores),
        admitted:
            payload.admitted == null ? null : List<String>.of(payload.admitted!),
        focus: payload.focus,
        darUsed: payload.darUsed,
        outcompeted: payload.outcompeted == null
            ? null
            : List<String>.of(payload.outcompeted!),
        conscious: List<String>.of(payload.conscious ?? const <String>[]),
        subconscious:
            List<String>.of(payload.subconscious ?? const <String>[]),
        states: List<FastStateChange>.of(payload.stateChanges),
        a: {
          for (final node in graph.nodes.values) node.id: node.activation,
        },
        q: {
          for (final node in graph.nodes.values) node.id: node.subthreshold,
        },
        ignition: List<FastIgnitionRecord>.of(payload.ignition),
      );

  /// `kernel.review(nodeId, event)`: runs the `review.on` slot on this engine.
  ///
  /// Returns nothing today because the tierB profile installs **no memory
  /// mechanism** - the JS kernel with `memory.dsr` absent also runs an empty hook
  /// list - so this is the seam where a wired memory layer would be called, not a
  /// stub that pretends to have reviewed something.
  List<Map<String, Object?>> review(String nodeId, Map<String, Object?> event) {
    if (!graph.hasNode(nodeId)) {
      throw ArgumentError('review：节点 "$nodeId" 不存在');
    }
    return const <Map<String, Object?>>[];
  }

  // ----------------------------------------------------------------- diagnosis

  /// The flat fact table the control layer reads (the JS
  /// `diagnostic_facts()`): no module needs to reach into engine internals.
  ///
  /// **Every numeric field here is already rounded to 6 decimals**, exactly as
  /// the JS builds it (`a: round6(...)`, `peak_drive: round6(...)`, …). That is
  /// load-bearing, not cosmetic: the classifier divides `peak_drive` by `ct` to
  /// get `closeness`, so reading the raw values instead shifts the published
  /// closeness by ~5e-7 and breaks the conformance diff.
  Map<String, FastDiagnosticFact> diagnosticFacts() {
    final last = lastRound;
    final facts = <String, FastDiagnosticFact>{};
    for (final node in graph.nodes.values) {
      final memory = (node.m['memory_dsr'] as Map?)?.cast<String, Object?>();
      facts[node.id] = FastDiagnosticFact(
        id: node.id,
        name: node.name,
        state: node.state,
        a: round6(node.activation),
        q: round6(node.subthreshold),
        drive: round6(last?.drive[node.id] ?? 0),
        score: round6(last?.scores[node.id] ?? 0),
        peakDrive: round6(_peakDrive[node.id] ?? 0),
        ct: node.ctOf(config),
        st: node.stOf(config),
        inDegree: graph.inEdges(node.id).length,
        outDegree: graph.outEdges(node.id).length,
        everActivated: _everActivated.contains(node.id),
        firstActivationRound: _firstActivation[node.id],
        activatedAtRound: _targetSteps[node.id],
        outcompeted: last?.outcompeted?.contains(node.id) ?? false,
        isTarget: _targetSet.contains(node.id),
        isStart: _starts.contains(node.id),
        r: round6(node.ms),
        // A missing/bogus memory field reads as 0 in the JS (`round6(undefined)`),
        // not as a crash - mirrored rather than "improved".
        r0: memory == null ? null : round6((memory['R0'] as num?)?.toDouble() ?? 0),
        s: memory == null ? null : round6((memory['S'] as num?)?.toDouble() ?? 0),
        d: memory == null ? null : round6((memory['D'] as num?)?.toDouble() ?? 0),
        f: memory == null
            ? 0
            : round6((memory['F'] as num?)?.toDouble() ?? 0),
      );
    }
    return facts;
  }

  /// Scalar target reachability: the metric counterfactuals compare.
  double reachability([List<String>? targetList]) {
    final list = targetList ?? _targets;
    var score = 0.0;
    for (final id in list) {
      if (!graph.hasNode(id)) {
        continue;
      }
      score += _node(id).activation;
      if (_everActivated.contains(id)) {
        score += 0.5;
      }
    }
    return round6(score);
  }

  /// Clones the engine for a counterfactual run: graph, memory bags, fast state
  /// and runtime counters are copied, and **`stopped` is cleared** so the clone
  /// can be stepped forward (which is why the JS `clone()` cannot simply reuse
  /// the original's run state). `lastRound` is intentionally *not* copied - the
  /// JS clone starts with none.
  FastEngine clone() {
    final graphCopy = graph.copy();
    final copy = FastEngine(
      graph: graphCopy,
      config: config,
      mechanisms: mechanisms,
      overrides: Map<String, Object?>.of(overrides),
      seed: seed,
      hours: hours,
    );
    copy.tick = tick;
    copy.startDiffusion(
      List<String>.of(_startOrder),
      List<String>.of(_targets),
    );
    copy._rounds = _rounds;
    copy._everActivated = Set<String>.of(_everActivated);
    copy._firstActivation = Map<String, int>.of(_firstActivation);
    copy._peakDrive = Map<String, double>.of(_peakDrive);
    copy._attempted = Set<String>.of(_attempted);
    copy._targetSteps = Map<String, int>.of(_targetSteps);
    copy._prevSnapshot = _prevSnapshot;
    copy._quiet = _quiet;
    copy._stopped = false;
    copy._stopReason = null;
    copy._targetsAllReached = _targetsAllReached;
    for (final node in graph.nodes.values) {
      final nodeCopy = graphCopy.nodes[node.id]!;
      nodeCopy.state = node.state;
      nodeCopy.al = node.al;
      nodeCopy.core['a'] = node.activation;
      nodeCopy.core['q'] = node.subthreshold;
      nodeCopy.ms = node.ms;
      nodeCopy.lastReviewTime = node.lastReviewTime;
    }
    return copy;
  }

  /// `get_kc()`: the development-zone gap, plus the dead-end penalty.
  FastKc getKc() {
    var gap = 0.0;
    for (final node in graph.nodes.values) {
      if (_starts.contains(node.id)) {
        continue;
      }
      if (!_everActivated.contains(node.id)) {
        continue;
      }
      final impact = _peakDrive[node.id] ?? 0;
      gap += node.weight *
          math.max(0, config.gapConstant * node.ctOf(config) - impact);
    }
    var penalty = 0.0;
    for (final id in _attempted) {
      if (_starts.contains(id) || _everActivated.contains(id)) {
        continue;
      }
      penalty += graph.nodes[id]!.weight * math.sqrt(1);
    }
    return FastKc(gap: round6(gap), penalty: round6(penalty));
  }

  /// `final_states()`.
  Map<String, String> finalStates() => {
        for (final node in graph.nodes.values) node.id: node.state.id,
      };

  /// `target_steps()`.
  Map<String, int> targetStepsOf() => {
        for (final id in _targets)
          if (_targetSteps.containsKey(id)) id: _targetSteps[id]!,
      };

  /// `result()`.
  FastResult result() {
    final kc = getKc();
    return FastResult(
      gap: kc.gap,
      penalty: kc.penalty,
      targetSteps: targetStepsOf(),
      targetsAllReached: _targetsAllReached,
      finalStates: finalStates(),
    );
  }

  /// `state()`: the result plus runtime counters and per-node fast state.
  ///
  /// `control` / `mechanism_state` / `warnings` are kernel-level and have no
  /// counterpart here: this port has no mechanism registry (§6.1 says the
  /// registry is Node-only and "Dart 不需要注册表").
  Map<String, Object?> state() {
    final kc = getKc();
    return {
      'kc': {'gap': kc.gap, 'penalty': kc.penalty},
      'target_steps': targetStepsOf(),
      'targets_all_reached': _targetsAllReached,
      'final_states': finalStates(),
      'rounds': _rounds,
      'stop_reason': _stopReason,
      'availability_last': lastRound?.availability ?? 1,
      'nodes': {
        for (final node in graph.nodes.values)
          node.id: {
            ...node.toJson(config),
            'a': round6(node.activation),
            'q': round6(node.subthreshold),
            'ever_activated': _everActivated.contains(node.id),
            'peak_drive': round6(_peakDrive[node.id] ?? 0),
          },
      },
      'initial_nodes': List<String>.of(_startOrder),
      'target_nodes': List<String>.of(_targets),
      'mechanisms': List<String>.of(mechanisms.ids),
    };
  }
}

/// Deep copy for the mechanism-private `m` bag, mirroring the JS
/// `JSON.parse(JSON.stringify(...))` clone so a counterfactual cannot write back
/// into the original's memory state.
Map<String, Object?> deepCopyMap(Map<String, Object?> source) => {
      for (final entry in source.entries) entry.key: _deepCopyValue(entry.value),
    };

Object? _deepCopyValue(Object? value) => switch (value) {
      Map() => {
          for (final entry in value.cast<String, Object?>().entries)
            entry.key: _deepCopyValue(entry.value),
        },
      List() => [for (final item in value) _deepCopyValue(item)],
      _ => value,
    };

String _requiredString(Map<Object?, Object?> source, String key, String where) {
  final value = source[key];
  if (value is! String || value.trim().isEmpty) {
    throw ArgumentError('$where 缺少必填字段 "$key"（需为非空字符串）');
  }
  return value;
}

double? _optionalNumber(Map<Object?, Object?> source, String key) {
  final value = source[key];
  if (value == null) {
    return null;
  }
  if (value is! num) {
    throw ArgumentError('字段 "$key" 必须是数字，实际为 $value');
  }
  return value.toDouble();
}

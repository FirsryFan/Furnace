/// 用途 1: judging a batch of candidate problems against the user's own state.
///
/// This is the "约 20 行胶水" of MINDNET_CONTRACT §6.3, spelled out as a pure
/// function so it can be tested without a database, a clock or a network:
///
/// ```text
/// tags -> CognitiveGraph.fromTags -> FastGraph.fromSpec
///      -> FastEngine.startDiffusion(starts, targets) -> run 3..5 rounds
///      -> FastDiagnosis.bottlenecks -> verdicts for this problem's nodes
/// ```
///
/// Three boundaries are deliberate and worth stating before the code:
///
/// * **tierA alone is enough.** The R/gain numbers come from
///   [CognitiveModel] per knowledge point; the fast layer only *sharpens* the
///   verdict (a `weak` complaint means "almost had it" - the development zone;
///   an `empty`/`dead_end` complaint means there is no way in or no way out -
///   a dead end). With no tags, no graph or `runFastLayer: false`, the same
///   function still returns verdicts, and the report says which mode it ran in.
/// * **`difficulty_hint` is never a model difficulty.** §6.3 is explicit: in
///   MindNet, difficulty is a property of each *cue*, updated from performance,
///   not a static property of a problem. The hint is used only as a *prior for
///   our own ranking*, and only when there is no history at all to judge from
///   (it must not override the model: that is tested).
/// * **every id is filtered to what the graph actually contains.** The port's
///   `startDiffusion` throws `ArgumentError` for an id that is not a node
///   (empty lists are legal), so a knowledge point outside the projection must
///   be dropped here rather than crash a review-planning call.
/// * **there is deliberately no danger-first ordering here.** It was written,
///   measured and removed (轮次二十二). Danger needs a node the diffusion leaves
///   **conscious**, but this evaluator's targets *are* the candidate's own
///   knowledge points, and `context.goal` excludes target nodes from the drive
///   on purpose (`fast_engine.dart` `_goalDriveCompute`: biasing the goal itself
///   would light it in round 1), so a candidate could never report its own
///   danger. Widening the filter is worse, not better: a probe over the same
///   graph showed the conscious set is decided by tag insertion order and
///   capacity, and does **not** change when a different card goes stale - it
///   would have ranked on tag order, not on what the learner has forgotten.
///   Danger stays a *context* reading (the readings page, where the metacognition
///   rows are folded into `FastDiagnosis.bottlenecks`), which is where it is
///   meaningful.
/// * **the counterfactual price is a tie-break and an explanation, never a
///   weight.** [FastPlanner.plan] prices each bottleneck's preferred
///   instruction as `V(π) = ΔR / cost`, measured on a clone of *this problem's
///   own* diffusion run (`fast_diagnosis.dart`). The evaluator attaches that
///   price to the evaluation and uses it only to order candidates whose
///   `rankKey` is equal: the costs and the intervention strengths behind `V(π)`
///   are [未标定], and folding an uncalibrated number into the primary key would
///   make a hint look like a measurement. A `retention` instruction without a
///   `RetentionProbe` is reported as *not simulated*, never as zero gain - so a
///   candidate can legitimately carry no price at all.
library;

import '../../../data/database/database.dart';
import 'cognitive_graph.dart';
import 'cognitive_model.dart';
import 'fast_diagnosis.dart';
import 'fast_engine.dart';
import 'knowledge_point_tag_bridge.dart';

/// What the evaluator concluded about one candidate problem.
enum ProblemVerdict {
  /// The user already retrieves every knowledge point involved: repeating this
  /// problem would cost time and buy little.
  tooEasy,

  /// The development zone (§6.3's `weak`, or a healthy set of cues): work the
  /// user can do now with effort.
  zpd,

  /// Every knowledge point is barely retrievable and hard: attempting this now
  /// is a grind rather than practice.
  tooHard,

  /// A dead end or out of scope: the model finds no way in (`empty` /
  /// `dead_end` for every knowledge point), or the problem has no knowledge
  /// points at all to judge. §6.3's "全是 empty ⇒ 超纲或死角".
  outOfScope,

  /// Its knowledge points are already covered by another candidate in the same
  /// batch, so it adds no new ground.
  redundant,

  /// In the development zone *and* worth the time: it covers several knowledge
  /// points, or the model flagged one as "almost had it".
  highValue,
}

/// One candidate problem. Deliberately domain-free: the caller decides whether
/// it comes from a package, a question bank or a photo.
class ProblemCandidate {
  const ProblemCandidate({
    required this.id,
    required this.stem,
    this.knowledgePointIds = const [],
    this.difficultyHint,
  });

  final String id;

  /// A short excerpt of the question, carried for the human-readable reason.
  final String stem;

  /// Knowledge point ids this problem exercises (its tags). Order is preserved
  /// and duplicates are ignored.
  final List<String> knowledgePointIds;

  /// The problem's *own* difficulty, when the source has one.
  ///
  /// **Never handed to the model as `D`** (§6.3): MindNet's difficulty belongs
  /// to each cue and is updated from performance. It is used here only as a
  /// prior for ranking when there is no history to judge from.
  final double? difficultyHint;
}

/// The evaluator's own thresholds. **All [未标定 / NOT CALIBRATED]**: they are
/// product defaults chosen to be explainable, not measured constants, and they
/// are parameters so a caller (or a future calibration) can override them
/// without editing this file (§6.6).
class ProblemEvaluatorThresholds {
  const ProblemEvaluatorThresholds({
    this.tooEasyRetrievability = 0.9,
    this.tooHardRetrievability = 0.25,
    this.tooHardDifficulty = 7.5,
    this.hintEasy = 0.35,
    this.hintHard = 0.66,
    this.diffusionRounds = 4,
  });

  /// Mean retrievability at or above which nothing here is worth reviewing.
  final double tooEasyRetrievability;

  /// Mean retrievability at or below which the material is barely there.
  final double tooHardRetrievability;

  /// Mean FSRS difficulty that makes "barely there" a grind instead of practice.
  final double tooHardDifficulty;

  /// `difficulty_hint` at or below which a problem reads as easy (only used
  /// when there is no history at all).
  final double hintEasy;

  /// `difficulty_hint` at or above which a problem reads as hard (same caveat).
  final double hintHard;

  /// Diffusion rounds per candidate. §6.3 says 3-5; the exact number is
  /// [未标定].
  final int diffusionRounds;
}

/// The verdict for one candidate, plus the numbers that produced it.
class ProblemEvaluation {
  const ProblemEvaluation({
    required this.problemId,
    required this.stem,
    required this.verdict,
    required this.rankKey,
    required this.reason,
    required this.knowledgePointIds,
    required this.judgedKnowledgePointIds,
    required this.diagnosisByKnowledgePoint,
    this.counterfactualValue,
    this.counterfactualMetric,
    this.counterfactualInstruction,
    this.counterfactualWhy,
  });

  final String problemId;
  final String stem;
  final ProblemVerdict verdict;

  /// Higher is better. Our own scale (the model's gain in a `[1, inf)` range
  /// plus documented bonuses), **not** a model output.
  final double rankKey;

  /// One human-readable sentence explaining the verdict.
  final String reason;

  /// The knowledge points as the caller declared them.
  final List<String> knowledgePointIds;

  /// Those of them that actually have a card row to judge from - i.e. the ones
  /// the tierA numbers were computed over. Empty means "no history".
  final List<String> judgedKnowledgePointIds;

  /// The fast layer's verdicts for this problem's knowledge points, from *this
  /// problem's own* diffusion run (`{}` when the fast layer did not run).
  final Map<String, BottleneckType> diagnosisByKnowledgePoint;

  /// The counterfactual price of the planner's preferred instruction for this
  /// problem's nodes: `V(π) = ΔR / cost` (`FastPlanner`).
  ///
  /// Null when the fast layer did not run, when no bottleneck had a simulatable
  /// instruction, or when the only instruction for it needs the memory layer
  /// (`retention` without a `RetentionProbe` is *not simulated*). An uncalibrated
  /// number, used only for the tie-break in [ProblemEvaluator.compareByRank].
  final double? counterfactualValue;

  /// `reachability` / `retention`: the metric [counterfactualValue] was measured
  /// in (`FastPlanEntry.metric`). Null whenever the value is.
  final String? counterfactualMetric;

  /// The instruction id the price belongs to (`add_in_edges`, ...).
  final String? counterfactualInstruction;

  /// The planner's own sentence for that entry - what was simulated and what
  /// changed.
  final String? counterfactualWhy;
}

/// The whole batch's result.
class ProblemEvaluationReport {
  const ProblemEvaluationReport({
    required this.evaluations,
    required this.fastLayerRan,
    required this.nodesWithoutMs,
  });

  /// Ranked: `rankKey` descending, then `counterfactualValue` descending (the
  /// ones without a price last), then problem id ascending - see
  /// [ProblemEvaluator.compareByRank]. There is no danger-first tier - see the
  /// boundary note at the top of this file.
  final List<ProblemEvaluation> evaluations;

  /// Whether the fast layer actually ran (tierB). When false every verdict came
  /// from tierA alone, and no `diagnosisByKnowledgePoint` is meaningful.
  final bool fastLayerRan;

  /// Nodes of the projected graph that carried no `ms` because no card row
  /// supplied an encoding strength. "Not provided" - **not** 0.8
  /// (`CognitiveGraph.nodesWithoutMs`).
  final List<String> nodesWithoutMs;
}

/// One candidate's fast-layer run: the complaints and the counterfactual plan,
/// both taken from the same engine.
class _FastRun {
  const _FastRun({required this.diagnosis, required this.plan});

  /// Bottleneck type by graph node (`FastDiagnosis.bottlenecks`, first wins).
  final Map<String, BottleneckType> diagnosis;

  /// The planner's lines for the same run (`FastPlanner.plan`).
  final List<FastPlanEntry> plan;
}

/// The evaluator. Pure: it reads what it is given and writes nothing.
abstract final class ProblemEvaluator {
  /// Evaluates [candidates] against [rowsByKnowledgePoint] (the user's card
  /// rows, keyed by knowledge point) and, when available, the fast layer.
  ///
  /// * `tags` - the projection's input (`CognitiveTag.fromTag(tagRow)`). An
  ///   empty list means "no graph", which is the tierA-only mode.
  /// * `startKnowledgePointIds` - what the user is holding in mind right now
  ///   (§6.3's `starts`; often the most recently reviewed points). Empty is
  ///   legal and means a pure memory computation.
  /// * `tagIdsByKnowledgePoint` - the `kp-…` → `tag-…` mapping
  ///   ([KnowledgePointTagBridge]). Supply it whenever the caller's ids are real
  ///   knowledge points; leave it empty only when they are already graph node
  ///   ids. Either way the mapping never leaks into the report.
  /// * `runFastLayer` - set false to judge from tierA alone even when a graph
  ///   is available.
  static ProblemEvaluationReport evaluate({
    required List<ProblemCandidate> candidates,
    required List<CognitiveTag> tags,
    required Map<String, CardState> rowsByKnowledgePoint,
    required CognitiveModel model,
    required double nowHours,
    List<String> startKnowledgePointIds = const [],
    Map<String, List<String>> tagIdsByKnowledgePoint =
        const <String, List<String>>{},
    Map<String, double> importanceByTagId = const {},
    Map<String, Object?> moduleDefaults = const {},
    bool runFastLayer = true,
    ProblemEvaluatorThresholds thresholds = const ProblemEvaluatorThresholds(),
  }) {
    final nodeIds = {for (final tag in tags) tag.id};

    // Q8 key space (`knowledge_point_tag_bridge.dart`): candidates, rows and
    // starts are keyed by **knowledge point** (`kp-…`), the graph's nodes are
    // **tags** (`tag-…`). Translate at this boundary only - the report below goes
    // back to knowledge points, so the model never sees a tag id it cannot
    // resolve. An empty map keeps the pre-Q8 behaviour (ids are node ids).
    final rowsByTagId = tagIdsByKnowledgePoint.isEmpty
        ? rowsByKnowledgePoint
        : KnowledgePointTagBridge.expandKeys<CardState>(
            byKnowledgePoint: rowsByKnowledgePoint,
            tagIdsByKnowledgePoint: tagIdsByKnowledgePoint,
          );

    // ms is R0, the encoding ceiling - not the current retrievability (§6.3 as
    // clarified by MindNet's own `ensureState`, which reads `ms` as `R0`).
    // A tag without a card row, or with an illegal R0, is *omitted* so the
    // projection can name it in `nodesWithoutMs`: MindNet fills a missing `ms`
    // with its own default (0.8, `src/model.js:50`), and this side deliberately
    // does **not** use that fallback - "not provided" stays observable instead,
    // the same convention `cognitive_graph.dart` states for callers.
    final msByTagId = <String, double>{};
    for (final tag in tags) {
      final row = rowsByTagId[tag.id];
      if (row == null) {
        continue;
      }
      final r0 = model.modelReadingOf(row, nowHours: nowHours).r0;
      if (r0.isFinite && r0 > 0 && r0 <= 1) {
        msByTagId[tag.id] = r0;
      }
    }

    final graph = CognitiveGraph.fromTags(
      tags: tags,
      ms: msByTagId,
      importance: importanceByTagId,
    );
    final spec = graph.toJson();
    final starts = [
      for (final id in tagIdsByKnowledgePoint.isEmpty
          ? startKnowledgePointIds
          : KnowledgePointTagBridge.tagIdsOfAll(
              startKnowledgePointIds,
              tagIdsByKnowledgePoint,
            ))
        if (nodeIds.contains(id)) id,
    ];

    var fastLayerRan = false;
    final evaluations = <ProblemEvaluation>[];
    for (final candidate in candidates) {
      final knowledgePointIds = <String>[];
      for (final id in candidate.knowledgePointIds) {
        if (!knowledgePointIds.contains(id)) {
          knowledgePointIds.add(id);
        }
      }
      final judged = [
        for (final id in knowledgePointIds)
          if (rowsByKnowledgePoint[id] != null) id,
      ];

      // This problem's own diffusion run. Targets are graph nodes: the engine
      // throws for anything else, and an empty target list is legal but tells us
      // nothing.
      final graphTargets = tagIdsByKnowledgePoint.isEmpty
          ? [
              for (final id in knowledgePointIds)
                if (nodeIds.contains(id)) id,
            ]
          : KnowledgePointTagBridge.tagIdsOfAll(
              knowledgePointIds,
              tagIdsByKnowledgePoint,
            ).where(nodeIds.contains).toList();
      var diagnosis = const <String, BottleneckType>{};
      FastPlanEntry? price;
      if (runFastLayer && tags.isNotEmpty && graphTargets.isNotEmpty) {
        final run = _runFastLayer(
          spec: spec,
          starts: starts,
          targets: graphTargets,
          nowHours: nowHours,
          moduleDefaults: moduleDefaults,
          rounds: thresholds.diffusionRounds,
        );
        final tagDiagnosis = run.diagnosis;
        price = _bestPlanEntry(run.plan, graphTargets);
        diagnosis = tagIdsByKnowledgePoint.isEmpty
            ? tagDiagnosis
            : KnowledgePointTagBridge.verdictsByKnowledgePoint(
                byTagId: tagDiagnosis,
                tagIdsByKnowledgePoint: tagIdsByKnowledgePoint,
              );
        fastLayerRan = true;
      }

      evaluations.add(_judge(
        candidate: candidate,
        knowledgePointIds: knowledgePointIds,
        judged: judged,
        diagnosis: diagnosis,
        plan: price,
        rows: rowsByKnowledgePoint,
        model: model,
        nowHours: nowHours,
        thresholds: thresholds,
      ));
    }

    _markRedundant(evaluations);

    evaluations.sort(compareByRank);

    return ProblemEvaluationReport(
      evaluations: List.unmodifiable(evaluations),
      fastLayerRan: fastLayerRan,
      nodesWithoutMs: graph.nodesWithoutMs,
    );
  }

  /// The report's total order: `rankKey` descending, then the counterfactual
  /// price descending (candidates without one come last), then problem id
  /// ascending - so the order is total and does not depend on the input order.
  ///
  /// The price is only ever a *tie-break*: `rankKey` is the primary key, and
  /// `V(π)`'s costs are [未标定] (see the header note). Public so the tie-break
  /// itself is testable without building an engine.
  static int compareByRank(ProblemEvaluation a, ProblemEvaluation b) {
    final byRank = b.rankKey.compareTo(a.rankKey);
    if (byRank != 0) {
      return byRank;
    }
    final aValue = a.counterfactualValue;
    final bValue = b.counterfactualValue;
    if (aValue != null && bValue != null) {
      final byValue = bValue.compareTo(aValue);
      if (byValue != 0) {
        return byValue;
      }
    } else if (aValue != null) {
      return -1;
    } else if (bValue != null) {
      return 1;
    }
    return a.problemId.compareTo(b.problemId);
  }

  /// Runs the tierB fast layer for one problem and returns what it complained
  /// about, keyed by knowledge point, together with the counterfactual prices
  /// from **the same engine** - so the diagnosis and the price can never
  /// describe two different runs.
  static _FastRun _runFastLayer({
    required Map<String, Object?> spec,
    required List<String> starts,
    required List<String> targets,
    required double nowHours,
    required Map<String, Object?> moduleDefaults,
    required int rounds,
  }) {
    // D3's random-source removal: only the four ported mechanisms, and
    // `T_ign = 0` makes ignition a hard threshold that draws nothing.
    const overrides = <String, Object?>{'attention.ignition.T_ign': 0};
    final engine = FastEngine(
      graph: FastGraph.fromSpec(spec, currentRealTime: nowHours),
      mechanisms: FastMechanisms.fromModuleDefaults(
        moduleDefaults,
        ids: const [
          FastMechanisms.shunting,
          FastMechanisms.capacity,
          FastMechanisms.ignition,
          FastMechanisms.goal,
        ],
        overrides: overrides,
      ),
      overrides: overrides,
      hours: nowHours,
    )..startDiffusion(starts, targets);
    engine.runRounds(rounds);

    final bottlenecks = FastDiagnosis.bottlenecks(engine: engine);
    final out = <String, BottleneckType>{};
    for (final bottleneck in bottlenecks) {
      out.putIfAbsent(bottleneck.node, () => bottleneck.type);
    }
    return _FastRun(
      diagnosis: out,
      plan: FastPlanner.plan(
        engine: engine,
        bottlenecks: bottlenecks,
        params: FastPlannerParams(simRounds: rounds),
      ),
    );
  }

  /// Picks this candidate's price: the highest `V(π)` among the planner's
  /// **simulated** entries for the problem's own graph nodes.
  ///
  /// Only simulated entries count - a `retention` instruction without a
  /// `RetentionProbe` is "the memory layer is not wired", not a zero. Ties go to
  /// the first target, so the choice does not depend on map iteration order.
  static FastPlanEntry? _bestPlanEntry(
    List<FastPlanEntry> plan,
    List<String> targets,
  ) {
    if (plan.isEmpty || targets.isEmpty) {
      return null;
    }
    final targetSet = targets.toSet();
    final targetIndex = <String, int>{
      for (var i = 0; i < targets.length; i += 1) targets[i]: i,
    };
    FastPlanEntry? best;
    for (final entry in plan) {
      if (!entry.simulated || entry.metric == null) {
        continue;
      }
      if (!targetSet.contains(entry.node)) {
        continue;
      }
      if (best == null) {
        best = entry;
        continue;
      }
      final byValue = entry.value.compareTo(best.value);
      if (byValue > 0) {
        best = entry;
      } else if (byValue == 0 &&
          (targetIndex[entry.node] ?? 0) < (targetIndex[best.node] ?? 0)) {
        best = entry;
      }
    }
    return best;
  }

  /// The judgement for one candidate. Kept as one function so the precedence
  /// between the verdicts is readable in one place.
  static ProblemEvaluation _judge({
    required ProblemCandidate candidate,
    required List<String> knowledgePointIds,
    required List<String> judged,
    required Map<String, BottleneckType> diagnosis,
    required FastPlanEntry? plan,
    required Map<String, CardState> rows,
    required CognitiveModel model,
    required double nowHours,
    required ProblemEvaluatorThresholds thresholds,
  }) {
    final complaints = [
      for (final id in knowledgePointIds)
        if (diagnosis[id] != null) diagnosis[id]!,
    ];
    final almostHadIt = complaints.contains(BottleneckType.weak);
    final noWayIn = complaints.isNotEmpty &&
        complaints.every((type) =>
            type == BottleneckType.empty || type == BottleneckType.deadEnd);

    if (knowledgePointIds.isEmpty) {
      return _evaluation(
        candidate: candidate,
        knowledgePointIds: knowledgePointIds,
        judged: judged,
        diagnosis: diagnosis,
        plan: plan,
        verdict: ProblemVerdict.outOfScope,
        rankKey: 0,
        reason: '没有闪存卡标签，模型无从判断',
      );
    }
    if (noWayIn) {
      return _evaluation(
        candidate: candidate,
        knowledgePointIds: knowledgePointIds,
        judged: judged,
        diagnosis: diagnosis,
        plan: plan,
        verdict: ProblemVerdict.outOfScope,
        rankKey: 0,
        reason: '诊断全是 empty/dead_end：线索进不去或走不下去（死角或超纲）',
      );
    }

    // tierA numbers over the knowledge points we actually have rows for.
    var meanRetrievability = 0.0;
    var meanGain = 1.0;
    var meanDifficulty = 0.0;
    if (judged.isNotEmpty) {
      for (final id in judged) {
        final row = rows[id]!;
        meanRetrievability += model.retrievabilityOf(row, nowHours: nowHours);
        meanGain += model.expectedGain(row, nowHours: nowHours);
        meanDifficulty += row.difficulty ?? 5.0;
      }
      final n = judged.length;
      meanRetrievability /= n;
      meanGain /= n;
      meanDifficulty /= n;
    }

    if (judged.isEmpty) {
      // No history anywhere: the hint is the only prior we have (§6.3 allows
      // it in *our* ranking; it is still never the model's D).
      final hint = candidate.difficultyHint;
      if (hint != null && hint >= thresholds.hintHard) {
        return _evaluation(
          candidate: candidate,
          knowledgePointIds: knowledgePointIds,
          judged: judged,
          diagnosis: diagnosis,
          plan: plan,
          verdict: ProblemVerdict.tooHard,
          rankKey: 0.5,
          reason: '没有复习记录，按题目自报难度 ${_pct(hint)} 先判为偏难（未标定先验）',
        );
      }
      final easy = hint != null && hint <= thresholds.hintEasy;
      return _evaluation(
        candidate: candidate,
        knowledgePointIds: knowledgePointIds,
        judged: judged,
        diagnosis: diagnosis,
        plan: plan,
        verdict: easy ? ProblemVerdict.tooEasy : ProblemVerdict.zpd,
        rankKey: easy ? 0.2 : 0.6,
        reason: easy
            ? '没有复习记录，按题目自报难度 ${_pct(hint)} 先判为偏易（未标定先验）'
            : '没有复习记录、也没有题目难度先验：模型无从判断，暂列发展中区（首次作答后才有结论）',
      );
    }

    if (meanRetrievability >= thresholds.tooEasyRetrievability &&
        !almostHadIt) {
      return _evaluation(
        candidate: candidate,
        knowledgePointIds: knowledgePointIds,
        judged: judged,
        diagnosis: diagnosis,
        plan: plan,
        verdict: ProblemVerdict.tooEasy,
        rankKey: meanGain - 0.1,
        reason: '平均可提取度 ${_pct(meanRetrievability)}：已经会了，复习它收益很低',
      );
    }
    if (meanRetrievability <= thresholds.tooHardRetrievability &&
        meanDifficulty >= thresholds.tooHardDifficulty) {
      return _evaluation(
        candidate: candidate,
        knowledgePointIds: knowledgePointIds,
        judged: judged,
        diagnosis: diagnosis,
        plan: plan,
        verdict: ProblemVerdict.tooHard,
        rankKey: meanGain - 0.05,
        reason: '平均可提取度 ${_pct(meanRetrievability)}'
            '且平均难度 ${meanDifficulty.toStringAsFixed(1)}：现在做它是硬啃',
      );
    }

    // "Worth the time" = the model flagged a cue as almost-there (the
    // development zone by the fast layer's own definition), or the problem
    // exercises more than one knowledge point at once (coverage is our reason,
    // and it is uncalibrated on purpose).
    final coversSeveral = judged.length >= 2;
    final highValue = almostHadIt || coversSeveral;
    return _evaluation(
      candidate: candidate,
      knowledgePointIds: knowledgePointIds,
      judged: judged,
      diagnosis: diagnosis,
      plan: plan,
      verdict: highValue ? ProblemVerdict.highValue : ProblemVerdict.zpd,
      rankKey:
          meanGain + 0.05 * (judged.length - 1) + (almostHadIt ? 0.15 : 0.0),
      reason: highValue
          ? '正在发展中（平均可提取度 ${_pct(meanRetrievability)}，模型增益 '
              '${meanGain.toStringAsFixed(2)}）：值得现在做'
          : '发展中区（平均可提取度 ${_pct(meanRetrievability)}）：可做',
    );
  }

  /// Marks a candidate whose knowledge points another candidate already covers.
  ///
  /// "Covered" is a set-containment test over the judged knowledge points: a
  /// problem that asks nothing new is `redundant`, and it is decided after all
  /// verdicts exist so the first (highest ranked) statement of a topic keeps its
  /// own verdict.
  static void _markRedundant(List<ProblemEvaluation> evaluations) {
    for (var i = 0; i < evaluations.length; i++) {
      final current = evaluations[i];
      if (current.verdict == ProblemVerdict.outOfScope ||
          current.judgedKnowledgePointIds.isEmpty) {
        continue;
      }
      final currentSet = current.judgedKnowledgePointIds.toSet();
      final covered = evaluations.any((other) =>
          other.problemId != current.problemId &&
          other.verdict != ProblemVerdict.outOfScope &&
          other.judgedKnowledgePointIds.length >
              current.judgedKnowledgePointIds.length &&
          currentSet.every(other.judgedKnowledgePointIds.contains));
      if (covered) {
        evaluations[i] = ProblemEvaluation(
          problemId: current.problemId,
          stem: current.stem,
          verdict: ProblemVerdict.redundant,
          rankKey: 0.1,
          // The counterfactual price is a property of the problem's own nodes,
          // so it survives the overwrite; the reason is replaced (and its
          // price clause with it) because the verdict is now "duplicate".
          reason: '这些闪存卡已被另一道更全的题覆盖，重复练习',
          knowledgePointIds: current.knowledgePointIds,
          judgedKnowledgePointIds: current.judgedKnowledgePointIds,
          diagnosisByKnowledgePoint: current.diagnosisByKnowledgePoint,
          counterfactualValue: current.counterfactualValue,
          counterfactualMetric: current.counterfactualMetric,
          counterfactualInstruction: current.counterfactualInstruction,
          counterfactualWhy: current.counterfactualWhy,
        );
      }
    }
  }

  static ProblemEvaluation _evaluation({
    required ProblemCandidate candidate,
    required List<String> knowledgePointIds,
    required List<String> judged,
    required Map<String, BottleneckType> diagnosis,
    required FastPlanEntry? plan,
    required ProblemVerdict verdict,
    required double rankKey,
    required String reason,
  }) {
    // "Not simulated" is a statement about the engine, not a price of zero:
    // such an entry carries no counterfactual field and adds no clause.
    final price = plan != null && plan.simulated ? plan : null;
    return ProblemEvaluation(
      problemId: candidate.id,
      stem: candidate.stem,
      verdict: verdict,
      rankKey: rankKey,
      reason: _withPrice(reason, price),
      knowledgePointIds: List.unmodifiable(knowledgePointIds),
      judgedKnowledgePointIds: List.unmodifiable(judged),
      diagnosisByKnowledgePoint: Map.unmodifiable(diagnosis),
      counterfactualValue: price?.value,
      counterfactualMetric: price?.metric,
      counterfactualInstruction: price?.instruction,
      counterfactualWhy: price?.why,
    );
  }

  /// Appends the counterfactual line when the planner actually simulated one.
  ///
  /// The clause is in the domain layer's words, like the rest of the reason, and
  /// it names the metric: a `reachability` gain is a claim about the graph, not
  /// about this problem's own cards.
  static String _withPrice(String reason, FastPlanEntry? plan) {
    if (plan == null) {
      return reason;
    }
    final metric = plan.metric ?? '未标定度量';
    return '$reason；反事实：${plan.instructionName}'
        '（$metric 增益 ${_num(plan.gain)} / 成本 ${_num(plan.cost)}'
        ' → V=${_num(plan.value)}；${plan.why}）';
  }
}

/// Three decimals: the planner's numbers are already rounded, and a reason line
/// is not a data table.
String _num(double value) => value.toStringAsFixed(3);

String _pct(double value) => '${(value * 100).round()}%';

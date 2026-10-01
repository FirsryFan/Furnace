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
library;

import '../../../data/database/database.dart';
import 'cognitive_graph.dart';
import 'cognitive_model.dart';
import 'fast_diagnosis.dart';
import 'fast_engine.dart';

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
}

/// The whole batch's result.
class ProblemEvaluationReport {
  const ProblemEvaluationReport({
    required this.evaluations,
    required this.fastLayerRan,
    required this.nodesWithoutMs,
  });

  /// Ranked: `rankKey` descending, then problem id ascending, so the order is
  /// total and independent of the input order.
  final List<ProblemEvaluation> evaluations;

  /// Whether the fast layer actually ran (tierB). When false every verdict came
  /// from tierA alone, and no `diagnosisByKnowledgePoint` is meaningful.
  final bool fastLayerRan;

  /// Nodes of the projected graph that carried no `ms` because no card row
  /// supplied an encoding strength. "Not provided" - **not** 0.8
  /// (`CognitiveGraph.nodesWithoutMs`).
  final List<String> nodesWithoutMs;
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
  /// * `runFastLayer` - set false to judge from tierA alone even when a graph
  ///   is available.
  static ProblemEvaluationReport evaluate({
    required List<ProblemCandidate> candidates,
    required List<CognitiveTag> tags,
    required Map<String, CardState> rowsByKnowledgePoint,
    required CognitiveModel model,
    required double nowHours,
    List<String> startKnowledgePointIds = const [],
    Map<String, double> importanceByTagId = const {},
    Map<String, Object?> moduleDefaults = const {},
    bool runFastLayer = true,
    ProblemEvaluatorThresholds thresholds =
        const ProblemEvaluatorThresholds(),
  }) {
    final nodeIds = {for (final tag in tags) tag.id};

    // ms is R0, the encoding ceiling - not the current retrievability (§6.3 as
    // clarified by MindNet's own `ensureState`, which reads `ms` as `R0`).
    // A tag without a card row, or with an illegal R0, is *omitted* so the
    // projection can name it in `nodesWithoutMs`: MindNet fills a missing `ms`
    // with its own default (0.8, `src/model.js:50`), and this side deliberately
    // does **not** use that fallback - "not provided" stays observable instead,
    // the same convention `cognitive_graph.dart` states for callers.
    final msByTagId = <String, double>{};
    for (final tag in tags) {
      final row = rowsByKnowledgePoint[tag.id];
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
      for (final id in startKnowledgePointIds)
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

      // This problem's own diffusion run. Targets are filtered to graph nodes:
      // the engine throws for anything else, and an empty target list is legal
      // but tells us nothing.
      final targets = [
        for (final id in knowledgePointIds)
          if (nodeIds.contains(id)) id,
      ];
      var diagnosis = const <String, BottleneckType>{};
      if (runFastLayer && tags.isNotEmpty && targets.isNotEmpty) {
        diagnosis = _diagnose(
          spec: spec,
          starts: starts,
          targets: targets,
          nowHours: nowHours,
          moduleDefaults: moduleDefaults,
          rounds: thresholds.diffusionRounds,
        );
        fastLayerRan = true;
      }

      evaluations.add(_judge(
        candidate: candidate,
        knowledgePointIds: knowledgePointIds,
        judged: judged,
        diagnosis: diagnosis,
        rows: rowsByKnowledgePoint,
        model: model,
        nowHours: nowHours,
        thresholds: thresholds,
      ));
    }

    _markRedundant(evaluations);

    evaluations.sort((a, b) {
      final byRank = b.rankKey.compareTo(a.rankKey);
      return byRank != 0 ? byRank : a.problemId.compareTo(b.problemId);
    });

    return ProblemEvaluationReport(
      evaluations: List.unmodifiable(evaluations),
      fastLayerRan: fastLayerRan,
      nodesWithoutMs: graph.nodesWithoutMs,
    );
  }

  /// Runs the tierB fast layer for one problem and returns what it complained
  /// about, keyed by knowledge point.
  static Map<String, BottleneckType> _diagnose({
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

    final out = <String, BottleneckType>{};
    for (final bottleneck in FastDiagnosis.bottlenecks(engine: engine)) {
      out.putIfAbsent(bottleneck.node, () => bottleneck.type);
    }
    return out;
  }

  /// The judgement for one candidate. Kept as one function so the precedence
  /// between the verdicts is readable in one place.
  static ProblemEvaluation _judge({
    required ProblemCandidate candidate,
    required List<String> knowledgePointIds,
    required List<String> judged,
    required Map<String, BottleneckType> diagnosis,
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
        verdict: ProblemVerdict.outOfScope,
        rankKey: 0,
        reason: '没有知识点标签，模型无从判断',
      );
    }
    if (noWayIn) {
      return _evaluation(
        candidate: candidate,
        knowledgePointIds: knowledgePointIds,
        judged: judged,
        diagnosis: diagnosis,
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
          verdict: ProblemVerdict.tooHard,
          rankKey: 0.5,
          reason:
              '没有复习记录，按题目自报难度 ${_pct(hint)} 先判为偏难（未标定先验）',
        );
      }
      final easy = hint != null && hint <= thresholds.hintEasy;
      return _evaluation(
        candidate: candidate,
        knowledgePointIds: knowledgePointIds,
        judged: judged,
        diagnosis: diagnosis,
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
      verdict: highValue ? ProblemVerdict.highValue : ProblemVerdict.zpd,
      rankKey: meanGain +
          0.05 * (judged.length - 1) +
          (almostHadIt ? 0.15 : 0.0),
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
          reason: '这些知识点已被另一道更全的题覆盖，重复练习',
          knowledgePointIds: current.knowledgePointIds,
          judgedKnowledgePointIds: current.judgedKnowledgePointIds,
          diagnosisByKnowledgePoint: current.diagnosisByKnowledgePoint,
        );
      }
    }
  }

  static ProblemEvaluation _evaluation({
    required ProblemCandidate candidate,
    required List<String> knowledgePointIds,
    required List<String> judged,
    required Map<String, BottleneckType> diagnosis,
    required ProblemVerdict verdict,
    required double rankKey,
    required String reason,
  }) =>
      ProblemEvaluation(
        problemId: candidate.id,
        stem: candidate.stem,
        verdict: verdict,
        rankKey: rankKey,
        reason: reason,
        knowledgePointIds: List.unmodifiable(knowledgePointIds),
        judgedKnowledgePointIds: List.unmodifiable(judged),
        diagnosisByKnowledgePoint: Map.unmodifiable(diagnosis),
      );
}

String _pct(double value) => '${(value * 100).round()}%';

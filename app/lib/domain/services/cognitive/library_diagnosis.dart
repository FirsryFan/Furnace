/// The whole-library tierB diagnosis: one diffusion run over the user's tag
/// graph, so the "认知模型" readings page can show a *real* zone per card
/// instead of [ReviewZone.unavailable] for every row.
///
/// Pure by construction - tags and card rows in, verdicts out, no database, no
/// clock, no IO - for the same reason [ProblemEvaluator] is pure: the page, the
/// probe and a test must get the same answer from the same inputs (D2).
///
/// Three product rules live here, because MindNet's engine does not have them
/// and this repository has no goal model to read them from:
///
/// * `starts` - "what the user is holding in mind right now" (§6.3). The page
///   passes the most recently reviewed knowledge points; empty is legal and
///   means the diffusion starts from the targets only.
/// * `targets` - MindNet's `goal` action ("这次要推进的目标"). Furnace has no
///   goal entity, so the closest honest stand-in is **today's due set**, which
///   the caller passes in. Everything outside it can therefore be reported as
///   `off_goal` / `dead_end`, which is exactly what those two verdicts mean.
///   Passing every node as a target is legal but makes those two verdicts
///   unreachable - the caller decides, this file does not guess.
/// * `rounds` - §6.3 says 3-5 rounds and the exact number is 未标定; the default
///   here is the same 4 as [ProblemEvaluatorThresholds.diffusionRounds].
///
/// **Danger is computed here now.** `danger` is the metacognition layer's
/// verdict ([Metacognition]), and MindNet gets it from `dangerRows` handed to
/// [FastDiagnosis.bottlenecks]. The belief formula needs a "how smoothly did
/// this go" signal, an encoding ceiling and "how long ago was this in mind" -
/// the first is the node's activation at the end of the diffusion, the second is
/// the model reading's `R0` (0.5 when the column has never been written, the
/// JS's own substitution for an unknown `R0`), and the third is "0 when the
/// diffusion leaves the node conscious, otherwise hours since it was last
/// reviewed". See [Metacognition] and
/// [_readMetacognition] for both substitutions in full, including why the
/// recency term is split in two. **That reading is a property of the run, not of
/// a problem**: it answers "what is on the learner's mind right now", and
/// 轮次二十二 measured that it cannot be projected onto one candidate - see the
/// boundary note in `problem_evaluator.dart` before wiring it there again.
///
/// Nodes with no card row are **not** counted: their retrievability is unknown,
/// and inventing one would manufacture confidence. They already show up in
/// [LibraryDiagnosis.nodesWithoutMs].
library;

import '../../../data/database/database.dart';
import 'cognitive_graph.dart';
import 'cognitive_model.dart';
import 'fast_diagnosis.dart';
import 'fast_engine.dart';
import 'metacognition.dart';

/// The result of one whole-library run, including *whether* it ran: an empty
/// [byKnowledgePoint] from a run means "the fast layer looked and had nothing to
/// say" (every node is healthy), while `fastLayerRan == false` means "there was
/// no graph to look at". Collapsing those two would let "not wired up" read as
/// "this student is fine" - the same distinction [ReviewAdvisory] makes between
/// `healthy` and `unavailable`.
class LibraryDiagnosis {
  const LibraryDiagnosis({
    required this.byKnowledgePoint,
    required this.fastLayerRan,
    this.metacognition = MetacognitionReading.empty,
    this.nodesWithoutMs = const <String>[],
    this.starts = const <String>[],
    this.targets = const <String>[],
    this.rounds = 0,
  });

  /// One verdict per complaining node, keyed by knowledge point (= tag) id.
  final Map<String, BottleneckType> byKnowledgePoint;

  /// Whether the diffusion actually ran. False means "no graph / no start".
  final bool fastLayerRan;

  /// Belief vs. reality for the counted nodes, including the `danger` rows that
  /// were folded into [byKnowledgePoint] as [BottleneckType.danger].
  final MetacognitionReading metacognition;

  /// Nodes the projection could not give an `ms` (R0) - observable on purpose:
  /// MindNet would fill its own default (0.8), this side refuses to invent it.
  final List<String> nodesWithoutMs;

  final List<String> starts;
  final List<String> targets;
  final int rounds;

  /// The honest "nothing ran" value.
  static const LibraryDiagnosis notRun = LibraryDiagnosis(
    byKnowledgePoint: <String, BottleneckType>{},
    fastLayerRan: false,
  );

  Map<String, Object?> toJson() => {
        'schema': 'mindnet.library/1',
        'fast_layer_ran': fastLayerRan,
        'rounds': rounds,
        'starts': starts,
        'targets': targets,
        'nodes_without_ms': nodesWithoutMs,
        'bottlenecks': {
          for (final entry in byKnowledgePoint.entries) entry.key: entry.value.id,
        },
        'metacognition': metacognition.toJson(),
      };
}

/// The row that represents a knowledge point: the unit with the most review
/// history, ties broken by id so the choice cannot depend on query order.
///
/// Furnace stores per unit (a point can own several blanks) while the fast layer
/// reasons per knowledge point, so *something* has to pick one. "The one that has
/// been reviewed the most" is the closest thing to "what this point currently
/// looks like"; the same rule is the AI tool's, and it lives here once so the two
/// callers cannot drift apart (D2).
CardState? representativeCardRow(List<CardState> states) {
  if (states.isEmpty) {
    return null;
  }
  final sorted = [...states]..sort((a, b) {
      final byReps = b.repetitions.compareTo(a.repetitions);
      return byReps != 0 ? byReps : a.id.compareTo(b.id);
    });
  return sorted.first;
}

/// Runs the fast layer once over the whole projection.
abstract final class LibraryDiagnosisRunner {
  /// Kept as a class method so the call site reads like the pipeline it is:
  /// tags -> CognitiveGraph.fromTags -> FastGraph.fromSpec ->
  /// FastEngine.startDiffusion -> runRounds -> FastDiagnosis.bottlenecks.
  static LibraryDiagnosis run({
    required List<CognitiveTag> tags,
    required Map<String, CardState> rowsByKnowledgePoint,
    required CognitiveModel model,
    required double nowHours,
    List<String> startKnowledgePointIds = const <String>[],
    List<String> targetKnowledgePointIds = const <String>[],
    Map<String, Object?> moduleDefaults = const <String, Object?>{},
    int rounds = 4,
  }) {
    if (tags.isEmpty) {
      return LibraryDiagnosis.notRun;
    }

    // `ms` is R0, the encoding ceiling (MindNet's `ensureState` reads it that
    // way). An illegal or missing R0 is *omitted* rather than defaulted, so
    // "not provided" stays visible in `nodesWithoutMs`.
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

    final graph = CognitiveGraph.fromTags(tags: tags, ms: msByTagId);
    final nodeIds = {for (final tag in tags) tag.id};
    // `startDiffusion` throws for an unknown id, so both lists are filtered to
    // real nodes here rather than crashing a read-only page.
    final starts = <String>[
      for (final id in startKnowledgePointIds)
        if (nodeIds.contains(id)) id,
    ];
    final targets = <String>[
      for (final id in targetKnowledgePointIds)
        if (nodeIds.contains(id)) id,
    ];
    if (starts.isEmpty && targets.isEmpty) {
      return LibraryDiagnosis(
        byKnowledgePoint: const <String, BottleneckType>{},
        fastLayerRan: false,
        nodesWithoutMs: graph.nodesWithoutMs,
      );
    }

    // D3's random-source removal: only the four ported mechanisms run, and
    // `T_ign = 0` turns ignition into a hard threshold so nothing is drawn.
    const overrides = <String, Object?>{'attention.ignition.T_ign': 0};
    final engine = FastEngine(
      graph: FastGraph.fromSpec(graph.toJson(), currentRealTime: nowHours),
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

    final metacognition = _readMetacognition(
      tags: tags,
      engine: engine,
      rowsByKnowledgePoint: rowsByKnowledgePoint,
      model: model,
      nowHours: nowHours,
      starts: starts,
    );

    final byKnowledgePoint = <String, BottleneckType>{};
    for (final bottleneck in FastDiagnosis.bottlenecks(
      engine: engine,
      dangerRows: [
        for (final row in metacognition.danger)
          FastDangerRow(
            node: row.node,
            name: row.name,
            belief: row.belief,
            r: row.r,
            diff: row.diff,
          ),
      ],
    )) {
      byKnowledgePoint.putIfAbsent(bottleneck.node, () => bottleneck.type);
    }

    return LibraryDiagnosis(
      byKnowledgePoint: byKnowledgePoint,
      fastLayerRan: true,
      metacognition: metacognition,
      nodesWithoutMs: graph.nodesWithoutMs,
      starts: starts,
      targets: targets,
      rounds: rounds,
    );
  }

  /// Belief vs. reality, built from what this app actually stores.
  ///
  /// Counted: every tag with a card row (so `R` is a real reading too) that is
  /// not a start. `fluency` = the activation the diffusion left on the node -
  /// MindNet's EMA seeded with its first observation. `r0` is `null` when the
  /// encoding column has never been written, which is how the formula's own 0.5
  /// substitution for an unknown `R0` stays reachable instead of being silently
  /// replaced by the model reading's 1.0 default.
  ///
  /// `recencyHours` is the "when was this last in mind" term, and MindNet gets it
  /// from a per-node `lastConscious` stamp that this app does not persist. So it
  /// is read in two halves, and the split matters because the alternative - just
  /// "hours since this card was last reviewed" - would couple the recency term to
  /// `R` (both come from the same `lastReviewedAt`) and cancel out the very gap
  /// the layer exists to find:
  ///
  /// * a node the diffusion leaves **conscious** is in mind *now*, exactly as the
  ///   JS stamps `lastConscious = ctx.hours` for a conscious node -> 0 hours;
  /// * otherwise the only trace left is the review history -> hours since the
  ///   representative card was last reviewed, and infinity when it never was
  ///   (the JS's `Infinity` for "never conscious").
  ///
  /// Private on purpose (轮次二十二): it was made public for a danger-first
  /// ordering in [ProblemEvaluator], and the measurement showed that ordering
  /// cannot work - the reader belongs to the run that produced it.
  static MetacognitionReading _readMetacognition({
    required List<CognitiveTag> tags,
    required FastEngine engine,
    required Map<String, CardState> rowsByKnowledgePoint,
    required CognitiveModel model,
    required double nowHours,
    required List<String> starts,
  }) {
    final observations = <MetacognitionObservation>[];
    for (final tag in tags) {
      final row = rowsByKnowledgePoint[tag.id];
      final node = engine.graph.nodes[tag.id];
      if (row == null || node == null) {
        continue;
      }
      final reading = model.modelReadingOf(row, nowHours: nowHours);
      if (!reading.r.isFinite) {
        continue;
      }
      final reviewedAt = row.lastReviewedAt;
      final conscious = node.state == FastNodeState.conscious;
      observations.add(MetacognitionObservation(
        node: tag.id,
        name: tag.name,
        fluency: node.activation,
        r0: row.encodingStrength == null ? null : reading.r0,
        r: reading.r,
        recencyHours: conscious
            ? 0
            : reviewedAt == null
                ? double.infinity
                : nowHours -
                    modelHoursOf(DateTime.fromMillisecondsSinceEpoch(reviewedAt)),
        isStart: starts.contains(tag.id),
      ));
    }
    return Metacognition.read(observations: observations);
  }
}

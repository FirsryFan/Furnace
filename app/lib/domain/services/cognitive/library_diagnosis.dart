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
/// **What cannot appear here:** `danger`. It comes from the metacognition layer
/// ([FastDiagnosis.bottlenecks]'s `dangerRows`), and this app stores no
/// confidence/belief rows at all, so the list stays empty by construction rather
/// than by accident. The page says so in words instead of implying "no danger".
library;

import '../../../data/database/database.dart';
import 'cognitive_graph.dart';
import 'cognitive_model.dart';
import 'fast_diagnosis.dart';
import 'fast_engine.dart';

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
    this.nodesWithoutMs = const <String>[],
    this.starts = const <String>[],
    this.targets = const <String>[],
    this.rounds = 0,
  });

  /// One verdict per complaining node, keyed by knowledge point (= tag) id.
  final Map<String, BottleneckType> byKnowledgePoint;

  /// Whether the diffusion actually ran. False means "no graph / no start".
  final bool fastLayerRan;

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

    final byKnowledgePoint = <String, BottleneckType>{};
    for (final bottleneck in FastDiagnosis.bottlenecks(engine: engine)) {
      byKnowledgePoint.putIfAbsent(bottleneck.node, () => bottleneck.type);
    }

    return LibraryDiagnosis(
      byKnowledgePoint: byKnowledgePoint,
      fastLayerRan: true,
      nodesWithoutMs: graph.nodesWithoutMs,
      starts: starts,
      targets: targets,
      rounds: rounds,
    );
  }
}

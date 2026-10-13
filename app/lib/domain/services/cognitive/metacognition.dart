/// The metacognition layer of MindNet v2 (`MODEL_v2_MATH.md` §6, ported from
/// `mechanisms/metacognition.belief.js`): how well the student *thinks* they
/// know something, and the two ways that belief can be wrong.
///
/// The point of the layer is a deliberate bias. Belief follows **how smoothly
/// the material went** (a moving average of activation), the encoding ceiling
/// `R0`, and "how long ago this was last in mind" - it deliberately does **not**
/// look at stability `S` or at review history. So a student who just crammed a
/// block feels confident while their real retrievability `R` is still low. That
/// gap is the whole product value:
///
/// * **danger** (`belief - R > delta`) - confident but cannot actually retrieve
///   it. These are the cards a student skips and most needs to practise.
/// * **anxiety** (`R - belief > delta`) - can retrieve it but does not believe it.
/// * `calibration` - mean `|belief - R|` over the counted nodes: 0 is perfectly
///   calibrated, larger is further off in either direction.
///
/// Like the rest of the cognitive layer this file is pure: observations in,
/// readings out. No database, no clock, no IO, so a page, the CLI probe and a
/// test agree by construction (D2).
///
/// **Two honest substitutions** live at the call site (`LibraryDiagnosisRunner`),
/// not here, because they come from what Furnace actually stores:
///
/// * fluency is the node's activation at the end of the run. MindNet keeps a
///   per-node EMA (`beta = 0.4`) across engine ticks; this app runs the engine
///   once per query, so the EMA's seed value (`fluency = a`, the JS default when
///   `bag.fluency === undefined`) is the faithful reading.
/// * "how long ago this node was last conscious" is ours: the time since the
///   knowledge point was last *reviewed*. MindNet has a persistent activation
///   bag, Furnace stores no such trace.
library;

import 'dart:math' as math;

import 'fast_engine.dart';

/// Weights of the belief formula. **Every value is 未标定** (uncalibrated): they
/// are the module's defaults, not fitted to this data set. The module's own note
/// explains why `w_fluency` is 1.5 rather than the math doc's 0.5: at 0.5 the
/// extra confidence cranked up by cramming came out at 0.03, "almost invisible".
class MetacognitionParams {
  const MetacognitionParams({
    this.wFluency = 1.5,
    this.wEncoding = 0.8,
    this.wRecency = 0.8,
    this.tauRecencyHours = 6,
    this.b0 = 1.5,
    this.delta = 0.2,
  });

  /// `w_fluency` (range 0-4).
  final double wFluency;

  /// `w_encoding` (range 0-4).
  final double wEncoding;

  /// `w_recency` (range 0-4).
  final double wRecency;

  /// `tau_recency_hours` (range 0.1-240).
  final double tauRecencyHours;

  /// `b0` (range -4..4): the bias taken off the logit.
  final double b0;

  /// `delta` (range 0.01-1): how big a `|belief - R|` gap has to be to count as
  /// danger or anxiety rather than noise.
  final double delta;

  Map<String, Object?> toJson() => {
        'w_fluency': wFluency,
        'w_encoding': wEncoding,
        'w_recency': wRecency,
        'tau_recency_hours': tauRecencyHours,
        'b0': b0,
        'delta': delta,
        'calibrated': false,
      };
}

/// One knowledge point as the belief formula sees it.
class MetacognitionObservation {
  const MetacognitionObservation({
    required this.node,
    required this.name,
    required this.fluency,
    required this.r0,
    required this.r,
    required this.recencyHours,
    this.isStart = false,
  });

  final String node;
  final String name;

  /// The moving average of activation (`a`); see the file docs for why this is
  /// the end-of-run activation here.
  final double fluency;

  /// The encoding ceiling, or `null` when it is genuinely unknown - the formula
  /// substitutes 0.5 for `null`, exactly as the JS does.
  final double? r0;

  /// Real retrievability now.
  final double r;

  /// Hours since this node was last in mind; [double.infinity] when never.
  final double recencyHours;

  /// Start nodes are skipped, as in the JS (`if (!f || f.is_start) continue`).
  final bool isStart;
}

/// One judgement: belief, reality, and the signed gap between them.
class MetacognitionRow {
  const MetacognitionRow({
    required this.node,
    required this.name,
    required this.belief,
    required this.r,
    required this.diff,
  });

  final String node;
  final String name;

  /// The model thinks the student knows it this well (0..1).
  final double belief;

  /// The student can actually retrieve it this well (0..1).
  final double r;

  /// `belief - r`: positive is overconfidence, negative is underconfidence.
  final double diff;

  Map<String, Object?> toJson() => {
        'node': node,
        'name': name,
        'belief': belief,
        'R': r,
        'diff': diff,
      };
}

/// The whole reading: every counted row, the two interesting tails (sorted by
/// how far off they are), and the mean error.
class MetacognitionReading {
  const MetacognitionReading({
    required this.rows,
    required this.danger,
    required this.anxiety,
    required this.calibration,
  });

  final List<MetacognitionRow> rows;
  final List<MetacognitionRow> danger;
  final List<MetacognitionRow> anxiety;

  /// Mean `|belief - R|` over [rows]; 0 when nothing was counted (the JS leaves
  /// 0 there too, so "no data" and "perfectly calibrated" share the number -
  /// the caller has to say which one it is, and [rows] is how it can tell).
  final double calibration;

  static const MetacognitionReading empty = MetacognitionReading(
    rows: <MetacognitionRow>[],
    danger: <MetacognitionRow>[],
    anxiety: <MetacognitionRow>[],
    calibration: 0,
  );

  /// Whether anything was counted at all.
  bool get hasRows => rows.isNotEmpty;

  Map<String, Object?> toJson() => {
        'schema': 'mindnet.metacognition/1',
        'calibration': calibration,
        'danger': [for (final row in danger) row.toJson()],
        'anxiety': [for (final row in anxiety) row.toJson()],
        'rows': [for (final row in rows) row.toJson()],
      };
}

/// The pure layer.
abstract final class Metacognition {
  /// `beta = 0.4`, hardcoded in the JS because it defines "the last few rounds"
  /// rather than being a mechanism parameter. Only meaningful across ticks; this
  /// app runs the engine once, so [read] takes the seed value directly.
  static const double emaBeta = 0.4;

  /// The numeric sigmoid, using the stable branch for negative arguments (the
  /// same two-branch form as the JS, so a very negative logit cannot overflow).
  static double sigmoid(double x) {
    if (x >= 0) {
      return 1 / (1 + math.exp(-x));
    }
    final e = math.exp(x);
    return e / (1 + e);
  }

  /// `beliefOf(fluency, R0, recencyHours, o)`, including the JS's `R0 === null`
  /// substitution of 0.5.
  static double beliefOf({
    required double fluency,
    required double? r0,
    required double recencyHours,
    MetacognitionParams params = const MetacognitionParams(),
  }) {
    final hours = recencyHours.isFinite && recencyHours > 0 ? recencyHours : 0.0;
    final recency = math.exp(-hours / params.tauRecencyHours);
    final z = params.wFluency * fluency +
        params.wEncoding * (r0 ?? 0.5) +
        params.wRecency * recency -
        params.b0;
    return sigmoid(z);
  }

  /// Turns observations into the reading. Rows are rounded to 6 decimals exactly
  /// as the JS does, so a future conformance diff against MindNet compares
  /// numbers rather than float noise.
  static MetacognitionReading read({
    required List<MetacognitionObservation> observations,
    MetacognitionParams params = const MetacognitionParams(),
  }) {
    final rows = <MetacognitionRow>[];
    final danger = <MetacognitionRow>[];
    final anxiety = <MetacognitionRow>[];
    var errorSum = 0.0;

    for (final observation in observations) {
      if (observation.isStart) {
        continue;
      }
      final belief = beliefOf(
        fluency: observation.fluency,
        r0: observation.r0,
        recencyHours: observation.recencyHours,
        params: params,
      );
      final gap = belief - observation.r;
      final row = MetacognitionRow(
        node: observation.node,
        name: observation.name,
        belief: FastEngine.round6(belief),
        r: observation.r,
        diff: FastEngine.round6(gap),
      );
      rows.add(row);
      if (gap > params.delta) {
        danger.add(row);
      }
      if (-gap > params.delta) {
        anxiety.add(row);
      }
      errorSum += gap.abs();
    }

    danger.sort((x, y) => y.diff.compareTo(x.diff));
    anxiety.sort((x, y) => x.diff.compareTo(y.diff));

    return MetacognitionReading(
      rows: rows,
      danger: danger,
      anxiety: anxiety,
      calibration: rows.isEmpty ? 0 : FastEngine.round6(errorSum / rows.length),
    );
  }
}

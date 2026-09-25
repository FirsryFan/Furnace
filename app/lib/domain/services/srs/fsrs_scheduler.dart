/// Dart port of the FSRS-6 spaced-repetition scheduler (long-term mode),
/// line-by-line port of ts-fsrs v5.4.1 `packages/fsrs` (2026-09):
///
/// - algorithm.ts (FSRSAlgorithm, forgetting curve with decay = -w20)
/// - impl/long_term_scheduler.ts (no intra-day learning steps)
/// - constant.ts + default.ts (FSRS-6 default weights)
///
/// Local-only, fully deterministic, no fuzz (enable_fuzz = false).
///
/// Furnace integration: the spec's wrong-answer forced-binding machine
/// (10 min short interval, 2 consecutive correct) lives OUTSIDE this class,
/// on CardStates.forced/forcedStreak; once released, FSRS takes over again.
library;

import 'dart:math' as math;

/// Grade mapping used across the codebase UI: 忘记->Again, 模糊->Hard,
/// 记得->Good (Easy reserved). Mirrors ts-fsrs Rating 1..4.
enum FsrsRating { again, hard, good, easy }

extension FsrsRatingX on FsrsRating {
  int get value => index + 1;
}

/// FSRS-6 defaults (ts-fsrs constant.ts).
class FsrsParameters {
  const FsrsParameters({
    this.w = _defaultW,
    this.requestRetention = 0.9,
    this.maximumInterval = 36500,
  });

  final List<double> w;
  final double requestRetention;
  final double maximumInterval;

  static const List<double> _defaultW = [
    0.212, 1.2931, 2.3065, 8.2956, // initial stability Again/Hard/Good/Easy
    6.4133, 0.8334, 3.0194, 0.001, // difficulty params
    1.8722, 0.1666, 0.796, // recall stability params
    1.4835, 0.0614, 0.2629, 1.6483, // forget stability params
    0.6014, 1.8729, // hard penalty / easy bound
    0.5425, 0.0912, 0.0658, // short-term (unused in long-term mode)
    0.1542, // FSRS6 decay
  ];
}

/// Memory state carried by CardStates (stability / difficulty).
class FsrsMemory {
  const FsrsMemory({required this.stability, required this.difficulty});

  final double stability;
  final double difficulty;
}

/// Outcome of scheduling one review.
class FsrsScheduleResult {
  const FsrsScheduleResult({
    required this.memory,
    required this.dueAt,
    required this.scheduledDays,
    required this.lapses,
  });

  final FsrsMemory memory;

  /// Next review moment (>= [now] + 1 day in long-term mode).
  final DateTime dueAt;
  final int scheduledDays;

  /// Increment of the lapse counter for this review (0 or 1).
  final int lapses;
}

/// Pure FSRS-6 scheduler (long-term mode).
abstract final class FsrsScheduler {
  static const double sMin = 0.001;
  static const double sMax = 36500.0;
  static const double initSMax = 100.0;

  // --- parameter helpers ---------------------------------------------------

  /// w with 17 (FSRS-4/5) or 19 (FSRS-5/6 without decay) entries migrated to
  /// the FSRS-6 21-entry shape (mirrors default.ts migrateParameters).
  static List<double> normalizeWeights(List<double> w) {
    final list = List<double>.from(w);
    switch (list.length) {
      case 21:
        return list;
      case 19:
        return [...list, 0.0, 0.1542];
      case 17:
        final migrated = List<double>.from(list);
        migrated[4] = double.parse((list[5] * 2.0 + list[4]).toStringAsFixed(8));
        migrated[5] =
            double.parse((log(list[5] * 3.0 + 1.0) / 3.0).toStringAsFixed(8));
        migrated[6] = double.parse((list[6] + 0.5).toStringAsFixed(8));
        return [...migrated, 0.0, 0.0, 0.0, 0.1542];
      default:
        throw ArgumentError(
            'FSRS parameter length must be 17, 19 or 21, got ${w.length}');
    }
  }

  // --- curve pieces --------------------------------------------------------

  /// decay = -w20 ; factor = e^(ln(0.9)/decay) - 1
  static ({double decay, double factor}) decayFactor(List<double> w) {
    final decay = -w[20];
    final factor = exp(log(0.9) / decay) - 1.0;
    return (decay: decay, factor: round8(factor));
  }

  /// R(t,S) = (1 + factor * t / S)^decay  (t in days)
  static double forgettingCurve({
    required List<double> w,
    required double elapsedDays,
    required double stability,
  }) {
    final df = decayFactor(w);
    return round8(pow(1 + (df.factor * elapsedDays) / stability, df.decay));
  }

  /// I(r) = (r^(1/decay) - 1) / factor
  static double intervalModifier(List<double> w, double retention) {
    final df = decayFactor(w);
    return round8((pow(retention, 1 / df.decay) - 1) / df.factor);
  }

  /// S0(G) = max(w[G-1], 0.1)
  static double initStability(List<double> w, FsrsRating g) =>
      max(w[g.value - 1], 0.1);

  /// D0(G) = w4 - e^((G-1)*w5) + 1, clamped into [1, 10]
  static double initDifficulty(List<double> w, FsrsRating g) {
    final d = w[4] - exp((g.value - 1) * w[5]) + 1;
    return round8(clamp(d, 1, 10));
  }

  static double linearDamping(double deltaD, double oldD) =>
      round8((deltaD * (10 - oldD)) / 9);

  /// D' = clamp(w7 * D0(Easy) + (1 - w7) * (D + damping(-w6*(G-3), D)), 1, 10)
  static double nextDifficulty(
      List<double> w, double d, FsrsRating g) {
    final deltaD = -w[6] * (g.value - 3);
    final nextD = d + linearDamping(deltaD, d);
    return clamp(w[7] * initDifficulty(w, FsrsRating.easy) +
        (1 - w[7]) * nextD, 1, 10);
  }

  /// S'r after a successful recall.
  static double nextRecallStability(
      List<double> w, double d, double s, double r, FsrsRating g) {
    final hardPenalty = g == FsrsRating.hard ? w[15] : 1.0;
    final easyBound = g == FsrsRating.easy ? w[16] : 1.0;
    return round8(clamp(
        s *
            (1 +
                exp(w[8]) *
                    (11 - d) *
                    pow(s, -w[9]) *
                    (exp((1 - r) * w[10]) - 1) *
                    hardPenalty *
                    easyBound),
        sMin,
        sMax));
  }

  /// S'f after a failed recall (long-term mode, w17/w18 unused).
  static double nextForgetStability(List<double> w, double d, double s, double r) {
    final raw = w[11] *
        pow(d, -w[12]) *
        (pow(s + 1, w[13]) - 1) *
        exp((1 - r) * w[14]);
    return round8(clamp(raw, sMin, sMax));
  }

  // --- next-state (algorithm.ts next_state) --------------------------------

  /// Memory transition; [memory] null means a new card.
  static FsrsMemory nextMemory({
    required List<double> w,
    required FsrsMemory? memory,
    required double elapsedDays,
    required FsrsRating g,
    double? retrievability,
  }) {
    final d = memory?.difficulty ?? 0.0;
    final s = memory?.stability ?? 0.0;
    if (d == 0 && s == 0) {
      return FsrsMemory(
        difficulty: clamp(initDifficulty(w, g), 1, 10),
        stability: initStability(w, g),
      );
    }
    final r = retrievability ??
        forgettingCurve(w: w, elapsedDays: elapsedDays, stability: s);
    final double newS;
    if (g == FsrsRating.again) {
      final sAfterFail = nextForgetStability(w, d, s, r);
      // Long-term mode: w17 = w18 = 0 -> lower bound = s; clamp keeps <= s.
      newS = clamp(sAfterFail, sMin, s);
    } else {
      newS = nextRecallStability(w, d, s, r, g);
    }
    return FsrsMemory(stability: newS, difficulty: nextDifficulty(w, d, g));
  }

  /// next_interval: max(1, round(S * intervalModifier)), capped.
  static int nextIntervalDays(
      List<double> w, double stability, double retention, double maximumInterval) {
    final ivl =
        max(1.0, (stability * intervalModifier(w, retention)).roundToDouble())
            .toInt();
    return ivl > maximumInterval ? maximumInterval.toInt() : ivl;
  }

  // --- one-review scheduling (LongTermScheduler single path) ----------------

  /// Schedules a review with the given rating.
  ///
  /// [lastReview] is required when [memory] is not null (elapsed days derive
  /// from it). New cards schedule from today.
  static FsrsScheduleResult schedule({
    required FsrsMemory? memory,
    required DateTime lastReview,
    required DateTime now,
    required FsrsRating rating,
    FsrsParameters parameters = const FsrsParameters(),
  }) {
    final w = normalizeWeights(parameters.w);
    final isNew = memory == null;
    final elapsedDays = isNew
        ? 0.0
        : max(0.0, now.difference(lastReview).inMilliseconds / 86400000.0);

    // Compute the full four-way family so the monotonic ordering constraints
    // of the reference implementation hold for the chosen grade.
    FsrsMemory family(FsrsRating g) => nextMemory(
          w: w,
          memory: memory,
          elapsedDays: elapsedDays,
          g: g,
          retrievability: isNew
              ? null
              : forgettingCurve(
                  w: w,
                  elapsedDays: elapsedDays,
                  stability: memory.stability),
        );

    var again = nextIntervalDays(
        w, family(FsrsRating.again).stability, parameters.requestRetention, parameters.maximumInterval);
    var hard = nextIntervalDays(
        w, family(FsrsRating.hard).stability, parameters.requestRetention, parameters.maximumInterval);
    var good = nextIntervalDays(
        w, family(FsrsRating.good).stability, parameters.requestRetention, parameters.maximumInterval);
    var easy = nextIntervalDays(
        w, family(FsrsRating.easy).stability, parameters.requestRetention, parameters.maximumInterval);

    again = again < hard ? again : hard;
    hard = hard > again + 1 ? hard : again + 1;
    good = good > hard + 1 ? good : hard + 1;
    easy = easy > good + 1 ? easy : good + 1;

    final days = switch (rating) {
      FsrsRating.again => again,
      FsrsRating.hard => hard,
      FsrsRating.good => good,
      FsrsRating.easy => easy,
    };
    final memory2 = family(rating);
    final lapses = (rating == FsrsRating.again && !isNew) ? 1 : 0;

    return FsrsScheduleResult(
      memory: memory2,
      scheduledDays: days,
      dueAt: now.add(Duration(days: days)),
      lapses: lapses,
    );
  }

  // --- tiny helpers ---------------------------------------------------------

  static double round8(double v) => double.parse(v.toStringAsFixed(8));
  static double clamp(double v, double lo, double hi) =>
      v < lo ? lo : (v > hi ? hi : v);
}

double exp(double x) => math.exp(x);
double log(double x) => math.log(x);
double pow(double x, double y) => math.pow(x, y).toDouble();
double max(double a, double b) => a > b ? a : b;

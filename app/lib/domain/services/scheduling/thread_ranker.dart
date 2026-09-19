/// ThreadRanker - the weighted priority ranking engine (spec 1.1.3 + user
/// annotations 2026-09-08).
///
///   total = urgency*wUrgency + goalMatch*wGoal + fit*wFit
///           + expectedPressure*wExpected - fatiguePenalty*wFatigue
///
/// All sub-scores are normalized to [0,1]; defaults live in
/// ThreadflowDefaults (GAP 4.1). Pure Dart - no DB access.
///
/// User-annotated semantics (blueprint v2):
/// - `expected_time` and `deadline` are INDEPENDENT observation points.
///   `expected_time` NEVER triggers the red hard constraint; when it is near
///   or past, the event gets a YELLOW flag plus a `expectedPressure` boost.
/// - The red constraint ONLY looks at `deadline`:
///     available = (deadline - now) - busy hard-block minutes
///     estimate > available  ->  `insufficient`, moved out of the main list.
///   `deadline < now` is a separate `overdue` bucket.
/// - The ranking exposes every component and weight so the UI can show and
///   edit them (property page, no hidden parameters).
library;

import 'dart:math' as math;

import '../config/threadflow_defaults.dart';
import 'time_window_engine.dart';

/// Tunable weights of the weighted sum. Exposed to the UI so the user can
/// inspect and edit every parameter (blueprint P5). Defaults come from
/// [ThreadflowDefaults].
class RankWeights {
  const RankWeights({
    this.urgency = ThreadflowDefaults.wUrgency,
    this.goal = ThreadflowDefaults.wGoal,
    this.fit = ThreadflowDefaults.wFit,
    this.fatigue = ThreadflowDefaults.wFatigue,
    this.expected = ThreadflowDefaults.wExpected,
  });

  final double urgency;
  final double goal;
  final double fit;
  final double fatigue;
  final double expected;

  RankWeights copyWith({
    double? urgency,
    double? goal,
    double? fit,
    double? fatigue,
    double? expected,
  }) =>
      RankWeights(
        urgency: urgency ?? this.urgency,
        goal: goal ?? this.goal,
        fit: fit ?? this.fit,
        fatigue: fatigue ?? this.fatigue,
        expected: expected ?? this.expected,
      );

  Map<String, double> toMap() => {
        'urgency': urgency,
        'goal': goal,
        'fit': fit,
        'fatigue': fatigue,
        'expected': expected,
      };

  /// Sum of all five weights.
  ///
  /// The five weights are NOT hand-normalized any more: `wExpected` was added
  /// on top of the original spec set `0.4/0.3/0.2/0.1`, which made the
  /// achievable total 1.05 and inflated every score by 5% (verified by probe:
  /// `0.4 + 0.3 + 0.2 + 0.1 + 0.05 = 1.05`). The ranker divides by this sum
  /// so scores stay comparable in [0,1] whatever the user dials in.
  double get sum => urgency + goal + fit + fatigue + expected;

  /// Returns the same weights rescaled so they add up to exactly 1.0.
  /// A non-positive sum is returned unchanged (the caller guards that case).
  RankWeights normalized() {
    final total = sum;
    if (total <= 0) {
      return this;
    }
    return RankWeights(
      urgency: urgency / total,
      goal: goal / total,
      fit: fit / total,
      fatigue: fatigue / total,
      expected: expected / total,
    );
  }
}

class RankEvent {
  const RankEvent({
    required this.id,
    required this.title,
    this.estimateMinutes,
    this.expectedAt,
    this.dueAt,
    this.energyRequired,
    this.tagPaths = const [],
  });

  final String id;
  final String title;
  final int? estimateMinutes;
  final DateTime? expectedAt;
  final DateTime? dueAt;
  final int? energyRequired;

  /// Full hierarchical tag paths attached to the event.
  final List<String> tagPaths;
}

class RankGoal {
  const RankGoal({this.text, this.path});

  /// Free text goal (the only mode in use - blueprint 2.5).
  final String? text;

  /// Legacy Mindnet node path. Kept for compatibility; Mindnet is merged into
  /// the tag system (blueprint 2.8) so this stays null in normal use.
  final String? path;
}

/// A completion-log entry as consumed by the fatigue penalty.
class RankCompletion {
  const RankCompletion({required this.completedAt, this.tagPaths = const []});

  final DateTime completedAt;
  final List<String> tagPaths;
}

class RankContext {
  const RankContext({
    required this.now,
    this.energy,
    this.goal = const RankGoal(),
    this.blocks = const [],
    this.completions = const [],
    this.dueHorizon,
    this.weights = const RankWeights(),
  });

  final DateTime now;

  /// Current energy 1..10; null = not set.
  final int? energy;
  final RankGoal goal;

  /// Schedule blocks (busy hard blocks occupy time).
  final List<ScheduleBlock> blocks;

  /// Recent completion history (spec 2 Thread -> History).
  final List<RankCompletion> completions;

  /// Horizon for free-window computation (defaults to 7 days).
  final DateTime? dueHorizon;

  /// Editable weights (blueprint P5 - no hidden parameters).
  final RankWeights weights;
}

/// Full score decomposition for one event: every raw component plus the
/// contribution it made to the total. The property page renders exactly these
/// numbers (blueprint P6: no reason text in the list, everything in property).
class RankScore {
  const RankScore({
    required this.urgency,
    required this.goalMatch,
    required this.fit,
    required this.fatiguePenalty,
    required this.total,
    this.expectedPressure = 0.0,
    this.energyFit,
    this.windowFit,
    this.weights = const RankWeights(),
  });

  final double urgency;
  final double goalMatch;
  final double fit;
  final double fatiguePenalty;

  /// Yellow-flag component: how near/past `expected_time` is (0..1).
  final double expectedPressure;

  /// Sub-components of [fit], exposed for the property page. Null means "no
  /// data for this side" (energy not set / no estimate), which is different
  /// from a genuine 0.0 score.
  final double? energyFit;
  final double? windowFit;

  final double total;
  final RankWeights weights;

  /// Per-component contribution = component * weight (fatigue is a penalty).
  double get urgencyContribution => urgency * weights.urgency;
  double get goalContribution => goalMatch * weights.goal;
  double get fitContribution => fit * weights.fit;
  double get expectedContribution => expectedPressure * weights.expected;
  double get fatigueContribution => -fatiguePenalty * weights.fatigue;

  /// True when the event carries the yellow "expected time is near/past" flag.
  bool get isExpectedNear => expectedPressure > 0;
}

class RankedEvent {
  const RankedEvent({
    required this.event,
    required this.score,
    this.insufficient = false,
    this.overdue = false,
    this.availableMinutes,
    this.neededMinutes,
  });

  final RankEvent event;
  final RankScore score;

  /// Hard-constraint violation: estimate does not fit before the deadline.
  final bool insufficient;

  /// Deadline already passed (separate bucket from [insufficient]).
  final bool overdue;

  /// available = (deadline - now) - busy minutes (spec 1.1.3).
  final int? availableMinutes;
  final int? neededMinutes;

  /// Yellow flag: expected time is near or past (kept in the main list).
  bool get expectedNear => score.isExpectedNear;
}

class RankOutput {
  const RankOutput({
    required this.ready,
    required this.insufficient,
    this.overdue = const [],
  });

  /// Normal ranked list (may still contain yellow-flagged events).
  final List<RankedEvent> ready;

  /// Red: estimate does not fit before the deadline.
  final List<RankedEvent> insufficient;

  /// Red: deadline already passed.
  final List<RankedEvent> overdue;

  List<RankedEvent> get all => [...ready, ...insufficient, ...overdue];
}

abstract final class ThreadRanker {
  static RankOutput rank({
    required List<RankEvent> events,
    required RankContext context,
  }) {
    final ready = <RankedEvent>[];
    final insufficient = <RankedEvent>[];
    final overdue = <RankedEvent>[];

    for (final event in events) {
      final dueAt = event.dueAt;
      final estimate = event.estimateMinutes;

      if (dueAt != null && !dueAt.isAfter(context.now)) {
        overdue.add(RankedEvent(
          event: event,
          score: _score(event, context),
          overdue: true,
          availableMinutes: 0,
          neededMinutes: estimate,
        ));
        continue;
      }

      final busy = _busyMinutesBeforeDeadline(context, event);
      final hardAvailable = dueAt == null
          ? null
          : _millisToMinutes(
                  dueAt.difference(context.now).inMilliseconds) -
              busy;

      final cannotFit = estimate != null &&
          estimate > 0 &&
          dueAt != null &&
          hardAvailable != null &&
          estimate >
              hardAvailable + ThreadflowDefaults.insufficientMarginMinutes;

      if (cannotFit) {
        insufficient.add(RankedEvent(
          event: event,
          score: _score(event, context),
          insufficient: true,
          availableMinutes: hardAvailable,
          neededMinutes: estimate,
        ));
      } else {
        ready.add(RankedEvent(
          event: event,
          score: _score(event, context),
          availableMinutes: hardAvailable,
          neededMinutes: estimate,
        ));
      }
    }

    ready.sort((a, b) => b.score.total.compareTo(a.score.total));
    insufficient.sort((a, b) {
      final aDue = a.event.dueAt;
      final bDue = b.event.dueAt;
      if (aDue != null && bDue != null) {
        return aDue.compareTo(bDue);
      }
      if (aDue != null) {
        return -1;
      }
      return bDue != null ? 1 : a.event.title.compareTo(b.event.title);
    });
    overdue.sort((a, b) {
      final aDue = a.event.dueAt;
      final bDue = b.event.dueAt;
      if (aDue != null && bDue != null) {
        return bDue.compareTo(aDue); // most recently overdue first
      }
      return a.event.title.compareTo(b.event.title);
    });

    return RankOutput(
      ready: ready,
      insufficient: insufficient,
      overdue: overdue,
    );
  }

  static RankScore _score(RankEvent event, RankContext context) {
    // Normalized so the achievable total stays inside [0,1] no matter what
    // weights the user dialed in (see RankWeights.sum).
    final weights = context.weights.normalized();
    final urgency = _urgency(event, context.now);
    final goal = _goalMatch(event, context.goal);
    final energyFit = _energyFit(event, context);
    final windowFit = _windowFit(event, context);
    final fit = _fitOf(energyFit, windowFit);
    final fatigue = _fatigue(event, context);
    final expected = _expectedPressure(event, context.now);
    final total = urgency * weights.urgency +
        goal * weights.goal +
        fit * weights.fit +
        expected * weights.expected -
        fatigue * weights.fatigue;
    return RankScore(
      urgency: urgency,
      goalMatch: goal,
      fit: fit,
      fatiguePenalty: fatigue,
      expectedPressure: expected,
      energyFit: energyFit,
      windowFit: windowFit,
      total: total,
      weights: weights,
    );
  }

  /// Averages only the sub-components that actually have data.
  ///
  /// "Not set" must not silently read as half-match: previously a missing
  /// energy level produced `energyFit = 0.5` and dragged every score down by a
  /// fixed amount (verified by probe: `energyFit=0.5`, `fit=0.75`). A missing
  /// sub-component is now dropped from the average; when neither side has data
  /// the documented neutral score applies.
  static double _fitOf(double? energyFit, double? windowFit) {
    if (energyFit != null && windowFit != null) {
      return (energyFit + windowFit) / 2;
    }
    if (windowFit != null) {
      return windowFit;
    }
    if (energyFit != null) {
      return energyFit;
    }
    return ThreadflowDefaults.fitMissingEstimateScore;
  }

  // --- urgency ---------------------------------------------------------------

  static double _urgency(RankEvent event, DateTime now) {
    if (event.dueAt != null) {
      final remaining = event.dueAt!.difference(now);
      if (remaining.inMinutes <= ThreadflowDefaults.urgencyCapMinutes) {
        return 1.0;
      }
      return _decay(remaining.inMinutes.toDouble(),
          ThreadflowDefaults.urgencyHalfLifeMinutes);
    }
    if (event.expectedAt != null) {
      final remaining = event.expectedAt!.difference(now);
      if (remaining.inMinutes <= 0) {
        return ThreadflowDefaults.expectedSoftCap;
      }
      return _decay(remaining.inMinutes.toDouble(),
              ThreadflowDefaults.expectedSoftHalfLifeMinutes) *
          ThreadflowDefaults.expectedSoftCap;
    }
    return 0.0;
  }

  static double _decay(double minutes, double halfLifeMinutes) =>
      pow(0.5, minutes / halfLifeMinutes);

  // --- goal match (1.1.3; free text only per blueprint 2.5) -------------------

  static double _goalMatch(RankEvent event, RankGoal goal) {
    if (event.tagPaths.isEmpty) {
      return 0.0;
    }
    if (goal.path != null && goal.path!.isNotEmpty) {
      var best = 0.0;
      for (final tag in event.tagPaths) {
        if (TagPath.isSameOrUnder(path: goal.path!, candidate: tag)) {
          return 1.0;
        }
        // Partial credit: shared ancestor depth / goal depth.
        final goalSegs = TagPath.segments(goal.path!);
        final tagSegs = TagPath.segments(tag);
        var shared = 0;
        final limit = goalSegs.length < tagSegs.length
            ? goalSegs.length
            : tagSegs.length;
        while (shared < limit && goalSegs[shared] == tagSegs[shared]) {
          shared++;
        }
        final partial = shared / goalSegs.length;
        if (partial > best) {
          best = partial;
        }
      }
      return best;
    }
    final text = goal.text;
    if (text == null || text.trim().isEmpty) {
      return 0.0;
    }
    final keywords = text
        .split(RegExp(r'[\s，。；、,.;:：！？!?（）()]+'))
        .where((k) => k.isNotEmpty)
        .toList();
    if (keywords.isEmpty) {
      return 0.0;
    }
    var hits = 0;
    for (final keyword in keywords) {
      for (final tag in event.tagPaths) {
        if (tag.contains(keyword)) {
          hits++;
          break;
        }
      }
    }
    return hits / keywords.length;
  }

  // --- state fit -------------------------------------------------------------

  /// Energy component, or null when the energy level is not set (the caller
  /// drops it from the average instead of inventing a neutral value).
  static double? _energyFit(RankEvent event, RankContext context) {
    final required = event.energyRequired;
    final current = context.energy;
    if (required == null || current == null) {
      return null;
    }
    final delta = (required - current).abs().toDouble();
    return 1.0 - (delta / 9.0).clamp(0.0, 1.0);
  }

  /// Window component, or null when the event has no estimate to fit
  /// anywhere.
  static double? _windowFit(RankEvent event, RankContext context) {
    final estimate = event.estimateMinutes;
    if (estimate == null || estimate <= 0) {
      return null;
    }
    final window = TimeWindowEngine.nextFreeWindow(
      blocks: context.blocks,
      from: context.now,
      minDuration: Duration(minutes: estimate),
      horizon: context.dueHorizon,
    );
    if (window == null) {
      return 0.0;
    }
    return 1.0;
  }

  // --- fatigue penalty (1.1.3, D7) ---------------------------------------------

  static double _fatigue(RankEvent event, RankContext context) {
    final now = context.now;
    final windowMinutes = ThreadflowDefaults.fatigueWindowMinutes;
    var raw = 0.0;
    for (final completion in context.completions) {
      final ageMinutes =
          now.difference(completion.completedAt).inMinutes.toDouble();
      if (ageMinutes < 0 || ageMinutes >= windowMinutes) {
        continue;
      }
      final decay = 1.0 - ageMinutes / windowMinutes;
      var overlap = 0;
      for (final donePath in completion.tagPaths) {
        for (final eventPath in event.tagPaths) {
          if (TagPath.isSameOrUnder(path: donePath, candidate: eventPath) ||
              TagPath.isSameOrUnder(path: eventPath, candidate: donePath)) {
            overlap++;
          }
        }
      }
      if (overlap > 0) {
        raw += decay * overlap;
      }
    }
    final normalized = raw / ThreadflowDefaults.fatigueNormDenominator;
    return normalized.clamp(0.0, 1.0);
  }

  // --- expected-time pressure (blueprint 2.3, YELLOW flag) ---------------------

  /// Rises to 1 as `expected_time` approaches (within
  /// [ThreadflowDefaults.expectedNearWindowMinutes]), saturates at 1 while
  /// overdue, then fades back to 0 over the soft half-life so a
  /// long-forgotten expectation does not boost forever.
  static double _expectedPressure(RankEvent event, DateTime now) {
    final expectedAt = event.expectedAt;
    if (expectedAt == null) {
      return 0.0;
    }
    final minutesUntil = expectedAt.difference(now).inMinutes.toDouble();
    final window = ThreadflowDefaults.expectedNearWindowMinutes.toDouble();
    if (minutesUntil <= 0) {
      // Past the expected moment with no deadline conflict (such events never
      // reach here): keep the yellow flag for the near window, then fade.
      final overdue = -minutesUntil;
      if (overdue <= window) {
        return 1.0;
      }
      final faded =
          (1.0 - (overdue - window) / ThreadflowDefaults.expectedSoftHalfLifeMinutes)
              .clamp(0.0, 1.0);
      return faded;
    }
    if (minutesUntil >= window) {
      return 0.0;
    }
    return 1.0 - minutesUntil / window;
  }

  // --- hard constraint ---------------------------------------------------------

  static int _busyMinutesBeforeDeadline(RankContext context, RankEvent event) {
    final dueAt = event.dueAt;
    if (dueAt == null || !dueAt.isAfter(context.now)) {
      return 0;
    }
    return TimeWindowEngine.busyMinutes(
      blocks: context.blocks,
      windowStart: context.now,
      windowEnd: dueAt,
    );
  }

  static int _millisToMinutes(int millis) =>
      (millis / 60000).floor().clamp(0, 1 << 31);
}

double pow(double base, double exponent) => math.pow(base, exponent).toDouble();

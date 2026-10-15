import 'dart:math' as math;

import 'rhythm_gate.dart';

/// How long a gap between two study actions still counts as "the same sitting".
///
/// **Uncalibrated proxy.** MindNet's rhythm tier only knows `t_on`, the
/// unbroken on-task minutes the engine has been running; this app has no
/// session timer, so the sitting has to be *derived from the study log* that
/// already exists (`review_logs.reviewed_at`, `exposure_logs.exposed_at`).
/// 15 minutes is the chosen reading of "a break long enough to reset the
/// clock": anything longer starts a new sitting, anything shorter extends the
/// current one. It is a named constant precisely so a later calibration round
/// can find and replace it.
const Duration kStudySessionGap = Duration(minutes: 15);

/// `α` at or above this reads as "make the hard thing".
const double kRhythmHardAbove = 0.7;

/// `α` below this reads as "rest or do something easy".
const double kRhythmRestBelow = 0.35;

/// What the reading suggests right now.
///
/// The three live values mirror the roadmap's wording ("做难 / 做易 / 休息");
/// [none] is what the caller sees when there is no sitting to read at all,
/// which is *not* the same claim as "your α is 1".
enum StudyAdvice { none, hard, moderate, rest }

/// One sitting: a maximal run of study actions whose consecutive gaps are all
/// `<= gap`.
class StudySession {
  const StudySession({
    required this.startedAt,
    required this.lastActionAt,
    required this.actionCount,
  });

  final DateTime startedAt;
  final DateTime lastActionAt;
  final int actionCount;

  /// Wall time from the first action of the sitting to its last one. The
  /// reading itself measures to `now`, not to here (see [StudyRhythm.read]).
  Duration get span => lastActionAt.difference(startedAt);
}

/// A reading of the rhythm tier's `α` for the sitting the user is in.
///
/// [vigilance] is `G_vig(τ) = exp(-t_on/τ_vig)` (§5.2) and is the number the
/// advice is based on, because `G_duty` averages out over a cycle: the duty gate
/// decides *when inside a cycle* the engine is on, not how much of it is.
/// [availability] is the gate's own `openTicks / cycleTicks` for [load] and is
/// carried along for the ordering work that will consume it later.
class StudyRhythmReading {
  const StudyRhythmReading({
    required this.session,
    required this.now,
    required this.minutesOn,
    required this.vigilance,
    required this.cycleTicks,
    required this.openTicks,
    required this.availability,
    required this.advice,
  });

  final StudySession session;
  final DateTime now;

  /// Unbroken on-task minutes: sitting start → [now].
  final double minutesOn;
  final double vigilance;
  final int cycleTicks;
  final int openTicks;
  final double availability;
  final StudyAdvice advice;

  int get minutesOnRounded => minutesOn.round();

  /// `0.37` → `37`, for the UI's percent display.
  int get vigilancePercent => (vigilance.clamp(0, 1) * 100).round();

  Map<String, Object?> toJson() => <String, Object?>{
        'minutes_on': minutesOnRounded,
        'vigilance': vigilance,
        'cycle_ticks': cycleTicks,
        'open_ticks': openTicks,
        'availability': availability,
        'advice': advice.name,
        'session_started_at': session.startedAt.millisecondsSinceEpoch,
        'session_actions': session.actionCount,
      };
}

/// Pure logic: turn a list of study-action timestamps into "the sitting you are
/// in, and what α says about it".
///
/// Nothing here touches the database or the clock: the caller passes `now`
/// explicitly, which is what makes the boundary cases (a gap of exactly
/// `gap`, actions after `now`) testable.
abstract final class StudyRhythm {
  /// Splits [actions] into sittings. Input order does not matter; actions in the
  /// future relative to [now] are dropped by [read] but kept by this function
  /// (it has no `now` to judge them against).
  static List<StudySession> sessions(
    Iterable<DateTime> actions, {
    Duration gap = kStudySessionGap,
  }) {
    final sorted = actions.toList()..sort();
    if (sorted.isEmpty) {
      return const <StudySession>[];
    }

    final result = <StudySession>[];
    var start = sorted.first;
    var last = sorted.first;
    var count = 1;
    for (var i = 1; i < sorted.length; i += 1) {
      final at = sorted[i];
      if (at.difference(last) <= gap) {
        last = at;
        count += 1;
      } else {
        result.add(
          StudySession(
              startedAt: start, lastActionAt: last, actionCount: count),
        );
        start = at;
        last = at;
        count = 1;
      }
    }
    result.add(
      StudySession(startedAt: start, lastActionAt: last, actionCount: count),
    );
    return result;
  }

  /// The sitting `now` falls into, or null when the last action is older than
  /// [gap] — i.e. the user walked away long enough that the on-task clock has
  /// reset. Returning null (rather than α = 1) is the point: "you are fresh"
  /// and "there is no sitting" are different claims.
  static StudySession? currentSession(
    Iterable<DateTime> actions, {
    required DateTime now,
    Duration gap = kStudySessionGap,
  }) {
    final upToNow = actions.where((at) => !at.isAfter(now));
    final all = sessions(upToNow, gap: gap);
    if (all.isEmpty) {
      return null;
    }
    final last = all.last;
    if (now.difference(last.lastActionAt) > gap) {
      return null;
    }
    return last;
  }

  /// The reading, or null when there is no sitting to read.
  ///
  /// [load] is the activation load the reference's `round.before` sums (nodes
  /// at or above their ignition threshold); it defaults to 0 because the thread
  /// page has no engine run in hand, and it only moves the *cycle*.
  static StudyRhythmReading? read({
    required Iterable<DateTime> actions,
    required DateTime now,
    double load = 0,
    RhythmGateParams params = const RhythmGateParams(),
  }) {
    if (load < 0) {
      throw ArgumentError.value(load, 'load', '负荷不能为负');
    }
    final session = currentSession(actions, now: now);
    if (session == null) {
      return null;
    }

    final gate = RhythmGate(params: params);
    final minutesOn =
        now.difference(session.startedAt).inMilliseconds / 60000.0;
    final vigilance = gate.vigilanceFor(minutesOn: minutesOn);
    final cycleTicks = gate.cycleTicksFor(load: load);
    final openTicks = gate.openCountFor(
      cycle: cycleTicks,
      vigilance: vigilance,
    );

    return StudyRhythmReading(
      session: session,
      now: now,
      minutesOn: minutesOn,
      vigilance: vigilance,
      cycleTicks: cycleTicks,
      openTicks: openTicks,
      availability: cycleTicks == 0 ? 1 : openTicks / cycleTicks,
      advice: adviceFor(vigilance),
    );
  }

  /// The three-way suggestion. Thresholds are uncalibrated (see
  /// [kRhythmHardAbove] / [kRhythmRestBelow]) and deliberately coarse: the
  /// reading shows the number next to the words so the user can disagree with
  /// the words without losing the measurement.
  static StudyAdvice adviceFor(double vigilance) {
    if (vigilance.isNaN) {
      return StudyAdvice.none;
    }
    if (vigilance >= kRhythmHardAbove) {
      return StudyAdvice.hard;
    }
    if (vigilance >= kRhythmRestBelow) {
      return StudyAdvice.moderate;
    }
    return StudyAdvice.rest;
  }

  /// `G_vig`'s half-life in minutes, for the UI's explanation line.
  static double halfVigilanceMinutes({
    RhythmGateParams params = const RhythmGateParams(),
  }) =>
      params.tauVigMinutes * math.ln2;
}

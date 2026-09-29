import 'package:drift/drift.dart';

import '../../../data/database/database.dart';
import 'dsr_memory.dart';

/// Bridges the cognitive model's memory state and the `card_states` row.
///
/// **The point of this file is that there is exactly one memory state per
/// card.** MindNet's `R0` / `S` / `Σ` / `D` map onto columns that already
/// exist - `encoding_strength`, `stability`, `savings`, `difficulty` - so
/// adopting the model needs no new table, no new column and no migration.
/// Running the model therefore cannot desynchronise from what the review flow
/// reads: both sides read and write the same row.
///
/// The conversion is deliberately **stateless and total**: every field that
/// exists in one representation exists in the other, and nothing else is
/// stashed anywhere. If a future field cannot be stored, the right move is to
/// add a column (one definition, one migration) rather than to keep a shadow
/// copy in memory.
abstract final class DsrCardState {
  /// Hours per day. MindNet works in hours; `card_states` stores days.
  ///
  /// This is the single conversion point the contract warns about
  /// (MINDNET_CONTRACT §6.1): the curve constants are identical in both
  /// systems, so converting anywhere else would be a silent bug.
  static const double hoursPerDay = 24;

  /// Reads the model state out of a stored row.
  ///
  /// A row that has never carried model state (NULL columns) is initialised
  /// from the card's own data rather than from a default: an item with known
  /// stability should not be treated as brand new just because the cognitive
  /// model has not seen it yet. That is what keeps the two from disagreeing on
  /// the first read - the historical FSRS values become the model's starting
  /// point.
  ///
  /// **Unit convention, and the trap in it.** MindNet's clock (`u`) is *hours
  /// since the Unix epoch*, and its `ensureState` initialises
  /// `lastReview = node.last_review_time || now` with `now` defaulting to 0.
  /// So "no review recorded" means **0 hours since the epoch** - the model
  /// treats a never-reviewed item as learned at the beginning of time, which
  /// makes its retrievability decay to almost nothing instead of reading as
  /// brand new. Substituting the current time here is intuitive and wrong: it
  /// makes `dt = 0` forever, so the item stays at R = 1 and the model silently
  /// does nothing at all.
  static DsrState read(
    CardState row, {
    DsrParams params = const DsrParams(),
    double nowHours = 0,
  }) {
    final s = row.stability;
    final d = row.difficulty;
    if (s == null && d == null) {
      // Truly unset: no memory at all yet.
      return DsrState.initial(
        now: nowHours,
        ms: row.encodingStrength,
        params: params,
        lastReview: _hoursFrom(row.lastReviewedAt) ?? 0,
      );
    }

    return DsrState(
      // With no recorded ceiling, 1.0 is the honest reading: FSRS's curve has
      // no ceiling, and R0 = 1 makes this model's curve identical to it
      // (verified: both give R = 0.9 at t = S).
      r0: row.encodingStrength ?? 1.0,
      s: (s ?? 0) * hoursPerDay,
      sigma: row.savings ?? 0.8,
      d: d ?? params.d0,
      n: row.repetitions,
      // `lapses` is a lifetime count and the model's `F` is decayed evidence,
      // so they are not the same quantity. Starting F at 0 is the honest
      // choice: the model will rebuild its own evidence from real failures,
      // and inventing decayed history from a count would be fabrication.
      f: 0,
      lastFail: null,
      lastReview: _hoursFrom(row.lastReviewedAt) ?? 0,
      initializedAt: nowHours,
    );
  }

  /// Writes the model state back onto a row's update companion.
  ///
  /// Every scheduled value the review flow relies on is derived here, so a
  /// single call leaves the row fully consistent - there is no second step that
  /// a caller could forget.
  static CardStatesCompanion write(
    DsrState state, {
    required double nowHours,
    required double targetRetention,
    DsrParams params = const DsrParams(),
    int? nowMillis,
  }) {
    final intervalHours =
        DsrMemory.scheduleInterval(state, nowHours, targetRetention, params);
    final now = nowMillis ?? _millisFromHours(nowHours);

    return CardStatesCompanion(
      stability: Value(state.s / hoursPerDay),
      difficulty: Value(state.d),
      encodingStrength: Value(state.r0),
      savings: Value(state.sigma),
      intervalDays: Value(intervalHours / hoursPerDay),
      dueAt: Value(
        intervalHours <= 0
            // The target is unreachable (it sits above R0): due immediately
            // rather than scheduled into the past.
            ? now
            : now + (intervalHours * Duration.millisecondsPerHour).round(),
      ),
      lastReviewedAt: Value(now),
      updatedAt: Value(now),
      // Present but unused by the model; kept accurate so the row is
      // self-consistent for anything that still reads them (the SM-2 and FSRS
      // paths, and the review UI).
      repetitions: Value(state.n),
      ease: Value(_easeFrom(state)),
    );
  }

  /// The current retrievability of a stored row, in `[0, 1]`.
  ///
  /// This is the "how well is it known right now" number the review ordering
  /// needs; it is derived, never stored separately.
  static double retrievabilityOf(
    CardState row, {
    required double nowHours,
    DsrParams params = const DsrParams(),
  }) {
    final state = read(row, params: params, nowHours: nowHours);
    return DsrMemory.retrievability(state, nowHours, params).r;
  }

  /// How much a review right now would strengthen the item.
  ///
  /// Used to prioritise: reviewing something that is nearly forgotten (low R)
  /// yields more than reviewing something still fresh, which is the model's
  /// whole claim and a better ordering rule than "due date ascending".
  static double expectedGain(
    CardState row, {
    required double nowHours,
    double closeness = 0.5,
    DsrParams params = const DsrParams(),
  }) {
    final state = read(row, params: params, nowHours: nowHours);
    final r = DsrMemory.retrievability(state, nowHours, params).r;
    return DsrMemory.stabilityIncrease(
        state, r, params, DsrEventType.retrievalSuccess, closeness);
  }

  /// Maps the review UI's rating (1..4) onto a model event.
  ///
  /// The mapping is explicit because the two vocabularies differ: FSRS grades
  /// describe how the recall felt, while the model distinguishes *how* the
  /// answer was produced. A failed recall is a lapse; a hard-but-successful one
  /// is a success with a low grade (which raises D and therefore slows later
  /// gains) - not a failure, because the answer did come back.
  static DsrReviewEvent eventFor({
    required int rating,
    bool reread = false,
    double closeness = 0.5,
  }) {
    if (rating <= 1) {
      return const DsrReviewEvent(type: DsrEventType.lapse, grade: 1);
    }
    return DsrReviewEvent(
      type: reread ? DsrEventType.reread : DsrEventType.retrievalSuccess,
      grade: rating.clamp(1, 4),
      closeness: closeness,
    );
  }

  /// Applies one review to a stored row and returns the update to persist.
  ///
  /// A pure function of the row plus the event: it reads, computes, and hands
  /// back a companion. The caller owns the write, so there is exactly one place
  /// per call site where the database changes.
  static ({CardStatesCompanion update, DsrReviewOutcome outcome}) applyReview(
    CardState row, {
    required int rating,
    required double nowHours,
    required double targetRetention,
    bool reread = false,
    double closeness = 0.5,
    DsrParams params = const DsrParams(),
    int? nowMillis,
  }) {
    final state = read(row, params: params, nowHours: nowHours);
    final outcome = DsrMemory.applyReview(
      state,
      nowHours,
      eventFor(rating: rating, reread: reread, closeness: closeness),
      params,
    );
    return (
      update: write(
        state,
        nowHours: nowHours,
        targetRetention: targetRetention,
        params: params,
        nowMillis: nowMillis,
      ),
      outcome: outcome,
    );
  }

  /// A display-only ease value, so the legacy column does not silently become
  /// nonsense. `1.3 + difficulty` puts D = 1 at 2.3 and D = 10 at 11.3, which
  /// is the same direction (higher = harder) as SM-2's ease.
  static double _easeFrom(DsrState state) => 1.3 + state.d;

  static double? _hoursFrom(int? millis) =>
      millis == null ? null : millis / Duration.millisecondsPerHour;

  static int _millisFromHours(double hours) =>
      (hours * Duration.millisecondsPerHour).round();
}

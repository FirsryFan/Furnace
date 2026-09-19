/// Simplified SM-2 spaced repetition scheduler for KnowFlow.
///
/// The UI exposes three review ratings:
/// - [SrsRating.forgot]
/// - [SrsRating.fuzzy]
/// - [SrsRating.remembered]
///
/// Internally they are mapped to SM-2 quality values so the algorithm stays
/// close to the classic implementation and can be replaced by FSRS later.
library;

/// User rating after reviewing a card.
enum SrsRating {
  forgot,
  fuzzy,
  remembered;

  int get quality => switch (this) {
        SrsRating.forgot => 2,
        SrsRating.fuzzy => 3,
        SrsRating.remembered => 5,
      };
}

/// Persisted scheduling state for one card.
class SrsState {
  const SrsState({
    this.repetitions = 0,
    this.easeFactor = 2.5,
    this.intervalDays = 0,
    this.dueAt,
  });

  final int repetitions;
  final double easeFactor;
  final double intervalDays;
  final DateTime? dueAt;

  SrsState copyWith({
    int? repetitions,
    double? easeFactor,
    double? intervalDays,
    DateTime? dueAt,
  }) {
    return SrsState(
      repetitions: repetitions ?? this.repetitions,
      easeFactor: easeFactor ?? this.easeFactor,
      intervalDays: intervalDays ?? this.intervalDays,
      dueAt: dueAt ?? this.dueAt,
    );
  }
}

/// Result of applying a rating to a card.
class SrsReviewResult {
  const SrsReviewResult({
    required this.state,
    required this.nextDueAt,
  });

  final SrsState state;
  final DateTime nextDueAt;
}

/// SM-2 scheduler implementation.
abstract final class Sm2Scheduler {
  static const double minimumEase = 1.3;

  /// Applies [rating] to [current] and returns the new state plus next due time.
  ///
  /// [now] is used as the review time. If [current.dueAt] is null the card is
  /// treated as a new card.
  static SrsReviewResult review({
    required SrsState current,
    required SrsRating rating,
    required DateTime now,
  }) {
    final quality = rating.quality;
    var repetitions = current.repetitions;
    var interval = current.intervalDays;
    var ease = current.easeFactor;

    if (quality >= 3) {
      repetitions += 1;
      interval = switch (repetitions) {
        1 => 1,
        2 => 6,
        _ => (interval * ease).roundToDouble(),
      };
    } else {
      repetitions = 0;
      interval = 1;
    }

    ease = ease +
        (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02));
    if (ease < minimumEase) {
      ease = minimumEase;
    }

    final nextDueAt = now.add(Duration(days: interval.round()));
    final next = SrsState(
      repetitions: repetitions,
      easeFactor: ease,
      intervalDays: interval,
      dueAt: nextDueAt,
    );

    return SrsReviewResult(state: next, nextDueAt: nextDueAt);
  }

  /// Cards due on or before [now] are ready for review.
  static bool isDue(SrsState state, DateTime now) {
    final dueAt = state.dueAt;
    if (dueAt == null) {
      return true;
    }
    return !dueAt.isAfter(now);
  }
}

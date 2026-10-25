/// Review spacing: the target memory retention FSRS schedules against.
///
/// User feedback (2026-10-25): 「闪存卡…间隔时间太短了」. FSRS ships a default
/// target retention of 0.9, and in long-term mode 0.9 means "the interval equals
/// stability" — the first Good answer on a new card comes back in **3 days** and
/// then roughly 10. Nothing let the user ask for longer spacing, so the number
/// was effectively hard-coded.
///
/// This file owns the one place that number is translated from "how the user
/// wants to space reviews" into an FSRS parameter. Lower retention = longer
/// intervals (the scheduler accepts a bigger forgetting risk). The mapping is
/// coarse on purpose: three named choices the user can reason about, not a
/// free-form float they cannot calibrate.
library;

/// Factory default: 0.85.
///
/// Deliberately lower than FSRS's own 0.9 default: the app's first-run spacing
/// was reported as too short, and 0.85 multiplies every interval by ~1.9
/// (interval modifier 0.9 → 1.0, 0.85 → ≈1.905). Users who preferred the old
/// rhythm can pick 更短 (0.90) in 复习偏好.
const double kDefaultReviewRetention = 0.85;

/// Lowest retention the UI can pick: 0.75.
///
/// Below this the intervals start doubling every couple of reviews and a lapsed
/// card can be forgotten for months; the clamp keeps a corrupt/legacy value from
/// throwing the whole schedule away.
const double kReviewRetentionMin = 0.75;

/// Highest retention the UI can pick: 0.95.
const double kReviewRetentionMax = 0.95;

/// The three spacing choices the preferences UI shows.
enum ReviewSpacing {
  /// 更长: accept more forgetting risk, review less often.
  longer(0.80),

  /// 标准: the factory default (0.85).
  standard(kDefaultReviewRetention),

  /// 更短: closer to FSRS's own 0.9 default — more reviews, shorter gaps.
  shorter(0.90);

  const ReviewSpacing(this.retention);

  /// The FSRS target retention this choice maps to.
  final double retention;

  /// Maps a stored retention back to the closest choice.
  ///
  /// Stored values never have to be one of the three: a future version may add
  /// a choice, and the raw column is a double. Anything below the midpoint
  /// between 更长/标准 reads as 更长, above the midpoint between 标准/更短 reads
  /// as 更短, and everything in between reads as 标准 — so an unknown-but-legal
  /// number still lands on a sane segment instead of crashing or showing nothing.
  static ReviewSpacing fromRetention(double? raw) {
    final retention = normalizeReviewRetention(raw);
    if (retention < (longer.retention + standard.retention) / 2) {
      return longer;
    }
    if (retention > (standard.retention + shorter.retention) / 2) {
      return shorter;
    }
    return standard;
  }
}

/// Normalizes whatever the settings row holds into a usable FSRS retention.
///
/// - null / NaN / infinity → [kDefaultReviewRetention] (the user never picked,
///   or the row is corrupt; neither may throw during a review).
/// - anything outside [kReviewRetentionMin]..[kReviewRetentionMax] → clamped.
///
/// The clamp is a guard, not a rewrite: legal values pass through untouched, so
/// a future finer setting is not silently flattened to the three presets.
double normalizeReviewRetention(double? raw) {
  if (raw == null || raw.isNaN || raw.isInfinite) {
    return kDefaultReviewRetention;
  }
  if (raw < kReviewRetentionMin) {
    return kReviewRetentionMin;
  }
  if (raw > kReviewRetentionMax) {
    return kReviewRetentionMax;
  }
  return raw;
}

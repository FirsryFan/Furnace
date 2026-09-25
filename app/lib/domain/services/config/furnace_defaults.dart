/// Central default constants for the Furnace algorithms (GAP 4.1-4.3).
///
/// Every tunable value that the final spec (FURNACE_SPEC.md 1.1.3 / 1.3)
/// does not pin down lives here - single source of truth, no UI hardcoding.
library;

class FurnaceDefaults {
  FurnaceDefaults._();

  // ---- ThreadRanker weights (spec 1.1.3) --------------------------------
  static const double wUrgency = 0.4;
  static const double wGoal = 0.3;
  static const double wFit = 0.2;
  static const double wFatigue = 0.1;

  /// Extra weight for the YELLOW expected-time pressure component (blueprint
  /// 2.3, user annotation 2026-09-08). Deliberately small: `expected_time` is
  /// a soft observation point and must never outweigh a real deadline.
  static const double wExpected = 0.05;

  // ---- ThreadRanker sub-scores -------------------------------------------
  /// Urgency = 0.5^(remainingMinutes / halfLife); overdue or <= 15 min -> 1.
  static const double urgencyHalfLifeMinutes = 240;
  static const int urgencyCapMinutes = 15;

  /// Soft constraint (expected time only, no deadline): urgency capped at 0.5
  /// with its own half-life.
  static const double expectedSoftHalfLifeMinutes = 360;
  static const double expectedSoftCap = 0.5;

  /// Expected-time pressure (YELLOW flag): the flag ramps up inside this
  /// window before the expected moment (1.0 at the moment itself), stays 1.0
  /// while overdue, then fades over [expectedSoftHalfLifeMinutes].
  static const int expectedNearWindowMinutes = 120;

  /// Fatigue penalty window and decay (linear 1 -> 0 over the window).
  static const int fatigueWindowMinutes = 60;
  static const double fatigueNormDenominator = 2.0;

  /// Energy fit: 1 - min(1, |required - current| / 9).
  static const int energyScaleMin = 1;
  static const int energyScaleMax = 10;

  /// Fit for estimated duration vs the next free window: 1 when the free
  /// window >= estimate, else freeWindow / estimate (0.5 when the estimate
  /// is missing and no window info is used).
  static const double fitMissingEstimateScore = 0.5;

  /// Hard constraint: estimate > available -> red-listed at the bottom.
  static const int insufficientMarginMinutes = 0;

  // ---- Actual-time recording (blueprint 2.6, user annotation 14) ----------
  /// Actual duration = completion moment - start moment. No running timer is
  /// ever started; only the two stamps are stored.
  ///
  /// A record is treated as "probably interrupted" (excluded from model
  /// updates by default) when actual > estimate * [actualAnomalyMultiplier]
  /// AND actual > [actualAnomalyMinMinutes].
  static const double actualAnomalyMultiplier = 3.0;
  static const int actualAnomalyMinMinutes = 30;

  // ---- Thread status bar --------------------------------------------------
  /// State older than this prompts for confirmation before sorting.
  static const Duration stateStaleAfter = Duration(hours: 2);

  // ---- Knowledge / cloze (spec 1.3.2) ------------------------------------
  /// Probability of attempting a brand-new cloze blank per draw.
  static const double newClozeProbability = 0.5;

  /// Short relearning interval after a wrong answer.
  static const int forcedRelearnMinutes = 10;

  /// Consecutive correct answers required to release a forced unit.
  static const int forcedConsecutiveCorrect = 2;

  /// Mindnet graph diffusion boost factors and cycle count (spec 1.3.3).
  static const double boostDistance1 = 1.8;
  static const double boostDistance2 = 1.3;
  static const int boostCycles = 3;

  // ---- Appearance (spec 4) -----------------------------------------------
  static const double scaleMin = 0.8;
  static const double scaleMax = 1.5;
}

/// Path utilities for the hierarchical tag system (spec 1.1.1/1.1.2).
abstract final class TagPath {
  static const String separator = '/';

  /// Full path split into its segments.
  static List<String> segments(String path) =>
      path.split(separator).where((s) => s.isNotEmpty).toList();

  /// Parent path of [path] ("" for a top-level tag).
  static String parent(String path) {
    final index = path.lastIndexOf(separator);
    return index < 0 ? '' : path.substring(0, index);
  }

  /// The leaf (last segment) of [path].
  static String leaf(String path) {
    final index = path.lastIndexOf(separator);
    return index < 0 ? path : path.substring(index + 1);
  }

  static String join(List<String> segments) => segments.join(separator);

  /// True when [candidate] is [path] itself or under it.
  static bool isSameOrUnder({required String path, required String candidate}) {
    return candidate == path || candidate.startsWith('$path$separator');
  }

  /// All ancestor paths of [path] including itself (root-most first).
  static List<String> ancestorsInclusive(String path) {
    final parts = segments(path);
    return [
      for (var i = 1; i <= parts.length; i++) join(parts.sublist(0, i)),
    ];
  }
}

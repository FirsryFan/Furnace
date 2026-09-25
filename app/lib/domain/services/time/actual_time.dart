/// Actual-time recording (blueprint 2.6, user annotation 2026-09-08).
///
/// The app NEVER runs a ticking timer: it only stores the moment the user
/// started an event and the moment they completed it, then computes the
/// difference in whole minutes. This keeps the resource cost at zero and makes
/// "forgot to stop it" a data problem instead of a battery problem.
///
/// Anomaly guard: a suspiciously long record must not poison the duration
/// model, so it is excluded by default while staying visible and switchable
/// per record.
library;

import '../config/furnace_defaults.dart';

/// The outcome of one completed event, ready to be written to the completion
/// history.
class ActualTimeRecord {
  const ActualTimeRecord({
    required this.actualMinutes,
    required this.suspicious,
    required this.includeInModel,
  });

  /// Completion moment - start moment, in whole minutes (never negative).
  final int actualMinutes;

  /// True when the record looks interrupted (see the default rule) and was
  /// therefore excluded by default.
  final bool suspicious;

  /// Whether this record may feed the duration model. Defaults to
  /// `!suspicious`, but the user can flip it per record.
  final bool includeInModel;
}

abstract final class ActualTime {
  /// Computes the record for an event that was started at [startedAt] and
  /// completed at [completedAt].
  ///
  /// [estimateMinutes] enables the anomaly rule; pass null when the event has
  /// no estimate (nothing to compare against, so nothing is suspicious).
  /// [userOverride] forces the `includeInModel` flag when the user explicitly
  /// toggled it for this record.
  static ActualTimeRecord compute({
    required DateTime startedAt,
    required DateTime completedAt,
    int? estimateMinutes,
    bool? userOverride,
  }) {
    final seconds = completedAt.difference(startedAt).inSeconds;
    final minutes = seconds <= 0 ? 0 : (seconds / 60).floor();
    final suspicious = isSuspicious(
      actualMinutes: minutes,
      estimateMinutes: estimateMinutes,
    );
    return ActualTimeRecord(
      actualMinutes: minutes,
      suspicious: suspicious,
      includeInModel: userOverride ?? !suspicious,
    );
  }

  /// Default anomaly rule: `actual > estimate * multiplier` AND
  /// `actual > minMinutes`. Both conditions are required so that a short
  /// 5-minute task taking 16 minutes is not flagged.
  static bool isSuspicious({
    required int actualMinutes,
    int? estimateMinutes,
  }) {
    final estimate = estimateMinutes;
    if (estimate == null || estimate <= 0) {
      return false;
    }
    return actualMinutes >
            estimate * FurnaceDefaults.actualAnomalyMultiplier &&
        actualMinutes > FurnaceDefaults.actualAnomalyMinMinutes;
  }
}

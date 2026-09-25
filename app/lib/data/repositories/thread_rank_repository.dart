import 'package:drift/drift.dart';

import '../../domain/services/config/furnace_defaults.dart';
import '../../domain/services/scheduling/thread_ranker.dart';
import '../database/database.dart';

/// Repository for the single-row Thread ranking parameters.
///
/// Every weight the ranking engine uses is stored here instead of being
/// hard-coded, because the user requires all parameters to be visible and
/// editable from the event property page (blueprint P5 / user annotation 6).
class ThreadRankRepository {
  ThreadRankRepository(this._db);

  final AppDatabase _db;

  Future<ThreadRankSetting?> getSettings() async {
    final rows = await _db.select(_db.threadRankSettings).get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<ThreadRankSetting> ensureSettings() async {
    final existing = await getSettings();
    if (existing != null) {
      return existing;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.threadRankSettings).insert(
          ThreadRankSettingsCompanion.insert(createdAt: now),
        );
    return (_db.select(_db.threadRankSettings)..where((t) => t.id.equals(1)))
        .getSingle();
  }

  /// The weights in the shape the ranking engine consumes.
  Future<RankWeights> getWeights() async {
    final settings = await ensureSettings();
    return RankWeights(
      urgency: settings.wUrgency,
      goal: settings.wGoal,
      fit: settings.wFit,
      fatigue: settings.wFatigue,
      expected: settings.wExpected,
    );
  }

  /// Persists edited weights. Pass null to leave a weight untouched.
  Future<void> updateWeights({
    double? urgency,
    double? goal,
    double? fit,
    double? fatigue,
    double? expected,
  }) async {
    await ensureSettings();
    await (_db.update(_db.threadRankSettings)..where((t) => t.id.equals(1)))
        .write(
      ThreadRankSettingsCompanion(
        wUrgency: urgency == null ? const Value.absent() : Value(urgency),
        wGoal: goal == null ? const Value.absent() : Value(goal),
        wFit: fit == null ? const Value.absent() : Value(fit),
        wFatigue: fatigue == null ? const Value.absent() : Value(fatigue),
        wExpected: expected == null ? const Value.absent() : Value(expected),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  Future<void> updateWeightsFrom(RankWeights weights) => updateWeights(
        urgency: weights.urgency,
        goal: weights.goal,
        fit: weights.fit,
        fatigue: weights.fatigue,
        expected: weights.expected,
      );

  /// Restores the shipped default weights.
  Future<void> resetWeights() => updateWeights(
        urgency: FurnaceDefaults.wUrgency,
        goal: FurnaceDefaults.wGoal,
        fit: FurnaceDefaults.wFit,
        fatigue: FurnaceDefaults.wFatigue,
        expected: FurnaceDefaults.wExpected,
      );

  /// Whether the Thread status bar is collapsed (blueprint 2.2).
  Future<bool> isHeaderCollapsed() async =>
      (await ensureSettings()).headerCollapsed;

  Future<void> setHeaderCollapsed(bool collapsed) async {
    await ensureSettings();
    await (_db.update(_db.threadRankSettings)..where((t) => t.id.equals(1)))
        .write(
      ThreadRankSettingsCompanion(
        headerCollapsed: Value(collapsed),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// Global switch: may actual durations inform the duration model
  /// (blueprint 2.6).
  Future<bool> getUseActualTime() async =>
      (await ensureSettings()).useActualTime;

  Future<void> setUseActualTime(bool value) async {
    await ensureSettings();
    await (_db.update(_db.threadRankSettings)..where((t) => t.id.equals(1)))
        .write(
      ThreadRankSettingsCompanion(
        useActualTime: Value(value),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }
}

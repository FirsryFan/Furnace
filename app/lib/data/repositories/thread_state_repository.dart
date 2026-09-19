import 'package:drift/drift.dart';

import '../database/database.dart';

/// Repository for the single-row Thread status bar state (spec 1.1.3):
/// current energy level and main goal. Row id is always 1.
class ThreadStateRepository {
  ThreadStateRepository(this._db);

  final AppDatabase _db;

  Future<ThreadState?> getState() async {
    final rows = await _db.select(_db.threadStates).get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<ThreadState> ensureState() async {
    final existing = await getState();
    if (existing != null) {
      return existing;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.threadStates).insert(
          ThreadStatesCompanion.insert(createdAt: now),
        );
    return (await _db.select(_db.threadStates)..where((t) => t.id.equals(1)))
        .getSingle();
  }

  /// Updates the status bar state and stamps [updatedAt] (used by the
  /// >2h staleness prompt in the sort flow).
  Future<ThreadState> updateState({
    int? energy,
    String? goalText,
    String? goalNodeId,
    String? goalPath,
    bool clearEnergy = false,
    bool clearGoal = false,
    DateTime? updatedAt,
  }) async {
    final state = await ensureState();
    final now = updatedAt ?? DateTime.now();
    await (_db.update(_db.threadStates)..where((t) => t.id.equals(1))).write(
      ThreadStatesCompanion(
        energy: clearEnergy
            ? const Value<int?>(null)
            : (energy == null ? const Value.absent() : Value(energy)),
        goalText: clearGoal
            ? const Value<String?>(null)
            : (goalText == null ? const Value.absent() : Value(goalText)),
        goalNodeId: clearGoal
            ? const Value<String?>(null)
            : (goalNodeId == null
                ? const Value.absent()
                : Value(goalNodeId)),
        goalPath: clearGoal
            ? const Value<String?>(null)
            : (goalPath == null ? const Value.absent() : Value(goalPath)),
        updatedAt: Value(now.millisecondsSinceEpoch),
      ),
    );
    return state;
  }

  /// Whether the persisted state is stale (> [staleAfter] since last update).
  /// Returns true when there is no recorded state yet.
  Future<bool> isStale(Duration staleAfter) async {
    final state = await getState();
    final updatedAt = state?.updatedAt;
    if (updatedAt == null) {
      return true;
    }
    final age = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(updatedAt));
    return age > staleAfter;
  }
}

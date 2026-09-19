import 'package:drift/drift.dart';

import '../database/database.dart';
import '../ids.dart';

/// Repository for time blocks.
class TimeBlockRepository {
  TimeBlockRepository(this._db);

  final AppDatabase _db;

  Future<TimeBlock> createTimeBlock({
    required String title,
    required int startAt,
    required int endAt,
    String? repeatRule,
    bool available = true,
    String? energy,
    String? suitableFor,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _newId('tb');
    await _db.into(_db.timeBlocks).insert(
          TimeBlocksCompanion.insert(
            id: id,
            title: title,
            startAt: startAt,
            endAt: endAt,
            repeatRule: Value(repeatRule),
            available: Value(available),
            energy: Value(energy),
            suitableFor: Value(suitableFor),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (await _db.select(_db.timeBlocks)..where((t) => t.id.equals(id)))
        .getSingle();
  }

  Future<List<TimeBlock>> getTimeBlocks({bool onlyAvailable = false}) {
    final query = _db.select(_db.timeBlocks);
    if (onlyAvailable) {
      query.where((t) => t.available.equals(true));
    }
    query.orderBy([(t) => OrderingTerm.asc(t.startAt)]);
    return query.get();
  }

  Future<void> updateTimeBlock(
    String id, {
    String? title,
    int? startAt,
    int? endAt,
    String? repeatRule,
    bool? available,
    String? energy,
    String? suitableFor,
  }) async {
    await (_db.update(_db.timeBlocks)..where((t) => t.id.equals(id))).write(
      TimeBlocksCompanion(
        title: title == null ? const Value.absent() : Value(title),
        startAt: startAt == null ? const Value.absent() : Value(startAt),
        endAt: endAt == null ? const Value.absent() : Value(endAt),
        repeatRule:
            repeatRule == null ? const Value.absent() : Value(repeatRule),
        available:
            available == null ? const Value.absent() : Value(available),
        energy: energy == null ? const Value.absent() : Value(energy),
        suitableFor:
            suitableFor == null ? const Value.absent() : Value(suitableFor),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  Future<void> deleteTimeBlock(String id) async {
    await _db.transaction(() async {
      await (_db.delete(_db.taskTimeBlocks)
            ..where((t) => t.timeBlockId.equals(id)))
          .go();
      await (_db.delete(_db.timeBlocks)..where((t) => t.id.equals(id))).go();
    });
  }

  String _newId(String prefix) => Ids.next(prefix);
}

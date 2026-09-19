import 'package:drift/drift.dart';

import '../database/database.dart';
import '../ids.dart';

/// Repository for the daily study ledger (blueprint 4.4, user annotation 19).
///
/// The review screen itself stays free of statistics so the user can reach
/// flow; every "this went wrong" / "this got lifted" line lands here instead,
/// keyed by local calendar day so the insight screen can group by day without
/// any timezone guesswork.
class DiffusionLogRepository {
  DiffusionLogRepository(this._db);

  final AppDatabase _db;

  /// Appends one ledger line.
  Future<void> append({
    required String ownerType,
    required String kind,
    String? ownerId,
    String? ownerTitle,
    String? knowledgePointId,
    String? knowledgePointTitle,
    int? distance,
    double? factor,
    String? detail,
    required DateTime occurredAt,
  }) async {
    await _db.transaction(() async {
      await _append(
        ownerType: ownerType,
        kind: kind,
        ownerId: ownerId,
        ownerTitle: ownerTitle,
        knowledgePointId: knowledgePointId,
        knowledgePointTitle: knowledgePointTitle,
        distance: distance,
        factor: factor,
        detail: detail,
        occurredAt: occurredAt,
      );
    });
  }

  /// Appends several lines in one transaction (one wrong answer plus its
  /// diffusion boosts form a single event).
  Future<void> appendAll(List<DiffusionLogDraft> drafts) async {
    if (drafts.isEmpty) {
      return;
    }
    await _db.transaction(() async {
      for (final draft in drafts) {
        await _append(
          ownerType: draft.ownerType,
          kind: draft.kind,
          ownerId: draft.ownerId,
          ownerTitle: draft.ownerTitle,
          knowledgePointId: draft.knowledgePointId,
          knowledgePointTitle: draft.knowledgePointTitle,
          distance: draft.distance,
          factor: draft.factor,
          detail: draft.detail,
          occurredAt: draft.occurredAt,
        );
      }
    });
  }

  /// Raw insert; the caller owns the transaction (nesting transactions is not
  /// supported by Drift).
  Future<void> _append({
    required String ownerType,
    required String kind,
    required DateTime occurredAt,
    String? ownerId,
    String? ownerTitle,
    String? knowledgePointId,
    String? knowledgePointTitle,
    int? distance,
    double? factor,
    String? detail,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.diffusionLogs).insert(
          DiffusionLogsCompanion.insert(
            id: _newId(),
            ownerType: ownerType,
            kind: kind,
            ownerId: Value(ownerId),
            ownerTitle: Value(ownerTitle),
            knowledgePointId: Value(knowledgePointId),
            knowledgePointTitle: Value(knowledgePointTitle),
            distance: Value(distance),
            factor: Value(factor),
            detail: Value(detail),
            dayKey: dayKeyOf(occurredAt),
            occurredAt: occurredAt.millisecondsSinceEpoch,
            createdAt: now,
          ),
        );
  }

  /// Every line of one local calendar day, newest first.
  Future<List<DiffusionLog>> getForDay(DateTime day) {
    return (_db.select(_db.diffusionLogs)
          ..where((d) => d.dayKey.equals(dayKeyOf(day)))
          ..orderBy([
            (d) => OrderingTerm.desc(d.occurredAt),
            (d) => OrderingTerm.desc(d.id),
          ]))
        .get();
  }

  /// The most recent [limit] local calendar days that have any ledger lines,
  /// newest first (used for a day picker).
  Future<List<String>> recentDayKeys({int limit = 30}) async {
    final rows = await (_db.selectOnly(_db.diffusionLogs, distinct: true)
          ..addColumns([_db.diffusionLogs.dayKey])
          ..orderBy([OrderingTerm.desc(_db.diffusionLogs.dayKey)])
          ..limit(limit))
        .get();
    return [
      for (final row in rows)
        if (row.read(_db.diffusionLogs.dayKey) != null)
          row.read(_db.diffusionLogs.dayKey)!,
    ];
  }

  /// Aggregated "what went wrong" counters for one day.
  Future<DiffusionDaySummary> summarizeDay(DateTime day) async {
    final rows = await getForDay(day);
    return DiffusionDaySummary(
      dayKey: dayKeyOf(day),
      wrongCount: rows.where((r) => r.kind == 'wrong').length,
      boostCount: rows.where((r) => r.kind == 'boost').length,
      releasedCount: rows.where((r) => r.kind == 'release').length,
      entries: rows,
    );
  }

  Future<void> deleteForDay(DateTime day) async {
    await (_db.delete(_db.diffusionLogs)
          ..where((d) => d.dayKey.equals(dayKeyOf(day))))
        .go();
  }

  /// Local calendar day key `yyyy-MM-dd`.
  static String dayKeyOf(DateTime moment) {
    final local = moment.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  String _newId() => Ids.next('dl');
}

/// One ledger line to append.
class DiffusionLogDraft {
  const DiffusionLogDraft({
    required this.ownerType,
    required this.kind,
    required this.occurredAt,
    this.ownerId,
    this.ownerTitle,
    this.knowledgePointId,
    this.knowledgePointTitle,
    this.distance,
    this.factor,
    this.detail,
  });

  final String ownerType;
  final String kind;
  final DateTime occurredAt;
  final String? ownerId;
  final String? ownerTitle;
  final String? knowledgePointId;
  final String? knowledgePointTitle;
  final int? distance;
  final double? factor;
  final String? detail;
}

/// Aggregated counters plus the raw lines for one day.
class DiffusionDaySummary {
  const DiffusionDaySummary({
    required this.dayKey,
    required this.wrongCount,
    required this.boostCount,
    required this.releasedCount,
    required this.entries,
  });

  final String dayKey;
  final int wrongCount;
  final int boostCount;
  final int releasedCount;
  final List<DiffusionLog> entries;

  bool get isEmpty => entries.isEmpty;
}

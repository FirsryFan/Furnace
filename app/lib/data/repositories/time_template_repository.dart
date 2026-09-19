import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/database.dart';
import '../ids.dart';
import 'time_block_repository.dart';

/// One block inside a day/week template.
class TemplateBlock {
  const TemplateBlock({
    required this.title,
    required this.startMinutes,
    required this.endMinutes,
    this.available = true,
    this.repeatRule,
    this.dows = const [],
    this.monthDay,
    this.colorSlot = 0,
  });

  final String title;

  /// Minutes since local midnight, so templates are timezone-independent.
  final int startMinutes;
  final int endMinutes;
  final bool available;

  /// Optional repeat rule JSON applied to the created block.
  final String? repeatRule;

  /// Weekdays (1=Mon..7=Sun) this block belongs to; empty = every day.
  final List<int> dows;

  /// Day of month (1..31) this block belongs to; null = any.
  final int? monthDay;

  /// Colour slot index; the UI maps it onto a pastel palette so blocks are
  /// translucent coloured cards rather than a uniform bar.
  final int colorSlot;

  bool appliesTo(DateTime day) {
    if (monthDay != null && day.day != monthDay) {
      return false;
    }
    if (dows.isEmpty) {
      return true;
    }
    return dows.contains(day.weekday);
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'start': startMinutes,
        'end': endMinutes,
        'available': available,
        if (repeatRule != null) 'repeatRule': repeatRule,
        if (dows.isNotEmpty) 'dows': dows,
        if (monthDay != null) 'monthDay': monthDay,
        'color': colorSlot,
      };

  factory TemplateBlock.fromJson(Map<String, dynamic> json) => TemplateBlock(
        title: json['title'] as String? ?? '',
        startMinutes: (json['start'] as num?)?.toInt() ?? 0,
        endMinutes: (json['end'] as num?)?.toInt() ?? 60,
        available: json['available'] as bool? ?? true,
        repeatRule: json['repeatRule'] as String?,
        dows: [
          for (final value in (json['dows'] as List<dynamic>? ?? const []))
            (value as num).toInt(),
        ],
        monthDay: (json['monthDay'] as num?)?.toInt(),
        colorSlot: (json['color'] as num?)?.toInt() ?? 0,
      );
}

/// Schedule templates: a whole week or a single day of blocks laid down in one
/// action (user feedback item 3).
class TimeTemplateRepository {
  TimeTemplateRepository(this._db);

  final AppDatabase _db;

  Future<List<TimeTemplate>> getTemplates({String? kind}) {
    final query = _db.select(_db.timeTemplates);
    if (kind != null) {
      query.where((t) => t.kind.equals(kind));
    }
    query.orderBy([
      (t) => OrderingTerm.asc(t.sortOrder),
      (t) => OrderingTerm.asc(t.createdAt),
    ]);
    return query.get();
  }

  Future<TimeTemplate?> getById(String id) {
    return (_db.select(_db.timeTemplates)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  List<TemplateBlock> blocksOf(TimeTemplate template) {
    try {
      final map = jsonDecode(template.payload) as Map<String, dynamic>;
      return [
        for (final raw in (map['blocks'] as List<dynamic>? ?? const []))
          TemplateBlock.fromJson(raw as Map<String, dynamic>),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<TimeTemplate> save({
    String? id,
    required String name,
    required String kind,
    required List<TemplateBlock> blocks,
    int sortOrder = 0,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final payload = jsonEncode({
      'blocks': [for (final block in blocks) block.toJson()],
    });
    final existing = id == null ? null : await getById(id);
    if (existing != null) {
      await (_db.update(_db.timeTemplates)..where((t) => t.id.equals(existing.id)))
          .write(
        TimeTemplatesCompanion(
          name: Value(name),
          kind: Value(kind),
          payload: Value(payload),
          sortOrder: Value(sortOrder),
          updatedAt: Value(now),
        ),
      );
      return (await getById(existing.id))!;
    }
    final newId = id ?? Ids.next('tpl-time');
    await _db.into(_db.timeTemplates).insert(
          TimeTemplatesCompanion.insert(
            id: newId,
            name: name,
            kind: kind,
            payload: payload,
            sortOrder: Value(sortOrder),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (await getById(newId))!;
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.timeTemplates)..where((t) => t.id.equals(id))).go();
  }

  /// Materialises [template] onto [days]: every block that applies to a day
  /// becomes a real `TimeBlock` on that date.
  ///
  /// Blocks are placed exactly as the template says, so deliberately
  /// overlapping blocks are allowed (user feedback 3: no overlap avoidance).
  /// Returns the number of blocks created.
  Future<int> applyToDays({
    required TimeTemplate template,
    required List<DateTime> days,
    TimeBlockRepository? writer,
  }) async {
    final repo = writer ?? TimeBlockRepository(_db);
    final blocks = blocksOf(template);
    if (blocks.isEmpty || days.isEmpty) {
      return 0;
    }
    var created = 0;
    for (final day in days) {
      final base = DateTime(day.year, day.month, day.day);
      for (final block in blocks) {
        if (!block.appliesTo(day)) {
          continue;
        }
        final start = base.add(Duration(minutes: block.startMinutes));
        var end = base.add(Duration(minutes: block.endMinutes));
        if (!end.isAfter(start)) {
          // A block that crosses midnight: keep it valid rather than silently
          // creating a zero/negative span.
          end = start.add(const Duration(minutes: 30));
        }
        await repo.createTimeBlock(
          title: block.title,
          startAt: start.millisecondsSinceEpoch,
          endAt: end.millisecondsSinceEpoch,
          available: block.available,
          repeatRule: block.repeatRule,
        );
        created++;
      }
    }
    return created;
  }
}

/// Single-row Time module view preferences.
class TimeViewRepository {
  TimeViewRepository(this._db);

  final AppDatabase _db;

  Future<TimeViewSetting?> get() async {
    final rows = await _db.select(_db.timeViewSettings).get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<TimeViewSetting> ensure() async {
    final existing = await get();
    if (existing != null) {
      return existing;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.timeViewSettings).insert(
          TimeViewSettingsCompanion.insert(createdAt: now),
        );
    return (_db.select(_db.timeViewSettings)..where((t) => t.id.equals(1)))
        .getSingle();
  }

  Future<void> update({
    int? timelineSpanDays,
    double? timelinePxPerDay,
    bool? timelineCollapsed,
    int? minutesPerRow,
    bool? chosen,
  }) async {
    await ensure();
    await (_db.update(_db.timeViewSettings)..where((t) => t.id.equals(1))).write(
      TimeViewSettingsCompanion(
        timelineSpanDays: timelineSpanDays == null
            ? const Value.absent()
            : Value(timelineSpanDays),
        timelinePxPerDay: timelinePxPerDay == null
            ? const Value.absent()
            : Value(timelinePxPerDay),
        timelineCollapsed: timelineCollapsed == null
            ? const Value.absent()
            : Value(timelineCollapsed),
        minutesPerRow:
            minutesPerRow == null ? const Value.absent() : Value(minutesPerRow),
        minutesPerRowChosen:
            chosen == null ? const Value.absent() : Value(chosen),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }
}

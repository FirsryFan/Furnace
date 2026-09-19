import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowflow/data/database/database.dart';
import 'package:knowflow/data/repositories/time_block_repository.dart';
import 'package:knowflow/data/repositories/time_template_repository.dart';

/// Day/week templates and the Time view preferences (user feedback item 3).
void main() {
  late AppDatabase db;
  late TimeTemplateRepository templates;
  late TimeBlockRepository blocks;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    templates = TimeTemplateRepository(db);
    blocks = TimeBlockRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('templates round-trip', () {
    test('saving and reading back keeps every block field', () async {
      await templates.save(
        name: '工作日',
        kind: 'week',
        blocks: const [
          TemplateBlock(
            title: '早读',
            startMinutes: 7 * 60,
            endMinutes: 7 * 60 + 40,
            available: false,
            dows: [1, 2, 3, 4, 5],
            colorSlot: 3,
          ),
          TemplateBlock(
            title: '深度时间',
            startMinutes: 20 * 60,
            endMinutes: 21 * 60 + 30,
            colorSlot: 5,
          ),
        ],
      );

      final all = await templates.getTemplates();
      expect(all, hasLength(1));
      final parsed = templates.blocksOf(all.single);
      expect(parsed, hasLength(2));
      expect(parsed.first.title, '早读');
      expect(parsed.first.startMinutes, 420);
      expect(parsed.first.endMinutes, 460);
      expect(parsed.first.available, isFalse);
      expect(parsed.first.dows, [1, 2, 3, 4, 5]);
      expect(parsed.first.colorSlot, 3);
      expect(parsed.last.dows, isEmpty);
    });

    test('saving with an existing id updates instead of duplicating', () async {
      final first = await templates.save(
        name: 'A',
        kind: 'day',
        blocks: const [
          TemplateBlock(title: 'x', startMinutes: 60, endMinutes: 120),
        ],
      );
      await templates.save(
        id: first.id,
        name: 'B',
        kind: 'day',
        blocks: const [
          TemplateBlock(title: 'y', startMinutes: 120, endMinutes: 180),
        ],
      );
      final all = await templates.getTemplates();
      expect(all, hasLength(1));
      expect(all.single.name, 'B');
      expect(templates.blocksOf(all.single).single.title, 'y');
    });

    test('kind filters the list', () async {
      await templates.save(
        name: 'd',
        kind: 'day',
        blocks: const [
          TemplateBlock(title: 'x', startMinutes: 0, endMinutes: 30),
        ],
      );
      await templates.save(
        name: 'w',
        kind: 'week',
        blocks: const [
          TemplateBlock(title: 'y', startMinutes: 0, endMinutes: 30),
        ],
      );
      expect(await templates.getTemplates(kind: 'day'), hasLength(1));
      expect(await templates.getTemplates(kind: 'week'), hasLength(1));
      expect(await templates.getTemplates(), hasLength(2));
    });
  });

  group('applying a template', () {
    test('materialises blocks on every requested day', () async {
      final template = await templates.save(
        name: '全天',
        kind: 'day',
        blocks: const [
          TemplateBlock(
              title: '上午课', startMinutes: 8 * 60, endMinutes: 12 * 60, available: false),
          TemplateBlock(title: '自习', startMinutes: 19 * 60, endMinutes: 21 * 60),
        ],
      );

      final monday = DateTime(2026, 9, 14);
      final week = [for (var i = 0; i < 5; i++) monday.add(Duration(days: i))];
      final created = await templates.applyToDays(
        template: template,
        days: week,
        writer: blocks,
      );
      expect(created, 10);

      final stored = await blocks.getTimeBlocks();
      expect(stored, hasLength(10));
      final firstStart = DateTime.fromMillisecondsSinceEpoch(stored.first.startAt);
      expect(firstStart.hour, greaterThanOrEqualTo(0));
      // Blocks land exactly on the requested dates.
      final dates = {
        for (final block in stored)
          DateTime.fromMillisecondsSinceEpoch(block.startAt).day,
      };
      expect(dates, {14, 15, 16, 17, 18});
    });

    test('dow filters keep a day template off the weekend', () async {
      final weekdayOnly = await templates.save(
        name: '工作日',
        kind: 'week',
        blocks: const [
          TemplateBlock(
            title: '上课',
            startMinutes: 8 * 60,
            endMinutes: 12 * 60,
            available: false,
            dows: [1, 2, 3, 4, 5],
          ),
        ],
      );
      final monday = DateTime(2026, 9, 14);
      final week = [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];
      final created = await templates.applyToDays(
        template: weekdayOnly,
        days: week,
        writer: blocks,
      );
      expect(created, 5, reason: 'Saturday and Sunday must be skipped');
      final stored = await blocks.getTimeBlocks();
      expect(
        stored.map((b) => DateTime.fromMillisecondsSinceEpoch(b.startAt).weekday),
        everyElement(lessThanOrEqualTo(5)),
      );
    });

    test('monthDay targets one date of the month', () async {
      final monthly = await templates.save(
        name: '月会',
        kind: 'day',
        blocks: const [
          TemplateBlock(
            title: '月会',
            startMinutes: 18 * 60,
            endMinutes: 19 * 60,
            monthDay: 15,
          ),
        ],
      );
      final created = await templates.applyToDays(
        template: monthly,
        days: [DateTime(2026, 9, 14), DateTime(2026, 9, 15)],
        writer: blocks,
      );
      expect(created, 1);
    });

    test('deliberately overlapping blocks are both created', () async {
      // The user explicitly does not want overlap avoidance.
      final overlapping = await templates.save(
        name: '重叠',
        kind: 'day',
        blocks: const [
          TemplateBlock(title: 'A', startMinutes: 9 * 60, endMinutes: 11 * 60),
          TemplateBlock(title: 'B', startMinutes: 10 * 60, endMinutes: 12 * 60),
        ],
      );
      final created = await templates.applyToDays(
        template: overlapping,
        days: [DateTime(2026, 9, 14)],
        writer: blocks,
      );
      expect(created, 2);
      final stored = await blocks.getTimeBlocks();
      expect(stored, hasLength(2));
      final spans = stored
          .map((b) => (
                start: DateTime.fromMillisecondsSinceEpoch(b.startAt),
                end: DateTime.fromMillisecondsSinceEpoch(b.endAt),
              ))
          .toList();
      expect(
        spans.any((s) => s.start.hour == 10 && s.end.hour == 12),
        isTrue,
        reason: 'the overlapping block must survive unchanged',
      );
    });

    test('a template with no blocks creates nothing', () async {
      final empty = await templates.save(
        name: '空',
        kind: 'day',
        blocks: const [],
      );
      expect(
        await templates.applyToDays(
            template: empty, days: [DateTime(2026, 9, 14)], writer: blocks),
        0,
      );
    });
  });

  group('view preferences', () {
    test('defaults are the documented ones and updates persist', () async {
      final repo = TimeViewRepository(db);
      final initial = await repo.ensure();
      expect(initial.timelineSpanDays, 730);
      expect(initial.timelinePxPerDay, 6);
      expect(initial.timelineCollapsed, isFalse);
      // 30, not 60: a whole-hour grid hides half-hour boundaries
      // (user: 不要默认按小时来分).
      expect(initial.minutesPerRow, 30);
      expect(initial.minutesPerRowChosen, isFalse);

      await repo.update(
        timelineSpanDays: 1825,
        timelinePxPerDay: 12,
        timelineCollapsed: true,
        minutesPerRow: 15,
        chosen: true,
      );
      final updated = await repo.ensure();
      expect(updated.timelineSpanDays, 1825);
      expect(updated.timelinePxPerDay, 12);
      expect(updated.timelineCollapsed, isTrue);
      expect(updated.minutesPerRow, 15);
      expect(updated.minutesPerRowChosen, isTrue,
          reason: 'a deliberate pick is recorded so later default changes '
              'never override it');
      expect(updated.updatedAt, isNotNull);

      // ensure() never creates a second row.
      final rows = await db.select(db.timeViewSettings).get();
      expect(rows, hasLength(1));
    });
  });
}

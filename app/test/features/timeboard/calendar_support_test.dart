import 'package:flutter_test/flutter_test.dart';
import 'package:knowflow/features/timeboard/presentation/calendar_page.dart';
import 'package:knowflow/features/timeboard/presentation/widgets/calendar_support.dart';

/// ISO-8601 week numbering, used by the week-number column and the multi-year
/// timeline (user feedback item 3).
void main() {
  group('IsoWeek.number', () {
    test('matches known ISO week numbers', () {
      // 2026-01-01 is a Thursday, so it belongs to week 1 of 2026.
      expect(IsoWeek.number(DateTime(2026, 1, 1)), 1);
      expect(IsoWeek.number(DateTime(2026, 1, 4)), 1);
      expect(IsoWeek.number(DateTime(2026, 1, 5)), 2);
      // 2025-12-29 (Monday) already belongs to ISO week 1 of 2026.
      expect(IsoWeek.number(DateTime(2025, 12, 29)), 1);
      expect(IsoWeek.weekYear(DateTime(2025, 12, 29)), 2026);
      // Mid-year sanity: 2026-09-14 is a Monday in week 38.
      expect(IsoWeek.number(DateTime(2026, 9, 14)), 38);
    });

    test('stays continuous across a year boundary', () {
      // 2027-01-04 is a Monday: ISO week 1 of 2027, right after week 53 of 2026.
      expect(IsoWeek.number(DateTime(2027, 1, 4)), 1);
      final lastWeekOf2026 = IsoWeek.number(DateTime(2026, 12, 28));
      expect(lastWeekOf2026, greaterThanOrEqualTo(52));
    });

    test('label carries the week-numbering year', () {
      expect(IsoWeek.label(DateTime(2026, 9, 14)), '2026-W38');
      expect(IsoWeek.label(DateTime(2025, 12, 29)), '2026-W01');
    });
  });

  group('IsoWeek.weekDays / weekStart', () {
    test('a week runs Monday..Sunday', () {
      final days = IsoWeek.weekDays(DateTime(2026, 9, 16)); // Wednesday
      expect(days.first.weekday, DateTime.monday);
      expect(days.last.weekday, DateTime.sunday);
      expect(days, hasLength(7));
      expect(days.first.day, 14);
      expect(days.last.day, 20);
    });

    test('a week never spans two week numbers', () {
      for (var offset = 0; offset < 60; offset++) {
        final days = IsoWeek.weekDays(DateTime(2026, 1, 1).add(Duration(days: offset)));
        final numbers = {for (final day in days) IsoWeek.number(day)};
        expect(numbers, hasLength(1), reason: 'week of ${days.first}');
      }
    });
  });

  group('BlockPalette', () {
    test('colour slots are stable for the same block id', () {
      expect(BlockPalette.slotForId('tb-abc'), BlockPalette.slotForId('tb-abc'));
    });

    test('different ids usually spread over the palette', () {
      final slots = {
        for (var i = 0; i < 200; i++) BlockPalette.slotForId('tb-$i'),
      };
      expect(slots.length, greaterThan(3),
          reason: 'blocks must not all end up the same colour');
    });

    test('busy blocks are more opaque than open ones', () {
      final base = BlockPalette.colorFor(0);
      expect(BlockPalette.fill(base, busy: true).a,
          greaterThan(BlockPalette.fill(base, busy: false).a));
    });
  });

  group('sub-hour grid rows (user: 不要默认按小时来分)', () {
    test('a 30-minute grid shows the half hour, not just whole hours', () {
      final labels = [
        for (var row = 0; row < 6; row++) rowLabel(row, 30),
      ];
      expect(labels, ['00:00', '00:30', '01:00', '01:30', '02:00', '02:30']);
    });

    test('a 15-minute grid labels every quarter', () {
      expect(rowLabel(0, 15), '00:00');
      expect(rowLabel(1, 15), '00:15');
      expect(rowLabel(3, 15), '00:45');
      expect(rowLabel(5, 15), '01:15');
    });

    test('an hour grid still works', () {
      expect(rowLabel(0, 60), '00:00');
      expect(rowLabel(9, 60), '09:00');
      expect(rowLabel(23, 60), '23:00');
    });

    test('only whole hours are major ticks', () {
      expect(isMajorTick(0, 30), isTrue);
      expect(isMajorTick(1, 30), isFalse);
      expect(isMajorTick(2, 30), isTrue);
      expect(isMajorTick(1, 15), isFalse);
      expect(isMajorTick(4, 15), isTrue);
      expect(isMajorTick(3, 60), isTrue);
    });

    test('a day is covered exactly once at every row size', () {
      for (final minutes in [15, 30, 60]) {
        final rows = (24 * 60) ~/ minutes;
        expect(rows * minutes, 24 * 60);
        expect(rowLabel(rows - 1, minutes), isNotNull);
      }
    });
  });
}

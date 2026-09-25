import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/scheduling/time_window_engine.dart';

ScheduleBlock block(
  String id,
  int startHour,
  int endHour, {
  bool available = false,
  String? repeatRule,
  DateTime? day,
}) {
  final base = day ?? DateTime(2026, 9, 7);
  return ScheduleBlock(
    id: id,
    title: id,
    startAt: DateTime(base.year, base.month, base.day, startHour),
    endAt: DateTime(base.year, base.month, base.day, endHour),
    available: available,
    repeatRule: repeatRule,
  );
}

void main() {
  final monday = DateTime(2026, 9, 7); // Monday
  final wednesday = DateTime(2026, 9, 9);

  group('TimeWindowEngine expansion', () {
    test('single block clips into window', () {
      final b = block('class', 8, 10, day: monday);
      final parts = TimeWindowEngine.expand(
        block: b,
        windowStart: DateTime(2026, 9, 7, 9),
        windowEnd: DateTime(2026, 9, 7, 11),
      );
      expect(parts, hasLength(1));
      expect(parts.single.start.hour, 9);
      expect(parts.single.end.hour, 10);
    });

    test('weekly rule fires only on listed weekdays', () {
      final b = block('lecture', 14, 16,
          repeatRule: '{"type":"weekly","dows":[1,3]}');
      final parts = TimeWindowEngine.expand(
        block: b,
        windowStart: monday,
        windowEnd: wednesday.add(const Duration(days: 1)),
      );
      expect(parts, hasLength(2)); // Monday and Wednesday
    });

    test('daily rule fires every day', () {
      final b = block('gym', 7, 8, repeatRule: '{"type":"daily"}');
      final parts = TimeWindowEngine.expand(
        block: b,
        windowStart: monday,
        windowEnd: monday.add(const Duration(days: 3)),
      );
      expect(parts, hasLength(3));
    });

    test('malformed rule treated as single occurrence', () {
      final b = block('weird', 8, 9, repeatRule: 'not json');
      final parts = TimeWindowEngine.expand(
        block: b,
        windowStart: monday,
        windowEnd: monday.add(const Duration(days: 2)),
      );
      expect(parts, hasLength(1));
    });
  });

  group('occupancy and free windows', () {
    test('busy minutes only counts unavailable blocks', () {
      final blocks = [
        block('busy', 8, 10, available: false, day: monday),
        block('open', 10, 12, available: true, day: monday),
      ];
      final minutes = TimeWindowEngine.busyMinutes(
        blocks: blocks,
        windowStart: monday,
        windowEnd: monday.add(const Duration(hours: 24)),
      );
      expect(minutes, 120);
    });

    test('next free window skips busy hard blocks', () {
      final blocks = [
        block('busy1', 8, 10, available: false, day: monday),
        block('busy2', 12, 14, available: false, day: monday),
      ];
      final window = TimeWindowEngine.nextFreeWindow(
        blocks: blocks,
        from: DateTime(2026, 9, 7, 7),
        minDuration: const Duration(minutes: 60),
      );
      expect(window, isNotNull);
      expect(window!.$1.hour, 7);
    });

    test('no window when fully busy within horizon', () {
      final dayStart = DateTime(2026, 9, 7);
      final busy = ScheduleBlock(
        id: 'all-day',
        title: 'busy',
        startAt: dayStart,
        endAt: dayStart.add(const Duration(hours: 23, minutes: 59)),
        available: false,
        repeatRule: '{"type":"daily"}',
      );
      final window = TimeWindowEngine.nextFreeWindow(
        blocks: [busy],
        from: dayStart,
        minDuration: const Duration(minutes: 30),
        maxWindow: const Duration(days: 2),
      );
      expect(window, isNull);
    });

    test('isBusyAt detects conflicts (spec 1.2.3)', () {
      final blocks = [block('class', 8, 10, available: false, day: monday)];
      expect(
        TimeWindowEngine.isBusyAt(
            blocks: blocks, moment: DateTime(2026, 9, 7, 9, 30)),
        isTrue,
      );
      expect(
        TimeWindowEngine.isBusyAt(
            blocks: blocks, moment: DateTime(2026, 9, 7, 12)),
        isFalse,
      );
    });
  });
}

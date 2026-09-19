/// Pure time-window utilities for the Thread side of the loop.
///
/// Semantics (GAP D6): a schedule block with `available == false` is a busy
/// hard block (class/meeting/commute) and occupies time; `available == true`
/// blocks are open soft blocks used only for soft matching and never count
/// as occupancy. Repeat rules are JSON:
///   null | {"type":"none"} | {"type":"daily"} | {"type":"weekly","dows":[1..7]}
library;

import 'dart:convert';

/// A busy interval already expanded to a concrete time span.
class BusyInterval {
  const BusyInterval({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  Duration get duration => end.difference(start);
}

/// A schedule block occurrence candidate (raw row shape, no DB dependency).
class ScheduleBlock {
  const ScheduleBlock({
    required this.id,
    required this.title,
    required this.startAt,
    required this.endAt,
    required this.available,
    this.repeatRule,
  });

  final String id;
  final String title;
  final DateTime startAt;
  final DateTime endAt;
  final bool available;

  /// JSON repeat rule; null / {"type":"none"} = single occurrence.
  final String? repeatRule;

  Duration get duration => endAt.difference(startAt);
}

class RepeatRule {
  const RepeatRule({required this.type, this.dows = const []});

  factory RepeatRule.fromJson(String? json) {
    if (json == null || json.isEmpty) {
      return const RepeatRule(type: 'none');
    }
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final type = map['type'] as String? ?? 'none';
      final dows = (map['dows'] as List<dynamic>? ?? const [])
          .map((e) => e as int)
          .toList();
      return RepeatRule(type: type, dows: dows);
    } catch (_) {
      return const RepeatRule(type: 'none');
    }
  }

  final String type; // none | daily | weekly
  final List<int> dows; // 1=Monday .. 7=Sunday

  bool get isRecurring => type != 'none';

  /// True when this rule fires on [day]'s weekday (weekly rules).
  bool matches(DateTime day) {
    if (type == 'none' || type == 'daily') {
      return true;
    }
    final iso = day.weekday; // 1=Monday..7=Sunday
    return dows.contains(iso);
  }
}

abstract final class TimeWindowEngine {
  /// Expands all occurrences of [block] that overlap the window
  /// [windowStart, windowEnd) (busy or open - caller filters).
  static List<BusyInterval> expand({
    required ScheduleBlock block,
    required DateTime windowStart,
    required DateTime windowEnd,
    Duration maxWindow = const Duration(days: 365),
  }) {
    final rule = RepeatRule.fromJson(block.repeatRule);
    final results = <BusyInterval>[];
    if (!rule.isRecurring) {
      final start = block.startAt.isBefore(windowStart)
          ? windowStart
          : block.startAt;
      final end = block.endAt.isAfter(windowEnd) ? windowEnd : block.endAt;
      if (start.isBefore(end)) {
        results.add(BusyInterval(start: start, end: end));
      }
      return results;
    }

    // Recurring: iterate day by day from the first candidate day.
    final dayStart = DateTime(windowStart.year, windowStart.month,
        windowStart.day); // local wall-clock day grid
    final blockDuration = block.endAt.difference(block.startAt);
    final maxDay = windowEnd.isAfter(dayStart.add(maxWindow))
        ? dayStart.add(maxWindow)
        : windowEnd;
    for (var day = dayStart;
        !day.isAfter(maxDay);
        day = day.add(const Duration(days: 1))) {
      if (!rule.matches(day)) {
        continue;
      }
      final occurrenceStart = DateTime(
        day.year,
        day.month,
        day.day,
        block.startAt.hour,
        block.startAt.minute,
      );
      final occurrenceEnd = occurrenceStart.add(blockDuration);
      final start =
          occurrenceStart.isBefore(windowStart) ? windowStart : occurrenceStart;
      final end = occurrenceEnd.isAfter(windowEnd) ? windowEnd : occurrenceEnd;
      if (start.isBefore(end)) {
        results.add(BusyInterval(start: start, end: end));
      }
    }
    return results;
  }

  /// Total busy (available == false) occupancy in minutes inside
  /// [windowStart, windowEnd).
  static int busyMinutes({
    required List<ScheduleBlock> blocks,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) {
    var total = 0;
    for (final block in blocks) {
      if (block.available) {
        continue;
      }
      final parts =
          expand(block: block, windowStart: windowStart, windowEnd: windowEnd);
      for (final part in parts) {
        total += part.duration.inMinutes;
      }
    }
    return total;
  }

  /// Busy hard intervals inside the window (for conflict warnings etc.).
  static List<BusyInterval> busyIntervals({
    required List<ScheduleBlock> blocks,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) {
    final results = <BusyInterval>[];
    for (final block in blocks) {
      if (block.available) {
        continue;
      }
      results.addAll(
          expand(block: block, windowStart: windowStart, windowEnd: windowEnd));
    }
    results.sort((a, b) => a.start.compareTo(b.start));
    return results;
  }

  /// The first free interval of at least [minDuration] starting at or after
  /// [from] and ending no later than [horizon]. Free = not inside any busy
  /// hard block (open blocks do not occupy).
  static (DateTime, DateTime)? nextFreeWindow({
    required List<ScheduleBlock> blocks,
    required DateTime from,
    required Duration minDuration,
    DateTime? horizon,
    Duration maxWindow = const Duration(days: 7),
  }) {
    final windowEnd = horizon ?? from.add(maxWindow);
    final busy = busyIntervals(
        blocks: blocks, windowStart: from, windowEnd: windowEnd);
    var cursor = from;
    for (final interval in busy) {
      if (interval.start.isAfter(cursor)) {
        final free = interval.start.difference(cursor);
        if (free >= minDuration) {
          return (cursor, cursor.add(minDuration));
        }
      }
      if (interval.end.isAfter(cursor)) {
        cursor = interval.end;
      }
    }
    if (windowEnd.difference(cursor) >= minDuration) {
      return (cursor, cursor.add(minDuration));
    }
    return null;
  }

  /// Whether [moment] falls inside any busy hard block (conflict check for
  /// expected/deadline moments, spec 1.2.3).
  static bool isBusyAt({
    required List<ScheduleBlock> blocks,
    required DateTime moment,
  }) {
    final windowStart = moment.subtract(const Duration(minutes: 1));
    final windowEnd = moment.add(const Duration(minutes: 1));
    return busyIntervals(
            blocks: blocks, windowStart: windowStart, windowEnd: windowEnd)
        .isNotEmpty;
  }
}

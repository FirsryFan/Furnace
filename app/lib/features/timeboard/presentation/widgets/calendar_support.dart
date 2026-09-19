import 'package:flutter/material.dart';

/// ISO-8601 week helpers (user feedback item 3: the week column shows a week
/// number, and the month grid needs one per row).
///
/// One scheme is used everywhere: the calendar year's week number 1..53, which
/// matches ISO-8601 and therefore stays continuous across the multi-year
/// timeline instead of restarting inside every month.
abstract final class IsoWeek {
  /// ISO week number of [date] (1..53).
  static int number(DateTime date) {
    // A date belongs to the week of its Thursday, and week 1 is the week that
    // contains 4 January. Counting weeks since that week's Thursday gives the
    // number directly (the first Thursday is the Thursday of week 1, so the
    // offset is +1, not +2 - the classic off-by-one in this algorithm).
    final thursday = date.add(Duration(days: 4 - _isoWeekday(date)));
    final firstThursday = _firstThursdayOf(thursday.year);
    final diff = thursday.difference(firstThursday).inDays;
    return (diff ~/ 7) + 1;
  }

  /// ISO week-numbering year of [date] (can differ from `date.year` at the
  /// year boundary).
  static int weekYear(DateTime date) {
    final thursday = date.add(Duration(days: 4 - _isoWeekday(date)));
    return thursday.year;
  }

  /// `2026-W37` style label.
  static String label(DateTime date) =>
      '${weekYear(date)}-W${number(date).toString().padLeft(2, '0')}';

  /// Monday of the ISO week containing [date].
  static DateTime weekStart(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return day.subtract(Duration(days: _isoWeekday(day) - 1));
  }

  /// Every day of the ISO week containing [date], Monday first.
  static List<DateTime> weekDays(DateTime date) {
    final start = weekStart(date);
    return [for (var i = 0; i < 7; i++) start.add(Duration(days: i))];
  }

  /// 1 = Monday .. 7 = Sunday.
  static int _isoWeekday(DateTime date) => date.weekday;

  /// Thursday of ISO week 1 of [year]: the Thursday of the week containing
  /// 4 January.
  static DateTime _firstThursdayOf(int year) {
    final jan4 = DateTime(year, 1, 4);
    final monday = jan4.subtract(Duration(days: jan4.weekday - 1));
    return monday.add(const Duration(days: 3));
  }
}

/// Translucent coloured block palette (user feedback 3: blocks are transparent
/// cards in different colours instead of one uniform bar).
///
/// Slot 0 is the plain "busy" colour; the rest cycle for visual grouping. Alpha
/// keeps overlapping blocks readable, which matters because overlaps are
/// explicitly allowed.
abstract final class BlockPalette {
  static const List<Color> _slots = [
    Color(0xFF1565C0), // blue
    Color(0xFF2E7D32), // green
    Color(0xFF6A1B9A), // purple
    Color(0xFFEF6C00), // orange
    Color(0xFF00838F), // teal
    Color(0xFFAD1457), // pink
    Color(0xFF4527A0), // indigo
    Color(0xFF827717), // olive
  ];

  static int get slotCount => _slots.length;

  static Color colorFor(int slot) => _slots[slot.abs() % _slots.length];

  /// Deterministic colour for a block, so a block keeps its colour across
  /// rebuilds and sessions.
  static int slotForId(String id) {
    var hash = 0;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash % _slots.length;
  }

  /// Fill drawn behind the label. Busy blocks are more opaque than open ones
  /// (GAP D6 semantics stay visible).
  static Color fill(Color base, {required bool busy}) =>
      base.withValues(alpha: busy ? 0.55 : 0.22);

  static Color border(Color base, {required bool busy}) =>
      base.withValues(alpha: busy ? 0.95 : 0.6);
}

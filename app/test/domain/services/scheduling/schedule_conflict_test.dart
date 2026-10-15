/// 日程冲突（Q23 / spec 1.2.3）的纯逻辑契约。
///
/// 这一组测试**只钉口径，不发明规则**：
/// * 忙碌 = `available == false`；开放块（available == true）不算占用（D6）。
/// * 重复规则（none/daily/weekly+dow）按 [TimeWindowEngine.expand] 展开。
/// * 区间按半开 `[start, end)`：**首尾相接不算冲突**（`a.end == b.start`）。
/// * 时刻用引擎既有的 [TimeWindowEngine.isBusyAt]（它是 ±1 分钟探测窗口：
///   块结束那一刻也算撞上、块开始前一分钟也算撞上）。这条是既有实现，不是新规则，
///   这里逐点断言它和新 API 同真同假，免得以后有人悄悄改一边。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/scheduling/schedule_conflict.dart';
import 'package:furnace/domain/services/scheduling/time_window_engine.dart';

/// 2026-09-07 是星期一。
final DateTime monday = DateTime(2026, 9, 7);

ScheduleBlock busy(
  String id,
  int startHour,
  int endHour, {
  DateTime? day,
  int startMinute = 0,
  int endMinute = 0,
  String? repeatRule,
}) {
  final base = day ?? monday;
  final startAt =
      DateTime(base.year, base.month, base.day, startHour, startMinute);
  var endAt = DateTime(base.year, base.month, base.day, endHour, endMinute);
  if (!endAt.isAfter(startAt)) {
    // 跨过午夜的块（22:00 → 次日 02:00）endAt 在第二天；
    // 引擎对 endAt < startAt 的负长度块视为不存在，所以别拿它当跨天用例。
    endAt = endAt.add(const Duration(days: 1));
  }
  return ScheduleBlock(
    id: id,
    title: '块 $id',
    startAt: startAt,
    endAt: endAt,
    available: false,
    repeatRule: repeatRule,
  );
}

ScheduleBlock open(
  String id,
  int startHour,
  int endHour, {
  DateTime? day,
}) {
  final base = day ?? monday;
  return ScheduleBlock(
    id: id,
    title: '块 $id',
    startAt: DateTime(base.year, base.month, base.day, startHour),
    endAt: DateTime(base.year, base.month, base.day, endHour),
    available: true,
  );
}

DateTime at(int dayOffset, int hour, [int minute = 0]) =>
    DateTime(2026, 9, 7 + dayOffset, hour, minute);

void main() {
  group('inRange：区间撞上忙碌块（半开区间）', () {
    test('命中时返回的是块的**真实**起止，不是被查询窗口裁过的那一段', () {
      final blocks = [busy('class', 8, 10)];

      final hits = ScheduleConflict.inRange(
        blocks: blocks,
        start: at(0, 9),
        end: at(0, 9, 30),
      );

      expect(hits, hasLength(1));
      expect(hits.single.block.id, 'class');
      // 被裁的话这里会是 9:00 / 9:30 —— 那样"移到这块之前"就会挪到错误的时刻。
      expect(hits.single.busy.start, at(0, 8));
      expect(hits.single.busy.end, at(0, 10));
    });

    test('首尾相接不算冲突', () {
      final blocks = [busy('class', 8, 10)];

      expect(
        ScheduleConflict.inRange(
            blocks: blocks, start: at(0, 10), end: at(0, 11)),
        isEmpty,
      );
      expect(
        ScheduleConflict.inRange(
            blocks: blocks, start: at(0, 7), end: at(0, 8)),
        isEmpty,
      );
      // 只贴着一分钟也不算。
      expect(
        ScheduleConflict.inRange(
            blocks: blocks, start: at(0, 7, 59), end: at(0, 8)),
        isEmpty,
      );
    });

    test('覆盖、部分重叠、完全包裹都算撞上，按开始时间排序', () {
      final blocks = [busy('late', 14, 16), busy('early', 8, 10)];

      final hits = ScheduleConflict.inRange(
        blocks: blocks,
        start: at(0, 9),
        end: at(0, 15),
      );

      expect(hits.map((h) => h.block.id).toList(), ['early', 'late']);
      expect(hits.first.busy.start, at(0, 8));
      expect(hits.last.busy.end, at(0, 16));
    });

    test('空区间 / 反向区间一律不撞', () {
      final blocks = [busy('class', 8, 10)];

      expect(
        ScheduleConflict.inRange(
            blocks: blocks, start: at(0, 9), end: at(0, 9)),
        isEmpty,
      );
      expect(
        ScheduleConflict.inRange(
            blocks: blocks, start: at(0, 11), end: at(0, 9)),
        isEmpty,
      );
    });

    test('开放块（available=true）不算占用', () {
      final blocks = [open('open', 8, 10)];

      expect(
        ScheduleConflict.inRange(
            blocks: blocks, start: at(0, 9), end: at(0, 9, 30)),
        isEmpty,
      );
      expect(ScheduleConflict.at(blocks: blocks, moment: at(0, 9)), isNull);
    });
  });

  group('inRange：跨天与重复规则', () {
    test('跨天的块在两天里都算撞上', () {
      final blocks = [busy('night', 22, 2, day: monday)];

      expect(
        ScheduleConflict.inRange(
            blocks: blocks, start: at(0, 23), end: at(0, 23, 30)),
        hasLength(1),
      );
      expect(
        ScheduleConflict.inRange(
            blocks: blocks, start: at(1, 1), end: at(1, 1, 30)),
        hasLength(1),
      );
      // 真起止横跨两天：22:00(周一) → 02:00(周二)。
      final hit = ScheduleConflict.at(blocks: blocks, moment: at(1, 1));
      expect(hit, isNotNull);
      expect(hit!.busy.start, at(0, 22));
      expect(hit.busy.end, at(1, 2));
      // 首尾相接：周二 02:00 那一刻不算撞（区间口径）。
      expect(
        ScheduleConflict.inRange(
            blocks: blocks, start: at(1, 2), end: at(1, 3)),
        isEmpty,
      );
    });

    test('daily 规则在之后每一天都展开', () {
      final blocks = [busy('daily', 9, 10, repeatRule: '{"type":"daily"}')];

      for (final offset in <int>[0, 1, 5, 30]) {
        expect(
          ScheduleConflict.inRange(
              blocks: blocks, start: at(offset, 9, 30), end: at(offset, 9, 45)),
          hasLength(1),
          reason: '第 $offset 天应该撞上',
        );
      }
      expect(
        ScheduleConflict.inRange(
            blocks: blocks, start: at(2, 11), end: at(2, 12)),
        isEmpty,
      );
    });

    test('weekly 规则只在列出的星期几展开', () {
      final blocks = [
        busy('lecture', 14, 16, repeatRule: '{"type":"weekly","dows":[1,3]}'),
      ];

      // 周一、周三命中；周二、周四不命中。
      expect(ScheduleConflict.at(blocks: blocks, moment: at(0, 15)), isNotNull);
      expect(ScheduleConflict.at(blocks: blocks, moment: at(2, 15)), isNotNull);
      expect(ScheduleConflict.at(blocks: blocks, moment: at(1, 15)), isNull);
      expect(ScheduleConflict.at(blocks: blocks, moment: at(3, 15)), isNull);
    });
  });

  group('at：时刻撞上忙碌块（沿用引擎 isBusyAt 口径）', () {
    test('和 TimeWindowEngine.isBusyAt 对每个探测时刻同真同假', () {
      final blocks = [
        busy('a', 8, 10),
        busy('b', 10, 12),
        busy('c', 14, 16, day: at(1, 0)),
      ];
      final probes = <DateTime>[
        at(0, 7),
        at(0, 8),
        at(0, 9),
        at(0, 9, 59),
        at(0, 10),
        at(0, 11),
        at(0, 12),
        at(0, 13),
        at(0, 14),
        at(1, 0),
        at(1, 14),
        at(1, 16),
        at(1, 17),
      ];

      for (final moment in probes) {
        final engine =
            TimeWindowEngine.isBusyAt(blocks: blocks, moment: moment);
        final mine =
            ScheduleConflict.at(blocks: blocks, moment: moment) != null;
        expect(mine, engine, reason: '口径不一致：$moment');
      }
    });

    test('引擎的 ±1 分钟探测把"块结束那一刻"也算撞上（既有口径，钉住）', () {
      final blocks = [busy('class', 8, 10)];

      expect(
          TimeWindowEngine.isBusyAt(blocks: blocks, moment: at(0, 10)), isTrue);
      expect(ScheduleConflict.at(blocks: blocks, moment: at(0, 10)), isNotNull);
      // 但区间口径（半开）认为 10:00 之后不撞 —— 两种口径的差别是有意的、已知的。
      expect(
        ScheduleConflict.inRange(
            blocks: blocks, start: at(0, 10), end: at(0, 11)),
        isEmpty,
      );
    });

    test('没撞上返回 null；同时撞上多块时取最早开始的那块', () {
      final blocks = [busy('late', 14, 16), busy('early', 8, 10)];

      expect(ScheduleConflict.at(blocks: blocks, moment: at(0, 12)), isNull);
      final hit = ScheduleConflict.at(blocks: blocks, moment: at(0, 10));
      expect(hit, isNotNull);
      expect(hit!.block.id, 'early');
      expect(hit.busy.start, at(0, 8));
      expect(hit.busy.end, at(0, 10));
    });
  });

  group('顺延：落到引擎判定为空闲的最近时刻', () {
    test('往后顺延：块结束后一分钟（引擎口径里 10:00 那一刻仍算撞上）', () {
      final blocks = [busy('class', 8, 10)];
      final hit = ScheduleConflict.at(blocks: blocks, moment: at(0, 9))!;

      final moved = ScheduleConflict.freeMomentAfter(blocks: blocks, hit: hit);

      expect(moved, at(0, 10, 1));
      expect(
          TimeWindowEngine.isBusyAt(blocks: blocks, moment: moved!), isFalse);
    });

    test('往前顺延：块开始前一分钟', () {
      final blocks = [busy('class', 8, 10)];
      final hit = ScheduleConflict.at(blocks: blocks, moment: at(0, 9))!;

      final moved = ScheduleConflict.freeMomentBefore(blocks: blocks, hit: hit);

      expect(moved, at(0, 7, 59));
      expect(
          TimeWindowEngine.isBusyAt(blocks: blocks, moment: moved!), isFalse);
    });

    test('连着几块时会跳过整条链', () {
      final blocks = [busy('a', 8, 10), busy('b', 10, 12)];
      final hit = ScheduleConflict.at(blocks: blocks, moment: at(0, 9))!;

      expect(ScheduleConflict.freeMomentAfter(blocks: blocks, hit: hit),
          at(0, 12, 1));
      expect(
        ScheduleConflict.freeMomentBefore(blocks: blocks, hit: hit),
        at(0, 7, 59),
      );
    });

    test('一天之内找不到空位时返回 null，不硬造一个时刻', () {
      final blocks = [
        busy('all-day', 0, 23,
            startMinute: 0, endMinute: 59, repeatRule: '{"type":"daily"}'),
      ];
      final hit = ScheduleConflict.at(blocks: blocks, moment: at(0, 12))!;

      expect(
        ScheduleConflict.freeMomentAfter(blocks: blocks, hit: hit, maxHops: 4),
        isNull,
      );
      expect(
        ScheduleConflict.freeMomentBefore(blocks: blocks, hit: hit, maxHops: 4),
        isNull,
      );
    });
  });

  group('区间顺延：整段平移，保证不再与这块相撞', () {
    test('移到这块之前：结束正好落在块开始', () {
      final blocks = [busy('class', 8, 10)];
      final hit = ScheduleConflict.at(blocks: blocks, moment: at(0, 9))!;

      final (start, end) = ScheduleConflict.rangeBefore(
        hit: hit,
        length: const Duration(hours: 1),
      );

      expect(end, at(0, 8));
      expect(start, at(0, 7));
      expect(
        ScheduleConflict.inRange(blocks: blocks, start: start, end: end),
        isEmpty,
      );
    });

    test('移到这块之后：开始正好落在块结束', () {
      final blocks = [busy('class', 8, 10)];
      final hit = ScheduleConflict.at(blocks: blocks, moment: at(0, 9))!;

      final (start, end) = ScheduleConflict.rangeAfter(
        hit: hit,
        length: const Duration(minutes: 90),
      );

      expect(start, at(0, 10));
      expect(end, at(0, 11, 30));
      expect(
        ScheduleConflict.inRange(blocks: blocks, start: start, end: end),
        isEmpty,
      );
    });
  });
}

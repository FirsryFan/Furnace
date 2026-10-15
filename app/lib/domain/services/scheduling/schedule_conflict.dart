/// 日程冲突（Q23 / spec 1.2.3）：把 [TimeWindowEngine] 已经算出来的忙碌区间
/// 包成 UI 真正需要问的三件事——「撞上了哪一块」「这块的真实起止是什么」
/// 「能不能挪、挪到哪个时刻」。
///
/// **口径全部沿用引擎，这里不发明规则：**
/// * 忙碌 = `available == false`；开放块（`available == true`）不算占用（GAP D6）。
/// * 重复规则（null / `{"type":"none"}` / `daily` / `weekly`+`dows`）按
///   [TimeWindowEngine.expand] 展开。
/// * 区间按半开 `[start, end)`：**首尾相接不算冲突**（`a.end == b.start`）。
/// * 时刻用 [TimeWindowEngine.isBusyAt]，与它逐点同真同假。注意它的实现是
///   **±1 分钟探测窗口**：块结束那一刻、块开始前一分钟都算撞上。这是既有口径，
///   `schedule_conflict_test.dart` 把它和区间口径的差别都钉住了，免得以后
///   有人悄悄改动一边。
///
/// 为什么不用现成的 [TimeWindowEngine.busyIntervals]：它把区间**裁到查询窗口**上，
/// 而「移到这块之前/之后」需要的恰恰是没被裁过的真实边界。这里用 expand 在一个
/// 加宽过（±块时长）的窗口上展开，再按半开重叠过滤，拿到真实起止。
library;

import 'time_window_engine.dart';

/// 一次冲突：撞上的**源块**（能拿到 title）与它**真实**的那一次展开。
class ScheduleConflictHit {
  const ScheduleConflictHit({required this.block, required this.busy});

  /// 撞上的日程块（原始行形状，title/id 都在）。
  final ScheduleBlock block;

  /// 撞上的那一次展开；起止是真实的（不是被查询窗口裁过的）。
  final BusyInterval busy;

  @override
  String toString() => 'ScheduleConflictHit(${block.id} '
      '${busy.start.toIso8601String()}→${busy.end.toIso8601String()})';
}

/// 冲突判定与顺延候选（纯逻辑，无 Flutter / 无 DB / 无时钟）。
abstract final class ScheduleConflict {
  /// [start, end) 撞上的所有忙碌块，按真实开始时间（再按 id）排序。
  ///
  /// 返回值里的 `busy` 一律是**真实起止**——这点是刻意的：调用方要拿它算
  /// 「移到这块之前/之后」，被窗口裁过的边界会算错。
  static List<ScheduleConflictHit> inRange({
    required List<ScheduleBlock> blocks,
    required DateTime start,
    required DateTime end,
  }) {
    if (!start.isBefore(end)) {
      return const <ScheduleConflictHit>[];
    }
    final hits = <ScheduleConflictHit>[];
    for (final block in blocks) {
      if (block.available) {
        // 开放块不占时间（GAP D6）。
        continue;
      }
      final width = block.endAt.difference(block.startAt);
      final pad = width.isNegative ? Duration.zero : width;
      for (final occurrence in TimeWindowEngine.expand(
        block: block,
        windowStart: start.subtract(pad),
        windowEnd: end.add(pad),
      )) {
        // 半开重叠：首尾相接不算。
        if (occurrence.start.isBefore(end) && start.isBefore(occurrence.end)) {
          hits.add(ScheduleConflictHit(block: block, busy: occurrence));
        }
      }
    }
    hits.sort((a, b) {
      final byStart = a.busy.start.compareTo(b.busy.start);
      if (byStart != 0) {
        return byStart;
      }
      return a.block.id.compareTo(b.block.id);
    });
    return hits;
  }

  /// [moment] 那一刻是否撞上忙碌块；撞上时返回最早开始的那一块。
  ///
  /// 「撞没撞上」由 [TimeWindowEngine.isBusyAt] 判定（同一个 ±1 分钟探测窗口），
  /// 这里只是把「撞上哪一块」也带出来。
  ///
  /// 多块命中时的选择顺序：先取**真正盖住这一刻**（`start <= moment < end`）的
  /// 那一块——它的边界没被裁剪，弹窗显示的范围才准；都不盖住时（例如
  /// [moment] 正好是块结束那一刻，±1 分钟探测仍算撞上）取最早开始的。
  static ScheduleConflictHit? at({
    required List<ScheduleBlock> blocks,
    required DateTime moment,
  }) {
    // 「撞没撞上」直接问引擎原语（`isBusyAt` 内部就是 `busyIntervals(±1min)`），
    // 这里只负责回答「是哪一块」。
    if (!TimeWindowEngine.isBusyAt(blocks: blocks, moment: moment)) {
      return null;
    }
    final hits = inRange(
      blocks: blocks,
      start: moment.subtract(const Duration(minutes: 1)),
      end: moment.add(const Duration(minutes: 1)),
    );
    if (hits.isEmpty) {
      return null;
    }
    for (final hit in hits) {
      if (!moment.isBefore(hit.busy.start) && moment.isBefore(hit.busy.end)) {
        return hit;
      }
    }
    return hits.first;
  }

  /// 从撞上的这块往 [direction]（-1 = 之前 / +1 = 之后）走，返回引擎判定为
  /// **空闲**的最近时刻（每次以整分钟为步长，且直接跳到下一块的边界外，
  /// 不会一分钟一分钟挪）。
  ///
  /// 找不到（例如一整天都被重复忙碌块占满）返回 null——不硬造一个时刻。
  ///
  /// 注意「空闲」的判定就是引擎的 [TimeWindowEngine.isBusyAt]，所以块结束那一刻
  /// 仍算忙碌，往后要再走一分钟才是空闲（见测试）。
  static DateTime? freeMoment({
    required List<ScheduleBlock> blocks,
    required ScheduleConflictHit hit,
    required int direction,
    int maxHops = 64,
  }) {
    assert(direction != 0, 'direction 必须非零：-1 = 之前 / +1 = 之后');
    var cursor = direction < 0 ? hit.busy.start : hit.busy.end;
    for (var hop = 0; hop < maxHops; hop++) {
      final next = at(blocks: blocks, moment: cursor);
      if (next == null) {
        return cursor;
      }
      final step = direction < 0
          ? next.busy.start.subtract(const Duration(minutes: 1))
          : next.busy.end.add(const Duration(minutes: 1));
      if (step == cursor) {
        // 走不动了（异常数据），不空转到 maxHops。
        return null;
      }
      cursor = step;
    }
    return null;
  }

  /// [freeMoment] 的「移到这块之前」。
  static DateTime? freeMomentBefore({
    required List<ScheduleBlock> blocks,
    required ScheduleConflictHit hit,
    int maxHops = 64,
  }) =>
      freeMoment(blocks: blocks, hit: hit, direction: -1, maxHops: maxHops);

  /// [freeMoment] 的「移到这块之后」。
  static DateTime? freeMomentAfter({
    required List<ScheduleBlock> blocks,
    required ScheduleConflictHit hit,
    int maxHops = 64,
  }) =>
      freeMoment(blocks: blocks, hit: hit, direction: 1, maxHops: maxHops);

  /// 区间版顺延：整段平移到这块**之前**，结束正好落在块开始（半开区间下不再相撞）。
  static (DateTime, DateTime) rangeBefore({
    required ScheduleConflictHit hit,
    required Duration length,
  }) {
    final end = hit.busy.start;
    return (end.subtract(length), end);
  }

  /// 区间版顺延：整段平移到这块**之后**，开始正好落在块结束。
  static (DateTime, DateTime) rangeAfter({
    required ScheduleConflictHit hit,
    required Duration length,
  }) {
    final start = hit.busy.end;
    return (start, start.add(length));
  }
}

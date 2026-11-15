/// 本周 / 本日时间窗投影（schema v47，2026-11-15）。
///
/// 契约：`INTEGRATION-CONTRACT-2026-11-15.md` §3.5。侧边栏/ThreadFeed 的
/// 「本周任务 / 本日任务」是 **tasks 表的纯投影**，不是第二张计划表、不是第二份
/// 状态：本文件只做两件事——
///
///  1. 定义本地日历窗口 [weekWindow] / [dayWindow]（周一为一周第一天）；
///  2. 把已经排好序的节点 id 列表按「成员关系」切成 week / day / unscheduled 三桶，
///     **保持调用方给的相对顺序**（排序仍然只有 `ThreadRankService` 一个入口）。
///
/// 成员关系（写死，不猜）：
///
///  * `status ∈ {todo, doing, blocked}` 才参与投影（`ThreadStatus.appearsInWindow`；
///    done/skipped 归归档）；
///  * 锚点 = `expectedAt ?? dueAt`（软期望优先；契约 §3.5 原文「用
///    node.expectedAt ?? node.dueAt 判窗口重叠」）；
///  * 锚点落在窗口 `[start, end)` 内才进这一桶（本地时刻；日窗口是周窗口的子集，
///    所以今天的任务会同时出现在两桶里——这是有意的，两桶是**两个问法**）；
///  * 两个时间都为 NULL → `unscheduled`（「未排期」），**不进**任何时间窗；
///  * `week` / `day` 容器自己也参与投影（它们带着 `windowStart` 物化，锚点就在
///    本窗口内）；容器不因 `kind` 被特殊放行——没日期就是没排期。
///
/// 不做的事：不读库、不写库、不算权重、不调用排名器、不依赖 Flutter。窗口用
/// 「本地日历字段」构造（`DateTime(y, m, d)` 自动进位），刻意不用
/// `add(Duration(days: 7))`，以免夏令时把一周边成 23/25 小时。
library;

import '../thread/thread_node_kind.dart';
import '../thread/thread_status.dart';

/// 一个半开区间窗口 `[start, end)`，按本地时刻比较。
class ThreadWindow {
  const ThreadWindow({required this.start, required this.end});

  /// 窗口起点（含）。
  final DateTime start;

  /// 窗口终点（不含）。
  final DateTime end;

  /// [moment] 是否落在本窗口内（`start <= moment < end`）。
  bool contains(DateTime moment) =>
      !moment.isBefore(start) && moment.isBefore(end);

  /// 当前时刻是否还在窗口内（给 UI 判断"今天"用；不参与成员判定）。
  bool containsNow(DateTime now) => contains(now);

  @override
  bool operator ==(Object other) =>
      other is ThreadWindow && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() =>
      'ThreadWindow(${start.toIso8601String()} .. ${end.toIso8601String()})';
}

/// 取「用户所在时区」的日历时刻：UTC 输入先转本地，避免用 UTC 的年月日当时区。
DateTime _localOf(DateTime moment) => moment.isUtc ? moment.toLocal() : moment;

/// 本周窗口：`[本周一 00:00, 下周一 00:00)`（本地时刻，ISO 周：周一为第一天）。
///
/// [now] 是 UTC 时会先转本地再取日历字段：窗口的"哪一天"永远按用户所在时区算。
ThreadWindow weekWindow(DateTime now) {
  final local = _localOf(now);
  // 用日历字段做减法（不经 Duration），跨夏令时也落在真实的周一 00:00。
  final monday =
      DateTime(local.year, local.month, local.day - (local.weekday - 1));
  return ThreadWindow(
    start: monday,
    end: DateTime(monday.year, monday.month, monday.day + 7),
  );
}

/// 本日窗口：`[今天 00:00, 明天 00:00)`（本地时刻）。
ThreadWindow dayWindow(DateTime now) {
  final local = _localOf(now);
  return ThreadWindow(
    start: DateTime(local.year, local.month, local.day),
    end: DateTime(local.year, local.month, local.day + 1),
  );
}

/// 投影用的节点视图：只取「谁、什么种类、什么状态、两个时间」。
///
/// 刻意不直接用 drift 的 `Task` 行：本文件属于 domain 纯逻辑，接受值对象才能
/// 在没有数据库、没有 Flutter 的测试里钉死窗口规则。application 层负责把 `Task`
/// 映射成它（epoch 毫秒 → 本地 `DateTime`）。
class ThreadWindowNode {
  const ThreadWindowNode({
    required this.id,
    required this.kind,
    required this.status,
    this.expectedAt,
    this.dueAt,
  });

  /// `tasks.id`（稳定主键）。
  final String id;

  /// 节点种类（week/day 容器与逐题 task 一样参与投影）。
  final ThreadNodeKind kind;

  /// 状态；done/skipped 不参与投影。
  final ThreadStatus status;

  /// 软期望时刻（本地；NULL = 没排）。
  final DateTime? expectedAt;

  /// 硬截止时刻（本地；NULL = 没截止）。
  final DateTime? dueAt;

  /// 窗口成员判定用的锚点：软期望优先，其次硬截止；两者都没有 = 未排期。
  DateTime? get anchor => expectedAt ?? dueAt;
}

/// 一次投影的结果：三桶 + 这次用的两个窗口（UI 要显示「本周」是哪一周）。
class ThreadWindowBuckets {
  const ThreadWindowBuckets({
    required this.week,
    required this.day,
    required this.unscheduled,
    required this.weekWindow,
    required this.dayWindow,
  });

  /// 本周任务（保持调用方给的相对顺序；容器也在里面）。
  final List<ThreadWindowNode> week;

  /// 本日任务（同上；日窗口是周窗口的子集）。
  final List<ThreadWindowNode> day;

  /// 两个时间都为 NULL 的节点（「未排期」；不进任何时间窗）。
  final List<ThreadWindowNode> unscheduled;

  /// 这次投影用的本周窗口。
  final ThreadWindow weekWindow;

  /// 这次投影用的本日窗口。
  final ThreadWindow dayWindow;

  /// 两个时间窗都空 = UI 不该显示「本周/本日」分类（不占位、不显示空标签）。
  bool get isEmpty => week.isEmpty && day.isEmpty;

  /// 有任务的节点总数（week ∪ day ∪ unscheduled；终态节点不在内）。
  int get totalCount => week.length + day.length + unscheduled.length;
}

/// 窗口投影器：一个纯函数，无状态。
class ThreadWindowProjection {
  const ThreadWindowProjection._();

  /// 把 [nodes] 切成 week / day / unscheduled 三桶。
  ///
  /// [orderedIds] 是调用方已有的相对顺序（侧边栏/ThreadFeed 传
  /// `ThreadFeed.readyTasks` 的 id 顺序）。**本函数不排序**：先按 [orderedIds]
  /// 取节点，再把不在其中但参与投影的节点按输入顺序接在后面（例如 week/day 容器
  /// 不在 ready 列表里，它们会落在各自桶的尾部）。
  ///
  /// [now] 决定两个窗口；同一个节点在同一时刻只会有一种归属：
  /// 终态 → 不出现；锚点为 NULL → unscheduled；锚点在周窗口 → week；锚点在日窗口
  /// → day（同时可能也在 week）。
  static ThreadWindowBuckets project({
    required Iterable<ThreadWindowNode> nodes,
    required Iterable<String> orderedIds,
    required DateTime now,
  }) {
    final byId = <String, ThreadWindowNode>{};
    for (final node in nodes) {
      byId.putIfAbsent(node.id, () => node);
    }
    final ordered = <ThreadWindowNode>[];
    final seen = <String>{};
    for (final id in orderedIds) {
      final node = byId[id];
      if (node != null && seen.add(id)) {
        ordered.add(node);
      }
    }
    for (final node in byId.values) {
      if (seen.add(node.id)) {
        ordered.add(node);
      }
    }

    final week = weekWindow(now);
    final day = dayWindow(now);
    final weekNodes = <ThreadWindowNode>[];
    final dayNodes = <ThreadWindowNode>[];
    final unscheduled = <ThreadWindowNode>[];

    for (final node in ordered) {
      if (!node.status.appearsInWindow) {
        continue;
      }
      final anchor = node.anchor;
      if (anchor == null) {
        unscheduled.add(node);
        continue;
      }
      if (week.contains(anchor)) {
        weekNodes.add(node);
      }
      if (day.contains(anchor)) {
        dayNodes.add(node);
      }
    }

    return ThreadWindowBuckets(
      week: List.unmodifiable(weekNodes),
      day: List.unmodifiable(dayNodes),
      unscheduled: List.unmodifiable(unscheduled),
      weekWindow: week,
      dayWindow: day,
    );
  }
}

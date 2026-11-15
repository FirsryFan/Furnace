/// 父容器状态/进度 rollup（schema v47，2026-11-15）。
///
/// 契约：`INTEGRATION-CONTRACT-2026-11-15.md` §3.4（父容器状态由子节点汇总）与
/// §3.5（`parentRollup(week) = 子节点 done / 子节点总数`，跳过/卡住单列、不算完成）。
///
/// 为什么要有它：周/日/组卷物化出的父容器（kind = week/day/paper）自己只有一个
/// `tasks.status` 列，物化器只把它建成 `todo`；于是侧边栏/Thread 看一周或一天时，
/// 容器看上去永远"没开始"。可是父容器的真实状态完全由子任务决定，父行上的状态
/// 只是它的**缓存**。本文件把这条规则做成一个**纯函数**：
///
///  1. 只读：不查库、不写库、**不写父容器状态**；输入是 `Task` 行的只读投影
///     [ThreadRollupNode]（application 层负责把 drift 行映射过来，见
///     `features/thread/application/thread_rollup_projection.dart`）。
///  2. 规则写死（契约 §3.4 的优先级顺序），不由页面各自再算一遍：
///     - 没有子节点 → 状态 `null`（"没有子任务"不是一种状态，不猜 `todo`）；
///     - 任一子节点 `doing` → `doing`；
///     - 否则任一 `blocked` → `blocked`；
///     - 否则任一 `todo` → `todo`；
///     - 否则子节点全是 `done`/`skipped`：至少一个 `done` → `done`，全 `skipped`
///       → `skipped`。
///  3. 数值不冒充：估时 = 子节点之和，**任一子节点估时为 null（或没有子节点）→
///     null**，不把"未知"写成 0；进度 = `done / total`，分母为 0 时返回 null
///     （不是 0%）。
///
/// 不做的事：不做第二调度器（不排序、不选槽位）、不读事件流、不推断"应该"完成
/// 什么。写父状态若要发生，仍然只能走 `ThreadFlowWriter`（同一写口），并且由调用
/// 方显式决定；本文件只负责回答"如果现在汇总，父容器是什么样"。
library;

import 'thread_node_kind.dart';
import 'thread_status.dart';

/// rollup 的输入节点：`Task` 行的只读投影（只取汇总需要的五个字段）。
///
/// 刻意不直接用 drift 的 `Task`：本文件属于 domain 纯逻辑，用值对象才能在
/// 没有数据库、没有 Flutter 的测试里把状态规则和 null 语义钉死
/// （与 `scheduling/thread_windows.dart` 的 `ThreadWindowNode` 同一做法）。
class ThreadRollupNode {
  const ThreadRollupNode({
    required this.id,
    required this.status,
    this.kind = ThreadNodeKind.task,
    this.parentId,
    this.estimateMinutes,
  });

  /// `tasks.id`（稳定主键）。
  final String id;

  /// 节点种类；容器（week/day）也照常参与，`kind` 只用于展示/筛选。
  final ThreadNodeKind kind;

  /// 流程状态（v47 五值）。未知/NULL 值由映射层读成 `todo`。
  final ThreadStatus status;

  /// 父节点 id（NULL = 根节点）。
  final String? parentId;

  /// 估时（分钟）；NULL = 未知。
  final int? estimateMinutes;
}

/// 各状态子节点计数。`total` 恒等于五项之和。
class ThreadRollupCounts {
  const ThreadRollupCounts({
    required this.total,
    required this.todo,
    required this.doing,
    required this.done,
    required this.blocked,
    required this.skipped,
  });

  /// 按状态列表数一遍（唯一计数口径，保证 total == 五项之和）。
  factory ThreadRollupCounts.of(Iterable<ThreadStatus> statuses) {
    var total = 0;
    var todo = 0;
    var doing = 0;
    var done = 0;
    var blocked = 0;
    var skipped = 0;
    for (final status in statuses) {
      total++;
      switch (status) {
        case ThreadStatus.todo:
          todo++;
        case ThreadStatus.doing:
          doing++;
        case ThreadStatus.done:
          done++;
        case ThreadStatus.blocked:
          blocked++;
        case ThreadStatus.skipped:
          skipped++;
      }
    }
    return ThreadRollupCounts(
      total: total,
      todo: todo,
      doing: doing,
      done: done,
      blocked: blocked,
      skipped: skipped,
    );
  }

  /// 子节点总数（跳过/卡住也在内——它们不是"完成"，但仍是子节点）。
  final int total;

  /// 待办（`todo`）。
  final int todo;

  /// 进行中（`doing`）。
  final int doing;

  /// 已完成（`done`）。
  final int done;

  /// 卡住（`blocked`）。
  final int blocked;

  /// 跳过（`skipped`）。
  final int skipped;

  /// 没有子节点。
  bool get isEmpty => total == 0;

  /// 终态子节点数（done + skipped）。
  int get terminal => done + skipped;

  /// 两个计数相加（合并多个容器的汇总时用）。
  ThreadRollupCounts plus(ThreadRollupCounts other) => ThreadRollupCounts(
        total: total + other.total,
        todo: todo + other.todo,
        doing: doing + other.doing,
        done: done + other.done,
        blocked: blocked + other.blocked,
        skipped: skipped + other.skipped,
      );

  @override
  String toString() => 'ThreadRollupCounts(total: $total, todo: $todo, '
      'doing: $doing, done: $done, blocked: $blocked, skipped: $skipped)';
}

/// 一个父容器的只读汇总结果。
class ThreadRollup {
  const ThreadRollup._({
    required this.parentId,
    required this.status,
    required this.counts,
    required this.estimateMinutes,
    required this.fraction,
    required this.percent,
  });

  /// 汇总 [parent] 的 [children]。
  ///
  /// [children] 为空时不猜状态：`status == null`、counts 全 0、估时与进度都
  /// null。其余规则见库级注释（契约 §3.4 的优先级顺序）。
  factory ThreadRollup.of({
    required ThreadRollupNode parent,
    required Iterable<ThreadRollupNode> children,
  }) {
    final rows = children.toList(growable: false);
    return ThreadRollup.fromCounts(
      parentId: parent.id,
      counts: ThreadRollupCounts.of([for (final child in rows) child.status]),
      estimateMinutes: _sumEstimates(rows),
    );
  }

  /// 由已有计数直接构造（[merge] 与调用方复用同一套状态/进度规则）。
  factory ThreadRollup.fromCounts({
    String? parentId,
    required ThreadRollupCounts counts,
    int? estimateMinutes,
  }) {
    return ThreadRollup._(
      parentId: parentId,
      status: _statusOf(counts),
      counts: counts,
      estimateMinutes: estimateMinutes,
      fraction: _fractionOf(counts),
      percent: _percentOf(counts),
    );
  }

  /// 把多个容器的汇总合并成一个（「本周/本日」chips 的聚合）。
  ///
  /// 计数相加；状态与进度按**合并后的计数**重算（同一套规则，不另写一份）；
  /// 估时：任一汇总的估时为 null → 合并结果也是 null（未知不冒充 0），没有
  /// 输入 → null。[rollups] 为空返回 null（没有可汇总的容器）。
  static ThreadRollup? merge(Iterable<ThreadRollup> rollups) {
    final rows = rollups.toList(growable: false);
    if (rows.isEmpty) {
      return null;
    }
    var counts = const ThreadRollupCounts(
      total: 0,
      todo: 0,
      doing: 0,
      done: 0,
      blocked: 0,
      skipped: 0,
    );
    int? estimate;
    var estimateKnown = true;
    for (final rollup in rows) {
      counts = counts.plus(rollup.counts);
      final childEstimate = rollup.estimateMinutes;
      if (childEstimate == null) {
        estimateKnown = false;
      } else if (estimateKnown) {
        estimate = (estimate ?? 0) + childEstimate;
      }
    }
    return ThreadRollup.fromCounts(
      counts: counts,
      estimateMinutes: estimateKnown ? estimate : null,
    );
  }

  /// 被汇总的父节点 id；由 [ThreadRollup.merge] 得到时为 null。
  final String? parentId;

  /// 汇总出来的状态；`null` = 没有子节点（不猜）。
  final ThreadStatus? status;

  /// 各状态计数。
  final ThreadRollupCounts counts;

  /// 子节点估时之和；任一子节点估时为 null（或没有子节点）→ null。
  final int? estimateMinutes;

  /// 进度 0..1 = `done / total`；没有子节点 → null（不是 0）。
  final double? fraction;

  /// 进度百分比 0..100（四舍五入）；没有子节点 → null。
  final int? percent;

  /// 没有任何子节点：这个父节点没有可汇总的东西。
  bool get isEmpty => counts.isEmpty;

  /// 子节点全部完成（`done` 数 == 总数；跳过不算完成）。
  bool get isComplete => counts.total > 0 && counts.done == counts.total;

  /// 子节点全部进入终态（`done` 或 `skipped`）。
  bool get allTerminal => counts.total > 0 && counts.terminal == counts.total;

  @override
  String toString() => 'ThreadRollup(parent: $parentId, '
      'status: ${status?.id}, $counts, estimate: $estimateMinutes, '
      'percent: $percent)';

  // ---------------------------------------------------------------------------
  // internals
  // ---------------------------------------------------------------------------

  /// 契约 §3.4 的状态优先级（doing > blocked > todo > done/skipped 折叠）。
  static ThreadStatus? _statusOf(ThreadRollupCounts counts) {
    if (counts.total == 0) {
      return null;
    }
    if (counts.doing > 0) {
      return ThreadStatus.doing;
    }
    if (counts.blocked > 0) {
      return ThreadStatus.blocked;
    }
    if (counts.todo > 0) {
      return ThreadStatus.todo;
    }
    if (counts.done > 0) {
      return ThreadStatus.done;
    }
    return ThreadStatus.skipped;
  }

  static double? _fractionOf(ThreadRollupCounts counts) {
    if (counts.total == 0) {
      return null;
    }
    return counts.done / counts.total;
  }

  static int? _percentOf(ThreadRollupCounts counts) {
    if (counts.total == 0) {
      return null;
    }
    return (counts.done * 100 / counts.total).round();
  }

  /// 子节点估时之和；**空集或任一子节点估时为 null → null**。
  ///
  /// 统计全部子节点（包含 done/skipped）：父容器的估时是"这个容器计划占多少
  /// 容量"，不是"还剩多少"，与 `PaperTaskMaterializer` 的求和口径一致。
  static int? _sumEstimates(List<ThreadRollupNode> children) {
    if (children.isEmpty) {
      return null;
    }
    var sum = 0;
    for (final child in children) {
      final estimate = child.estimateMinutes;
      if (estimate == null) {
        return null;
      }
      sum += estimate;
    }
    return sum;
  }
}

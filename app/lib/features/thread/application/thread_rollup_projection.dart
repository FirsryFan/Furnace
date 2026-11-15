/// ThreadFeed → 父容器 rollup 的应用层接线（schema v47，2026-11-15）。
///
/// 契约：`INTEGRATION-CONTRACT-2026-11-15.md` §3.4 / §3.5。本文件只做三件事：
///
///  1. 把 drift 的 `Task` 行映射成 domain 的 [ThreadRollupNode]（epoch 毫秒不参与
///     汇总，所以这里只取 id/kind/status/parentId/estimateMinutes）；
///  2. 按 `parentId` 分组，对**每个有子节点的父节点**调用
///     [ThreadRollup.of]（纯函数，规则在 domain 里，这里不复写）；
///  3. 把同一时间窗里同一类容器的汇总合并给「本周/本日」chips 用。
///
/// 三条硬约束：
///
///  * **只读**：不查库（`ThreadFeed.tasks` 里已经有全部任务行）、不写库、不写父
///    状态、不触发任何 writer；`ThreadFeed` 本来就是一次排序结果的内存快照。
///  * **不做第二调度器**：不排序、不选槽位，只是把已有行数一遍。
///  * **不猜**：没有子节点的父节点不进 map（没有可汇总的东西）；状态/估时/进度
///    的空值语义全部来自 domain，不在应用层补默认值。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database.dart';
import '../../../domain/services/scheduling/thread_windows.dart';
import '../../../domain/services/thread/thread_node_kind.dart';
import '../../../domain/services/thread/thread_rollup.dart';
import '../../../domain/services/thread/thread_status.dart';
import 'thread_rank_service.dart';

/// `Task` 行 → rollup 输入。NULL/未知的 `kind` / `status` 按 domain 的读侧口径
/// （`Task` 老行 `kind` 为 NULL 读作普通任务；未知状态读作 `todo`）。
ThreadRollupNode threadRollupNodeOf(Task task) => ThreadRollupNode(
      id: task.id,
      kind: ThreadNodeKind.fromStorage(task.kind),
      status: ThreadStatus.fromStorage(task.status),
      parentId: task.parentId,
      estimateMinutes: task.estimateMinutes,
    );

/// 由一份任务行集合算出「父节点 id → 汇总」。
///
/// 只包含**至少有一个子节点**的父节点：叶子任务不进 map，界面据此不显示
/// 一条空的"子任务"行。父节点本身可以是任何 kind（task/week/day/paper/review）
/// ——规则只看子节点，不按 kind 特判。
Map<String, ThreadRollup> threadRollupsOf(Iterable<Task> tasks) {
  final rows = tasks.toList(growable: false);
  final childrenByParentId = <String, List<ThreadRollupNode>>{};
  for (final task in rows) {
    final parentId = task.parentId;
    if (parentId == null || parentId.isEmpty) {
      continue;
    }
    (childrenByParentId[parentId] ??= <ThreadRollupNode>[])
        .add(threadRollupNodeOf(task));
  }

  final rollups = <String, ThreadRollup>{};
  for (final task in rows) {
    final children = childrenByParentId[task.id];
    if (children == null || children.isEmpty) {
      continue;
    }
    rollups[task.id] = ThreadRollup.of(
      parent: threadRollupNodeOf(task),
      children: children,
    );
  }
  return Map<String, ThreadRollup>.unmodifiable(rollups);
}

/// 一个窗口桶里**指定种类**容器的合并汇总（「本周/本日」chips 用）。
///
/// [kind] 只匹配合适的容器（本周 chip 用 `week`、本日 chip 用 `day`）：窗口桶是
/// 按锚点重叠切的，同一天里周容器的锚点（周一 00:00）也可能落在日窗口内，如果
/// 不分种类，本日 chip 会把整周的子任务算成"今日进度"。没有匹配的容器或容器
/// 没有子任务时返回 null（chips 不显示假的 0/0）。
ThreadRollup? threadContainerRollupOf({
  required Iterable<ThreadWindowNode> nodes,
  required Map<String, ThreadRollup> rollups,
  required ThreadNodeKind kind,
}) {
  final selected = <ThreadRollup>[];
  for (final node in nodes) {
    if (node.kind != kind) {
      continue;
    }
    final rollup = rollups[node.id];
    if (rollup != null && !rollup.isEmpty) {
      selected.add(rollup);
    }
  }
  return ThreadRollup.merge(selected);
}

/// 当前排序结果里的父容器汇总（只读派生，不写库）。
///
/// 还没排过序（`ThreadFeed == null`）时返回空 map：页面仍然只显示"需要重新
/// 排序"，不会为了进度自己再读一遍库或排一遍序。
final threadRollupsProvider = Provider<Map<String, ThreadRollup>>((ref) {
  final feed = ref.watch(threadFeedProvider).valueOrNull;
  if (feed == null) {
    return const <String, ThreadRollup>{};
  }
  return threadRollupsOf(feed.tasks.values);
});

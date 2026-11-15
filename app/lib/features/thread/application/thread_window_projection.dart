/// ThreadFeed → 「本周任务 / 本日任务」临时分类（应用层，2026-11-15）。
///
/// 契约：`INTEGRATION-CONTRACT-2026-11-15.md` §3.5。窗口规则本身在
/// `domain/services/scheduling/thread_windows.dart`（纯 Dart，有独立测试）；这里只做
/// 两件接线的事：
///
///  1. 把 `ThreadFeed.tasks` 的 `Task` 行映射成 [ThreadWindowNode]（epoch 毫秒 →
///     本地 `DateTime`），**不重新查库**——feed 里已经有全部任务行；
///  2. 把 `ThreadFeed.readyTasks` 的 id 顺序原样交给投影器，作为分类内的相对顺序。
///
/// 所以「本周/本日」是 **同一份排序结果的过滤**：不重算权重、不重排、不写库、
/// 不产生第二份任务状态。还没排过序（`ThreadFeed == null`）时这里返回 `null`，
/// 页面沿用既有「需要重新排序」提示，而不是自己排一遍。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database.dart';
import '../../../domain/services/scheduling/thread_windows.dart';
import '../../../domain/services/thread/thread_node_kind.dart';
import '../../../domain/services/thread/thread_status.dart';
import 'thread_rank_service.dart';

/// 投影用的「现在」。测试覆盖它来钉死周/日窗口；运行时不覆盖 = `DateTime.now()`。
///
/// 单独做成 provider 而不是参数，是因为页面拿不到注入点；而它只影响"哪一周/哪一天"，
/// 不参与排序，所以不能与 `ThreadRankService` 的时钟混用。
final threadWindowNowProvider = Provider<DateTime>((ref) => DateTime.now());

/// 从一份已算好的 [feed] 派生三桶；纯函数，便于在 widget 外直接测。
ThreadWindowBuckets threadWindowBucketsOf(ThreadFeed feed, DateTime now) {
  final nodes = <ThreadWindowNode>[
    for (final task in feed.tasks.values) _nodeOf(task),
  ];
  return ThreadWindowProjection.project(
    nodes: nodes,
    orderedIds: [for (final task in feed.readyTasks) task.id],
    now: now,
  );
}

/// 「本周任务 / 本日任务」：`null` = 还没排序（页面显示"需要重新排序"）。
final threadWindowBucketsProvider = Provider<ThreadWindowBuckets?>((ref) {
  final feed = ref.watch(threadFeedProvider).valueOrNull;
  if (feed == null) {
    return null;
  }
  return threadWindowBucketsOf(feed, ref.watch(threadWindowNowProvider));
});

ThreadWindowNode _nodeOf(Task task) => ThreadWindowNode(
      id: task.id,
      kind: ThreadNodeKind.fromStorage(task.kind),
      status: ThreadStatus.fromStorage(task.status),
      expectedAt: task.expectedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(task.expectedAt!),
      dueAt: task.dueAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(task.dueAt!),
    );

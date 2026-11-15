import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/database/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/scheduling/thread_windows.dart';
// 流程状态（todo/doing/done/blocked/skipped）与下面 `widgets/thread_status_edge.dart`
// 里同名的**时间** lifecycle 枚举不是一回事：本文件里 `ThreadStatus` 指时间颜色，
// 流程判断走 `taskFlowStatus()`（来自 task_status_actions.dart），比较时用前缀别名。
import '../../../domain/services/thread/thread_node_kind.dart';
import '../../../domain/services/thread/thread_rollup.dart';
import '../../../domain/services/thread/thread_status.dart' as flow;
import '../../../l10n/app_localizations.dart';
import '../../tasks/presentation/widgets/task_status_actions.dart';
import '../application/study_rhythm_reader.dart';
import '../application/thread_rank_service.dart';
import '../application/thread_rollup_projection.dart';
import '../application/thread_window_projection.dart';
import 'event_properties_page.dart';
import 'widgets/energy_colors.dart';
import 'widgets/thread_rollup_progress.dart';
import 'widgets/thread_status_bar.dart';
import 'widgets/thread_status_edge.dart';

/// The property page is the single place where ranking parameters are shown
/// and edited (blueprint 2.4); the list just links to it.
export 'event_properties_page.dart' show openEventProperties;

/// Thread module (blueprint 2.1; user annotations 5, 11, 12, 13).
///
/// Two peer views instead of one page with folded sections:
///   1. 事件流 - only events that can be ranked normally, WITHOUT any reason
///      text or score (user annotation 13: no L1 in the list).
///   2. 已归档 - completed + not-enough-time + overdue.
/// The event property page (all parameters, editable) opens over the list.
class ThreadPage extends ConsumerStatefulWidget {
  const ThreadPage({super.key});

  @override
  ConsumerState<ThreadPage> createState() => _ThreadPageState();
}

class _ThreadPageState extends ConsumerState<ThreadPage> {
  bool _archiveView = false;

  @override
  void initState() {
    super.initState();
    // A write anywhere else (a task edited in the task list, the AI assistant
    // adding one, a schedule block moved) invalidates the in-memory ranking.
    // Re-sorting keeps the stream honest; the ranker is pure, so nothing moves
    // unless the inputs really changed - and it never writes, so this cannot
    // feed itself.
    _revisionSubscription = ref.listenManual(dataRevisionProvider, (_, __) {
      if (ref.read(threadFeedProvider).valueOrNull == null) {
        return;
      }
      ref.read(threadFeedProvider.notifier).sort();
    });
  }

  late final ProviderSubscription<int> _revisionSubscription;

  @override
  void dispose() {
    _revisionSubscription.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final feedAsync = ref.watch(threadFeedProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.threadTitle),
        actions: [
          // Where the attention hint can be brought back after the reading's
          // own hide button removed it (schema v15 switch, roadmap §3 row 4),
          // plus the cognitive-order switch (schema v16, roadmap §2-D).
          _ThreadMenu(
            rhythmText: l10n.threadRhythmToggle,
            cognitiveText: l10n.threadCognitiveRankToggle,
          ),
          IconButton(
            tooltip: l10n.tasksNewTask,
            icon: const Icon(Icons.add),
            onPressed: () => _createEvent(context),
          ),
        ],
      ),
      body: Column(
        children: [
          ThreadStatusBar(
            onOpenProperties: () {
              final feed = feedAsync.valueOrNull;
              final first = feed?.readyTasks.isNotEmpty == true
                  ? feed!.readyTasks.first
                  : null;
              if (first != null) {
                openEventProperties(context, first);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.threadNoEvents)),
                );
              }
            },
          ),
          // 认知排序档位开着时，次序换了就得说清楚它是"提示"而不是测量
          // （加成常数全部未标定，见 cognitive_rank.dart）。
          if (ref.watch(cognitiveRankEnabledProvider).valueOrNull ?? false)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Row(
                children: [
                  Icon(
                    Icons.psychology_outlined,
                    size: 14,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      l10n.threadCognitiveRankNote,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.bolt),
                  label: Text(l10n.threadTitle),
                ),
                ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: Text(l10n.threadArchive),
                ),
              ],
              selected: {_archiveView},
              onSelectionChanged: (selection) =>
                  setState(() => _archiveView = selection.first),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: feedAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(child: Text('$error')),
              data: (feed) => _archiveView
                  ? _ArchiveView(feed: feed)
                  : _EventStreamView(feed: feed),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createEvent(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => const _NewEventDialog(),
    );
  }
}

/// The ranked event stream. Before the first sort it says so instead of
/// showing an arbitrary order (user annotation 12).
///
/// 顶部「全部 / 本周任务 / 本日任务」是**临时分类**（契约 §3.5，2026-11-15）：
/// 只对已经排好的 [ThreadFeed.readyTasks] 按时间窗过滤，不改排序、不写库、不新增
/// 第二份任务状态。两个时间窗都空时整条分类栏不渲染（不显示空分类）。
class _EventStreamView extends ConsumerStatefulWidget {
  const _EventStreamView({required this.feed});

  final ThreadFeed? feed;

  @override
  ConsumerState<_EventStreamView> createState() => _EventStreamViewState();
}

/// 临时分类：`all` = 原来的事件流（默认），其余两个是窗口过滤。
enum _ThreadWindowFilter { all, week, day }

class _EventStreamViewState extends ConsumerState<_EventStreamView> {
  _ThreadWindowFilter _filter = _ThreadWindowFilter.all;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final current = widget.feed;
    if (current == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sort,
                size: 40, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(l10n.threadNeedsSort),
          ],
        ),
      );
    }

    final buckets = ref.watch(threadWindowBucketsProvider);
    // 父容器的子任务汇总（只读；来自 feed 里已有的任务行，不查库不写库）。
    final rollups = ref.watch(threadRollupsProvider);
    final canFilter = buckets != null && !buckets.isEmpty;
    // 选中的窗口如果已经空了（任务被完成/删掉后重排），回落到「全部」而不是让
    // 用户看到一个空列表 + 一条已经消失的 chip。
    final effective = canFilter ? _filter : _ThreadWindowFilter.all;
    final tasks = _tasksFor(current, buckets, effective);

    return Column(
      children: [
        if (canFilter)
          _ThreadWindowFilterBar(
            selected: effective,
            buckets: buckets,
            // chips 上的进度只取"同类容器"的汇总：本周 chip 只看 week 容器、
            // 本日 chip 只看 day 容器，避免周容器锚点落在周一 0 点时被算进"本日"。
            weekRollup: threadContainerRollupOf(
              nodes: buckets.week,
              rollups: rollups,
              kind: ThreadNodeKind.week,
            ),
            dayRollup: threadContainerRollupOf(
              nodes: buckets.day,
              rollups: rollups,
              kind: ThreadNodeKind.day,
            ),
            onSelected: (filter) => setState(() => _filter = filter),
          ),
        Expanded(
          child: tasks.isEmpty
              ? Center(
                  child: Text(
                    effective == _ThreadWindowFilter.all
                        ? l10n.threadNoEvents
                        : l10n.threadWindowEmpty,
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: tasks.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) => _EventTile(
                    task: tasks[index],
                    reason: current.reasonFor(tasks[index].id),
                    // 容器行显示汇总；叶子任务没有 rollup，显示零高度。
                    rollup: rollups[tasks[index].id],
                  ),
                ),
        ),
      ],
    );
  }

  /// 分类内只做过滤，次序沿用 [ThreadFeed.readyTasks]（分类不重新排序）。
  List<Task> _tasksFor(
    ThreadFeed feed,
    ThreadWindowBuckets? buckets,
    _ThreadWindowFilter filter,
  ) {
    final nodes = switch (filter) {
      _ThreadWindowFilter.all => null,
      _ThreadWindowFilter.week => buckets?.week ?? const <ThreadWindowNode>[],
      _ThreadWindowFilter.day => buckets?.day ?? const <ThreadWindowNode>[],
    };
    if (nodes == null) {
      return feed.readyTasks;
    }
    return [
      for (final node in nodes)
        if (feed.tasks[node.id] != null) feed.tasks[node.id]!,
    ];
  }
}

/// 「全部 / 本周任务 / 本日任务」的临时分类栏；空桶不显示对应 chip。
class _ThreadWindowFilterBar extends StatelessWidget {
  const _ThreadWindowFilterBar({
    required this.selected,
    required this.buckets,
    required this.onSelected,
    this.weekRollup,
    this.dayRollup,
  });

  final _ThreadWindowFilter selected;
  final ThreadWindowBuckets buckets;
  final ValueChanged<_ThreadWindowFilter> onSelected;

  /// 「本周」chip 上的汇总进度（week 容器的子任务；null = 没有可汇总的容器）。
  final ThreadRollup? weekRollup;

  /// 「本日」chip 上的汇总进度（day 容器的子任务；null = 没有可汇总的容器）。
  final ThreadRollup? dayRollup;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Tooltip(
      message: l10n.threadWindowTemporary,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        child: Row(
          children: [
            _chip(context, l10n.threadWindowAll, _ThreadWindowFilter.all, null),
            if (buckets.week.isNotEmpty)
              _chip(
                context,
                l10n.threadWindowWeek,
                _ThreadWindowFilter.week,
                weekRollup,
              ),
            if (buckets.day.isNotEmpty)
              _chip(
                context,
                l10n.threadWindowDay,
                _ThreadWindowFilter.day,
                dayRollup,
              ),
          ],
        ),
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    String label,
    _ThreadWindowFilter filter,
    ThreadRollup? rollup,
  ) =>
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          // chip 文字保持原样（测试与用户都按这个名字找）；汇总进度是紧挨着的
          // 第二段文字，没有可汇总的容器时完全不出现。
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label),
              if (rollup != null && !rollup.isEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  AppLocalizations.of(context)
                      .threadRollupDoneOf(rollup.counts.done, rollup.counts.total),
                  key: ValueKey('thread-window-rollup-${filter.name}'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ),
          selected: selected == filter,
          onSelected: (_) => onSelected(filter),
        ),
      );
}

class _EventTile extends ConsumerWidget {
  const _EventTile({required this.task, this.reason, this.rollup});

  final Task task;

  /// Segment B's "why is it here" line, when segment B produced one.
  ///
  /// The text comes from the ranking layer (`BalancedTask.reasonZh`) and is
  /// Chinese-only today: the domain layer owns the wording, so the sentence can
  /// never disagree with the number it explains. Localising it is a later round
  /// (it would move the wording, not the rule).
  final String? reason;

  /// 这个节点作为父容器时的子任务汇总（只读）；叶子任务为 null。
  ///
  /// 只有在本周/本日分类里容器行会出现在列表里（`readyTasks` 不含 week/day
  /// 容器），所以这行进度也只在这些视图里可见。
  final ThreadRollup? rollup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = ThreadStatus.of(task, DateTime.now());
    // v47 流程状态（todo/doing/done/blocked/skipped）；和上面那个「边缘色」状态
    // 是两套词表：这里决定"哪些动作此刻可用"，不参与颜色。
    final flowStatus = taskFlowStatus(task);
    final reasonText = reason;
    final details = <String>[
      if (task.estimateMinutes != null) '${task.estimateMinutes} min',
      if (task.energyRequired != null)
        '${l10n.threadEnergy} ${task.energyRequired}',
      if (task.dueAt != null) _formatMoment(task.dueAt!),
    ];

    // Swipe or menu to delete (user feedback item 4: there was no delete).
    return Dismissible(
      key: ValueKey('event-${task.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: theme.colorScheme.errorContainer,
        child: Icon(Icons.delete_outline,
            color: theme.colorScheme.onErrorContainer),
      ),
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) => _delete(ref),
      child: InkWell(
        onTap: () => openEventProperties(context, task),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          child: Row(
            children: [
              ThreadStatusEdge(status: status),
              const SizedBox(width: 10),
              IconButton(
                tooltip: l10n.commonConfirm,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.radio_button_unchecked),
                color: theme.colorScheme.primary,
                // 完成只允许 todo/doing（writer 状态机）：窗口分类里的 blocked
                // 行不能从这里"完成"，否则会抛非法迁移。
                onPressed:
                    flowStatus.isSchedulable ? () => _complete(context, ref) : null,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge,
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        details.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (rollup != null && !rollup!.isEmpty) ...[
                      const SizedBox(height: 2),
                      ThreadRollupProgressLine(
                        key: ValueKey('thread-rollup-line-${task.id}'),
                        rollup: rollup!,
                      ),
                    ],
                    if (reasonText != null && reasonText.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.lightbulb_outline,
                            size: 13,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              reasonText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                key: ValueKey('event-actions-${task.id}'),
                tooltip: l10n.commonEdit,
                icon: const Icon(Icons.more_vert),
                onSelected: (value) async {
                  switch (value) {
                    // 提交 / 卡住 / 跳过 / 恢复：走 TaskRepository →
                    // ThreadFlowWriter；每个动作都先二次确认（见
                    // task_status_actions.dart）。
                    case 'submitted':
                      await _runStatusAction(context, ref,
                          TaskStatusAction.submit);
                    case 'stuck':
                      await _runStatusAction(context, ref,
                          TaskStatusAction.stuck);
                    case 'skipped':
                      await _runStatusAction(context, ref,
                          TaskStatusAction.skip);
                    case 'reopened':
                      await _runStatusAction(context, ref,
                          TaskStatusAction.reopen);
                    case 'properties':
                      await openEventProperties(context, task);
                    case 'delete':
                      if (await _confirmDelete(context) == true) {
                        await _delete(ref);
                      }
                  }
                },
                itemBuilder: (context) => [
                  for (final action in TaskStatusAction.values)
                    PopupMenuItem(
                      value: action.eventKind.id,
                      enabled: action.allowedFrom(flowStatus),
                      child: Text(action.label(l10n)),
                    ),
                  PopupMenuItem(
                    value: 'properties',
                    child: Text(l10n.commonEdit),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(l10n.commonDelete),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatMoment(int millis) {
    final moment = DateTime.fromMillisecondsSinceEpoch(millis);
    final two = (int value) => value.toString().padLeft(2, '0');
    return '${two(moment.month)}-${two(moment.day)} ${two(moment.hour)}:${two(moment.minute)}';
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.threadDeleteTitle(task.title)),
        content: Text(l10n.threadDeleteBody),
        actions: [
          IconButton(
            tooltip: l10n.commonCancel,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          IconButton.filled(
            tooltip: l10n.commonDelete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(WidgetRef ref) async {
    await ref.read(taskRepositoryProvider).deleteTask(task.id);
    await ref.read(threadFeedProvider.notifier).sort();
  }

  /// 提交 / 卡住 / 跳过 / 恢复：确认 + 写库交给共享入口，成功后重排事件流。
  ///
  /// 跳过会让这一行退出 ready 列表、恢复会让它回到 ready；数据修订订阅本来也会
  /// 触发一次重排，这里显式再排一次是为了让"用户刚点的动作"立刻生效，而不是等
  /// 下一个微任务。
  Future<void> _runStatusAction(
    BuildContext context,
    WidgetRef ref,
    TaskStatusAction action,
  ) async {
    final changed = await runTaskStatusAction(
      context,
      ref,
      task: task,
      action: action,
    );
    if (changed) {
      await ref.read(threadFeedProvider.notifier).sort();
    }
  }

  Future<void> _complete(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(taskRepositoryProvider);
    final tags = await ref.read(tagRepositoryProvider).tagsForObject(
          objectType: 'task',
          objectId: task.id,
        );
    final useActualTime =
        await ref.read(threadRankRepositoryProvider).getUseActualTime();
    // Completing is the only place the "start" stamp matters: an event that
    // was never started still completes, it simply records no actual duration.
    if (task.startedAt == null) {
      await repo.startTask(task.id,
          at: DateTime.now()
              .subtract(Duration(minutes: task.estimateMinutes ?? 0)));
    }
    await repo.completeTask(
      task.id,
      tagIds: [for (final tag in tags) tag.id],
      tagPaths: [
        for (final tag in tags)
          if (tag.path != null) tag.path!,
      ],
      useActualTime: useActualTime,
    );
    await ref.read(threadFeedProvider.notifier).sort();
  }
}

/// Completed + not-enough-time + overdue + 卡住/跳过 (user annotations 5 and 11;
/// 卡住/跳过段是 task-90 加的「恢复」落点).
class _ArchiveView extends ConsumerWidget {
  const _ArchiveView({required this.feed});

  final ThreadFeed? feed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = feed;
    if (current == null) {
      return Center(child: Text(l10n.threadArchiveEmpty));
    }

    final completed = current.completedTasks;
    final insufficient = current.ranked.insufficient;
    final overdue = current.ranked.overdue;
    // 卡住/跳过既不在 ready（它们不是待办），也不在完成历史里；归档视图就是
    // "离开 ready 的节点"的落点，所以在这里给它们一行 + 一个显式「恢复」。
    // 排序用 `updated_at` 倒序：最近被卡住/跳过的最可能需要恢复。
    final parked = <Task>[
      for (final task in current.tasks.values)
        if (_isParked(task)) task,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    if (completed.isEmpty &&
        insufficient.isEmpty &&
        overdue.isEmpty &&
        parked.isEmpty) {
      return Center(child: Text(l10n.threadArchiveEmpty));
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (parked.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.inventory_2_outlined,
            color: ThreadStatus.expectedPassed.color,
            title: l10n.tasksStatusSectionArchived,
          ),
          for (final task in parked)
            _ArchivedTile(
              title: task.title,
              // 真正的流程状态写在副标题；边缘色沿用"时间已过"的黄色（UI 的
              // `ThreadStatus` 只表达时间 lifecycle，不表达 blocked/skipped）。
              subtitle: taskStatusLabel(l10n, task),
              status: ThreadStatus.expectedPassed,
              task: task,
              restorable: true,
            ),
        ],
        if (insufficient.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.hourglass_disabled,
            color: ThreadStatus.deadlinePassed.color,
            title: l10n.threadArchiveInsufficient,
          ),
          for (final ranked in insufficient)
            _ArchivedTile(
              title: ranked.event.title,
              subtitle: l10n.threadInsufficientDetail(
                ranked.neededMinutes?.toString() ?? '-',
                ranked.availableMinutes?.toString() ?? '-',
              ),
              status: ThreadStatus.deadlinePassed,
              task: current.taskFor(ranked.event.id),
            ),
        ],
        if (overdue.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.event_busy,
            color: ThreadStatus.deadlinePassed.color,
            title: l10n.threadArchiveOverdue,
          ),
          for (final ranked in overdue)
            _ArchivedTile(
              title: ranked.event.title,
              status: ThreadStatus.deadlinePassed,
              task: current.taskFor(ranked.event.id),
            ),
        ],
        if (completed.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.check_circle_outline,
            color: ThreadStatus.completed.color,
            title: l10n.threadArchiveCompleted,
          ),
          for (final task in completed)
            _ArchivedTile(
              title: task.title,
              status: ThreadStatus.completed,
              task: task,
              done: true,
            ),
        ],
      ],
    );
  }
}

/// 卡住/跳过：两个"离开待办但不是完成"的流程状态（`ThreadFlow` 词表）。
bool _isParked(Task task) {
  final status = taskFlowStatus(task);
  return status == flow.ThreadStatus.blocked ||
      status == flow.ThreadStatus.skipped;
}

/// One archived row: same coloured edge as the main list, plus the two actions
/// that make the archive useful (edit / delete) and, for blocked/skipped rows,
/// the explicit restore entry (task-90).
class _ArchivedTile extends ConsumerWidget {
  const _ArchivedTile({
    required this.title,
    required this.status,
    required this.task,
    this.subtitle,
    this.done = false,
    this.restorable = false,
  });

  final String title;
  final ThreadStatus status;
  final Task? task;
  final String? subtitle;
  final bool done;

  /// true = 这一行是卡住/跳过，给出「恢复」（`reopened` 事件，二次确认）。
  final bool restorable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Dismissible(
      key: ValueKey('archived-$title-${task?.id ?? ''}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: theme.colorScheme.errorContainer,
        child: Icon(Icons.delete_outline,
            color: theme.colorScheme.onErrorContainer),
      ),
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.threadDeleteTitle(title)),
          content: Text(l10n.threadDeleteBody),
          actions: [
            IconButton(
              tooltip: l10n.commonCancel,
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            IconButton.filled(
              tooltip: l10n.commonDelete,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
      onDismissed: (_) async {
        final id = task?.id;
        if (id == null) {
          return;
        }
        await ref.read(taskRepositoryProvider).deleteTask(id);
        await ref.read(threadFeedProvider.notifier).sort();
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        child: Row(
          children: [
            ThreadStatusEdge(status: status, height: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      decoration: done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (task != null && restorable)
              IconButton(
                key: ValueKey('archived-restore-${task!.id}'),
                tooltip: l10n.tasksReopen,
                icon: const Icon(Icons.undo),
                onPressed: () async {
                  final changed = await runTaskStatusAction(
                    context,
                    ref,
                    task: task!,
                    action: TaskStatusAction.reopen,
                  );
                  if (changed) {
                    await ref.read(threadFeedProvider.notifier).sort();
                  }
                },
              ),
            if (task != null)
              IconButton(
                tooltip: l10n.commonEdit,
                icon: const Icon(Icons.tune),
                onPressed: () => openEventProperties(context, task!),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.color,
    required this.title,
  });

  final IconData icon;
  final Color color;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Minimal creation dialog: title + estimate + energy. The rest of the
/// parameters live in the property page, where each one is explained.
class _NewEventDialog extends ConsumerStatefulWidget {
  const _NewEventDialog();

  @override
  ConsumerState<_NewEventDialog> createState() => _NewEventDialogState();
}

class _NewEventDialogState extends ConsumerState<_NewEventDialog> {
  final _title = TextEditingController();
  final _estimate = TextEditingController();
  int? _energy;

  @override
  void dispose() {
    _title.dispose();
    _estimate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.tasksNewTask),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l10n.commonTitle,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _estimate,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            // Enter saves, so creating an event never needs the mouse.
            onSubmitted: (_) => _save(ref),
            decoration: InputDecoration(
              labelText: l10n.tasksEstimateMinutes,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(l10n.threadEnergy),
              const Spacer(),
              SizedBox(
                width: 220,
                child: Slider(
                  value: (_energy ?? 5).toDouble(),
                  min: EnergyColors.min.toDouble(),
                  max: EnergyColors.max.toDouble(),
                  divisions: EnergyColors.max - EnergyColors.min,
                  activeColor: EnergyColors.of(_energy ?? 5),
                  label: '${_energy ?? 5}',
                  onChanged: (v) => setState(() => _energy = v.round()),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _energy = null),
                child: Text(l10n.commonClear),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: l10n.commonCancel,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        IconButton.filled(
          tooltip: l10n.commonSave,
          icon: const Icon(Icons.check),
          onPressed: _title.text.trim().isEmpty ? null : () => _save(ref),
        ),
      ],
    );
  }

  /// Shared by the check button and the Enter key.
  Future<void> _save(WidgetRef ref) async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      return;
    }
    await ref.read(taskRepositoryProvider).createTask(
          title: title,
          estimateMinutes: int.tryParse(_estimate.text.trim()),
          energyRequired: _energy,
        );
    await ref.read(threadFeedProvider.notifier).sort();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}

/// The thread page's view menu: the attention-hint switch (kept in the app bar so
/// hiding the reading on the status bar itself is undoable even when no event is
/// in focus) and the cognitive-order switch (roadmap §2-D).
///
/// The check marks show the persisted choices; NULL for the rhythm hint (never
/// chosen) reads as on, which is the shipped default (`docs/MINDNET_ROADMAP.md`
/// §3 row 4), while the cognitive order defaults to off on purpose: its boosts
/// are all uncalibrated, so it must not replace the list the user is used to
/// without being asked.
class _ThreadMenu extends ConsumerWidget {
  const _ThreadMenu({required this.rhythmText, required this.cognitiveText});

  final String rhythmText;
  final String cognitiveText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rhythmEnabled =
        ref.watch(rhythmHintsEnabledProvider).valueOrNull ?? true;
    final cognitiveEnabled =
        ref.watch(cognitiveRankEnabledProvider).valueOrNull ?? false;
    return PopupMenuButton<_ThreadMenuItem>(
      tooltip: rhythmText,
      icon: const Icon(Icons.more_vert),
      onSelected: (item) async {
        switch (item) {
          case _ThreadMenuItem.rhythm:
            await ref
                .read(settingsRepositoryProvider)
                .updateRhythmHintsEnabled(!rhythmEnabled);
            ref.invalidate(rhythmHintsEnabledProvider);
            ref.invalidate(studyRhythmProvider);
          case _ThreadMenuItem.cognitive:
            await ref
                .read(threadRankRepositoryProvider)
                .setCognitiveRankEnabled(!cognitiveEnabled);
            ref.invalidate(cognitiveRankEnabledProvider);
            // 开关一翻，用户期待的是"现在"的次序就变：直接重排一次，不
            // 等下一次数据变化（`sort()` 自己会重新读开关与素材）。
            await ref.read(threadFeedProvider.notifier).sort();
        }
      },
      itemBuilder: (context) => [
        CheckedPopupMenuItem<_ThreadMenuItem>(
          value: _ThreadMenuItem.rhythm,
          checked: rhythmEnabled,
          child: Text(rhythmText),
        ),
        CheckedPopupMenuItem<_ThreadMenuItem>(
          value: _ThreadMenuItem.cognitive,
          checked: cognitiveEnabled,
          child: Text(cognitiveText),
        ),
      ],
    );
  }
}

enum _ThreadMenuItem { rhythm, cognitive }

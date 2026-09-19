import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../application/thread_rank_service.dart';
import 'event_properties_page.dart';
import 'widgets/energy_colors.dart';
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
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final feedAsync = ref.watch(threadFeedProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.threadTitle),
        actions: [
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
class _EventStreamView extends ConsumerWidget {
  const _EventStreamView({required this.feed});

  final ThreadFeed? feed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = feed;
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
    final tasks = current.readyTasks;
    if (tasks.isEmpty) {
      return Center(child: Text(l10n.threadNoEvents));
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: tasks.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) => _EventTile(task: tasks[index]),
    );
  }
}

class _EventTile extends ConsumerWidget {
  const _EventTile({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = ThreadStatus.of(task, DateTime.now());
    final details = <String>[
      if (task.estimateMinutes != null) '${task.estimateMinutes} min',
      if (task.energyRequired != null) '${l10n.threadEnergy} ${task.energyRequired}',
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
        child: Icon(Icons.delete_outline, color: theme.colorScheme.onErrorContainer),
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
                onPressed: () => _complete(context, ref),
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
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: l10n.commonEdit,
                icon: const Icon(Icons.more_vert),
                onSelected: (value) async {
                  switch (value) {
                    case 'properties':
                      await openEventProperties(context, task);
                    case 'delete':
                      if (await _confirmDelete(context) == true) {
                        await _delete(ref);
                      }
                  }
                },
                itemBuilder: (context) => [
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
          at: DateTime.now().subtract(Duration(minutes: task.estimateMinutes ?? 0)));
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

/// Completed + not-enough-time + overdue (user annotations 5 and 11).
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

    if (completed.isEmpty && insufficient.isEmpty && overdue.isEmpty) {
      return Center(child: Text(l10n.threadArchiveEmpty));
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
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

/// One archived row: same coloured edge as the main list, plus the two actions
/// that make the archive useful (edit / delete).
class _ArchivedTile extends ConsumerWidget {
  const _ArchivedTile({
    required this.title,
    required this.status,
    required this.task,
    this.subtitle,
    this.done = false,
  });

  final String title;
  final ThreadStatus status;
  final Task? task;
  final String? subtitle;
  final bool done;

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
        child:
            Icon(Icons.delete_outline, color: theme.colorScheme.onErrorContainer),
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

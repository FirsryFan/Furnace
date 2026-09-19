import 'package:flutter/material.dart';
import 'package:knowflow/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../tasks/application/task_scheduler_providers.dart';

final timeBlocksProvider = FutureProvider<List<TimeBlock>>((ref) {
  return ref.watch(timeBlockRepositoryProvider).getTimeBlocks();
});

final timeBlockTasksProvider =
    FutureProvider.family<List<Task>, String>((ref, timeBlockId) {
  return ref.watch(taskRepositoryProvider).getTasksForTimeBlock(timeBlockId);
});

class _ScheduleEntry {
  const _ScheduleEntry({required this.block, required this.tasks});

  final TimeBlock block;
  final List<Task> tasks;
}

final timeBlockScheduleProvider = FutureProvider<List<_ScheduleEntry>>((ref) async {
  final blocks = await ref.watch(timeBlockRepositoryProvider).getTimeBlocks();
  final entries = <_ScheduleEntry>[];
  for (final block in blocks) {
    final tasks = await ref.watch(taskRepositoryProvider).getTasksForTimeBlock(block.id);
    if (tasks.isNotEmpty) {
      entries.add(_ScheduleEntry(block: block, tasks: tasks));
    }
  }
  entries.sort((a, b) => a.block.startAt.compareTo(b.block.startAt));
  return entries;
});

/// Time board module: list and create time blocks.
///
/// [embedded] drops the module-level AppBar when the page is shown as one tab
/// of the Time module (the calendar owns the module chrome).
class TimeBoardPage extends ConsumerWidget {
  const TimeBoardPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final blocksAsync = ref.watch(timeBlocksProvider);
    final scheduleAsync = ref.watch(timeBlockScheduleProvider);

    return Scaffold(
      appBar: embedded
          ? null
          : AppBar(
              title: Text(l10n.navTime),
              actions: [
                IconButton(
                  tooltip: l10n.timeNewBlock,
                  icon: const Icon(Icons.add),
                  onPressed: () => _createTimeBlock(context, ref),
                ),
              ],
            ),
      floatingActionButton: embedded
          ? FloatingActionButton(
              tooltip: l10n.timeNewBlock,
              onPressed: () => _createTimeBlock(context, ref),
              child: const Icon(Icons.add),
            )
          : null,
      body: blocksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('$error')),
        data: (blocks) {
          if (blocks.isEmpty) {
            return Center(
              child: FilledButton.icon(
                onPressed: () => _createTimeBlock(context, ref),
                icon: const Icon(Icons.add),
                label: Text(l10n.timeNewBlock),
              ),
            );
          }
          final scheduleEntries =
              scheduleAsync.valueOrNull ?? const <_ScheduleEntry>[];
          return ListView(
            children: [
              if (scheduleEntries.isNotEmpty)
                Card(
                  margin: const EdgeInsets.all(8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.timeTodaySchedule,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        for (final entry in scheduleEntries)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.task_alt),
                            title: Text(
                              entry.tasks.map((t) => t.title).join(', '),
                            ),
                            subtitle: Text(
                              '${_formatTime(entry.block.startAt)} - '
                              '${_formatTime(entry.block.endAt)}',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              for (final block in blocks) ...[
                Builder(
                  builder: (context) {
                    final linkedTasksAsync = ref.watch(
                      timeBlockTasksProvider(block.id),
                    );
                    final linkedTasks =
                        linkedTasksAsync.valueOrNull ?? const <Task>[];
                    return ListTile(
                      leading: const Icon(Icons.schedule),
                      title: Text(block.title),
                      subtitle: Text(
                        '${_formatTime(block.startAt)} - '
                        '${_formatTime(block.endAt)}'
                        '${block.available ? '' : ' · ${l10n.timeUnavailable}'}'
                        '${linkedTasks.isEmpty ? '' : '\n${linkedTasks.map((t) => t.title).join(', ')}'}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: l10n.commonEdit,
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () =>
                                _editTimeBlock(context, ref, block),
                          ),
                          Switch(
                            value: block.available,
                            onChanged: (value) =>
                                _setAvailable(context, ref, block, value),
                          ),
                          IconButton(
                            tooltip: l10n.commonDelete,
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () =>
                                _deleteTimeBlock(context, ref, block.id),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  String _formatTime(int millis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Future<void> _createTimeBlock(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final titleController = TextEditingController();
    final now = TimeOfDay.now();
    var start = now;
    var end = TimeOfDay(hour: (now.hour + 1) % 24, minute: now.minute);
    String energy = 'medium';
    String suitable = 'memorize';

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l10n.timeNewBlock),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                autofocus: true,
                decoration: InputDecoration(labelText: l10n.commonTitle),
              ),
              const SizedBox(height: 12),
              ListTile(
                title: Text('${l10n.commonStart}: ${start.format(context)}'),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: start,
                  );
                  if (picked != null) {
                    setState(() => start = picked);
                  }
                },
              ),
              ListTile(
                title: Text('${l10n.commonEnd}: ${end.format(context)}'),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: end,
                  );
                  if (picked != null) {
                    setState(() => end = picked);
                  }
                },
              ),
              DropdownButtonFormField<String>(
                value: energy,
                decoration: InputDecoration(labelText: l10n.timeEnergy),
                items: [
                  DropdownMenuItem(value: '', child: Text(l10n.timeNone)),
                  DropdownMenuItem(
                      value: 'high', child: Text(l10n.timeEnergyHigh)),
                  DropdownMenuItem(
                      value: 'medium', child: Text(l10n.timeEnergyMedium)),
                  DropdownMenuItem(
                      value: 'low', child: Text(l10n.timeEnergyLow)),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => energy = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: suitable,
                decoration: InputDecoration(labelText: l10n.timeSuitable),
                items: [
                  DropdownMenuItem(value: '', child: Text(l10n.timeNone)),
                  DropdownMenuItem(
                      value: 'memorize',
                      child: Text(l10n.timeSuitableMemorize)),
                  DropdownMenuItem(
                      value: 'deep_work',
                      child: Text(l10n.timeSuitableDeepWork)),
                  DropdownMenuItem(
                      value: 'review',
                      child: Text(l10n.timeSuitableReview)),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => suitable = value);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.commonSave),
            ),
          ],
        ),
      ),
    );

    if (saved != true) {
      return;
    }
    final title = titleController.text.trim();
    if (title.isEmpty) {
      return;
    }
    final today = DateTime.now();
    final startMillis = DateTime(
      today.year,
      today.month,
      today.day,
      start.hour,
      start.minute,
    ).millisecondsSinceEpoch;
    final endMillis = DateTime(
      today.year,
      today.month,
      today.day,
      end.hour,
      end.minute,
    ).millisecondsSinceEpoch;

    await ref.read(timeBlockRepositoryProvider).createTimeBlock(
          title: title,
          startAt: startMillis,
          endAt: endMillis,
          energy: energy.isEmpty ? null : energy,
          suitableFor: suitable.isEmpty ? null : suitable,
        );
    ref.invalidate(timeBlocksProvider);
    ref.invalidate(scheduleSuggestionsProvider);
  }

  Future<void> _editTimeBlock(
    BuildContext context,
    WidgetRef ref,
    TimeBlock block,
  ) async {
    final l10n = AppLocalizations.of(context);
    final titleController = TextEditingController(text: block.title);
    final startDt = DateTime.fromMillisecondsSinceEpoch(block.startAt);
    final endDt = DateTime.fromMillisecondsSinceEpoch(block.endAt);
    var start = TimeOfDay.fromDateTime(startDt);
    var end = TimeOfDay.fromDateTime(endDt);
    var available = block.available;
    var energy = block.energy ?? '';
    var suitable = block.suitableFor ?? '';
    var blockTags = await ref
        .read(tagRepositoryProvider)
        .tagsForObject(objectType: 'time_block', objectId: block.id);

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l10n.commonEdit),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                autofocus: true,
                decoration: InputDecoration(labelText: l10n.commonTitle),
              ),
              const SizedBox(height: 12),
              ListTile(
                title: Text('${l10n.commonStart}: ${start.format(context)}'),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: start,
                  );
                  if (picked != null) {
                    setState(() => start = picked);
                  }
                },
              ),
              ListTile(
                title: Text('${l10n.commonEnd}: ${end.format(context)}'),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: end,
                  );
                  if (picked != null) {
                    setState(() => end = picked);
                  }
                },
              ),
              DropdownButtonFormField<String>(
                value: energy,
                decoration: InputDecoration(labelText: l10n.timeEnergy),
                items: [
                  DropdownMenuItem(value: '', child: Text(l10n.timeNone)),
                  DropdownMenuItem(
                      value: 'high', child: Text(l10n.timeEnergyHigh)),
                  DropdownMenuItem(
                      value: 'medium', child: Text(l10n.timeEnergyMedium)),
                  DropdownMenuItem(
                      value: 'low', child: Text(l10n.timeEnergyLow)),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => energy = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: suitable,
                decoration: InputDecoration(labelText: l10n.timeSuitable),
                items: [
                  DropdownMenuItem(value: '', child: Text(l10n.timeNone)),
                  DropdownMenuItem(
                      value: 'memorize',
                      child: Text(l10n.timeSuitableMemorize)),
                  DropdownMenuItem(
                      value: 'deep_work',
                      child: Text(l10n.timeSuitableDeepWork)),
                  DropdownMenuItem(
                      value: 'review',
                      child: Text(l10n.timeSuitableReview)),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => suitable = value);
                  }
                },
              ),
              Row(
                children: [
                  Text(
                    l10n.tagsTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: l10n.commonAdd,
                    icon: const Icon(Icons.add),
                    onPressed: () async {
                      final allTags = await ref
                          .read(tagRepositoryProvider)
                          .getAllTags();
                      final existingIds = blockTags.map((t) => t.id).toSet();
                      final candidates = allTags
                          .where((t) => !existingIds.contains(t.id))
                          .toList();
                      if (candidates.isEmpty) {
                        return;
                      }
                      final selected = await showDialog<Tag>(
                        context: context,
                        builder: (ctx) => SimpleDialog(
                          title: Text(l10n.tagsTitle),
                          children: [
                            for (final tag in candidates)
                              SimpleDialogOption(
                                onPressed: () => Navigator.pop(ctx, tag),
                                child: Text(tag.name),
                              ),
                          ],
                        ),
                      );
                      if (selected != null) {
                        await ref
                            .read(tagRepositoryProvider)
                            .addTagToObject(
                              tagId: selected.id,
                              objectType: 'time_block',
                              objectId: block.id,
                            );
                        setState(() {
                          blockTags = [...blockTags, selected];
                        });
                      }
                    },
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final tag in blockTags)
                    Chip(
                      label: Text(tag.name),
                      onDeleted: () async {
                        await ref
                            .read(tagRepositoryProvider)
                            .removeTagFromObject(
                              tagId: tag.id,
                              objectType: 'time_block',
                              objectId: block.id,
                            );
                        setState(() {
                          blockTags = [
                            for (final t in blockTags)
                              if (t.id != tag.id) t,
                          ];
                        });
                      },
                    ),
                ],
              ),
              SwitchListTile(
                title: Text(l10n.timeAvailable),
                value: available,
                onChanged: (value) => setState(() => available = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.commonSave),
            ),
          ],
        ),
      ),
    );

    if (saved != true) {
      return;
    }
    final title = titleController.text.trim();
    if (title.isEmpty) {
      return;
    }
    final today = DateTime.now();
    final startMillis = DateTime(
      today.year,
      today.month,
      today.day,
      start.hour,
      start.minute,
    ).millisecondsSinceEpoch;
    final endMillis = DateTime(
      today.year,
      today.month,
      today.day,
      end.hour,
      end.minute,
    ).millisecondsSinceEpoch;

    await ref.read(timeBlockRepositoryProvider).updateTimeBlock(
          block.id,
          title: title,
          startAt: startMillis,
          endAt: endMillis,
          available: available,
          energy: energy.isEmpty ? null : energy,
          suitableFor: suitable.isEmpty ? null : suitable,
        );
    ref.invalidate(timeBlocksProvider);
    ref.invalidate(scheduleSuggestionsProvider);
  }

  Future<void> _setAvailable(
    BuildContext context,
    WidgetRef ref,
    TimeBlock block,
    bool value,
  ) async {
    await ref.read(timeBlockRepositoryProvider).updateTimeBlock(
          block.id,
          available: value,
        );
    ref.invalidate(timeBlocksProvider);
    ref.invalidate(scheduleSuggestionsProvider);
  }

  Future<void> _deleteTimeBlock(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    await ref.read(timeBlockRepositoryProvider).deleteTimeBlock(id);
    ref.invalidate(timeBlocksProvider);
    ref.invalidate(scheduleSuggestionsProvider);
  }
}

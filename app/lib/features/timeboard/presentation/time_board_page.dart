import 'package:flutter/material.dart';
import 'package:furnace/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/database/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/tags/tag_usage.dart';
import '../../tags/application/tag_usage_providers.dart';
import '../../tasks/application/task_scheduler_providers.dart';

final timeBlocksProvider = FutureProvider<List<TimeBlock>>((ref) {
  ref.watchDatabaseRevision();
  return ref.watch(timeBlockRepositoryProvider).getTimeBlocks();
});

final timeBlockTasksProvider =
    FutureProvider.family<List<Task>, String>((ref, timeBlockId) {
  ref.watchDatabaseRevision();
  return ref.watch(taskRepositoryProvider).getTasksForTimeBlock(timeBlockId);
});

class _ScheduleEntry {
  const _ScheduleEntry({required this.block, required this.tasks});

  final TimeBlock block;
  final List<Task> tasks;
}

final timeBlockScheduleProvider =
    FutureProvider<List<_ScheduleEntry>>((ref) async {
  ref.watchDatabaseRevision();
  final blocks = await ref.watch(timeBlockRepositoryProvider).getTimeBlocks();
  final entries = <_ScheduleEntry>[];
  for (final block in blocks) {
    final tasks =
        await ref.watch(taskRepositoryProvider).getTasksForTimeBlock(block.id);
    if (tasks.isNotEmpty) {
      entries.add(_ScheduleEntry(block: block, tasks: tasks));
    }
  }
  entries.sort((a, b) => a.block.startAt.compareTo(b.block.startAt));
  return entries;
});

/// Keys the tests use to reach the board's filter row and its empty states.
const Key timeBoardFilterAllKey = Key('time-board-filter-all');
const Key timeBoardFilterTodayKey = Key('time-board-filter-today');
const Key timeBoardTodayEmptyKey = Key('time-board-today-empty');
const Key timeBoardEmptyActionKey = Key('time-board-empty-action');
const Key timeBoardTodayEmptyActionKey = Key('time-board-today-empty-action');

/// What the board lists right now.
enum TimeBoardFilter {
  /// Every block, whenever it falls.
  all,

  /// Only blocks overlapping today in the device's local time zone.
  today,
}

/// The local instant at which the calendar day containing [now] starts.
///
/// Built through the [DateTime] constructor instead of subtracting
/// [Duration]s, so 23- or 25-hour days (DST) still get correct boundaries.
DateTime timeBoardDayStart(DateTime now) =>
    DateTime(now.year, now.month, now.day);

/// Whether [block] overlaps the local day that starts at [dayStart].
///
/// Both ends are half-open: a block ending exactly at midnight belongs to the
/// day that just ended, one starting exactly at midnight to the day that just
/// began, and a block spanning midnight overlaps both days.
bool timeBlockOverlapsDay(TimeBlock block, DateTime dayStart) {
  final dayEnd = DateTime(dayStart.year, dayStart.month, dayStart.day + 1);
  return block.startAt < dayEnd.millisecondsSinceEpoch &&
      block.endAt > dayStart.millisecondsSinceEpoch;
}

/// [blocks] overlapping the day that starts at [dayStart], in argument order.
List<TimeBlock> timeBlocksForDay(List<TimeBlock> blocks, DateTime dayStart) {
  return [
    for (final block in blocks)
      if (timeBlockOverlapsDay(block, dayStart)) block,
  ];
}

/// Time board module: list and create time blocks.
///
/// [embedded] drops the module-level AppBar when the page is shown as one tab
/// of the Time module (the calendar owns the module chrome).
class TimeBoardPage extends ConsumerStatefulWidget {
  const TimeBoardPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<TimeBoardPage> createState() => _TimeBoardPageState();
}

class _TimeBoardPageState extends ConsumerState<TimeBoardPage> {
  /// The filter is how the board is being read right now, not a stored
  /// preference: every visit starts on "all".
  TimeBoardFilter _filter = TimeBoardFilter.all;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final blocksAsync = ref.watch(timeBlocksProvider);
    final scheduleAsync = ref.watch(timeBlockScheduleProvider);

    return Scaffold(
      appBar: widget.embedded
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
      floatingActionButton: widget.embedded
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
            // Nothing at all is a different state from nothing today: a
            // filter would only ever return the same empty list, so it is not
            // offered and the original empty state stays.
            return Center(
              child: FilledButton.icon(
                key: timeBoardEmptyActionKey,
                onPressed: () => _createTimeBlock(context, ref),
                icon: const Icon(Icons.add),
                label: Text(l10n.timeNewBlock),
              ),
            );
          }
          final dayStart = timeBoardDayStart(DateTime.now());
          final todayOnly = _filter == TimeBoardFilter.today;
          final visibleBlocks =
              todayOnly ? timeBlocksForDay(blocks, dayStart) : blocks;
          final scheduleEntries = [
            for (final entry
                in scheduleAsync.valueOrNull ?? const <_ScheduleEntry>[])
              if (!todayOnly || timeBlockOverlapsDay(entry.block, dayStart))
                entry,
          ];
          return ListView(
            children: [
              _buildFilterRow(l10n),
              if (visibleBlocks.isEmpty)
                _buildTodayEmpty(l10n)
              else ...[
                if (scheduleEntries.isNotEmpty)
                  _buildScheduleCard(context, l10n, scheduleEntries),
                for (final block in visibleBlocks)
                  _buildBlockTile(context, l10n, block),
              ],
            ],
          );
        },
      ),
    );
  }

  /// The "all / today" switch. Only offered once at least one block exists.
  Widget _buildFilterRow(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            key: timeBoardFilterAllKey,
            label: Text(l10n.timeBoardFilterAll),
            selected: _filter == TimeBoardFilter.all,
            onSelected: (_) => setState(() => _filter = TimeBoardFilter.all),
          ),
          ChoiceChip(
            key: timeBoardFilterTodayKey,
            label: Text(l10n.timeBoardFilterToday),
            selected: _filter == TimeBoardFilter.today,
            onSelected: (_) => setState(() => _filter = TimeBoardFilter.today),
          ),
        ],
      ),
    );
  }

  /// "Nothing today" is not "nothing at all": blocks exist, they just fall
  /// on other days. Keep the create action next to the message.
  Widget _buildTodayEmpty(AppLocalizations l10n) {
    return Padding(
      key: timeBoardTodayEmptyKey,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.event_available_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(l10n.timeBoardTodayEmpty),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: timeBoardTodayEmptyActionKey,
            onPressed: () => _createTimeBlock(context, ref),
            icon: const Icon(Icons.add),
            label: Text(l10n.timeNewBlock),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleCard(
    BuildContext context,
    AppLocalizations l10n,
    List<_ScheduleEntry> scheduleEntries,
  ) {
    return Card(
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
                title: Text(entry.tasks.map((t) => t.title).join(', ')),
                subtitle: Text(
                  '${_formatTime(entry.block.startAt)} - '
                  '${_formatTime(entry.block.endAt)}',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockTile(
    BuildContext context,
    AppLocalizations l10n,
    TimeBlock block,
  ) {
    final linkedTasksAsync = ref.watch(timeBlockTasksProvider(block.id));
    final linkedTasks = linkedTasksAsync.valueOrNull ?? const <Task>[];
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
            onPressed: () => _editTimeBlock(context, ref, block),
          ),
          Switch(
            value: block.available,
            onChanged: (value) => _setAvailable(context, ref, block, value),
          ),
          IconButton(
            tooltip: l10n.commonDelete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _deleteTimeBlock(context, ref, block.id),
          ),
        ],
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
                      value: 'review', child: Text(l10n.timeSuitableReview)),
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
                      value: 'review', child: Text(l10n.timeSuitableReview)),
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
                      final allTags =
                          await ref.read(tagRepositoryProvider).getAllTags();
                      final resolver =
                          await ref.read(tagUsageResolverProvider.future);
                      if (!context.mounted) {
                        return;
                      }
                      final existingIds = blockTags.map((t) => t.id).toSet();
                      // 「纳入时间表」可见的标签（继承生效后），保持仓库顺序。
                      final visibleIds = resolver
                          .visibleOf(
                            allTags.map((tag) => tag.id),
                            TagUsage.time,
                          )
                          .toSet();
                      final candidates = <Tag>[
                        for (final tag in allTags)
                          if (visibleIds.contains(tag.id) &&
                              !existingIds.contains(tag.id))
                            tag,
                      ];
                      if (candidates.isEmpty) {
                        // 静默 return 会让用户以为按钮坏了：说明为什么没有
                        // 可选项（整树没声明用途 vs 声明了但都不含时间表）。
                        await showDialog<void>(
                          context: context,
                          builder: (ctx) => SimpleDialog(
                            key: const ValueKey<String>(
                              'time-block-tag-scope-empty',
                            ),
                            contentPadding:
                                const EdgeInsets.fromLTRB(24, 20, 24, 12),
                            children: [
                              Text(
                                resolver.hasAnyDeclaration
                                    ? l10n.timeBlockTagScopeEmpty
                                    : l10n.timeBlockTagScopeDefaultHint,
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: Text(l10n.commonClose),
                                ),
                              ),
                            ],
                          ),
                        );
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
                        await ref.read(tagRepositoryProvider).addTagToObject(
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
              // 选择器只列「纳入时间表」那棵树里的标签；没有声明时=不限制，
              // 所以这条提示必须始终可见，而不是只在过滤生效时才出现。
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.timeBlockTagScopeHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 4),
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

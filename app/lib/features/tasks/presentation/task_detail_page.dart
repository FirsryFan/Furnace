import 'package:flutter/material.dart';
import 'package:furnace/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/notification_provider.dart';
import '../../../data/database/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../application/task_scheduler_providers.dart';

/// Task detail page: subtasks, dependencies, reminder.
class TaskDetailPage extends ConsumerStatefulWidget {
  const TaskDetailPage({super.key, required this.taskId});

  final String taskId;

  @override
  ConsumerState<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends ConsumerState<TaskDetailPage> {
  Task? _task;
  List<Task> _subtasks = [];
  List<Task> _dependencies = [];
  List<Tag> _tags = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(taskRepositoryProvider);
    final task = await repo.getTaskById(widget.taskId);
    final subtasks = await repo.getTasks(parentId: widget.taskId);
    final depIds = await repo.getDependencyIds(widget.taskId);
    final dependencies = <Task>[];
    for (final id in depIds) {
      final dep = await repo.getTaskById(id);
      if (dep != null) {
        dependencies.add(dep);
      }
    }
    final taskTags = await ref
        .read(tagRepositoryProvider)
        .tagsForObject(objectType: 'task', objectId: widget.taskId);

    if (!mounted) {
      return;
    }
    setState(() {
      _task = task;
      _subtasks = subtasks;
      _dependencies = dependencies;
      _tags = taskTags;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final task = _task;

    return Scaffold(
      appBar: AppBar(
        title: Text(task?.title ?? ''),
        actions: [
          IconButton(
            tooltip: l10n.commonEdit,
            icon: const Icon(Icons.edit_outlined),
            onPressed: task == null ? null : () => _editTask(context, task),
          ),
          IconButton(
            tooltip: l10n.commonDelete,
            icon: const Icon(Icons.delete_outline),
            onPressed: task == null ? null : () => _deleteTask(context),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : task == null
              ? Center(child: Text(l10n.commonTitle))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      task.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_priorityLabel(l10n, task.priority)}'
                      '${task.estimateMinutes != null ? ' · ${task.estimateMinutes} min' : ''}'
                      '${task.remindAt != null ? ' · ${l10n.tasksReminder}' : ''}',
                    ),
                    const Divider(height: 32),
                    Row(
                      children: [
                        Text(
                          l10n.tasksSubtasks,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: l10n.tasksAddSubtask,
                          icon: const Icon(Icons.add),
                          onPressed: () => _addSubtask(context),
                        ),
                      ],
                    ),
                    for (final sub in _subtasks)
                      ListTile(
                        dense: true,
                        title: Text(sub.title),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _deleteSubtask(context, sub.id),
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                TaskDetailPage(taskId: sub.id),
                          ),
                        ),
                      ),
                    const Divider(height: 16),
                    Row(
                      children: [
                        Text(
                          l10n.tasksDependencies,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: l10n.tasksAddDependency,
                          icon: const Icon(Icons.add_link),
                          onPressed: () => _addDependency(context),
                        ),
                      ],
                    ),
                    for (final dep in _dependencies)
                      ListTile(
                        dense: true,
                        title: Text(dep.title),
                        trailing: IconButton(
                          icon: const Icon(Icons.link_off),
                          onPressed: () =>
                              _removeDependency(context, dep.id),
                        ),
                      ),
                    const Divider(height: 16),
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
                          onPressed: () => _addTag(context),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final tag in _tags)
                          Chip(
                            label: Text(tag.name),
                            onDeleted: () => _removeTag(context, tag),
                          ),
                      ],
                    ),
                    const Divider(height: 16),
                    ListTile(
                      leading: const Icon(Icons.alarm),
                      title: Text(l10n.tasksRemindAt),
                      subtitle: Text(
                        task.remindAt == null
                            ? l10n.tasksReminder
                            : _formatDateTime(task.remindAt!),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _setReminder(context, task),
                      ),
                    ),
                  ],
                ),
    );
  }

  String _priorityLabel(AppLocalizations l10n, int priority) {
    return switch (priority) {
      0 => l10n.tasksPriorityLow,
      2 => l10n.tasksPriorityHigh,
      _ => l10n.tasksPriorityMedium,
    };
  }

  String _formatDateTime(int millis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _editTask(BuildContext context, Task task) async {
    final l10n = AppLocalizations.of(context);
    final titleController = TextEditingController(text: task.title);
    final estimateController = TextEditingController(
      text: task.estimateMinutes?.toString() ?? '',
    );
    var priority = task.priority;
    var dueAt = task.dueAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(task.dueAt!);

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
              DropdownButtonFormField<int>(
                value: priority,
                decoration: InputDecoration(labelText: l10n.tasksSuggestions),
                items: [
                  DropdownMenuItem(value: 0, child: Text(l10n.tasksPriorityLow)),
                  DropdownMenuItem(
                      value: 1, child: Text(l10n.tasksPriorityMedium)),
                  DropdownMenuItem(
                      value: 2, child: Text(l10n.tasksPriorityHigh)),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => priority = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: estimateController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.tasksEstimateMinutes,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.tasksDueAt),
                subtitle: Text(
                  dueAt == null
                      ? l10n.tasksDueAt
                      : _formatDateTime(dueAt!.millisecondsSinceEpoch),
                ),
                trailing: dueAt == null
                    ? null
                    : IconButton(
                        tooltip: l10n.commonClear,
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => dueAt = null),
                      ),
                onTap: () async {
                  final now = DateTime.now();
                  final date = await showDatePicker(
                    context: context,
                    initialDate: dueAt ?? DateTime(now.year, now.month, now.day),
                    firstDate: DateTime(now.year - 1),
                    lastDate: DateTime(now.year + 5),
                  );
                  if (date == null) {
                    return;
                  }
                  final time = await showTimePicker(
                    context: context,
                    initialTime: dueAt == null
                        ? TimeOfDay.fromDateTime(now)
                        : TimeOfDay.fromDateTime(dueAt!),
                  );
                  if (time != null) {
                    setState(() {
                      dueAt = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      );
                    });
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
    final estimate = int.tryParse(estimateController.text.trim());
    await ref.read(taskRepositoryProvider).updateTask(
          task.id,
          title: title,
          priority: priority,
          estimateMinutes: estimate,
          dueAt: dueAt?.millisecondsSinceEpoch,
          clearDueAt: dueAt == null && task.dueAt != null,
        );
    ref.invalidate(taskListProvider);
    ref.invalidate(scheduleSuggestionsProvider);
    await _load();
  }

  Future<void> _addTag(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final allTags = await ref.read(tagRepositoryProvider).getAllTags();
    final existingIds = _tags.map((t) => t.id).toSet();
    final candidates = allTags.where((t) => !existingIds.contains(t.id)).toList();
    if (candidates.isEmpty) {
      return;
    }
    final selected = await showDialog<Tag>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.tagsTitle),
        children: [
          for (final tag in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, tag),
              child: Text(tag.name),
            ),
        ],
      ),
    );
    if (selected == null) {
      return;
    }
    await ref.read(tagRepositoryProvider).addTagToObject(
          tagId: selected.id,
          objectType: 'task',
          objectId: widget.taskId,
        );
    await _load();
  }

  Future<void> _removeTag(BuildContext context, Tag tag) async {
    await ref.read(tagRepositoryProvider).removeTagFromObject(
          tagId: tag.id,
          objectType: 'task',
          objectId: widget.taskId,
        );
    await _load();
  }

  Future<void> _addSubtask(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.tasksAddSubtask),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.commonTitle),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty) {
      return;
    }
    await ref.read(taskRepositoryProvider).createTask(
          title: title,
          parentId: widget.taskId,
        );
    ref.invalidate(taskListProvider);
    ref.invalidate(scheduleSuggestionsProvider);
    await _load();
  }

  Future<void> _deleteSubtask(BuildContext context, String id) async {
    await ref.read(taskRepositoryProvider).deleteTask(id);
    ref.invalidate(taskListProvider);
    ref.invalidate(scheduleSuggestionsProvider);
    await _load();
  }

  Future<void> _addDependency(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final all = await ref.read(taskRepositoryProvider).getOpenTasks();
    final depIds = _dependencies.map((d) => d.id).toSet()..add(widget.taskId);
    final candidates = all.where((t) => !depIds.contains(t.id)).toList();

    if (candidates.isEmpty) {
      return;
    }
    final selected = await showDialog<Task>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.tasksAddDependency),
        children: [
          for (final task in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, task),
              child: Text(task.title),
            ),
        ],
      ),
    );
    if (selected == null) {
      return;
    }
    await ref.read(taskRepositoryProvider).addDependency(
          taskId: widget.taskId,
          dependsOnTaskId: selected.id,
        );
    ref.invalidate(scheduleSuggestionsProvider);
    await _load();
  }

  Future<void> _removeDependency(BuildContext context, String depId) async {
    await ref.read(taskRepositoryProvider).removeDependency(
          taskId: widget.taskId,
          dependsOnTaskId: depId,
        );
    ref.invalidate(scheduleSuggestionsProvider);
    await _load();
  }

  Future<void> _setReminder(BuildContext context, Task task) async {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year, now.month, now.day),
      firstDate: DateTime(now.year),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (time == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    final remindAt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    await ref.read(taskRepositoryProvider).updateTask(
          task.id,
          remindAt: remindAt.millisecondsSinceEpoch,
        );
    final notificationId = task.id.hashCode & 0x7fffffff;
    await ref
        .read(notificationServiceProvider)
        .cancelReminder(notificationId);
    await ref.read(notificationServiceProvider).scheduleReminder(
          id: notificationId,
          title: task.title,
          body: l10n.tasksReminder,
          when: remindAt,
        );
    ref.invalidate(taskListProvider);
    ref.invalidate(scheduleSuggestionsProvider);
    await _load();
  }

  Future<void> _deleteTask(BuildContext context) async {
    await ref.read(taskRepositoryProvider).deleteTask(widget.taskId);
    ref.invalidate(taskListProvider);
    ref.invalidate(scheduleSuggestionsProvider);
    if (mounted) {
      Navigator.pop(context);
    }
  }
}

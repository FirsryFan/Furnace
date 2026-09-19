import 'package:flutter/material.dart';
import 'package:knowflow/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/scheduling/task_scheduler.dart';
import '../application/task_scheduler_providers.dart';
import 'task_detail_page.dart';

/// Task module: basic task list + auto-scheduling suggestions.
class TasksPage extends ConsumerWidget {
  const TasksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tasksAsync = ref.watch(taskListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navTasks),
        actions: [
          IconButton(
            tooltip: l10n.tasksSuggestions,
            icon: const Icon(Icons.auto_awesome),
            onPressed: () => _showSuggestions(context, ref),
          ),
          IconButton(
            tooltip: l10n.tasksNewTask,
            icon: const Icon(Icons.add),
            onPressed: () => _createTask(context, ref),
          ),
        ],
      ),
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('$error')),
        data: (tasks) {
          if (tasks.isEmpty) {
            return Center(
              child: FilledButton.icon(
                onPressed: () => _createTask(context, ref),
                icon: const Icon(Icons.add),
                label: Text(l10n.tasksNewTask),
              ),
            );
          }
          return ListView.builder(
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              return ListTile(
                leading: IconButton(
                  icon: Icon(
                    task.status == 'done'
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: task.status == 'done'
                        ? Colors.green
                        : Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: () => _toggleDone(context, ref, task),
                ),
                title: Text(task.title),
                subtitle: Text(
                  '${_priorityLabel(l10n, task.priority)}'
                  '${task.estimateMinutes != null ? ' · ${task.estimateMinutes} min' : ''}'
                  '${task.dueAt != null ? ' · ${_formatDue(task.dueAt!)}' : ''}',
                ),
                trailing: IconButton(
                  tooltip: l10n.commonDelete,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _deleteTask(context, ref, task.id),
                ),
                onTap: () => _openDetail(context, task.id),
              );
            },
          );
        },
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

  String _formatDue(int millis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    return '$month-$day ${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _createTask(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final titleController = TextEditingController();
    final estimateController = TextEditingController();
    var priority = 1;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l10n.tasksNewTask),
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
    await ref.read(taskRepositoryProvider).createTask(
          title: title,
          priority: priority,
          estimateMinutes: estimate,
        );
    ref.invalidate(taskListProvider);
    ref.invalidate(scheduleSuggestionsProvider);
  }

  void _openDetail(BuildContext context, String taskId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => TaskDetailPage(taskId: taskId)),
    );
  }

  Future<void> _toggleDone(BuildContext context, WidgetRef ref, Task task) async {
    await ref.read(taskRepositoryProvider).updateTask(
          task.id,
          status: task.status == 'done' ? 'todo' : 'done',
        );
    ref.invalidate(taskListProvider);
    ref.invalidate(scheduleSuggestionsProvider);
  }

  Future<void> _deleteTask(BuildContext context, WidgetRef ref, String id) async {
    await ref.read(taskRepositoryProvider).deleteTask(id);
    ref.invalidate(taskListProvider);
    ref.invalidate(scheduleSuggestionsProvider);
  }

  Future<void> _adoptSuggestion(
    BuildContext context,
    WidgetRef ref,
    TaskSuggestion suggestion,
  ) async {
    final timeBlockId = suggestion.timeBlockId;
    if (timeBlockId == null) {
      return;
    }
    await ref.read(taskRepositoryProvider).linkTaskToTimeBlock(
          taskId: suggestion.taskId,
          timeBlockId: timeBlockId,
          isSuggestion: false,
        );
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${suggestion.taskTitle} ✓')),
    );
    ref.invalidate(scheduleSuggestionsProvider);
  }

  Future<void> _showSuggestions(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final l10n = AppLocalizations.of(context);
    final result = await ref.read(scheduleSuggestionsProvider.future);
    if (!context.mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.tasksSuggestions),
        content: SizedBox(
          width: 480,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final suggestion in result.suggestions)
                ListTile(
                  leading: const Icon(Icons.arrow_forward),
                  title: Text(suggestion.taskTitle),
                  subtitle: suggestion.suggestedStart == null
                      ? Text('${l10n.tasksSuggestions}: ${suggestion.reason}')
                      : Text(
                          '${suggestion.suggestedStart!.hour}:'
                          '${suggestion.suggestedStart!.minute.toString().padLeft(2, '0')}'
                          ' - '
                          '${suggestion.suggestedEnd!.hour}:'
                          '${suggestion.suggestedEnd!.minute.toString().padLeft(2, '0')}',
                        ),
                  trailing: suggestion.timeBlockId == null
                      ? null
                      : IconButton(
                          tooltip: l10n.tasksSuggestions,
                          icon: const Icon(Icons.check),
                          onPressed: () => _adoptSuggestion(
                            context,
                            ref,
                            suggestion,
                          ),
                        ),
                ),
              if (result.suggestions.isEmpty)
                ListTile(title: Text(l10n.tasksNoSuggestions)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonConfirm),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:furnace/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/scheduling/task_scheduler.dart';
import '../../../domain/services/thread/thread_status.dart';
import '../application/task_scheduler_providers.dart';
import 'task_detail_page.dart';
import 'widgets/task_status_actions.dart';

/// Task module: basic task list + auto-scheduling suggestions.
///
/// v47 起列表按**流程状态**分三段读（task-76）：
///
///  * 「待办」= `todo|doing`，行首仍是完成勾选；
///  * 「已完成」= `done`，勾选可重开；
///  * 「卡住 / 跳过」= `blocked|skipped`，行首不再是"未完成"圆圈，也不再混在待办里。
///
/// 分成三段不是为了多一个视图，而是因为 v47 明确 blocked/skipped **既不是待办也
/// 不是完成**（见 `ThreadStatus`）：把卡住的行画成一个没勾的待办，会让用户以为
/// 它还在排队。状态动作（提交/卡住/跳过/恢复）在每行右侧的菜单里，按当前状态
/// 可用；卡住/跳过的行首图标本身就是「恢复」入口（task-90）。
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

          // 三个互斥的桶，按状态读唯一来源 `ThreadStatus`：
          // blocked/skipped 不再靠"没勾选"冒充待办。
          final open = <Task>[];
          final done = <Task>[];
          final archived = <Task>[];
          for (final task in tasks) {
            final status = taskFlowStatus(task);
            switch (status) {
              case ThreadStatus.todo:
              case ThreadStatus.doing:
                open.add(task);
              case ThreadStatus.done:
                done.add(task);
              case ThreadStatus.blocked:
              case ThreadStatus.skipped:
                archived.add(task);
            }
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              if (open.isNotEmpty) ...[
                _SectionHeader(
                  icon: Icons.checklist,
                  title: l10n.tasksStatusSectionTodo,
                ),
                for (final task in open) _TaskRow(task: task),
              ],
              if (done.isNotEmpty) ...[
                _SectionHeader(
                  icon: Icons.done_all,
                  title: l10n.tasksStatusSectionDone,
                ),
                for (final task in done) _TaskRow(task: task),
              ],
              if (archived.isNotEmpty) ...[
                _SectionHeader(
                  icon: Icons.inventory_2_outlined,
                  title: l10n.tasksStatusSectionArchived,
                ),
                for (final task in archived) _TaskRow(task: task),
              ],
            ],
          );
        },
      ),
    );
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

/// One task row. The leading control completes `todo|doing` and reopens `done`
/// (existing checkbox semantics); `blocked|skipped` rows show a state icon that
/// is itself the "restore" entry (`reopen` via `TaskRepository` → writer, with
/// the shared second confirmation), and keep the other status actions in the
/// trailing menu.
class _TaskRow extends ConsumerWidget {
  const _TaskRow({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status = taskFlowStatus(task);

    final details = <String>[
      _priorityLabel(l10n, task.priority),
      if (task.estimateMinutes != null) '${task.estimateMinutes} min',
      if (task.dueAt != null) _formatDue(task.dueAt!),
      // 卡住/跳过的行把状态写在副标题里：它不在待办段，用户要能一眼看出为什么。
      if (status == ThreadStatus.blocked || status == ThreadStatus.skipped)
        taskStatusLabel(l10n, task),
    ];

    return ListTile(
      leading: _leading(context, ref, status),
      title: Text(task.title),
      subtitle: Text(details.join(' · ')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TaskStatusMenu(
            task: task,
            onChanged: (_) {
              ref.invalidate(taskListProvider);
              ref.invalidate(scheduleSuggestionsProvider);
            },
          ),
          IconButton(
            tooltip: l10n.commonDelete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _deleteTask(context, ref, task.id),
          ),
        ],
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => TaskDetailPage(taskId: task.id)),
      ),
    );
  }

  Widget _leading(BuildContext context, WidgetRef ref, ThreadStatus status) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    switch (status) {
      case ThreadStatus.done:
        return IconButton(
          icon: const Icon(Icons.check_circle, color: Colors.green),
          tooltip: taskStatusLabelOf(l10n, status),
          onPressed: () => _toggleDone(context, ref),
        );
      case ThreadStatus.blocked:
        return IconButton(
          icon: Icon(
            Icons.pause_circle_outline,
            color: theme.colorScheme.tertiary,
          ),
          tooltip: l10n.tasksReopen,
          onPressed: () => _reopen(context, ref),
        );
      case ThreadStatus.skipped:
        return IconButton(
          icon: Icon(
            Icons.skip_next_outlined,
            color: theme.colorScheme.outline,
          ),
          tooltip: l10n.tasksReopen,
          onPressed: () => _reopen(context, ref),
        );
      case ThreadStatus.todo:
      case ThreadStatus.doing:
        return IconButton(
          icon: Icon(
            Icons.radio_button_unchecked,
            color: theme.colorScheme.primary,
          ),
          tooltip: taskStatusLabelOf(l10n, status),
          onPressed: () => _toggleDone(context, ref),
        );
    }
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

  /// 旧勾选行为（todo/doing → done，done → todo）保持不变；blocked/skipped
  /// 不走这里——它们的「恢复」是行首状态图标（`_reopen`），带二次确认。
  ///
  /// task-90 起 done → todo 也不再直写：`updateTask(status:'todo')` 内部走
  /// `TaskRepository.reopenTask` → `ThreadFlowWriter.reopen`，落一条 `reopened`
  /// 事件并清 `completed_at`；完成历史不回滚。勾选框这一步仍是即时生效（既有
  /// 语义，不弹确认），与状态菜单/详情页的显式「恢复」并存。
  Future<void> _toggleDone(BuildContext context, WidgetRef ref) async {
    final status = taskFlowStatus(task);
    if (!status.isSchedulable && status != ThreadStatus.done) {
      return;
    }
    await ref.read(taskRepositoryProvider).updateTask(
          task.id,
          status: status == ThreadStatus.done
              ? ThreadStatus.todo.id
              : ThreadStatus.done.id,
        );
    ref.invalidate(taskListProvider);
    ref.invalidate(scheduleSuggestionsProvider);
  }

  /// 卡住 / 跳过 → 待办：走共享状态动作（二次确认 + writer + SnackBar）。
  Future<void> _reopen(BuildContext context, WidgetRef ref) async {
    final changed = await runTaskStatusAction(
      context,
      ref,
      task: task,
      action: TaskStatusAction.reopen,
    );
    if (changed) {
      ref.invalidate(taskListProvider);
      ref.invalidate(scheduleSuggestionsProvider);
    }
  }

  Future<void> _deleteTask(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    await ref.read(taskRepositoryProvider).deleteTask(id);
    ref.invalidate(taskListProvider);
    ref.invalidate(scheduleSuggestionsProvider);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// 任务的「提交 / 卡住 / 跳过 / 恢复」四个状态入口（task-76；`reopen` 于
/// task-90 / B7 追加）。
///
/// 为什么需要这一层：`ThreadFlowWriter` 与 `TaskRepository` 已经有
/// `submitTask` / `markTaskStuck` / `skipTask` / `reopenTask`（唯一写口的四个
/// 便捷方法），本文件只做三件事：
///
///  1. 把动作和 writer 的**状态机**绑在一起（`allowedFrom` 直接读
///     `ThreadEventKind`，不在这里另写一份"哪些状态能做"的规则）；
///  2. 每个动作都先弹二次确认，再经 `TaskRepository` 落库，最后用 SnackBar 说
///     清结果——误触一次不会直接改状态；
///  3. 不引入第二状态、不直接写 `tasks.status`、不写完成历史（那仍只属于
///     `completed`）。`reopen` 是**显式恢复**（blocked/skipped → todo，写一条
///     `reopened` 事件），不是对提交/卡住/跳过的快照撤销：那些动作没有快照，
///     `reopened` 也不会把它们写过的事件抹掉。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/database/database.dart';
import '../../../../data/repositories/repository_providers.dart';
import '../../../../domain/services/thread/thread_event_kind.dart';
import '../../../../domain/services/thread/thread_status.dart';
import '../../../../l10n/app_localizations.dart';

/// 提交 / 卡住 / 跳过 / 恢复。
enum TaskStatusAction {
  submit(ThreadEventKind.submitted),
  stuck(ThreadEventKind.stuck),
  skip(ThreadEventKind.skipped),
  reopen(ThreadEventKind.reopened);

  const TaskStatusAction(this.eventKind);

  /// 落库的事件种类（与 `ThreadFlowWriter.submit/markStuck/skip/reopen` 同一个
  /// 枚举）。
  final ThreadEventKind eventKind;

  /// 当前状态是否允许这个动作。**唯一来源**是 writer 的 `allowedFrom`：UI 不放宽
  /// 也不收紧状态机，避免出现"按钮亮着但写库报非法迁移"。
  ///
  /// 唯一的 UI 层判断：`done` 的「恢复」不放进状态菜单 / 按钮组——任务页行首勾选
  /// 已经承担 done→todo（既有语义），同一件事不摆两条入口。writer 本身允许
  /// done→todo（契约 §3.4 的重开一行），`TaskRepository.updateTask(status:'todo')`
  /// 也照常走它。
  bool allowedFrom(ThreadStatus status) {
    if (this == TaskStatusAction.reopen && status == ThreadStatus.done) {
      return false;
    }
    return eventKind.allowedFrom.contains(status);
  }

  String label(AppLocalizations l10n) => switch (this) {
        TaskStatusAction.submit => l10n.tasksSubmit,
        TaskStatusAction.stuck => l10n.tasksMarkStuck,
        TaskStatusAction.skip => l10n.tasksSkip,
        TaskStatusAction.reopen => l10n.tasksReopen,
      };

  IconData get icon => switch (this) {
        TaskStatusAction.submit => Icons.send_outlined,
        TaskStatusAction.stuck => Icons.pause_circle_outline,
        TaskStatusAction.skip => Icons.skip_next_outlined,
        TaskStatusAction.reopen => Icons.undo,
      };

  String confirmTitle(AppLocalizations l10n, String title) => switch (this) {
        TaskStatusAction.submit => l10n.tasksSubmitTitle(title),
        TaskStatusAction.stuck => l10n.tasksStuckTitle(title),
        TaskStatusAction.skip => l10n.tasksSkipTitle(title),
        TaskStatusAction.reopen => l10n.tasksReopenTitle(title),
      };

  String confirmBody(AppLocalizations l10n) => switch (this) {
        TaskStatusAction.submit => l10n.tasksSubmitBody,
        TaskStatusAction.stuck => l10n.tasksStuckBody,
        TaskStatusAction.skip => l10n.tasksSkipBody,
        TaskStatusAction.reopen => l10n.tasksReopenBody,
      };

  String doneMessage(AppLocalizations l10n, String title) => switch (this) {
        TaskStatusAction.submit => l10n.tasksSubmitDone(title),
        TaskStatusAction.stuck => l10n.tasksStuckDone(title),
        TaskStatusAction.skip => l10n.tasksSkipDone(title),
        TaskStatusAction.reopen => l10n.tasksReopenDone(title),
      };
}

/// 任务行上的流程状态（`todo/doing/done/blocked/skipped`）。
///
/// 独立成函数是为了让 UI 不必到处 import domain 枚举；未知/NULL 值按 `todo`
/// 读，与 `TaskRepository` 的读侧口径一致。
ThreadStatus taskFlowStatus(Task task) => ThreadStatus.fromStorage(task.status);

/// 任务是否还在待办集合里（只有 `todo|doing`）。
bool isTaskSchedulable(Task task) => taskFlowStatus(task).isSchedulable;

String taskStatusLabel(AppLocalizations l10n, Task task) =>
    taskStatusLabelOf(l10n, taskFlowStatus(task));

String taskStatusLabelOf(AppLocalizations l10n, ThreadStatus status) =>
    switch (status) {
      ThreadStatus.todo => l10n.tasksStatusTodo,
      ThreadStatus.doing => l10n.tasksStatusDoing,
      ThreadStatus.done => l10n.tasksStatusDone,
      ThreadStatus.blocked => l10n.tasksStatusBlocked,
      ThreadStatus.skipped => l10n.tasksStatusSkipped,
    };

/// 执行一个状态动作：状态检查 → 二次确认 → `TaskRepository` → SnackBar。
///
/// 返回 `true` 表示真的写了一次；用户取消、状态不允许或写库失败都返回 `false`
/// （失败已经用 SnackBar 说过原因，调用方不必再弹第二个提示）。
Future<bool> runTaskStatusAction(
  BuildContext context,
  WidgetRef ref, {
  required Task task,
  required TaskStatusAction action,
}) async {
  final l10n = AppLocalizations.of(context);
  final status = taskFlowStatus(task);

  if (!action.allowedFrom(status)) {
    _showMessage(
      context,
      l10n.tasksStatusNotAllowed(taskStatusLabelOf(l10n, status), action.label(l10n)),
    );
    return false;
  }

  final confirmed = await _confirm(context, task, action);
  if (confirmed != true || !context.mounted) {
    return false;
  }

  final repository = ref.read(taskRepositoryProvider);
  try {
    switch (action) {
      case TaskStatusAction.submit:
        await repository.submitTask(task.id);
      case TaskStatusAction.stuck:
        await repository.markTaskStuck(task.id);
      case TaskStatusAction.skip:
        await repository.skipTask(task.id);
      case TaskStatusAction.reopen:
        await repository.reopenTask(task.id);
    }
  } on StateError catch (error) {
    // 最可能的来源：状态机拒绝（例如任务在这一瞬间被别人改成了 skipped）。
    // 原样带出 writer 的消息，避免 UI 编一个含糊的"操作失败"。
    if (context.mounted) {
      _showMessage(
        context,
        l10n.tasksStatusActionFailed(error.message.toString()),
      );
    }
    return false;
  } catch (error) {
    if (context.mounted) {
      _showMessage(context, l10n.tasksStatusActionFailed('$error'));
    }
    return false;
  }

  if (!context.mounted) {
    return true;
  }
  _showMessage(context, action.doneMessage(l10n, task.title));
  return true;
}

Future<bool> _confirm(
  BuildContext context,
  Task task,
  TaskStatusAction action,
) async {
  final l10n = AppLocalizations.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: ValueKey('task-status-confirm-${action.eventKind.id}'),
      title: Text(action.confirmTitle(l10n, task.title)),
      content: Text(action.confirmBody(l10n)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.commonConfirm),
        ),
      ],
    ),
  );
  return result == true;
}

void _showMessage(BuildContext context, String message) {
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(message)),
  );
}

/// 任务详情页用：一行四个按钮，按当前状态自动禁用不允许的动作。
class TaskStatusActions extends ConsumerWidget {
  const TaskStatusActions({
    super.key,
    required this.task,
    this.onChanged,
  });

  final Task task;

  /// 动作真的写入后回调（页面据此重新读库/排序）。
  final ValueChanged<TaskStatusAction>? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status = taskFlowStatus(task);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final action in TaskStatusAction.values)
          TextButton.icon(
            key: ValueKey('task-status-${action.eventKind.id}'),
            onPressed: action.allowedFrom(status)
                ? () async {
                    final done = await runTaskStatusAction(
                      context,
                      ref,
                      task: task,
                      action: action,
                    );
                    if (done) {
                      onChanged?.call(action);
                    }
                  }
                : null,
            icon: Icon(action.icon, size: 18),
            label: Text(action.label(l10n)),
          ),
      ],
    );
  }
}

/// 任务行用：一个「状态操作」弹出菜单，四个动作按状态可用。
///
/// 行上放三个文字按钮会把标题挤没；菜单还能顺手把不允许的动作显示成灰色，
/// 用户能看到"为什么这里点不了"，而不是按钮凭空消失。
class TaskStatusMenu extends ConsumerWidget {
  const TaskStatusMenu({
    super.key,
    required this.task,
    this.onChanged,
  });

  final Task task;

  final ValueChanged<TaskStatusAction>? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status = taskFlowStatus(task);
    return PopupMenuButton<TaskStatusAction>(
      key: ValueKey('task-status-menu-${task.id}'),
      tooltip: l10n.tasksStatusMenu,
      icon: const Icon(Icons.flag_outlined),
      onSelected: (action) async {
        final done = await runTaskStatusAction(
          context,
          ref,
          task: task,
          action: action,
        );
        if (done) {
          onChanged?.call(action);
        }
      },
      itemBuilder: (context) => [
        for (final action in TaskStatusAction.values)
          PopupMenuItem<TaskStatusAction>(
            key: ValueKey('task-status-menu-item-${action.eventKind.id}'),
            value: action,
            enabled: action.allowedFrom(status),
            child: Row(
              children: [
                Icon(action.icon, size: 18),
                const SizedBox(width: 12),
                Text(action.label(l10n)),
              ],
            ),
          ),
      ],
    );
  }
}

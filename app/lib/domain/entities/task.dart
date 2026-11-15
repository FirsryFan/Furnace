/// Task domain entity used by the scheduling engine.
library;

/// 调度层看到的状态（schema v47 五值：`tasks.status` 是自由 TEXT）。
///
/// 用值补齐而不是替换：`blocked` / `skipped` 是 v47 加的值、不加列；调度器只
/// 处理 `todo|doing`（见 [TaskItem.isOpen]），卡住/跳过不应当成待办。
enum TaskStatus { todo, doing, done, blocked, skipped }

enum TaskPriority { low, medium, high }

class TaskItem {
  const TaskItem({
    required this.id,
    required this.title,
    this.status = TaskStatus.todo,
    this.priority = TaskPriority.medium,
    this.estimateMinutes,
    this.dueAt,
    this.dependencies = const [],
    this.tags = const [],
  });

  final String id;
  final String title;
  final TaskStatus status;
  final TaskPriority priority;
  final int? estimateMinutes;
  final DateTime? dueAt;
  final List<String> dependencies;
  final List<String> tags;

  /// 能不能进调度器（段 A/B）的候选集：只有 `todo|doing`。
  ///
  /// v47 之前这里写的是 `status != done`，于是 blocked/skipped 会被排进待办。
  bool get isOpen => status == TaskStatus.todo || status == TaskStatus.doing;

  TaskItem copyWith({
    TaskStatus? status,
    TaskPriority? priority,
    int? estimateMinutes,
    DateTime? dueAt,
    List<String>? dependencies,
    List<String>? tags,
  }) {
    return TaskItem(
      id: id,
      title: title,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      estimateMinutes: estimateMinutes ?? this.estimateMinutes,
      dueAt: dueAt ?? this.dueAt,
      dependencies: dependencies ?? this.dependencies,
      tags: tags ?? this.tags,
    );
  }
}

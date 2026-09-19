/// Task domain entity used by the scheduling engine.
library;

enum TaskStatus { todo, doing, done }

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

  bool get isOpen => status != TaskStatus.done;

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

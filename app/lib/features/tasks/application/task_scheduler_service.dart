import '../../../data/repositories/tag_repository.dart';
import '../../../data/repositories/task_repository.dart';
import '../../../data/repositories/time_block_repository.dart';
import '../../../domain/entities/task.dart';
import '../../../domain/entities/time_block.dart';
import '../../../domain/services/scheduling/task_scheduler.dart';

/// Application service that loads data from repositories and runs the
/// [TaskScheduler] engine.
class TaskSchedulerService {
  TaskSchedulerService({
    required TaskRepository taskRepository,
    required TimeBlockRepository timeBlockRepository,
    required TagRepository tagRepository,
  })  : _taskRepository = taskRepository,
        _timeBlockRepository = timeBlockRepository,
        _tagRepository = tagRepository;

  final TaskRepository _taskRepository;
  final TimeBlockRepository _timeBlockRepository;
  final TagRepository _tagRepository;

  Future<TaskScheduleResult> scheduleNow() async {
    final dbTasks = await _taskRepository.getOpenTasks();
    final dbBlocks = await _timeBlockRepository.getTimeBlocks(
      onlyAvailable: true,
    );

    final tasks = <TaskItem>[];
    for (final task in dbTasks) {
      final dependencies = await _taskRepository.getDependencyIds(task.id);
      final taskTags = await _tagRepository.tagsForObject(
        objectType: 'task',
        objectId: task.id,
      );
      tasks.add(
        TaskItem(
          id: task.id,
          title: task.title,
          status: _mapStatus(task.status),
          priority: _mapPriority(task.priority),
          estimateMinutes: task.estimateMinutes,
          dueAt: task.dueAt == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(task.dueAt!),
          dependencies: dependencies,
          tags: [for (final tag in taskTags) tag.name],
        ),
      );
    }

    final blocks = [
      for (final block in dbBlocks)
        TimeBlock(
          id: block.id,
          title: block.title,
          start: DateTime.fromMillisecondsSinceEpoch(block.startAt),
          end: DateTime.fromMillisecondsSinceEpoch(block.endAt),
          available: block.available,
          energy: block.energy,
          suitableFor: block.suitableFor,
        ),
    ];

    return TaskScheduler.schedule(tasks: tasks, timeBlocks: blocks);
  }

  /// `tasks.status` 是自由 TEXT（v47 五值）。这里显式映射，不再用 `_ => todo`
  /// 兜底：那会把 `blocked` / `skipped` 悄悄当成待办。`getOpenTasks()` 已经只取
  /// `todo|doing`，本方法只是让"万一传进来"时也不说谎。
  TaskStatus _mapStatus(String status) {
    return switch (status) {
      'doing' => TaskStatus.doing,
      'done' => TaskStatus.done,
      'blocked' => TaskStatus.blocked,
      'skipped' => TaskStatus.skipped,
      _ => TaskStatus.todo,
    };
  }

  TaskPriority _mapPriority(int priority) {
    return switch (priority) {
      0 => TaskPriority.low,
      2 => TaskPriority.high,
      _ => TaskPriority.medium,
    };
  }
}

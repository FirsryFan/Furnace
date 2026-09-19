/// Transparent task scheduling engine for KnowFlow.
///
/// Rule order:
/// 1. Dependencies must come before dependents.
/// 2. Higher priority first.
/// 3. Earlier due date first.
/// 4. Try to place each task into an available time block that can fit its
///    estimated duration.
library;

import '../../entities/task.dart';
import '../../entities/time_block.dart';

/// Machine-readable reason for a suggestion; UI translates it.
enum SuggestionReason {
  dependency,
  priority,
  dueDate,
  estimate,
  noTimeBlock,
}

class TaskSuggestion {
  const TaskSuggestion({
    required this.taskId,
    required this.taskTitle,
    required this.reason,
    this.suggestedStart,
    this.suggestedEnd,
    this.timeBlockId,
  });

  final String taskId;
  final String taskTitle;
  final SuggestionReason reason;
  final DateTime? suggestedStart;
  final DateTime? suggestedEnd;
  final String? timeBlockId;
}

class TaskScheduleResult {
  const TaskScheduleResult({
    required this.suggestions,
    required this.unscheduledTaskIds,
  });

  final List<TaskSuggestion> suggestions;
  final List<String> unscheduledTaskIds;
}

abstract final class TaskScheduler {
  static TaskScheduleResult schedule({
    required List<TaskItem> tasks,
    required List<TimeBlock> timeBlocks,
  }) {
    final openTasks = tasks.where((t) => t.isOpen).toList();
    final byId = {for (final t in openTasks) t.id: t};

    // Topological order using Kahn's algorithm.
    final indegree = <String, int>{for (final t in openTasks) t.id: 0};
    final dependents = <String, List<String>>{for (final t in openTasks) t.id: []};

    for (final task in openTasks) {
      for (final depId in task.dependencies) {
        if (!byId.containsKey(depId)) {
          continue;
        }
        indegree[task.id] = (indegree[task.id] ?? 0) + 1;
        dependents[depId] = [...(dependents[depId] ?? []), task.id];
      }
    }

    final ready = <TaskItem>[
      for (final task in openTasks)
        if ((indegree[task.id] ?? 0) == 0) task,
    ];
    ready.sort(_compareByPriorityThenDue);

    final ordered = <TaskItem>[];
    while (ready.isNotEmpty) {
      final task = ready.removeAt(0);
      ordered.add(task);
      for (final nextId in dependents[task.id] ?? const <String>[]) {
        final next = byId[nextId];
        if (next == null) {
          continue;
        }
        indegree[nextId] = (indegree[nextId] ?? 0) - 1;
        if (indegree[nextId] == 0) {
          ready.add(next);
          ready.sort(_compareByPriorityThenDue);
        }
      }
    }

    final scheduledIds = <String>{};
    final suggestions = <TaskSuggestion>[];
    final nextStartByBlock = <String, DateTime>{
      for (final block in timeBlocks.where((b) => b.available)) block.id: block.start,
    };

    for (final task in ordered) {
      final estimate = task.estimateMinutes;
      TimeBlock? chosenBlock;
      DateTime? start;
      DateTime? end;

      if (estimate != null && estimate > 0) {
        final candidateBlocks = timeBlocks.where((b) => b.available).toList()
          ..sort((a, b) {
            final aMatch = task.tags.contains(a.suitableFor) ? 0 : 1;
            final bMatch = task.tags.contains(b.suitableFor) ? 0 : 1;
            return aMatch.compareTo(bMatch);
          });
        for (final block in candidateBlocks) {
          var cursor = nextStartByBlock[block.id] ?? block.start;
          if (cursor.isBefore(block.start)) {
            cursor = block.start;
          }
          final estimatedEnd = cursor.add(Duration(minutes: estimate));
          if (!estimatedEnd.isAfter(block.end)) {
            chosenBlock = block;
            start = cursor;
            end = estimatedEnd;
            nextStartByBlock[block.id] = estimatedEnd;
            break;
          }
        }
      }

      final reason = _reasonFor(task, chosenBlock != null);
      suggestions.add(
        TaskSuggestion(
          taskId: task.id,
          taskTitle: task.title,
          reason: reason,
          suggestedStart: start,
          suggestedEnd: end,
          timeBlockId: chosenBlock?.id,
        ),
      );
      if (chosenBlock != null) {
        scheduledIds.add(task.id);
      }
    }

    final unscheduled = [
      for (final task in ordered)
        if (!scheduledIds.contains(task.id)) task.id,
    ];

    return TaskScheduleResult(
      suggestions: suggestions,
      unscheduledTaskIds: unscheduled,
    );
  }

  static SuggestionReason _reasonFor(TaskItem task, bool hasTimeBlock) {
    if (task.dependencies.isNotEmpty) {
      return SuggestionReason.dependency;
    }
    if (task.priority == TaskPriority.high) {
      return SuggestionReason.priority;
    }
    if (task.dueAt != null) {
      return SuggestionReason.dueDate;
    }
    if (hasTimeBlock) {
      return SuggestionReason.estimate;
    }
    return SuggestionReason.noTimeBlock;
  }

  static int _compareByPriorityThenDue(TaskItem a, TaskItem b) {
    final priorityCompare = b.priority.index.compareTo(a.priority.index);
    if (priorityCompare != 0) {
      return priorityCompare;
    }
    final aDue = a.dueAt;
    final bDue = b.dueAt;
    if (aDue != null && bDue != null) {
      return aDue.compareTo(bDue);
    }
    if (aDue != null) {
      return -1;
    }
    if (bDue != null) {
      return 1;
    }
    return a.title.compareTo(b.title);
  }
}

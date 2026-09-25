import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/entities/task.dart';
import 'package:furnace/domain/entities/time_block.dart';
import 'package:furnace/domain/services/scheduling/task_scheduler.dart';

void main() {
  group('TaskScheduler', () {
    test('sorts high priority before low priority', () {
      final tasks = [
        const TaskItem(
          id: 'low',
          title: 'Low',
          priority: TaskPriority.low,
        ),
        const TaskItem(
          id: 'high',
          title: 'High',
          priority: TaskPriority.high,
        ),
      ];

      final result = TaskScheduler.schedule(tasks: tasks, timeBlocks: const []);

      expect(result.suggestions.map((s) => s.taskId).toList(), ['high', 'low']);
    });

    test('dependencies come before dependents', () {
      final tasks = [
        const TaskItem(
          id: 'b',
          title: 'B',
          dependencies: ['a'],
        ),
        const TaskItem(
          id: 'a',
          title: 'A',
          priority: TaskPriority.low,
        ),
      ];

      final result = TaskScheduler.schedule(tasks: tasks, timeBlocks: const []);

      expect(result.suggestions.map((s) => s.taskId).toList(), ['a', 'b']);
    });

    test('fits task into available time block', () {
      final tasks = [
        const TaskItem(
          id: 't1',
          title: 'Task 1',
          estimateMinutes: 30,
        ),
      ];
      final blocks = [
        TimeBlock(
          id: 'b1',
          title: 'Block 1',
          start: DateTime(2026, 8, 19, 19),
          end: DateTime(2026, 8, 19, 21),
        ),
      ];

      final result = TaskScheduler.schedule(tasks: tasks, timeBlocks: blocks);

      expect(result.suggestions.single.suggestedStart,
          DateTime(2026, 8, 19, 19));
      expect(result.suggestions.single.suggestedEnd,
          DateTime(2026, 8, 19, 19, 30));
      expect(result.suggestions.single.timeBlockId, 'b1');
      expect(result.unscheduledTaskIds, isEmpty);
    });

    test('prefers block whose suitableFor matches task tag', () {
      final tasks = [
        const TaskItem(
          id: 't1',
          title: '背单词',
          estimateMinutes: 30,
          tags: ['memorize'],
        ),
      ];
      final blocks = [
        TimeBlock(
          id: 'b1',
          title: '普通时间',
          start: DateTime(2026, 8, 19, 19),
          end: DateTime(2026, 8, 19, 21),
        ),
        TimeBlock(
          id: 'b2',
          title: '背诵时间',
          start: DateTime(2026, 8, 19, 18),
          end: DateTime(2026, 8, 19, 20),
          suitableFor: 'memorize',
        ),
      ];

      final result = TaskScheduler.schedule(tasks: tasks, timeBlocks: blocks);

      expect(result.suggestions.single.timeBlockId, 'b2');
    });

    test('reports unscheduled when block too short', () {
      final tasks = [
        const TaskItem(
          id: 't1',
          title: 'Task 1',
          estimateMinutes: 120,
        ),
      ];
      final blocks = [
        TimeBlock(
          id: 'b1',
          title: 'Block 1',
          start: DateTime(2026, 8, 19, 19),
          end: DateTime(2026, 8, 19, 20),
        ),
      ];

      final result = TaskScheduler.schedule(tasks: tasks, timeBlocks: blocks);

      expect(result.unscheduledTaskIds, ['t1']);
    });
  });
}

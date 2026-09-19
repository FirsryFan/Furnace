import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/scheduling/task_scheduler.dart';

/// Loads all tasks for the task list.
final taskListProvider = FutureProvider<List<Task>>((ref) {
  return ref.watch(taskRepositoryProvider).getTasks();
});

/// Loads current task/time data and computes scheduling suggestions.
final scheduleSuggestionsProvider = FutureProvider<TaskScheduleResult>((ref) {
  return ref.watch(taskSchedulerServiceProvider).scheduleNow();
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/repositories/tag_repository.dart';
import '../../../data/repositories/task_repository.dart';
import '../../../data/repositories/thread_rank_repository.dart';
import '../../../data/repositories/thread_state_repository.dart';
import '../../../data/repositories/time_block_repository.dart';
import '../../../domain/services/config/furnace_defaults.dart';
import '../../../domain/services/scheduling/thread_ranker.dart';
import '../../../domain/services/scheduling/time_window_engine.dart';

/// One computed Thread feed.
///
/// The ranking result is deliberately NOT persisted (blueprint 2.7 / user
/// annotation 12): it lives only in memory, and a cold start simply asks for a
/// re-sort. [computedAt] is kept so the UI can say "sorted N minutes ago".
class ThreadFeed {
  const ThreadFeed({
    required this.ranked,
    required this.tasks,
    required this.computedAt,
    required this.weights,
  });

  final RankOutput ranked;

  /// Task rows the ranking was computed from, by id.
  final Map<String, Task> tasks;

  final DateTime computedAt;
  final RankWeights weights;

  /// The event rows that can be worked on right now, in ranked order.
  List<Task> get readyTasks => [
        for (final ranked in ranked.ready)
          if (tasks[ranked.event.id] != null) tasks[ranked.event.id]!,
      ];

  /// Completed events (from the task table, newest completion first).
  List<Task> get completedTasks => [
        for (final task in tasks.values)
          if (task.status == 'done') task,
      ]..sort((a, b) => (b.completedAt ?? 0).compareTo(a.completedAt ?? 0));

  Task? taskFor(String id) => tasks[id];
}

/// Builds a ranked feed from the stored events, schedule blocks, completion
/// history and the user's own (editable) weights.
class ThreadRankService {
  ThreadRankService({
    required this.taskRepository,
    required this.timeBlockRepository,
    required this.tagRepository,
    required this.threadRankRepository,
    required this.threadStateRepository,
  });

  final TaskRepository taskRepository;
  final TimeBlockRepository timeBlockRepository;
  final TagRepository tagRepository;
  final ThreadRankRepository threadRankRepository;
  final ThreadStateRepository threadStateRepository;

  /// Computes the feed for [now]. Never touches the database to write.
  Future<ThreadFeed> build({DateTime? now}) async {
    final moment = now ?? DateTime.now();

    final List<Task> tasks = await taskRepository.getTasks();
    final List<TimeBlock> blocks = await timeBlockRepository.getTimeBlocks();
    final ThreadState? state = await threadStateRepository.getState();
    final RankWeights weights = await threadRankRepository.getWeights();

    final completions = await taskRepository.getCompletionLogs(
      sinceMs: moment
          .subtract(Duration(minutes: FurnaceDefaults.fatigueWindowMinutes))
          .millisecondsSinceEpoch,
    );

    final tagPaths = <String, List<String>>{};
    for (final task in tasks) {
      final tags = await tagRepository.tagsForObject(
        objectType: 'task',
        objectId: task.id,
      );
      tagPaths[task.id] = [
        for (final tag in tags)
          if (tag.path != null && tag.path!.isNotEmpty) tag.path!,
      ];
    }

    final rankCompletions = <RankCompletion>[];
    for (final log in completions) {
      rankCompletions.add(RankCompletion(
        completedAt: DateTime.fromMillisecondsSinceEpoch(log.completedAt),
        tagPaths: _decodeList(log.tagPaths),
      ));
    }

    final events = <RankEvent>[];
    for (final task in tasks) {
      if (task.status == 'done') {
        continue; // completed events belong to the archive view
      }
      events.add(RankEvent(
        id: task.id,
        title: task.title,
        estimateMinutes: task.estimateMinutes,
        expectedAt: task.expectedAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(task.expectedAt!),
        dueAt: task.dueAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(task.dueAt!),
        energyRequired: task.energyRequired,
        tagPaths: tagPaths[task.id] ?? const [],
      ));
    }

    final ranked = ThreadRanker.rank(
      events: events,
      context: RankContext(
        now: moment,
        energy: state?.energy,
        goal: RankGoal(text: state?.goalText),
        blocks: [
          for (final block in blocks)
            ScheduleBlock(
              id: block.id,
              title: block.title,
              startAt: DateTime.fromMillisecondsSinceEpoch(block.startAt),
              endAt: DateTime.fromMillisecondsSinceEpoch(block.endAt),
              available: block.available,
              repeatRule: block.repeatRule,
            ),
        ],
        completions: rankCompletions,
        weights: weights,
      ),
    );

    return ThreadFeed(
      ranked: ranked,
      tasks: {for (final task in tasks) task.id: task},
      computedAt: moment,
      weights: weights,
    );
  }

  static List<String> _decodeList(String? encoded) {
    if (encoded == null || encoded.isEmpty) {
      return const [];
    }
    return encoded.split('\u0001').where((e) => e.isNotEmpty).toList();
  }
}

/// In-memory Thread feed. `null` = not sorted yet since app start, which the
/// UI surfaces as "需要重新排序" instead of silently showing a stale order.
class ThreadFeedNotifier extends AsyncNotifier<ThreadFeed?> {
  @override
  Future<ThreadFeed?> build() async => null;

  /// Recomputes the ranking. Returns the staleness of the status bar at the
  /// moment of the call so the caller can run the >2h confirmation prompt
  /// before actually sorting (blueprint 2.2 / user annotation 10).
  Future<bool> isStateStale() async {
    final repo = ref.read(threadStateRepositoryProvider);
    return repo.isStale(FurnaceDefaults.stateStaleAfter);
  }

  /// Runs the sort and publishes the result.
  Future<void> sort() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(threadRankServiceProvider).build(),
    );
  }
}

/// The live Thread status bar state (energy + goal), read by the status bar.
/// Invalidate it after any write so the bar reflects the new value.
final threadStateProvider = FutureProvider<ThreadState?>((ref) {
  return ref.watch(threadStateRepositoryProvider).getState();
});

/// The user's current (possibly edited) ranking weights. Read by the usage
/// documentation page and by the weights editor.
final currentWeightsProvider = FutureProvider<RankWeights>((ref) {
  return ref.watch(threadRankRepositoryProvider).getWeights();
});

final threadRankServiceProvider = Provider<ThreadRankService>((ref) {
  return ThreadRankService(
    taskRepository: ref.watch(taskRepositoryProvider),
    timeBlockRepository: ref.watch(timeBlockRepositoryProvider),
    tagRepository: ref.watch(tagRepositoryProvider),
    threadRankRepository: ref.watch(threadRankRepositoryProvider),
    threadStateRepository: ref.watch(threadStateRepositoryProvider),
  );
});

final threadFeedProvider =
    AsyncNotifierProvider<ThreadFeedNotifier, ThreadFeed?>(
  ThreadFeedNotifier.new,
);

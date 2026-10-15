import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/database/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/repositories/tag_repository.dart';
import '../../../data/repositories/task_repository.dart';
import '../../../data/repositories/thread_rank_repository.dart';
import '../../../data/repositories/thread_state_repository.dart';
import '../../../data/repositories/time_block_repository.dart';
import '../../../domain/services/config/furnace_defaults.dart';
import '../../../domain/services/scheduling/domain_balance.dart';
import '../../../domain/services/scheduling/thread_balance_inputs.dart';
import '../../../domain/services/scheduling/thread_ranker.dart';
import '../../../domain/services/scheduling/time_window_engine.dart';
import 'thread_balance_provider.dart';

/// One computed Thread feed.
///
/// The ranking result is deliberately NOT persisted (blueprint 2.7 / user
/// annotation 12): it lives only in memory, and a cold start simply asks for a
/// re-sort. [computedAt] is kept so the UI can say "sorted N minutes ago".
///
/// Two orders live in here on purpose:
///
/// * [ranked] is segment A (`ThreadRanker`): the hard constraints, unchanged -
///   anything that inspects "is this even feasible" keeps using it;
/// * [balanced] is segment B (`DomainBalanceRanker`): the recommended order
///   after domain balance and cognitive effectiveness, plus the reason line.
///   [readyTasks] follows it, and [reasonFor] is what the UI renders.
class ThreadFeed {
  const ThreadFeed({
    required this.ranked,
    required this.tasks,
    required this.computedAt,
    required this.weights,
    this.balanced,
  });

  final RankOutput ranked;

  /// Segment B's output; `null` only for a feed built without the balance step
  /// (tests that only care about segment A).
  final DomainBalanceOutput? balanced;

  /// Task rows the ranking was computed from, by id.
  final Map<String, Task> tasks;

  final DateTime computedAt;
  final RankWeights weights;

  /// The event rows that can be worked on right now, in the recommended order.
  ///
  /// Segment B's greedy order wins when it exists; segment A's order is the
  /// fallback and also the safety net for any ready task segment B did not
  /// mention (it should be a subset, but the UI must never lose a task).
  List<Task> get readyTasks {
    final output = balanced;
    if (output == null || output.ranked.isEmpty) {
      return [
        for (final ranked in ranked.ready)
          if (tasks[ranked.event.id] != null) tasks[ranked.event.id]!,
      ];
    }
    final seen = <String>{};
    final ordered = <Task>[];
    for (final entry in output.ranked) {
      final task = tasks[entry.taskId];
      if (task != null && seen.add(entry.taskId)) {
        ordered.add(task);
      }
    }
    for (final ranked in ranked.ready) {
      final task = tasks[ranked.event.id];
      if (task != null && seen.add(ranked.event.id)) {
        ordered.add(task);
      }
    }
    return ordered;
  }

  /// Completed events (from the task table, newest completion first).
  List<Task> get completedTasks => [
        for (final task in tasks.values)
          if (task.status == 'done') task,
      ]..sort((a, b) => (b.completedAt ?? 0).compareTo(a.completedAt ?? 0));

  Task? taskFor(String id) => tasks[id];

  /// Segment B's line for one task, or null when it has none.
  BalancedTask? balanceFor(String taskId) {
    final output = balanced;
    if (output == null) {
      return null;
    }
    for (final entry in output.ranked) {
      if (entry.taskId == taskId) {
        return entry;
      }
    }
    return null;
  }

  /// "Why is it here" in one Chinese sentence (null = no balance data).
  String? reasonFor(String taskId) => balanceFor(taskId)?.reasonZh;
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
  ///
  /// [balance] is segment B's external input (tag mounts + cognitive readings).
  /// The default is "know nothing": the feed is still built, but the
  /// effectiveness term is neutral and every task lands in `未分类`.
  Future<ThreadFeed> build({
    DateTime? now,
    ThreadBalanceInputs balance = ThreadBalanceInputs.empty,
  }) async {
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

    final context = RankContext(
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
    );

    final ranked = ThreadRanker.rank(events: events, context: context);

    // 段落 B 永远跑：空输入时它退化成"没有个性化信息的中性排序"，但仍然给出
    // 领域配额与理由。它不重算可行域——红名单/超期桶原样来自段落 A。
    final balanced = DomainBalanceRanker.rank(
      events: events,
      context: context,
      taskKnowledgePoints: balance.taskKnowledgePoints,
      readings: balance.readings,
      tags: balance.tags,
      taskTagLinks: balance.taskTagLinks,
      knowledgePointNames: balance.knowledgePointNames,
      weights: balance.weights,
      tuning: balance.tuning,
      windowSlots: balance.windowSlots,
    );

    return ThreadFeed(
      ranked: ranked,
      balanced: balanced,
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
  Future<ThreadFeed?> build() async {
    // 段落 B 的输入 provider 是 autoDispose（它的上游诊断 provider 也是），而
    // 这个 feed 要活到用户下次点"排序"为止：这里订阅一次让它跟着 feed 存活，
    // 但**不**因为输入变化而重建——否则每次数据库写入都会把已经排好的顺序清掉
    // （页面用"需要重新排序"的提示来表达陈旧，而不是自己清空）。
    ref.listen(threadBalanceInputsProvider, (_, __) {});
    return null;
  }

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
    state = await AsyncValue.guard(() async {
      final balance = await _balanceInputs();
      return ref.read(threadRankServiceProvider).build(balance: balance);
    });
  }

  /// Segment B's inputs. A read failure is not a sort failure: the feed simply
  /// falls back to "no personal signal" (segment A order, neutral
  /// effectiveness), which is exactly what the pre-Q6 app did.
  Future<ThreadBalanceInputs> _balanceInputs() async {
    try {
      return await ref.read(threadBalanceInputsProvider.future);
    } catch (_) {
      return ThreadBalanceInputs.empty;
    }
  }
}

/// The live Thread status bar state (energy + goal), read by the status bar.
/// Re-runs after any database write, so the bar reflects the new value without
/// a restart.
final threadStateProvider = FutureProvider<ThreadState?>((ref) {
  ref.watchDatabaseRevision();
  return ref.watch(threadStateRepositoryProvider).getState();
});

/// The user's current (possibly edited) ranking weights. Read by the usage
/// documentation page and by the weights editor.
final currentWeightsProvider = FutureProvider<RankWeights>((ref) {
  ref.watchDatabaseRevision();
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

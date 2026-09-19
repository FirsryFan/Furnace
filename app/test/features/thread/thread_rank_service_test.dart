import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowflow/data/database/database.dart';
import 'package:knowflow/data/repositories/tag_repository.dart';
import 'package:knowflow/data/repositories/task_repository.dart';
import 'package:knowflow/data/repositories/thread_rank_repository.dart';
import 'package:knowflow/data/repositories/thread_state_repository.dart';
import 'package:knowflow/data/repositories/time_block_repository.dart';
import 'package:knowflow/features/thread/application/thread_rank_service.dart';

/// End-to-end glue: stored events + schedule blocks + status bar + editable
/// weights -> a ranked feed the UI can render.
void main() {
  late AppDatabase db;
  late ThreadRankService service;
  late TaskRepository tasks;
  late ThreadStateRepository states;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tasks = TaskRepository(db);
    states = ThreadStateRepository(db);
    service = ThreadRankService(
      taskRepository: tasks,
      timeBlockRepository: TimeBlockRepository(db),
      tagRepository: TagRepository(db),
      threadRankRepository: ThreadRankRepository(db),
      threadStateRepository: states,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('goal and energy from the status bar drive the ordering', () async {
    final late = await tasks.createTask(
      title: '随便一件事',
      estimateMinutes: 20,
      dueAt: DateTime.now().add(const Duration(days: 5)).millisecondsSinceEpoch,
    );
    final urgent = await tasks.createTask(
      title: '马上要交',
      estimateMinutes: 20,
      dueAt: DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
    );

    // No status set yet: urgency alone separates them.
    final before = await service.build();
    expect(before.ranked.ready.first.event.id, urgent.id);

    // A goal that only matches the far event flips the order once the weights
    // say goal match matters more than urgency.
    final tags = TagRepository(db);
    final tag = await tags.createTag(name: '数学');
    await tags.addTagToObject(
      tagId: tag.id,
      objectType: 'task',
      objectId: late.id,
    );
    await states.updateState(energy: 5, goalText: '数学');
    await ThreadRankRepository(db).updateWeights(
      urgency: 0.1,
      goal: 0.9,
      fit: 0,
      fatigue: 0,
      expected: 0,
    );

    final after = await service.build();
    expect(after.ranked.ready.first.event.id, late.id,
        reason: 'the goal-matching event wins with goal-heavy weights');
    expect(late.id, isNot(urgent.id));
  });

  test('an overdue deadline lands in the archive buckets, not the stream',
      () async {
    final overdue = await tasks.createTask(
      title: '已经晚了',
      estimateMinutes: 30,
      dueAt: DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch,
    );
    final tooBig = await tasks.createTask(
      title: '装不下',
      estimateMinutes: 500,
      dueAt: DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
    );
    final normal = await tasks.createTask(title: '正常', estimateMinutes: 15);

    final feed = await service.build();
    expect(feed.ranked.overdue.single.event.id, overdue.id);
    expect(feed.ranked.insufficient.single.event.id, tooBig.id);
    expect(feed.readyTasks.map((t) => t.id), [normal.id]);
  });

  test('completed events leave the stream and appear in the archive', () async {
    final task = await tasks.createTask(title: '做完了', estimateMinutes: 10);
    await tasks.startTask(
      task.id,
      at: DateTime.now().subtract(const Duration(minutes: 12)),
    );
    await tasks.completeTask(task.id, estimateMinutes: 10);

    final feed = await service.build();
    expect(feed.readyTasks, isEmpty);
    expect(feed.completedTasks.single.id, task.id);

    final logs = await db.select(db.completionLogs).get();
    expect(logs.single.actualMinutes, inInclusiveRange(11, 13));
  });

  test('busy hard blocks eat into the deadline budget', () async {
    final moment = DateTime(2026, 9, 8, 20);
    final blocks = TimeBlockRepository(db);
    await blocks.createTimeBlock(
      title: '晚自习',
      startAt: moment.add(const Duration(minutes: 10)).millisecondsSinceEpoch,
      endAt: moment.add(const Duration(minutes: 40)).millisecondsSinceEpoch,
      available: false,
    );
    final task = await tasks.createTask(
      title: '需要 31 分钟',
      estimateMinutes: 31,
      dueAt: moment.add(const Duration(minutes: 60)).millisecondsSinceEpoch,
    );

    final feed = await service.build(now: moment);
    final ranked = feed.ranked.insufficient.single;
    expect(ranked.event.id, task.id);
    expect(ranked.availableMinutes, 30, reason: '60 minutes minus 30 busy');
  });

  test('the expected moment carries a yellow flag without turning red',
      () async {
    final moment = DateTime(2026, 9, 8, 20);
    final soon = await tasks.createTask(
      title: '打算现在做',
      estimateMinutes: 20,
      expectedAt: moment.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch,
    );

    final feed = await service.build(now: moment);
    expect(feed.ranked.insufficient, isEmpty);
    expect(feed.ranked.overdue, isEmpty);
    expect(feed.ranked.ready.single.event.id, soon.id);
    expect(feed.ranked.ready.single.expectedNear, isTrue);
  });
}

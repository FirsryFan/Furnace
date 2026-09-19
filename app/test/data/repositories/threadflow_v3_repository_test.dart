import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowflow/data/database/database.dart';
import 'package:knowflow/data/repositories/task_repository.dart';
import 'package:knowflow/data/repositories/thread_rank_repository.dart';

/// Actual-duration bookkeeping (blueprint 2.6, user annotation 14): two
/// stamps, no ticking timer, and an anomaly guard the user can override.
void main() {
  late AppDatabase db;
  late TaskRepository tasks;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tasks = TaskRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('start stamp is written and survives an unrelated edit', () async {
    final task = await tasks.createTask(title: '写作文', estimateMinutes: 40);
    expect(task.startedAt, isNull);

    final started = DateTime(2026, 9, 8, 20);
    await tasks.startTask(task.id, at: started);
    expect((await tasks.getTaskById(task.id))!.startedAt,
        started.millisecondsSinceEpoch);

    await tasks.updateTask(task.id, energyRequired: 7);
    expect((await tasks.getTaskById(task.id))!.startedAt,
        started.millisecondsSinceEpoch,
        reason: 'a later edit must not wipe the start stamp');

    await tasks.updateTask(task.id, clearStartedAt: true);
    expect((await tasks.getTaskById(task.id))!.startedAt, isNull);
  });

  test('completing records actual minutes and is model-eligible', () async {
    final task = await tasks.createTask(title: '背单词', estimateMinutes: 30);
    await tasks.startTask(
      task.id,
      at: DateTime.now().subtract(const Duration(minutes: 28)),
    );

    await tasks.completeTask(
      task.id,
      tagPaths: const ['英语/单词'],
      estimateMinutes: 30,
    );

    final log = (await db.select(db.completionLogs).get()).single;
    expect(log.taskId, task.id);
    expect(log.actualMinutes, inInclusiveRange(27, 30));
    expect(log.durationSuspicious, isFalse);
    expect(log.includeInModel, isTrue);
    expect(log.tagPaths, '英语/单词');

    final done = await tasks.getTaskById(task.id);
    expect(done!.status, 'done');
    expect(done.completedAt, isNotNull);
  });

  test('a suspiciously long record is excluded by default', () async {
    final task = await tasks.createTask(title: '忘关了', estimateMinutes: 10);
    await tasks.startTask(
      task.id,
      at: DateTime.now().subtract(const Duration(minutes: 100)),
    );
    await tasks.completeTask(task.id, estimateMinutes: 10);

    final log = (await db.select(db.completionLogs).get()).single;
    expect(log.durationSuspicious, isTrue);
    expect(log.includeInModel, isFalse);
    expect(log.actualMinutes, greaterThanOrEqualTo(100));

    // The user can flip it back on for this single record.
    await tasks.setCompletionInModel(log.id, true);
    final flipped = (await db.select(db.completionLogs).get()).single;
    expect(flipped.includeInModel, isTrue);
  });

  test('an event without a start stamp records no actual duration', () async {
    final task = await tasks.createTask(title: '直接完成', estimateMinutes: 20);
    await tasks.completeTask(task.id, estimateMinutes: 20);

    final log = (await db.select(db.completionLogs).get()).single;
    expect(log.actualMinutes, isNull);
    expect(log.includeInModel, isTrue);
    expect(log.durationSuspicious, isFalse);
  });

  test('the global switch keeps actual time out of the model', () async {
    final task = await tasks.createTask(title: '不参考', estimateMinutes: 30);
    await tasks.startTask(
      task.id,
      at: DateTime.now().subtract(const Duration(minutes: 30)),
    );
    await tasks.completeTask(
      task.id,
      estimateMinutes: 30,
      useActualTime: false,
    );

    final log = (await db.select(db.completionLogs).get()).single;
    expect(log.actualMinutes, isNotNull,
        reason: 'the duration is still recorded for the user to see');
    expect(log.includeInModel, isFalse,
        reason: 'but it must not inform the model');
  });

  test('duration calibration averages eligible records only', () async {
    expect(await tasks.getDurationCalibration(), isNull);

    // Eligible: 60 actual / 30 estimated = 2.0
    final first = await tasks.createTask(title: 'a', estimateMinutes: 30);
    await tasks.startTask(
      first.id,
      at: DateTime.now().subtract(const Duration(minutes: 60)),
    );
    await tasks.completeTask(first.id, estimateMinutes: 30);

    // Eligible: 30 actual / 30 estimated = 1.0  -> mean 1.5
    final second = await tasks.createTask(title: 'b', estimateMinutes: 30);
    await tasks.startTask(
      second.id,
      at: DateTime.now().subtract(const Duration(minutes: 30)),
    );
    await tasks.completeTask(second.id, estimateMinutes: 30);

    // Not eligible (user turned the model off).
    final third = await tasks.createTask(title: 'c', estimateMinutes: 10);
    await tasks.startTask(
      third.id,
      at: DateTime.now().subtract(const Duration(minutes: 500)),
    );
    await tasks.completeTask(third.id, estimateMinutes: 10);

    final calibration = await tasks.getDurationCalibration();
    expect(calibration, isNotNull);
    expect(calibration!, closeTo(1.5, 0.02));
  });

  test('ranking settings round-trip through the repository', () async {
    final rank = ThreadRankRepository(db);
    await rank.setHeaderCollapsed(true);
    await rank.setUseActualTime(false);
    await rank.updateWeightsFrom(await rank.getWeights());

    expect(await rank.isHeaderCollapsed(), isTrue);
    expect(await rank.getUseActualTime(), isFalse);
    final row = (await db.select(db.threadRankSettings).get()).single;
    expect(row.id, 1, reason: 'single-row table');
    expect(row.updatedAt, isNotNull);
  });
}

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/domain/services/scheduling/thread_windows.dart';
import 'package:furnace/domain/services/thread/thread_node_kind.dart';
import 'package:furnace/domain/services/thread/thread_rollup.dart';
import 'package:furnace/domain/services/thread/thread_status.dart';
import 'package:furnace/features/thread/application/thread_rollup_projection.dart';

/// `thread_rollup_projection.dart`（应用层，2026-11-15）：把 `Task` 行分组喂给
/// domain 的 `ThreadRollup`，并把窗口桶里的同类容器合并给 chips。
///
/// 要锁的行为：
///
///  * 只有**有子节点**的父节点进 map；叶子任务不进（UI 据此不多画一行空汇总）；
///  * 汇总结果与 domain 规则一致（状态/计数/估时/进度来自同一份纯函数）；
///  * **只读**：算一次 rollup 不写 `tasks`、不写 `thread_events`，父容器状态
///    保持原样（本任务的核心验收）；
///  * 窗口聚合只取指定 kind，避免周容器锚点落在日窗口时把整周算成"本日"。
void main() {
  group('threadRollupsOf', () {
    late AppDatabase db;
    late TaskRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = TaskRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('按 parentId 分组：父容器得到汇总，叶子任务不进 map', () async {
      final parent = await repo.createTask(
        title: '第 46 周组卷',
        kind: ThreadNodeKind.week,
        sourceKey: 'paper:week:2026-W46:rollup-test',
      );
      final done = await repo.createTask(
        title: '第 1 题',
        parentId: parent.id,
        estimateMinutes: 10,
      );
      final doing = await repo.createTask(
        title: '第 2 题',
        parentId: parent.id,
        estimateMinutes: 5,
      );
      await repo.startTask(doing.id);
      await repo.completeTask(done.id);

      final rollups = threadRollupsOf(await repo.getTasks());

      expect(rollups.keys, contains(parent.id));
      expect(rollups.keys, isNot(contains(done.id)));
      expect(rollups.keys, isNot(contains(doing.id)));

      final rollup = rollups[parent.id]!;
      expect(rollup.parentId, parent.id);
      expect(rollup.status, ThreadStatus.doing);
      expect(rollup.counts.total, 2);
      expect(rollup.counts.done, 1);
      expect(rollup.counts.doing, 1);
      expect(rollup.estimateMinutes, 15);
      expect(rollup.percent, 50);
    });

    test('只读：算 rollup 不写父状态、不写新事件', () async {
      final parent = await repo.createTask(
        title: '周容器',
        kind: ThreadNodeKind.week,
        sourceKey: 'paper:week:2026-W46:readonly-test',
      );
      final child = await repo.createTask(
        title: '子任务',
        parentId: parent.id,
        estimateMinutes: 8,
      );

      List<String> snapshotTasks(List<Task> tasks) => [
            for (final task in tasks)
              '${task.id}:${task.status}:${task.updatedAt}',
          ];
      Future<List<String>> snapshotEvents() async {
        final rows = await db.select(db.threadEvents).get();
        return [for (final row in rows) '${row.id}:${row.taskId}:${row.kind}'];
      }

      final tasksBefore = snapshotTasks(await db.select(db.tasks).get());
      final eventsBefore = await snapshotEvents();

      final rollups = threadRollupsOf(await repo.getTasks());
      expect(rollups[parent.id], isNotNull);

      expect(snapshotTasks(await db.select(db.tasks).get()), tasksBefore);
      expect(await snapshotEvents(), eventsBefore);
      expect((await repo.getTaskById(parent.id))!.status, 'todo');
      expect((await repo.getTaskById(child.id))!.status, 'todo');
    });
  });

  group('threadContainerRollupOf', () {
    ThreadRollup rollupFor(String parentId, List<ThreadStatus> statuses) =>
        ThreadRollup.of(
          parent: ThreadRollupNode(id: parentId, status: ThreadStatus.todo),
          children: [
            for (var i = 0; i < statuses.length; i++)
              ThreadRollupNode(
                id: '$parentId-$i',
                status: statuses[i],
                parentId: parentId,
              ),
          ],
        );

    test('只汇总指定 kind 的容器（周 chip 不吞掉日容器）', () {
      final rollups = <String, ThreadRollup>{
        'w': rollupFor('w', [
          ThreadStatus.done,
          ThreadStatus.todo,
        ]),
        'd': rollupFor('d', [
          ThreadStatus.done,
          ThreadStatus.done,
        ]),
      };
      final nodes = [
        const ThreadWindowNode(
          id: 'w',
          kind: ThreadNodeKind.week,
          status: ThreadStatus.todo,
        ),
        const ThreadWindowNode(
          id: 'd',
          kind: ThreadNodeKind.day,
          status: ThreadStatus.todo,
        ),
      ];

      final week = threadContainerRollupOf(
        nodes: nodes,
        rollups: rollups,
        kind: ThreadNodeKind.week,
      );
      expect(week, isNotNull);
      expect(week!.counts.total, 2);
      expect(week.counts.done, 1);
      expect(week.percent, 50);

      final day = threadContainerRollupOf(
        nodes: nodes,
        rollups: rollups,
        kind: ThreadNodeKind.day,
      );
      expect(day, isNotNull);
      expect(day!.percent, 100);
    });

    test('窗口里没有该 kind 的容器 → null（chips 不显示假的 0/0）', () {
      final nodes = [
        const ThreadWindowNode(
          id: 'd',
          kind: ThreadNodeKind.day,
          status: ThreadStatus.todo,
        ),
      ];
      expect(
        threadContainerRollupOf(
          nodes: nodes,
          rollups: const {},
          kind: ThreadNodeKind.week,
        ),
        isNull,
      );
    });
  });
}

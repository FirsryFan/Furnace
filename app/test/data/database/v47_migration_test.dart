import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/domain/services/thread/thread_event_kind.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v46 -> v47：ThreadFlow 内容整合底座
/// （`INTEGRATION-CONTRACT-2026-11-15.md` §2.2 / §3.1 / §3.4）。
///
/// 五条独立可失败的断言：
///
///  1. 真实 v46 文件打开后升级到 v47：`content_refs` / `thread_events` 两表建成
///     且为空，`tasks.kind` / `tasks.source_key` 两列补上；老任务、老完成记录、
///     老标签一行不少、一个字段不变。
///  2. 升级来的两列是 NULL（老行语义 = `task` / 没有幂等键），迁移**不回填**。
///  3. 迁移可重复执行：连开两次库不抛错、数据不变、版本停在 47。
///  4. 版本号被盖成 v47 但表/列没写的文件，由 `beforeOpen` 自愈补出来（Drift
///     在版本已是当前值时跳过 onUpgrade —— 与 v24/v31/v37/v42/v45 同一个坑）。
///  5. 全新库（onCreate）就是 v47：两表 + 两列 + `source_key` 唯一索引都在。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig47_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 当前 schema 的库 + 一组"v47 以前就存在"的数据，然后把 v47 的结构拆掉、
  /// `user_version` 压回 [userVersion] —— 就是一个 v46 安装升级前的文件。
  Future<File> buildPreV47Db({
    required String name,
    int userVersion = 46,
  }) async {
    final file = File('${tempDir.path}/$name.db');
    final fresh = AppDatabase.forTesting(NativeDatabase(file));
    await fresh.into(fresh.tags).insert(
          TagsCompanion.insert(
            id: 'tag-old',
            name: '物理',
            path: const Value('物理'),
            createdAt: 1700000000000,
            updatedAt: 1700000000000,
          ),
        );
    await fresh.into(fresh.tasks).insert(
          TasksCompanion.insert(
            id: 'task-old',
            title: 'v46 的老任务',
            description: const Value('升级不能动我'),
            status: const Value('doing'),
            estimateMinutes: const Value(25),
            createdAt: 1700000000000,
            updatedAt: 1700000000000,
          ),
        );
    await fresh.into(fresh.completionLogs).insert(
          CompletionLogsCompanion.insert(
            id: 'cl-old',
            taskId: 'task-old',
            title: 'v46 的老完成记录',
            completedAt: 1700000000000,
            createdAt: 1700000000000,
          ),
        );
    await fresh.close();

    final raw = sql.sqlite3.open(file.path);
    try {
      // 先拆索引再拆列：SQLite 不允许 DROP COLUMN 掉一个还被索引引用的列。
      raw.execute('DROP INDEX IF EXISTS idx_tasks_source_key');
      raw.execute('DROP TABLE IF EXISTS content_refs');
      raw.execute('DROP TABLE IF EXISTS thread_events');
      raw.execute('ALTER TABLE tasks DROP COLUMN kind');
      raw.execute('ALTER TABLE tasks DROP COLUMN source_key');
      raw.execute('PRAGMA user_version = $userVersion');
    } finally {
      raw.dispose();
    }
    return file;
  }

  int userVersionOf(String path) {
    final raw = sql.sqlite3.open(path);
    try {
      return raw.select('PRAGMA user_version').single['user_version'] as int;
    } finally {
      raw.dispose();
    }
  }

  Future<List<String>> tableNamesOf(AppDatabase db) async {
    final rows = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    ).get();
    return [for (final row in rows) row.read<String>('name')];
  }

  Future<List<String>> indexNamesOf(AppDatabase db) async {
    final rows = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='index' ORDER BY name",
    ).get();
    return [for (final row in rows) row.read<String>('name')];
  }

  Future<void> expectV47Structure(AppDatabase db) async {
    final tables = await tableNamesOf(db);
    expect(tables, contains('content_refs'));
    expect(tables, contains('thread_events'));
    expect(await db.columnsOf('tasks'), containsAll(<String>['kind', 'source_key']));
    expect(await db.columnsOf('content_refs'), containsAll(<String>[
      'id',
      'content_id',
      'content_version',
      'content_hash',
      'subject',
      'object_type',
      'object_id',
      'role',
      'metadata_json',
      'created_at',
      'updated_at',
    ]));
    expect(await db.columnsOf('thread_events'), containsAll(<String>[
      'id',
      'task_id',
      'kind',
      'payload_json',
      'occurred_at',
      'source_key',
    ]));
    final indexes = await indexNamesOf(db);
    expect(indexes, contains('idx_tasks_source_key'));
    expect(indexes, contains('idx_content_refs_content'));
    expect(indexes, contains('idx_thread_events_task'));
  }

  Future<void> expectOldDataIntact(AppDatabase db) async {
    final tasks = await db.select(db.tasks).get();
    expect(tasks, hasLength(1));
    final task = tasks.single;
    expect(task.id, 'task-old');
    expect(task.title, 'v46 的老任务');
    expect(task.description, '升级不能动我');
    expect(task.status, 'doing');
    expect(task.estimateMinutes, 25);
    // 迁移不回填：老行的两个新列都是 NULL。
    expect(task.kind, isNull);
    expect(task.sourceKey, isNull);

    final logs = await db.select(db.completionLogs).get();
    expect(logs, hasLength(1));
    expect(logs.single.id, 'cl-old');
    expect(logs.single.taskId, 'task-old');
    expect(logs.single.title, 'v46 的老完成记录');

    final tags = await db.select(db.tags).get();
    expect(tags.map((t) => t.id), contains('tag-old'));

    // 两张新表升级后为空：老库没有任何一行需要回填。
    expect(await db.select(db.contentRefs).get(), isEmpty);
    expect(await db.select(db.threadEvents).get(), isEmpty);
  }

  test('v46 文件升级到 v47：两表两列都在，老数据一行不少', () async {
    final file = await buildPreV47Db(name: 'v46_upgrade');
    expect(userVersionOf(file.path), 46);

    final db = AppDatabase.forTesting(NativeDatabase(file));
    await expectV47Structure(db);
    await expectOldDataIntact(db);
    await db.close();

    expect(userVersionOf(file.path), 47);
  });

  test('迁移可重复执行：连开两次不抛错、数据不变、版本停在 47', () async {
    final file = await buildPreV47Db(name: 'twice');

    var db = AppDatabase.forTesting(NativeDatabase(file));
    await expectV47Structure(db);
    await expectOldDataIntact(db);
    await db.close();
    expect(userVersionOf(file.path), 47);

    // 第二次打开：onUpgrade 不再跑，只剩 beforeOpen 的空转探测。
    db = AppDatabase.forTesting(NativeDatabase(file));
    await expectV47Structure(db);
    await expectOldDataIntact(db);
    await db.close();
    expect(userVersionOf(file.path), 47);
  });

  test('版本号盖成 v47 但结构缺失的文件由 beforeOpen 自愈', () async {
    final file = await buildPreV47Db(name: 'fake47', userVersion: 47);
    expect(userVersionOf(file.path), 47);

    // 没有自愈的话，下面这几次读写会抛 no such table / no such column。
    final db = AppDatabase.forTesting(NativeDatabase(file));
    await expectV47Structure(db);
    await expectOldDataIntact(db);
    await db.close();
    expect(userVersionOf(file.path), 47, reason: '已经是最新版本，不再迁移');
  });

  test('全新库（onCreate）就是 v47：两表两列与索引都在', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    expect(db.schemaVersion, 47);
    // 触发 onCreate。
    await db.select(db.localSettings).get();
    await expectV47Structure(db);
    await db.close();
  });

  test('tasks.source_key 的部分唯一索引拒绝重复的幂等键', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.tasks).insert(
          TasksCompanion.insert(
            id: 'task-1',
            title: '第一个计划节点',
            sourceKey: const Value('day:2026-11-15'),
            createdAt: 1,
            updatedAt: 1,
          ),
        );
    // 不同 source_key、以及多个 NULL 都必须允许（老库全是 NULL）。
    await db.into(db.tasks).insert(
          TasksCompanion.insert(
            id: 'task-2',
            title: '第二个计划节点',
            sourceKey: const Value('day:2026-11-16'),
            createdAt: 2,
            updatedAt: 2,
          ),
        );
    await db.into(db.tasks).insert(
          TasksCompanion.insert(
            id: 'task-3',
            title: '没有幂等键的老式任务',
            createdAt: 3,
            updatedAt: 3,
          ),
        );
    await db.into(db.tasks).insert(
          TasksCompanion.insert(
            id: 'task-4',
            title: '另一个没有幂等键的老式任务',
            createdAt: 4,
            updatedAt: 4,
          ),
        );
    // 同一个 source_key 第二次：唯一索引必须拒绝。
    await expectLater(
      db.into(db.tasks).insert(
            TasksCompanion.insert(
              id: 'task-duplicate',
              title: '重复的计划节点',
              sourceKey: const Value('day:2026-11-15'),
              createdAt: 5,
              updatedAt: 5,
            ),
          ),
      throwsA(anything),
    );
    await db.close();
  });

  test('升级后的老任务可经 TaskRepository 完成：事件落到 v47 新表，kind 仍 NULL',
      () async {
    final file = await buildPreV47Db(name: 'wiring');
    final db = AppDatabase.forTesting(NativeDatabase(file));
    await expectV47Structure(db);

    final repo = TaskRepository(db);
    await repo.completeTask('task-old');

    final task = await repo.getTaskById('task-old');
    expect(task!.status, 'done');
    expect(task.completedAt, isNotNull);
    expect(task.kind, isNull, reason: '迁移不回填老行的 kind');

    final events = await db.select(db.threadEvents).get();
    expect(events, hasLength(1));
    expect(events.single.taskId, 'task-old');
    expect(events.single.kind, ThreadEventKind.completed.id);

    // 老完成记录仍在，新完成记录追加一条（完成历史只增不减）。
    expect(await db.select(db.completionLogs).get(), hasLength(2));
    await db.close();
  });
}

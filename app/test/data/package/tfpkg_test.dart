import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowflow/data/database/database.dart';
import 'package:knowflow/data/package/tfpkg_codec.dart';
import 'package:knowflow/data/package/tfpkg_service.dart';
import 'package:knowflow/data/repositories/tag_repository.dart';
import 'package:knowflow/data/repositories/task_repository.dart';
import 'package:knowflow/data/repositories/thread_rank_repository.dart';

/// `.tfpkg` workspace export/import (spec §3 / GAP D4).
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('codec', () {
    test('round-trips a dump and its attachments', () {
      final dump = TfpkgDump(
        appVersion: '0.1.0',
        exportedAt: DateTime(2026, 9, 8, 12),
        tables: {
          'tasks': TableDump(rows: [
            {'id': 't1', 'title': '写作业', 'done': 0, 'estimate': 30},
          ]),
          'tags': TableDump(rows: [
            {'id': 'g1', 'path': '文化课/数学'},
          ]),
        },
        themes: ['{"name":"深潜"}'],
      );
      final bytes = TfpkgCodec.encode(TfpkgDump(
        appVersion: dump.appVersion,
        exportedAt: dump.exportedAt,
        tables: dump.tables,
        themes: dump.themes,
        attachments: [
          AttachmentBlob(
            path: 'attachments/bg.png',
            bytes: Uint8List.fromList([1, 2, 3, 4]),
          ),
        ],
      ));

      final decoded = TfpkgCodec.decode(bytes);
      expect(decoded.dump.appVersion, '0.1.0');
      expect(decoded.dump.tables.keys, containsAll(['tasks', 'tags']));
      expect(decoded.dump.tables['tasks']!.rows.single['title'], '写作业');
      expect(decoded.dump.themes.single, '{"name":"深潜"}');
      expect(decoded.attachments, hasLength(1));
      expect(decoded.attachments.single.path, 'attachments/bg.png');
      expect(decoded.attachments.single.bytes, [1, 2, 3, 4]);
      expect(TfpkgCodec.listEntries(bytes),
          containsAll(['manifest.json', 'attachments/bg.png']));
    });

    test('a zip without a manifest is rejected', () {
      expect(
        () => TfpkgCodec.decode(Uint8List.fromList([0, 1, 2, 3])),
        throwsA(isA<Exception>()),
      );
    });

    test('counts reflect the dumped rows', () {
      final dump = TfpkgDump(tables: {
        'a': TableDump(rows: [
          {'id': 1},
          {'id': 2},
        ]),
        'b': TableDump(rows: const []),
      });
      expect(dump.counts, {'a': 2, 'b': 0});
      expect(dump.totalRows, 2);
    });
  });

  group('end to end through two databases', () {
    test('everything the user created survives export and import', () async {
      // Arrange: a populated workspace.
      final tags = TagRepository(db);
      final culture = await tags.createTag(name: '文化课');
      final math = await tags.createTag(name: '数学', parentId: culture.id);

      final tasks = TaskRepository(db);
      final task = await tasks.createTask(
        title: '复习函数',
        estimateMinutes: 25,
        energyRequired: 7,
        dueAt: DateTime(2026, 9, 20).millisecondsSinceEpoch,
      );
      await tags.addTagToObject(
        tagId: math.id,
        objectType: 'task',
        objectId: task.id,
      );
      await ThreadRankRepository(db).updateWeights(urgency: 0.5);

      final service = TfpkgService(db);
      final bytes = await service.exportBytes(appVersion: '0.1.0');
      expect(bytes, isNotEmpty);

      // Act: import into a completely fresh database.
      final target = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(target.close);
      final manifest = TfpkgCodec.readManifest(bytes);
      expect(manifest.counts['tasks'], 1);
      expect(manifest.counts['tags'], 2);

      final report = await TfpkgService(target).importDump(manifest);

      // Assert.
      expect(report.mode, TfpkgMergeMode.append);
      final importedTasks = await TaskRepository(target).getTasks();
      expect(importedTasks.single.title, '复习函数');
      expect(importedTasks.single.energyRequired, 7);

      final importedTags = await TagRepository(target).getAllTags();
      expect(importedTags.map((t) => t.path),
          containsAll(<String>['文化课', '文化课/数学']));

      // The edited ranking weights travel too.
      expect((await ThreadRankRepository(target).getWeights()).urgency, 0.5);
    });

    test('append keeps local rows and only adds missing ones', () async {
      final source = TfpkgService(db);
      await TaskRepository(db).createTask(title: '来自包', estimateMinutes: 10);
      final bytes = await source.exportBytes();
      final dump = TfpkgCodec.readManifest(bytes);

      final target = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(target.close);
      await TaskRepository(target).createTask(title: '本地已有');

      await TfpkgService(target).importDump(dump, mode: TfpkgMergeMode.append);

      final titles = (await TaskRepository(target).getTasks())
          .map((t) => t.title)
          .toList();
      expect(titles, containsAll(<String>['本地已有', '来自包']));
      expect(titles, hasLength(2));

      // Importing the same package twice must not duplicate anything.
      await TfpkgService(target).importDump(dump, mode: TfpkgMergeMode.append);
      expect((await TaskRepository(target).getTasks()), hasLength(2));
    });

    test('replace empties the local table first', () async {
      final bytes = await TfpkgService(db).exportBytes();
      final dump = TfpkgCodec.readManifest(bytes);

      final target = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(target.close);
      await TaskRepository(target).createTask(title: '应该被清掉');

      // Export a package that actually contains one task, then replace.
      await TaskRepository(db).createTask(title: '包里的任务');
      final bytes2 = await TfpkgService(db).exportBytes();
      final dump2 = TfpkgCodec.readManifest(bytes2);
      await TfpkgService(target).importDump(dump2, mode: TfpkgMergeMode.replace);

      final tasks = await TaskRepository(target).getTasks();
      expect(tasks.map((t) => t.title), ['包里的任务']);
    });

    test('unknown tables are reported, not fatal', () async {
      final dump = TfpkgDump(tables: {
        'tasks': TableDump(rows: const []),
        'a_table_from_the_future': TableDump(rows: [
          {'id': 'x'},
        ]),
      });
      final report = await TfpkgService(db).importDump(dump);
      expect(report.skippedTables, contains('a_table_from_the_future'));
      expect(report.written.keys, contains('tasks'));
    });

    test('rows with columns this build does not know are tolerated', () async {
      // A file exported by a newer build carries an extra column; the import
      // must insert what it can instead of failing.
      final dump = TfpkgDump(tables: {
        'tasks': TableDump(rows: [
          {
            'id': 'future-1',
            'title': '未来字段',
            'created_at': 1,
            'updated_at': 1,
            'a_column_that_does_not_exist': 'ignored',
          },
        ]),
      });
      final report = await TfpkgService(db).importDump(dump);
      expect(report.written['tasks'], 1);
      final tasks = await TaskRepository(db).getTasks();
      expect(tasks.single.title, '未来字段');
    });
  });
}

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/features/questions/data/question_media_store.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v26 -> v27：`attachments.role`（轮次一百三十四，答案与解析截图随题保存）。
///
/// 这一列把「题干配图」和「答案截图」分开。迁移只加一列、不回填：NULL 的语义
/// 就是「v27 之前写下的行 = 题干配图」，回填成 'stem' 反而把旧数据和新写的
/// 题干图混成一种，以后想区分就再也分不出来。
///
/// 要锁的三件事：
///
///  1. 真实 v26 文件升级后，老附件行 role 是 NULL，题干配图清单里**一张不少**
///     （读侧 NULL 折成 stem），答案截图清单为空；升级后的库能立刻写 answer；
///  2. 已经被盖成 v27、却没有这一列的文件靠 beforeOpen 自愈 —— Drift 在
///     user_version 等于当前版本时完全跳过 onUpgrade，那一刻没有自愈，读附件
///     就会因为 no such column 炸掉；
///  3. 新列能写能读：answer 关库重开还是 answer，NULL 还是 NULL，不会被读侧
///     的折法写回库。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig27_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 用当前 schema 建库、写两条附件（都是题干配图，v26 世界里没有答案截图），
  /// 然后把 role 列 DROP 掉、把 user_version 压回 [userVersion]。
  Future<File> buildDb({
    required int userVersion,
    required String name,
  }) async {
    final dbFile = File('${tempDir.path}/$name.db');
    final fresh = AppDatabase.forTesting(NativeDatabase(dbFile));
    await fresh.into(fresh.attachments).insert(
          AttachmentsCompanion.insert(
            id: 'att-v26-a',
            ownerType: QuestionMediaStore.ownerType,
            ownerId: 'q-v26',
            relPath: 'question_images/q-v26/att-v26-a/page1.png',
            createdAt: 1,
          ),
        );
    await fresh.into(fresh.attachments).insert(
          AttachmentsCompanion.insert(
            id: 'att-v26-b',
            ownerType: QuestionMediaStore.ownerType,
            ownerId: 'q-v26',
            relPath: 'question_images/q-v26/att-v26-b/page2.png',
            sortOrder: const Value(1),
            createdAt: 2,
          ),
        );
    await fresh.close();

    final raw = sql.sqlite3.open(dbFile.path);
    raw.execute('ALTER TABLE attachments DROP COLUMN role');
    raw.execute('PRAGMA user_version = $userVersion');
    raw.dispose();
    return dbFile;
  }

  QuestionMediaStore storeFor(AppDatabase db, Directory support) =>
      QuestionMediaStore(
        database: db,
        supportDirectory: () async => support,
      );

  test('真实 v26 文件升级后：老配图一张不少（role NULL 折成 stem）、答案清单为空', () async {
    final file = await buildDb(userVersion: 26, name: 'v26');
    final db = AppDatabase.forTesting(NativeDatabase(file));
    final support = Directory('${tempDir.path}/support-v26')
      ..createSync(recursive: true);
    final store = storeFor(db, support);

    final stems = await store.list('q-v26', role: QuestionImageRole.stem);
    expect(stems, hasLength(2), reason: 'v27 之前的所有题目图片都是题干配图');
    expect(stems.map((image) => image.fileName), ['page1.png', 'page2.png']);
    expect(
      stems.map((image) => image.role),
      [QuestionImageRole.stem, QuestionImageRole.stem],
    );
    expect(await store.list('q-v26', role: QuestionImageRole.answer), isEmpty);

    final rows = await (db.select(db.attachments)
          ..where((t) => t.ownerId.equals('q-v26')))
        .get();
    expect(rows.map((row) => row.role), [null, null],
        reason: '迁移不回填：NULL 就是「旧数据 = 题干配图」的兼容语义');

    // 升级后的库能立刻写答案截图，且从 answer 自己的 0 起排号。
    final answer = await store.save(
      questionId: 'q-v26',
      fileName: 'answer.jpg',
      bytes: Uint8List.fromList([1, 2, 3]),
      role: QuestionImageRole.answer,
    );
    expect(answer.role, QuestionImageRole.answer);
    expect(answer.sortOrder, 0);
    final answers = await store.list('q-v26', role: QuestionImageRole.answer);
    expect(answers.map((image) => image.fileName), ['answer.jpg']);
    expect(
      (await store.list('q-v26', role: QuestionImageRole.stem)).map(
        (image) => image.fileName,
      ),
      ['page1.png', 'page2.png'],
      reason: '答案截图不能挤进题干配图清单',
    );
    await db.close();
  });

  test('被盖成 v27 却没有 role 列的文件，靠自愈补列', () async {
    final file = await buildDb(userVersion: 27, name: 'fake27');
    final db = AppDatabase.forTesting(NativeDatabase(file));
    final support = Directory('${tempDir.path}/support-fake27')
      ..createSync(recursive: true);
    final store = storeFor(db, support);

    // 没有自愈的话，这一次读取就会因为 no such column 抛异常。
    final stems = await store.list('q-v26', role: QuestionImageRole.stem);
    expect(stems, hasLength(2));

    final answer = await store.save(
      questionId: 'q-v26',
      fileName: 'healed.png',
      bytes: Uint8List.fromList([1]),
      role: QuestionImageRole.answer,
    );
    expect(answer.role, QuestionImageRole.answer);
    expect(
      (await store.list('q-v26', role: QuestionImageRole.answer))
          .map((image) => image.fileName),
      ['healed.png'],
    );
    await db.close();
  });

  test('带角色入库后关库重开（已是 v27，不再迁移）仍然读得回来', () async {
    final dbFile = File('${tempDir.path}/v27persist.db');
    var db = AppDatabase.forTesting(NativeDatabase(dbFile));
    await db.into(db.attachments).insert(
          AttachmentsCompanion.insert(
            id: 'att-answer',
            ownerType: QuestionMediaStore.ownerType,
            ownerId: 'q-keep',
            relPath: 'question_images/q-keep/att-answer/answer.jpg',
            role: const Value(QuestionImageRole.answer),
            createdAt: 10,
          ),
        );
    await db.into(db.attachments).insert(
          AttachmentsCompanion.insert(
            id: 'att-legacy',
            ownerType: QuestionMediaStore.ownerType,
            ownerId: 'q-keep',
            relPath: 'question_images/q-keep/att-legacy/stem.png',
            createdAt: 11,
          ),
        );
    await db.close();

    db = AppDatabase.forTesting(NativeDatabase(dbFile));
    final support = Directory('${tempDir.path}/support-keep')
      ..createSync(recursive: true);
    final store = storeFor(db, support);

    final answers = await store.list('q-keep', role: QuestionImageRole.answer);
    expect(answers.single.role, QuestionImageRole.answer);
    final stems = await store.list('q-keep', role: QuestionImageRole.stem);
    expect(stems.single.fileName, 'stem.png');
    final rows = await (db.select(db.attachments)
          ..where((t) => t.ownerId.equals('q-keep')))
        .get();
    final byId = {for (final row in rows) row.id: row};
    expect(byId['att-answer']!.role, QuestionImageRole.answer);
    expect(byId['att-legacy']!.role, isNull, reason: '读侧的折算不写回库');
    await db.close();
  });
}
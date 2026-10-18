import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v23 -> v24：`questions.serial_no`（题目编号）与 `attachments.sort_order`
/// （配图排序）（轮次一百二十一）。
///
/// 加的是**两列**，要锁的是三件事：
///
///  1. 真实 v23 文件升级后，老题按 `(created_at, id)` 补出 1..N 的编号，老附件
///     的排序读出来是 0（不是 NULL 崩掉），新题的号接着最大号往下排；
///  2. 已经被盖成 v24、却没有这两列的文件靠 `beforeOpen` 自愈 —— Drift 在
///     `user_version` 等于当前版本时完全跳过 `onUpgrade`，那一刻没有自愈，读题目
///     就会炸；而且光补列不够，自愈必须**回填**编号。
///  3. [AppDatabase.backfillQuestionSerialNumbers] 只补 NULL：已有号一行不动，
///     再跑一次返回 0（幂等）。
///
/// 「v23 文件」的造法：先用当前 schema 建库、写两道题和一个附件，再把两列
/// DROP 掉、把 `user_version` 压回去。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig24_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<File> buildDb({
    required int userVersion,
    required String name,
    bool attachImage = true,
  }) async {
    final dbFile = File('${tempDir.path}/$name.db');
    final fresh = AppDatabase.forTesting(NativeDatabase(dbFile));
    final repository = QuestionRepository(fresh);
    final first = (await repository.ingest(
      const QuestionDraft(stem: '第一道题', subjectKey: 'math'),
      now: DateTime.fromMillisecondsSinceEpoch(1000),
    ))
        .question;
    await repository.ingest(
      const QuestionDraft(stem: '第二道题', subjectKey: 'physics'),
      now: DateTime.fromMillisecondsSinceEpoch(2000),
    );
    if (attachImage) {
      await fresh.into(fresh.attachments).insert(
            AttachmentsCompanion.insert(
              id: 'att-mig24',
              ownerType: 'question',
              ownerId: first.id,
              relPath: 'question_images/${first.id}/att-mig24/page.png',
              createdAt: 1000,
            ),
          );
    }
    await fresh.close();

    final raw = sql.sqlite3.open(dbFile.path);
    raw.execute('ALTER TABLE questions DROP COLUMN serial_no');
    raw.execute('ALTER TABLE attachments DROP COLUMN sort_order');
    raw.execute('PRAGMA user_version = $userVersion');
    raw.dispose();
    return dbFile;
  }

  Future<List<Question>> questionsOf(AppDatabase db) async {
    return (db.select(db.questions)
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  test('真实 v23 文件升级后：老题按时间补号，新题接着排，老附件排序读 0', () async {
    final file = await buildDb(userVersion: 23, name: 'v23');
    final db = AppDatabase.forTesting(NativeDatabase(file));

    final old = await questionsOf(db);
    expect(old.map((q) => q.serialNo), [1, 2]);
    expect(old.first.stem, '第一道题');

    final attachment = await db.select(db.attachments).getSingle();
    expect(attachment.sortOrder, 0, reason: 'v23 时代没有 sort_order，回填为 0');

    final repository = QuestionRepository(db);
    final third = (await repository.ingest(
      const QuestionDraft(stem: '升级后新入库的题'),
      now: DateTime.fromMillisecondsSinceEpoch(3000),
    ))
        .question;
    expect(third.serialNo, 3);
    await db.close();
  });

  test('被盖成 v24 却没有这两列的文件，靠自愈补列并回填编号', () async {
    final file = await buildDb(userVersion: 24, name: 'fake24');
    final db = AppDatabase.forTesting(NativeDatabase(file));

    // 没有自愈的话，第一次读题目就会因为 "no such column: serial_no" 炸掉。
    final old = await questionsOf(db);
    expect(old.map((q) => q.serialNo), [1, 2]);
    final attachment = await db.select(db.attachments).getSingle();
    expect(attachment.sortOrder, 0);

    final repository = QuestionRepository(db);
    final third = (await repository.ingest(
      const QuestionDraft(stem: '自愈后新入库的题'),
      now: DateTime.fromMillisecondsSinceEpoch(4000),
    ))
        .question;
    expect(third.serialNo, 3);
    await db.close();
  });

  test('backfill 只补 NULL，已有号不动，再跑一次返回 0', () async {
    final file = await buildDb(userVersion: 24, name: 'backfill', attachImage: false);
    // 先把一列 DROP 再重开：这一步只是为了让下面的 UPDATE 能跑在"列已存在"的
    // 库上——v24 的库本来就有列，这里直接改数据模拟"导入带进来没号的题"。
    final db = AppDatabase.forTesting(NativeDatabase(file));
    final old = await questionsOf(db);
    final second = old[1];

    await db.customStatement(
      'UPDATE questions SET serial_no = NULL WHERE id = ?',
      [second.id],
    );
    // 打开时的自愈只在"真的补了列"之后回填；列已经在，所以那一道仍然是 NULL。
    expect((await questionsOf(db)).map((q) => q.serialNo), [1, null]);

    final filled = await db.backfillQuestionSerialNumbers();
    expect(filled, 1);
    expect((await questionsOf(db)).map((q) => q.serialNo), [1, 2]);

    // 幂等：没有 NULL 了，就一行都不该动。
    expect(await db.backfillQuestionSerialNumbers(), 0);
    await db.close();
  });
}

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v25 -> v26：questions 三个"外部来源"列（轮次一百二十七，定点组卷网找题）。
///
/// 三列全可空：`source_url` 是来源页链接，`zujuan_question_id` /
/// `zujuan_bank_id` 是组卷网的 questionid / bankid（重建链接、按 qid 认题）。
/// 手工/拍照/自建题没有外部来源，所以 NULL 是常态而不是"迁移失败"。
///
/// 要锁的三件事：
///
///  1. 真实 v25 文件升级后，老题原样保留（含 v24 的题号），三列是 NULL ——
///     迁移只加列，不替老题编造来源；
///  2. 已经被盖成 v26、却没有这三列的文件靠 beforeOpen 自愈 —— Drift 在
///     user_version 等于当前版本时完全跳过 onUpgrade，那一刻没有自愈，读题库
///     就会因为 no such column 炸掉；
///  3. 新列能写能读：带来源入库后关库重开（不再迁移）仍然读得回，且 NULL 与
///     "有来源" 可区分。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig26_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 用当前 schema 建库、写两题（一题自建、一题带组卷网来源），然后把 v26 的
  /// 三列 DROP 掉、把 user_version 压回 [userVersion]（压成 26 即"伪装缺列文件"）。
  Future<File> buildDb({
    required int userVersion,
    required String name,
  }) async {
    final dbFile = File('${tempDir.path}/$name.db');
    final fresh = AppDatabase.forTesting(NativeDatabase(dbFile));
    final repo = QuestionRepository(fresh);
    await repo.ingest(
      const QuestionDraft(
        stem: '光合作用的场所是叶绿体。（自建题）',
        answer: '叶绿体',
        subjectKey: 'biology',
        sourceLevel: 'personal',
      ),
      now: DateTime.utc(2026, 10, 20, 10),
    );
    await repo.ingest(
      const QuestionDraft(
        stem: '下列属于可遗传变异的是（组卷网来源题）',
        answer: 'A',
        subjectKey: 'biology',
        sourceLevel: 'school',
        sourceUrl: 'https://zujuan.xkw.com/11q123456.html',
        zujuanQuestionId: '123456',
        zujuanBankId: '11',
        origin: 'zujuan',
        state: 'raw',
      ),
      now: DateTime.utc(2026, 10, 20, 11),
    );
    await fresh.close();

    final raw = sql.sqlite3.open(dbFile.path);
    raw.execute('ALTER TABLE questions DROP COLUMN source_url');
    raw.execute('ALTER TABLE questions DROP COLUMN zujuan_question_id');
    raw.execute('ALTER TABLE questions DROP COLUMN zujuan_bank_id');
    raw.execute('PRAGMA user_version = $userVersion');
    raw.dispose();
    return dbFile;
  }

  Question byStem(List<Question> rows, String needle) =>
      rows.firstWhere((q) => q.stem.contains(needle));

  test('真实 v25 文件升级后：老题保留、题号还在、三列是 NULL', () async {
    final file = await buildDb(userVersion: 25, name: 'v25');
    final db = AppDatabase.forTesting(NativeDatabase(file));
    final repo = QuestionRepository(db);

    final rows = await repo.all();
    expect(rows, hasLength(2));

    final manual = byStem(rows, '自建题');
    expect(manual.subjectKey, 'biology');
    expect(manual.answer, '叶绿体');
    expect(manual.serialNo, 1, reason: 'v24 的题号必须原样保留');
    expect(manual.sourceUrl, isNull);
    expect(manual.zujuanQuestionId, isNull);
    expect(manual.zujuanBankId, isNull);

    final sourced = byStem(rows, '组卷网来源题');
    expect(sourced.serialNo, 2);
    // 迁移只加列：老文件里原本没有的列不会凭空出现值。
    expect(sourced.sourceUrl, isNull);
    expect(sourced.zujuanQuestionId, isNull);
    expect(sourced.zujuanBankId, isNull);

    // 升级后的库能立刻写带来源的新题。
    final inserted = await repo.ingest(
      const QuestionDraft(
        stem: '升级后新增的组卷网题',
        sourceUrl: 'https://zujuan.xkw.com/gzsw/11q999.html',
        zujuanQuestionId: '999',
        zujuanBankId: '11',
        origin: 'zujuan',
        state: 'raw',
      ),
      now: DateTime.utc(2026, 10, 21),
    );
    expect(inserted.created, isTrue);
    expect(inserted.question.serialNo, 3);
    expect(inserted.question.sourceUrl, 'https://zujuan.xkw.com/gzsw/11q999.html');
    await db.close();
  });

  test('带来源入库后关库重开（已是 v26，不再迁移）仍然读得回来', () async {
    final file = await buildDb(userVersion: 25, name: 'v25persist');

    var db = AppDatabase.forTesting(NativeDatabase(file));
    var repo = QuestionRepository(db);
    final inserted = await repo.ingest(
      const QuestionDraft(
        stem: '重开之后还要读得回来源的题',
        sourceUrl: 'https://zujuan.xkw.com/10q42.html',
        zujuanQuestionId: '42',
        zujuanBankId: '10',
        origin: 'zujuan',
        state: 'raw',
      ),
      now: DateTime.utc(2026, 10, 22),
    );
    final id = inserted.question.id;
    await db.close();

    db = AppDatabase.forTesting(NativeDatabase(file));
    repo = QuestionRepository(db);
    final reopened = await repo.byId(id);
    expect(reopened, isNotNull);
    expect(reopened!.zujuanQuestionId, '42');
    expect(reopened.zujuanBankId, '10');
    expect(reopened.sourceUrl, 'https://zujuan.xkw.com/10q42.html');
    expect(reopened.origin, 'zujuan');
    expect(reopened.state, 'raw');
    await db.close();
  });

  test('被盖成 v26 却没有这三列的文件，靠自愈补列', () async {
    final file = await buildDb(userVersion: 26, name: 'fake26');
    final db = AppDatabase.forTesting(NativeDatabase(file));
    final repo = QuestionRepository(db);

    // 没有自愈的话，这一次读取就会因为 no such column 抛异常。
    final rows = await repo.all();
    expect(rows, hasLength(2));
    expect(byStem(rows, '自建题').sourceUrl, isNull);

    final inserted = await repo.ingest(
      const QuestionDraft(
        stem: '自愈之后补进来的组卷网题',
        zujuanQuestionId: '777',
        zujuanBankId: '11',
        origin: 'zujuan',
        state: 'raw',
      ),
    );
    expect(inserted.question.zujuanQuestionId, '777');
    expect(inserted.question.zujuanBankId, '11');
    expect(inserted.question.sourceUrl, isNull);
    await db.close();
  });
}

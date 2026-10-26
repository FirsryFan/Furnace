import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v39 -> v40：题目加 `text_format` / `extension_of` / `capability` 三列
/// （轮次一百八十二，handoff 管线 v1 §7 M1/M2）。
///
/// 三列全可空：NULL 分别读作「纯文本」「不是扩展题」「能力点未标注」。
/// 要锁的三件事：
///
///  1. 真实 v39 文件升级后，老题目三列都是 NULL，且升级后立刻能写、重开还在；
///  2. 被盖成 v40 却缺这三列的文件靠 beforeOpen 自愈 —— Drift 在 user_version
///     等于当前版本时完全跳过 onUpgrade，没有自愈读题目就会 no such column；
///  3. 写入口径：textFormat 只有 markdown 才落库（plain 写 NULL）；capability
///     存去重升序的 JSON 串；updateFromPack 的「null = 不动 / 空列表 = 清空」。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig40_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 用当前 schema 建库、放一道题，然后把 v40 的三列 DROP 掉、把
  /// user_version 压回 [userVersion]。
  Future<File> buildDb({
    required int userVersion,
    required String name,
  }) async {
    final dbFile = File('${tempDir.path}/$name.db');
    final fresh = AppDatabase.forTesting(NativeDatabase(dbFile));
    await fresh.into(fresh.questions).insert(
          QuestionsCompanion.insert(
            id: 'q-1',
            stem: '已知函数 f(x)=x^2，求单调区间。',
            createdAt: 1700000000000,
            updatedAt: 1700000000000,
          ),
        );
    await fresh.close();

    final raw = sql.sqlite3.open(dbFile.path);
    raw.execute('ALTER TABLE questions DROP COLUMN text_format');
    raw.execute('ALTER TABLE questions DROP COLUMN extension_of');
    raw.execute('ALTER TABLE questions DROP COLUMN capability');
    raw.execute('PRAGMA user_version = $userVersion');
    raw.dispose();
    return dbFile;
  }

  test('真实 v39 文件升级后：老题目三列为 NULL，写入后重开还在', () async {
    final file = await buildDb(userVersion: 39, name: 'v39');
    var db = AppDatabase.forTesting(NativeDatabase(file));
    var repo = QuestionRepository(db);

    var row = await repo.byId('q-1');
    expect(row, isNotNull);
    expect(row!.textFormat, isNull, reason: 'NULL 就是 plain，迁移不回填');
    expect(row.extensionOf, isNull);
    expect(row.capability, isNull);

    expect(
      await repo.updateFromPack(
        questionId: 'q-1',
        stem: row.stem,
        textFormat: 'markdown',
        extensionOf: '888888',
        capability: const <String>['A7', 'A2', 'A3', 'A2'],
      ),
      1,
    );
    row = (await repo.byId('q-1'))!;
    expect(row.textFormat, 'markdown');
    expect(row.extensionOf, '888888');
    expect(row.capability, '["A2","A3","A7"]',
        reason: '能力点去重并按数字升序，A10 排在 A9 之后');
    expect(
        decodeQuestionCapability(row.capability), <String>['A2', 'A3', 'A7']);
    await db.close();

    // 已经是 v40，重开不再迁移；三列必须原样还在。
    db = AppDatabase.forTesting(NativeDatabase(file));
    repo = QuestionRepository(db);
    row = (await repo.byId('q-1'))!;
    expect(row.textFormat, 'markdown');
    expect(row.extensionOf, '888888');
    expect(
        decodeQuestionCapability(row.capability), <String>['A2', 'A3', 'A7']);
    await db.close();
  });

  test('被盖成 v40 却缺三列的文件，靠自愈补列', () async {
    final file = await buildDb(userVersion: 40, name: 'fake40');
    final db = AppDatabase.forTesting(NativeDatabase(file));
    final repo = QuestionRepository(db);

    // 没有自愈的话，这一读就会因为 no such column 抛异常。
    final row = await repo.byId('q-1');
    expect(row, isNotNull);
    expect(row!.textFormat, isNull);
    expect(
      await repo.updateFromPack(
        questionId: 'q-1',
        stem: row.stem,
        textFormat: 'markdown',
        capability: const <String>['A1'],
      ),
      1,
    );
    expect((await repo.byId('q-1'))!.textFormat, 'markdown');
    await db.close();
  });

  test('写入口径：ingest 落库 / plain 写 NULL / 更新语义（null 不动、空列表清空）', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = QuestionRepository(db);

    final plain = await repo.ingest(const QuestionDraft(stem: '纯文本题'));
    expect(plain.question.textFormat, isNull);
    expect(plain.question.extensionOf, isNull);
    expect(plain.question.capability, isNull);

    final fancy = await repo.ingest(const QuestionDraft(
      stem: 'Markdown 题',
      textFormat: 'markdown',
      extensionOf: '  123456  ',
      capability: <String>['A10', 'A2', 'bad', 'A2'],
    ));
    expect(fancy.question.textFormat, 'markdown');
    expect(fancy.question.extensionOf, '123456', reason: '仓储只 trim');
    expect(fancy.question.capability, '["A2","A10"]',
        reason: '非法代码丢弃、去重、按数字升序（不是字典序）');

    // 旧包更新不带这三项（服务层把 plain / 空列表映射成 null）：不能把 markdown / 标注降级。
    expect(
      await repo.updateFromPack(
        questionId: fancy.question.id,
        stem: 'Markdown 题',
        textFormat: 'plain',
      ),
      1,
    );
    var row = (await repo.byId(fancy.question.id))!;
    expect(row.textFormat, 'markdown');
    expect(row.capability, '["A2","A10"]', reason: 'capability 省略 = 不动');

    // 明确清空：capability 传空列表即写 NULL（仓储语义）；extensionOf 传 null 不动。
    expect(
      await repo.updateFromPack(
        questionId: fancy.question.id,
        stem: 'Markdown 题',
        capability: const <String>[],
      ),
      1,
    );
    row = (await repo.byId(fancy.question.id))!;
    expect(row.capability, isNull);
    expect(row.extensionOf, '123456');
    await db.close();
  });
}

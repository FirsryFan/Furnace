import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v29 -> v30：题目自定义题名 `questions.title`（轮次一百三十九）。
///
/// 一列可空文本：NULL 的语义是「还没名字」；自动命名只在用户主动点「自动
/// 命名」或批量补名时写入，迁移不回填——回填会把一批旧模型生成的短名冻在
/// 每一台老安装上，而用户看不出那是自动生成的。
///
/// 要锁的三件事：
///
///  1. 真实 v29 文件升级后，老题目读作「没有题名」，且升级后立刻能命名、重开仍在；
///  2. 已经被盖成 v30、却没有这一列的文件靠 beforeOpen 自愈 —— Drift 在
///     user_version 等于当前版本时完全跳过 onUpgrade，那一刻没有自愈，读题目
///     就会因为 no such column 炸掉；
///  3. 空白串写 NULL、批量改题名只命中存在的行。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig30_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 用当前 schema 建库、放一道题，然后把 title 列 DROP 掉、把 user_version
  /// 压回 [userVersion]。
  Future<File> buildDb({
    required int userVersion,
    required String name,
  }) async {
    final dbFile = File('${tempDir.path}/$name.db');
    final fresh = AppDatabase.forTesting(NativeDatabase(dbFile));
    await fresh.into(fresh.questions).insert(
          QuestionsCompanion.insert(
            id: 'q-1',
            stem: '一根弹簧振子从平衡位置拉开后释放。',
            createdAt: 1700000000000,
            updatedAt: 1700000000000,
          ),
        );
    await fresh.close();

    final raw = sql.sqlite3.open(dbFile.path);
    raw.execute('ALTER TABLE questions DROP COLUMN title');
    raw.execute('PRAGMA user_version = $userVersion');
    raw.dispose();
    return dbFile;
  }

  test('真实 v29 文件升级后：老题目没有题名，且立刻能命名、重开还在', () async {
    final file = await buildDb(userVersion: 29, name: 'v29');
    var db = AppDatabase.forTesting(NativeDatabase(file));
    var repo = QuestionRepository(db);

    var row = await repo.byId('q-1');
    expect(row, isNotNull);
    expect(row!.title, isNull, reason: '迁移不回填，NULL 就是「还没名字」');

    expect(await repo.setQuestionTitle('q-1', '  弹簧振子  '), isTrue);
    row = await repo.byId('q-1');
    expect(row!.title, '弹簧振子', reason: '仓库只 trim，不替域层做长度截断');
    await db.close();

    // 已经是 v30，重开不再迁移；题名必须原样还在。
    db = AppDatabase.forTesting(NativeDatabase(file));
    repo = QuestionRepository(db);
    expect((await repo.byId('q-1'))!.title, '弹簧振子');
    await db.close();
  });

  test('被盖成 v30 却缺 title 列的文件，靠自愈补列', () async {
    final file = await buildDb(userVersion: 30, name: 'fake30');
    final db = AppDatabase.forTesting(NativeDatabase(file));
    final repo = QuestionRepository(db);

    // 没有自愈的话，这一读就会因为 no such column 抛异常。
    expect((await repo.byId('q-1'))!.title, isNull);
    expect(await repo.setQuestionTitle('q-1', '自愈后的名字'), isTrue);
    expect((await repo.byId('q-1'))!.title, '自愈后的名字');
    await db.close();
  });

  test('空白串清成 NULL；批量改名命中两行、跳过不存在的 id', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = QuestionRepository(db);
    final first = await repo.ingest(const QuestionDraft(stem: '第一道题的题干'));
    final second = await repo.ingest(const QuestionDraft(stem: '第二道题的题干'));

    expect(await repo.setQuestionTitle(first.question.id, '   '), isTrue);
    expect((await repo.byId(first.question.id))!.title, isNull,
        reason: '空白不是第三种状态，写 NULL');

    final changed = await repo.setQuestionTitles(<String, String?>{
      first.question.id: '题目甲',
      second.question.id: '题目乙',
      'q-does-not-exist': '幽灵',
      '   ': '空白 id 不算',
    });
    expect(changed, 2, reason: '只统计真正 UPDATE 命中的行');
    expect((await repo.byId(first.question.id))!.title, '题目甲');
    expect((await repo.byId(second.question.id))!.title, '题目乙');

    expect(await repo.setQuestionTitles(const <String, String?>{}), 0);
    await db.close();
  });
}

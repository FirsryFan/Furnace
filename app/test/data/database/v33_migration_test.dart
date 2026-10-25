import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v32 -> v33：题目编号高水位 `question_serial_counters`（轮次一百六十三）。
///
/// 这一版只**新增一张单行表**：老库没有"历史最大发放号"可回填（迁移前的分配
/// 就是「现存最大号 + 1」，删号的历史不在库里），但升级时会把高水位抬到现存
/// 最大号——否则升级后先删最大号那题、再入库，号仍会被接手。要锁的是四种真实
/// 文件状态：
///
///  1. 真实 v32 文件升级到 33 后，老题原样还在，高水位被抬到现存最大号；
///     删掉最大号那题后下一题不接手旧号（跨重开也成立）；
///  2. 版本号已经被盖成 v33、却没有这张表的文件靠 beforeOpen 自愈建表
///     （Drift 只在 user_version 低于 schemaVersion 时跑 onUpgrade，
///     `_upgradeV32ToV33` 根本不会执行）；
///  3. v31 老库一路升到 33：v31→v32 建作答表与 v32→v33 建高水位表按顺序执行。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig33_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<({Question question, bool created})> seedQuestion(
    AppDatabase db, {
    String stem = 'v33 迁移用的题',
  }) {
    return QuestionRepository(db).ingest(
      QuestionDraft(
        stem: stem,
        answer: 'A',
        options: const <QuestionOptionDraft>[
          QuestionOptionDraft(label: 'A', content: '1', isCorrect: true),
          QuestionOptionDraft(label: 'B', content: '2'),
        ],
      ),
    );
  }

  /// 用当前 schema 建库、放一道题，然后把 `question_serial_counters` 表 DROP
  /// 掉、user_version 压回 [userVersion]。
  Future<({File file, String questionId, int serialNo})> buildOldDb({
    required int userVersion,
    required String name,
  }) async {
    final file = File('${tempDir.path}/$name.db');
    final fresh = AppDatabase.forTesting(NativeDatabase(file));
    final ingested = await seedQuestion(fresh);
    final serialNo = ingested.question.serialNo;
    await fresh.close();
    expect(serialNo, isNotNull, reason: '新入库的题一定有编号');

    final raw = sql.sqlite3.open(file.path);
    raw.execute('DROP TABLE question_serial_counters');
    raw.execute('PRAGMA user_version = $userVersion');
    raw.dispose();
    return (
      file: file,
      questionId: ingested.question.id,
      serialNo: serialNo!,
    );
  }

  Future<int> userVersionOf(AppDatabase db) async {
    final row = await db.customSelect('PRAGMA user_version').getSingle();
    return row.read<int>('user_version');
  }

  Future<int?> counterOf(AppDatabase db) async {
    final row = await (db.select(db.questionSerialCounters)
          ..where((t) => t.id.equals(1)))
        .getSingleOrNull();
    return row?.lastIssued;
  }

  test('真实 v32 文件升级后：老题还在，第一次 ingest 写高水位，删掉最高号后不接手', () async {
    final built = await buildOldDb(userVersion: 32, name: 'v32');
    var db = AppDatabase.forTesting(NativeDatabase(built.file));
    var repo = QuestionRepository(db);

    expect(await userVersionOf(db), db.schemaVersion);
    final existing = await repo.byId(built.questionId);
    expect(existing, isNotNull);
    expect(existing!.serialNo, built.serialNo);
    expect(await counterOf(db), built.serialNo, reason: '迁移把高水位抬到现存最大号');

    final second = await seedQuestion(db, stem: '第二题');
    expect(second.question.serialNo, built.serialNo + 1);
    expect(await counterOf(db), second.question.serialNo);

    // 删掉最大号那题：v33 之前号会被下一题接手，现在不会。
    await repo.deleteQuestion(second.question.id);
    expect(await repo.byId(second.question.id), isNull);
    final third = await seedQuestion(db, stem: '第三题');
    expect(third.question.serialNo, second.question.serialNo! + 1);
    await db.close();

    // 重开：高水位行必须还在，新题接着长。
    db = AppDatabase.forTesting(NativeDatabase(built.file));
    expect(await userVersionOf(db), db.schemaVersion);
    expect(await QuestionRepository(db).byId(third.question.id), isNotNull);
    expect(await counterOf(db), third.question.serialNo);
    final fourth = await seedQuestion(db, stem: '第四题');
    expect(fourth.question.serialNo, third.question.serialNo! + 1);
    await db.close();
  });

  test('升级时抬到现存最大号：先删最大号再入库，号不会被接手', () async {
    final built = await buildOldDb(userVersion: 32, name: 'v32-seeded');
    var db = AppDatabase.forTesting(NativeDatabase(built.file));
    var repo = QuestionRepository(db);
    expect(await counterOf(db), built.serialNo);

    // 升级后还没入库过就先删掉最大号那题：没有 seed 的话下一题会拿 1。
    await repo.deleteQuestion(built.questionId);
    expect(await repo.byId(built.questionId), isNull);
    final next = await seedQuestion(db, stem: '删完最大号之后的题');
    expect(next.question.serialNo, built.serialNo + 1);
    expect(await counterOf(db), next.question.serialNo);
    await db.close();

    // 重开仍然记着这个号。
    db = AppDatabase.forTesting(NativeDatabase(built.file));
    repo = QuestionRepository(db);
    expect(await counterOf(db), next.question.serialNo);
    await repo.deleteQuestion(next.question.id);
    final after = await seedQuestion(db, stem: '再删再入库');
    expect(after.question.serialNo, next.question.serialNo! + 1);
    await db.close();
  });

  test('被盖成 v33 却缺 question_serial_counters 表的文件，靠自愈建表', () async {
    final built = await buildOldDb(userVersion: 33, name: 'fake33');
    final db = AppDatabase.forTesting(NativeDatabase(built.file));
    final repo = QuestionRepository(db);

    // 没有自愈的话，ingest 写高水位时会抛 no such table，一道题也存不进去。
    expect(await counterOf(db), isNull);
    final ingested = await seedQuestion(db, stem: '自愈后的题');
    expect(ingested.question.serialNo, built.serialNo + 1);
    expect(await counterOf(db), ingested.question.serialNo);
    expect(await repo.byId(ingested.question.id), isNotNull);
    expect(await userVersionOf(db), db.schemaVersion);
    await db.close();
  });

  test('v31 老库一路升到 33：建作答表与建高水位表都生效', () async {
    final file = File('${tempDir.path}/v31.db');
    final fresh = AppDatabase.forTesting(NativeDatabase(file));
    final ingested = await seedQuestion(fresh);
    await fresh.close();

    final raw = sql.sqlite3.open(file.path);
    raw.execute('DROP TABLE question_attempts');
    raw.execute('DROP TABLE question_serial_counters');
    raw.execute('PRAGMA user_version = 31');
    raw.dispose();

    final db = AppDatabase.forTesting(NativeDatabase(file));
    expect(await userVersionOf(db), db.schemaVersion);

    // v31 -> v32 建出来的作答表可用。
    final attemptRows = await db.select(db.questionAttempts).get();
    expect(attemptRows, isEmpty);

    // v32 -> v33：高水位表在第一次 ingest 时写入。
    final second = await seedQuestion(db, stem: '一路升上来的题');
    expect(second.question.serialNo, ingested.question.serialNo! + 1);
    expect(await counterOf(db), second.question.serialNo);
    expect(await QuestionRepository(db).byId(ingested.question.id), isNotNull);
    await db.close();
  });

  test('健康的 v33 库重开不会重建高水位表，行还在', () async {
    final file = File('${tempDir.path}/healthy33.db');
    var db = AppDatabase.forTesting(NativeDatabase(file));
    final first = await seedQuestion(db);
    await db.close();

    db = AppDatabase.forTesting(NativeDatabase(file));
    expect(await userVersionOf(db), db.schemaVersion);
    expect(await counterOf(db), first.question.serialNo);
    await db.close();
  });
}

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/handwriting_proposal_repository.dart';
import 'package:furnace/data/repositories/question_attempt_repository.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v31 -> v32：自测作答记录 `question_attempts`（轮次一百五十五）。
///
/// 这一版只**新增一张表**：没有一列需要回填，老的作答（此前并不存在）
/// 也不会搬家。要锁的是三种真实文件状态：
///
///  1. 真实 v31 文件升级到 32 后，老题原样还在，新表立刻可写、重开仍在；
///  2. 版本号已经被盖成 v32、却没有这张表的文件靠 beforeOpen 自愈建表
///     （Drift 只在 user_version 低于 schemaVersion 时跑 onUpgrade，
///     `_upgradeV31ToV32` 根本不会执行）；
///  3. v30 老库一路升到 32：v30→v31 补 `source_photos` 列与 v31→v32 建表
///     两条迁移按顺序执行、互不打架。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig32_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<String> seedQuestion(AppDatabase db) async {
    final ingested = await QuestionRepository(db).ingest(
      const QuestionDraft(
        stem: 'v32 迁移用的题',
        answer: 'A',
        options: <QuestionOptionDraft>[
          QuestionOptionDraft(label: 'A', content: '1', isCorrect: true),
          QuestionOptionDraft(label: 'B', content: '2'),
        ],
      ),
    );
    return ingested.question.id;
  }

  /// 用当前 schema 建库、放一道题（模拟 v30 时再放一条单图整理 run），
  /// 然后把 `question_attempts` 表 DROP 掉、user_version 压回 [userVersion]。
  ///
  /// [dropSourcePhotos] 用来模拟真实 v30 文件：v31 才加的列被删掉，
  /// 升级时只能靠 `_upgradeV30ToV31` 补回来。
  Future<({File file, String questionId})> buildOldDb({
    required int userVersion,
    required String name,
    bool dropSourcePhotos = false,
  }) async {
    final file = File('${tempDir.path}/$name.db');
    final fresh = AppDatabase.forTesting(NativeDatabase(file));
    final questionId = await seedQuestion(fresh);
    if (dropSourcePhotos) {
      await fresh.into(fresh.handwritingIntakeRuns).insert(
            HandwritingIntakeRunsCompanion.insert(
              sourceRef: 'handwriting_intake/photo-1/page.png',
              analyzedAt: 1700000000000,
              createdAt: 1700000000000,
            ),
          );
    }
    await fresh.close();

    final raw = sql.sqlite3.open(file.path);
    raw.execute('DROP TABLE question_attempts');
    if (dropSourcePhotos) {
      raw.execute(
          'ALTER TABLE handwriting_intake_runs DROP COLUMN source_photos');
    }
    raw.execute('PRAGMA user_version = $userVersion');
    raw.dispose();
    return (file: file, questionId: questionId);
  }

  Future<int> userVersionOf(AppDatabase db) async {
    final row = await db.customSelect('PRAGMA user_version').getSingle();
    return row.read<int>('user_version');
  }

  test('真实 v31 文件升级后：老题还在，新表立刻能写、重开还在', () async {
    final built = await buildOldDb(userVersion: 31, name: 'v31');
    var db = AppDatabase.forTesting(NativeDatabase(built.file));
    var repo = QuestionAttemptRepository(db);

    expect(await userVersionOf(db), 32);
    final question = await QuestionRepository(db).byId(built.questionId);
    expect(question, isNotNull);
    expect(question!.stem, 'v32 迁移用的题');
    expect(await repo.historyFor(built.questionId), isEmpty);

    final recorded = await repo.record(
      questionId: built.questionId,
      selectedLabels: const <String>['a'],
      isCorrect: true,
      now: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
    expect(recorded, isNotEmpty);
    var history = await repo.historyFor(built.questionId);
    expect(history, hasLength(1));
    expect(history.single.isCorrect, isTrue);
    await db.close();

    // 已经是 v32，重开不再迁移；作答行必须原样还在。
    db = AppDatabase.forTesting(NativeDatabase(built.file));
    repo = QuestionAttemptRepository(db);
    history = await repo.historyFor(built.questionId);
    expect(history, hasLength(1));
    expect(history.single.id, recorded);
    expect(
      history.single.attemptedAt,
      DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
    await db.close();
  });

  test('被盖成 v32 却缺 question_attempts 表的文件，靠自愈建表', () async {
    final built = await buildOldDb(userVersion: 32, name: 'fake32');
    final db = AppDatabase.forTesting(NativeDatabase(built.file));
    final repo = QuestionAttemptRepository(db);

    // 没有自愈的话，这一读会因为 no such table: question_attempts 抛异常。
    expect(await repo.historyFor(built.questionId), isEmpty);

    await repo.record(
      questionId: built.questionId,
      selectedLabels: const <String>['b'],
      isCorrect: false,
    );
    final history = await repo.historyFor(built.questionId);
    expect(history, hasLength(1));
    expect(history.single.isCorrect, isFalse);
    expect(await userVersionOf(db), 32);
    await db.close();
  });

  test('v30 老库一路升到 32：补 source_photos 列与建作答表都生效', () async {
    final built = await buildOldDb(
      userVersion: 30,
      name: 'v30',
      dropSourcePhotos: true,
    );
    final db = AppDatabase.forTesting(NativeDatabase(built.file));
    expect(await userVersionOf(db), 32);

    // v30 -> v31：老 run 没有照片列，补列后读作单图。
    final runs = await HandwritingProposalRepository(db).runs();
    expect(runs, hasLength(1));
    expect(runs.single.sourcePhotos, isEmpty, reason: '迁移不回填，空 = 单图');
    expect(runs.single.isMulti, isFalse);

    // v31 -> v32：同一遍迁移里建出来的作答表立刻可写。
    final repo = QuestionAttemptRepository(db);
    await repo.record(
      questionId: built.questionId,
      selectedLabels: const <String>['a', 'b'],
      isCorrect: true,
      now: DateTime.fromMillisecondsSinceEpoch(1700000001000),
    );
    expect(await repo.historyFor(built.questionId), hasLength(1));
    expect(await QuestionRepository(db).byId(built.questionId), isNotNull);
    await db.close();
  });

  test('健康的 v32 库重开不会重建表，作答行还在', () async {
    final file = File('${tempDir.path}/healthy32.db');
    var db = AppDatabase.forTesting(NativeDatabase(file));
    final questionId = await seedQuestion(db);
    final repo = QuestionAttemptRepository(db);
    final recorded = await repo.record(
      questionId: questionId,
      selectedLabels: const <String>['c'],
      isCorrect: false,
    );
    await db.close();

    db = AppDatabase.forTesting(NativeDatabase(file));
    final reopened = await QuestionAttemptRepository(db).historyFor(questionId);
    expect(reopened, hasLength(1));
    expect(reopened.single.id, recorded);
    expect(await userVersionOf(db), 32);
    await db.close();
  });
}

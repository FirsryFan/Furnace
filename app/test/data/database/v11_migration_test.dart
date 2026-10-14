import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v10 -> v11：`review_logs.predicted_r`（M6 校准曲线的原料）。
///
/// 这一列的意义全在**它什么时候被写**：复习前一刻的预测。所以迁移只有两种可
/// 接受的形状——老行留 NULL（当时没记过预测，事后补一个就是编造），新行能写能读。
/// 两条断言各锁一种失败模式：
///
///  1. 真实的 v10 文件升级后，`predicted_r` 到位、且**老日志全是 NULL**：
///     如果哪天有人"为了曲线好看"在迁移里按当前模型重算一遍，这条会红。
///  2. 已经被盖成 v11、却没有这一列的文件，靠 `beforeOpen` 自愈——Drift 在
///     `user_version` 等于当前版本时完全跳过 `onUpgrade`。
void main() {
  late Directory tempDir;

  /// 造一个 **v10 形状**的文件：v10 的全部表（含测评三表），review_logs 没有
  /// `predicted_r`。[userVersion] 用来复现"版本号跑在列前面"。
  File buildV10Db({int userVersion = 10}) {
    final dbFile = File('${tempDir.path}/v10_$userVersion.db');
    final db = sql.sqlite3.open(dbFile.path);
    db.execute('''
CREATE TABLE profiles (
  id TEXT PRIMARY KEY, display_name TEXT NOT NULL, avatar_color INTEGER,
  created_at INTEGER NOT NULL);
CREATE TABLE local_settings (
  id INTEGER PRIMARY KEY, language TEXT NOT NULL DEFAULT 'system',
  theme_mode TEXT NOT NULL DEFAULT 'system', profile_id TEXT,
  active_theme_id TEXT,
  ai_enabled INTEGER NOT NULL DEFAULT 0, ai_api_key TEXT, ai_base_url TEXT,
  ai_model TEXT, ai_permission_mode TEXT, ai_max_rounds INTEGER,
  anki_judge_mode TEXT, anki_card_type_preference TEXT,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
CREATE TABLE knowledge_points (
  id TEXT PRIMARY KEY, title TEXT NOT NULL, content TEXT NOT NULL,
  content_format TEXT, source TEXT, external_id TEXT, package_id TEXT,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
CREATE TABLE card_templates (
  id TEXT PRIMARY KEY, knowledge_point_id TEXT NOT NULL, type TEXT NOT NULL,
  question TEXT NOT NULL, answer TEXT NOT NULL, options TEXT,
  cloze_template TEXT, hint TEXT, sort_order INTEGER NOT NULL DEFAULT 0,
  external_id TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
CREATE TABLE card_states (
  id TEXT PRIMARY KEY, card_template_id TEXT, due_at INTEGER,
  interval_days REAL NOT NULL DEFAULT 0, ease REAL NOT NULL DEFAULT 2.5,
  repetitions INTEGER NOT NULL DEFAULT 0, lapses INTEGER NOT NULL DEFAULT 0,
  state TEXT NOT NULL DEFAULT 'new', last_reviewed_at INTEGER,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  knowledge_point_id TEXT, unit_key TEXT, stability REAL, difficulty REAL,
  encoding_strength REAL, savings REAL,
  forced INTEGER NOT NULL DEFAULT 0, forced_streak INTEGER NOT NULL DEFAULT 0);
CREATE TABLE review_group_plans (
  id TEXT PRIMARY KEY, tag_id TEXT NOT NULL, tag_path TEXT NOT NULL,
  new_cards_per_day INTEGER NOT NULL DEFAULT 0,
  review_cards_per_day INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
CREATE TABLE review_logs (
  id TEXT PRIMARY KEY, card_state_id TEXT NOT NULL, card_template_id TEXT,
  unit_key TEXT, rating INTEGER NOT NULL, rating_fsrs INTEGER, correct INTEGER,
  judge_mode TEXT, format TEXT, ms_taken INTEGER, reviewed_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL, reviewed_solution INTEGER, closeness REAL);
CREATE TABLE assessment_sessions (
  id TEXT PRIMARY KEY, subject_key TEXT NOT NULL DEFAULT '',
  scope_tag_ids TEXT NOT NULL DEFAULT '[]', started_at INTEGER NOT NULL,
  finished_at INTEGER, budget INTEGER, note TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
CREATE TABLE assessment_responses (
  id TEXT PRIMARY KEY, session_id TEXT NOT NULL, knowledge_point_id TEXT,
  step_kind TEXT NOT NULL, prompt TEXT NOT NULL DEFAULT '',
  answer TEXT NOT NULL DEFAULT '', correct INTEGER, self_rating INTEGER,
  confidence REAL, elapsed_ms INTEGER, judged_by TEXT NOT NULL DEFAULT 'self',
  created_at INTEGER NOT NULL);
CREATE TABLE cognitive_priors (
  knowledge_point_id TEXT NOT NULL, source TEXT NOT NULL, r0 REAL NOT NULL,
  d REAL, fluency REAL, n INTEGER NOT NULL DEFAULT 0,
  calibrated INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL,
  PRIMARY KEY (knowledge_point_id, source));
''');

    // 一个已经复习过的用户：一条 v9 形状的失败日志（有答案回看 + 接近度）。
    db.execute('''
INSERT INTO knowledge_points (id, title, content, created_at, updated_at)
VALUES ('kp1', '叶绿体', '光合作用的场所是叶绿体。', 1700000000000,
  1700000000000)''');
    db.execute('''
INSERT INTO review_logs (id, card_state_id, card_template_id, rating, correct,
  judge_mode, format, reviewed_at, created_at, reviewed_solution, closeness)
VALUES ('rl1', 'cs1', 'ct1', 1, 0, 'auto', 'fill', 1700000000000,
  1700000000000, 1, 0.6)''');

    db.execute('PRAGMA user_version = $userVersion');
    db.dispose();
    return dbFile;
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig11_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('真实 v10 文件升级后能写预测，但老日志一律没有预测', () async {
    final db = AppDatabase.forTesting(NativeDatabase(buildV10Db()));
    final anki = AnkiRepository(db);

    final logs = await db.select(db.reviewLogs).get();
    expect(logs.single.reviewedSolution, isTrue, reason: 'v9 的列要原样留着');
    expect(logs.single.closeness, 0.6);
    expect(
      logs.single.predictedR,
      isNull,
      reason: '迁移不能给历史行补预测——那不是当时算出来的数',
    );

    // 新的一列立刻可用：写一条带预测的日志，再读回来。
    await anki.addReviewLog(
      cardStateId: 'cs1',
      cardTemplateId: 'ct1',
      rating: 2,
      correct: 1,
      reviewedAt: 1700000100000,
      predictedR: 0.731234,
    );
    final again = await db.select(db.reviewLogs).get();
    final fresh = again.firstWhere((row) => row.id != 'rl1');
    expect(fresh.predictedR, 0.731234);
    expect(fresh.correct, 1);

    // 而 M6 的读数把"没有预测"如实排除在校准之外。
    final samples = await anki.retentionSamples();
    expect(samples, hasLength(2));
    expect(samples.map((s) => s.predictedR), [null, 0.731234]);
    await db.close();
  });

  test('被盖成 v11 却没有这一列的文件，靠自愈补上并能写进去', () async {
    // user_version 已经是 11，Drift 跳过 onUpgrade，列只能由 beforeOpen 补。
    final db = AppDatabase.forTesting(
      NativeDatabase(buildV10Db(userVersion: 11)),
    );
    final anki = AnkiRepository(db);

    await anki.addReviewLog(
      cardStateId: 'cs1',
      cardTemplateId: 'ct1',
      rating: 2,
      reviewedAt: 1700000200000,
      predictedR: 0.5,
    );

    final fresh = (await db.select(db.reviewLogs).get())
        .firstWhere((row) => row.id != 'rl1');
    expect(fresh.predictedR, 0.5);
    await db.close();
  });
}

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v8 -> v9: two optional columns on `review_logs` that record *how* a miss
/// happened - was the answer looked at, and how close was the recall
/// (`MindNet docs/IO_PROTOCOL.md` section 2.3, `wrong` + `reviewed_solution`).
///
/// Three claims, each with its own failure mode:
///
///  1. A real v8 file opens and gains both columns - no missing column when a
///     log is read back.
///  2. A file stamped v9 that never got the columns is **healed** on open, by
///     the same `beforeOpen` self-heal the v5/v6/v7/v8 migrations use: Drift
///     skips `onUpgrade` entirely when the stored version is already current.
///  3. The columns arrive **unset (NULL)** and stay NULL unless a caller says
///     otherwise. NULL means "nobody asked / not applicable" and is deliberately
///     not the same as a stored `false`: writing `false` into every historical
///     row would claim those misses were resolved without the answer, which the
///     old code never recorded.
///
/// The column lists mirror `tables.dart` minus the v9 columns, kept as raw SQL
/// on purpose: that is what an on-disk v8 file looks like.
void main() {
  late Directory tempDir;

  /// Builds a database in the **v8 shape**.
  ///
  /// [withV9Columns] controls the two new review-log columns (so the heal path
  /// can be reproduced), [userVersion] controls what the file claims to be.
  File buildV8Db({int userVersion = 8, bool withV9Columns = false}) {
    final dbFile = File(
      '${tempDir.path}/v8_${userVersion}_$withV9Columns.db',
    );
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
CREATE TABLE tags (
  id TEXT PRIMARY KEY, parent_id TEXT, name TEXT NOT NULL, path TEXT,
  color INTEGER, description TEXT, source_node_id TEXT,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
CREATE TABLE object_tags (
  id TEXT PRIMARY KEY, tag_id TEXT NOT NULL, object_type TEXT NOT NULL,
  object_id TEXT NOT NULL, created_at INTEGER NOT NULL);
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
  created_at INTEGER NOT NULL${withV9Columns ? ', reviewed_solution INTEGER, closeness REAL' : ''});
''');

    // Rows an existing user would have: a settings row, one knowledge point with
    // a template, a ripened unit state, and one miss already logged before the
    // question about the answer existed.
    db.execute('''
INSERT INTO local_settings (id, language, theme_mode, ai_enabled, ai_model,
  created_at, updated_at)
VALUES (1, 'zh', 'system', 1, 'deepseek-chat', 1700000000000, 1700000000000)''');
    db.execute('''
INSERT INTO knowledge_points (id, title, content, created_at, updated_at)
VALUES ('kp1', '叶绿体', '光合作用的场所是叶绿体。', 1700000000000,
  1700000000000)''');
    db.execute('''
INSERT INTO card_templates (id, knowledge_point_id, type, question, answer,
  created_at, updated_at)
VALUES ('ct1', 'kp1', 'qa', '光合作用的场所？', '叶绿体', 1700000000000,
  1700000000000)''');
    db.execute('''
INSERT INTO card_states (id, knowledge_point_id, unit_key, state, stability,
  difficulty, created_at, updated_at)
VALUES ('cs1', 'kp1', 'cloze:s1', 'review', 12.5, 5.25, 1700000000000,
  1700000000000)''');
    db.execute('''
INSERT INTO review_logs (id, card_state_id, card_template_id, rating, correct,
  judge_mode, format, reviewed_at, created_at)
VALUES ('rl1', 'cs1', 'ct1', 1, 0, 'auto', 'fill', 1700000000000,
  1700000000000)''');

    db.execute('PRAGMA user_version = $userVersion');
    db.dispose();
    return dbFile;
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig9_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a real v8 file upgrades and keeps its logs', () async {
    final db = AppDatabase.forTesting(NativeDatabase(buildV8Db()));
    // Touching the table is the point: a missing column throws here.
    final logs = await db.select(db.reviewLogs).get();
    expect(logs, hasLength(1));
    expect(logs.single.judgeMode, 'auto');
    expect(logs.single.format, 'fill');
    expect(logs.single.correct, 0);
    expect(
      logs.single.reviewedSolution,
      isNull,
      reason: 'a miss logged before the question existed was never resolved',
    );
    expect(logs.single.closeness, isNull);
    await db.close();
  });

  test('the v8 tables survive: the settings row is still readable', () async {
    final db = AppDatabase.forTesting(NativeDatabase(buildV8Db()));
    final settings = (await db.select(db.localSettings).get()).single;
    expect(settings.language, 'zh');
    expect(settings.aiEnabled, isTrue, reason: 'the upgrade must not reset AI');
    expect(settings.ankiJudgeMode, isNull);
    final groupPlans = await db.select(db.reviewGroupPlans).get();
    expect(groupPlans, isEmpty, reason: 'no plan row still means no cap');
    await db.close();
  });

  test('a file stamped v9 without the columns is healed on open', () async {
    // user_version says 9, so Drift skips onUpgrade entirely, yet
    // review_logs has neither column. `beforeOpen` has to add them.
    final db = AppDatabase.forTesting(
      NativeDatabase(buildV8Db(userVersion: 9)),
    );
    final logs = await db.select(db.reviewLogs).get();
    expect(logs.single.reviewedSolution, isNull);
    expect(logs.single.closeness, isNull);
    // Writing through the same path proves the columns are real, not just
    // tolerated on read.
    await AnkiRepository(db).addReviewLog(
      cardStateId: 'cs1',
      cardTemplateId: 'ct1',
      rating: 1,
      reviewedAt: 1700000001000,
      correct: 0,
      judgeMode: 'auto',
      reviewedSolution: true,
      closeness: 0.6,
    );
    final written =
        (await db.select(db.reviewLogs).get()).firstWhere((r) => r.correct == 0 &&
            r.reviewedAt == 1700000001000);
    expect(written.reviewedSolution, isTrue);
    expect(written.closeness, 0.6);
    await db.close();
  });

  test('NULL is not the same as a stored false', () async {
    final db = AppDatabase.forTesting(NativeDatabase(buildV8Db()));
    final repo = AnkiRepository(db);
    // A correct answer never had the question asked: the caller passes nothing
    // and the row keeps NULL rather than claiming `false`.
    await repo.addReviewLog(
      cardStateId: 'cs1',
      cardTemplateId: 'ct1',
      rating: 3,
      reviewedAt: 1700000002000,
      correct: 1,
      judgeMode: 'auto',
    );
    // A miss that the user resolved as "still didn't know" is a fact worth
    // recording, so it stores an explicit false with no closeness.
    await repo.addReviewLog(
      cardStateId: 'cs1',
      cardTemplateId: 'ct1',
      rating: 1,
      reviewedAt: 1700000003000,
      correct: 0,
      judgeMode: 'auto',
      reviewedSolution: false,
    );
    final rows = await db.select(db.reviewLogs).get();
    final unasked = rows.firstWhere((r) => r.reviewedAt == 1700000002000);
    final resolved = rows.firstWhere((r) => r.reviewedAt == 1700000003000);
    expect(unasked.reviewedSolution, isNull);
    expect(unasked.closeness, isNull);
    expect(resolved.reviewedSolution, isFalse);
    expect(resolved.closeness, isNull);
    await db.close();
  });
}

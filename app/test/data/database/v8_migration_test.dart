import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/review_plan_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/features/anki/application/card_type_preference.dart';
import 'package:furnace/features/anki/application/judge_mode_preference.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v7 -> v8: the per-group daily plan table, plus the two review preferences
/// that v7 introduced but that had never been exercised on a real file.
///
/// Four separate claims, each with its own failure mode:
///
///  1. A real v7 file opens and gains `review_group_plans` - no missing table.
///  2. A file stamped v8 that never got the table is **healed** on open, by the
///     same `beforeOpen` self-heal the v5/v6/v7 columns use: Drift skips
///     `onUpgrade` entirely when the stored version is already current.
///  3. The two v7 preference columns arrive **unset**. NULL means "the user
///     never chose", which resolves to `strict` judging and the `mixed` card
///     type - i.e. exactly the behaviour the app had before the settings
///     existed. Writing today's defaults into every row would freeze them.
///  4. A plan is keyed by the tag **id**, so a tag rename keeps the plan (the
///     path is what changes) and a tag delete takes its plan with it.
///
/// The column lists mirror `tables.dart` minus the v8 table, kept as raw SQL on
/// purpose: that is what an on-disk v7 file looks like.
void main() {
  late Directory tempDir;

  /// Builds a database in the **v7 shape**.
  ///
  /// [withV7Columns] controls the two review-preference columns (so the heal
  /// path can be reproduced), [userVersion] controls what the file claims to be.
  File buildV7Db({int userVersion = 7, bool withV7Columns = false}) {
    final dbFile = File(
      '${tempDir.path}/v7_${userVersion}_$withV7Columns.db',
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
  ${withV7Columns ? 'anki_judge_mode TEXT, anki_card_type_preference TEXT,' : ''}
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
CREATE TABLE review_logs (
  id TEXT PRIMARY KEY, card_state_id TEXT NOT NULL, card_template_id TEXT,
  unit_key TEXT, rating INTEGER NOT NULL, rating_fsrs INTEGER, correct INTEGER,
  judge_mode TEXT, format TEXT, ms_taken INTEGER, reviewed_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL);
''');

    // Rows an existing user would have: a settings row that predates the review
    // preferences, a two-level tag tree, one knowledge point under the child
    // tag, and one review already logged today.
    db.execute('''
INSERT INTO local_settings (id, language, theme_mode, ai_enabled, ai_model,
  created_at, updated_at)
VALUES (1, 'zh', 'system', 1, 'deepseek-chat', 1700000000000, 1700000000000)''');
    db.execute('''
INSERT INTO tags (id, parent_id, name, path, created_at, updated_at)
VALUES ('tag-cn', NULL, '语文', '语文', 1700000000000, 1700000000000)''');
    db.execute('''
INSERT INTO tags (id, parent_id, name, path, created_at, updated_at)
VALUES ('tag-essay', 'tag-cn', '作文', '语文/作文', 1700000000000,
  1700000000000)''');
    db.execute('''
INSERT INTO knowledge_points (id, title, content, created_at, updated_at)
VALUES ('kp1', '叶绿体', '光合作用的场所是叶绿体。', 1700000000000,
  1700000000000)''');
    db.execute('''
INSERT INTO object_tags (id, tag_id, object_type, object_id, created_at)
VALUES ('link1', 'tag-essay', 'knowledge_point', 'kp1', 1700000000000)''');
    db.execute('''
INSERT INTO card_states (id, knowledge_point_id, unit_key, state, stability,
  difficulty, created_at, updated_at)
VALUES ('cs1', 'kp1', 'cloze:s1', 'review', 12.5, 5.25, 1700000000000,
  1700000000000)''');
    db.execute('''
INSERT INTO review_logs (id, card_state_id, rating, correct, judge_mode,
  reviewed_at, created_at)
VALUES ('rl1', 'cs1', 2, 1, 'auto', 1700000000000, 1700000000000)''');

    db.execute('PRAGMA user_version = $userVersion');
    db.dispose();
    return dbFile;
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig8_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a real v7 file upgrades and keeps its rows and settings', () async {
    final db = AppDatabase.forTesting(NativeDatabase(buildV7Db()));
    // Touching the stores is the point: a missing column throws here.
    final settings = (await db.select(db.localSettings).get()).single;
    expect(settings.language, 'zh');
    expect(settings.aiEnabled, isTrue, reason: 'the upgrade must not reset AI');
    expect(settings.aiModel, 'deepseek-chat');
    expect((await db.select(db.tags).get()).length, 2);
    expect((await db.select(db.knowledgePoints).get()).single.title, '叶绿体');
    expect((await db.select(db.reviewLogs).get()).single.judgeMode, 'auto');
    await db.close();
  });

  test('the v8 table is created empty, so nothing is capped on upgrade',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase(buildV7Db()));
    // Empty is the whole design: no row means no configured target, and an
    // install that never opens the plan UI keeps drawing exactly the cards it
    // drew before this release.
    expect(await db.select(db.reviewGroupPlans).get(), isEmpty);
    expect(
      (await ReviewPlanRepository(db, AnkiRepository(db)).loadDay()).isEmpty,
      isTrue,
      reason: 'no rows means no cap anywhere',
    );
    await db.close();
  });

  test('a file stamped v8 but missing the table is healed on open', () async {
    // Reproduces the real-world shape this project already hit with v5:
    // user_version says 8, so Drift skips onUpgrade entirely, yet the table was
    // never created. beforeOpen must repair the file or every plan query throws.
    final db = AppDatabase.forTesting(
      NativeDatabase(buildV7Db(userVersion: 8)),
    );
    expect(await db.select(db.reviewGroupPlans).get(), isEmpty,
        reason: 'beforeOpen must have created the table');
    await db.close();
  });

  test('the two v7 preference columns read as "never chosen"', () async {
    final db = AppDatabase.forTesting(NativeDatabase(buildV7Db()));
    final settings = (await db.select(db.localSettings).get()).single;
    // NULL, not 'strict' / 'mixed': an upgraded install must keep following the
    // shipped defaults rather than having today's values frozen into it.
    expect(settings.ankiJudgeMode, isNull);
    expect(settings.ankiCardTypePreference, isNull);
    // ...and the repository turns that NULL into today's behaviour.
    final repository = ReviewPlanRepository(db, AnkiRepository(db));
    expect(await repository.getJudgeModePreference(),
        JudgeModePreference.strict);
    expect(await repository.getCardTypePreference(), CardTypePreference.mixed);
    await db.close();
  });

  test('a v8 file that already has the columns keeps its values', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase(buildV7Db(userVersion: 8, withV7Columns: true)),
    );
    final settings = (await db.select(db.localSettings).get()).single;
    expect(settings.language, 'zh', reason: 'unchanged by the upgrade');
    expect(settings.aiMaxRounds, isNull,
        reason: 'the heal must not invent a value for a column it added');
    expect(settings.ankiJudgeMode, isNull);
    expect(settings.ankiCardTypePreference, isNull);
    await db.close();
  });

  test('the new table is writable and a plan survives a tag rename', () async {
    final db = AppDatabase.forTesting(NativeDatabase(buildV7Db()));
    final anki = AnkiRepository(db);
    final repository = ReviewPlanRepository(db, anki);

    await repository.setGroupPlan(
      tagId: 'tag-cn',
      newCardsPerDay: 5,
      reviewCardsPerDay: 20,
    );
    var plans = await repository.groupPlans();
    expect(plans.single.tagPath, '语文');
    expect(plans.single.newCardsPerDay, 5);

    // The row is keyed by the tag id, so a rename (which rewrites the cached
    // path of the tag *and* its whole subtree) has to leave the plan in place
    // and simply show the new path.
    await TagRepository(db).renameTag('tag-cn', '国文');
    plans = await repository.groupPlans();
    expect(plans.single.tagId, 'tag-cn');
    expect(plans.single.tagPath, '国文');
    expect(plans.single.reviewCardsPerDay, 20);
    await db.close();
  });

  test('saving the same group twice updates one row', () async {
    final db = AppDatabase.forTesting(NativeDatabase(buildV7Db()));
    final repository = ReviewPlanRepository(db, AnkiRepository(db));

    await repository.setGroupPlan(
      tagId: 'tag-cn',
      newCardsPerDay: 1,
      reviewCardsPerDay: 2,
    );
    await repository.setGroupPlan(
      tagId: 'tag-cn',
      newCardsPerDay: 7,
      reviewCardsPerDay: 30,
    );

    final plans = await repository.groupPlans();
    expect(plans, hasLength(1), reason: 'one target per group, not two');
    expect(plans.single.newCardsPerDay, 7);
    expect(plans.single.reviewCardsPerDay, 30);
    await db.close();
  });

  test('deleting a tag takes its plan with it', () async {
    final db = AppDatabase.forTesting(NativeDatabase(buildV7Db()));
    final repository = ReviewPlanRepository(db, AnkiRepository(db));
    await repository.setGroupPlan(
      tagId: 'tag-essay',
      newCardsPerDay: 3,
      reviewCardsPerDay: 9,
    );
    expect(await repository.groupPlans(), hasLength(1));

    // The cleanup happens in Dart, not only in the FK declaration: a database
    // opened by an older build may predate `PRAGMA foreign_keys = ON`, and an
    // orphan plan row would then sit on a tag id nothing can ever resolve.
    await TagRepository(db).deleteTag('tag-essay');

    expect(await repository.groupPlans(), isEmpty,
        reason: 'a plan must not outlive its group');
    expect(await db.select(db.reviewGroupPlans).get(), isEmpty);
    await db.close();
  });
}

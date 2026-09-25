import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/time_block_repository.dart';
import 'package:furnace/data/repositories/time_template_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v3 -> v4 upgrade in place: the Time module gained schedule templates and
/// single-row view preferences (user feedback item 3).
void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig4_');
    dbFile = File('${tempDir.path}/v3.db');
    final db = sql.sqlite3.open(dbFile.path);
    // A v3 database: the tables the migration touches, plus enough of the
    // schema that Drift does not complain while opening.
    db.execute('''
CREATE TABLE local_settings (
  id INTEGER PRIMARY KEY, language TEXT, theme_mode TEXT, profile_id TEXT,
  active_theme_id TEXT, created_at INTEGER, updated_at INTEGER);
CREATE TABLE tags (id TEXT PRIMARY KEY, name TEXT, path TEXT);
CREATE TABLE tasks (
  id TEXT PRIMARY KEY, parent_id TEXT, title TEXT, description TEXT,
  status TEXT, priority INTEGER, estimate_minutes INTEGER, due_at INTEGER,
  remind_at INTEGER, expected_at INTEGER, energy_required INTEGER,
  completed_at INTEGER, started_at INTEGER, created_at INTEGER, updated_at INTEGER);
CREATE TABLE completion_logs (
  id TEXT PRIMARY KEY, task_id TEXT, title TEXT, tag_ids TEXT, tag_paths TEXT,
  estimate_minutes INTEGER, energy_required INTEGER, completed_at INTEGER,
  actual_minutes INTEGER, include_in_model INTEGER DEFAULT 1,
  duration_suspicious INTEGER DEFAULT 0, created_at INTEGER);
CREATE TABLE thread_rank_settings (
  id INTEGER PRIMARY KEY, w_urgency REAL DEFAULT 0.4, w_goal REAL DEFAULT 0.3,
  w_fit REAL DEFAULT 0.2, w_fatigue REAL DEFAULT 0.1, w_expected REAL DEFAULT 0.05,
  header_collapsed INTEGER DEFAULT 0, use_actual_time INTEGER DEFAULT 1,
  updated_at INTEGER, created_at INTEGER);
CREATE TABLE diffusion_logs (
  id TEXT PRIMARY KEY, owner_type TEXT, owner_id TEXT, owner_title TEXT,
  kind TEXT, knowledge_point_id TEXT, knowledge_point_title TEXT,
  distance INTEGER, factor REAL, detail TEXT, day_key TEXT,
  occurred_at INTEGER, created_at INTEGER);
CREATE TABLE time_blocks (
  id TEXT PRIMARY KEY, title TEXT, start_at INTEGER, end_at INTEGER,
  repeat_rule TEXT, available INTEGER DEFAULT 1, energy TEXT,
  suitable_for TEXT, created_at INTEGER, updated_at INTEGER);
CREATE TABLE knowledge_points (id TEXT PRIMARY KEY, title TEXT);
CREATE TABLE card_templates (id TEXT PRIMARY KEY);
CREATE TABLE card_states (
  id TEXT PRIMARY KEY, card_template_id TEXT, due_at INTEGER,
  interval_days REAL DEFAULT 0, ease REAL DEFAULT 2.5,
  repetitions INTEGER DEFAULT 0, lapses INTEGER DEFAULT 0, state TEXT,
  last_reviewed_at INTEGER, created_at INTEGER, updated_at INTEGER,
  knowledge_point_id TEXT, unit_key TEXT, stability REAL, difficulty REAL,
  forced INTEGER DEFAULT 0, forced_streak INTEGER DEFAULT 0);
CREATE TABLE review_logs (
  id TEXT PRIMARY KEY, card_state_id TEXT, card_template_id TEXT,
  unit_key TEXT, rating INTEGER, rating_fsrs INTEGER, correct INTEGER,
  judge_mode TEXT, format TEXT, ms_taken INTEGER, reviewed_at INTEGER,
  created_at INTEGER);
''');
    const now = 1700000000000;
    db.execute(
      "INSERT INTO time_blocks (id, title, start_at, end_at, available, created_at, updated_at) "
      "VALUES ('tb1', '旧日程块', $now, ${now + 3600000}, 1, $now, $now)",
    );
    db.execute('PRAGMA user_version = 3');
    db.dispose();
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('opens a v3 database and migrates it to v4 in place', () async {
    final db = AppDatabase.forTesting(NativeDatabase(dbFile));

    // Legacy rows survive untouched.
    final blocks = await TimeBlockRepository(db).getTimeBlocks();
    expect(blocks, hasLength(1));
    expect(blocks.single.title, '旧日程块');

    // The v4 tables now exist and accept writes.
    final templates = TimeTemplateRepository(db);
    final saved = await templates.save(
      name: '迁移后模板',
      kind: 'day',
      blocks: const [
        TemplateBlock(title: '早读', startMinutes: 420, endMinutes: 460),
      ],
    );
    expect(saved.kind, 'day');
    expect(templates.blocksOf(saved).single.title, '早读');

    final views = TimeViewRepository(db);
    final settings = await views.ensure();
    expect(settings.timelineSpanDays, 730);
    // The table is created from the schema that ships after the v4 -> v5
    // change, so the row-size default is the fine 30-minute grid.
    expect(settings.minutesPerRow, 30);
    expect(settings.minutesPerRowChosen, isFalse);

    // The previous view state was not disturbed.
    expect((await db.select(db.timeViewSettings).get()), hasLength(1));

    await db.close();
  });
}

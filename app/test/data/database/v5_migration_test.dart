import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/time_template_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v4 -> v5: the day/week grid no longer defaults to whole-hour rows
/// (user: "不要默认按小时来分").
///
/// The migration must move everybody who never picked a row size off the old
/// 60-minute default, while leaving a deliberate choice alone.
void main() {
  late Directory tempDir;

  /// Builds a v4 database whose time_view_settings row holds [minutesPerRow],
  /// with or without the `minutes_per_row_chosen` column (that column is the
  /// thing v5 adds).
  File buildV4Db({
    required int minutesPerRow,
    bool withChosenColumn = false,
    bool chosen = false,
  }) {
    final dbFile = File('${tempDir.path}/v4_$minutesPerRow'
        '${withChosenColumn ? '_c$chosen' : ''}.db');
    final db = sql.sqlite3.open(dbFile.path);
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
  id INTEGER PRIMARY KEY, w_urgency REAL, w_goal REAL, w_fit REAL,
  w_fatigue REAL, w_expected REAL, header_collapsed INTEGER,
  use_actual_time INTEGER, updated_at INTEGER, created_at INTEGER);
CREATE TABLE diffusion_logs (
  id TEXT PRIMARY KEY, owner_type TEXT, owner_id TEXT, owner_title TEXT,
  kind TEXT, knowledge_point_id TEXT, knowledge_point_title TEXT,
  distance INTEGER, factor REAL, detail TEXT, day_key TEXT,
  occurred_at INTEGER, created_at INTEGER);
CREATE TABLE time_blocks (
  id TEXT PRIMARY KEY, title TEXT, start_at INTEGER, end_at INTEGER,
  repeat_rule TEXT, available INTEGER DEFAULT 1, energy TEXT,
  suitable_for TEXT, created_at INTEGER, updated_at INTEGER);
CREATE TABLE time_templates (
  id TEXT PRIMARY KEY, name TEXT, kind TEXT, payload TEXT,
  sort_order INTEGER DEFAULT 0, created_at INTEGER, updated_at INTEGER);
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
    if (withChosenColumn) {
      db.execute('''
CREATE TABLE time_view_settings (
  id INTEGER PRIMARY KEY, timeline_span_days INTEGER DEFAULT 730,
  timeline_px_per_day REAL DEFAULT 6, timeline_collapsed INTEGER DEFAULT 0,
  minutes_per_row INTEGER DEFAULT 60,
  minutes_per_row_chosen INTEGER DEFAULT 0,
  updated_at INTEGER, created_at INTEGER)''');
      db.execute(
        'INSERT INTO time_view_settings (id, minutes_per_row, '
        'minutes_per_row_chosen, created_at) '
        "VALUES (1, $minutesPerRow, ${chosen ? 1 : 0}, 1700000000000)",
      );
    } else {
      // The pre-v5 shape: no `minutes_per_row_chosen` column at all.
      db.execute('''
CREATE TABLE time_view_settings (
  id INTEGER PRIMARY KEY, timeline_span_days INTEGER DEFAULT 730,
  timeline_px_per_day REAL DEFAULT 6, timeline_collapsed INTEGER DEFAULT 0,
  minutes_per_row INTEGER DEFAULT 60,
  updated_at INTEGER, created_at INTEGER)''');
      db.execute(
        'INSERT INTO time_view_settings (id, minutes_per_row, created_at) '
        'VALUES (1, $minutesPerRow, 1700000000000)',
      );
    }
    db.execute('PRAGMA user_version = 4');
    db.dispose();
    return dbFile;
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig5_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('an untouched 60-minute default is moved to 30', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase(buildV4Db(minutesPerRow: 60, withChosenColumn: true)),
    );
    final settings = await TimeViewRepository(db).ensure();
    expect(settings.minutesPerRow, 30,
        reason: 'the user never chose 60, so they get the new fine default');
    expect(settings.minutesPerRowChosen, isFalse);
    await db.close();
  });

  test('a deliberate 60-minute choice survives', () async {
    final db = AppDatabase.forTesting(NativeDatabase(
      buildV4Db(minutesPerRow: 60, withChosenColumn: true, chosen: true),
    ));
    final settings = await TimeViewRepository(db).ensure();
    expect(settings.minutesPerRow, 60,
        reason: 'the user explicitly picked 60 and must keep it');
    expect(settings.minutesPerRowChosen, isTrue);
    await db.close();
  });

  test('the v5 column is added when the table predates it', () async {
    // This is the shape an actual v4 database has: time_view_settings was
    // created by the v4 release, whose schema did NOT yet carry
    // `minutes_per_row_chosen`. Drift refuses to map such rows (non-null
    // read), so the migration must add the column before anything else.
    final db = AppDatabase.forTesting(
      NativeDatabase(buildV4Db(minutesPerRow: 60)),
    );
    final settings = await TimeViewRepository(db).ensure();
    expect(settings.minutesPerRowChosen, isFalse);
    expect(settings.minutesPerRow, 30,
        reason: 'no deliberate choice on record -> new fine default');
    await db.close();
  });

  test('a file stamped v5 but missing the v5 column is repaired on open',
      () async {
    // Reproduces the real development database: user_version already says 5,
    // so Drift skips onUpgrade entirely, yet time_view_settings has no
    // minutes_per_row_chosen column. beforeOpen must heal it, otherwise the
    // generated mapper throws on the non-null read.
    final dbFile = buildV4Db(minutesPerRow: 60);
    final raw = sql.sqlite3.open(dbFile.path);
    raw.execute('PRAGMA user_version = 5');
    raw.dispose();

    final db = AppDatabase.forTesting(NativeDatabase(dbFile));
    final settings = await TimeViewRepository(db).ensure();
    expect(settings.minutesPerRowChosen, isFalse,
        reason: 'the column must exist after beforeOpen healed the file');
    // Healing adds the column but does not reinterpret the stored value:
    // that is the migration's job, and the version said it already ran.
    expect(settings.minutesPerRow, 60);
    await db.close();
  });

  test('a deliberate 15-minute choice survives untouched', () async {
    final db = AppDatabase.forTesting(NativeDatabase(
      buildV4Db(minutesPerRow: 15, withChosenColumn: true, chosen: true),
    ));
    expect((await TimeViewRepository(db).ensure()).minutesPerRow, 15);
    await db.close();
  });

  test('the v5 column exists and reads as "not chosen" in the old default case',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase(
      buildV4Db(minutesPerRow: 60, withChosenColumn: true),
    ));
    final settings = await TimeViewRepository(db).ensure();
    expect(settings.minutesPerRowChosen, isFalse);
    expect(settings.minutesPerRow, 30);
    await db.close();
  });

  test('other view preferences are not disturbed by the migration', () async {
    final db = AppDatabase.forTesting(NativeDatabase(
      buildV4Db(minutesPerRow: 60, withChosenColumn: true),
    ));
    final settings = await TimeViewRepository(db).ensure();
    expect(settings.timelineSpanDays, 730);
    expect(settings.timelinePxPerDay, 6);
    expect(settings.timelineCollapsed, isFalse);
    await db.close();
  });
}

import 'dart:io';

// `isNull` exists in both packages as a *different* thing: drift's is a SQL
// query expression, matcher's is the test predicate. Hide drift's so the
// expectations read normally.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v6 -> v7: `local_settings.ai_max_rounds`, the agent loop's tool-call budget.
///
/// The migration has to satisfy three separate claims, and each one fails in
/// its own way:
///
///  1. A real v6 file opens and gains the column - no missing-column crash.
///  2. A file stamped v7 whose column was never written is **healed** on open,
///     by the same `beforeOpen` self-heal the v5/v6 columns use, because Drift
///     skips `onUpgrade` entirely for a file whose version is already current.
///  3. The column arrives **unset**. NULL means "the user never chose", which
///     [AiConfig] resolves to the shipped default; writing 8 into every
///     existing row would instead freeze today's default into every install.
///
/// Lives here rather than next to the v1..v6 migration tests because this task
/// owns new AI tests under `test/features/ai/`; the shape is copied from
/// `test/data/database/v6_migration_test.dart`.
void main() {
  late Directory tempDir;

  /// Builds a database in the **v6 shape**: every table the v6 release had,
  /// with its five `local_settings.ai_*` columns, and without
  /// `ai_max_rounds` unless [withV7Column] asks for it.
  ///
  /// Kept as raw SQL on purpose - that is what an on-disk v6 file looks like.
  File buildV6Db({int userVersion = 6, bool withV7Column = false}) {
    final dbFile = File('${tempDir.path}/v6_${userVersion}_$withV7Column.db');
    final db = sql.sqlite3.open(dbFile.path);
    db.execute('''
CREATE TABLE profiles (
  id TEXT PRIMARY KEY, display_name TEXT, avatar_color INTEGER, created_at INTEGER);
CREATE TABLE local_settings (
  id INTEGER PRIMARY KEY, language TEXT NOT NULL DEFAULT 'system',
  theme_mode TEXT NOT NULL DEFAULT 'system', profile_id TEXT,
  active_theme_id TEXT,
  ai_enabled INTEGER NOT NULL DEFAULT 0, ai_api_key TEXT, ai_base_url TEXT,
  ai_model TEXT, ai_permission_mode TEXT,
  ${withV7Column ? 'ai_max_rounds INTEGER,' : ''}
  created_at INTEGER NOT NULL, updated_at INTEGER);
CREATE TABLE tags (
  id TEXT PRIMARY KEY, parent_id TEXT, name TEXT NOT NULL, path TEXT, color INTEGER,
  description TEXT, sort_order INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
CREATE TABLE object_tags (
  id TEXT PRIMARY KEY, tag_id TEXT NOT NULL, object_type TEXT NOT NULL,
  object_id TEXT NOT NULL, created_at INTEGER NOT NULL);
CREATE TABLE mind_maps (
  id TEXT PRIMARY KEY, title TEXT NOT NULL, created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL);
CREATE TABLE mind_nodes (
  id TEXT PRIMARY KEY, map_id TEXT NOT NULL, parent_id TEXT, title TEXT NOT NULL,
  note TEXT, sort_order INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
CREATE TABLE tasks (
  id TEXT PRIMARY KEY, parent_id TEXT, title TEXT NOT NULL, description TEXT,
  status TEXT NOT NULL DEFAULT 'todo', priority INTEGER NOT NULL DEFAULT 1,
  estimate_minutes INTEGER, due_at INTEGER, remind_at INTEGER, expected_at INTEGER,
  energy_required INTEGER, completed_at INTEGER, started_at INTEGER,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
CREATE TABLE task_dependencies (
  id TEXT PRIMARY KEY, task_id TEXT NOT NULL, depends_on_task_id TEXT NOT NULL,
  created_at INTEGER NOT NULL);
CREATE TABLE time_blocks (
  id TEXT PRIMARY KEY, title TEXT NOT NULL, start_at INTEGER NOT NULL,
  end_at INTEGER NOT NULL, repeat_rule TEXT, available INTEGER NOT NULL DEFAULT 1,
  energy TEXT, suitable_for TEXT, created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL);
CREATE TABLE task_time_blocks (
  id TEXT PRIMARY KEY, task_id TEXT NOT NULL, time_block_id TEXT NOT NULL,
  created_at INTEGER NOT NULL);
CREATE TABLE knowledge_points (
  id TEXT PRIMARY KEY, title TEXT NOT NULL, description TEXT,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
CREATE TABLE card_templates (
  id TEXT PRIMARY KEY, knowledge_point_id TEXT, kind TEXT NOT NULL DEFAULT 'basic',
  front TEXT, back TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
CREATE TABLE card_states (
  id TEXT PRIMARY KEY, card_template_id TEXT, due_at INTEGER,
  interval_days REAL NOT NULL DEFAULT 0, ease REAL NOT NULL DEFAULT 2.5,
  repetitions INTEGER NOT NULL DEFAULT 0, lapses INTEGER NOT NULL DEFAULT 0,
  state TEXT NOT NULL DEFAULT 'new', last_reviewed_at INTEGER,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  knowledge_point_id TEXT, unit_key TEXT, stability REAL, difficulty REAL,
  forced INTEGER NOT NULL DEFAULT 0, forced_streak INTEGER NOT NULL DEFAULT 0,
  encoding_strength REAL, savings REAL);
CREATE TABLE review_logs (
  id TEXT PRIMARY KEY, card_state_id TEXT NOT NULL, card_template_id TEXT,
  unit_key TEXT, rating INTEGER, rating_fsrs INTEGER, correct INTEGER,
  judge_mode TEXT, format TEXT, ms_taken INTEGER, reviewed_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL);
CREATE TABLE knowledge_packages (
  id TEXT PRIMARY KEY, title TEXT NOT NULL, created_at INTEGER NOT NULL);
CREATE TABLE package_items (
  id TEXT PRIMARY KEY, package_id TEXT NOT NULL, created_at INTEGER NOT NULL);
CREATE TABLE thread_states (
  id TEXT PRIMARY KEY, task_id TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'new',
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
CREATE TABLE task_templates (
  id TEXT PRIMARY KEY, title TEXT NOT NULL, payload TEXT NOT NULL,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
CREATE TABLE completion_logs (
  id TEXT PRIMARY KEY, task_id TEXT NOT NULL, title TEXT NOT NULL, tag_ids TEXT,
  tag_paths TEXT, estimate_minutes INTEGER, energy_required INTEGER,
  completed_at INTEGER NOT NULL, actual_minutes INTEGER,
  include_in_model INTEGER NOT NULL DEFAULT 1,
  duration_suspicious INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);
CREATE TABLE cloze_slots (
  id TEXT PRIMARY KEY, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
CREATE TABLE cloze_history (
  id TEXT PRIMARY KEY, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
CREATE TABLE boost_entries (
  id TEXT PRIMARY KEY, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
CREATE TABLE themes (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, payload TEXT NOT NULL,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
CREATE TABLE attachments (
  id TEXT PRIMARY KEY, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
CREATE TABLE thread_rank_settings (
  id INTEGER PRIMARY KEY, w_urgency REAL NOT NULL DEFAULT 0.4,
  w_goal REAL NOT NULL DEFAULT 0.3, w_fit REAL NOT NULL DEFAULT 0.2,
  w_fatigue REAL NOT NULL DEFAULT 0.1, w_expected REAL NOT NULL DEFAULT 0.05,
  header_collapsed INTEGER NOT NULL DEFAULT 0,
  use_actual_time INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL, created_at INTEGER NOT NULL);
CREATE TABLE diffusion_logs (
  id TEXT PRIMARY KEY, owner_type TEXT NOT NULL, owner_id TEXT, owner_title TEXT,
  kind TEXT NOT NULL, knowledge_point_id TEXT, knowledge_point_title TEXT,
  distance INTEGER, factor REAL, detail TEXT, day_key TEXT, occurred_at INTEGER,
  created_at INTEGER NOT NULL);
CREATE TABLE time_templates (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, kind TEXT NOT NULL, payload TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL);
CREATE TABLE time_view_settings (
  id INTEGER PRIMARY KEY, timeline_span_days INTEGER NOT NULL DEFAULT 730,
  timeline_px_per_day REAL NOT NULL DEFAULT 6,
  timeline_collapsed INTEGER NOT NULL DEFAULT 0,
  minutes_per_row INTEGER NOT NULL DEFAULT 30,
  minutes_per_row_chosen INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER, created_at INTEGER NOT NULL);
CREATE TABLE ai_conversations (
  id TEXT PRIMARY KEY, title TEXT NOT NULL, created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL);
CREATE TABLE ai_messages (
  id TEXT PRIMARY KEY, conversation_id TEXT NOT NULL, role TEXT NOT NULL,
  content TEXT, tool_call_id TEXT, created_at INTEGER NOT NULL);
CREATE TABLE ai_actions (
  id TEXT PRIMARY KEY, conversation_id TEXT NOT NULL, message_id TEXT,
  tool_call_id TEXT, tool_name TEXT NOT NULL, args_json TEXT NOT NULL,
  risk TEXT NOT NULL, status TEXT NOT NULL, before_json TEXT, after_json TEXT,
  result_json TEXT, created_at INTEGER NOT NULL, updated_at INTEGER);
''');

    // Rows an existing user would have: a settings row with AI already
    // configured, and a task that predates the upgrade.
    final roundColumn = withV7Column ? 'ai_max_rounds, ' : '';
    final roundValue = withV7Column ? '5, ' : '';
    db.execute('''
INSERT INTO local_settings (id, language, theme_mode, ai_enabled, ai_model,
  ${roundColumn}created_at, updated_at)
VALUES (1, 'zh', 'system', 1, 'deepseek-chat', ${roundValue}1700000000000,
  1700000000000)''');
    db.execute('''
INSERT INTO profiles (id, display_name, created_at)
VALUES ('p1', '旧用户', 1700000000000)''');
    db.execute('''
INSERT INTO tasks (id, title, status, created_at, updated_at)
VALUES ('t1', '升级前就有的任务', 'todo', 1700000000000, 1700000000000)''');

    db.execute('PRAGMA user_version = $userVersion');
    db.dispose();
    return dbFile;
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig7_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a real v6 file upgrades and keeps its rows and AI settings', () async {
    final db = AppDatabase.forTesting(NativeDatabase(buildV6Db()));
    // Touching the stores is the point: a missing column throws here.
    expect((await db.select(db.tasks).get()).single.title, '升级前就有的任务');
    expect((await db.select(db.profiles).get()).single.displayName, '旧用户');
    final settings = (await db.select(db.localSettings).get()).single;
    expect(settings.language, 'zh');
    expect(settings.aiEnabled, isTrue, reason: 'the upgrade must not reset AI');
    expect(settings.aiModel, 'deepseek-chat');
    await db.close();
  });

  test('the upgraded column reads as "never chosen", not as the default',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase(buildV6Db()));
    final settings = (await db.select(db.localSettings).get()).single;
    // NULL, not the shipped default: an upgraded install must keep following it
    // rather than having today's default frozen into its settings row.
    expect(settings.aiMaxRounds, isNull);
    // ...and the repository turns that NULL into the default for the loop.
    expect((await AiRepository(db).getConfig()).maxRounds,
        AiConfig.defaultMaxRounds);
    await db.close();
  });

  test('a file stamped v7 but missing the column is healed on open', () async {
    // Reproduces the real-world shape this project already hit with v5:
    // user_version says 7, so Drift skips onUpgrade entirely, yet the column
    // was never written. beforeOpen must repair the file or the generated
    // mapper throws on the read.
    final db = AppDatabase.forTesting(
      NativeDatabase(buildV6Db(userVersion: 7)),
    );
    expect((await db.select(db.localSettings).get()).single.aiMaxRounds, isNull,
        reason: 'beforeOpen must have added the column');
    await db.close();
  });

  test('a v7 file that already has the column keeps its value', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase(buildV6Db(userVersion: 7, withV7Column: true)),
    );
    final settings = (await db.select(db.localSettings).get()).single;
    expect(settings.aiMaxRounds, 5, reason: 'still the stored budget');
    expect(settings.aiModel, 'deepseek-chat', reason: 'unchanged by the heal');
    expect((await AiRepository(db).getConfig()).maxRounds, 5,
        reason: 'and the repository reads it back for the loop');
    await db.close();
  });

  test('the new column is writable through the generated mapper', () async {
    final db = AppDatabase.forTesting(NativeDatabase(buildV6Db()));
    await (db.update(db.localSettings)..where((t) => t.id.equals(1))).write(
      const LocalSettingsCompanion(aiMaxRounds: Value(12)),
    );
    expect((await db.select(db.localSettings).get()).single.aiMaxRounds, 12);
    await db.close();
  });
}

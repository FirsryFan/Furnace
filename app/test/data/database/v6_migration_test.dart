import 'dart:io';

// `isNull` exists in both packages as a *different* thing: drift's is a SQL
// query expression, matcher's is the test predicate. Hide drift's so the
// expectations read normally.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v5 -> v6: AI conversation storage, the AI settings columns, and the two
/// cognitive-model fields (`encoding_strength` / `savings`).
///
/// Three things must hold, and each is a separate failure mode:
///
///  1. A real v5 file opens and **upgrades** - no missing-column crash.
///  2. A file stamped v6 whose columns were never added is **healed** on open
///     (the self-heal path that already exists for v5).
///  3. **Existing data survives**: an old build that never heard of AI must
///     still read its rows afterwards, and the new columns must read as
///     "unset" rather than being fabricated as 1.0 / 0.
void main() {
  late Directory tempDir;

  /// Builds a database in the **v5 shape**: every table the v5 release had,
  /// without the three `ai_*` tables, without the five `local_settings.ai_*`
  /// columns, and without `card_states.encoding_strength` / `savings`.
  ///
  /// The column lists mirror `tables.dart` minus the v6 additions; the tables
  /// this file does not touch are declared in their v5 form so the generated
  /// mappers have something to read. Kept as raw SQL on purpose - that is what
  /// an on-disk v5 file actually looks like.
  File buildV5Db({int userVersion = 5, bool withV6Columns = false}) {
    final dbFile = File('${tempDir.path}/v5_${userVersion}_$withV6Columns.db');
    final db = sql.sqlite3.open(dbFile.path);
    db.execute('''
CREATE TABLE profiles (
  id TEXT PRIMARY KEY, display_name TEXT, avatar_color INTEGER, created_at INTEGER);
CREATE TABLE local_settings (
  id INTEGER PRIMARY KEY, language TEXT NOT NULL DEFAULT 'system',
  theme_mode TEXT NOT NULL DEFAULT 'system', profile_id TEXT,
  active_theme_id TEXT,
  ${withV6Columns ? 'ai_enabled INTEGER NOT NULL DEFAULT 0, ai_api_key TEXT, ai_base_url TEXT, ai_model TEXT, ai_permission_mode TEXT,' : ''}
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
  forced INTEGER NOT NULL DEFAULT 0, forced_streak INTEGER NOT NULL DEFAULT 0
  ${withV6Columns ? ', encoding_strength REAL, savings REAL' : ''});
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
''');

    // Rows an existing user would have.
    db.execute("INSERT INTO local_settings (id, language, theme_mode, created_at, "
        "updated_at) VALUES (1, 'zh', 'system', 1700000000000, 1700000000000)");
    db.execute("INSERT INTO profiles (id, display_name, created_at) "
        "VALUES ('p1', '旧用户', 1700000000000)");
    db.execute("INSERT INTO tasks (id, title, status, created_at, updated_at) "
        "VALUES ('t1', '升级前就有的任务', 'todo', 1700000000000, 1700000000000)");
    db.execute("INSERT INTO knowledge_points (id, title, created_at, updated_at) "
        "VALUES ('kp1', '力学', 1700000000000, 1700000000000)");
    db.execute('''
INSERT INTO card_states (id, knowledge_point_id, unit_key, state, stability,
  difficulty, created_at, updated_at)
VALUES ('cs1', 'kp1', 'cloze:s1', 'review', 12.5, 5.25, 1700000000000, 1700000000000)''');

    db.execute('PRAGMA user_version = $userVersion');
    db.dispose();
    return dbFile;
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig6_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a real v5 file upgrades and keeps its rows', () async {
    final db = AppDatabase.forTesting(NativeDatabase(buildV5Db()));
    // Touching each store is the point: a missing column would throw here.
    expect((await db.select(db.tasks).get()).single.title, '升级前就有的任务');
    expect((await db.select(db.profiles).get()).single.displayName, '旧用户');
    expect((await db.select(db.localSettings).get()).single.language, 'zh');
    await db.close();
  });

  test('the v6 AI tables exist after upgrading a v5 file', () async {
    final db = AppDatabase.forTesting(NativeDatabase(buildV5Db()));
    // Empty, but present and readable.
    expect(await db.select(db.aiConversations).get(), isEmpty);
    expect(await db.select(db.aiMessages).get(), isEmpty);
    expect(await db.select(db.aiActions).get(), isEmpty);
    await db.close();
  });

  test('the AI settings columns are added and default to "AI is off"', () async {
    final db = AppDatabase.forTesting(NativeDatabase(buildV5Db()));
    final row = (await db.select(db.localSettings).get()).single;
    expect(row.aiEnabled, isFalse,
        reason: 'an existing install must not have AI switched on by the '
            'migration - the offline default has to survive the upgrade');
    expect(row.aiApiKey, isNull);
    expect(row.aiBaseUrl, isNull);
    expect(row.aiModel, isNull);
    expect(row.aiPermissionMode, isNull);
    await db.close();
  });

  test('the cognitive-model columns are added as unset, not fabricated', () async {
    final db = AppDatabase.forTesting(NativeDatabase(buildV5Db()));
    final state = (await db.select(db.cardStates).get()).single;
    // NULL, not 1.0 / 0.0: "never recorded" and "recorded as 1.0" are
    // different facts, and the MindNet port depends on telling them apart.
    expect(state.encodingStrength, isNull);
    expect(state.savings, isNull);
    // The pre-existing FSRS state is untouched.
    expect(state.stability, 12.5);
    expect(state.difficulty, 5.25);
    await db.close();
  });

  test('an existing install can still write after upgrading', () async {
    final db = AppDatabase.forTesting(NativeDatabase(buildV5Db()));
    await db.into(db.tasks).insert(TasksCompanion.insert(
          id: 't2',
          title: '升级后新建的任务',
          status: const Value('todo'),
          createdAt: 1700000001000,
          updatedAt: 1700000001000,
        ));
    expect((await db.select(db.tasks).get()).length, 2);

    // And the new settings columns are writable through the generated mapper.
    await (db.update(db.localSettings)..where((t) => t.id.equals(1))).write(
      const LocalSettingsCompanion(aiEnabled: Value(true), aiModel: Value('deepseek-chat')),
    );
    final row = (await db.select(db.localSettings).get()).single;
    expect(row.aiEnabled, isTrue);
    expect(row.aiModel, 'deepseek-chat');
    await db.close();
  });

  test('a file stamped v6 but missing the v6 columns is healed on open',
      () async {
    // Reproduces the real-world shape this project already hit once with v5:
    // user_version says 6, so Drift skips onUpgrade entirely, yet the columns
    // were never written. beforeOpen must repair the file or the generated
    // mapper throws on the non-null read.
    final db = AppDatabase.forTesting(
      NativeDatabase(buildV5Db(userVersion: 6)),
    );
    final state = (await db.select(db.cardStates).get()).single;
    expect(state.encodingStrength, isNull,
        reason: 'beforeOpen must have added the column');
    expect((await db.select(db.localSettings).get()).single.aiEnabled, isFalse,
        reason: 'beforeOpen must have added the AI columns');
    await db.close();
  });

  test('a v6 file that already has the columns is left alone', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase(buildV5Db(userVersion: 6, withV6Columns: true)),
    );
    final state = (await db.select(db.cardStates).get()).single;
    expect(state.encodingStrength, isNull, reason: 'still unset, not zeroed');
    expect(state.stability, 12.5, reason: 'existing value untouched');
    await db.close();
  });

  test('conversations and actions round-trip through the new tables', () async {
    final db = AppDatabase.forTesting(NativeDatabase(buildV5Db()));
    await db.into(db.aiConversations).insert(AiConversationsCompanion.insert(
          id: 'c1',
          title: '第一次对话',
          createdAt: 1700000002000,
          updatedAt: 1700000002000,
        ));
    await db.into(db.aiMessages).insert(AiMessagesCompanion.insert(
          id: 'm1',
          conversationId: 'c1',
          role: 'user',
          content: const Value('帮我建个任务'),
          createdAt: 1700000002000,
        ));
    await db.into(db.aiActions).insert(AiActionsCompanion.insert(
          id: 'a1',
          conversationId: 'c1',
          toolName: 'manage_task',
          argsJson: '{"action":"create"}',
          risk: 'write',
          status: 'executed',
          createdAt: 1700000002000,
        ));

    expect((await db.select(db.aiMessages).get()).single.content, '帮我建个任务');
    expect((await db.select(db.aiActions).get()).single.status, 'executed');
    await db.close();
  });
}

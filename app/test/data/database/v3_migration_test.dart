import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowflow/data/database/database.dart';
import 'package:knowflow/data/repositories/diffusion_log_repository.dart';
import 'package:knowflow/data/repositories/task_repository.dart';
import 'package:knowflow/data/repositories/thread_rank_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// Builds a real v2 database file and verifies the v2 -> v3 upgrade in place
/// (blueprint v2 / user annotations 2026-09-08).
void main() {
  late Directory tempDir;
  late File dbFile;
  const now = 1700000000000;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('threadflow_mig3_');
    dbFile = File('${tempDir.path}/v2.db');
    final db = sql.sqlite3.open(dbFile.path);
    db.execute('''
CREATE TABLE local_settings (
  id INTEGER PRIMARY KEY, language TEXT, theme_mode TEXT, profile_id TEXT,
  active_theme_id TEXT, created_at INTEGER, updated_at INTEGER);
CREATE TABLE tags (
  id TEXT PRIMARY KEY, parent_id TEXT, name TEXT, path TEXT, color INTEGER,
  description TEXT, source_node_id TEXT, created_at INTEGER, updated_at INTEGER);
CREATE TABLE tasks (
  id TEXT PRIMARY KEY, parent_id TEXT, title TEXT, description TEXT,
  status TEXT, priority INTEGER, estimate_minutes INTEGER, due_at INTEGER,
  remind_at INTEGER, expected_at INTEGER, energy_required INTEGER,
  completed_at INTEGER, created_at INTEGER, updated_at INTEGER);
CREATE TABLE completion_logs (
  id TEXT PRIMARY KEY, task_id TEXT, title TEXT, tag_ids TEXT, tag_paths TEXT,
  estimate_minutes INTEGER, energy_required INTEGER, completed_at INTEGER,
  created_at INTEGER);
CREATE TABLE thread_states (
  id INTEGER PRIMARY KEY, energy INTEGER, goal_text TEXT, goal_node_id TEXT,
  goal_path TEXT, updated_at INTEGER, created_at INTEGER);
CREATE TABLE time_blocks (
  id TEXT PRIMARY KEY, title TEXT, start_at INTEGER, end_at INTEGER,
  repeat_rule TEXT, available INTEGER, energy TEXT, suitable_for TEXT,
  created_at INTEGER, updated_at INTEGER);
''');
    db.execute(
      "INSERT INTO tasks (id, title, status, priority, estimate_minutes, "
      "expected_at, created_at, updated_at) VALUES "
      "('task1', '读完第三章', 'todo', 1, 40, $now, $now, $now)",
    );
    db.execute(
      "INSERT INTO completion_logs (id, task_id, title, estimate_minutes, "
      "completed_at, created_at) VALUES "
      "('cl1', 'task1', '旧记录', 30, $now, $now)",
    );
    db.execute(
      "INSERT INTO thread_states (id, energy, goal_text, updated_at, created_at) "
      "VALUES (1, 7, '数学', $now, $now)",
    );
    // Card tables are referenced by the schema; create the minimal shapes.
    db.execute('CREATE TABLE knowledge_points (id TEXT PRIMARY KEY, title TEXT)');
    db.execute('''
CREATE TABLE card_states (
  id TEXT PRIMARY KEY, card_template_id TEXT, due_at INTEGER,
  interval_days REAL DEFAULT 0, ease REAL DEFAULT 2.5,
  repetitions INTEGER DEFAULT 0, lapses INTEGER DEFAULT 0, state TEXT,
  last_reviewed_at INTEGER, created_at INTEGER, updated_at INTEGER,
  knowledge_point_id TEXT, unit_key TEXT, stability REAL, difficulty REAL,
  forced INTEGER DEFAULT 0, forced_streak INTEGER DEFAULT 0)''');
    db.execute('CREATE TABLE card_templates (id TEXT PRIMARY KEY)');
    db.execute('''
CREATE TABLE review_logs (
  id TEXT PRIMARY KEY, card_state_id TEXT, card_template_id TEXT,
  unit_key TEXT, rating INTEGER, rating_fsrs INTEGER, correct INTEGER,
  judge_mode TEXT, format TEXT, ms_taken INTEGER, reviewed_at INTEGER,
  created_at INTEGER)''');
    db.execute('PRAGMA user_version = 2');
    db.dispose();
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('opens a v2 database and migrates it to v3 in place', () async {
    final db = AppDatabase.forTesting(NativeDatabase(dbFile));

    // --- legacy rows survive, new columns read as null/default -------------
    final tasks = TaskRepository(db);
    final legacy = await tasks.getTaskById('task1');
    expect(legacy, isNotNull);
    expect(legacy!.estimateMinutes, 40);
    expect(legacy.expectedAt, now);
    expect(legacy.startedAt, isNull);

    final legacyLog = (await db.select(db.completionLogs).get()).single;
    expect(legacyLog.title, '旧记录');
    expect(legacyLog.actualMinutes, isNull);
    expect(legacyLog.durationSuspicious, isFalse);

    // Existing thread status is untouched.
    final state = (await db.select(db.threadStates).get()).single;
    expect(state.energy, 7);
    expect(state.goalText, '数学');

    // --- new ranking settings table seeds with the shipped defaults --------
    final rank = ThreadRankRepository(db);
    final weights = await rank.getWeights();
    expect(weights.urgency, 0.4);
    expect(weights.goal, 0.3);
    expect(weights.fit, 0.2);
    expect(weights.fatigue, 0.1);
    expect(weights.expected, 0.05);
    expect(await rank.isHeaderCollapsed(), isFalse);
    expect(await rank.getUseActualTime(), isTrue);

    // Parameters are editable and persist.
    await rank.updateWeights(urgency: 0.5, expected: 0.2);
    final edited = await rank.getWeights();
    expect(edited.urgency, 0.5);
    expect(edited.expected, 0.2);
    expect(edited.goal, 0.3, reason: 'untouched weights keep their value');
    await rank.resetWeights();
    expect((await rank.getWeights()).urgency, 0.4);

    // --- new diffusion ledger table accepts rows ---------------------------
    final ledger = DiffusionLogRepository(db);
    await ledger.append(
      ownerType: 'knowledge',
      ownerId: 'kp1',
      ownerTitle: '光合作用',
      kind: 'wrong',
      knowledgePointTitle: '光合作用场所',
      detail: '叶绿体',
      occurredAt: DateTime.fromMillisecondsSinceEpoch(now),
    );
    await ledger.append(
      ownerType: 'knowledge',
      ownerId: 'kp2',
      ownerTitle: '呼吸作用',
      kind: 'boost',
      knowledgePointTitle: '呼吸作用场所',
      distance: 1,
      factor: 1.8,
      occurredAt:
          DateTime.fromMillisecondsSinceEpoch(now).add(const Duration(seconds: 1)),
    );
    final today = await ledger.getForDay(
      DateTime.fromMillisecondsSinceEpoch(now),
    );
    expect(today, hasLength(2));
    expect(today.first.kind, 'boost', reason: 'newest line first');
    expect(today.first.dayKey, '2023-11-15');

    await db.close();
  });
}

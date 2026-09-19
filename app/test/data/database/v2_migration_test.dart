import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowflow/data/database/database.dart';
import 'package:knowflow/data/repositories/anki_repository.dart';
import 'package:knowflow/data/repositories/task_repository.dart';
import 'package:knowflow/data/repositories/thread_state_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// Builds a real v1 database file (subset of the v1 tables touched by the
/// migration) and verifies the v1 -> v2 upgrade in place.
void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('threadflow_mig_');
    dbFile = File('${tempDir.path}/v1.db');
    final db = sql.sqlite3.open(dbFile.path);
    db.execute('''
CREATE TABLE local_settings (
  id INTEGER PRIMARY KEY, language TEXT, theme_mode TEXT,
  profile_id TEXT, created_at INTEGER, updated_at INTEGER);
CREATE TABLE tags (
  id TEXT PRIMARY KEY, name TEXT, color INTEGER, description TEXT,
  source_node_id TEXT, created_at INTEGER, updated_at INTEGER);
CREATE TABLE tasks (
  id TEXT PRIMARY KEY, parent_id TEXT, title TEXT, description TEXT,
  status TEXT, priority INTEGER, estimate_minutes INTEGER, due_at INTEGER,
  remind_at INTEGER, created_at INTEGER, updated_at INTEGER);
CREATE TABLE knowledge_points (
  id TEXT PRIMARY KEY, title TEXT, content TEXT, source TEXT,
  external_id TEXT, package_id TEXT, created_at INTEGER, updated_at INTEGER);
CREATE TABLE card_templates (
  id TEXT PRIMARY KEY, knowledge_point_id TEXT, type TEXT, question TEXT,
  answer TEXT, options TEXT, cloze_template TEXT, hint TEXT, sort_order INTEGER,
  external_id TEXT, created_at INTEGER, updated_at INTEGER);
CREATE TABLE card_states (
  id TEXT PRIMARY KEY, card_template_id TEXT, due_at INTEGER,
  interval_days REAL DEFAULT 0, ease REAL DEFAULT 2.5,
  repetitions INTEGER DEFAULT 0, lapses INTEGER DEFAULT 0,
  state TEXT DEFAULT 'new', last_reviewed_at INTEGER,
  created_at INTEGER, updated_at INTEGER);
CREATE TABLE review_logs (
  id TEXT PRIMARY KEY, card_state_id TEXT, card_template_id TEXT,
  rating INTEGER, reviewed_at INTEGER, created_at INTEGER);
''');
    final now = 1700000000000;
    db.execute(
      'INSERT INTO local_settings (id, language, theme_mode, created_at, updated_at) '
      'VALUES (1, \'zh\', \'dark\', $now, $now)',
    );
    // Duplicate-name top tags: migration must keep one and suffix the other.
    db.execute(
      "INSERT INTO tags (id, name, created_at, updated_at) VALUES "
      "('t1', '阅读', $now, $now), ('t2', '阅读', $now, $now), "
      "('t3', '写作', $now, $now)",
    );
    db.execute(
      "INSERT INTO tasks (id, title, status, priority, created_at, updated_at) "
      "VALUES ('task1', '读完第三章', 'todo', 1, $now, $now)",
    );
    db.execute(
      "INSERT INTO knowledge_points (id, title, content, created_at, updated_at) "
      "VALUES ('kp1', '光合作用场所', '光合作用主要场所是叶绿体。', $now, $now)",
    );
    db.execute(
      "INSERT INTO card_templates (id, knowledge_point_id, type, question, answer, "
      "sort_order, created_at, updated_at) VALUES "
      "('tpl1', 'kp1', 'fill_blank', '光合作用的主要场所是___。', '叶绿体', 0, $now, $now)",
    );
    db.execute(
      "INSERT INTO card_states (id, card_template_id, state, created_at, updated_at) "
      "VALUES ('cs1', 'tpl1', 'review', $now, $now)",
    );
    db.execute(
      "INSERT INTO review_logs (id, card_state_id, card_template_id, rating, "
      "reviewed_at, created_at) VALUES ('log1', 'cs1', 'tpl1', 2, $now, $now)",
    );
    db.execute('PRAGMA user_version = 1');
    db.dispose();
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('opens a v1 database and migrates it to v2 in place', () async {
    final db = AppDatabase.forTesting(NativeDatabase(dbFile));

    // New v2 tables exist and accept writes.
    final states = ThreadStateRepository(db);
    await states.updateState(energy: 7, goalText: '数学');
    final state = await states.getState();
    expect(state, isNotNull);
    expect(state!.energy, 7);

    // Tasks gained the v2 columns.
    final tasks = TaskRepository(db);
    final task = await tasks.createTask(
      title: 'new event',
      expectedAt: 1700000001000,
      energyRequired: 6,
    );
    expect(task.expectedAt, 1700000001000);
    expect(task.energyRequired, 6);

    // Legacy task survived with defaulted columns.
    final legacy = await tasks.getTaskById('task1');
    expect(legacy, isNotNull);
    expect(legacy!.expectedAt, isNull);

    // Tags: path backfilled; same-name duplicates deduplicated; unique index.
    final tags = await db.select(db.tags).get();
    final paths = tags.map((t) => t.path).toList()..sort();
    expect(paths, contains('阅读'));
    expect(paths, contains('阅读-2'));
    expect(paths, contains('写作'));

    // Card state: knowledge point + unit key backfilled from template.
    final cardStates = await db.select(db.cardStates).get();
    expect(cardStates, hasLength(1));
    expect(cardStates.single.knowledgePointId, 'kp1');
    expect(cardStates.single.unitKey, 'preset:tpl1');
    expect(cardStates.single.forced, 0);

    // Review log: v2 columns writable.
    final anki = AnkiRepository(db);
    await anki.addReviewLog(
      cardStateId: cardStates.single.id,
      cardTemplateId: 'tpl1',
      rating: 1,
      ratingFsrs: 2,
      correct: 0,
      judgeMode: 'auto',
      format: 'fill',
      msTaken: 5000,
      reviewedAt: 1700000002000,
    );
    final logs = await db.select(db.reviewLogs).get();
    expect(logs, hasLength(2));
    final newest = logs.reduce((a, b) => a.reviewedAt > b.reviewedAt ? a : b);
    expect(newest.ratingFsrs, 2);
    expect(newest.correct, 0);
    expect(newest.format, 'fill');

    await db.close();
  });
}

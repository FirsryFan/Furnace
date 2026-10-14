import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/assessment_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v9 -> v10：测评层三张表（`docs/ASSESSMENT_DESIGN.md` §5）。
///
/// 三条断言，各有一个失败模式：
///
///  1. 真实的 v9 文件打开后**多出三张表、且一行不少**：老数据（设置、知识点、
///     复习日志）必须原样可读，否则迁移就是拿用户的库做实验。
///  2. 已经被盖成 v10、但表并不存在的文件，靠 `beforeOpen` 自愈：Drift 在
///     `user_version` 已等于当前版本时**完全跳过** `onUpgrade`，所以"表不存在"
///     这类伤只能由自愈路径处理（v5–v9 的列都是这么修的，v10 的表同理）。
///  3. **生成 schema 不带外键**：`references(...)` 在表定义里只是意图声明，SQLite
///     并不执行它（探针验证：连 v2 就存在的 `review_logs` 也没有外键）。所以"删
///     一轮连步骤一起删"必须是仓储的动作，这条断言就是那道防线。
void main() {
  late Directory tempDir;

  /// 造一个**v9 形状**的文件：v9 的全部表与列，没有测评层三张表。
  ///
  /// [userVersion] 控制文件自称的版本，用来复现"版本号跑在表前面"这一种伤。
  File buildV9Db({int userVersion = 9}) {
    final dbFile = File('${tempDir.path}/v9_$userVersion.db');
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
''');

    // 一个老用户会有的东西：设置行、一个知识点、一张卡、一条 r9 的形状的复习
    // 日志。
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
INSERT INTO review_logs (id, card_state_id, card_template_id, rating, correct,
  judge_mode, format, reviewed_at, created_at, reviewed_solution, closeness)
VALUES ('rl1', 'cs1', 'ct1', 1, 0, 'auto', 'fill', 1700000000000,
  1700000000000, 1, 0.6)''');

    db.execute('PRAGMA user_version = $userVersion');
    db.dispose();
    return dbFile;
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig10_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// `PRAGMA foreign_key_list` 里被引用的表名。
  Future<List<String>> referencedTables(AppDatabase db, String table) async {
    final rows = await db.customSelect('PRAGMA foreign_key_list($table)').get();
    return [for (final row in rows) row.read<String>('table')];
  }

  test('真实 v9 文件升级后三张表到位，老数据一行不少', () async {
    final db = AppDatabase.forTesting(NativeDatabase(buildV9Db()));

    // 三张新表都能读（表不存在会在这里抛 "no such table"），且都是空的：
    // 没有人被测过，"没测过"就是空表。
    expect(await db.select(db.assessmentSessions).get(), isEmpty);
    expect(await db.select(db.assessmentResponses).get(), isEmpty);
    expect(await db.select(db.cognitivePriors).get(), isEmpty);

    final settings = (await db.select(db.localSettings).get()).single;
    expect(settings.language, 'zh');
    expect(settings.aiEnabled, isTrue, reason: '升级不能把 AI 设置重置掉');
    final points = await db.select(db.knowledgePoints).get();
    expect(points.single.title, '叶绿体');
    final logs = await db.select(db.reviewLogs).get();
    expect(logs.single.reviewedSolution, isTrue, reason: 'v9 的列要原样留着');
    expect(logs.single.closeness, 0.6);
    await db.close();
  });

  test('生成 schema 不带外键——级联只能在仓储里显式做', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    // 这是实测出来的项目事实，不是猜的：项目里没有一张表带外键约束，连 v2 就在的
    // review_logs 也没有。把断言写成"为空"，是为了让任何"以为有 FK 兜底"的改动
    // 在这里先红一次，而不是在用户库里悄悄留下孤儿行。
    for (final table in <String>[
      'review_logs',
      'card_templates',
      'assessment_responses',
      'cognitive_priors',
    ]) {
      expect(
        await referencedTables(db, table),
        isEmpty,
        reason: '$table 目前不带外键约束（实测）',
      );
    }

    // 于是清理是仓储的动作：删一轮，步骤必须跟着走。
    final repo = AssessmentRepository(db);
    final sessionId = await repo.startSession();
    await repo.addStep(
      sessionId: sessionId,
      stepKind: AssessmentRepository.selfReportStep,
      selfRating: 3,
      now: DateTime(2026, 10, 15, 9, 1),
    );
    expect(await repo.steps(sessionId), hasLength(1));
    await repo.deleteSession(sessionId);
    expect(await repo.steps(sessionId), isEmpty);
    await db.close();
  });

  test('被盖成 v10 却没有表的文件，靠自愈补上并能写进去', () async {
    // user_version 已经是 10，所以 Drift 跳过 onUpgrade；表只能由 beforeOpen
    // 的自愈路径创建。
    final db = AppDatabase.forTesting(NativeDatabase(buildV9Db(userVersion: 10)));
    final repo = AssessmentRepository(db);
    final sessionId = await repo.startSession(
      subjectKey: 'biology',
      scopeTagIds: const <String>['t1'],
      now: DateTime(2026, 10, 15, 9),
    );
    await repo.addStep(
      sessionId: sessionId,
      stepKind: AssessmentRepository.selfReportStep,
      knowledgePointId: 'kp1',
      selfRating: 4,
      now: DateTime(2026, 10, 15, 9, 1),
    );
    final steps = await repo.steps(sessionId);
    expect(steps.single.selfRating, 4);
    expect(steps.single.judgedBy, 'self');
    await db.close();
  });
}

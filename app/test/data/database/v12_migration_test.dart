import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v11 -> v12：题库四张表（`docs/QUESTION_BANK_DESIGN.md`）。
///
/// 迁移本身只是"建四张空表"，所以两条断言锁的是两件容易坏的事：
///
///  1. 真实 v11 文件升级后**老数据一行不少**，且四张新表立刻能写能读
///     （题目 + 选项 + 标签边 + 一条推理链）。
///  2. 已经被盖成 v12、却没有这四张表的文件靠 `beforeOpen` 自愈——Drift 在
///     `user_version` 等于当前版本时完全跳过 `onUpgrade`，那一刻没有自愈就会
///     让每次组卷/推理读取都报 "no such table"。
void main() {
  late Directory tempDir;

  /// 造一个 **v11 形状**的文件：v11 的全部表（含 `review_logs.predicted_r`），
  /// 但没有 v12 的四张表。[userVersion] 用来复现"版本号跑在表前面"。
  File buildV11Db({int userVersion = 11}) {
    final dbFile = File('${tempDir.path}/v11_$userVersion.db');
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
  created_at INTEGER NOT NULL, reviewed_solution INTEGER, closeness REAL,
  predicted_r REAL);
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
CREATE TABLE tags (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, color INTEGER, parent_id TEXT,
  path TEXT, sort_order INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
CREATE TABLE object_tags (
  id TEXT PRIMARY KEY, tag_id TEXT NOT NULL, object_type TEXT NOT NULL,
  object_id TEXT NOT NULL, created_at INTEGER NOT NULL);
''');
    db.execute('''
INSERT INTO knowledge_points (id, title, content, created_at, updated_at)
VALUES ('kp1', '叶绿体', '光合作用的场所是叶绿体。', 1700000000000,
  1700000000000)''');
    db.execute('''
INSERT INTO tags (id, name, created_at, updated_at)
VALUES ('t1', '生物', 1700000000000, 1700000000000)''');
    db.execute('PRAGMA user_version = $userVersion');
    db.dispose();
    return dbFile;
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig12_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('真实 v11 文件升级后四张新表可用，老数据一行不少', () async {
    final db = AppDatabase.forTesting(NativeDatabase(buildV11Db()));
    final repo = QuestionRepository(db);

    expect(await db.select(db.knowledgePoints).get(), hasLength(1));

    final ingested = await repo.ingest(
      const QuestionDraft(
        stem: '光合作用的场所是（  ）',
        answer: '叶绿体',
        subjectKey: 'biology',
        questionType: 'single_choice',
        sourceLevel: 'gaokao',
        sourceLabel: '2024 湖南卷',
        year: 2024,
        options: [
          QuestionOptionDraft(label: 'A', content: '叶绿体', isCorrect: true),
          QuestionOptionDraft(label: 'B', content: '线粒体'),
        ],
        tagIds: {'t1'},
      ),
    );
    expect(ingested.created, isTrue);
    expect(ingested.question.stemFingerprint, isNotEmpty);
    expect(await repo.optionsOf(ingested.question.id), hasLength(2));
    expect(await repo.tagIdsOf(ingested.question.id), ['t1']);

    final chainId = await repo.saveChain(
      ingested.question.id,
      const ReasoningChainDraft(
        model: 'test-model',
        summary: '先定位场所，再排除细胞器',
        steps: [
          ReasoningStepDraft(goal: '读题找限定词', actionType: 'definition'),
          ReasoningStepDraft(
            goal: '排除线粒体',
            actionType: 'counterexample',
            stuckRisk: 1.4,
          ),
        ],
      ),
    );
    final steps = await repo.stepsOf(chainId);
    expect(steps.map((s) => s.idx), [0, 1]);
    expect(steps.last.stuckRisk, 1.0, reason: 'stuckRisk 钳到 [0,1]');
    expect((await repo.byId(ingested.question.id))!.state, 'processed');

    await db.close();
  });

  test('被盖成 v12 却没有这四张表的文件，靠自愈补上并能写进去', () async {
    // user_version 已经是 12，Drift 跳过 onUpgrade，表只能由 beforeOpen 补。
    final db = AppDatabase.forTesting(
      NativeDatabase(buildV11Db(userVersion: 12)),
    );
    final repo = QuestionRepository(db);

    final ingested = await repo.ingest(const QuestionDraft(stem: '自愈后仍能入库'));
    expect(ingested.created, isTrue);
    expect(await repo.all(), hasLength(1));

    await db.close();
  });
}

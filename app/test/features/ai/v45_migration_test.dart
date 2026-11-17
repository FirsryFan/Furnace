import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/features/ai/domain/agent_run.dart';
import 'package:furnace/features/ai/infrastructure/agent_run_store.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v44 -> v45: the five global agent-run tables
/// (STUDENT-MODE-AND-AGENT-LOOP-DESIGN §5.1-§5.6).
///
/// The schema is at v46 since the model-parameter layer landed, so a file
/// stamped 44 upgrades through both steps; what this test locks is still the
/// v45 part of that path:
///
///  1. A real v44 file opens, the five tables + indexes exist, and the old
///     conversation/message rows are untouched.
///  2. Migration is repeatable: opening twice does not throw (indexes use
///     `IF NOT EXISTS`, tables are probed before creation).
///  3. A file whose version says the tables exist but whose tables are missing
///     is healed by `beforeOpen`, and no data is lost.
///  4. A fresh database (onCreate) creates the five tables and their indexes.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig45_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  const agentTables = <String>[
    'agent_runs',
    'agent_steps',
    'agent_verifications',
    'agent_claims',
    'agent_experiences',
  ];

  const expectedIndexes = <String>{
    'idx_agent_runs_conversation',
    'idx_agent_runs_started',
    'idx_agent_steps_run',
    'idx_agent_verifications_run',
    'idx_agent_claims_run',
    'idx_agent_experiences_cluster',
  };

  /// Builds a current-schema database with one v44-era conversation + message,
  /// then DROPs the five agent tables and stamps [userVersion] - i.e. a file
  /// from before v45.
  Future<File> buildPreV45Db({
    required String name,
    int userVersion = 44,
  }) async {
    final file = File('${tempDir.path}/$name.db');
    final fresh = AppDatabase.forTesting(NativeDatabase(file));
    await fresh.into(fresh.aiConversations).insert(
          AiConversationsCompanion.insert(
            id: 'conv-old',
            title: '升级前的对话',
            createdAt: 1700000000000,
            updatedAt: 1700000000000,
          ),
        );
    await fresh.into(fresh.aiMessages).insert(
          AiMessagesCompanion.insert(
            id: 'msg-old',
            conversationId: 'conv-old',
            role: 'user',
            content: const Value('旧的用户消息'),
            createdAt: 1700000000001,
          ),
        );
    await fresh.close();

    final raw = sql.sqlite3.open(file.path);
    try {
      for (final table in agentTables) {
        raw.execute('DROP TABLE IF EXISTS $table');
      }
      raw.execute('PRAGMA user_version = $userVersion');
    } finally {
      raw.dispose();
    }
    return file;
  }

  int userVersionOf(String path) {
    final raw = sql.sqlite3.open(path);
    try {
      return raw.select('PRAGMA user_version').single['user_version'] as int;
    } finally {
      raw.dispose();
    }
  }

  Future<Set<String>> indexNamesOf(AppDatabase db) async {
    final rows = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_agent_%'",
    ).get();
    return {for (final row in rows) row.read<String>('name')};
  }

  Future<void> expectOldDataIntact(AppDatabase db) async {
    final conversations = await db.select(db.aiConversations).get();
    expect(conversations.length, 1);
    expect(conversations.single.id, 'conv-old');
    expect(conversations.single.title, '升级前的对话');
    final messages = await db.select(db.aiMessages).get();
    expect(messages.length, 1);
    expect(messages.single.content, '旧的用户消息');
  }

  AgentRunState newRun() => AgentRunState.start(
        id: 'run-v45',
        conversationId: 'conv-old',
        presetId: 'student_solver',
        mode: AgentMode.student,
        startedAt: 1700000001000,
      );

  test('真实 v44 文件升级：五表 + 六个索引建好，旧数据保留且可写', () async {
    final file = await buildPreV45Db(name: 'v44_upgrade');
    expect(userVersionOf(file.path), 44);

    final db = AppDatabase.forTesting(NativeDatabase(file));
    await db.select(db.aiConversations).get(); // 触发 onUpgrade + beforeOpen

    // 五张表都在，且关键列存在（不是空表壳）。
    for (final table in agentTables) {
      expect(await db.columnsOf(table), isNotEmpty, reason: '$table 应该存在');
    }
    expect(await db.columnsOf('agent_runs'), contains('answer_sheet_json'));
    expect(await db.columnsOf('agent_steps'), contains('state_fingerprint'));
    expect(await db.columnsOf('agent_verifications'), contains('verdict'));
    expect(await db.columnsOf('agent_claims'), contains('checked_version'));
    expect(await db.columnsOf('agent_experiences'), contains('revoked_at'));

    // 旧数据一行不少。
    await expectOldDataIntact(db);

    // 新表可写、可读。
    final store = AgentRunStore(db);
    final run = newRun();
    run.finish(AgentRunStatus.answered, nowMs: 1700000002000);
    await store.saveRun(run);
    final loaded = (await store.loadRun('run-v45'))!;
    expect(loaded.conversationId, 'conv-old');
    expect(loaded.status, AgentRunStatus.answered);
    expect(loaded.stopReason, isNull);

    // 索引是设计文档 §5.1-§5.5 那六条。
    expect(await indexNamesOf(db), containsAll(expectedIndexes));
    await db.close();

    // 当前 schema 是 v48：v44 -> v45 -> v46 -> v47 -> v48 一路升上来。
    expect(userVersionOf(file.path), 48);
  });

  test('迁移幂等：连续打开两次不抛，旧数据与新 run 都不变', () async {
    final file = await buildPreV45Db(name: 'twice');

    var db = AppDatabase.forTesting(NativeDatabase(file));
    await expectOldDataIntact(db);
    await AgentRunStore(db).saveRun(newRun());
    expect(await indexNamesOf(db), containsAll(expectedIndexes));
    await db.close();
    expect(userVersionOf(file.path), 48);

    // 第二次打开：onUpgrade 不再跑，只剩 beforeOpen 探表/探列/建索引。
    db = AppDatabase.forTesting(NativeDatabase(file));
    await expectOldDataIntact(db);
    final loaded = await AgentRunStore(db).loadRun('run-v45');
    expect(loaded, isNotNull);
    expect(loaded!.id, 'run-v45');
    expect(await indexNamesOf(db), containsAll(expectedIndexes));
    await db.close();

    expect(userVersionOf(file.path), 48);
  });

  test('版本号已是最新但缺表：beforeOpen 自愈建表，数据不丢', () async {
    final file = await buildPreV45Db(name: 'fake48', userVersion: 48);
    expect(userVersionOf(file.path), 48);
    final raw = sql.sqlite3.open(file.path);
    try {
      expect(
        raw
            .select(
              "SELECT name FROM sqlite_master WHERE type='table' AND name='agent_runs'",
            )
            .length,
        0,
        reason: '前提：版本号已是当前版本，但表还没建',
      );
    } finally {
      raw.dispose();
    }

    final db = AppDatabase.forTesting(NativeDatabase(file));
    // 没有自愈的话，这一次读会抛 no such table。
    await expectOldDataIntact(db);
    for (final table in agentTables) {
      expect(await db.columnsOf(table), isNotEmpty, reason: '$table 应该被自愈建出来');
    }
    expect(await indexNamesOf(db), containsAll(expectedIndexes));

    final store = AgentRunStore(db);
    await store.saveRun(newRun());
    expect(await store.loadRun('run-v45'), isNotNull);
    await db.close();

    expect(userVersionOf(file.path), 48, reason: '已经是最新版本（v48），不再回退');
  });

  test('全新库（onCreate）：schemaVersion 是最新版本，五表与索引都在', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    expect(db.schemaVersion, 48);
    // 触发 onCreate。
    await db.select(db.agentExperiences).get();
    for (final table in agentTables) {
      expect(await db.columnsOf(table), isNotEmpty);
    }
    expect(await indexNamesOf(db), containsAll(expectedIndexes));
    await db.close();
  });

  test('agent_experiences 的 reward / provenance 可写可读（P1 表先留位）', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.agentExperiences).insert(
          AgentExperiencesCompanion.insert(
            id: 'exp-1',
            cluster: 'student/q15',
            stateKey: 'fp-1',
            action: 'tool:search:abc',
            reward: 1.0,
            provenanceRunId: const Value('run-v45'),
            createdAt: 1700000000000,
          ),
        );
    final row = (await db.select(db.agentExperiences).get()).single;
    expect(row.reward, 1.0);
    expect(row.provenanceRunId, 'run-v45');
    expect(row.version, 1);
    expect(row.revokedAt, isNull);
    await db.close();
  });
}

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/material_intake_repository.dart';
import 'package:furnace/domain/services/ingest/material_intake_plan.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v17 -> v18：线索边表 `knowledge_edges`（`docs/MINDNET_ROADMAP.md` §2-C ④，轮次六十八）。
///
/// 与 v17 那次同构：加的是**一张新表**，所以要锁两件事：
///
///  1. 真实 v17 文件升级后表能用（材料的连接真的落成线索边），而老数据一个不少；
///  2. 已经被盖成 v18、却没有这张表的文件靠 `beforeOpen` 自愈 —— Drift 在
///     `user_version` 等于当前版本时完全跳过 `onUpgrade`，那一刻没有自愈，
///     材料的连接会在第一次写时炸（v6/v7/v8/v10/v12/v13/v14/v17 踩过同一个坑）。
///
/// 「v17 文件」的造法：v18 的 schema 只比 v17 多这一张表，所以先用当前 schema 建库、
/// 写一个先前的知识点，再把 `knowledge_edges` DROP 掉、把 `user_version` 压回 17。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig18_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<File> buildV17Db({
    required int userVersion,
    required String name,
  }) async {
    final dbFile = File('${tempDir.path}/$name.db');

    final fresh = AppDatabase.forTesting(NativeDatabase(dbFile));
    await AnkiRepository(fresh)
        .createKnowledgePoint(title: '先前的点', content: 'v17 时代就有');
    await fresh.close();

    final raw = sql.sqlite3.open(dbFile.path);
    raw.execute('DROP TABLE knowledge_edges');
    raw.execute('PRAGMA user_version = $userVersion');
    raw.dispose();
    return dbFile;
  }

  /// 一条知识点 + 一条连着它的线索边（节点 id 由材料的确定性 id 决定）。
  MaterialIntakePlan planOf() => const MaterialIntakePlan(
        batchId: 'b-mig18',
        topic: 'travel',
        proposals: <MaterialIntakeProposal>[
          MaterialIntakeProposal(
            id: 'kp:en::s::abc',
            kind: MaterialIntakeKind.knowledgePoint,
            title: 'I relied on him.',
            nodeId: 'en::s::abc',
            body: '原文：I relied on him.',
            why: '材料里标了「句」',
            exists: false,
            evidence: MaterialIntakeEvidence(
              source: '词汇书',
              page: 12,
              region: '第 12 页',
              batchId: 'b-mig18',
            ),
          ),
          MaterialIntakeProposal(
            id: 'kp:en::w::rely-on',
            kind: MaterialIntakeKind.knowledgePoint,
            title: 'rely on',
            nodeId: 'en::w::rely-on',
            body: '释义：依靠',
            why: '材料里标了「词」',
            exists: false,
            evidence: MaterialIntakeEvidence(
              source: '词汇书',
              page: 12,
              region: '第 12 页',
              batchId: 'b-mig18',
            ),
          ),
          MaterialIntakeProposal(
            id: 'edge:e_1',
            kind: MaterialIntakeKind.connection,
            title: 'rely on → I relied on him.',
            from: 'en::w::rely-on',
            to: 'en::s::abc',
            ls: 0.6,
            origin: 'produce',
            body: '',
            why: '用它造出这句话（词 → 句）',
            exists: false,
            evidence: MaterialIntakeEvidence(
              source: '词汇书',
              page: 12,
              region: '边：produce',
              batchId: 'b-mig18',
            ),
          ),
        ],
        skipped: <MaterialIntakeSkip>[],
      );

  Future<void> expectUsable(AppDatabase db) async {
    final repository = MaterialIntakeRepository(db);
    await repository.record(
      planOf(),
      summaryText: '批次 b-mig18：3 条 → 2 节点 / 1 边',
      analyzedAt: DateTime.fromMillisecondsSinceEpoch(1789000000000),
    );
    expect(await repository.pendingProposals('b-mig18'), hasLength(3));

    final outcome = await repository.apply(batchId: 'b-mig18');
    expect(outcome.created, hasLength(2));
    expect(outcome.createdEdges, hasLength(1), reason: '线索边真的落进新表');
    expect(outcome.deferred, isEmpty);

    final edges = await db.select(db.knowledgeEdges).get();
    expect(edges.single.id, 'e_1');
    expect(edges.single.fromId, 'en::w::rely-on');
    expect(edges.single.toId, 'en::s::abc');
    expect(edges.single.lsCalibrated, isFalse);

    // 老数据也在：先前的点 + 材料建出来的两个。
    final points = await db.select(db.knowledgePoints).get();
    expect(points, hasLength(3));
  }

  test('真实 v17 文件升级后新表可用，老知识点还在', () async {
    final file = await buildV17Db(userVersion: 17, name: 'v17');
    final db = AppDatabase.forTesting(NativeDatabase(file));

    await expectUsable(db);
    await db.close();
  });

  test('被盖成 v18 却没有这张表的文件，靠自愈补上', () async {
    final file = await buildV17Db(userVersion: 18, name: 'v18');
    final db = AppDatabase.forTesting(NativeDatabase(file));

    await expectUsable(db);
    await db.close();
  });
}

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/material_intake_repository.dart';
import 'package:furnace/domain/services/ingest/material_intake_plan.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v18 -> v19：`material_intake_proposals.already_existed`（轮次七十五）。
///
/// 与 v18 那次不同，这次加的是**一列**而不是一张表，所以要锁的还是那两件事：
///
///  1. 真实 v18 文件升级后那一列能用（"本来就有的"这句历史真的存得下来），
///     而老数据一个不少；
///  2. 已经被盖成 v19、却没有这一列的文件靠 `beforeOpen` 自愈 —— Drift 在
///     `user_version` 等于当前版本时完全跳过 `onUpgrade`，那一刻没有自愈，
///     历史的第一次读就会炸（v6/v7/v8/v9/v10/v11/v12/v13/v14/v17/v18 踩过同一个坑）。
///
/// 「v18 文件」的造法：v19 的 schema 只比 v18 多这一列，所以先用当前 schema 建库、
/// 写一个先前的知识点，再把 `already_existed` DROP 掉、把 `user_version` 压回 18。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig19_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<File> buildV18Db({
    required int userVersion,
    required String name,
  }) async {
    final dbFile = File('${tempDir.path}/$name.db');

    final fresh = AppDatabase.forTesting(NativeDatabase(dbFile));
    final anki = AnkiRepository(fresh);
    await anki.createKnowledgePoint(title: '先前的点', content: 'v18 时代就有');
    // 这一条带 external_id：升级之后它就该被认成"本来就有的"。
    await anki.createKnowledgePoint(
      title: 'rely on（先有的）',
      content: 'v18 时代就有',
      externalId: 'en::w::rely-on',
    );
    await fresh.close();

    final raw = sql.sqlite3.open(dbFile.path);
    raw.execute(
      'ALTER TABLE material_intake_proposals DROP COLUMN already_existed',
    );
    raw.execute('PRAGMA user_version = $userVersion');
    raw.dispose();
    return dbFile;
  }

  /// 一个知识点 + 一条连着它的线索边，外加一条"本来就有的"点。
  MaterialIntakePlan planOf() => const MaterialIntakePlan(
        batchId: 'b-mig19',
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
              batchId: 'b-mig19',
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
              batchId: 'b-mig19',
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
              batchId: 'b-mig19',
            ),
          ),
        ],
        skipped: <MaterialIntakeSkip>[],
      );

  Future<void> expectUsable(AppDatabase db) async {
    final repository = MaterialIntakeRepository(db);
    await repository.record(
      planOf(),
      summaryText: '批次 b-mig19：3 条 → 2 节点 / 1 边',
      analyzedAt: DateTime.fromMillisecondsSinceEpoch(1789000000000),
    );
    expect(await repository.pendingProposals('b-mig19'), hasLength(3));

    final outcome = await repository.apply(batchId: 'b-mig19');
    expect(outcome.created, hasLength(1));
    expect(outcome.existing, <String>['kp:en::w::rely-on']);
    expect(outcome.createdEdges, hasLength(1), reason: '两端都在，边落得下来');
    expect(outcome.deferred, isEmpty);

    // 新列真的存住了这句历史：一条是本来就有的，两条是这次新建的。
    final applied = await repository.appliedProposals('b-mig19');
    expect(applied, hasLength(3));
    final byId = <String, bool>{
      for (final row in applied) row.proposal.id: row.alreadyExisted,
    };
    expect(byId['kp:en::w::rely-on'], isTrue);
    expect(byId['kp:en::s::abc'], isFalse);
    expect(byId['edge:e_1'], isFalse);

    // 老数据也在：先前的两个点 + 这次新建的一个。
    final points = await db.select(db.knowledgePoints).get();
    expect(points, hasLength(3));
  }

  test('真实 v18 文件升级后新列可用，老知识点还在', () async {
    final file = await buildV18Db(userVersion: 18, name: 'v18');
    final db = AppDatabase.forTesting(NativeDatabase(file));

    await expectUsable(db);
    await db.close();
  });

  test('被盖成 v19 却没有这一列的文件，靠自愈补上', () async {
    final file = await buildV18Db(userVersion: 19, name: 'v19');
    final db = AppDatabase.forTesting(NativeDatabase(file));

    await expectUsable(db);
    await db.close();
  });
}

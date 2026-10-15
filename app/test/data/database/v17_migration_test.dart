import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/material_intake_repository.dart';
import 'package:furnace/domain/services/ingest/material_intake_plan.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v16 -> v17：材料摄取的两张表（`material_intake_batches` /
/// `material_intake_proposals`，`docs/MINDNET_ROADMAP.md` §2-C ①）。
///
/// 这一条与"加一列"的迁移不同，它加的是**两张新表**，所以要锁两件事：
///
///  1. 真实 v16 文件升级后两张表能用（记一批提案、确认、知识点落库都在），而老数据
///     （这里用 `knowledge_points` 里有先前的点代表）一个不少；
///  2. 已经被盖成 v17、却没有这两张表的文件靠 `beforeOpen` 自愈 —— Drift 在
///     `user_version` 等于当前版本时完全跳过 `onUpgrade`，那一刻没有自愈，材料摄取的
///     落库会在第一次写时炸（v6/v7/v8/v10/v12/v13/v14 那批踩过同一个坑）。
///
/// 「v16 文件」的造法：v17 的 schema 只比 v16 多这两张表，所以先用当前 schema 建库、写一个
/// 先前的知识点，再把两张表 DROP 掉、把 `user_version` 压回 16。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig17_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<File> buildV16Db({
    required int userVersion,
    required String name,
  }) async {
    final dbFile = File('${tempDir.path}/$name.db');

    final fresh = AppDatabase.forTesting(NativeDatabase(dbFile));
    await AnkiRepository(fresh)
        .createKnowledgePoint(title: '先前的点', content: 'v16 时代就有');
    await fresh.close();

    final raw = sql.sqlite3.open(dbFile.path);
    raw.execute('DROP TABLE material_intake_proposals');
    raw.execute('DROP TABLE material_intake_batches');
    raw.execute('PRAGMA user_version = $userVersion');
    raw.dispose();
    return dbFile;
  }

  MaterialIntakePlan planOf() => const MaterialIntakePlan(
        batchId: 'b-mig',
        topic: 'travel',
        proposals: <MaterialIntakeProposal>[
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
              batchId: 'b-mig',
            ),
          ),
        ],
        skipped: <MaterialIntakeSkip>[],
      );

  Future<void> expectUsable(AppDatabase db) async {
    final repository = MaterialIntakeRepository(db);
    await repository.record(
      planOf(),
      summaryText: '批次 b-mig：1 条 → 1 节点',
      analyzedAt: DateTime.fromMillisecondsSinceEpoch(1789000000000),
    );
    expect((await repository.pendingProposals('b-mig')), hasLength(1));

    final outcome = await repository.apply(batchId: 'b-mig');
    expect(outcome.created, hasLength(1));

    // 老数据也在：先前的点 + 材料建出来的。
    final points = await db.select(db.knowledgePoints).get();
    expect(points, hasLength(2));
  }

  test('真实 v16 文件升级后两张新表可用，老知识点还在', () async {
    final file = await buildV16Db(userVersion: 16, name: 'v16');
    final db = AppDatabase.forTesting(NativeDatabase(file));

    await expectUsable(db);
    await db.close();
  });

  test('被盖成 v17 却没有这两张表的文件，靠自愈补上', () async {
    final file = await buildV16Db(userVersion: 17, name: 'v17');
    final db = AppDatabase.forTesting(NativeDatabase(file));

    await expectUsable(db);
    await db.close();
  });
}

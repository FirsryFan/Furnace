import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/material_intake_repository.dart';
import 'package:furnace/domain/services/ingest/material_intake_plan.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v22 -> v23：`material_intake_batches.detail_text`（轮次一百）。
///
/// 加的是**一列**，要锁的还是那两件事（与 v19/v21/v22 同一种失败模式）：
///
///  1. 真实 v22 文件升级后那一列能用（"这一跑做了什么"真的存得下来），老批次一个不少；
///  2. 已经被盖成 v23、却没有这一列的文件靠 `beforeOpen` 自愈 —— Drift 在 `user_version`
///     等于当前版本时完全跳过 `onUpgrade`，那一刻没有自愈，读批次列表就会炸。
///
/// 「v22 文件」的造法：先用当前 schema 建库、记一批，再把 `detail_text` DROP 掉、
/// 把 `user_version` 压回 22。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig23_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  MaterialIntakePlan planOf() => const MaterialIntakePlan(
        batchId: 'b-mig23',
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
              batchId: 'b-mig23',
            ),
          ),
        ],
        skipped: <MaterialIntakeSkip>[],
      );

  Future<File> buildV22Db({
    required int userVersion,
    required String name,
  }) async {
    final dbFile = File('${tempDir.path}/$name.db');
    final fresh = AppDatabase.forTesting(NativeDatabase(dbFile));
    await MaterialIntakeRepository(fresh).record(
      planOf(),
      summaryText: 'v22 时代记下的一批',
      analyzedAt: DateTime.fromMillisecondsSinceEpoch(1789000000000),
    );
    await fresh.close();

    final raw = sql.sqlite3.open(dbFile.path);
    raw.execute('ALTER TABLE material_intake_batches DROP COLUMN detail_text');
    raw.execute('PRAGMA user_version = $userVersion');
    raw.dispose();
    return dbFile;
  }

  test('真实 v22 文件升级后那一列能用，老批次还在', () async {
    final file = await buildV22Db(userVersion: 22, name: 'v22');
    final db = AppDatabase.forTesting(NativeDatabase(file));
    final repository = MaterialIntakeRepository(db);

    final old = (await repository.batch('b-mig23'))!;
    expect(old.summaryText, contains('v22 时代'));
    expect(old.detailText, isNull, reason: 'v22 时代没有这一列，读出来就是没有');

    await repository.editPointProposal(
      batchId: 'b-mig23',
      proposalId: 'kp:en::w::rely-on',
      body: '升级之后补的正文',
    );
    expect(
      (await repository.pendingProposals('b-mig23')).single.body,
      '升级之后补的正文',
    );

    // 新列真的存得住"这一跑做了什么"。
    await repository.record(
      planOf(),
      summaryText: '升级之后再记一次',
      analyzedAt: DateTime.fromMillisecondsSinceEpoch(1789000009999),
      detailText: '1 [knowledge] 新增节点 en::w::rely-on',
    );
    expect(
      (await repository.batch('b-mig23'))!.detailText,
      '1 [knowledge] 新增节点 en::w::rely-on',
    );
    await db.close();
  });

  test('被盖成 v23 却没有这一列的文件，靠自愈补上', () async {
    final file = await buildV22Db(userVersion: 23, name: 'fake23');
    final db = AppDatabase.forTesting(NativeDatabase(file));
    final repository = MaterialIntakeRepository(db);

    // 没有自愈的话，第一次读批次就会因为"no such column: detail_text"炸掉。
    final old = (await repository.batch('b-mig23'))!;
    expect(old.detailText, isNull);

    await repository.record(
      planOf(),
      summaryText: '自愈之后记的',
      analyzedAt: DateTime.fromMillisecondsSinceEpoch(1789000019999),
      detailText: '1 [knowledge] 自愈补上的那一列',
    );
    expect(
      (await repository.batch('b-mig23'))!.detailText,
      '1 [knowledge] 自愈补上的那一列',
    );
    await db.close();
  });
}

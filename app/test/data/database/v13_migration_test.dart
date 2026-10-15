import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/handwriting_proposal_repository.dart';
import 'package:furnace/domain/services/intake/handwriting_proposals.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v12 -> v13：拍照整理提案的两张表（`docs/HANDWRITING_INTAKE_DESIGN.md` §4）。
///
/// 迁移本身只是"建两张空表"，所以两条断言锁的是两件容易坏的事：
///
///  1. 真实 v12 文件升级后**老数据一行不少**，两张新表立刻能写能读
///     （一条 run + 三类产物的确认状态）；
///  2. 已经被盖成 v13、却没有这两张表的文件靠 `beforeOpen` 自愈——Drift 在
///     `user_version` 等于当前版本时完全跳过 `onUpgrade`，那一刻没有自愈就会
///     让每次"待确认队列"读取都报 "no such table"（看起来像"我从来没整理过"）。
///
/// 「v12 文件」的造法：v13 的 schema 只比 v12 多这两张表，所以先用当前
/// schema 建库、写入 v12 时代就有的数据，再把这两张表 DROP 掉、把
/// `user_version` 压回 12——得到的文件与真实 v12 文件结构一致。
void main() {
  late Directory tempDir;

  const sourceRef = 'handwriting_intake/hw-1/page.png';

  HandwritingProposalSet proposals() => const HandwritingProposalSet(
        sourceRef: sourceRef,
        proposals: <HandwritingProposal>[
          HandwritingProposal(
            id: 'tag-0',
            kind: HandwritingProposalKind.tag,
            titleZh: '动量守恒',
            fields: <String, String>{'parent_path': '文化课/物理'},
          ),
          HandwritingProposal(
            id: 'knowledge_point-1',
            kind: HandwritingProposalKind.knowledgePoint,
            titleZh: '动量守恒的条件',
            fields: <String, String>{'content': '合外力为零'},
          ),
        ],
      );

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig13_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 造一个 v12 形状的文件。[userVersion] 用来复现"版本号跑在表前面"。
  Future<File> buildV12Db({
    required int userVersion,
    required String name,
  }) async {
    final dbFile = File('${tempDir.path}/$name.db');

    final fresh = AppDatabase.forTesting(NativeDatabase(dbFile));
    await fresh.customStatement(
      'INSERT INTO knowledge_points (id, title, content, created_at, updated_at) '
      "VALUES ('kp1', '动量守恒', '合外力为零', 1700000000000, 1700000000000)",
    );
    await fresh.into(fresh.attachments).insert(
          AttachmentsCompanion.insert(
            id: 'att1',
            ownerType: 'handwriting_intake',
            ownerId: '',
            relPath: sourceRef,
            createdAt: 1700000000000,
          ),
        );
    await fresh.close();

    final raw = sql.sqlite3.open(dbFile.path);
    raw.execute('DROP TABLE handwriting_proposals');
    raw.execute('DROP TABLE handwriting_intake_runs');
    raw.execute('PRAGMA user_version = $userVersion');
    raw.dispose();
    return dbFile;
  }

  test('真实 v12 文件升级后两张新表可用，老数据一行不少', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase(await buildV12Db(userVersion: 12, name: 'v12')),
    );
    final repository = HandwritingProposalRepository(db);

    expect(await db.select(db.knowledgePoints).get(), hasLength(1));
    expect((await db.select(db.attachments).get()).single.relPath, sourceRef);

    final analyzedAt = DateTime(2026, 10, 16, 9, 30);
    await repository.saveRun(
      set: proposals(),
      analyzedAt: analyzedAt,
      rawReply: '模型原话',
    );
    var run = (await repository.runs()).single;
    expect(run.analyzedAt, analyzedAt);
    expect(run.rawReply, '模型原话');
    expect(run.proposalSet.proposals, hasLength(2));

    await repository.markApplied(
      sourceRef: sourceRef,
      proposalId: 'tag-0',
      appliedAt: DateTime(2026, 10, 16, 9, 35),
    );
    run = (await repository.runs()).single;
    expect(run.appliedProposalIds, <String>{'tag-0'});

    await db.close();
  });

  test('被盖成 v13 却没有这两张表的文件，靠自愈补上并能写进去', () async {
    // user_version 已经是 13，Drift 跳过 onUpgrade，表只能由 beforeOpen 补。
    final db = AppDatabase.forTesting(
      NativeDatabase(await buildV12Db(userVersion: 13, name: 'v13')),
    );
    final repository = HandwritingProposalRepository(db);

    await repository.saveRun(
      set: proposals(),
      analyzedAt: DateTime(2026, 10, 16, 10),
    );
    expect((await repository.runs()).single.proposals, hasLength(2));
    expect(await db.select(db.knowledgePoints).get(), hasLength(1));

    await db.close();
  });
}

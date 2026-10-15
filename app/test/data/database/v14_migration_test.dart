import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v13 -> v14：曝光日志表 `exposure_logs`（`docs/MINDNET_ROADMAP.md` §2）。
///
/// 迁移本身只是"建一张空表"，所以两条断言锁的是两件容易坏的事：
///
///  1. 真实 v13 文件升级后**老数据一行不少**，新表立刻能写能读（一条曝光
///     行：`source` / `exposed_at` / `created_at` 都在，且**没有** `review_logs`
///     行被顺手写出来）；
///  2. 已经被盖成 v14、却没有这张表的文件靠 `beforeOpen` 自愈——Drift 在
///     `user_version` 等于当前版本时完全跳过 `onUpgrade`，那一刻没有自愈就会
///     让每次"读过没测"写入都报 "no such table"。
///
/// 「v13 文件」的造法：v14 的 schema 只比 v13 多这一张表，所以先用当前 schema
/// 建库、写入 v13 时代就有的数据（知识点 + 单元卡状态），再把这张表 DROP 掉、
/// 把 `user_version` 压回 13——得到的文件与真实 v13 文件结构一致。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig14_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 造一个 v13 形状的文件。[userVersion] 用来复现"版本号跑在表前面"。
  Future<({File file, String cardStateId})> buildV13Db({
    required int userVersion,
    required String name,
  }) async {
    final dbFile = File('${tempDir.path}/$name.db');

    final fresh = AppDatabase.forTesting(NativeDatabase(dbFile));
    final repository = AnkiRepository(fresh);
    final point = await repository.createKnowledgePoint(
      title: '动量守恒',
      content: '合外力为零',
    );
    final state = await repository.getOrCreateUnitCardState(point.id, 'unit-1');
    await fresh.close();

    final raw = sql.sqlite3.open(dbFile.path);
    raw.execute('DROP TABLE exposure_logs');
    raw.execute('PRAGMA user_version = $userVersion');
    raw.dispose();
    return (file: dbFile, cardStateId: state.id);
  }

  test('真实 v13 文件升级后新表可用，老数据一行不少', () async {
    final built = await buildV13Db(userVersion: 13, name: 'v13');
    final db = AppDatabase.forTesting(NativeDatabase(built.file));
    final repository = AnkiRepository(db);

    // 老数据：知识点与单元卡状态都还在。
    expect(await db.select(db.knowledgePoints).get(), hasLength(1));
    expect(await db.select(db.cardStates).get(), hasLength(1));

    const exposedAt = 1700000000000;
    await repository.addExposureLog(
      cardStateId: built.cardStateId,
      exposedAt: exposedAt,
    );

    final rows = await db.select(db.exposureLogs).get();
    expect(rows, hasLength(1));
    expect(rows.single.cardStateId, built.cardStateId);
    expect(rows.single.source, kExposureSourceAnswerReveal);
    expect(rows.single.exposedAt, exposedAt);
    expect(rows.single.createdAt, exposedAt);
    // 曝光不是一次测试：这条写入不产生复习记录。
    expect(await db.select(db.reviewLogs).get(), isEmpty);

    await db.close();
  });

  test('被盖成 v14 却没有这张表的文件，靠自愈补上并能写进去', () async {
    // user_version 已经是 14，Drift 跳过 onUpgrade，表只能由 beforeOpen 补。
    final built = await buildV13Db(userVersion: 14, name: 'v14');
    final db = AppDatabase.forTesting(NativeDatabase(built.file));
    final repository = AnkiRepository(db);

    await repository.addExposureLog(
      cardStateId: built.cardStateId,
      exposedAt: 1700000000000,
    );

    expect(await db.select(db.exposureLogs).get(), hasLength(1));
    expect(await db.select(db.knowledgePoints).get(), hasLength(1));

    await db.close();
  });
}

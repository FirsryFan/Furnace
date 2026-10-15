import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/thread_rank_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v15 -> v16：`thread_rank_settings.cognitive_rank_enabled`（认知排序档位开关，
/// `docs/MINDNET_ROADMAP.md` §2-D）。
///
/// 与 v15 那条（加一个可空列）不同，这一列**非空并带默认 false**，所以两条断言锁的是
/// 两件容易坏的事：
///
///  1. 真实 v15 文件升级后老权重一个不变，新开关落成 false —— 迁移绝不能替用户打开一个
///     还没标定的排序档位；
///  2. 已经被盖成 v16、却没有这一列的文件靠 `beforeOpen` 自愈——Drift 在
///     `user_version` 等于当前版本时完全跳过 `onUpgrade`，那一刻没有自愈就会让每次读取
///     排序参数在 mapping 时抛错（v6/v7 那批列踩过同一个坑）。
///
/// 「v15 文件」的造法：v16 的 schema 只比 v15 多这一列，所以先用当前 schema 建库、写入
/// v15 时代就有的参数（权重 + 折叠/实际用时开关），把新开关先打开一次，再把这一列 DROP
/// 掉、把 `user_version` 压回 15——得到的文件与真实 v15 文件结构一致，且"列没了"是
/// 可验证的（升级后读到的 false 只可能来自列默认值）。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig16_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 造一个 v15 形状的文件。[userVersion] 用来复现"版本号跑在列前面"。
  Future<File> buildV15Db({
    required int userVersion,
    required String name,
  }) async {
    final dbFile = File('${tempDir.path}/$name.db');

    final fresh = AppDatabase.forTesting(NativeDatabase(dbFile));
    final repository = ThreadRankRepository(fresh);
    await repository.updateWeights(urgency: 0.7, goal: 0.11);
    await repository.setCognitiveRankEnabled(true);
    await fresh.close();

    final raw = sql.sqlite3.open(dbFile.path);
    raw.execute(
        'ALTER TABLE thread_rank_settings DROP COLUMN cognitive_rank_enabled');
    raw.execute('PRAGMA user_version = $userVersion');
    raw.dispose();
    return dbFile;
  }

  test('真实 v15 文件升级后老权重一个不变，新开关落成默认关', () async {
    final file = await buildV15Db(userVersion: 15, name: 'v15');
    final db = AppDatabase.forTesting(NativeDatabase(file));
    final repository = ThreadRankRepository(db);

    // 老参数：用户改过的权重还在，新开关读作"用户没选过"。
    final weights = await repository.getWeights();
    expect(weights.urgency, closeTo(0.7, 1e-9));
    expect(weights.goal, closeTo(0.11, 1e-9));
    expect(await repository.getCognitiveRankEnabled(), isFalse);

    // 用户打开之后才落值。
    await repository.setCognitiveRankEnabled(true);
    expect(await repository.getCognitiveRankEnabled(), isTrue);

    await db.close();
  });

  test('被盖成 v16 却没有这一列的文件，靠自愈补上并能写进去', () async {
    // user_version 已经是 16，Drift 跳过 onUpgrade，列只能由 beforeOpen 补。
    final file = await buildV15Db(userVersion: 16, name: 'v16');
    final db = AppDatabase.forTesting(NativeDatabase(file));
    final repository = ThreadRankRepository(db);

    expect(await repository.getCognitiveRankEnabled(), isFalse);
    await repository.setCognitiveRankEnabled(true);
    expect(await repository.getCognitiveRankEnabled(), isTrue);

    await db.close();
  });
}

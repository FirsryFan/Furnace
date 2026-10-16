import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/settings_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v21 -> v22：`local_settings.goal_beta`（机制面板上那个滑块 —— 目标机制的
/// 牵引强度 `context.goal.beta_goal`，`docs/MINDNET_ROADMAP.md` §3 第 8 行的
/// 第一个用户侧滑块）。
///
/// 迁移只是"加一个可空列"，所以两条断言锁的是两件容易坏的事（与 v21 那份同一个
/// 模板）：
///
///  1. 真实 v21 文件升级后**老设置一行不少**，新列落成 NULL（= 用户从没调过，
///     app 读作转录表里的出厂值 —— 迁移绝不能在用户没拖过时替他写 0.3，
///     那等于把今天的出厂值冻进每一台已有安装）；
///  2. 已经被盖成 v22、却没有这一列的文件靠 `beforeOpen` 自愈 —— Drift 在
///     `user_version` 等于当前版本时完全跳过 `onUpgrade`。
///
/// 「v21 文件」的造法：v22 的 schema 只比 v21 多这一列，所以先用当前 schema 建库、
/// 写入 v21 时代就有的设置（语言、那个开关），再把这一列 DROP 掉、把 `user_version`
/// 压回 21 —— 得到的文件与真实 v21 文件结构一致。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig22_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 造一个 v21 形状的文件。[userVersion] 用来复现"版本号跑在列前面"。
  Future<File> buildV21Db({
    required int userVersion,
    required String name,
  }) async {
    final dbFile = File('${tempDir.path}/$name.db');

    final fresh = AppDatabase.forTesting(NativeDatabase(dbFile));
    final repository = SettingsRepository(fresh);
    await repository.ensureSettings(language: 'zh');
    await fresh.close();

    final raw = sql.sqlite3.open(dbFile.path);
    raw.execute('ALTER TABLE local_settings DROP COLUMN goal_beta');
    raw.execute('PRAGMA user_version = $userVersion');
    raw.dispose();
    return dbFile;
  }

  test('真实 v21 文件升级后新列可用，老设置一行不少', () async {
    final file = await buildV21Db(userVersion: 21, name: 'v21');
    final db = AppDatabase.forTesting(NativeDatabase(file));
    final repository = SettingsRepository(db);

    // 老设置：语言、那个开关都还在，新列读作"用户没调过"。
    final settings = await repository.getSettings();
    expect(settings, isNotNull);
    expect(settings!.language, 'zh');
    expect(settings.goalMechanismEnabled, isNull);
    expect(settings.goalBeta, isNull);

    // 用户拖过之后才落值，写值和"回到出厂值"（写回 NULL）两个方向都要能用。
    await repository.updateGoalBeta(1.2);
    expect((await repository.getSettings())!.goalBeta, 1.2);
    await repository.updateGoalBeta(null);
    expect((await repository.getSettings())!.goalBeta, isNull);

    await db.close();
  });

  test('被盖成 v22 却没有这一列的文件，靠自愈补上并能写进去', () async {
    // user_version 已经是 22，Drift 跳过 onUpgrade，列只能由 beforeOpen 补。
    final file = await buildV21Db(userVersion: 22, name: 'v22');
    final db = AppDatabase.forTesting(NativeDatabase(file));
    final repository = SettingsRepository(db);

    expect((await repository.getSettings())!.goalBeta, isNull);
    await repository.updateGoalBeta(0.1);
    expect((await repository.getSettings())!.goalBeta, 0.1);

    await db.close();
  });
}

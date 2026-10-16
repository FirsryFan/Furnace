import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/settings_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v20 -> v21：`local_settings.goal_mechanism_enabled`（机制面板上"装不装目标
/// 机制"那个开关，`docs/MINDNET_ROADMAP.md` §3 第 8 行的第一个用户侧开关）。
///
/// 迁移只是"加一个可空列"，所以两条断言锁的是两件容易坏的事：
///
///  1. 真实 v20 文件升级后**老设置一行不少**，新列落成 NULL（= 用户从没选过，
///     app 读作出厂默认"装这个机制"——迁移绝不能在用户没选过时替他写 true，
///     那等于悄悄换掉他的引擎）；
///  2. 已经被盖成 v21、却没有这一列的文件靠 `beforeOpen` 自愈——Drift 在
///     `user_version` 等于当前版本时完全跳过 `onUpgrade`，那一刻没有自愈就会让
///     每次设置读取都在 mapping 时抛错（v6/v7/v15 那批列踩过同一个坑）。
///
/// 「v20 文件」的造法：v21 的 schema 只比 v20 多这一列，所以先用当前 schema
/// 建库、写入 v20 时代就有的设置（语言），再把这一列 DROP 掉、把 `user_version`
/// 压回 20——得到的文件与真实 v20 文件结构一致。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig21_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 造一个 v20 形状的文件。[userVersion] 用来复现"版本号跑在列前面"。
  Future<File> buildV20Db({
    required int userVersion,
    required String name,
  }) async {
    final dbFile = File('${tempDir.path}/$name.db');

    final fresh = AppDatabase.forTesting(NativeDatabase(dbFile));
    final repository = SettingsRepository(fresh);
    await repository.ensureSettings(language: 'zh');
    await fresh.close();

    final raw = sql.sqlite3.open(dbFile.path);
    raw.execute(
        'ALTER TABLE local_settings DROP COLUMN goal_mechanism_enabled');
    raw.execute('PRAGMA user_version = $userVersion');
    raw.dispose();
    return dbFile;
  }

  test('真实 v20 文件升级后新列可用，老设置一行不少', () async {
    final file = await buildV20Db(userVersion: 20, name: 'v20');
    final db = AppDatabase.forTesting(NativeDatabase(file));
    final repository = SettingsRepository(db);

    // 老设置：语言还在，且新列读作"用户没选过"。
    final settings = await repository.getSettings();
    expect(settings, isNotNull);
    expect(settings!.language, 'zh');
    expect(settings.goalMechanismEnabled, isNull);

    // 用户选了之后才落值，两个方向都要能写。
    await repository.updateGoalMechanismEnabled(false);
    expect((await repository.getSettings())!.goalMechanismEnabled, isFalse);
    await repository.updateGoalMechanismEnabled(true);
    expect((await repository.getSettings())!.goalMechanismEnabled, isTrue);

    await db.close();
  });

  test('被盖成 v21 却没有这一列的文件，靠自愈补上并能写进去', () async {
    // user_version 已经是 21，Drift 跳过 onUpgrade，列只能由 beforeOpen 补。
    final file = await buildV20Db(userVersion: 21, name: 'v21');
    final db = AppDatabase.forTesting(NativeDatabase(file));
    final repository = SettingsRepository(db);

    expect((await repository.getSettings())!.goalMechanismEnabled, isNull);
    await repository.updateGoalMechanismEnabled(false);
    expect((await repository.getSettings())!.goalMechanismEnabled, isFalse);

    await db.close();
  });
}

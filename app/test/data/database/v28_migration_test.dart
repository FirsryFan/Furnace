import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/settings_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v27 -> v28：复习提醒的开关与时刻（轮次一百三十五）。
///
/// 两列都可空，NULL 的语义是「用户没选过」：开关读作关闭、时刻读作出厂 20:00。
/// 迁移只补列、不回填——回填会把今天的 20:00 冻进每一台已有安装，以后改出厂
/// 时刻就达不到了（与 `goal_beta` / `capabilityActionOverlayJson` 同一个契约）。
///
/// 要锁的三件事：
///
///  1. 真实 v27 文件升级后，老设置行读作「关 + 没选过」，且升级后立刻能写能读；
///  2. 已经被盖成 v28、却没有这两列的文件靠 beforeOpen 自愈 —— Drift 在
///     user_version 等于当前版本时完全跳过 onUpgrade，那一刻没有自愈，读设置
///     就会因为 no such column 炸掉；
///  3. 新列能写能读：关库重开还是同一个值；0（午夜）与 NULL（没选过）必须区分。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig28_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 用当前 schema 建库、写一条 v27 世界的设置行（没有复习提醒两列的值），
  /// 然后把两列 DROP 掉、把 user_version 压回 [userVersion]。
  Future<File> buildDb({
    required int userVersion,
    required String name,
  }) async {
    final dbFile = File('\${tempDir.path}/$name.db');
    final fresh = AppDatabase.forTesting(NativeDatabase(dbFile));
    await fresh.into(fresh.localSettings).insert(
          LocalSettingsCompanion.insert(
            language: const Value('zh'),
            themeMode: const Value('light'),
            createdAt: 1700000000000,
            updatedAt: 1700000000000,
          ),
        );
    await fresh.close();

    final raw = sql.sqlite3.open(dbFile.path);
    raw.execute(
        'ALTER TABLE local_settings DROP COLUMN review_reminder_enabled');
    raw.execute(
        'ALTER TABLE local_settings DROP COLUMN review_reminder_minutes');
    raw.execute('PRAGMA user_version = $userVersion');
    raw.dispose();
    return dbFile;
  }

  test('真实 v27 文件升级后：老设置行读作「关 + 没选过」，且立刻能写能读', () async {
    final file = await buildDb(userVersion: 27, name: 'v27');
    var db = AppDatabase.forTesting(NativeDatabase(file));
    var repo = SettingsRepository(db);

    expect(await repo.getReviewReminderEnabled(), isFalse,
        reason: 'NULL 读作关闭：升级不替用户打开一个会弹系统通知的开关');
    expect(await repo.getReviewReminderMinutes(), isNull,
        reason: 'NULL 读作没选过，默认时刻由域层给，不写进库');

    await repo.updateReviewReminderEnabled(true);
    await repo.updateReviewReminderMinutes(1230);
    expect(await repo.getReviewReminderEnabled(), isTrue);
    expect(await repo.getReviewReminderMinutes(), 1230);
    await db.close();

    // 已经是 v28，重开不再迁移；值必须原样还在。
    db = AppDatabase.forTesting(NativeDatabase(file));
    repo = SettingsRepository(db);
    expect(await repo.getReviewReminderEnabled(), isTrue);
    expect(await repo.getReviewReminderMinutes(), 1230);
    await db.close();
  });

  test('被盖成 v28 却缺两列的文件，靠自愈补列', () async {
    final file = await buildDb(userVersion: 28, name: 'fake28');
    final db = AppDatabase.forTesting(NativeDatabase(file));
    final repo = SettingsRepository(db);

    // 没有自愈的话，这两次读取就会因为 no such column 抛异常。
    expect(await repo.getReviewReminderEnabled(), isFalse);
    expect(await repo.getReviewReminderMinutes(), isNull);

    await repo.updateReviewReminderMinutes(0);
    expect(await repo.getReviewReminderMinutes(), 0,
        reason: '0 是午夜，是用户能选的合法值，不能被当成 NULL');
    await repo.updateReviewReminderEnabled(true);
    expect(await repo.getReviewReminderEnabled(), isTrue);
    await db.close();
  });

  test('分钟越界抛 ArgumentError 且不写库；0 与 NULL 可区分', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = SettingsRepository(db);
    await repo.ensureSettings();

    expect(await repo.getReviewReminderMinutes(), isNull);
    await expectLater(
        repo.updateReviewReminderMinutes(-1), throwsArgumentError);
    await expectLater(
        repo.updateReviewReminderMinutes(1440), throwsArgumentError);
    expect(await repo.getReviewReminderMinutes(), isNull,
        reason: '越界的值既不能静默 clamp 也不能写进库');

    await repo.updateReviewReminderMinutes(0);
    expect(await repo.getReviewReminderMinutes(), 0);
    await repo.updateReviewReminderMinutes(1439);
    expect(await repo.getReviewReminderMinutes(), 1439);
    await db.close();
  });

  test('新库没有设置行时：关 + 没选过（不靠迁移，靠读侧兜底）', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = SettingsRepository(db);
    expect(await repo.getReviewReminderEnabled(), isFalse);
    expect(await repo.getReviewReminderMinutes(), isNull);
    await db.close();
  });
}

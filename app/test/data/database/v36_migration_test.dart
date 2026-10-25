import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/settings_repository.dart';
import 'package:furnace/data/repositories/time_template_repository.dart';
import 'package:furnace/domain/services/srs/review_retention.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v35 -> v36：两个用户可调的显示/排期偏好（轮次一百七十五）：
///
///  * `local_settings.review_retention` —— 目标记忆保持率（review_service 每次判分读）；
///  * `time_view_settings.hour_height` —— Time 日/周网格的自由行高。
///
/// 两列都可空、NULL 读作出厂值（0.85 / 按 minutesPerRow 旧公式推），迁移只补列、
/// 不回填——回填会把今天的出厂值冻进每一台已有安装，以后改默认值也回不去。
///
/// 要锁的四件事：
///
///  1. 真实 v35 文件升级后，两处读作「没设过」，且升级后立刻能写能读、重开还在；
///  2. 已经被盖成 v36、却缺这两列的文件靠 beforeOpen 自愈 —— Drift 在 user_version
///     等于当前版本时完全跳过 onUpgrade，那一刻没有自愈，读设置就会 no such column；
///  3. `clearHourHeight()` 写出真正的 NULL（`update(hourHeight: null)` 是「本次不改」）；
///  4. 仓储不校验保持率范围，越界值原样读回，夹取只在领域层 `normalizeReviewRetention`。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig36_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 用当前 schema 建库、各写一行设置（没有这两列的值），然后把列 DROP 掉、
  /// 把 user_version 压回 [userVersion]。
  Future<File> buildDb({
    required int userVersion,
    required String name,
  }) async {
    final dbFile = File('${tempDir.path}/$name.db');
    final fresh = AppDatabase.forTesting(NativeDatabase(dbFile));
    await fresh.into(fresh.localSettings).insert(
          LocalSettingsCompanion.insert(
            language: const Value('zh'),
            themeMode: const Value('light'),
            createdAt: 1700000000000,
            updatedAt: 1700000000000,
          ),
        );
    await fresh.into(fresh.timeViewSettings).insert(
          TimeViewSettingsCompanion.insert(createdAt: 1700000000000),
        );
    await fresh.close();

    final raw = sql.sqlite3.open(dbFile.path);
    raw.execute('ALTER TABLE local_settings DROP COLUMN review_retention');
    raw.execute('ALTER TABLE time_view_settings DROP COLUMN hour_height');
    raw.execute('PRAGMA user_version = $userVersion');
    raw.dispose();
    return dbFile;
  }

  test('真实 v35 文件升级后：两处读作「没设过」，且立刻能写能读、重开还在', () async {
    final file = await buildDb(userVersion: 35, name: 'v35');
    var db = AppDatabase.forTesting(NativeDatabase(file));
    var settings = SettingsRepository(db);
    var views = TimeViewRepository(db);

    expect(await settings.getReviewRetention(), isNull,
        reason: 'NULL = 没设过，迁移不回填出厂值');
    expect(normalizeReviewRetention(await settings.getReviewRetention()),
        kDefaultReviewRetention,
        reason: '领域层把 NULL 翻译成出厂 0.85');
    final before = await views.get();
    expect(before, isNotNull, reason: 'v35 世界已经有这一行，升级不应删它');
    expect(before!.hourHeight, isNull, reason: 'NULL = 没拖过，行高按旧公式推');

    await settings.updateReviewRetention(ReviewSpacing.shorter.retention);
    await views.update(hourHeight: 120);
    expect(await settings.getReviewRetention(), 0.9);
    expect((await views.get())!.hourHeight, 120);
    await db.close();

    // 已经是 v36，重开不再迁移；两处选择必须原样还在。
    db = AppDatabase.forTesting(NativeDatabase(file));
    settings = SettingsRepository(db);
    views = TimeViewRepository(db);
    expect(await settings.getReviewRetention(), 0.9);
    expect((await views.get())!.hourHeight, 120);
    await db.close();
  });

  test('被盖成 v36 却缺这两列的文件，靠自愈补列', () async {
    final file = await buildDb(userVersion: 36, name: 'fake36');
    final db = AppDatabase.forTesting(NativeDatabase(file));
    final settings = SettingsRepository(db);
    final views = TimeViewRepository(db);

    // 没有自愈的话，这两次读取/写入就会因为 no such column 抛异常。
    expect(await settings.getReviewRetention(), isNull);
    expect((await views.get())!.hourHeight, isNull);
    await settings.updateReviewRetention(0.8);
    await views.update(hourHeight: 66);
    expect(await settings.getReviewRetention(), 0.8);
    expect((await views.get())!.hourHeight, 66);
    await db.close();
  });

  test('clearHourHeight 写回真正的 NULL；越界保持率仓库不校验、领域层才夹', () async {
    final file = await buildDb(userVersion: 35, name: 'clear');
    final db = AppDatabase.forTesting(NativeDatabase(file));
    final settings = SettingsRepository(db);
    final views = TimeViewRepository(db);

    await views.update(hourHeight: 88.5);
    expect((await views.get())!.hourHeight, 88.5);
    await views.clearHourHeight();
    expect((await views.get())!.hourHeight, isNull,
        reason: 'update(hourHeight: null) 是「本次不改」，清除必须走 clearHourHeight');

    await settings.updateReviewRetention(0.99);
    expect(await settings.getReviewRetention(), 0.99,
        reason: '仓储原样写、原样读，不偷偷改用户的选择');
    expect(normalizeReviewRetention(0.99), kReviewRetentionMax,
        reason: '夹取发生在领域层');
    await settings.updateReviewRetention(null);
    expect(await settings.getReviewRetention(), isNull);
    await db.close();
  });
}

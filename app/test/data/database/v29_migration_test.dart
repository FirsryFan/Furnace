import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/settings_repository.dart';
import 'package:furnace/domain/services/tags/tag_tree_sort.dart';
import 'package:furnace/domain/services/tags/tag_tree_view.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v28 -> v29：标签树排序方式（轮次一百三十八）。
///
/// 一列可空文本：NULL 的语义是「用户没选过」，读作域层出厂值「字典序」；
/// 写侧只存 `TagTreeSortMode.code` 这类稳定编码，不存中文。迁移只补列、
/// 不回填——回填会把出厂档位冻成一次用户选择，以后改出厂排序就达不到了
/// （与 `goalBeta` / `reviewReminderMinutes` 同一个契约）。
///
/// 要锁的三件事：
///
///  1. 真实 v28 文件升级后，老设置行读作「没选过」，且升级后立刻能写能读；
///  2. 已经被盖成 v29、却没有这一列的文件靠 beforeOpen 自愈 —— Drift 在
///     user_version 等于当前版本时完全跳过 onUpgrade，那一刻没有自愈，读设置
///     就会因为 no such column 炸掉；
///  3. NULL / 空白串 / 未知编码三种写入口径：空白存成 NULL，未知编码不被拒，
///     读侧用 `tagTreeSortModeFromStorage` 一律降级成字典序。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig29_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 用当前 schema 建库、写一条 v28 世界的设置行（没有排序方式这一列的值），
  /// 然后把列 DROP 掉、把 user_version 压回 [userVersion]。
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
    await fresh.close();

    final raw = sql.sqlite3.open(dbFile.path);
    raw.execute('ALTER TABLE local_settings DROP COLUMN tag_tree_sort_mode');
    raw.execute('PRAGMA user_version = $userVersion');
    raw.dispose();
    return dbFile;
  }

  test('真实 v28 文件升级后：老设置行读作「没选过」，且立刻能写能读', () async {
    final file = await buildDb(userVersion: 28, name: 'v28');
    var db = AppDatabase.forTesting(NativeDatabase(file));
    var repo = SettingsRepository(db);

    expect(await repo.getTagTreeSortMode(), isNull,
        reason: 'NULL 读作没选过，出厂字典序由域层给，不写进库');
    expect(tagTreeSortModeFromStorage(await repo.getTagTreeSortMode()),
        TagTreeSortMode.alphabetical);

    await repo.updateTagTreeSortMode(
        tagTreeSortModeToStorage(TagTreeSortMode.byObjectCount));
    expect(await repo.getTagTreeSortMode(), 'object_count');
    expect(tagTreeSortModeFromStorage(await repo.getTagTreeSortMode()),
        TagTreeSortMode.byObjectCount);
    await db.close();

    // 已经是 v29，重开不再迁移；值必须原样还在。
    db = AppDatabase.forTesting(NativeDatabase(file));
    repo = SettingsRepository(db);
    expect(await repo.getTagTreeSortMode(), 'object_count');
    await db.close();
  });

  test('被盖成 v29 却缺这一列的文件，靠自愈补列', () async {
    final file = await buildDb(userVersion: 29, name: 'fake29');
    final db = AppDatabase.forTesting(NativeDatabase(file));
    final repo = SettingsRepository(db);

    // 没有自愈的话，这两次读取/写入就会因为 no such column 抛异常。
    expect(await repo.getTagTreeSortMode(), isNull);
    await repo.updateTagTreeSortMode('created_at');
    expect(await repo.getTagTreeSortMode(), 'created_at');
    await db.close();
  });

  test('空白串存成 NULL；未知编码不拒绝、读侧降级成字典序', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = SettingsRepository(db);
    await repo.ensureSettings();

    await repo.updateTagTreeSortMode(' object_count ');
    expect(await repo.getTagTreeSortMode(), 'object_count',
        reason: '两端空白要 trim，库里只存稳定编码');

    await repo.updateTagTreeSortMode('   ');
    expect(await repo.getTagTreeSortMode(), isNull,
        reason: '空白不是第四种状态，写 NULL 表示「没选过」');

    await repo.updateTagTreeSortMode('by_pinyin');
    expect(await repo.getTagTreeSortMode(), 'by_pinyin',
        reason: '仓库不替域层的合法集合做把关，未知编码原样保留');
    expect(tagTreeSortModeFromStorage(await repo.getTagTreeSortMode()),
        TagTreeSortMode.alphabetical,
        reason: '未来版本写的模式，这一版读不懂就退回出厂字典序，不炸');

    await repo.updateTagTreeSortMode(null);
    expect(await repo.getTagTreeSortMode(), isNull, reason: '传 null = 恢复出厂排序');
    await db.close();
  });

  test('新库没有设置行时读作没选过（不靠迁移，靠读侧兜底）', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = SettingsRepository(db);
    expect(await repo.getTagTreeSortMode(), isNull);
    await db.close();
  });
}

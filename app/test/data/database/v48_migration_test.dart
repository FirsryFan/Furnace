import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/settings_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v47 -> v48：标签树展开状态 `local_settings.tag_tree_expanded_ids`
/// （2026-11-17，用户要求标签页默认完全折叠、跨页面/跨重启记住上次状态）。
///
/// 五条独立可失败的断言：
///
///  1. 真实 v47 文件打开后升级到 v48：`tag_tree_expanded_ids` 列补上；老设置行
///     一行不少、其他字段一个不变。
///  2. 升级来的列是 NULL，迁移**不回填**：NULL 读作「用户没保存过」= 出厂
///     全折叠（应用层 `tagTreeExpandedIdsFromStorage` 负责翻译）。
///  3. 迁移可重复执行：连开两次库不抛错、数据不变、版本停在当前 schema。
///  4. 版本号被盖成 v48 但列没写的文件，由 `beforeOpen` 自愈补出来（Drift 在
///     版本已是当前值时跳过 onUpgrade —— 与 v24/v31/v37/v42/v45/v47 同一个坑）。
///  5. 全新库（onCreate）就是 v48：列在，且仓库可写可读。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig48_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 当前 schema 的库 + 一条带既有偏好的设置行 + 一个标签，然后把 v48 的列拆掉、
  /// `user_version` 压回 [userVersion] —— 就是一个 v47 安装升级前的文件。
  Future<File> buildPreV48Db({
    required String name,
    int userVersion = 47,
  }) async {
    final file = File('${tempDir.path}/$name.db');
    final fresh = AppDatabase.forTesting(NativeDatabase(file));
    final repo = SettingsRepository(fresh);
    await repo.ensureSettings(language: 'zh', themeMode: 'dark');
    await repo.updateTagTreeSortMode('object_count');
    await fresh.into(fresh.tags).insert(
          TagsCompanion.insert(
            id: 'tag-old',
            name: '物理',
            createdAt: 1700000000000,
            updatedAt: 1700000000000,
          ),
        );
    await fresh.close();

    final raw = sql.sqlite3.open(file.path);
    try {
      raw.execute(
          'ALTER TABLE local_settings DROP COLUMN tag_tree_expanded_ids');
      raw.execute('PRAGMA user_version = $userVersion');
    } finally {
      raw.dispose();
    }
    return file;
  }

  int userVersionOf(String path) {
    final raw = sql.sqlite3.open(path);
    try {
      return raw.select('PRAGMA user_version').single['user_version'] as int;
    } finally {
      raw.dispose();
    }
  }

  Future<void> expectV48Structure(AppDatabase db) async {
    expect(
      await db.columnsOf('local_settings'),
      contains('tag_tree_expanded_ids'),
    );
  }

  Future<void> expectOldDataIntact(AppDatabase db) async {
    final rows = await db.select(db.localSettings).get();
    expect(rows, hasLength(1));
    final row = rows.single;
    expect(row.id, 1);
    expect(row.language, 'zh');
    expect(row.themeMode, 'dark');
    expect(row.tagTreeSortMode, 'object_count');
    // 迁移不回填：老行读到的是 NULL = 用户没保存过展开状态。
    expect(row.tagTreeExpandedIds, isNull);
    expect((await db.select(db.tags).get()).map((tag) => tag.id),
        <String>['tag-old']);
  }

  test('v47 文件升级到 v48：新列在，老设置行与标签一行不少', () async {
    final file = await buildPreV48Db(name: 'v47_upgrade');
    expect(userVersionOf(file.path), 47);

    final db = AppDatabase.forTesting(NativeDatabase(file));
    await expectV48Structure(db);
    await expectOldDataIntact(db);

    // 新列可经仓库写入并读回（升级后的库不是只读壳）。
    final repo = SettingsRepository(db);
    await repo.updateTagTreeExpandedIds('["tag-old"]');
    expect(await repo.getTagTreeExpandedIds(), '["tag-old"]');
    await db.close();

    expect(userVersionOf(file.path), 48);
  });

  test('迁移可重复执行：连开两次不抛错、数据不变、版本停在 48', () async {
    final file = await buildPreV48Db(name: 'twice');

    var db = AppDatabase.forTesting(NativeDatabase(file));
    await expectV48Structure(db);
    await expectOldDataIntact(db);
    await db.close();
    expect(userVersionOf(file.path), 48);

    // 第二次打开：onUpgrade 不再跑，只剩 beforeOpen 的空转探测。
    db = AppDatabase.forTesting(NativeDatabase(file));
    await expectV48Structure(db);
    await expectOldDataIntact(db);
    await db.close();
    expect(userVersionOf(file.path), 48);
  });

  test('版本号盖成 v48 但列缺失的文件由 beforeOpen 自愈', () async {
    final file = await buildPreV48Db(name: 'fake48', userVersion: 48);
    expect(userVersionOf(file.path), 48);

    // 没有自愈的话，读设置行会抛 no such column。
    final db = AppDatabase.forTesting(NativeDatabase(file));
    await expectV48Structure(db);
    await expectOldDataIntact(db);
    await db.close();
    expect(userVersionOf(file.path), 48, reason: '已经是最新版本，不再迁移');
  });

  test('全新库（onCreate）就是 v48：列在，且默认读作没保存过', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    expect(db.schemaVersion, 48);
    await expectV48Structure(db);
    final repo = SettingsRepository(db);
    expect(await repo.getTagTreeExpandedIds(), isNull,
        reason: 'NULL = 用户没保存过 = 出厂全折叠');
    await db.close();
  });
}

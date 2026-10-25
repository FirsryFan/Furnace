import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/settings_repository.dart';
import 'package:furnace/domain/services/cognitive/user_persona.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v34 -> v35：用户自我描述 `local_settings.user_persona`（轮次一百七十二）。
///
/// 一列可空文本：NULL 的语义是「用户没写过」，应用层 `normalizeUserPersona`
/// 负责把空白归一成 NULL、把超长挡在写库之前。迁移只补列、不回填——回填会把
/// 当时还不可能存在的内容写成一条假的自我描述（与 `questionLibrarySortMode`
/// / `tagTreeSortMode` 同一个契约）。
///
/// 要锁的四件事：
///
///  1. 真实 v34 文件升级后，老设置行读作「没写过」，且升级后立刻能写能读；
///  2. 已经被盖成 v35、却没有这一列的文件靠 beforeOpen 自愈 —— Drift 在
///     user_version 等于当前版本时完全跳过 onUpgrade，那一刻没有自愈，读设置
///     就会因为 no such column 炸掉；
///  3. 空白串存成 NULL（"没写"只有一种表示），超长不被仓库截断（截断会悄悄
///     丢用户的话，长度限制由编辑页用 `kUserPersonaMaxChars` 挡）；
///  4. 空 persona 的提示块是空串 —— AI 系统提示必须字节不变。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig35_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 用当前 schema 建库、写一条 v34 世界的设置行（没有 persona 这一列的值），
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
    raw.execute('ALTER TABLE local_settings DROP COLUMN user_persona');
    raw.execute('PRAGMA user_version = $userVersion');
    raw.dispose();
    return dbFile;
  }

  test('真实 v34 文件升级后：老设置行读作「没写过」，且立刻能写能读', () async {
    final file = await buildDb(userVersion: 34, name: 'v34');
    var db = AppDatabase.forTesting(NativeDatabase(file));
    var repo = SettingsRepository(db);

    expect(await repo.getUserPersona(), isNull, reason: 'NULL 读作没写过，迁移不回填任何内容');
    expect(userPersonaPromptBlock(await repo.getUserPersona()), isEmpty);

    await repo.updateUserPersona('  我是高三学生，数学想冲 120。  ');
    expect(await repo.getUserPersona(), '我是高三学生，数学想冲 120。',
        reason: '仓库两端 trim');
    await db.close();

    // 已经是 v35，重开不再迁移；原话必须原样还在。
    db = AppDatabase.forTesting(NativeDatabase(file));
    repo = SettingsRepository(db);
    expect(await repo.getUserPersona(), '我是高三学生，数学想冲 120。');
    await db.close();
  });

  test('被盖成 v35 却缺这一列的文件，靠自愈补列', () async {
    final file = await buildDb(userVersion: 35, name: 'fake35');
    final db = AppDatabase.forTesting(NativeDatabase(file));
    final repo = SettingsRepository(db);

    // 没有自愈的话，这两次读取/写入就会因为 no such column 抛异常。
    expect(await repo.getUserPersona(), isNull);
    await repo.updateUserPersona('自愈之后能写');
    expect(await repo.getUserPersona(), '自愈之后能写');
    await db.close();
  });

  test('空白存成 NULL；超长原样保留不截断；null = 清除', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = SettingsRepository(db);
    await repo.ensureSettings();

    await repo.updateUserPersona('   ');
    expect(await repo.getUserPersona(), isNull, reason: '空白不是第二种"没写"，写 NULL');

    await repo.updateUserPersona('');
    expect(await repo.getUserPersona(), isNull);

    final long = List.filled(kUserPersonaMaxChars + 1, '字').join();
    await repo.updateUserPersona(long);
    expect((await repo.getUserPersona())!.length, kUserPersonaMaxChars + 1,
        reason: '截断会悄悄丢用户的话；长度由编辑页用 tooLong 挡');

    await repo.updateUserPersona(null);
    expect(await repo.getUserPersona(), isNull, reason: '传 null = 清除');
    await db.close();
  });

  test('新库没有设置行时读作没写过（不靠迁移，靠读侧兜底）', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = SettingsRepository(db);
    expect(await repo.getUserPersona(), isNull);
    await db.close();
  });
}

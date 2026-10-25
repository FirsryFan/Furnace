import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/settings_repository.dart';
import 'package:furnace/features/questions/application/question_library_sort.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v33 -> v34：题库列表排序偏好 `local_settings.question_library_sort_mode`
/// （轮次一百六十八）。
///
/// 一列可空文本：NULL 的语义是「用户没选过」，读作域层出厂档位「最新在前」
/// （`questionLibrarySortFromStorage`）；写侧只存 `newest` / `serial` /
/// `wrong_first` 这类稳定 encode，不存中文。迁移只补列、不回填——回填会把出厂
/// 档位冻成一次用户选择，以后改出厂排序就达不到了（与 `tagTreeSortMode` /
/// `reviewReminderMinutes` 同一个契约）。
///
/// 要锁的三件事：
///
///  1. 真实 v33 文件升级后，老设置行读作「没选过」，且升级后立刻能写能读；
///  2. 已经被盖成 v34、却没有这一列的文件靠 beforeOpen 自愈 —— Drift 在
///     user_version 等于当前版本时完全跳过 onUpgrade，那一刻没有自愈，读设置
///     就会因为 no such column 炸掉；
///  3. NULL / 空白串 / 未知编码三种写入口径：空白存成 NULL，未知编码不被拒，
///     读侧用 `questionLibrarySortFromStorage` 一律降级成「最新在前」。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig34_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 用当前 schema 建库、写一条 v33 世界的设置行（没有排序偏好这一列的值），
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
    raw.execute(
        'ALTER TABLE local_settings DROP COLUMN question_library_sort_mode');
    raw.execute('PRAGMA user_version = $userVersion');
    raw.dispose();
    return dbFile;
  }

  test('真实 v33 文件升级后：老设置行读作「没选过」，且立刻能写能读', () async {
    final file = await buildDb(userVersion: 33, name: 'v33');
    var db = AppDatabase.forTesting(NativeDatabase(file));
    var repo = SettingsRepository(db);

    expect(await repo.getQuestionLibrarySortMode(), isNull,
        reason: 'NULL 读作没选过，出厂「最新」由域层给，不写进库');
    expect(
        questionLibrarySortFromStorage(await repo.getQuestionLibrarySortMode()),
        QuestionLibrarySort.newest);

    await repo.updateQuestionLibrarySortMode(
        questionLibrarySortCode(QuestionLibrarySort.serial));
    expect(await repo.getQuestionLibrarySortMode(), 'serial');
    expect(
        questionLibrarySortFromStorage(await repo.getQuestionLibrarySortMode()),
        QuestionLibrarySort.serial);
    await db.close();

    // 已经是 v34，重开不再迁移；值必须原样还在。
    db = AppDatabase.forTesting(NativeDatabase(file));
    repo = SettingsRepository(db);
    expect(await repo.getQuestionLibrarySortMode(), 'serial');
    await db.close();
  });

  test('被盖成 v34 却缺这一列的文件，靠自愈补列', () async {
    final file = await buildDb(userVersion: 34, name: 'fake34');
    final db = AppDatabase.forTesting(NativeDatabase(file));
    final repo = SettingsRepository(db);

    // 没有自愈的话，这两次读取/写入就会因为 no such column 抛异常。
    expect(await repo.getQuestionLibrarySortMode(), isNull);
    await repo.updateQuestionLibrarySortMode('wrong_first');
    expect(await repo.getQuestionLibrarySortMode(), 'wrong_first');
    await db.close();
  });

  test('空白串存成 NULL；未知编码不拒绝、读侧降级成最新', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = SettingsRepository(db);
    await repo.ensureSettings();

    await repo.updateQuestionLibrarySortMode(' serial ');
    expect(await repo.getQuestionLibrarySortMode(), 'serial',
        reason: '两端空白要 trim，库里只存稳定 encode');

    await repo.updateQuestionLibrarySortMode('   ');
    expect(await repo.getQuestionLibrarySortMode(), isNull,
        reason: '空白不是第四种状态，写 NULL 表示「没选过」');

    await repo.updateQuestionLibrarySortMode('by_difficulty');
    expect(await repo.getQuestionLibrarySortMode(), 'by_difficulty',
        reason: '仓库不替域层的合法集合做把关，未知编码原样保留');
    expect(questionLibrarySortFromStorage('by_difficulty'),
        QuestionLibrarySort.newest,
        reason: '未来版本写的档位，这一版读不懂就退回出厂最新，不炸');

    await repo.updateQuestionLibrarySortMode(null);
    expect(await repo.getQuestionLibrarySortMode(), isNull,
        reason: '传 null = 恢复出厂排序');
    await db.close();
  });

  test('新库没有设置行时读作没选过（不靠迁移，靠读侧兜底）', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = SettingsRepository(db);
    expect(await repo.getQuestionLibrarySortMode(), isNull);
    await db.close();
  });
}

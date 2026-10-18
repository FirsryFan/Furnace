import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/settings_repository.dart';
import 'package:furnace/domain/services/reasoning/capability_action_overlay.dart';
import 'package:furnace/features/questions/application/capability_vocabulary_store.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v24 -> v25：local_settings.capability_action_overlay_json（能力动作词表
/// overlay 持久化，轮次一百二十三）。
///
/// 加的是**一列可空偏好**，要锁的是三件事：
///
///  1. 真实 v24 文件升级后，老设置原样保留，新列是 NULL —— 迁移只加列，不替
///     用户选词表（与语言、主题、目标机制开关同一条契约）；
///  2. 已经被盖成 v25、却没有这一列的文件靠 beforeOpen 自愈 —— Drift 在
///     user_version 等于当前版本时完全跳过 onUpgrade，那一刻没有自愈，读设置
///     就会因为 no such column 炸掉；
///  3. 升级后的库能直接读写词表：NULL 读作出厂词表，保存后能读回来，且关库
///     重开（不再迁移）仍然在。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig25_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 造一个 v24 形状的文件：先用当前 schema 建库写好设置，再把新列 DROP 掉、
  /// 把 user_version 压回去（或压成 25 伪装成缺列文件）。
  Future<File> buildDb({
    required int userVersion,
    required String name,
  }) async {
    final dbFile = File('${tempDir.path}/$name.db');
    final fresh = AppDatabase.forTesting(NativeDatabase(dbFile));
    final settings = SettingsRepository(fresh);
    await settings.ensureSettings(language: 'zh', themeMode: 'dark');
    await settings.updateGoalBeta(0.7);
    await fresh.close();

    final raw = sql.sqlite3.open(dbFile.path);
    raw.execute(
      'ALTER TABLE local_settings DROP COLUMN capability_action_overlay_json',
    );
    raw.execute('PRAGMA user_version = $userVersion');
    raw.dispose();
    return dbFile;
  }

  CapabilityActionOverlay overlayWith(String key, String labelZh) =>
      CapabilityActionOverlay(
        customActions: <CustomCapabilityAction>[
          CustomCapabilityAction(
            key: key,
            labelZh: labelZh,
            subjectHints: const <String>['physics'],
          ),
        ],
      );

  test('真实 v24 文件升级后：老设置原样保留，新列是 NULL', () async {
    final file = await buildDb(userVersion: 24, name: 'v24');
    final db = AppDatabase.forTesting(NativeDatabase(file));
    final settings = SettingsRepository(db);

    final row = await settings.getSettings();
    expect(row, isNotNull);
    expect(row!.language, 'zh');
    expect(row.themeMode, 'dark');
    expect(row.goalBeta, 0.7);
    expect(
      row.capabilityActionOverlayJson,
      isNull,
      reason: '迁移只加列；NULL = 用户没改过词表 = 出厂词表',
    );

    final store = CapabilityVocabularyStore(settings);
    expect((await store.load()).isEmpty, isTrue);

    await store.save(overlayWith('force_diagram_analysis', '受力图分析'));
    final loaded = await store.load();
    expect(loaded.customActions.single.key, 'force_diagram_analysis');
    expect(loaded.customActions.single.labelZh, '受力图分析');
    await db.close();
  });

  test('保存后关库重开（已是 v25，不再迁移）仍然读得回来', () async {
    final file = await buildDb(userVersion: 24, name: 'v24persist');

    var db = AppDatabase.forTesting(NativeDatabase(file));
    await CapabilityVocabularyStore(SettingsRepository(db)).save(
      overlayWith('mapping_inversion', '映射与反演'),
    );
    await db.close();

    db = AppDatabase.forTesting(NativeDatabase(file));
    final loaded =
        await CapabilityVocabularyStore(SettingsRepository(db)).load();
    expect(loaded.customActions.single.key, 'mapping_inversion');
    expect(loaded.customActions.single.labelZh, '映射与反演');
    expect(loaded.customActions.single.subjectHints, <String>['physics']);
    await db.close();
  });

  test('被盖成 v25 却没有这一列的文件，靠自愈补列', () async {
    final file = await buildDb(userVersion: 25, name: 'fake25');
    final db = AppDatabase.forTesting(NativeDatabase(file));
    final settings = SettingsRepository(db);

    // 没有自愈的话，这一行读取就会因为 no such column 抛异常。
    final row = await settings.getSettings();
    expect(row!.language, 'zh');
    expect(row.capabilityActionOverlayJson, isNull);

    final store = CapabilityVocabularyStore(settings);
    await store.save(overlayWith('limit_process', '取极限'));
    expect((await store.load()).customActions.single.key, 'limit_process');
    await db.close();
  });
}

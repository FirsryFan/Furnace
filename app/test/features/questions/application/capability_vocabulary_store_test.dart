import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/repository_providers.dart';
import 'package:furnace/data/repositories/settings_repository.dart';
import 'package:furnace/domain/services/reasoning/capability_action.dart';
import 'package:furnace/domain/services/reasoning/capability_action_overlay.dart';
import 'package:furnace/features/questions/application/capability_vocabulary_store.dart';

/// 能力动作词表的持久化（schema v25，docs/REASONING_LAYER_DESIGN.md 第 4 节）。
///
/// 存的是**用户条目**，不是合并后的整张词表：内置词表跟着代码走，用户条目只有
/// 几十条。几条契约要钉住：
///
///  * NULL / 坏 JSON / 形状不对 ⇒ 出厂词表，绝不因为词表读不出来就阻塞别的功能；
///  * 保存空词表 ⇒ 写回 NULL（回到出厂词表），不留下 "version":1 的空壳；
///  * 保存即建行（local_settings 单行表可能还不存在）。
void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  late CapabilityVocabularyStore store;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsRepository(db);
    store = CapabilityVocabularyStore(settings);
  });

  tearDown(() async {
    await db.close();
  });

  CapabilityActionOverlay overlayWith(
    List<CustomCapabilityAction> actions,
  ) =>
      CapabilityActionOverlay(customActions: actions);

  CustomCapabilityAction action(
    String key,
    String labelZh, {
    List<String> subjectHints = const <String>['physics'],
  }) =>
      CustomCapabilityAction(
        key: key,
        labelZh: labelZh,
        subjectHints: subjectHints,
      );

  test('没有设置行：读作出厂词表，不抛异常', () async {
    final loaded = await store.load();
    expect(loaded.isEmpty, isTrue);
    expect(loaded.catalog.actions, hasLength(CapabilityAction.catalog.length));
    // 读不该顺手建行：没改过词表的用户，local_settings 里不该多出东西。
    expect(await settings.getSettings(), isNull);
  });

  test('设置行存在但列为 NULL：读作出厂词表', () async {
    await settings.ensureSettings();
    final loaded = await store.load();
    expect(loaded.isEmpty, isTrue);
    expect((await settings.getSettings())!.capabilityActionOverlayJson, isNull);
  });

  test('save 写进 local_settings，load 读回同一条，合并词表认得它', () async {
    await settings.ensureSettings();
    await store.save(
      overlayWith(<CustomCapabilityAction>[
        action('force_diagram_analysis', '受力图分析'),
      ]),
    );

    final row = await settings.getSettings();
    expect(row!.capabilityActionOverlayJson, contains('"version":1'));
    expect(row.capabilityActionOverlayJson, contains('force_diagram_analysis'));

    final loaded = await store.load();
    expect(loaded.customActions, hasLength(1));
    expect(loaded.customActions.single.key, 'force_diagram_analysis');
    expect(loaded.customActions.single.labelZh, '受力图分析');
    expect(loaded.customActions.single.subjectHints, <String>['physics']);

    final catalog = loaded.catalog;
    expect(catalog.actions, hasLength(CapabilityAction.catalog.length + 1));
    expect(catalog.isCustomKey('force_diagram_analysis'), isTrue);
    expect(catalog.isBuiltInKey('force_diagram_analysis'), isFalse);
    expect(catalog.byKey('force_diagram_analysis')!.labelZh, '受力图分析');
  });

  test('save 前没有设置行也会建行', () async {
    await store.save(
      overlayWith(<CustomCapabilityAction>[action('limit_process', '取极限')]),
    );
    final row = await settings.getSettings();
    expect(row, isNotNull);
    expect(row!.language, 'system', reason: 'ensureSettings 的出厂值');
    expect(row.capabilityActionOverlayJson, isNotNull);
    expect((await store.load()).customActions.single.key, 'limit_process');
  });

  test('save 空词表写回 NULL（回到出厂词表），不留下空壳 JSON', () async {
    await store.save(
      overlayWith(<CustomCapabilityAction>[action('limit_process', '取极限')]),
    );
    expect((await settings.getSettings())!.capabilityActionOverlayJson, isNotNull);

    await store.save(CapabilityActionOverlay.empty);
    expect(
      (await settings.getSettings())!.capabilityActionOverlayJson,
      isNull,
    );
    expect((await store.load()).isEmpty, isTrue);
  });

  test('保存空词表的空列表也写回 NULL', () async {
    await settings.ensureSettings();
    await store.save(overlayWith(<CustomCapabilityAction>[]));
    expect(
      (await settings.getSettings())!.capabilityActionOverlayJson,
      isNull,
    );
  });

  test('多条自定义动作按用户顺序保留', () async {
    await store.save(
      overlayWith(<CustomCapabilityAction>[
        action('force_diagram_analysis', '受力图分析'),
        action('limit_process', '取极限', subjectHints: const <String>[]),
        action('mapping_inversion', '映射与反演'),
      ]),
    );
    final loaded = await store.load();
    expect(
      loaded.customActions.map((a) => a.key).toList(),
      <String>['force_diagram_analysis', 'limit_process', 'mapping_inversion'],
    );
    expect(loaded.customActions[1].subjectHints, isEmpty);
    expect(loaded.toJson()['version'], 1);
  });

  test('坏 JSON 读作出厂词表，不抛异常', () async {
    await settings.ensureSettings();
    for (final bad in <String>[
      '',
      '   ',
      '{',
      '{"customActions": [oops',
      'not json at all',
    ]) {
      await settings.updateCapabilityActionOverlayJson(bad);
      final loaded = await store.load();
      expect(loaded.isEmpty, isTrue, reason: '坏 JSON 应读作出厂词表：$bad');
    }
  });

  test('形状不对的合法 JSON 也读作出厂词表', () async {
    await settings.ensureSettings();
    for (final wrongShape in <String>[
      'null',
      '42',
      '{"customActions": 42}',
      '{"version":1}',
      '"a string"',
    ]) {
      await settings.updateCapabilityActionOverlayJson(wrongShape);
      expect((await store.load()).isEmpty, isTrue, reason: wrongShape);
    }
  });

  test('坏数据被覆盖后能正常保存', () async {
    await settings.ensureSettings();
    await settings.updateCapabilityActionOverlayJson('{oops');
    expect((await store.load()).isEmpty, isTrue);

    await store.save(
      overlayWith(<CustomCapabilityAction>[action('limit_process', '取极限')]),
    );
    expect((await store.load()).customActions.single.key, 'limit_process');
  });

  test('非法条目照样存得下，合并时被拒并留下 issues', () async {
    // 校验发生在合并（catalog）而不是存储：界面层能边存边提示，不用猜哪条
    // 保存失败。
    await store.save(
      overlayWith(<CustomCapabilityAction>[
        action('Bad Key', '不合法', subjectHints: const <String>[]),
      ]),
    );
    final loaded = await store.load();
    expect(loaded.customActions.single.key, 'Bad Key');
    final catalog = loaded.catalog;
    expect(catalog.isCustomKey('Bad Key'), isFalse);
    expect(catalog.issues, hasLength(1));
    expect(
      catalog.issues.single.reason,
      CapabilityActionOverlayIssueReason.keyNotSnakeCase,
    );
  });

  test('provider：保存后 invalidate 才读到新词表（provider 有缓存）', () async {
    final container = ProviderContainer(
      overrides: <Override>[
        settingsRepositoryProvider.overrideWithValue(settings),
      ],
    );
    addTearDown(container.dispose);

    expect((await container.read(capabilityActionOverlayProvider.future)).isEmpty,
        isTrue);

    await store.save(
      overlayWith(<CustomCapabilityAction>[action('limit_process', '取极限')]),
    );
    // 没 invalidate 之前仍是旧值。
    expect((await container.read(capabilityActionOverlayProvider.future)).isEmpty,
        isTrue);

    container.invalidate(capabilityActionOverlayProvider);
    final refreshed =
        await container.read(capabilityActionOverlayProvider.future);
    expect(refreshed.customActions.single.key, 'limit_process');
  });
}

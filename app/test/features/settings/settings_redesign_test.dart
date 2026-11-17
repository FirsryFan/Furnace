// 2026-11-15 设置页重构的契约测试。
//
// 用户要求：设置界面干净、分组、普通学生只看到需要的；开发者/原型入口下沉。
// 这个文件钉住重构后的可见形状，防止它又退回"20 个 ListTile 平铺"：
//  1. 分区顺序固定：学习与计划 → AI → 外观与阅读 → 数据 → 帮助 → 开发者；
//  2. 开发者分区默认折叠，普通视图里没有设计板/预设原型/能力词表/示例数据/
//     高考资源库/诊断包；
//  3. 点「显示」后开发者入口全部出现，点「隐藏」后又消失；
//  4. 重复/无效入口不再出现（题库、标签、直连 db 的备份数据）；
//  5. 入口归位（task-113 第二遍清理）：卡组设置、认知模型不再放总设置；
//  6. 普通视图不出现开发字段/内部 id；
//  7. 关键入口仍然可达（今日计划、Markdown、知识库、使用文档、关于……）；
//  8. 档案卡可改名、数据位置可复制、备份与恢复在数据分区里。
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/settings_repository.dart';
import 'package:furnace/data/storage/app_storage.dart';
import 'package:furnace/features/ai/presentation/ai_settings_page.dart';
import 'package:furnace/features/assessment/presentation/assessment_center_page.dart';
import 'package:furnace/features/cognitive/presentation/cognitive_developer_page.dart';
import 'package:furnace/features/design_board/presentation/design_board_page.dart';
import 'package:furnace/features/markdown/presentation/markdown_settings_page.dart';
import 'package:furnace/features/packages/presentation/packages_page.dart';
import 'package:furnace/features/settings/presentation/about_page.dart';
import 'package:furnace/features/settings/presentation/data_backup_page.dart';
import 'package:furnace/features/settings/presentation/data_location_tile.dart';
import 'package:furnace/features/settings/presentation/data_section.dart';
import 'package:furnace/features/settings/presentation/review_reminder_section.dart';
import 'package:furnace/features/settings/presentation/settings_page.dart';
import 'package:furnace/features/settings/presentation/settings_profile_card.dart';
import 'package:furnace/features/settings/presentation/usage_doc_page.dart';
import 'package:furnace/features/settings/presentation/user_persona_page.dart';
import 'package:furnace/features/student_preset/application/preset_selection.dart';
import 'package:furnace/features/student_preset/presentation/preset_select_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

void main() {
  late AppDatabase db;
  late AppLocalizations zh;
  late AppLocalizations en;

  setUpAll(() async {
    zh = await AppLocalizations.delegate.load(const Locale('zh'));
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// 页面很高：先把所有分区构建出来，再断言顺序/存在性。
  Future<void> pumpSettings(
    WidgetTester tester, {
    Locale locale = const Locale('zh'),
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db), ...overrides],
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 展开开发者分区（默认折叠）。
  Future<void> expandDeveloper(WidgetTester tester) async {
    await tester.tap(find.byKey(settingsDeveloperToggleKey));
    await tester.pumpAndSettle();
  }

  testWidgets('分区顺序：学习与计划 → AI → 外观与阅读 → 数据 → 帮助 → 开发者',
      (tester) async {
    await pumpSettings(tester);

    final keys = <Key>[
      settingsSectionLearningKey,
      settingsSectionAiKey,
      settingsSectionAppearanceReadingKey,
      settingsSectionDataKey,
      settingsSectionHelpKey,
      settingsSectionDeveloperKey,
    ];
    for (final key in keys) {
      expect(find.byKey(key), findsOneWidget, reason: '分区 $key 应存在');
    }
    final ys = <double>[
      for (final key in keys) tester.getTopLeft(find.byKey(key)).dy,
    ];
    for (var i = 1; i < ys.length; i++) {
      expect(
        ys[i],
        greaterThan(ys[i - 1]),
        reason: '分区顺序固定，第 ${i + 1} 个分区应在上一个下面',
      );
    }
  });

  testWidgets('普通学生默认只看到前六块：开发者/原型入口全部隐藏', (tester) async {
    await pumpSettings(tester);

    // 开发者分区本身可见（标题 + 显示按钮 + 一句说明），但内容不构建。
    expect(find.byKey(settingsSectionDeveloperKey), findsOneWidget);
    expect(find.text(zh.settingsDeveloperShow), findsOneWidget);
    expect(find.text(zh.settingsDeveloperHint), findsOneWidget);

    for (final hidden in <Key>[
      settingsCognitiveDeveloperTileKey,
      settingsDesignBoardTileKey,
      settingsHighSchoolLibraryTileKey,
      settingsDiagnosticsTileKey,
      settingsPresetSelectTileKey,
      settingsDemoDataTileKey,
    ]) {
      expect(find.byKey(hidden), findsNothing, reason: '默认折叠时不该有 $hidden');
    }
    expect(find.text(zh.capabilityVocabularySettingsTitle), findsNothing);
    expect(find.byType(DesignBoardPage), findsNothing);
    expect(find.byType(PresetSelectPage), findsNothing);
  });

  testWidgets('展开开发者：折叠内容全部出现；再点隐藏又消失', (tester) async {
    await pumpSettings(tester);
    await expandDeveloper(tester);

    expect(find.text(zh.settingsDeveloperHide), findsOneWidget);
    for (final visible in <Key>[
      settingsCognitiveDeveloperTileKey,
      settingsDesignBoardTileKey,
      settingsHighSchoolLibraryTileKey,
      settingsDiagnosticsTileKey,
      settingsPresetSelectTileKey,
      settingsDemoDataTileKey,
    ]) {
      expect(find.byKey(visible), findsOneWidget, reason: '展开后应有 $visible');
    }
    expect(find.text(zh.capabilityVocabularySettingsTitle), findsOneWidget);
    expect(find.text(zh.settingsDemoData), findsOneWidget);
    expect(find.text('高考资源库'), findsOneWidget);

    // 收起：又只剩标题和说明。
    await expandDeveloper(tester);
    expect(find.text(zh.settingsDeveloperShow), findsOneWidget);
    expect(find.byKey(settingsDesignBoardTileKey), findsNothing);
    expect(find.byKey(settingsHighSchoolLibraryTileKey), findsNothing);
    expect(find.byKey(settingsPresetSelectTileKey), findsNothing);
  });

  testWidgets('重复/无效入口已删除：题库、标签、直连 db 的备份数据不再出现', (tester) async {
    await pumpSettings(tester);

    // 题库是外壳导航的独立目的地；标签是导航第二项；备份数据与 tfpkg 导出重复。
    expect(find.text(zh.navQuestions), findsNothing);
    expect(find.text(zh.navTags), findsNothing);
    expect(find.text(zh.settingsBackup), findsNothing);
    // 它们的功能都还在：工作区备份只有一个入口「备份与恢复」，进去才是
    // 导出/导入（第二遍清理把两行合并成一个入口组）。
    expect(find.byKey(settingsDataBackupTileKey), findsOneWidget);
    expect(find.text(zh.settingsBackupRestoreTitle), findsOneWidget);
    expect(find.text(zh.settingsTfpkgExport), findsNothing);
    expect(find.text(zh.settingsTfpkgImport), findsNothing);
  });

  testWidgets('备份与恢复页：一个入口组里是导出/导入，诊断包不在这里', (tester) async {
    await pumpSettings(tester);

    tester.widget<ListTile>(find.byKey(settingsDataBackupTileKey)).onTap!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(DataBackupPage), findsOneWidget);
    expect(find.text(zh.settingsTfpkgExport), findsOneWidget);
    expect(find.text(zh.settingsTfpkgImport), findsOneWidget);
    // 诊断包是排障工具：它在设置页开发者分区，不在用户数据入口组里。
    expect(find.text(zh.settingsDiagnosticExport), findsNothing);
  });

  testWidgets('入口归位：卡组设置不在总设置，认知模型不在总设置', (tester) async {
    await pumpSettings(tester);

    // 卡组就是标签树，卡组设置在闪存卡模块（复习计划页）里。
    expect(find.text(zh.settingsCardGroups), findsNothing);
    expect(find.byKey(const Key('settings-card-groups-tile')), findsNothing);
    // 认知模型原页已删：用户层只到顶层「学习状态」模块。
    expect(find.text('认知模型'), findsNothing);
    expect(find.byKey(const Key('settings-cognitive-model-tile')), findsNothing);
    // 高考资源库与诊断包下沉开发者（默认折叠）。
    expect(find.text('高考资源库'), findsNothing);
    expect(find.text(zh.settingsDiagnosticExport), findsNothing);
  });

  testWidgets('普通视图没有重复行：所有可见 ListTile 标题唯一', (tester) async {
    await pumpSettings(tester);

    final titles = <String>[];
    for (final tile in tester.widgetList<ListTile>(find.byType(ListTile))) {
      final title = tile.title;
      if (title is Text && title.data != null) {
        titles.add(title.data!);
      }
    }
    expect(titles, isNotEmpty);
    final duplicates = <String>[
      for (final title in titles)
        if (titles.where((other) => other == title).length > 1) title,
    ];
    expect(duplicates.toSet(), isEmpty, reason: '设置页不应有重复入口: $duplicates');
  });

  testWidgets('设置页不出现开发字段/内部 id（content_package、哈希、R0/band 等）',
      (tester) async {
    await pumpSettings(tester);

    final texts = <String>[
      for (final text in tester.widgetList<Text>(find.byType(Text)))
        if (text.data != null) text.data!,
    ];
    const forbidden = <String>[
      'content_package',
      'sha256',
      'hash',
      'R0',
      'Gain',
      'band',
      'zone',
      'calibration',
      'orphan',
      '内部 id',
    ];
    for (final token in forbidden) {
      expect(
        texts.any((text) => text.contains(token)),
        isFalse,
        reason: '普通设置页不该出现开发字段 "$token"',
      );
    }
  });

  testWidgets('关键入口仍可达：备份与恢复 / Markdown / 知识库 / 使用文档 / 关于',
      (tester) async {
    await pumpSettings(tester);

    Future<void> open(Key tileKey, Type pageType) async {
      final tile = find.byKey(tileKey);
      expect(tile, findsOneWidget, reason: '入口 $tileKey 应存在');
      tester.widget<ListTile>(tile).onTap!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(pageType), findsOneWidget, reason: '应打开 $pageType');
      Navigator.of(tester.element(find.byType(pageType))).pop();
      // 路由退场动画 300ms + 一帧移除；分步 pump 而不是 pumpAndSettle——
      // 有些页面在测试环境里会一直转加载圈，settle 会超时。
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(pageType), findsNothing);
    }

    await open(settingsUserPersonaTileKey, UserPersonaPage);
    await open(settingsAssessmentTileKey, AssessmentCenterPage);
    await open(settingsAiTileKey, AiSettingsPage);
    await open(settingsDataBackupTileKey, DataBackupPage);
    await open(settingsKnowledgeLibraryTileKey, PackagesPage);
    await open(settingsUsageDocTileKey, UsageDocPage);
    await open(settingsAboutTileKey, AboutPage);

    // Markdown 入口由 task-104 提供，挂在「外观与阅读」下（页面/入口不在这里实现）。
    final markdown = find.byKey(settingsMarkdownTileKey);
    await tester.scrollUntilVisible(markdown, 200);
    await tester.pumpAndSettle();
    expect(markdown, findsOneWidget);
    tester.widget<ListTile>(markdown).onTap!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(MarkdownSettingsPage), findsOneWidget);
  });

  testWidgets('复习提醒仍在学习分区里（开关对话框入口不丢）', (tester) async {
    await pumpSettings(tester);
    expect(find.byKey(reviewReminderSectionKey), findsOneWidget);
  });

  testWidgets('档案卡：显示名字；点按改名并写进数据库', (tester) async {
    await SettingsRepository(db).ensureProfile(displayName: '小明');
    await pumpSettings(tester);

    expect(find.byKey(settingsProfileCardKey), findsOneWidget);
    expect(find.text('小明'), findsOneWidget);
    expect(find.text(zh.settingsProfileIdentity), findsOneWidget);

    await tester.tap(find.byKey(settingsProfileCardKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(settingsProfileNameFieldKey), '小鱼');
    await tester.tap(find.text(zh.commonSave));
    await tester.pumpAndSettle();

    expect((await SettingsRepository(db).getProfile())!.displayName, '小鱼');
    expect(find.text('小鱼'), findsOneWidget);
  });

  testWidgets('数据位置：显示本机路径，点按复制并提示', (tester) async {
    final temp = Directory.systemTemp.createTempSync('furnace-settings-data-');
    addTearDown(() => temp.deleteSync(recursive: true));
    AppStorage.debugConfigureForTesting(supportDirectory: () async => temp);
    addTearDown(AppStorage.debugReset);

    // 剪贴板在 widget 测试里没有真实平台实现：截住 Clipboard.setData，
    // 既验证"点了会复制"，又拿到被复制的文本。
    final copied = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map<Object?, Object?>)['text']! as String);
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await pumpSettings(tester);

    expect(find.text(temp.path), findsOneWidget);
    await tester.tap(find.byKey(settingsDataLocationTileKey));
    await tester.pumpAndSettle();
    expect(find.text(zh.settingsDataLocationCopied), findsOneWidget);
    expect(copied, [temp.path]);
  });

  testWidgets('语言仍在外观与阅读分区里，点开是三种选择', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.byKey(settingsLanguageTileKey));
    await tester.pumpAndSettle();

    final dialog = find.byType(SimpleDialog);
    expect(dialog, findsOneWidget);
    for (final option in <String>[
      zh.settingsLanguageSystem,
      zh.settingsLanguageZh,
      zh.settingsLanguageEn,
    ]) {
      expect(
        find.descendant(of: dialog, matching: find.text(option)),
        findsOneWidget,
      );
    }
  });

  testWidgets('英文界面同样按分区渲染', (tester) async {
    await pumpSettings(tester, locale: const Locale('en'));

    expect(find.text(en.settingsSectionLearning), findsOneWidget);
    expect(find.text(en.settingsSectionHelp), findsOneWidget);
    expect(find.text(en.settingsDeveloperShow), findsOneWidget);
    expect(find.text(en.settingsSectionDeveloper), findsOneWidget);
  });

  testWidgets('已选预设时展开开发者，副标题显示当前档；默认折叠时不显示原型文案',
      (tester) async {
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    container.read(presetSelectionProvider.notifier).state =
        const PresetSelection(presetId: 'preset-medium', presetName: '中等');

    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已选：中等（内存，可随时改选）'), findsNothing);
    await expandDeveloper(tester);
    expect(find.text('已选：中等（内存，可随时改选）'), findsOneWidget);
  });
}

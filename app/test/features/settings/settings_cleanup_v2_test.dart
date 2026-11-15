// 设置第二遍清理（task-113）的验收测试。
//
// 用户反馈（原话）：
//  * 设置很多入口要合并；
//  * 管线/外接入口要清理；
//  * 「认知模型」进去基本围绕闪存卡，数据呈现诡异；
//  * 卡组设置不应放总设置；
//  * 很多功能奇怪，需要重点清理。
//
// 这个文件钉住第二遍清理后的形状（第一遍的形状见 `settings_redesign_test.dart`）：
//  1. 学习分区只留普通学生会用的入口；卡组设置/认知模型不在总设置；
//  2. 高考资源库、诊断包下沉开发者分区（默认折叠，展开才构建）；
//  3. 数据只留一个入口组：备份与恢复一行进导出/导入，诊断包不在数据区；
//  4. AI 页普通视图只有模型/API/权限，轮次上限/工具/技能包默认折叠；
//  5. 顶层模块叫「学习状态」，档位/强弱项以知识点为观测单位（不出现"张卡"口径）。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/skill/skill_store.dart';
import 'package:furnace/features/ai/application/ai_providers.dart';
import 'package:furnace/features/ai/presentation/ai_settings_page.dart';
import 'package:furnace/features/cognitive/presentation/mindnet_page.dart';
import 'package:furnace/features/library/presentation/gaokao_library_page.dart';
import 'package:furnace/features/settings/presentation/data_backup_page.dart';
import 'package:furnace/features/settings/presentation/data_section.dart';
import 'package:furnace/features/settings/presentation/settings_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

void main() {
  late AppDatabase db;
  late AppLocalizations zh;

  setUpAll(() async {
    zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> pumpPage(
    WidgetTester tester,
    Widget page, {
    List<Override> overrides = const [],
    Locale locale = const Locale('zh'),
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
          home: page,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('总设置：入口合并与归位', () {
    testWidgets('学习分区只剩 5 个普通入口；卡组/认知模型/高考资源库都不在',
        (tester) async {
      await pumpPage(tester, const SettingsPage());

      // 保留的普通入口。
      for (final kept in <Key>[
        settingsTodayPlanTileKey,
        settingsLearningInsightTileKey,
        settingsUserPersonaTileKey,
        settingsAssessmentTileKey,
      ]) {
        expect(find.byKey(kept), findsOneWidget, reason: '应保留入口 $kept');
      }
      expect(find.text(zh.reviewReminderSettingTitle), findsOneWidget);

      // 移走的入口（功能在各自模块里，不在总设置）。
      expect(find.text(zh.settingsCardGroups), findsNothing, reason: '卡组设置属于闪存卡模块');
      expect(find.text('认知模型'), findsNothing, reason: '用户入口只到学习状态模块');
      expect(find.text('高考资源库'), findsNothing, reason: '资源库下沉开发者');
      expect(find.text(zh.settingsDiagnosticExport), findsNothing, reason: '诊断包下沉开发者');
    });

    testWidgets('开发者展开后：高考资源库/诊断包出现，分别打开真实页面',
        (tester) async {
      await pumpPage(tester, const SettingsPage());
      await tester.tap(find.byKey(settingsDeveloperToggleKey));
      await tester.pumpAndSettle();

      expect(find.text('高考资源库'), findsOneWidget);
      expect(find.byKey(settingsDiagnosticsTileKey), findsOneWidget);

      // 诊断包：一排障工具，打开的是它自己的页（导出按钮在页里）。
      await tester.tap(find.byKey(settingsDiagnosticsTileKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(DiagnosticsBundlePage), findsOneWidget);
      expect(find.text(zh.settingsDiagnosticExport), findsWidgets);
    });

    testWidgets('数据分区只有一个入口组：备份与恢复在页内是导出/导入', (tester) async {
      await pumpPage(tester, const SettingsPage());

      expect(find.byKey(settingsDataBackupTileKey), findsOneWidget);
      // 「数据」分区里不再直接铺开导出/导入/诊断包。
      expect(find.text(zh.settingsTfpkgExport), findsNothing);
      expect(find.text(zh.settingsTfpkgImport), findsNothing);
      expect(find.text(zh.settingsDiagnosticExport), findsNothing);

      tester.widget<ListTile>(find.byKey(settingsDataBackupTileKey)).onTap!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(DataBackupPage), findsOneWidget);
      expect(find.text(zh.settingsTfpkgExport), findsOneWidget);
      expect(find.text(zh.settingsTfpkgImport), findsOneWidget);
    });

    testWidgets('高考资源库入口在开发者里点得开', (tester) async {
      await pumpPage(tester, const SettingsPage());
      await tester.tap(find.byKey(settingsDeveloperToggleKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(settingsHighSchoolLibraryTileKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(GaokaoLibraryPage), findsOneWidget);
    });
  });

  group('AI 页：模型/API/权限在前，开发者参数下沉', () {
    testWidgets('默认只有模型/API/权限；轮次上限与工具清单要展开才出现',
        (tester) async {
      await pumpPage(
        tester,
        const AiSettingsPage(),
        // 技能卡（默认折叠里）读安装列表；默认视图不构建它，展开时要能立即结束。
        overrides: [
          installedSkillsProvider.overrideWith((ref) => const <InstalledSkill>[]),
        ],
      );

      // 普通视图：API key / base url / model 三个输入框 + 权限模式。
      expect(find.byType(TextField), findsNWidgets(3));
      expect(find.text(zh.settingsAiPermissionMode), findsOneWidget);
      // 开发者参数默认折叠。
      expect(find.byType(Slider), findsNothing);
      expect(find.textContaining('可用工具（'), findsNothing);
      expect(find.text(zh.aiDeveloperParamsHint), findsOneWidget);

      await tester.tap(find.byKey(aiSettingsDeveloperToggleKey));
      await tester.pumpAndSettle();

      expect(find.byType(Slider), findsOneWidget);
      expect(find.textContaining('可用工具（'), findsOneWidget);
      expect(find.text(zh.aiDeveloperParamsHint), findsNothing);
    });
  });

  group('学习状态：不再以闪存卡为主要口径', () {
    testWidgets('顶层模块标签是「学习状态」', (tester) async {
      await pumpPage(tester, const MindNetPage());
      expect(zh.navMindnet, '学习状态');
      expect(find.text('学习状态'), findsOneWidget);
    });

    testWidgets('空库时档位/强弱项说「知识点」证据不足，不出现"张卡"读数',
        (tester) async {
      await pumpPage(tester, const MindNetPage());

      expect(find.text(zh.mindnetBandInsufficient(3)), findsOneWidget);
      expect(find.text(zh.mindnetStrengthsEmpty), findsOneWidget);
      // 用户层不再把"复习过多几张卡"当档位依据。
      expect(find.textContaining('张复习过的卡片'), findsNothing);
      expect(find.textContaining('实测 ·'), findsNothing);
      // 闪存卡只以"今天待复习"的形式出现，并明确标注是闪存卡。
      expect(find.textContaining('闪存卡待复习'), findsOneWidget);
    });
  });
}

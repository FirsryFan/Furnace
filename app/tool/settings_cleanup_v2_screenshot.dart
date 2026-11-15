/// 设置第二遍清理（task-113）的验收截图。
///
/// 运行方式（在 Furnace app 目录下）：
///
///   flutter test tool/settings_cleanup_v2_screenshot.dart
///
/// 与普通 widget 测试不同，这个脚本的真实职责是**落盘 PNG**：用真实中文
/// 字体（`assets/fonts/noto-sans-sc-regular.ttf`）渲染真实页面，写到工作区
/// `.work/settings-cleanup-v2-2026-11-15/`。
///
/// 拍四类页面：
///  1. 设置默认视图（开发者折叠）——看入口是不是真的变少；
///  2. 设置展开开发者——高考资源库/诊断包已下沉到这里；
///  3. AI 页默认 / 展开开发者参数——模型/API/权限在前，轮次上限/工具/技能在后；
///  4. 学习状态页（原 MindNet）——档位/强弱项以知识点为单位。
///
/// 不是 CI 用例：图标字体读本机 Flutter SDK 自带的 MaterialIcons，读不到就跳过。
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/settings_repository.dart';
import 'package:furnace/data/skill/skill_store.dart';
import 'package:furnace/data/storage/app_storage.dart';
import 'package:furnace/features/ai/application/ai_providers.dart';
import 'package:furnace/features/ai/presentation/ai_settings_page.dart';
import 'package:furnace/features/cognitive/presentation/mindnet_page.dart';
import 'package:furnace/features/settings/presentation/settings_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

const String _outDir =
    r'E:\Workspaces\agent-control\10-projects\agent-control-plane\.work\settings-cleanup-v2-2026-11-15';

/// 数据位置行在截图里显示的本机路径（只在界面出现，脚本不创建它）。
const String _fakeDataRoot = r'E:\Furnace\data';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _loadFonts();
  final zh = await AppLocalizations.delegate.load(const Locale('zh'));

  testWidgets('设置默认（开发者折叠）1280×2150', (tester) async {
    await _pump(tester, const SettingsPage(), size: const Size(1280, 2150));
    await _capture(tester, 'settings-cleanup-default-1280x2150.png');
    expect(zh.settingsSectionLearning, '学习与计划');
  });

  testWidgets('设置展开开发者 1280×2750', (tester) async {
    await _pump(tester, const SettingsPage(), size: const Size(1280, 2750));
    await tester.tap(find.byKey(settingsDeveloperToggleKey));
    await tester.pumpAndSettle();
    await _capture(tester, 'settings-cleanup-developer-1280x2750.png');
    expect(find.byKey(settingsHighSchoolLibraryTileKey), findsOneWidget);
  });

  testWidgets('AI 页默认（开发者参数折叠）1280×850', (tester) async {
    await _pump(tester, const AiSettingsPage(), size: const Size(1280, 850));
    await _capture(tester, 'ai-settings-default-1280x850.png');
    expect(find.byKey(aiSettingsDeveloperToggleKey), findsOneWidget);
  });

  testWidgets('AI 页展开开发者参数 1280×2200', (tester) async {
    await _pump(tester, const AiSettingsPage(), size: const Size(1280, 2200));
    await tester.tap(find.byKey(aiSettingsDeveloperToggleKey));
    await tester.pumpAndSettle();
    await _capture(tester, 'ai-settings-developer-1280x2200.png');
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('学习状态（原 MindNet）1280×1050', (tester) async {
    await _pump(tester, const MindNetPage(), size: const Size(1280, 1050));
    await _capture(tester, 'learning-status-1280x1050.png');
    expect(zh.navMindnet, '学习状态');
  });
}

final GlobalKey _captureKey = GlobalKey();

Future<void> _loadFonts() async {
  // 中文字体：仓库自带，保证截图里的标题/副标题不是豆腐块。
  final noto =
      File(r'E:\Projects\Furnace\app\assets\fonts\noto-sans-sc-regular.ttf');
  if (noto.existsSync()) {
    final bytes = await noto.readAsBytes();
    final loader = FontLoader('Noto Sans SC')
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
  // 图标字体：用本机 Flutter SDK 自带的 MaterialIcons；找不到就算了。
  final icons = File(
    r'D:\flutter\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf',
  );
  if (icons.existsSync()) {
    final bytes = await icons.readAsBytes();
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
}

ThemeData _theme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF3D8B63),
    brightness: Brightness.dark,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF101211),
    fontFamily: 'Noto Sans SC',
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1B1D1C),
      foregroundColor: Colors.white,
      elevation: 0,
    ),
  );
}

/// 档案卡、「自我描述」与学习状态都需要真实行：截图要能看出这是谁的页面。
Future<AppDatabase> _seedDatabase() async {
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  final settings = SettingsRepository(database);
  await settings.ensureProfile(displayName: '小明');
  await settings.updateUserPersona(
    '我是高三学生，数学想冲 120 分；习惯先看解析再做题，计算容易粗心。',
  );

  // 学习状态：4 个有复习记录的知识点（每点 1 张卡），外加 1 个新卡知识点。
  const points = <String, String>{
    'kp-1': '光合作用',
    'kp-2': '呼吸作用',
    'kp-3': '细胞运输',
    'kp-4': '酶与代谢',
  };
  var day = 0;
  for (final entry in points.entries) {
    day++;
    await database.into(database.knowledgePoints).insert(
          KnowledgePointsCompanion.insert(
            id: entry.key,
            title: entry.value,
            content: '截图用知识点',
            createdAt: 1,
            updatedAt: 1,
          ),
        );
    await database.into(database.cardStates).insert(
          CardStatesCompanion.insert(
            id: 'cs-${entry.key}',
            createdAt: 1,
            updatedAt: 2,
            dueAt: Value(
              DateTime.now().millisecondsSinceEpoch - day * 3600 * 1000,
            ),
            repetitions: const Value(3),
            knowledgePointId: Value(entry.key),
            unitKey: Value('cloze:${entry.key}'),
            stability: Value(4.0 + day),
            difficulty: const Value(5.0),
            encodingStrength: Value(0.82 - day * 0.05),
            savings: const Value(0.8),
            lastReviewedAt: Value(
              DateTime.now().millisecondsSinceEpoch - day * 86400 * 1000,
            ),
          ),
        );
  }
  return database;
}

Future<void> _pump(
  WidgetTester tester,
  Widget page, {
  required Size size,
}) async {
  // 数据位置行读 AppStorage：注入稳定假路径并清缓存，绝不探测真实 E:\Furnace\data。
  // 这个脚本本来就是 `flutter test` 跑的（见文件头），只是放在 tool/ 下，所以
  // analyzer 不认这里是 test 目录，需要两处 ignore。
  // ignore: invalid_use_of_visible_for_testing_member
  AppStorage.debugConfigureForTesting(
    supportDirectory: () async => Directory(_fakeDataRoot),
  );
  // ignore: invalid_use_of_visible_for_testing_member
  addTearDown(AppStorage.debugReset);

  final database = await _seedDatabase();
  addTearDown(database.close);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(database),
        // 技能卡（AI 页开发者参数里）读安装目录：截图环境没有插件，给空列表。
        installedSkillsProvider.overrideWith((ref) => const <InstalledSkill>[]),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: _theme(),
        home: RepaintBoundary(key: _captureKey, child: page),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory(_outDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final file = File('$_outDir\\$name');
    file.writeAsBytesSync(data!.buffer.asUint8List());
    // ignore: avoid_print
    print('SCREENSHOT ${file.path} (${file.lengthSync()} bytes)');
    image.dispose();
  });
}

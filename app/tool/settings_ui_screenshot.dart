/// 设置页重构的验收截图（默认折叠 / 展开开发者；1280 / 2560 两档宽度）。
///
/// 运行方式（在 Furnace app 目录下）：
///
///   flutter test tool/settings_ui_screenshot.dart
///
/// 与普通 widget 测试不同，这个脚本的真实职责是**落盘 PNG**：用真实中文
/// 字体（`assets/fonts/noto-sans-sc-regular.ttf`）渲染真实 `SettingsPage`，
/// 写到工作区 `.work/settings-redesign-2026-11-15/`。
/// 不是 CI 用例：图标字体读本机 Flutter SDK 自带的 MaterialIcons，读不到就跳过。
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/settings_repository.dart';
import 'package:furnace/data/storage/app_storage.dart';
import 'package:furnace/features/settings/presentation/settings_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

const String _outDir =
    r'E:\Workspaces\agent-control\10-projects\agent-control-plane\.work\settings-redesign-2026-11-15';

/// 数据位置行在截图里显示的本机路径（只在界面出现，脚本不创建它）。
const String _fakeDataRoot = r'E:\Furnace\data';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _loadFonts();
  final zh = await AppLocalizations.delegate.load(const Locale('zh'));

  testWidgets('设置页默认（开发者折叠）1280×2800', (tester) async {
    await _pumpSettings(tester, size: const Size(1280, 2800));
    await _capture(tester, 'settings-default-1280x2800.png');
    expect(zh.settingsSectionLearning, '学习与计划');
  });

  testWidgets('设置页默认（开发者折叠）2560×2800', (tester) async {
    await _pumpSettings(tester, size: const Size(2560, 2800));
    await _capture(tester, 'settings-default-2560x2800.png');
  });

  testWidgets('设置页展开开发者 1280×3100', (tester) async {
    await _pumpSettings(tester, size: const Size(1280, 3100));
    await tester.tap(find.byKey(settingsDeveloperToggleKey));
    await tester.pumpAndSettle();
    await _capture(tester, 'settings-developer-1280x3100.png');
    expect(find.byKey(settingsPresetSelectTileKey), findsOneWidget);
  });

  testWidgets('设置页展开开发者 2560×3100', (tester) async {
    await _pumpSettings(tester, size: const Size(2560, 3100));
    await tester.tap(find.byKey(settingsDeveloperToggleKey));
    await tester.pumpAndSettle();
    await _capture(tester, 'settings-developer-2560x3100.png');
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

/// 档案卡与「自我描述」都填上真实形状的内容：截图要能看出这是谁的设置页。
Future<AppDatabase> _seedDatabase() async {
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  final settings = SettingsRepository(database);
  await settings.ensureProfile(displayName: '小明');
  await settings.updateUserPersona(
    '我是高三学生，数学想冲 120 分；习惯先看解析再做题，计算容易粗心。',
  );
  return database;
}

Future<void> _pumpSettings(
  WidgetTester tester, {
  required Size size,
}) async {
  // 数据位置行读 AppStorage：每个用例重新注入稳定的假路径并清缓存，
  // 避免上一个用例的 Future 跨 test zone 复用；绝不探测真实的 E:\Furnace\data。
  // 这个脚本本来就是 `flutter test` 跑的（见文件头），只是放在 tool/ 下，
  // 所以 analyzer 不认这里是 test 目录，需要两处 ignore。
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
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: _theme(),
        home: RepaintBoundary(key: _captureKey, child: const SettingsPage()),
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

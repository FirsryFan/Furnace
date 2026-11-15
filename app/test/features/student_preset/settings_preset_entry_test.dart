// task-64：预设选择页在设置页的入口。
//
// 单独一个文件：这里要编译 DB 层（SettingsPage 依赖 appDatabaseProvider），
// 而 asset/页面测试不需要 DB；分开后一个模块的临时编译问题不会连带其它断言。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/features/settings/presentation/settings_page.dart';
import 'package:furnace/features/student_preset/application/preset_selection.dart';
import 'package:furnace/features/student_preset/presentation/preset_select_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<ProviderContainer> pumpSettings(
    WidgetTester tester, {
    PresetSelection? selection,
  }) async {
    // 设置页是一长列 tile：视口够高才不会让目标行根本没被构建。
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    if (selection != null) {
      container.read(presetSelectionProvider.notifier).state = selection;
    }
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
    return container;
  }

  testWidgets('设置里有「预设选择（原型）」，副标题说明诊断且非高考分', (tester) async {
    await pumpSettings(tester);

    // 2026-11-15 设置页重构：预设属于开发者/原型入口，默认折叠。
    expect(find.byKey(settingsPresetSelectTileKey), findsNothing);
    await tester.tap(find.byKey(settingsDeveloperToggleKey));
    await tester.pumpAndSettle();

    expect(find.byKey(settingsPresetSelectTileKey), findsOneWidget);
    expect(find.text('预设选择（原型）'), findsOneWidget);
    expect(find.text('4 档预设 × 3 题小样；诊断用，非高考分'), findsOneWidget);

    await tester.tap(find.byKey(settingsPresetSelectTileKey));
    await tester.pumpAndSettle();

    expect(find.byType(PresetSelectPage), findsOneWidget);
  });

  testWidgets('已选后设置页副标题显示当前档（内存，可随时改）', (tester) async {
    await pumpSettings(
      tester,
      selection: const PresetSelection(
        presetId: 'preset-medium',
        presetName: '中等',
      ),
    );

    await tester.tap(find.byKey(settingsDeveloperToggleKey));
    await tester.pumpAndSettle();

    expect(find.text('已选：中等（内存，可随时改选）'), findsOneWidget);
  });
}

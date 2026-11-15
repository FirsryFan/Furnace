// 入口组件：设置页/主题设置里放 `const MarkdownSettingsTile()` 即可进入
// A4 预览 + Markdown 设置页；入口是独立组件，不依赖设置页内部结构。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/markdown/application/markdown_providers.dart';
import 'package:furnace/features/markdown/presentation/markdown_settings_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

import 'support/markdown_fakes.dart';

void main() {
  testWidgets('MarkdownSettingsTile 打开 Markdown 设置页', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = MemoryMarkdownThemeStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          markdownThemeStoreProvider.overrideWithValue(store),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: MarkdownSettingsTile()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tile = find.byKey(settingsMarkdownTileKey);
    expect(tile, findsOneWidget);
    expect(find.text('Markdown 排版'), findsOneWidget);

    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownSettingsPage), findsOneWidget);
    expect(find.byKey(MarkdownSettingsKeys.previewPaper), findsOneWidget);
    expect(find.byKey(MarkdownSettingsKeys.modeToggle), findsOneWidget);
  });
}

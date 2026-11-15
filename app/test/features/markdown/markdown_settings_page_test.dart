// Markdown 设置页：左 A4 预览 / 右设置、左下角代码↔预览、代码不保存、
// 默认文档重置、预设/标题居中/分栏/页眉页脚等设置即时生效。
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/markdown/application/markdown_providers.dart';
import 'package:furnace/features/markdown/domain/markdown_default_document.dart';
import 'package:furnace/features/markdown/domain/markdown_render_theme.dart';
import 'package:furnace/features/markdown/presentation/markdown_renderer.dart';
import 'package:furnace/features/markdown/presentation/markdown_settings_page.dart';
import 'package:furnace/l10n/app_localizations.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../settings/support/question_pack_fakes.dart';
import 'support/markdown_fakes.dart';

void main() {
  Future<MemoryMarkdownThemeStore> pumpPage(
    WidgetTester tester, {
    MarkdownRenderTheme? seed,
    Size size = const Size(1500, 3400),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = MemoryMarkdownThemeStore(seed);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          markdownThemeStoreProvider.overrideWithValue(store),
          markdownPdfFontResolverProvider
              .overrideWithValue(FakeMarkdownPdfFontResolver()),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MarkdownSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('左侧完整 A4 预览 + 左下角代码/预览切换', (tester) async {
    await pumpPage(tester);

    expect(find.byKey(MarkdownSettingsKeys.previewPane), findsOneWidget);
    expect(find.byKey(MarkdownSettingsKeys.previewPaper), findsOneWidget);
    expect(find.byKey(MarkdownSettingsKeys.modeToggle), findsOneWidget);
    expect(find.byKey(MarkdownSettingsKeys.codeEditor), findsNothing);
    // 默认文档真的被渲染（标题/表格/公式文本都在）。
    expect(find.byType(GptMarkdown), findsWidgets);

    await tester.tap(find.byKey(MarkdownSettingsKeys.modeToggle));
    await tester.pumpAndSettle();
    expect(find.byKey(MarkdownSettingsKeys.codeEditor), findsOneWidget);
    final editor = tester.widget<TextField>(
      find.byKey(MarkdownSettingsKeys.codeEditor),
    );
    expect(editor.controller?.text, defaultMarkdownDocument);
  });

  testWidgets('代码模式可编辑但不保存：再进页面仍是默认文档', (tester) async {
    final store = await pumpPage(tester);
    await tester.tap(find.byKey(MarkdownSettingsKeys.modeToggle));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(MarkdownSettingsKeys.codeEditor),
      '# 临时标题\n\n临时正文（不该被保存）',
    );
    await tester.pumpAndSettle();

    // 切回预览：临时内容进入预览（不落盘）。
    await tester.tap(find.byKey(MarkdownSettingsKeys.modeToggle));
    await tester.pumpAndSettle();
    expect(find.textContaining('临时标题'), findsWidgets);

    // 重建页面（模拟离开再进入）：仍显示默认文档。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          markdownThemeStoreProvider.overrideWithValue(store),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MarkdownSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(MarkdownSettingsKeys.modeToggle));
    await tester.pumpAndSettle();
    final editor = tester.widget<TextField>(
      find.byKey(MarkdownSettingsKeys.codeEditor),
    );
    expect(editor.controller?.text, defaultMarkdownDocument);
    expect(editor.controller?.text, isNot(contains('临时标题')));
  });

  testWidgets('重置默认文档', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(MarkdownSettingsKeys.modeToggle));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(MarkdownSettingsKeys.codeEditor),
      '改掉的内容',
    );
    await tester.tap(find.byKey(MarkdownSettingsKeys.resetDocument));
    await tester.pumpAndSettle();
    final editor = tester.widget<TextField>(
      find.byKey(MarkdownSettingsKeys.codeEditor),
    );
    expect(editor.controller?.text, defaultMarkdownDocument);
  });

  testWidgets('切换预设：纸张背景与主题一起变，并写入存储', (tester) async {
    final store = await pumpPage(tester);
    await tester.tap(
      find.byKey(
        const Key('${MarkdownSettingsKeys.presetChipPrefix}dark'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));

    final paper = tester.widget<Container>(
      find.byKey(MarkdownSettingsKeys.previewPaper),
    );
    final decoration = paper.decoration! as BoxDecoration;
    expect(decoration.color, MarkdownRenderTheme.dark.background);
    expect(store.saves, isNotEmpty);
    expect(store.saves.last.id, 'dark');
  });

  testWidgets('标题居中开关影响预览里的标题对齐', (tester) async {
    await pumpPage(tester);
    expect(find.byType(MarkdownCenteredHeading), findsNothing);
    await tester.tap(find.byKey(MarkdownSettingsKeys.headingCenterSwitch));
    await tester.pumpAndSettle();
    expect(find.byType(MarkdownCenteredHeading), findsWidgets);
  });

  testWidgets('分栏开关：预览变成两栏', (tester) async {
    await pumpPage(tester);
    final before = tester.widgetList<GptMarkdown>(find.byType(GptMarkdown)).length;
    expect(before, 1);
    await tester.tap(find.byKey(MarkdownSettingsKeys.columnsSwitch));
    await tester.pumpAndSettle();
    final after = tester.widgetList<GptMarkdown>(find.byType(GptMarkdown)).length;
    expect(after, greaterThanOrEqualTo(2));
  });

  testWidgets('页眉页脚/页码设置写入主题', (tester) async {
    final store = await pumpPage(tester);
    await tester.enterText(
      find.byKey(MarkdownSettingsKeys.pdfHeaderField),
      '页眉示例',
    );
    await tester.enterText(
      find.byKey(MarkdownSettingsKeys.pdfFooterField),
      '页脚示例',
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    expect(store.saves.last.pdfHeader, '页眉示例');
    expect(store.saves.last.pdfFooter, '页脚示例');
    // 预览页脚出现文本。
    expect(find.text('页脚示例'), findsWidgets);
  });

  testWidgets('缺字体时导出 PDF 明确报不可用，不假装成功', (tester) async {
    final picker = FakeQuestionPackPicker();
    final previous = FilePickerPlatform.instance;
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = previous);

    await pumpPage(tester);
    await tester.tap(find.byKey(MarkdownSettingsKeys.exportPdf));
    await tester.pumpAndSettle();
    expect(picker.saveCalls, 0);
    expect(find.textContaining('PDF 导出不可用'), findsWidgets);
  });

  testWidgets('预览与文档渲染共用统一 renderer', (tester) async {
    await pumpPage(tester);
    expect(find.byType(MarkdownRenderer), findsWidgets);
  });
}

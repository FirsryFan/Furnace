// 统一 Markdown 渲染器：LaTeX、中英文字体、标题居中、表格、代码块行号、
// 全局主题 scope。断言看"树里真实画出来的东西"（Text/RichText/Math 控件），
// 不看截图。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/markdown/domain/markdown_render_theme.dart';
import 'package:furnace/features/markdown/presentation/markdown_renderer.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

/// 树里所有文字（Text/EditableText/RichText）拼起来。
String renderedText(WidgetTester tester) {
  final buffer = StringBuffer();
  for (final widget in tester.allWidgets) {
    if (widget is Text) {
      buffer.writeln(widget.data ?? widget.textSpan?.toPlainText() ?? '');
    } else if (widget is RichText) {
      buffer.writeln(widget.text.toPlainText(includePlaceholders: false));
    }
  }
  return buffer.toString();
}

/// val_latex_flutter 的公式 widget（传递依赖，不直接 import 其包）。
int mathWidgetCount(WidgetTester tester) => tester
    .widgetList(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == 'Math',
        skipOffstage: false,
      ),
    )
    .length;

Future<void> pumpRenderer(
  WidgetTester tester,
  String markdown, {
  MarkdownRenderTheme? theme,
  MarkdownRenderMode mode = MarkdownRenderMode.document,
  ThemeData? appTheme,
  Size size = const Size(1000, 3000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final renderer = MarkdownRenderer(
    markdown: markdown,
    theme: theme,
    mode: mode,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme,
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: theme == null
              ? renderer
              : MarkdownThemeScope(theme: theme, child: renderer),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('LaTeX', () {
    testWidgets(r'行内 $...$ 与块级 $$...$$ 都真正排版，不显示美元定界符', (tester) async {
      await pumpRenderer(
        tester,
        r'已知 $x^2-5x+6=0$，求根。' '\n\n' r'$$' '\n' r'\int_0^1 x^2\,dx' '\n' r'$$',
      );
      expect(tester.takeException(), isNull);
      expect(mathWidgetCount(tester), 2);
      expect(renderedText(tester), isNot(contains(r'$')));
    });

    testWidgets(r'价格里的 $ 不误判为公式（正文保留）', (tester) async {
      await pumpRenderer(tester, r'花了 $5 到 $9。');
      expect(mathWidgetCount(tester), 0);
      expect(renderedText(tester), contains(r'$5'));
    });
  });

  group('主题生效', () {
    testWidgets('中文字体来自全局主题 scope，字号跟随主题', (tester) async {
      final theme = MarkdownRenderTheme.paper.copyWith(
        cjkFontFamily: 'Noto Sans SC',
        fontSize: 20,
      );
      await pumpRenderer(tester, '# 标题\n\n正文', theme: theme);
      final markdown = tester.widget<GptMarkdown>(find.byType(GptMarkdown));
      expect(markdown.style?.fontFamily, 'Noto Sans SC');
      expect(markdown.style?.fontSize, 20);
      expect(markdown.useDollarSignsForLatex, isTrue);
    });

    testWidgets('没有 scope 时退回内置纸张主题，不崩', (tester) async {
      await pumpRenderer(tester, '# 标题\n\n正文');
      final markdown = tester.widget<GptMarkdown>(find.byType(GptMarkdown));
      expect(markdown.style?.fontSize, MarkdownRenderTheme.paper.fontSize);
      expect(tester.takeException(), isNull);
    });

    testWidgets('链接颜色与表格斑马纹来自主题', (tester) async {
      final theme = MarkdownRenderTheme.sepia.copyWith(
        tableStriped: true,
      );
      await pumpRenderer(
        tester,
        '[链接](https://example.com)\n\n| 甲 | 乙 |\n| --- | --- |\n| 1 | 2 |',
        theme: theme,
      );
      final markdown = tester.widget<GptMarkdown>(find.byType(GptMarkdown));
      expect(markdown.styleSheet?.link?.color, theme.linkColor);
      expect(
        markdown.styleSheet?.table?.rowStripeColor,
        theme.tableRowStripe,
      );
      expect(
        markdown.styleSheet?.table?.headerBackground,
        theme.tableHeaderBackground,
      );
    });

    testWidgets('surface 模式颜色跟软件主题走，排版仍跟 Markdown 主题', (tester) async {
      final theme = MarkdownRenderTheme.paper.copyWith(fontSize: 19);
      final appTheme = ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3D8B63),
          brightness: Brightness.dark,
        ),
      );
      await pumpRenderer(
        tester,
        '[链接](https://example.com)',
        theme: theme,
        mode: MarkdownRenderMode.surface,
        appTheme: appTheme,
      );
      final markdown = tester.widget<GptMarkdown>(find.byType(GptMarkdown));
      expect(markdown.style?.fontSize, 19);
      expect(
        markdown.styleSheet?.link?.color,
        appTheme.colorScheme.primary,
        reason: '界面内联模式必须跟随当前软件主题，否则深色界面下看不清',
      );
    });

    testWidgets('标题居中来自主题 headingAlignment', (tester) async {
      final centered = MarkdownRenderTheme.paper.copyWith(
        headingAlignment: MarkdownHeadingAlignment.center,
      );
      await pumpRenderer(tester, '# 居中标题', theme: centered);
      expect(find.byType(MarkdownCenteredHeading), findsWidgets);

      final left = MarkdownRenderTheme.paper.copyWith(
        headingAlignment: MarkdownHeadingAlignment.start,
      );
      await pumpRenderer(tester, '# 左对齐标题', theme: left);
      expect(find.byType(MarkdownCenteredHeading), findsNothing);
    });

    testWidgets('代码块行号开关只影响代码块，不丢代码', (tester) async {
      const code = '```dart\nfinal x = 1;\nfinal y = 2;\n```';
      final withNumbers = MarkdownRenderTheme.paper.copyWith(
        codeShowLineNumbers: true,
      );
      await pumpRenderer(tester, code, theme: withNumbers);
      expect(
        find.byType(MarkdownCodeLineNumbersGutter),
        findsOneWidget,
      );
      final text = renderedText(tester);
      expect(text, contains('final x = 1;'));
      expect(text, contains('final y = 2;'));

      await pumpRenderer(tester, code, theme: MarkdownRenderTheme.paper);
      expect(find.byType(MarkdownCodeLineNumbersGutter), findsNothing);
      expect(renderedText(tester), contains('final x = 1;'));
    });
  });
}

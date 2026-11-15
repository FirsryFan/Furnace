// 统一 Markdown 主题：4 套旧主题迁移为预置、JSON 往返、坏值夹取、分栏切分。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/markdown/domain/markdown_columns.dart';
import 'package:furnace/features/markdown/domain/markdown_render_theme.dart';

void main() {
  group('预置', () {
    test('4 套旧主题迁移为预置，id/名称/背景不同', () {
      expect(
        MarkdownRenderTheme.all.map((theme) => theme.id),
        <String>['paper', 'sepia', 'dark', 'compact'],
      );
      expect(
        MarkdownRenderTheme.all.map((theme) => theme.name),
        <String>['纸张', '护眼', '深色', '紧凑'],
      );
      expect(
        MarkdownRenderTheme.all.map((theme) => theme.background).toSet(),
        hasLength(4),
      );
      for (final theme in MarkdownRenderTheme.all) {
        expect(theme.codeBackground, isNot(theme.background));
        expect(theme.foreground, isNot(theme.background));
      }
    });

    test('旧主题的排版差异保留：字号/行距/页边距', () {
      expect(
        MarkdownRenderTheme.compact.fontSize,
        lessThan(MarkdownRenderTheme.paper.fontSize),
      );
      expect(
        MarkdownRenderTheme.compact.lineHeight,
        lessThan(MarkdownRenderTheme.paper.lineHeight),
      );
      expect(
        MarkdownRenderTheme.compact.pageMargin,
        lessThan(MarkdownRenderTheme.paper.pageMargin),
      );
      expect(MarkdownRenderTheme.paper.headingRule, isTrue);
      expect(MarkdownRenderTheme.compact.headingRule, isFalse);
      expect(MarkdownRenderTheme.dark.isDark, isTrue);
      expect(MarkdownRenderTheme.sepia.tableStriped, isTrue);
    });

    test('未知 id 退回纸张主题', () {
      expect(MarkdownRenderTheme.byId('nope').id, 'paper');
      expect(MarkdownRenderTheme.byId(null).id, 'paper');
      expect(MarkdownRenderTheme.byId('dark').id, 'dark');
    });

    test('每个预置都带中英文字体与代码字体候选', () {
      for (final theme in MarkdownRenderTheme.all) {
        expect(theme.bodyFontFallback, isNotEmpty);
        expect(MarkdownRenderTheme.monoFontOptions, contains('系统默认'));
      }
      expect(MarkdownRenderTheme.cjkFontOptions, contains('Noto Sans SC'));
      expect(MarkdownRenderTheme.latinFontOptions, contains('Segoe UI'));
    });
  });

  group('JSON 往返', () {
    test('toJson → fromJson 保留每一个字段', () {
      final theme = MarkdownRenderTheme.sepia.copyWith(
        cjkFontFamily: 'Noto Sans SC',
        latinFontFamily: 'Georgia',
        monoFontFamily: 'Cascadia Mono',
        fontSize: 18,
        lineHeight: 1.9,
        paragraphSpacing: 0.8,
        headingScale: 1.2,
        headingWeight: 800,
        headingAlignment: MarkdownHeadingAlignment.center,
        headingRule: true,
        tableBorderVisible: false,
        tableBorderWidth: 1.5,
        tableStriped: true,
        tableCompact: true,
        codeShowLineNumbers: true,
        codeFontScale: 1.1,
        codeRadius: 8,
        showCodeCopyButton: false,
        pageMargin: 80,
        columnsEnabled: true,
        columnCount: 2,
        columnGap: 32,
        columnRule: false,
        showPageNumber: false,
        pdfHeader: '页眉',
        pdfFooter: '页脚',
      );
      final restored = MarkdownRenderTheme.fromJson(theme.toJson());
      expect(restored, theme);
      expect(restored.cjkFontFamily, 'Noto Sans SC');
      expect(restored.headingAlignment, MarkdownHeadingAlignment.center);
      expect(restored.columnsEnabled, isTrue);
      expect(restored.pdfHeader, '页眉');
    });

    test('坏值/越界夹回安全范围；版本不符退回预设', () {
      final json = <String, Object?>{
        ...MarkdownRenderTheme.paper.toJson(),
        'fontSize': 999,
        'lineHeight': 0.1,
        'headingWeight': 5000,
        'columnCount': 9,
        'pageMargin': 9999,
        'headingAlignment': 'diagonal',
      };
      final restored = MarkdownRenderTheme.fromJson(json);
      expect(restored.fontSize, MarkdownRenderLimits.maxFontSize);
      expect(restored.lineHeight, MarkdownRenderLimits.minLineHeight);
      expect(restored.headingWeight, MarkdownRenderLimits.maxHeadingWeight);
      expect(restored.columnCount, 3);
      expect(restored.pageMargin, MarkdownRenderLimits.maxPageMargin);
      expect(restored.headingAlignment, MarkdownHeadingAlignment.start);

      final wrongVersion = <String, Object?>{
        ...MarkdownRenderTheme.paper.toJson(),
        'version': 999,
      };
      expect(MarkdownRenderTheme.fromJson(wrongVersion).id, 'paper');
    });

    test('surface 模式用软件主题颜色，排版参数保留', () {
      final theme = MarkdownRenderTheme.dark.copyWith(fontSize: 20);
      final surface = theme.forSurface(
        ColorScheme.fromSeed(seedColor: const Color(0xFF2F6F4F)),
        isDark: false,
      );
      expect(surface.fontSize, 20);
      expect(surface.isDark, isFalse);
      expect(surface.foreground, isNot(theme.foreground));
      expect(surface.linkColor, isNot(theme.linkColor));
      expect(surface.paperShadow, isFalse);
    });
  });

  group('分栏切分', () {
    test('两栏都非空、顺序保留、代码围栏不被拆开', () {
      const source = '# 一\n\n第一段。\n\n```dart\nvoid main() {}\n```\n\n'
          '## 二\n\n第二段。\n\n第三段。\n';
      final chunks = splitMarkdownIntoColumns(source, 2);
      expect(chunks, hasLength(2));
      expect(chunks[0].trim(), isNotEmpty);
      expect(chunks[1].trim(), isNotEmpty);
      // 代码围栏必须完整落在某一栏里。
      final joined = chunks.join('\n');
      expect('```'.allMatches(joined).length, 2);
      expect(joined.contains('void main()'), isTrue);
      expect(joined.contains('第二段'), isTrue);
    });

    test('单栏/空文档原样返回', () {
      expect(splitMarkdownIntoColumns('abc', 1), <String>['abc']);
      expect(splitMarkdownIntoColumns('', 2), <String>['']);
    });
  });
}

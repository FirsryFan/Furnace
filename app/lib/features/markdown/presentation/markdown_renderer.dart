/// 全软件唯一的 Markdown 渲染入口。
///
/// 所有 Markdown 显示——AI 消息、题目详情、闪存卡题干/答案、设置页 A4 预览、
/// PDF 的排版参数——都走这里。底层用 `gpt_markdown` 解析并排版：
///
///  * 支持 **LaTeX** `$...$`（行内）与 `$$...$$`（块级），由
///    `useDollarSignsForLatex` 打开，公式交给 `val_latex_flutter` 真正排版；
///  * 颜色、字体、字号、行距、标题字号/字重/居中、表格边框/斑马纹/紧凑、
///    代码块字体/背景/边框/行号、引用、列表、任务框、图片、公式样式全部来自
///    [MarkdownRenderTheme]；
///  * [MarkdownRenderMode.surface] 用于界面内联：颜色从当前 `ColorScheme`
///    推导，避免深色界面里看不清；[MarkdownRenderMode.document] 用于纸张
///    （A4 预览/PDF）：颜色与页面参数完全来自主题。
///
/// 全局主题通过 [MarkdownThemeScope] 向下传递（`FurnaceApp` 在根部挂载）；
/// 没有 scope 时退回内置 `paper` 预设，所以单独 pump 一个组件的测试不需要
/// ProviderScope。
library;

import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../domain/markdown_render_theme.dart';

/// 代码块行号栏（测试可按类型定位；不能用固定 Key——正文里可能有多个代码块）。
class MarkdownCodeLineNumbersGutter extends StatelessWidget {
  const MarkdownCodeLineNumbersGutter({
    super.key,
    required this.lineCount,
    required this.style,
    required this.padding,
  });

  final int lineCount;
  final TextStyle style;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var index = 0; index < lineCount; index++)
            Text('${index + 1}', style: style),
        ],
      ),
    );
  }
}

/// 居中标题的外层容器（测试可按类型定位；同一文档会有多个标题）。
class MarkdownCenteredHeading extends StatelessWidget {
  const MarkdownCenteredHeading({
    super.key,
    required this.child,
    required this.dividerColor,
    required this.showDivider,
    required this.dividerPadding,
  });

  final Widget child;
  final Color dividerColor;
  final bool showDivider;
  final EdgeInsetsGeometry dividerPadding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Align(alignment: Alignment.center, child: child),
          if (showDivider)
            Padding(
              padding: dividerPadding,
              child: Container(height: 1, color: dividerColor),
            ),
        ],
      ),
    );
  }
}

/// 把当前全局 Markdown 主题传给子树。
class MarkdownThemeScope extends InheritedWidget {
  const MarkdownThemeScope({
    super.key,
    required this.theme,
    required super.child,
  });

  final MarkdownRenderTheme theme;

  static MarkdownRenderTheme? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MarkdownThemeScope>()?.theme;

  static MarkdownRenderTheme of(BuildContext context) =>
      maybeOf(context) ?? MarkdownRenderTheme.fallback;

  @override
  bool updateShouldNotify(MarkdownThemeScope oldWidget) =>
      theme != oldWidget.theme;
}

/// 统一 Markdown 渲染器。
class MarkdownRenderer extends StatelessWidget {
  const MarkdownRenderer({
    super.key,
    required this.markdown,
    this.theme,
    this.style,
    this.textAlign,
    this.mode = MarkdownRenderMode.surface,
    this.onLinkTap,
    this.onImageTap,
    this.imageBuilder,
  });

  /// 要渲染的 Markdown 源码。
  final String markdown;

  /// 显式主题；null 时用 [MarkdownThemeScope] 的全局主题，再退回 paper。
  final MarkdownRenderTheme? theme;

  /// 正文基础样式（调用方页面自己的字号/字色）。排版类参数仍由主题补足。
  final TextStyle? style;

  /// 段落对齐方式；null = 主题默认（start）。
  final TextAlign? textAlign;

  final MarkdownRenderMode mode;

  final void Function(String url, String title)? onLinkTap;
  final void Function(String url)? onImageTap;

  /// 图片构造器：Markdown 里的 `![alt](url)` 交给它画。
  ///
  /// 题目详情/卡片用它把本地题干图（`question-image:N`）画成行内小图；不传时
  /// 走包内默认加载（`data:` URL 或网络地址）。调用方要保证自己认得这些 url，
  /// 否则离线环境会触发一次网络加载。
  final ImageBuilder? imageBuilder;

  @override
  Widget build(BuildContext context) {
    final localTheme = Theme.of(context);
    final document = mode == MarkdownRenderMode.document;
    final resolved =
        theme ?? MarkdownThemeScope.maybeOf(context) ?? MarkdownRenderTheme.fallback;
    final effective = document
        ? resolved
        : resolved.forSurface(
            localTheme.colorScheme,
            isDark: localTheme.brightness == Brightness.dark,
          );

    final baseStyle = (style ?? const TextStyle()).merge(
      TextStyle(
        fontFamily: effective.cjkFontFamily,
        fontFamilyFallback: effective.bodyFontFallback,
        fontSize: style?.fontSize ?? effective.fontSize,
        height: effective.lineHeight,
        color: style?.color ?? effective.foreground,
      ),
    );
    final baseSize = baseStyle.fontSize ?? effective.fontSize;

    final headingStyles = <TextStyle>[
      for (final scale in markdownHeadingScale)
        baseStyle.copyWith(
          fontSize: baseSize * scale * effective.headingScale,
          fontWeight: _weightOf(effective.headingWeight),
          color: effective.headingColor,
          height: effective.lineHeight.clamp(1.15, 2.0),
          fontFamily: effective.cjkFontFamily,
          fontFamilyFallback: effective.bodyFontFallback,
        ),
    ];

    final styleSheet = _styleSheet(effective, document: document);

    final gptTheme = GptMarkdownThemeData(
      brightness: effective.isDark ? Brightness.dark : Brightness.light,
      h1: headingStyles[0],
      h2: headingStyles[1],
      h3: headingStyles[2],
      h4: headingStyles[3],
      h5: headingStyles[4],
      h6: headingStyles[5],
      hrLineThickness: 1,
      hrLineColor: effective.ruleColor,
      hrLinePadding: EdgeInsets.zero,
      linkColor: effective.linkColor,
      linkHoverColor: effective.linkColor,
      autoAddDividerLineAfterH1: effective.headingRule,
      inlineCode: _inlineCodeStyle(effective),
      styleSheet: styleSheet,
    );

    final headingBuilder =
        effective.headingAlignment == MarkdownHeadingAlignment.center
            ? _centeredHeadingBuilder(effective)
            : null;

    return GptMarkdownTheme(
      gptThemeData: gptTheme,
      child: SelectionArea(
        child: GptMarkdown(
          markdown,
          style: baseStyle,
          textAlign: textAlign ?? TextAlign.start,
          useDollarSignsForLatex: true,
          styleSheet: styleSheet,
          inlineCodeStyle: _inlineCodeStyle(effective),
          headingBuilder: headingBuilder,
          codeBuilder: effective.codeShowLineNumbers
              ? _lineNumberedCodeBuilder(effective)
              : null,
          onLinkTap: onLinkTap,
          onImageTap: onImageTap,
          imageBuilder: imageBuilder,
        ),
      ),
    );
  }

  static FontWeight _weightOf(int weight) {
    final index = ((weight / 100).round() - 1).clamp(0, 8);
    return FontWeight.values[index];
  }

  static InlineCodeStyle _inlineCodeStyle(MarkdownRenderTheme theme) =>
      InlineCodeStyle(
        fontFamily: theme.monoFontFamily,
        fontFamilyFallback: MarkdownRenderTheme.monoFontFallback,
        fontSizeFactor: theme.codeFontScale,
        fontWeight: FontWeight.w400,
        color: theme.codeForeground,
        backgroundColor: theme.inlineCodeBackground,
        borderRadius: const Radius.circular(3),
        padding: EdgeInsets.symmetric(
          horizontal: theme.fontSize * 0.2,
          vertical: theme.fontSize * 0.02,
        ),
      );

  static GptMarkdownStyleSheet _styleSheet(
    MarkdownRenderTheme theme, {
    required bool document,
  }) {
    final borderWidth =
        theme.tableBorderVisible ? theme.tableBorderWidth : 0.0;
    final borderColor =
        theme.tableBorderVisible ? theme.tableBorder : Colors.transparent;
    final cellVertical = theme.tableCompact
        ? theme.fontSize * 0.16
        : theme.fontSize * 0.3;

    return GptMarkdownStyleSheet(
      blockSpacing: theme.fontSize * theme.paragraphSpacing,
      blockQuote: BlockQuoteStyle(
        barWidth: 3,
        barColor: theme.quoteBar,
        backgroundColor: theme.quoteBackground,
        padding: EdgeInsets.fromLTRB(
          theme.fontSize * 0.7,
          theme.fontSize * 0.5,
          theme.fontSize * 0.5,
          theme.fontSize * 0.2,
        ),
        margin: EdgeInsets.only(
          top: theme.fontSize * 0.15,
          bottom: theme.fontSize * 0.5,
        ),
        textStyle: TextStyle(color: theme.quoteForeground),
      ),
      heading: HeadingStyle(
        showDivider: theme.headingRule,
        dividerColor: theme.ruleColor,
        dividerThickness: 1,
        dividerPadding: EdgeInsets.only(top: theme.fontSize * 0.2),
      ),
      link: LinkStyle(color: theme.linkColor),
      inlineCode: _inlineCodeStyle(theme),
      list: ListStyle(
        bulletColor: theme.bulletColor,
        markerTextStyle: TextStyle(
          color: theme.mutedForeground,
          fontWeight: FontWeight.w400,
        ),
      ),
      checkbox: CheckboxStyle(
        checkedColor: theme.checkboxColor,
        uncheckedColor: theme.mutedForeground,
        checkColor: theme.background,
      ),
      codeBlock: CodeBlockStyle(
        backgroundColor: theme.codeBackground,
        borderColor: borderColor,
        borderWidth: borderWidth,
        borderRadius: Radius.circular(theme.codeRadius),
        padding: EdgeInsets.all(theme.fontSize * 0.75),
        fontFamily: theme.monoFontFamily,
        fontSize: theme.fontSize * theme.codeFontScale,
        textColor: theme.codeForeground,
        showLanguageLabel: true,
        languageStyle: TextStyle(
          color: theme.mutedForeground,
          fontSize: theme.fontSize * 0.68,
          fontWeight: FontWeight.w600,
        ),
        // 纸张/PDF 不需要复制按钮；界面里默认保留。
        showCopyButton: theme.showCodeCopyButton && !document,
        copyLabel: '复制代码',
        copiedLabel: '已复制',
      ),
      table: TableStyle(
        borderColor: borderColor,
        borderWidth: borderWidth,
        borderRadius: const Radius.circular(4),
        cellPadding: EdgeInsets.symmetric(
          horizontal: theme.fontSize * (theme.tableCompact ? 0.4 : 0.6),
          vertical: cellVertical,
        ),
        headerBackground: theme.tableHeaderBackground,
        headerTextStyle: TextStyle(
          fontWeight: FontWeight.w700,
          color: theme.headingColor,
        ),
        rowStripeColor: theme.tableStriped ? theme.tableRowStripe : null,
        overflow: document ? TableOverflow.wrap : TableOverflow.scroll,
      ),
      image: const ImageStyle(
        borderRadius: Radius.circular(4),
        fit: BoxFit.contain,
        maxHeight: 480,
      ),
      hr: HrStyle(thickness: 1, color: theme.ruleColor),
      latex: LatexStyle(
        textStyle: TextStyle(color: theme.foreground),
        padding: EdgeInsets.symmetric(vertical: theme.fontSize * 0.4),
        scrollBlockHorizontally: true,
      ),
    );
  }

  /// 标题居中：包一层占满宽度的 Column，并在 h1 下补回主题要求的分隔线。
  static HeadingBuilder _centeredHeadingBuilder(MarkdownRenderTheme theme) {
    return (context, level, content, style) {
      return MarkdownCenteredHeading(
        showDivider: level == 1 && theme.headingRule,
        dividerColor: theme.ruleColor,
        dividerPadding: EdgeInsets.only(top: theme.fontSize * 0.2),
        child: content,
      );
    };
  }

  /// 代码块行号：默认渲染器带语法高亮但没有行号；打开行号时改用等宽纯文本
  /// + 独立行号栏（不使用包内私有控件，也不额外引入高亮依赖）。
  static CodeBlockBuilder _lineNumberedCodeBuilder(MarkdownRenderTheme theme) {
    return (context, language, code, closed) {
      final mono = TextStyle(
        color: theme.codeForeground,
        fontSize: theme.fontSize * theme.codeFontScale,
        fontFamily: theme.monoFontFamily,
        fontFamilyFallback: MarkdownRenderTheme.monoFontFallback,
        height: 1.45,
      );
      final lines = code.trimRight().split('\n');
      final numberStyle = mono.copyWith(
        color: theme.mutedForeground,
        fontWeight: FontWeight.w400,
      );
      return Container(
        width: double.infinity,
        margin: EdgeInsets.only(bottom: theme.fontSize * 0.5),
        padding: EdgeInsets.all(theme.fontSize * 0.75),
        decoration: BoxDecoration(
          color: theme.codeBackground,
          borderRadius: BorderRadius.circular(theme.codeRadius),
          border: theme.tableBorderVisible
              ? Border.all(
                  color: theme.tableBorder,
                  width: theme.tableBorderWidth,
                )
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            MarkdownCodeLineNumbersGutter(
              lineCount: lines.length,
              style: numberStyle,
              padding: EdgeInsets.only(right: theme.fontSize * 0.5),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(lines.join('\n'), style: mono),
              ),
            ),
          ],
        ),
      );
    };
  }
}

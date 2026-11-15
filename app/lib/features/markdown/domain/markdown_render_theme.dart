/// 全软件统一的 Markdown 渲染主题。
///
/// 这是"Markdown 只有一套"的单一事实来源：AI 消息、题目详情、闪存卡题干、
/// 设置页的 A4 预览、PDF 导出，全部从同一个 [MarkdownRenderTheme] 取颜色、
/// 字体、字号、行距、标题、表格、代码块、分栏和 PDF 页面参数。
///
/// 两种使用模式（见 `MarkdownRenderMode`）：
///
///  * **surface**（软件界面里）：颜色从当前 `ColorScheme` 推导，保证深色/浅色
///    软件主题下都读得清；字体/字号/标题/表格/代码块等排版参数仍来自本主题。
///  * **document**（纸张）：颜色、纸张、页边距、页眉页脚都来自本主题，用于
///    设置页的 A4 预览与 PDF，保证"看到的就是导出的"。
///
/// 主题以整份 JSON 存到应用支持目录（`markdown/theme.json`），不新增 DB
/// schema；[MarkdownRenderLimits] 负责把坏数据夹回安全范围。
library;

import 'package:flutter/material.dart';

/// 标题对齐方式：左对齐或居中。
enum MarkdownHeadingAlignment {
  start,
  center;

  static MarkdownHeadingAlignment fromName(String? value) => switch (value) {
        'center' => MarkdownHeadingAlignment.center,
        _ => MarkdownHeadingAlignment.start,
      };

  String get name => this == MarkdownHeadingAlignment.center ? 'center' : 'start';
}

/// 主题的使用场景：界面内联 vs 纸张文档。
enum MarkdownRenderMode { surface, document }

/// 标题相对正文的字号倍数（h1..h6）。预览、界面与 PDF 共用，避免三处不同。
const List<double> markdownHeadingScale = <double>[
  1.8,
  1.5,
  1.3,
  1.15,
  1.05,
  1.0,
];

/// 可调的排版范围。滑块、JSON 反序列化都引用这里，避免两处漂移。
class MarkdownRenderLimits {
  const MarkdownRenderLimits._();

  static const double minFontSize = 12;
  static const double maxFontSize = 24;
  static const double fontSizeStep = 1;

  static const double minLineHeight = 1.2;
  static const double maxLineHeight = 2.4;
  static const double lineHeightStep = 0.1;

  static const double minParagraphSpacing = 0;
  static const double maxParagraphSpacing = 1.5;
  static const double paragraphSpacingStep = 0.05;

  static const double minHeadingScale = 0.8;
  static const double maxHeadingScale = 1.4;
  static const double headingScaleStep = 0.05;

  static const double minTableBorderWidth = 0;
  static const double maxTableBorderWidth = 2;
  static const double tableBorderWidthStep = 0.5;

  static const double minCodeFontScale = 0.7;
  static const double maxCodeFontScale = 1.2;
  static const double codeFontScaleStep = 0.05;

  static const double minCodeRadius = 0;
  static const double maxCodeRadius = 12;
  static const double codeRadiusStep = 2;

  static const double minPageMargin = 24;
  static const double maxPageMargin = 120;
  static const double pageMarginStep = 4;

  static const double minColumnGap = 8;
  static const double maxColumnGap = 64;
  static const double columnGapStep = 4;

  static const int minHeadingWeight = 400;
  static const int maxHeadingWeight = 900;
  static const int headingWeightStep = 100;

  static double clampFontSize(double value) =>
      value.clamp(minFontSize, maxFontSize).toDouble();

  static double clampLineHeight(double value) =>
      value.clamp(minLineHeight, maxLineHeight).toDouble();

  static double clampParagraphSpacing(double value) =>
      value.clamp(minParagraphSpacing, maxParagraphSpacing).toDouble();

  static double clampHeadingScale(double value) =>
      value.clamp(minHeadingScale, maxHeadingScale).toDouble();

  static double clampTableBorderWidth(double value) =>
      value.clamp(minTableBorderWidth, maxTableBorderWidth).toDouble();

  static double clampCodeFontScale(double value) =>
      value.clamp(minCodeFontScale, maxCodeFontScale).toDouble();

  static double clampCodeRadius(double value) =>
      value.clamp(minCodeRadius, maxCodeRadius).toDouble();

  static double clampPageMargin(double value) =>
      value.clamp(minPageMargin, maxPageMargin).toDouble();

  static double clampColumnGap(double value) =>
      value.clamp(minColumnGap, maxColumnGap).toDouble();

  static int clampHeadingWeight(int value) => value
      .clamp(minHeadingWeight, maxHeadingWeight)
      .toInt();

  static int clampColumnCount(int value) => value.clamp(2, 3).toInt();
}

/// 一套 Markdown 渲染主题：颜色 + 版式 + 纸张/PDF 参数。
@immutable
class MarkdownRenderTheme {
  const MarkdownRenderTheme({
    required this.id,
    required this.name,
    required this.nameEn,
    required this.background,
    required this.foreground,
    required this.mutedForeground,
    required this.headingColor,
    required this.codeBackground,
    required this.codeForeground,
    required this.inlineCodeBackground,
    required this.tableHeaderBackground,
    required this.tableBorder,
    required this.tableRowStripe,
    required this.quoteBar,
    required this.quoteBackground,
    required this.quoteForeground,
    required this.linkColor,
    required this.ruleColor,
    required this.bulletColor,
    required this.checkboxColor,
    required this.cjkFontFamily,
    required this.latinFontFamily,
    required this.monoFontFamily,
    required this.fontSize,
    required this.lineHeight,
    required this.paragraphSpacing,
    required this.headingScale,
    required this.headingWeight,
    required this.headingAlignment,
    required this.headingRule,
    required this.tableBorderVisible,
    required this.tableBorderWidth,
    required this.tableStriped,
    required this.tableCompact,
    required this.codeShowLineNumbers,
    required this.codeFontScale,
    required this.codeRadius,
    required this.showCodeCopyButton,
    required this.pageMargin,
    required this.columnsEnabled,
    required this.columnCount,
    required this.columnGap,
    required this.columnRule,
    required this.showPageNumber,
    required this.pdfHeader,
    required this.pdfFooter,
    required this.isDark,
    required this.paperShadow,
  });

  // ---------------------------------------------------------------- 标识
  final String id;
  final String name;
  final String nameEn;

  // ---------------------------------------------------------------- 颜色
  final Color background;
  final Color foreground;
  final Color mutedForeground;
  final Color headingColor;
  final Color codeBackground;
  final Color codeForeground;
  final Color inlineCodeBackground;
  final Color tableHeaderBackground;
  final Color tableBorder;
  final Color tableRowStripe;
  final Color quoteBar;
  final Color quoteBackground;
  final Color quoteForeground;
  final Color linkColor;
  final Color ruleColor;
  final Color bulletColor;
  final Color checkboxColor;

  // ---------------------------------------------------------------- 字体
  /// 中文正文主字体；null = 系统默认。允许 fonts 资产外的系统字体名（按名回退）。
  final String? cjkFontFamily;

  /// 英文字体；null = 系统默认。作为 [cjkFontFamily] 的回退。
  final String? latinFontFamily;

  /// 等宽字体（代码块/行内代码）。
  final String? monoFontFamily;

  // ---------------------------------------------------------------- 版式
  final double fontSize;
  final double lineHeight;

  /// 段间距（正文字号倍数）。
  final double paragraphSpacing;

  /// 标题字号在 [markdownHeadingScale] 之上的整体倍数。
  final double headingScale;
  final int headingWeight;
  final MarkdownHeadingAlignment headingAlignment;

  /// 一级标题下方是否画分隔线。
  final bool headingRule;

  // ---------------------------------------------------------------- 表格
  final bool tableBorderVisible;
  final double tableBorderWidth;
  final bool tableStriped;
  final bool tableCompact;

  // ---------------------------------------------------------------- 代码块
  final bool codeShowLineNumbers;
  final double codeFontScale;
  final double codeRadius;

  /// 界面内代码块是否显示复制按钮（纸张/PDF 不显示）。
  final bool showCodeCopyButton;

  // ---------------------------------------------------------------- 纸张/PDF
  /// A4 页边距（逻辑像素；PDF 按 96dpi→72pt 换算）。
  final double pageMargin;

  final bool columnsEnabled;
  final int columnCount;
  final double columnGap;
  final bool columnRule;
  final bool showPageNumber;
  final String pdfHeader;
  final String pdfFooter;

  final bool isDark;
  final bool paperShadow;

  /// 内置字体候选。打包的 Noto Sans SC 在 PDF 里嵌入；界面里按名匹配，缺失
  /// 时 Flutter 会回退到系统字体。
  static const List<String> cjkFontOptions = <String>[
    '系统默认',
    'Microsoft YaHei',
    'Noto Sans SC',
    'PingFang SC',
    'Source Han Sans SC',
    'SimHei',
    'SimSun',
  ];

  static const List<String> latinFontOptions = <String>[
    '系统默认',
    'Segoe UI',
    'Georgia',
    'Times New Roman',
    'Arial',
    'Cambria',
  ];

  static const List<String> monoFontOptions = <String>[
    '系统默认',
    'Consolas',
    'Cascadia Mono',
    'JetBrains Mono',
    'Menlo',
    'DejaVu Sans Mono',
  ];

  /// 中文回退链：选了中文字体时，缺字形按顺序找；`Segoe UI Symbol` 兜住
  /// 任务清单的 ☐/☑。
  static const List<String> _cjkFallbacks = <String>[
    'Microsoft YaHei',
    'Noto Sans SC',
    'PingFang SC',
    'Source Han Sans SC',
    'Segoe UI',
    'Segoe UI Symbol',
  ];

  static const List<String> _monoFallbacks = <String>[
    'Consolas',
    'Cascadia Mono',
    'JetBrains Mono',
    'Menlo',
    'DejaVu Sans Mono',
    'monospace',
  ];

  /// 界面字体：中文主字体 + 英文回退 + 中文回退链。
  List<String> get bodyFontFallback {
    final fallbacks = <String>[];
    final latin = latinFontFamily;
    if (latin != null && latin != cjkFontFamily) {
      fallbacks.add(latin);
    }
    for (final family in _cjkFallbacks) {
      if (family != cjkFontFamily && !fallbacks.contains(family)) {
        fallbacks.add(family);
      }
    }
    return fallbacks;
  }

  /// 等宽回退链。
  static const List<String> monoFontFallback = _monoFallbacks;

  /// 全部内置预设：原来的 4 套 Typora 式主题迁移为预置。
  static const List<MarkdownRenderTheme> all = <MarkdownRenderTheme>[
    paper,
    sepia,
    dark,
    compact,
  ];

  static MarkdownRenderTheme get fallback => paper;

  /// 按 id 取预设；未知 id 退回 [paper]（坏数据不崩）。
  static MarkdownRenderTheme byId(String? id) {
    for (final theme in all) {
      if (theme.id == id) {
        return theme;
      }
    }
    return paper;
  }

  /// 纸张：白底黑字、GitHub 式代码/表格配色（原 paper）。
  static const MarkdownRenderTheme paper = MarkdownRenderTheme(
    id: 'paper',
    name: '纸张',
    nameEn: 'Paper',
    background: Color(0xFFFFFFFF),
    foreground: Color(0xFF1F2328),
    mutedForeground: Color(0xFF57606A),
    headingColor: Color(0xFF1F2328),
    codeBackground: Color(0xFFF6F8FA),
    codeForeground: Color(0xFF24292F),
    inlineCodeBackground: Color(0xFFF0F2F4),
    tableHeaderBackground: Color(0xFFF6F8FA),
    tableBorder: Color(0xFFD0D7DE),
    tableRowStripe: Color(0xFFF8F9FA),
    quoteBar: Color(0xFFD0D7DE),
    quoteBackground: Color(0xFFF6F8FA),
    quoteForeground: Color(0xFF57606A),
    linkColor: Color(0xFF0969DA),
    ruleColor: Color(0xFFD0D7DE),
    bulletColor: Color(0xFF57606A),
    checkboxColor: Color(0xFF0969DA),
    cjkFontFamily: null,
    latinFontFamily: 'Segoe UI',
    monoFontFamily: 'Consolas',
    fontSize: 16,
    lineHeight: 1.7,
    paragraphSpacing: 0.65,
    headingScale: 1,
    headingWeight: 700,
    headingAlignment: MarkdownHeadingAlignment.start,
    headingRule: true,
    tableBorderVisible: true,
    tableBorderWidth: 1,
    tableStriped: false,
    tableCompact: false,
    codeShowLineNumbers: false,
    codeFontScale: 0.9,
    codeRadius: 4,
    showCodeCopyButton: true,
    pageMargin: 64,
    columnsEnabled: false,
    columnCount: 2,
    columnGap: 24,
    columnRule: true,
    showPageNumber: true,
    pdfHeader: '',
    pdfFooter: '',
    isDark: false,
    paperShadow: true,
  );

  /// 护眼（Sepia）：米黄纸、棕字（原 sepia）。
  static const MarkdownRenderTheme sepia = MarkdownRenderTheme(
    id: 'sepia',
    name: '护眼',
    nameEn: 'Sepia',
    background: Color(0xFFF4ECD8),
    foreground: Color(0xFF3B3127),
    mutedForeground: Color(0xFF6B5B43),
    headingColor: Color(0xFF2E2620),
    codeBackground: Color(0xFFE8DDC4),
    codeForeground: Color(0xFF3B3127),
    inlineCodeBackground: Color(0xFFE3D6B8),
    tableHeaderBackground: Color(0xFFEADFC8),
    tableBorder: Color(0xFFC9B998),
    tableRowStripe: Color(0xFFF0E7D2),
    quoteBar: Color(0xFFB8A277),
    quoteBackground: Color(0xFFEFE5CD),
    quoteForeground: Color(0xFF6B5B43),
    linkColor: Color(0xFF8A5A2B),
    ruleColor: Color(0xFFC9B998),
    bulletColor: Color(0xFF6B5B43),
    checkboxColor: Color(0xFF8A5A2B),
    cjkFontFamily: null,
    latinFontFamily: 'Georgia',
    monoFontFamily: 'Consolas',
    fontSize: 16.5,
    lineHeight: 1.85,
    paragraphSpacing: 0.7,
    headingScale: 1,
    headingWeight: 700,
    headingAlignment: MarkdownHeadingAlignment.start,
    headingRule: false,
    tableBorderVisible: true,
    tableBorderWidth: 1,
    tableStriped: true,
    tableCompact: false,
    codeShowLineNumbers: false,
    codeFontScale: 0.9,
    codeRadius: 4,
    showCodeCopyButton: true,
    pageMargin: 72,
    columnsEnabled: false,
    columnCount: 2,
    columnGap: 24,
    columnRule: true,
    showPageNumber: true,
    pdfHeader: '',
    pdfFooter: '',
    isDark: false,
    paperShadow: true,
  );

  /// 深色：深灰纸、浅灰字（原 dark）。
  static const MarkdownRenderTheme dark = MarkdownRenderTheme(
    id: 'dark',
    name: '深色',
    nameEn: 'Dark',
    background: Color(0xFF1E1F22),
    foreground: Color(0xFFD4D4D4),
    mutedForeground: Color(0xFFA9AEB6),
    headingColor: Color(0xFFF0F0F0),
    codeBackground: Color(0xFF2B2D31),
    codeForeground: Color(0xFFE6E6E6),
    inlineCodeBackground: Color(0xFF33363B),
    tableHeaderBackground: Color(0xFF2B2D31),
    tableBorder: Color(0xFF3C3F44),
    tableRowStripe: Color(0xFF26282C),
    quoteBar: Color(0xFF4E5259),
    quoteBackground: Color(0xFF26282C),
    quoteForeground: Color(0xFFA9AEB6),
    linkColor: Color(0xFF6CB6FF),
    ruleColor: Color(0xFF3C3F44),
    bulletColor: Color(0xFFA9AEB6),
    checkboxColor: Color(0xFF6CB6FF),
    cjkFontFamily: null,
    latinFontFamily: 'Segoe UI',
    monoFontFamily: 'Consolas',
    fontSize: 16,
    lineHeight: 1.8,
    paragraphSpacing: 0.65,
    headingScale: 1,
    headingWeight: 700,
    headingAlignment: MarkdownHeadingAlignment.start,
    headingRule: false,
    tableBorderVisible: true,
    tableBorderWidth: 1,
    tableStriped: false,
    tableCompact: false,
    codeShowLineNumbers: false,
    codeFontScale: 0.9,
    codeRadius: 4,
    showCodeCopyButton: true,
    pageMargin: 64,
    columnsEnabled: false,
    columnCount: 2,
    columnGap: 24,
    columnRule: true,
    showPageNumber: true,
    pdfHeader: '',
    pdfFooter: '',
    isDark: true,
    paperShadow: false,
  );

  /// 紧凑：窄页、小字号、紧行距（原 compact）。
  static const MarkdownRenderTheme compact = MarkdownRenderTheme(
    id: 'compact',
    name: '紧凑',
    nameEn: 'Compact',
    background: Color(0xFFFBFBFB),
    foreground: Color(0xFF24292F),
    mutedForeground: Color(0xFF4B535B),
    headingColor: Color(0xFF101418),
    codeBackground: Color(0xFFF1F2F4),
    codeForeground: Color(0xFF24292F),
    inlineCodeBackground: Color(0xFFEDEEF0),
    tableHeaderBackground: Color(0xFFF1F2F4),
    tableBorder: Color(0xFFDDE1E6),
    tableRowStripe: Color(0xFFF5F6F7),
    quoteBar: Color(0xFFC3C8CE),
    quoteBackground: Color(0xFFF1F2F4),
    quoteForeground: Color(0xFF4B535B),
    linkColor: Color(0xFF0B6BCB),
    ruleColor: Color(0xFFDDE1E6),
    bulletColor: Color(0xFF4B535B),
    checkboxColor: Color(0xFF0B6BCB),
    cjkFontFamily: null,
    latinFontFamily: 'Segoe UI',
    monoFontFamily: 'Consolas',
    fontSize: 14.5,
    lineHeight: 1.45,
    paragraphSpacing: 0.5,
    headingScale: 1,
    headingWeight: 700,
    headingAlignment: MarkdownHeadingAlignment.start,
    headingRule: false,
    tableBorderVisible: true,
    tableBorderWidth: 1,
    tableStriped: false,
    tableCompact: true,
    codeShowLineNumbers: false,
    codeFontScale: 0.9,
    codeRadius: 4,
    showCodeCopyButton: true,
    pageMargin: 48,
    columnsEnabled: false,
    columnCount: 2,
    columnGap: 20,
    columnRule: true,
    showPageNumber: true,
    pdfHeader: '',
    pdfFooter: '',
    isDark: false,
    paperShadow: false,
  );

  /// 用当前软件主题的配色替换颜色，字体/版式保持本主题。
  ///
  /// 这是"界面内联"模式的落地：Markdown 的排版由统一点主题决定，文字颜色
  /// 必须跟着当前 UI 深浅走，否则深色界面里会白纸黑字或黑底黑字。
  MarkdownRenderTheme forSurface(ColorScheme scheme, {required bool isDark}) {
    return copyWith(
      background: scheme.surface,
      foreground: scheme.onSurface,
      mutedForeground: scheme.onSurfaceVariant,
      headingColor: scheme.onSurface,
      codeBackground: scheme.surfaceContainer,
      codeForeground: scheme.onSurface,
      inlineCodeBackground: scheme.surfaceContainerHigh,
      tableHeaderBackground: scheme.surfaceContainerHigh,
      tableBorder: scheme.outlineVariant,
      tableRowStripe: scheme.surfaceContainerLow,
      quoteBar: scheme.outlineVariant,
      quoteBackground: scheme.surfaceContainerLow,
      quoteForeground: scheme.onSurfaceVariant,
      linkColor: scheme.primary,
      ruleColor: scheme.outlineVariant,
      bulletColor: scheme.onSurfaceVariant,
      checkboxColor: scheme.primary,
      isDark: isDark,
      paperShadow: false,
    );
  }

  MarkdownRenderTheme copyWith({
    String? id,
    String? name,
    String? nameEn,
    Color? background,
    Color? foreground,
    Color? mutedForeground,
    Color? headingColor,
    Color? codeBackground,
    Color? codeForeground,
    Color? inlineCodeBackground,
    Color? tableHeaderBackground,
    Color? tableBorder,
    Color? tableRowStripe,
    Color? quoteBar,
    Color? quoteBackground,
    Color? quoteForeground,
    Color? linkColor,
    Color? ruleColor,
    Color? bulletColor,
    Color? checkboxColor,
    String? cjkFontFamily,
    bool clearCjkFontFamily = false,
    String? latinFontFamily,
    bool clearLatinFontFamily = false,
    String? monoFontFamily,
    bool clearMonoFontFamily = false,
    double? fontSize,
    double? lineHeight,
    double? paragraphSpacing,
    double? headingScale,
    int? headingWeight,
    MarkdownHeadingAlignment? headingAlignment,
    bool? headingRule,
    bool? tableBorderVisible,
    double? tableBorderWidth,
    bool? tableStriped,
    bool? tableCompact,
    bool? codeShowLineNumbers,
    double? codeFontScale,
    double? codeRadius,
    bool? showCodeCopyButton,
    double? pageMargin,
    bool? columnsEnabled,
    int? columnCount,
    double? columnGap,
    bool? columnRule,
    bool? showPageNumber,
    String? pdfHeader,
    String? pdfFooter,
    bool? isDark,
    bool? paperShadow,
  }) {
    return MarkdownRenderTheme(
      id: id ?? this.id,
      name: name ?? this.name,
      nameEn: nameEn ?? this.nameEn,
      background: background ?? this.background,
      foreground: foreground ?? this.foreground,
      mutedForeground: mutedForeground ?? this.mutedForeground,
      headingColor: headingColor ?? this.headingColor,
      codeBackground: codeBackground ?? this.codeBackground,
      codeForeground: codeForeground ?? this.codeForeground,
      inlineCodeBackground:
          inlineCodeBackground ?? this.inlineCodeBackground,
      tableHeaderBackground:
          tableHeaderBackground ?? this.tableHeaderBackground,
      tableBorder: tableBorder ?? this.tableBorder,
      tableRowStripe: tableRowStripe ?? this.tableRowStripe,
      quoteBar: quoteBar ?? this.quoteBar,
      quoteBackground: quoteBackground ?? this.quoteBackground,
      quoteForeground: quoteForeground ?? this.quoteForeground,
      linkColor: linkColor ?? this.linkColor,
      ruleColor: ruleColor ?? this.ruleColor,
      bulletColor: bulletColor ?? this.bulletColor,
      checkboxColor: checkboxColor ?? this.checkboxColor,
      cjkFontFamily: clearCjkFontFamily
          ? null
          : (cjkFontFamily ?? this.cjkFontFamily),
      latinFontFamily: clearLatinFontFamily
          ? null
          : (latinFontFamily ?? this.latinFontFamily),
      monoFontFamily: clearMonoFontFamily
          ? null
          : (monoFontFamily ?? this.monoFontFamily),
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      headingScale: headingScale ?? this.headingScale,
      headingWeight: headingWeight ?? this.headingWeight,
      headingAlignment: headingAlignment ?? this.headingAlignment,
      headingRule: headingRule ?? this.headingRule,
      tableBorderVisible: tableBorderVisible ?? this.tableBorderVisible,
      tableBorderWidth: tableBorderWidth ?? this.tableBorderWidth,
      tableStriped: tableStriped ?? this.tableStriped,
      tableCompact: tableCompact ?? this.tableCompact,
      codeShowLineNumbers:
          codeShowLineNumbers ?? this.codeShowLineNumbers,
      codeFontScale: codeFontScale ?? this.codeFontScale,
      codeRadius: codeRadius ?? this.codeRadius,
      showCodeCopyButton: showCodeCopyButton ?? this.showCodeCopyButton,
      pageMargin: pageMargin ?? this.pageMargin,
      columnsEnabled: columnsEnabled ?? this.columnsEnabled,
      columnCount: columnCount ?? this.columnCount,
      columnGap: columnGap ?? this.columnGap,
      columnRule: columnRule ?? this.columnRule,
      showPageNumber: showPageNumber ?? this.showPageNumber,
      pdfHeader: pdfHeader ?? this.pdfHeader,
      pdfFooter: pdfFooter ?? this.pdfFooter,
      isDark: isDark ?? this.isDark,
      paperShadow: paperShadow ?? this.paperShadow,
    );
  }

  /// JSON 版本号：改了字段语义就加 1，旧文件按预设兜底而不是猜字段。
  static const int jsonVersion = 1;

  Map<String, Object?> toJson() => <String, Object?>{
        'version': jsonVersion,
        'id': id,
        'name': name,
        'nameEn': nameEn,
        'background': background.toARGB32(),
        'foreground': foreground.toARGB32(),
        'mutedForeground': mutedForeground.toARGB32(),
        'headingColor': headingColor.toARGB32(),
        'codeBackground': codeBackground.toARGB32(),
        'codeForeground': codeForeground.toARGB32(),
        'inlineCodeBackground': inlineCodeBackground.toARGB32(),
        'tableHeaderBackground': tableHeaderBackground.toARGB32(),
        'tableBorder': tableBorder.toARGB32(),
        'tableRowStripe': tableRowStripe.toARGB32(),
        'quoteBar': quoteBar.toARGB32(),
        'quoteBackground': quoteBackground.toARGB32(),
        'quoteForeground': quoteForeground.toARGB32(),
        'linkColor': linkColor.toARGB32(),
        'ruleColor': ruleColor.toARGB32(),
        'bulletColor': bulletColor.toARGB32(),
        'checkboxColor': checkboxColor.toARGB32(),
        'cjkFontFamily': cjkFontFamily,
        'latinFontFamily': latinFontFamily,
        'monoFontFamily': monoFontFamily,
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'paragraphSpacing': paragraphSpacing,
        'headingScale': headingScale,
        'headingWeight': headingWeight,
        'headingAlignment': headingAlignment.name,
        'headingRule': headingRule,
        'tableBorderVisible': tableBorderVisible,
        'tableBorderWidth': tableBorderWidth,
        'tableStriped': tableStriped,
        'tableCompact': tableCompact,
        'codeShowLineNumbers': codeShowLineNumbers,
        'codeFontScale': codeFontScale,
        'codeRadius': codeRadius,
        'showCodeCopyButton': showCodeCopyButton,
        'pageMargin': pageMargin,
        'columnsEnabled': columnsEnabled,
        'columnCount': columnCount,
        'columnGap': columnGap,
        'columnRule': columnRule,
        'showPageNumber': showPageNumber,
        'pdfHeader': pdfHeader,
        'pdfFooter': pdfFooter,
        'isDark': isDark,
        'paperShadow': paperShadow,
      };

  /// 从 JSON 还原。字段缺失/类型错误/越界都夹回安全值；版本不匹配按预设
  /// 兜底（返回 [fallback]），不猜旧格式。
  factory MarkdownRenderTheme.fromJson(Map<String, Object?> json) {
    if (json['version'] != jsonVersion) {
      return fallback;
    }
    final base = byId(json['id'] is String ? json['id']! as String : null);

    Color color(String key) {
      final value = json[key];
      if (value is int) {
        return Color(value);
      }
      if (value is num) {
        return Color(value.toInt());
      }
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) {
          return Color(parsed);
        }
      }
      return base.toJson()[key] is int
          ? Color(base.toJson()[key]! as int)
          : base.foreground;
    }

    double number(String key, double fallbackValue, double Function(double) clamp) {
      final value = json[key];
      if (value is num) {
        return clamp(value.toDouble());
      }
      return fallbackValue;
    }

    String? font(String key) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
      return null;
    }

    String text(String key, String fallbackValue) {
      final value = json[key];
      return value is String ? value : fallbackValue;
    }

    bool flag(String key, bool fallbackValue) {
      final value = json[key];
      return value is bool ? value : fallbackValue;
    }

    return MarkdownRenderTheme(
      id: text('id', base.id),
      name: text('name', base.name),
      nameEn: text('nameEn', base.nameEn),
      background: color('background'),
      foreground: color('foreground'),
      mutedForeground: color('mutedForeground'),
      headingColor: color('headingColor'),
      codeBackground: color('codeBackground'),
      codeForeground: color('codeForeground'),
      inlineCodeBackground: color('inlineCodeBackground'),
      tableHeaderBackground: color('tableHeaderBackground'),
      tableBorder: color('tableBorder'),
      tableRowStripe: color('tableRowStripe'),
      quoteBar: color('quoteBar'),
      quoteBackground: color('quoteBackground'),
      quoteForeground: color('quoteForeground'),
      linkColor: color('linkColor'),
      ruleColor: color('ruleColor'),
      bulletColor: color('bulletColor'),
      checkboxColor: color('checkboxColor'),
      cjkFontFamily: font('cjkFontFamily'),
      latinFontFamily: font('latinFontFamily'),
      monoFontFamily: font('monoFontFamily'),
      fontSize: number(
        'fontSize',
        base.fontSize,
        MarkdownRenderLimits.clampFontSize,
      ),
      lineHeight: number(
        'lineHeight',
        base.lineHeight,
        MarkdownRenderLimits.clampLineHeight,
      ),
      paragraphSpacing: number(
        'paragraphSpacing',
        base.paragraphSpacing,
        MarkdownRenderLimits.clampParagraphSpacing,
      ),
      headingScale: number(
        'headingScale',
        base.headingScale,
        MarkdownRenderLimits.clampHeadingScale,
      ),
      headingWeight: MarkdownRenderLimits.clampHeadingWeight(
        json['headingWeight'] is num
            ? (json['headingWeight']! as num).toInt()
            : base.headingWeight,
      ),
      headingAlignment: MarkdownHeadingAlignment.fromName(
        json['headingAlignment'] is String
            ? json['headingAlignment']! as String
            : null,
      ),
      headingRule: flag('headingRule', base.headingRule),
      tableBorderVisible:
          flag('tableBorderVisible', base.tableBorderVisible),
      tableBorderWidth: number(
        'tableBorderWidth',
        base.tableBorderWidth,
        MarkdownRenderLimits.clampTableBorderWidth,
      ),
      tableStriped: flag('tableStriped', base.tableStriped),
      tableCompact: flag('tableCompact', base.tableCompact),
      codeShowLineNumbers:
          flag('codeShowLineNumbers', base.codeShowLineNumbers),
      codeFontScale: number(
        'codeFontScale',
        base.codeFontScale,
        MarkdownRenderLimits.clampCodeFontScale,
      ),
      codeRadius: number(
        'codeRadius',
        base.codeRadius,
        MarkdownRenderLimits.clampCodeRadius,
      ),
      showCodeCopyButton:
          flag('showCodeCopyButton', base.showCodeCopyButton),
      pageMargin: number(
        'pageMargin',
        base.pageMargin,
        MarkdownRenderLimits.clampPageMargin,
      ),
      columnsEnabled: flag('columnsEnabled', base.columnsEnabled),
      columnCount:
          MarkdownRenderLimits.clampColumnCount(
        json['columnCount'] is num
            ? (json['columnCount']! as num).toInt()
            : base.columnCount,
      ),
      columnGap: number(
        'columnGap',
        base.columnGap,
        MarkdownRenderLimits.clampColumnGap,
      ),
      columnRule: flag('columnRule', base.columnRule),
      showPageNumber: flag('showPageNumber', base.showPageNumber),
      pdfHeader: text('pdfHeader', base.pdfHeader),
      pdfFooter: text('pdfFooter', base.pdfFooter),
      isDark: flag('isDark', base.isDark),
      paperShadow: flag('paperShadow', base.paperShadow),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MarkdownRenderTheme && other.toJson().toString() == toJson().toString();

  @override
  int get hashCode => toJson().toString().hashCode;
}

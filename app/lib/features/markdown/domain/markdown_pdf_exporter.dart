/// Markdown → PDF（A4）：与设置页 A4 预览共用同一份 [MarkdownRenderTheme]。
///
/// 为什么是 `pdf` 包而不是 `printing`：`pdf` 是纯 Dart 生成字节，不引入平台
/// 插件/原生库；保存复用仓库已有的 `file_picker.saveFile`。
///
/// 中文字体见 `markdown_pdf_fonts.dart`：字体通过 `pw.Font.ttf` 嵌入，且每一
/// 处 TextStyle（正文/标题/代码/表格/页眉页脚）都显式带 font——`pdf` 的表格
/// 表头、默认文本样式如果没有 font，会退回 WinAnsi 的 Helvetica，中文变乱码。
///
/// 与预览共享的东西：颜色、字号、行距、段距、标题层级/居中/分隔线、表格
/// 边框/斑马纹/紧凑、代码块背景/行号、页边距、页眉/页脚/页码。
///
/// 左右分栏：`theme.columnsEnabled` 为真时走**真正的双栏排页**——A4 纸、栏宽
/// `(contentWidth - columnGap) / N`、栏间可画竖线，页眉/页脚/页码/页边距全部
/// 保留。`pdf` 包没有报纸式多栏自动分页（`Partitions` 是两条独立栏流，`Row`
/// 又不可跨页），所以分页由本文件 + `markdown_pdf_columns.dart` 自己算：
/// 先用 `pdf` 包自己的 layout 测量每个顶层块在栏宽下的高度，再按"左栏→右栏→
/// 下一页"的顺序逐页生成 Row。单栏路径保持原 multiPage 实现不变。
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'markdown_ast.dart';
import 'markdown_columns.dart';
import 'markdown_pdf_columns.dart';
import 'markdown_pdf_fonts.dart';
import 'markdown_render_theme.dart';

/// PDF 生成失败（排版异常等），与"缺字体"区分开。
class MarkdownPdfExportException implements Exception {
  MarkdownPdfExportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 一次导出的版面统计：只用于测试/诊断，不参与排版。
class MarkdownPdfLayoutInfo {
  const MarkdownPdfLayoutInfo({
    required this.columnsEnabled,
    required this.columnCount,
    required this.columnWidth,
    required this.pageCount,
    required this.widePageCount,
  });

  /// 是否真的走了双栏排页（false = 单栏，或双栏不可用退回单栏）。
  final bool columnsEnabled;

  /// 实际栏数；单栏为 1。
  final int columnCount;

  /// 每栏宽度（pt）；单栏为正文宽度。
  final double columnWidth;

  /// 生成的总页数。
  final int pageCount;

  /// 其中"通栏页"的数量（半栏放不下、整页放得下的大块独占页）。
  final int widePageCount;
}

/// 预览主题 → 一份 A4 PDF。
class MarkdownPdfExporter {
  MarkdownPdfExporter({required this.fontResolver});

  final MarkdownPdfFontResolver fontResolver;

  static const PdfPageFormat _a4 = PdfPageFormat.a4;

  /// 1 逻辑像素 = 0.75pt（96dpi 屏 → 72dpi PDF）。
  static double pxToPt(double px) => px * 0.75;

  Future<Uint8List> build({
    required String markdown,
    required MarkdownRenderTheme theme,

    /// 版面统计回调（测试/诊断用，正常导出不传）。
    void Function(MarkdownPdfLayoutInfo info)? onLayout,
  }) async {
    final fontData = await fontResolver.resolve();
    final font = pw.Font.ttf(ByteData.sublistView(fontData.bytes));

    final bodySize = pxToPt(theme.fontSize);
    final margin = pxToPt(theme.pageMargin).clamp(18.0, _a4.width / 3);
    final contentWidth = _a4.width - margin * 2;

    final background = PdfColor.fromInt(theme.background.toARGB32());
    final foreground = PdfColor.fromInt(theme.foreground.toARGB32());
    final muted = PdfColor.fromInt(theme.mutedForeground.toARGB32());
    final headingColor = PdfColor.fromInt(theme.headingColor.toARGB32());
    final codeBackground = PdfColor.fromInt(theme.codeBackground.toARGB32());
    final codeForeground = PdfColor.fromInt(theme.codeForeground.toARGB32());
    final tableHeader =
        PdfColor.fromInt(theme.tableHeaderBackground.toARGB32());
    final tableBorder = PdfColor.fromInt(theme.tableBorder.toARGB32());
    final tableStripe = PdfColor.fromInt(theme.tableRowStripe.toARGB32());
    final quoteBar = PdfColor.fromInt(theme.quoteBar.toARGB32());
    final quoteBackground =
        PdfColor.fromInt(theme.quoteBackground.toARGB32());
    final quoteForeground =
        PdfColor.fromInt(theme.quoteForeground.toARGB32());
    final linkColor = PdfColor.fromInt(theme.linkColor.toARGB32());
    final ruleColor = PdfColor.fromInt(theme.ruleColor.toARGB32());

    pw.TextStyle bodyStyle({PdfColor? color}) => pw.TextStyle(
          font: font,
          fontSize: bodySize,
          color: color ?? foreground,
          // pdf 用 lineSpacing（额外行距）而不是 Flutter 的 height 倍数。
          lineSpacing:
              bodySize * (theme.lineHeight - 1).clamp(0.0, 2.0),
        );

    pw.Widget richText(
      List<MarkdownRun> runs, {
      PdfColor? color,
      double? fontSize,
      bool header = false,
    }) {
      final base = bodyStyle(color: color).copyWith(
        fontSize: fontSize ?? bodySize,
        fontWeight: header ? pw.FontWeight.bold : null,
      );
      return pw.RichText(
        text: pw.TextSpan(
          style: base,
          children: <pw.TextSpan>[
            for (final run in runs)
              _runSpan(
                run,
                base,
                font,
                linkColor: linkColor,
                codeBackground: codeBackground,
                codeForeground: codeForeground,
              ),
          ],
        ),
      );
    }

    final columnCount =
        MarkdownRenderLimits.clampColumnCount(theme.columnCount);
    final columnsRequested = theme.columnsEnabled && columnCount > 1;

    // 分栏时先按与预览同一个"顶层块/围栏安全"的切栏函数分块（分栏只支持
    // 2..3 栏，见 `MarkdownRenderLimits.clampColumnCount`），再按原顺序解析成
    // 块交给分页器；单栏路径仍整篇解析，行为与以前一致。
    final markdownChunks = columnsRequested
        ? splitMarkdownIntoColumns(markdown, columnCount)
        : <String>[markdown];
    final blocks = <MarkdownBlock>[
      for (final chunk in markdownChunks) ...parseMarkdownBlocks(chunk),
    ];

    final pageTheme = pw.PageTheme(
      pageFormat: _a4,
      margin: pw.EdgeInsets.symmetric(
        horizontal: margin,
        vertical: margin,
      ),
      buildBackground: (context) => pw.FullPage(
        ignoreMargins: true,
        child: pw.Container(color: background),
      ),
    );

    // 正文/测量/文档共用同一份 ThemeData：测量时若用 ThemeData.base()，
    // 字体的 fallback 行为会和真正排版不一致，实测高度就不可信了。
    final documentTheme = pw.ThemeData.withFont(base: font, bold: font);
    final pdf = pw.Document(theme: documentTheme);

    List<pw.Widget> buildBlocks(
      List<MarkdownBlock> blocks, {
      required double blockWidth,
      PdfColor? textColor,
      double depth = 0,
    }) {
      final widgets = <pw.Widget>[];
      for (final block in blocks) {
        switch (block) {
          case MarkdownHeading():
            final scale = markdownHeadingScale[
                (block.level - 1).clamp(0, 5).toInt()];
            final headingStyle = bodyStyle(color: headingColor).copyWith(
              fontSize: bodySize * scale * theme.headingScale,
              fontWeight: pw.FontWeight.bold,
            );
            final text = pw.RichText(
              textAlign: pw.TextAlign.left,
              text: pw.TextSpan(
                style: headingStyle,
                children: <pw.TextSpan>[
                  for (final run in block.runs)
                    _runSpan(
                      run,
                      headingStyle,
                      font,
                      linkColor: linkColor,
                      codeBackground: codeBackground,
                      codeForeground: codeForeground,
                    ),
                ],
              ),
            );
            widgets.add(
              pw.Padding(
                padding: pw.EdgeInsets.only(
                  top: block.level == 1 ? bodySize * 0.2 : bodySize * 0.8,
                  bottom: bodySize * 0.35,
                ),
                child: theme.headingRule && block.level == 1
                    ? pw.Container(
                        padding: pw.EdgeInsets.only(bottom: bodySize * 0.2),
                        decoration: pw.BoxDecoration(
                          border: pw.Border(
                            bottom: pw.BorderSide(
                              color: ruleColor,
                              width: 0.6,
                            ),
                          ),
                        ),
                        child: _alignHeading(text, theme, blockWidth),
                      )
                    : _alignHeading(text, theme, blockWidth),
              ),
            );
          case MarkdownParagraph():
            widgets.add(
              pw.Padding(
                padding: pw.EdgeInsets.only(
                  bottom: bodySize * theme.paragraphSpacing,
                ),
                child: richText(block.runs, color: textColor),
              ),
            );
          case MarkdownQuote():
            widgets.add(
              pw.Container(
                margin: pw.EdgeInsets.only(bottom: bodySize * 0.65),
                padding: const pw.EdgeInsets.fromLTRB(12, 8, 10, 2),
                decoration: pw.BoxDecoration(
                  color: quoteBackground,
                  border: pw.Border(
                    left: pw.BorderSide(color: quoteBar, width: 3),
                  ),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: buildBlocks(
                    block.blocks,
                    blockWidth: blockWidth,
                    textColor: quoteForeground,
                    depth: depth + 1,
                  ),
                ),
              ),
            );
          case MarkdownListBlock():
            var index = block.start;
            for (final item in block.items) {
              // 内置的 Noto Sans SC 有 U+2022 项目符号，无序列表与预览一致；但
              // 没有 U+2610/2611 任务框，PDF 里改用 [ ] / [x]。
              final marker = item.taskChecked == true
                  ? '[x]'
                  : item.taskChecked == false
                      ? '[ ]'
                      : block.ordered
                          ? '$index.'
                          : '•';
              if (block.ordered) {
                index += 1;
              }
              widgets.add(
                pw.Padding(
                  padding: pw.EdgeInsets.only(
                    left: bodySize * 0.2 + depth * bodySize * 0.45,
                    bottom: bodySize * 0.15,
                  ),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: <pw.Widget>[
                      pw.SizedBox(
                        width: bodySize * 1.6,
                        child: pw.Text(
                          marker,
                          style: bodyStyle(color: textColor ?? muted),
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: <pw.Widget>[
                            if (item.runs.isNotEmpty)
                              richText(item.runs, color: textColor),
                            if (item.children.isNotEmpty)
                              ...buildBlocks(
                                item.children,
                                blockWidth: blockWidth,
                                textColor: textColor,
                                depth: depth + 1,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
          case MarkdownCodeBlock():
            final code = block.code.trimRight();
            final codeText = theme.codeShowLineNumbers
                ? _withLineNumbers(code)
                : code;
            widgets.add(
              pw.Container(
                width: double.infinity,
                margin: pw.EdgeInsets.only(bottom: bodySize * 0.7),
                padding: pw.EdgeInsets.all(bodySize * 0.6),
                decoration: pw.BoxDecoration(
                  color: codeBackground,
                  borderRadius: pw.BorderRadius.circular(theme.codeRadius),
                ),
                child: pw.Text(
                  codeText,
                  style: pw.TextStyle(
                    font: font,
                    fontSize: bodySize * theme.codeFontScale,
                    color: codeForeground,
                    lineSpacing: bodySize * 0.15,
                  ),
                ),
              ),
            );
          case MarkdownTable():
            final header = block.header;
            final columnCount = <int>[
              header?.length ?? 0,
              for (final row in block.rows) row.length,
            ].fold<int>(0, (a, b) => a > b ? a : b);
            if (columnCount == 0) {
              break;
            }
            pw.Widget cell(List<MarkdownRun> runs, {bool header = false}) =>
                pw.Padding(
                  padding: pw.EdgeInsets.symmetric(
                    horizontal: bodySize * 0.35,
                    vertical: bodySize * (theme.tableCompact ? 0.16 : 0.25),
                  ),
                  child: richText(
                    runs,
                    header: header,
                    fontSize: bodySize * 0.95,
                  ),
                );
            List<pw.Widget> rowCells(
              List<List<MarkdownRun>> row, {
              bool header = false,
            }) {
              final widgets = <pw.Widget>[
                for (final runs in row) cell(runs, header: header),
              ];
              while (widgets.length < columnCount) {
                widgets.add(cell(const <MarkdownRun>[]));
              }
              return widgets;
            }

            final rows = <pw.TableRow>[
              if (header != null)
                pw.TableRow(
                  repeat: true,
                  decoration: pw.BoxDecoration(color: tableHeader),
                  children: rowCells(header, header: true),
                ),
              for (var index = 0; index < block.rows.length; index++)
                pw.TableRow(
                  decoration: theme.tableStriped && index.isOdd
                      ? pw.BoxDecoration(color: tableStripe)
                      : null,
                  children: rowCells(block.rows[index]),
                ),
            ];
            widgets.add(
              pw.Container(
                margin: pw.EdgeInsets.only(bottom: bodySize * 0.8),
                child: pw.Table(
                  border: theme.tableBorderVisible
                      ? pw.TableBorder.all(
                          color: tableBorder,
                          width: theme.tableBorderWidth,
                        )
                      : null,
                  columnWidths: <int, pw.TableColumnWidth>{
                    for (var i = 0; i < columnCount; i++)
                      i: const pw.FlexColumnWidth(),
                  },
                  children: rows,
                ),
              ),
            );
          case MarkdownRule():
            widgets.add(
              pw.Container(
                height: 0.7,
                margin: pw.EdgeInsets.symmetric(vertical: bodySize * 0.8),
                color: ruleColor,
              ),
            );
        }
      }
      return widgets;
    }

    pw.Widget header(pw.Context context) {
      if (theme.pdfHeader.trim().isEmpty) {
        return pw.SizedBox(height: 0);
      }
      return pw.Container(
        alignment: pw.Alignment.centerLeft,
        margin: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Text(
          theme.pdfHeader,
          style: pw.TextStyle(font: font, fontSize: 9, color: muted),
        ),
      );
    }

    pw.Widget footer(pw.Context context) {
      final hasFooter = theme.pdfFooter.trim().isNotEmpty;
      if (!hasFooter && !theme.showPageNumber) {
        return pw.SizedBox(height: 0);
      }
      return pw.Container(
        margin: const pw.EdgeInsets.only(top: 6),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: <pw.Widget>[
            pw.Text(
              hasFooter ? theme.pdfFooter : '',
              style: pw.TextStyle(font: font, fontSize: 9, color: muted),
            ),
            if (theme.showPageNumber)
              pw.Text(
                '第 ${context.pageNumber} 页',
                style: pw.TextStyle(font: font, fontSize: 9, color: muted),
              ),
          ],
        ),
      );
    }

    // 双栏版面统计（只给 onLayout 诊断用）。
    var columnsLayoutUsed = false;
    var columnsLayoutWidth = 0.0;
    var widePageCount = 0;

    /// 双栏排页：测量 → 分页 → 每页一个固定宽度的 Row。
    ///
    /// 返回 null = 本文档不适合双栏（有块比整页还高），调用方退回单栏。
    pw.MultiPage? buildColumnsMultiPage() {
      // 测量用独立 PdfDocument：`PdfPage` 构造时会把页对象登记进文档，不能
      // 借用最终文档，否则会多出一张空白页/污染页码。字体对象按 context 的
      // document 懒构建（pdf 包的 TtfFont.getFont 会缓存对应文档的 PdfFont），
      // 所以测量与真正的排版各用各的字体实例，互不干扰。
      final measureDocument = PdfDocument();
      final measurePage = PdfPage(measureDocument, pageFormat: _a4);
      final measureContext = pw.Context(
        document: measureDocument,
        page: measurePage,
        canvas: measurePage.getGraphics(),
      ).inheritFromAll(<pw.Inherited>[documentTheme]);

      double measureWidgets(List<pw.Widget> widgets, double width) {
        var total = 0.0;
        for (final widget in widgets) {
          total += pw.Widget.measure(
            widget,
            context: measureContext,
            constraints: pw.BoxConstraints(maxWidth: width),
          ).y;
        }
        return total;
      }

      final gap = pxToPt(theme.columnGap);
      final columnWidth = pdfColumnWidth(
        contentWidth: contentWidth,
        gap: gap,
        columns: columnCount,
      );
      if (columnWidth <= 1) {
        return null;
      }

      // MultiPage 的正文高度 = 页高 - 上下边距 - 页眉高 - 页脚高。页眉页脚
      // 也用同一套控件、同一测量上下文量；再留 1pt 余量，避免浮点误差让整页
      // 高出可用高度而被 MultiPage 判成"不可分页控件放不下"。
      final headerHeight = measureWidgets(
        <pw.Widget>[header(measureContext)],
        contentWidth,
      );
      final footerHeight = measureWidgets(
        <pw.Widget>[footer(measureContext)],
        contentWidth,
      );
      final pageHeight = _a4.height - margin * 2 - headerHeight - footerHeight;
      final columnHeight = pageHeight - 1;
      if (columnHeight <= bodySize) {
        return null;
      }

      // 顶层块 → 排版单元。列表按项拆开（长列表也能在两栏之间断开）；其余
      // 块整体是一个单元（表格/代码块/引用不会被切成两半）。
      final units = <_ColumnUnit>[];
      final heights = <ColumnBlockHeight>[];
      for (final block in blocks) {
        if (block is MarkdownListBlock) {
          for (var item = 0; item < block.items.length; item++) {
            final singleItem = MarkdownListBlock(
              ordered: block.ordered,
              items: <MarkdownListItem>[block.items[item]],
              start: block.start + item,
            );
            final unit = _ColumnUnit(
              build: (double width) => buildBlocks(
                <MarkdownBlock>[singleItem],
                blockWidth: width,
              ),
              isHeading: false,
            );
            final widgets = unit.build(columnWidth);
            if (widgets.isEmpty) {
              continue;
            }
            unit
              ..columnWidgets = widgets
              ..height = measureWidgets(widgets, columnWidth);
            units.add(unit);
            heights.add(
              ColumnBlockHeight(unit.height, isHeading: unit.isHeading),
            );
          }
          continue;
        }
        final unit = _ColumnUnit(
          build: (double width) => buildBlocks(
            <MarkdownBlock>[block],
            blockWidth: width,
          ),
          isHeading: block is MarkdownHeading,
        );
        final widgets = unit.build(columnWidth);
        if (widgets.isEmpty) {
          continue;
        }
        unit
          ..columnWidgets = widgets
          ..height = measureWidgets(widgets, columnWidth);
        units.add(unit);
        heights.add(
          ColumnBlockHeight(unit.height, isHeading: unit.isHeading),
        );
      }
      if (units.isEmpty) {
        return null;
      }

      // 半栏放不下、整页放得下的块（超长代码块/大表格）→ 通栏独占一页，
      // 保证不被横向切断。通栏也放不下 → 整篇退回单栏，交给 multiPage 的
      // 原有规则处理（Table 这类 SpanningWidget 仍可跨页；单个比整页还高的
      // 不可分块会和改动前一样抛出可识别的排版异常）。
      for (var index = 0; index < units.length; index++) {
        final unit = units[index];
        if (unit.height <= columnHeight) {
          continue;
        }
        final wideWidgets = unit.build(contentWidth);
        final wideHeight = measureWidgets(wideWidgets, contentWidth);
        unit
          ..wideWidgets = wideWidgets
          ..wideHeight = wideHeight;
        heights[index] = ColumnBlockHeight(
          unit.height,
          isHeading: unit.isHeading,
          wideHeight: wideHeight,
        );
      }

      final plan = paginateColumnBlocks(
        blocks: heights,
        columnHeight: columnHeight,
        pageHeight: pageHeight,
        columnCount: columnCount,
      );
      if (plan == null || plan.isEmpty) {
        return null;
      }

      List<pw.Widget> widgetsOf(List<int> indexes, {required bool wide}) {
        final result = <pw.Widget>[];
        for (final index in indexes) {
          final unit = units[index];
          result.addAll(
            wide ? unit.wideWidgets! : unit.columnWidgets,
          );
        }
        return result;
      }

      double heightOf(List<int> indexes) => indexes.fold<double>(
            0,
            (sum, index) => sum + units[index].height,
          );

      pw.Widget buildPage(PdfColumnPagePlan page) {
        if (page.isWide) {
          // 通栏页：正文宽度下重新构建/测量过的块，独自占一页。
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisSize: pw.MainAxisSize.min,
            children: widgetsOf(page.columns.single, wide: true),
          );
        }

        // 分栏页：每栏定宽 SizedBox，栏缝用等宽 SizedBox 垫出来；竖线画在
        // 栏缝正中（只占 1pt，左右各留 (gap-1)/2），所以两栏宽度严格等于
        // (contentWidth - gap) / N，且 Row 总宽正好是 contentWidth。
        final columnHeights = <double>[
          for (final indexes in page.columns) heightOf(indexes),
        ];
        final ruleHeight =
            columnHeights.fold<double>(0, (a, b) => a > b ? a : b);
        final filledColumns = page.columns
            .where((List<int> indexes) => indexes.isNotEmpty)
            .length;
        final drawRule = theme.columnRule && filledColumns >= 2;
        final children = <pw.Widget>[];
        for (var column = 0; column < page.columns.length; column++) {
          if (column > 0) {
            children.add(pw.SizedBox(width: gap / 2));
            if (drawRule) {
              children.add(
                pw.Container(width: 1, height: ruleHeight, color: ruleColor),
              );
              children.add(pw.SizedBox(width: gap / 2 - 1));
            } else {
              children.add(pw.SizedBox(width: gap / 2));
            }
          }
          children.add(
            pw.SizedBox(
              width: columnWidth,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisSize: pw.MainAxisSize.min,
                children: widgetsOf(page.columns[column], wide: false),
              ),
            ),
          );
        }
        return pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: children,
        );
      }

      final pageWidgets = <pw.Widget>[];
      for (var index = 0; index < plan.length; index++) {
        // 每页成对生成；`NewPage` 强制页边界，避免下一页的两栏被拼到本页
        // 剩余空白里。
        if (index > 0) {
          pageWidgets.add(pw.NewPage());
        }
        pageWidgets.add(buildPage(plan[index]));
      }

      columnsLayoutUsed = true;
      columnsLayoutWidth = columnWidth;
      widePageCount =
          plan.where((PdfColumnPagePlan page) => page.isWide).length;

      return pw.MultiPage(
        pageTheme: pageTheme,
        maxPages: 500,
        header: header,
        footer: footer,
        build: (context) => pageWidgets,
      );
    }

    try {
      // 分栏失败（有块高过整页）时退回单栏：单栏的 MultiPage 能跨页切块。
      final columnsMultiPage = columnsRequested && blocks.isNotEmpty
          ? buildColumnsMultiPage()
          : null;
      pdf.addPage(
        columnsMultiPage ??
            pw.MultiPage(
              pageTheme: pageTheme,
              maxPages: 500,
              header: header,
              footer: footer,
              build: (context) => <pw.Widget>[
                if (blocks.isEmpty)
                  pw.Padding(
                    padding: pw.EdgeInsets.only(top: bodySize),
                    child: pw.Text(
                      '（空文档）',
                      style: bodyStyle(color: muted),
                    ),
                  )
                else
                  ...buildBlocks(blocks, blockWidth: contentWidth),
              ],
            ),
      );
      final bytes = await pdf.save();
      onLayout?.call(
        MarkdownPdfLayoutInfo(
          columnsEnabled: columnsLayoutUsed,
          columnCount: columnsLayoutUsed ? columnCount : 1,
          columnWidth: columnsLayoutUsed ? columnsLayoutWidth : contentWidth,
          pageCount: pdf.document.pdfPageList.pages.length,
          widePageCount: widePageCount,
        ),
      );
      return bytes;
    } on MarkdownPdfFontUnavailableException {
      rethrow;
    } on Object catch (error) {
      throw MarkdownPdfExportException(
        'PDF 排版失败（文档里可能有超长表格或超大代码块）：$error',
      );
    }
  }

  /// 标题居中（主题设置 `headingAlignment`）：PDF 没有 Flutter 的 Align，
  /// 用定宽 Container 的居中。
  static pw.Widget _alignHeading(
    pw.Widget text,
    MarkdownRenderTheme theme,
    double contentWidth,
  ) {
    if (theme.headingAlignment != MarkdownHeadingAlignment.center) {
      return text;
    }
    return pw.Container(
      width: contentWidth,
      alignment: pw.Alignment.center,
      child: text,
    );
  }

  /// 代码行号：右对齐的行号列 + 竖线 + 代码（PDF 里用空格拼行头，避免再引入
  /// 一个不可分页的 Row）。
  static String _withLineNumbers(String code) {
    final lines = code.split('\n');
    final width = '${lines.length}'.length;
    final buffer = StringBuffer();
    for (var index = 0; index < lines.length; index++) {
      buffer.write('${'${index + 1}'.padLeft(width)} | ${lines[index]}');
      if (index != lines.length - 1) {
        buffer.write('\n');
      }
    }
    return buffer.toString();
  }
}

/// 双栏排版里的一个单元：一个顶层块，或列表里的一项。
///
/// [build] 按目标宽度重新构建控件；测量与真正排版都走它，保证"量的"和
/// "画的"是同一套构建代码。栏宽测量结果缓存在 [columnWidgets]/[height]，
/// 通栏结果缓存在 [wideWidgets]/[wideHeight]（同一个控件实例在测量后可以
/// 直接在真正的文档里重新 layout，layout 只覆盖 box，不依赖旧文档）。
class _ColumnUnit {
  _ColumnUnit({required this.build, required this.isHeading});

  final List<pw.Widget> Function(double width) build;
  final bool isHeading;

  List<pw.Widget> columnWidgets = const <pw.Widget>[];
  double height = 0;
  List<pw.Widget>? wideWidgets;
  double wideHeight = 0;
}

/// 单个行内片段的 PDF span。
pw.TextSpan _runSpan(
  MarkdownRun run,
  pw.TextStyle base,
  pw.Font font, {
  required PdfColor linkColor,
  required PdfColor codeBackground,
  required PdfColor codeForeground,
}) {
  var style = base;
  if (run.bold) {
    style = style.copyWith(fontWeight: pw.FontWeight.bold);
  }
  if (run.italic) {
    style = style.copyWith(fontStyle: pw.FontStyle.italic);
  }
  if (run.code) {
    style = style.copyWith(
      font: font,
      fontSize: base.fontSize == null ? null : base.fontSize! * 0.92,
      color: codeForeground,
      background: pw.BoxDecoration(
        color: codeBackground,
        borderRadius: pw.BorderRadius.circular(2),
      ),
    );
  }
  if (run.href != null) {
    style = style.copyWith(
      color: linkColor,
      decoration: pw.TextDecoration.underline,
      decorationColor: linkColor,
    );
  }
  if (run.strikethrough) {
    style = style.copyWith(
      decoration: pw.TextDecoration.lineThrough,
      decorationColor: style.color,
    );
  }
  return pw.TextSpan(text: run.text, style: style);
}

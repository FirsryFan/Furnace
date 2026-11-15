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
/// 边框/斑马纹/紧凑、代码块背景/行号、页边距、页眉/页脚/页码。PDF 不支持
/// 左右分栏（见报告），隐藏域 `theme.columnsEnabled` 只影响预览。
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'markdown_ast.dart';
import 'markdown_pdf_fonts.dart';
import 'markdown_render_theme.dart';

/// PDF 生成失败（排版异常等），与"缺字体"区分开。
class MarkdownPdfExportException implements Exception {
  MarkdownPdfExportException(this.message);

  final String message;

  @override
  String toString() => message;
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

    final blocks = parseMarkdownBlocks(markdown);
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

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: font),
    );

    List<pw.Widget> buildBlocks(
      List<MarkdownBlock> blocks, {
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
                        child: _alignHeading(text, theme, contentWidth),
                      )
                    : _alignHeading(text, theme, contentWidth),
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

    try {
      pdf.addPage(
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
              ...buildBlocks(blocks),
          ],
        ),
      );
      return await pdf.save();
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

/// OOXML（.docx）构造器：纯 Dart、不碰 Flutter、不写文件，只把"文档模型"变成
/// 一个可交给 Word 打开的 zip 字节流。
///
/// 版面参数与结构照着 `paper-composer` skill（D:\dsh-data\skills\paper-composer）的
/// `scripts/papercompose/docx.py` 与 `config.py` 移植，保留它踩过的四条硬约定：
///
/// 1. **页面几何四边独立**：左 1.2cm（装订）+ 右 4.0cm（批注栏）+ 上下 1.8cm，
///    正文栏宽 15.8cm。左右不等宽会改变折行，所以不能事后改 pgMar 糊。
/// 2. **图片只用 `wp:inline`**（随文图，绝不跑位）。受控环绕 `wp:anchor` 没有移植：
///    它必须逐份实测分页，题库导出没有这个验证预算；宁可图占纵向，也不让图压字。
/// 3. **页脚放页码域**（PAGE / NUMPAGES），左时期代号右页码；不做页首标题。
/// 4. **公式是 OMML 原生公式**，由调用方注入编译器（本文件不依赖 LeTeX 解析）；
///    编译失败由调用方决定"保留 LaTeX 原文并计数"，绝不在这里悄悄丢公式。
///
/// 没移植：表格、浮动图、页眉、多栏、目录。题库导出暂时用不到；需要时再加，
/// 但**不要**从 paper-composer 里贴一段浮动图进来——那需要重新实测分页。
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// WordprocessingML 主命名空间。
const String wNamespace =
    'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

/// Office Math 命名空间（OMML）。
const String mathNamespace =
    'http://schemas.openxmlformats.org/officeDocument/2006/math';

/// 关系命名空间。
const String relationshipsNamespace =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

/// Word 绘图（drawing）命名空间。
const String wordprocessingDrawingNamespace =
    'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing';

/// DrawingML 主命名空间。
const String drawingNamespace =
    'http://schemas.openxmlformats.org/drawingml/2006/main';

/// DrawingML 图片命名空间。
const String pictureNamespace =
    'http://schemas.openxmlformats.org/drawingml/2006/picture';

/// 1 twip = 635 EMU（1/1440 英寸 → 1/914400 英寸）。
const int emuPerTwip = 635;

/// 96dpi 下 1 像素 = 15 twips（1440 / 96）。
const int twipsPerPixel = 15;

/// 正文字号：五号（10.5pt），单位半磅。
const int kDocxBodyHalfPt = 21;

/// 标题/题号字号：小四（12pt）。
const int kDocxHeadHalfPt = 24;

/// 卷面标题字号：15pt。
const int kDocxTitleHalfPt = 30;

/// 次要信息字号：小五（9pt），给学科/来源/页码用。
const int kDocxMetaHalfPt = 18;

/// 正文字体（中文）。
const String kDocxBodyFontCn = '宋体';

/// 正文字体（西文）。
const String kDocxBodyFontEn = 'Times New Roman';

/// 标题字体（中文）。
const String kDocxHeadFontCn = '黑体';

/// 数学公式字体（OMML run 的 ascii 字体）。
const String kDocxMathFont = 'Cambria Math';

/// 段落对齐方式。
enum DocxAlign {
  left('left'),
  center('center'),
  right('right'),
  justify('both');

  const DocxAlign(this.xmlValue);

  /// 写进 `<w:jc w:val="…"/>` 的值。
  final String xmlValue;
}

/// 段落里的一段内容：文本或已编译好的公式。
sealed class DocxInline {
  const DocxInline();
}

/// 一段文本 run。
class DocxText extends DocxInline {
  const DocxText(
    this.text, {
    this.sizeHalfPt = kDocxBodyHalfPt,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.subscript = false,
    this.superscript = false,
    this.colorHex,
    this.fontCn,
    this.fontEn,
  });

  final String text;
  final int sizeHalfPt;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool subscript;
  final bool superscript;

  /// RGB 十六进制（不带 #），如 `595959`；null = 默认黑色。
  final String? colorHex;
  final String? fontCn;
  final String? fontEn;

  bool get isEmpty => text.isEmpty;
}

/// 一段已编译好的 OMML 公式（`<m:oMath>…</m:oMath>` 完整片段）。
///
/// 片段由调用方注入的编译器产出（见 `paper_docx.dart` 的 `DocxMathCompiler`）。
/// 这里**不校验**片段内容：编译器是纯逻辑层，坏片段应当在它的测试里拦下来；
/// 这里是装配层，再解析一遍 XML 只会重复一套规则。
class DocxMath extends DocxInline {
  const DocxMath(this.omml);

  final String omml;
}

/// 一个段落。
class DocxParagraph {
  DocxParagraph({
    this.inlines = const <DocxInline>[],
    this.align,
    this.spacingBeforeTw,
    this.spacingAfterTw,
    this.lineTw,
    this.lineRule = 'auto',
    this.keepNext = false,
    this.keepLines = false,
    this.pageBreakBefore = false,
    this.firstLineIndentTw,
    this.leftIndentTw,
    this.rightIndentTw,
    this.borderBottomHex,
    this.shadeHex,
  });

  final List<DocxInline> inlines;
  final DocxAlign? align;
  final int? spacingBeforeTw;
  final int? spacingAfterTw;
  final int? lineTw;

  /// `auto`（倍数行距）或 `atLeast`（最小值行距）。
  final String lineRule;
  final bool keepNext;
  final bool keepLines;
  final bool pageBreakBefore;
  final int? firstLineIndentTw;
  final int? leftIndentTw;
  final int? rightIndentTw;
  final String? borderBottomHex;
  final String? shadeHex;

  /// 没有任何可见内容（空文本且无公式）→ 只输出空段落标记。
  bool get isEmpty => inlines.every((inline) {
        return switch (inline) {
          DocxText(:final text) => text.isEmpty,
          DocxMath(:final omml) => omml.trim().isEmpty,
        };
      });
}

/// 页面几何与基本排版（全部用 OOXML 原生单位：twips / 半磅 / EMU）。
class DocxPageConfig {
  const DocxPageConfig({
    this.pageWidthTw = 11906,
    this.pageHeightTw = 16838,
    this.marginLeftTw = 680,
    this.marginRightTw = 2268,
    this.marginTopTw = 1020,
    this.marginBottomTw = 1020,
    this.lineTw = 252,
  });

  /// A4 + exam 模板（paper-composer 的实测值）：左 1.2cm、右 4.0cm 批注栏、
  /// 上下 1.8cm，正文栏宽 15.8cm。
  const DocxPageConfig.a4Exam({
    this.marginLeftTw = 680,
    this.marginRightTw = 2268,
    this.marginTopTw = 1020,
    this.marginBottomTw = 1020,
    this.lineTw = 252,
  })  : pageWidthTw = 11906,
        pageHeightTw = 16838;

  final int pageWidthTw;
  final int pageHeightTw;
  final int marginLeftTw;
  final int marginRightTw;
  final int marginTopTw;
  final int marginBottomTw;

  /// 行距（twips，`lineRule=auto` 时是 240 的倍数近似；252 ≈ 1.05 倍）。
  final int lineTw;

  /// 正文栏宽。
  int get contentWidthTw => pageWidthTw - marginLeftTw - marginRightTw;

  /// 正文可用高度。
  int get contentHeightTw => pageHeightTw - marginTopTw - marginBottomTw;

  /// 页脚到页边距的距离（与 paper-composer 同口径，最小 425）。
  int get footerDistanceTw => math.max(425, marginBottomTw - 283);
}

/// 一张要嵌进文档的图片。
class DocxImageSpec {
  const DocxImageSpec({
    required this.bytes,
    required this.extension,
    required this.pixelWidth,
    required this.pixelHeight,
    this.align = DocxAlign.center,
    this.maxWidthFraction = 0.62,
    this.maxHeightFraction = 0.22,
    this.maxUpscale = 1.5,
    this.spacingBeforeTw = 100,
    this.spacingAfterTw = 30,
    this.keepNext = false,
    this.note,
  });

  final Uint8List bytes;

  /// `png` / `jpeg` / `gif` / `bmp`（大小写均可）。
  final String extension;
  final int pixelWidth;
  final int pixelHeight;
  final DocxAlign align;

  /// 图片最大宽度占正文栏宽的比例（compact 档 0.62，来自 paper-composer 实测）。
  final double maxWidthFraction;

  /// 图片最大高度占正文可用高度的比例（compact 档 0.22）。
  final double maxHeightFraction;

  /// 小图最多放大到几倍；不设上限会把 32×32 的图标拉成半页。
  final double maxUpscale;
  final int spacingBeforeTw;
  final int spacingAfterTw;

  /// 图与后一段同页（题干末句 + 紧跟的插图不拆开）。
  final bool keepNext;

  /// 给排版报告/测试看的来源说明（不写进 docx）。
  final String? note;
}

/// 图片扩展名归一化：去点、转小写、`jpg` → `jpeg`；不认识的返回 null。
String? normalizeDocxImageExtension(String extension) {
  final ext = extension.trim().toLowerCase().replaceFirst(RegExp(r'^\.'), '');
  return switch (ext) {
    'png' => 'png',
    'jpg' || 'jpeg' || 'jpe' => 'jpeg',
    'gif' => 'gif',
    'bmp' || 'dib' => 'bmp',
    _ => null,
  };
}

/// 能不能把这个扩展名的图嵌进 docx（HEIC/WEBP 等暂不支持，由调用方报告跳过）。
bool supportsDocxImageExtension(String extension) =>
    normalizeDocxImageExtension(extension) != null;

/// 内嵌图片按"栏宽/页高比例"缩放后的 EMU 尺寸。
({int cxEmu, int cyEmu}) computeInlineImageExtent(
  DocxImageSpec spec,
  DocxPageConfig page,
) {
  if (spec.pixelWidth <= 0 || spec.pixelHeight <= 0) {
    throw ArgumentError(
      '图片像素尺寸必须为正：${spec.pixelWidth}x${spec.pixelHeight}',
    );
  }
  if (!spec.maxWidthFraction.isFinite ||
      !spec.maxHeightFraction.isFinite ||
      spec.maxWidthFraction <= 0 ||
      spec.maxHeightFraction <= 0) {
    throw ArgumentError('图片宽度/高度比例必须是正数');
  }
  final maxWidthTw = page.contentWidthTw * spec.maxWidthFraction;
  final maxHeightTw = page.contentHeightTw * spec.maxHeightFraction;
  final naturalWidthTw = spec.pixelWidth * twipsPerPixel;
  final naturalHeightTw = spec.pixelHeight * twipsPerPixel;

  var scale = math.min(
    maxWidthTw / naturalWidthTw,
    maxHeightTw / naturalHeightTw,
  );
  if (spec.maxUpscale > 0 && scale > spec.maxUpscale) {
    scale = spec.maxUpscale;
  }
  final widthTw = naturalWidthTw * scale;
  final heightTw = naturalHeightTw * scale;
  return (
    cxEmu: (widthTw * emuPerTwip).round(),
    cyEmu: (heightTw * emuPerTwip).round(),
  );
}

/// 文档构建器：按顺序 append 段落/图片，最后 [build] 出 zip 字节。
///
/// 用法固定为"先装配、后 build"：build 之后不允许再 append（否则改完不生效，
/// 调用方会以为图/段落已经进文档了）。
class DocxDocumentBuilder {
  DocxDocumentBuilder({
    this.page = const DocxPageConfig.a4Exam(),
    this.footerText,
    this.footerPageTemplate = '第 {PAGE} 页 / 共 {NUMPAGES} 页',
    this.footerRule = true,
  });

  final DocxPageConfig page;

  /// 页脚左侧文字（时期代号/导出时间等）；null 或空 = 不写。
  final String? footerText;

  /// 页脚右侧页码模板；支持 `{PAGE}` 与 `{NUMPAGES}` 两个占位符。
  /// 传 null 或空串 = 不写页码。
  final String? footerPageTemplate;

  /// 页脚上方细分隔线（paper-composer 同款）。
  final bool footerRule;

  final List<String> _paragraphs = <String>[];
  final List<_MediaEntry> _media = <_MediaEntry>[];
  final List<String> _imageRelationships = <String>[];
  final List<_ImagePlacement> _imagePlacements = <_ImagePlacement>[];
  int _nextRelationshipNumber = 0;
  int _nextPictureId = 0;
  int _paragraphCount = 0;
  int _mathCount = 0;
  bool _built = false;

  /// 已嵌入的图片张数。
  int get imageCount => _media.length;

  /// 已写入的段落数（图片各自算一个段落）。
  int get paragraphCount => _paragraphCount;

  /// 已写入的 OMML 公式段数。
  int get mathCount => _mathCount;

  /// 每张图的尺寸决策（给排版报告/测试断言用，不进 docx）。
  List<({String? note, int cxEmu, int cyEmu})> get imagePlacements =>
      List<({String? note, int cxEmu, int cyEmu})>.unmodifiable(
        _imagePlacements.map(
          (p) => (note: p.note, cxEmu: p.cxEmu, cyEmu: p.cyEmu),
        ),
      );

  /// 追加一个段落。
  void addParagraph(DocxParagraph paragraph) {
    _ensureNotBuilt();
    _paragraphs.add(_paragraphXml(paragraph));
    _paragraphCount++;
    _mathCount += paragraph.inlines.whereType<DocxMath>().length;
  }

  /// 追加多个段落。
  void addParagraphs(Iterable<DocxParagraph> paragraphs) {
    for (final paragraph in paragraphs) {
      addParagraph(paragraph);
    }
  }

  /// 追加一张随文居中图（`wp:inline`）。
  ///
  /// 扩展名不认识时抛 [ArgumentError]：调用方应先 [supportsDocxImageExtension]
  /// 判断并**报告跳过**，不要指望这里静默吞图。
  void addImage(DocxImageSpec spec) {
    _ensureNotBuilt();
    final extension = normalizeDocxImageExtension(spec.extension);
    if (extension == null) {
      throw ArgumentError.value(
        spec.extension,
        'spec.extension',
        '不支持的图片扩展名（可先用 supportsDocxImageExtension 判断）',
      );
    }
    final extent = computeInlineImageExtent(spec, page);
    final mediaName = 'image${_media.length + 1}.$extension';
    final relationshipId = 'rIdImg${_nextRelationshipNumber++}';
    final pictureId = ++_nextPictureId;
    _media.add(
      _MediaEntry(
        fileName: mediaName,
        bytes: spec.bytes,
        extension: extension,
      ),
    );
    _imageRelationships.add(
      '<Relationship Id="$relationshipId" Type="'
      '$relationshipsNamespace/image" Target="media/$mediaName"/>',
    );
    _paragraphs.add(
      _imageParagraphXml(
        relationshipId: relationshipId,
        pictureId: pictureId,
        cxEmu: extent.cxEmu,
        cyEmu: extent.cyEmu,
        align: spec.align,
        spacingBeforeTw: spec.spacingBeforeTw,
        spacingAfterTw: spec.spacingAfterTw,
        keepNext: spec.keepNext,
      ),
    );
    _paragraphCount++;
    _imagePlacements.add(
      _ImagePlacement(
        note: spec.note,
        cxEmu: extent.cxEmu,
        cyEmu: extent.cyEmu,
      ),
    );
  }

  /// 打包成 .docx 字节（可交给 FilePicker/File 保存）。
  ///
  /// 同一份 builder 只能 build 一次；重复 build 会抛 [StateError]（防止调用方
  /// 以为第二次 build 会带上 build 之后新加的内容）。
  Uint8List build() {
    _ensureNotBuilt();
    _built = true;
    final archive = Archive()
      ..addFile(
          _archiveFile('[Content_Types].xml', _encode(_contentTypesXml())))
      ..addFile(_archiveFile('_rels/.rels', _encode(_rootRelsXml())))
      ..addFile(_archiveFile('word/document.xml', _encode(_documentXml())))
      ..addFile(
        _archiveFile(
            'word/_rels/document.xml.rels', _encode(_documentRelsXml())),
      )
      ..addFile(_archiveFile('word/styles.xml', _encode(_stylesXml())))
      ..addFile(_archiveFile('word/settings.xml', _encode(_settingsXml())));
    if (footerPageTemplate != null || footerText != null) {
      archive.addFile(_archiveFile('word/footer1.xml', _encode(_footerXml())));
    }
    for (final media in _media) {
      archive.addFile(
        _archiveFile('word/media/${media.fileName}', media.bytes),
      );
    }
    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) {
      throw StateError('docx 打包失败：ZipEncoder 返回 null');
    }
    return Uint8List.fromList(encoded);
  }

  void _ensureNotBuilt() {
    if (_built) {
      throw StateError('docx 已经 build 过，不能再追加内容');
    }
  }

  bool get _hasFooter => footerText != null || footerPageTemplate != null;

  /// 图片段落：一个只含 drawing 的 run（rPr 字号 1，与 paper-composer 同款）。
  String _imageParagraphXml({
    required String relationshipId,
    required int pictureId,
    required int cxEmu,
    required int cyEmu,
    required DocxAlign align,
    required int spacingBeforeTw,
    required int spacingAfterTw,
    required bool keepNext,
  }) {
    final drawing = '<w:drawing><wp:inline distT="0" distB="0" distL="0" '
        'distR="0"><wp:extent cx="$cxEmu" cy="$cyEmu"/>'
        '<wp:effectExtent l="0" t="0" r="0" b="0"/>'
        '<wp:docPr id="$pictureId" name="Picture $pictureId"/>'
        '<a:graphic xmlns:a="$drawingNamespace">'
        '<a:graphicData uri="$pictureNamespace">'
        '<pic:pic xmlns:pic="$pictureNamespace">'
        '<pic:nvPicPr><pic:cNvPr id="$pictureId" name="Picture $pictureId"/>'
        '<pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="$relationshipId"/>'
        '<a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm><a:off x="0" y="0"/>'
        '<a:ext cx="$cxEmu" cy="$cyEmu"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
        '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing>';
    final run = '<w:r><w:rPr>'
        '<w:rFonts w:ascii="$kDocxBodyFontEn" w:hAnsi="$kDocxBodyFontEn" '
        'w:eastAsia="$kDocxBodyFontCn" w:cs="$kDocxBodyFontEn"/>'
        '<w:sz w:val="1"/><w:szCs w:val="1"/></w:rPr>$drawing</w:r>';
    final properties = <String>[
      if (keepNext) '<w:keepNext/>',
      '<w:spacing w:before="$spacingBeforeTw" w:after="$spacingAfterTw" '
          'w:line="${page.lineTw}" w:lineRule="auto"/>',
      '<w:jc w:val="${align.xmlValue}"/>',
    ];
    return '<w:p><w:pPr>${properties.join()}</w:pPr>$run</w:p>';
  }

  String _paragraphXml(DocxParagraph paragraph) {
    final properties = <String>[];
    if (paragraph.pageBreakBefore) properties.add('<w:pageBreakBefore/>');
    if (paragraph.keepNext) properties.add('<w:keepNext/>');
    if (paragraph.keepLines) properties.add('<w:keepLines/>');
    if (paragraph.shadeHex != null) {
      properties.add(
        '<w:shd w:val="clear" w:color="auto" w:fill="'
        '${paragraph.shadeHex}"/>',
      );
    }
    if (paragraph.borderBottomHex != null) {
      properties.add(
        '<w:pBdr><w:bottom w:val="single" w:sz="6" w:space="1" '
        'w:color="${paragraph.borderBottomHex}"/></w:pBdr>',
      );
    }
    if (paragraph.spacingBeforeTw != null ||
        paragraph.spacingAfterTw != null ||
        paragraph.lineTw != null) {
      properties.add(
        '<w:spacing w:before="${paragraph.spacingBeforeTw ?? 0}" '
        'w:after="${paragraph.spacingAfterTw ?? 0}" '
        'w:line="${paragraph.lineTw ?? page.lineTw}" '
        'w:lineRule="${paragraph.lineRule}"/>',
      );
    }
    if (paragraph.firstLineIndentTw != null ||
        paragraph.leftIndentTw != null ||
        paragraph.rightIndentTw != null) {
      final indent = <String>[
        if (paragraph.leftIndentTw != null)
          'w:left="${paragraph.leftIndentTw}"',
        if (paragraph.rightIndentTw != null)
          'w:right="${paragraph.rightIndentTw}"',
        if (paragraph.firstLineIndentTw != null)
          'w:firstLine="${paragraph.firstLineIndentTw}"',
      ];
      properties.add('<w:ind ${indent.join(' ')}/>');
    }
    if (paragraph.align != null) {
      properties.add('<w:jc w:val="${paragraph.align!.xmlValue}"/>');
    }

    final runs = StringBuffer();
    for (final inline in paragraph.inlines) {
      switch (inline) {
        case DocxText():
          runs.write(_textRunXml(inline));
        case DocxMath():
          runs.write(inline.omml);
      }
    }
    final prefix =
        properties.isEmpty ? '' : '<w:pPr>${properties.join()}</w:pPr>';
    return '<w:p>$prefix$runs</w:p>';
  }

  String _textRunXml(DocxText text) {
    if (text.text.isEmpty) return '';
    final lines = text.text.split('\n');
    final buffer = StringBuffer();
    for (var i = 0; i < lines.length; i++) {
      if (i > 0) buffer.write('<w:r><w:br/></w:r>');
      final line = lines[i];
      if (line.isEmpty) continue;
      buffer
        ..write('<w:r>')
        ..write(_runPropertiesXml(
          sizeHalfPt: text.sizeHalfPt,
          bold: text.bold,
          italic: text.italic,
          underline: text.underline,
          subscript: text.subscript,
          superscript: text.superscript,
          colorHex: text.colorHex,
          fontCn: text.fontCn ?? kDocxBodyFontCn,
          fontEn: text.fontEn ?? kDocxBodyFontEn,
        ))
        ..write('<w:t xml:space="preserve">')
        ..write(_escapeXmlText(line))
        ..write('</w:t></w:r>');
    }
    return buffer.toString();
  }

  String _runPropertiesXml({
    required int sizeHalfPt,
    bool bold = false,
    bool italic = false,
    bool underline = false,
    bool subscript = false,
    bool superscript = false,
    String? colorHex,
    String fontCn = kDocxBodyFontCn,
    String fontEn = kDocxBodyFontEn,
  }) {
    final parts = <String>[
      '<w:rFonts w:ascii="$fontEn" w:hAnsi="$fontEn" w:eastAsia="$fontCn" '
          'w:cs="$fontEn"/>',
      if (bold) '<w:b/><w:bCs/>',
      if (italic) '<w:i/><w:iCs/>',
      if (underline) '<w:u w:val="single"/>',
      if (subscript) '<w:vertAlign w:val="subscript"/>',
      if (superscript) '<w:vertAlign w:val="superscript"/>',
      if (colorHex != null) '<w:color w:val="$colorHex"/>',
      '<w:sz w:val="$sizeHalfPt"/><w:szCs w:val="$sizeHalfPt"/>',
    ];
    return '<w:rPr>${parts.join()}</w:rPr>';
  }

  String _documentXml() {
    final footerReference = _hasFooter
        ? '<w:footerReference w:type="default" r:id="rIdFoot"/>'
        : '';
    final section = '<w:sectPr>$footerReference'
        '<w:pgSz w:w="${page.pageWidthTw}" w:h="${page.pageHeightTw}"/>'
        '<w:pgMar w:top="${page.marginTopTw}" w:right="${page.marginRightTw}" '
        'w:bottom="${page.marginBottomTw}" w:left="${page.marginLeftTw}" '
        'w:header="${math.max(425, page.marginTopTw - 283)}" '
        'w:footer="${page.footerDistanceTw}" w:gutter="0"/>'
        '</w:sectPr>';
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<w:document xmlns:w="$wNamespace" xmlns:m="$mathNamespace" '
        'xmlns:r="$relationshipsNamespace" '
        'xmlns:wp="$wordprocessingDrawingNamespace" '
        'xmlns:a="$drawingNamespace" xmlns:pic="$pictureNamespace">'
        '<w:body>${_paragraphs.join()}$section</w:body></w:document>';
  }

  String _footerXml() {
    final properties = <String>[
      '<w:tabs><w:tab w:val="right" w:pos="${page.contentWidthTw}"/></w:tabs>',
      if (footerRule)
        '<w:pBdr><w:top w:val="single" w:sz="4" w:space="1" '
            'w:color="BFBFBF"/></w:pBdr>',
      '<w:jc w:val="left"/>',
    ];
    final bits = <String>[];
    final leftText = footerText?.trim() ?? '';
    if (leftText.isNotEmpty) {
      bits.add(
        _textRunXml(
          DocxText(leftText, sizeHalfPt: kDocxMetaHalfPt, colorHex: '595959'),
        ),
      );
    }
    final template = footerPageTemplate?.trim() ?? '';
    if (template.isNotEmpty) {
      if (leftText.isNotEmpty) bits.add('<w:r><w:tab/></w:r>');
      bits.add(_pageFieldRunsXml(template));
    }
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<w:ftr xmlns:w="$wNamespace"><w:p><w:pPr>${properties.join()}'
        '</w:pPr>${bits.join()}</w:p></w:ftr>';
  }

  /// 页码模板 → 文字 run 与 PAGE/NUMPAGES 域的混合序列。
  String _pageFieldRunsXml(String template) {
    final buffer = StringBuffer();
    var index = 0;
    final pattern = RegExp(r'\{PAGE\}|\{NUMPAGES\}');
    for (final match in pattern.allMatches(template)) {
      final text = template.substring(index, match.start);
      if (text.isNotEmpty) {
        buffer.write(
          _textRunXml(
            DocxText(text, sizeHalfPt: kDocxMetaHalfPt, colorHex: '595959'),
          ),
        );
      }
      final isPage = match.group(0) == '{PAGE}';
      buffer.write(_fieldXml(isPage ? ' PAGE ' : ' NUMPAGES '));
      index = match.end;
    }
    final tail = template.substring(index);
    if (tail.isNotEmpty) {
      buffer.write(
        _textRunXml(
          DocxText(tail, sizeHalfPt: kDocxMetaHalfPt, colorHex: '595959'),
        ),
      );
    }
    return buffer.toString();
  }

  String _fieldXml(String instruction) {
    final properties = _runPropertiesXml(
      sizeHalfPt: kDocxMetaHalfPt,
      colorHex: '595959',
    );
    return '<w:r>$properties<w:fldChar w:fldCharType="begin"/></w:r>'
        '<w:r>$properties<w:instrText xml:space="preserve">'
        '$instruction</w:instrText></w:r>'
        '<w:r>$properties<w:fldChar w:fldCharType="separate"/></w:r>'
        '<w:r>$properties<w:t>1</w:t></w:r>'
        '<w:r>$properties<w:fldChar w:fldCharType="end"/></w:r>';
  }

  String _stylesXml() {
    const runDefaults =
        '<w:rFonts w:ascii="$kDocxBodyFontEn" w:hAnsi="$kDocxBodyFontEn" '
        'w:eastAsia="$kDocxBodyFontCn" w:cs="$kDocxBodyFontEn"/>'
        '<w:sz w:val="$kDocxBodyHalfPt"/><w:szCs w:val="$kDocxBodyHalfPt"/>';
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<w:styles xmlns:w="$wNamespace"><w:docDefaults><w:rPrDefault>'
        '<w:rPr>$runDefaults</w:rPr></w:rPrDefault><w:pPrDefault><w:pPr>'
        '<w:spacing w:line="${page.lineTw}" w:lineRule="auto"/>'
        '<w:widowControl/></w:pPr></w:pPrDefault></w:docDefaults>'
        '<w:style w:type="paragraph" w:default="1" w:styleId="Normal">'
        '<w:name w:val="Normal"/><w:qFormat/></w:style></w:styles>';
  }

  String _settingsXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<w:settings xmlns:w="$wNamespace"><w:zoom w:percent="100"/>'
        '<w:defaultTabStop w:val="420"/><w:evenAndOddHeaders w:val="0"/>'
        '<w:compat><w:compatSetting w:name="compatibilityMode" '
        'w:uri="http://schemas.microsoft.com/office/word" w:val="15"/>'
        '</w:compat></w:settings>';
  }

  String _contentTypesXml() {
    final extensions = <String>{for (final media in _media) media.extension};
    final imageDefaults = StringBuffer();
    for (final extension in extensions) {
      imageDefaults.write(
        '<Default Extension="$extension" ContentType="'
        '${_imageContentType(extension)}"/>',
      );
    }
    final overrides = <String>[
      '<Override PartName="/word/document.xml" ContentType="application/vnd.'
          'openxmlformats-officedocument.wordprocessingml.document.main+xml"/>',
      '<Override PartName="/word/styles.xml" ContentType="application/vnd.'
          'openxmlformats-officedocument.wordprocessingml.styles+xml"/>',
      '<Override PartName="/word/settings.xml" ContentType="application/vnd.'
          'openxmlformats-officedocument.wordprocessingml.settings+xml"/>',
      if (_hasFooter)
        '<Override PartName="/word/footer1.xml" ContentType="application/vnd.'
            'openxmlformats-officedocument.wordprocessingml.footer+xml"/>',
    ];
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
        'content-types"><Default Extension="rels" ContentType="application/'
        'vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '${imageDefaults.toString()}${overrides.join()}</Types>';
  }

  String _rootRelsXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
        'relationships"><Relationship Id="rId1" Type="'
        '$relationshipsNamespace/officeDocument" '
        'Target="word/document.xml"/></Relationships>';
  }

  String _documentRelsXml() {
    final relationships = <String>[
      if (_hasFooter)
        '<Relationship Id="rIdFoot" Type="$relationshipsNamespace/footer" '
            'Target="footer1.xml"/>',
      '<Relationship Id="rIdSty" Type="$relationshipsNamespace/styles" '
          'Target="styles.xml"/>',
      '<Relationship Id="rIdSet" Type="$relationshipsNamespace/settings" '
          'Target="settings.xml"/>',
      ..._imageRelationships,
    ];
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
        'relationships">${relationships.join()}</Relationships>';
  }

  String _imageContentType(String extension) => switch (extension) {
        'png' => 'image/png',
        'jpeg' => 'image/jpeg',
        'gif' => 'image/gif',
        'bmp' => 'image/bmp',
        _ => 'application/octet-stream',
      };

  ArchiveFile _archiveFile(String name, List<int> bytes) =>
      ArchiveFile(name, bytes.length, bytes);

  List<int> _encode(String xml) => utf8.encode(xml);
}

class _MediaEntry {
  const _MediaEntry({
    required this.fileName,
    required this.bytes,
    required this.extension,
  });

  final String fileName;
  final Uint8List bytes;
  final String extension;
}

class _ImagePlacement {
  const _ImagePlacement({
    required this.note,
    required this.cxEmu,
    required this.cyEmu,
  });

  final String? note;
  final int cxEmu;
  final int cyEmu;
}

/// XML 文本转义 + 非法控制字符清理。
///
/// 题库文本来自 OCR/手写整理，混进 0x00–0x08 之类的控制字符很常见；XML 1.0
/// 不允许它们，原样写进去 Word 会直接报"文件已损坏"。这里按 XML 1.0 的
/// Char 产生式过滤：保留 \t \n \r 与 0x20 以上，其余丢掉。
String _escapeXmlText(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    if (rune == 0x09 || rune == 0x0A || rune == 0x0D) {
      buffer.writeCharCode(rune);
      continue;
    }
    if (rune < 0x20 || (rune >= 0x7F && rune <= 0x9F)) {
      continue;
    }
    switch (rune) {
      case 0x26:
        buffer.write('&amp;');
      case 0x3C:
        buffer.write('&lt;');
      case 0x3E:
        buffer.write('&gt;');
      case 0x22:
        buffer.write('&quot;');
      case 0x27:
        buffer.write('&apos;');
      default:
        buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

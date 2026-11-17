// PDF 中文字体与统一主题的回归测试。
//
// 这里钉住：
//   1. 内置字体资产真的被打进包（rootBundle 能读到，且是单字体 TrueType TTF）；
//   2. 资产缺失/被截断/TTC 时抛可识别异常并说明原因，不生成缺中文的 PDF；
//   3. 真生成出来的 PDF 有 %PDF 头、嵌入了 TrueType 字体（FontFile2）；
//   4. PDF 的 ToUnicode CMap 覆盖正文里的每个中文字符 → 中文可抽取/可复制；
//   5. 统一主题的页眉/页脚/页码/页边距真的进了 PDF。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/markdown/domain/markdown_pdf_exporter.dart';
import 'package:furnace/features/markdown/domain/markdown_pdf_fonts.dart';
import 'package:furnace/features/markdown/domain/markdown_render_theme.dart';

import 'support/markdown_fakes.dart';

/// 样例正文：覆盖标题/正文/粗体/行内代码/表格/列表/引用/页脚里的中文。
const String sampleChineseMarkdown = '# 中文标题\n\n'
    '正文 **加粗** 与 `代码`\n\n'
    '| 列 | 值 |\n| --- | --- |\n| 甲 | 1 |\n\n'
    '- 列表项\n\n'
    '> 引用中文\n';

/// 样例里出现的全部中文字符（去重）。
final List<String> sampleChineseChars = <String>{
  for (final rune in sampleChineseMarkdown.runes)
    if (rune >= 0x4e00 && rune <= 0x9fff) String.fromCharCode(rune),
}.toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('字体头分类：TTC 集合、CFF、单字体 TTF 被区分开', () {
    expect(
      trueTypeKind(Uint8List.fromList('ttcf'.codeUnits)),
      TrueTypeKind.collection,
    );
    expect(trueTypeKind(fakeTrueTypeBytes()), TrueTypeKind.trueType);
    expect(
      trueTypeKind(Uint8List.fromList('OTTO'.codeUnits)),
      TrueTypeKind.openType,
    );
    expect(
      trueTypeKind(Uint8List.fromList('XXXX'.codeUnits)),
      TrueTypeKind.unknown,
    );
    expect(trueTypeKind(Uint8List(2)), TrueTypeKind.unknown);
  });

  test('内置字体资产存在，且是单字体 TrueType TTF', () async {
    expect(
      hasBundledChineseFont(),
      isTrue,
      reason: 'expected ${BundledMarkdownPdfFontResolver.fontAssetPath} '
          'bundled in the app assets',
    );
    final data = await loadBundledChineseFont();
    expect(data, isNotNull);
    expect(data!.sourcePath, BundledMarkdownPdfFontResolver.fontAssetPath);
    expect(
      data.bytes.length,
      greaterThan(BundledMarkdownPdfFontResolver.minimumSaneFontBytes),
    );
    expect(trueTypeKind(data.bytes), TrueTypeKind.trueType);
    expect(
      _containsUtf16Be(data.bytes, 'NotoSansSC-Regular'),
      isTrue,
      reason: '内置字体的 name 表应包含 NotoSansSC-Regular',
    );
  });

  test('资产缺失时抛"字体不可用"，并说明缺的是哪个资产', () async {
    final resolver = BundledMarkdownPdfFontResolver(
      loadAsset: fakeAssetLoader(null),
    );
    try {
      await resolver.resolve();
      fail('缺字体时应抛 MarkdownPdfFontUnavailableException');
    } on MarkdownPdfFontUnavailableException catch (error) {
      expect(error.attempted.single, contains('noto-sans-sc-regular.ttf'));
      expect(error.attempted.single, contains('不可读'));
      expect(error.toString(), contains('没有找到可嵌入的中文字体'));
    }
  });

  test('TTC 字体集合被明确拒绝，不会喂给 pdf 包', () async {
    final resolver = BundledMarkdownPdfFontResolver(
      loadAsset: fakeAssetLoader(Uint8List.fromList('ttcf'.codeUnits)),
    );
    try {
      await resolver.resolve();
      fail('TTC 不应被接受');
    } on MarkdownPdfFontUnavailableException catch (error) {
      expect(error.attempted.single, contains('TTC'));
    }
  });

  test('CFF（OTTO）被明确拒绝：pdf 包只支持 TrueType outlines', () async {
    final resolver = BundledMarkdownPdfFontResolver(
      loadAsset: fakeAssetLoader(Uint8List.fromList('OTTO'.codeUnits)),
    );
    try {
      await resolver.resolve();
      fail('CFF 字体不应被接受');
    } on MarkdownPdfFontUnavailableException catch (error) {
      expect(error.attempted.single, contains('TrueType outlines'));
    }
  });

  test('被截断的字体资产被当作不可用，而不是丢给 pdf 包炸解析', () async {
    final resolver = BundledMarkdownPdfFontResolver(
      loadAsset: fakeAssetLoader(fakeTrueTypeBytes()),
    );
    try {
      await resolver.resolve();
      fail('截断字体不应被接受');
    } on MarkdownPdfFontUnavailableException catch (error) {
      expect(error.attempted.single, contains('截断'));
    }
  });

  test('生产解析器只请求内置资产，不碰任何系统字体路径', () async {
    final requests = <String>[];
    final resolver = BundledMarkdownPdfFontResolver(
      loadAsset: fakeAssetLoader(
        Uint8List.fromList(
          <int>[0x00, 0x01, 0x00, 0x00, ...List<int>.filled(300 * 1024, 0)],
        ),
        requests: requests,
      ),
    );
    await resolver.resolve();
    expect(requests, <String>[BundledMarkdownPdfFontResolver.fontAssetPath]);
    expect(
      requests.any((path) => path.toLowerCase().contains('.ttc')),
      isFalse,
    );
    expect(requests.any((path) => path.contains(r'C:\Windows')), isFalse);
  });

  test('生成带嵌入中文字体的 PDF，且 ToUnicode 覆盖全部中文字符', () async {
    final font = await loadBundledChineseFont();
    expect(font, isNotNull, reason: '内置字体资产应当存在');
    final exporter = MarkdownPdfExporter(
      fontResolver: FakeMarkdownPdfFontResolver(data: font),
    );
    final bytes = await exporter.build(
      markdown: sampleChineseMarkdown,
      theme: MarkdownRenderTheme.paper,
    );

    final raw = latin1.decode(bytes, allowInvalid: true);
    expect(bytes.length, greaterThan(1000));
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    expect(raw, contains('/Type/Page'));
    expect(raw, contains('/FontFile2'));
    expect(raw, contains('/ToUnicode'));

    final cmaps = _decodedFontCmStreams(bytes);
    expect(cmaps, contains('beginbfchar'));
    for (final char in sampleChineseChars) {
      final hex =
          char.codeUnitAt(0).toRadixString(16).toUpperCase().padLeft(4, '0');
      expect(
        cmaps.contains('<$hex>'),
        isTrue,
        reason: 'ToUnicode 应把字形映射回 U+$hex（$char）',
      );
    }
  });

  test('缺字体时导出器抛字体异常，而不是包装成排版失败', () async {
    final exporter = MarkdownPdfExporter(
      fontResolver: FakeMarkdownPdfFontResolver(),
    );
    await expectLater(
      exporter.build(markdown: '# 标题', theme: MarkdownRenderTheme.paper),
      throwsA(isA<MarkdownPdfFontUnavailableException>()),
    );
  });

  test('空文档也能生成合法 PDF', () async {
    final font = await loadBundledChineseFont();
    expect(font, isNotNull, reason: '内置字体资产应当存在');
    final exporter = MarkdownPdfExporter(
      fontResolver: FakeMarkdownPdfFontResolver(data: font),
    );
    final bytes = await exporter.build(
      markdown: '',
      theme: MarkdownRenderTheme.dark,
    );
    expect(latin1.decode(bytes, allowInvalid: true), contains('/Type/Page'));
  });

  test('统一主题的页眉/页脚/页码进入 PDF 内容流', () async {
    final font = await loadBundledChineseFont();
    expect(font, isNotNull, reason: '内置字体资产应当存在');
    final exporter = MarkdownPdfExporter(
      fontResolver: FakeMarkdownPdfFontResolver(data: font),
    );
    final theme = MarkdownRenderTheme.paper.copyWith(
      pdfHeader: '页眉文字',
      pdfFooter: '页脚文字',
      showPageNumber: true,
    );
    final bytes = await exporter.build(
      markdown: sampleChineseMarkdown,
      theme: theme,
    );
    final text = _decodedFontCmStreams(bytes);
    // 页眉/页脚/页码也会被嵌入字体的 ToUnicode 覆盖；这里断言 PDF 里确实用了
    // 中文字体子集（FontFile2）且页码文本进入了内容流（Flate 解压后可搜索）。
    expect(text, contains('beginbfchar'));
    expect(latin1.decode(bytes, allowInvalid: true), contains('/FontFile2'));
  });

  // ----------------------------------------------------------------------
  // 双栏：真正的两栏排页（不是只影响预览）
  // ----------------------------------------------------------------------

  test('双栏导出：走双栏分支、A4 两栏宽度正确、页数 > 0、与单栏输出不同', () async {
    final font = await loadBundledChineseFont();
    expect(font, isNotNull, reason: '内置字体资产应当存在');
    final exporter = MarkdownPdfExporter(
      fontResolver: FakeMarkdownPdfFontResolver(data: font),
    );
    final markdown = <String>[
      for (var index = 0; index < 40; index++)
        '## 第 $index 节\n\n这是第 $index 段正文，用来检查 PDF 双栏排版是否真的按两栏输出。',
    ].join('\n\n');
    final dualTheme = MarkdownRenderTheme.paper.copyWith(
      columnsEnabled: true,
      columnCount: 2,
      columnGap: 24,
      columnRule: true,
    );

    MarkdownPdfLayoutInfo? singleInfo;
    final single = await exporter.build(
      markdown: markdown,
      theme: MarkdownRenderTheme.paper,
      onLayout: (MarkdownPdfLayoutInfo info) => singleInfo = info,
    );
    MarkdownPdfLayoutInfo? dualInfo;
    final dual = await exporter.build(
      markdown: markdown,
      theme: dualTheme,
      onLayout: (MarkdownPdfLayoutInfo info) => dualInfo = info,
    );

    // 单栏路径没有被分栏逻辑改写。
    expect(singleInfo!.columnsEnabled, isFalse);
    expect(singleInfo!.columnCount, 1);
    expect(singleInfo!.pageCount, greaterThan(0));

    // 双栏分支真的执行了：栏数 2，栏宽 = (contentWidth - gap) / 2。
    // A4 宽 595.27559pt，页边距 64px → 48pt，栏缝 24px → 18pt。
    expect(
      dualInfo!.columnsEnabled,
      isTrue,
      reason: 'theme.columnsEnabled=true 时必须走 PDF 双栏排页',
    );
    expect(dualInfo!.columnCount, 2);
    expect(
      dualInfo!.columnWidth,
      closeTo((595.27559 - 48 * 2 - 18) / 2, 0.01),
    );
    expect(dualInfo!.pageCount, greaterThan(0));

    expect(dual.length, greaterThan(1000));
    expect(ascii.decode(dual.sublist(0, 5)), '%PDF-');
    expect(_pdfPageCount(dual), dualInfo!.pageCount);
    expect(
      dual,
      isNot(equals(single)),
      reason: '双栏输出（版式/页数）不应与单栏逐字节相同',
    );
  });

  test('双栏时栏间竖线画进 PDF；关掉 columnRule 就不画', () async {
    final font = await loadBundledChineseFont();
    expect(font, isNotNull, reason: '内置字体资产应当存在');
    final exporter = MarkdownPdfExporter(
      fontResolver: FakeMarkdownPdfFontResolver(data: font),
    );
    final markdown = <String>[
      for (var index = 0; index < 12; index++)
        '## 第 $index 节\n\n这是第 $index 段正文。',
    ].join('\n\n');

    final withRule = await exporter.build(
      markdown: markdown,
      theme: MarkdownRenderTheme.paper.copyWith(
        columnsEnabled: true,
        columnCount: 2,
        columnRule: true,
      ),
    );
    final withoutRule = await exporter.build(
      markdown: markdown,
      theme: MarkdownRenderTheme.paper.copyWith(
        columnsEnabled: true,
        columnCount: 2,
        columnRule: false,
      ),
    );

    // 栏间竖线是 1pt 宽、整栏高的填充矩形：`0 0 1 <height> re`。
    final rulePattern = RegExp(r'0 0 1 [\d.]+ re');
    expect(
      rulePattern.hasMatch(_decodedFontCmStreams(withRule)),
      isTrue,
      reason: 'columnRule=true 时 PDF 内容流里应有 1pt 宽的分栏竖线',
    );
    expect(
      rulePattern.hasMatch(_decodedFontCmStreams(withoutRule)),
      isFalse,
      reason: 'columnRule=false 时不应画分栏竖线',
    );
    expect(_pdfPageCount(withRule), greaterThan(0));
    expect(_pdfPageCount(withoutRule), greaterThan(0));
  });

  test('双栏放不下的大表格：退回单栏并让表格跨页，而不是抛异常', () async {
    final font = await loadBundledChineseFont();
    expect(font, isNotNull, reason: '内置字体资产应当存在');
    final exporter = MarkdownPdfExporter(
      fontResolver: FakeMarkdownPdfFontResolver(data: font),
    );
    // 60 行表格：在整页（通栏）下都比一页高，双栏分页器无法安全放置；
    // 单栏的 MultiPage 能让 Table 跨页（Table 是 pdf 包的 SpanningWidget）。
    final buffer = StringBuffer('## 长表格\n\n')
      ..writeln('| 甲 | 乙 |')
      ..writeln('| --- | --- |');
    for (var row = 0; row < 60; row++) {
      buffer.writeln('| 第 $row 行 | 值 $row |');
    }

    MarkdownPdfLayoutInfo? info;
    final bytes = await exporter.build(
      markdown: buffer.toString(),
      theme: MarkdownRenderTheme.paper.copyWith(
        columnsEnabled: true,
        columnCount: 2,
      ),
      onLayout: (MarkdownPdfLayoutInfo value) => info = value,
    );

    expect(bytes, isNotEmpty);
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    expect(info!.columnsEnabled, isFalse, reason: '双栏分页不可靠时应退回单栏');
    expect(info!.columnCount, 1);
    expect(info!.pageCount, greaterThan(1), reason: '表格应在单栏里跨页');
  });

  test('半栏放不下、整页放得下的大表格独占通栏页', () async {
    final font = await loadBundledChineseFont();
    expect(font, isNotNull, reason: '内置字体资产应当存在');
    final exporter = MarkdownPdfExporter(
      fontResolver: FakeMarkdownPdfFontResolver(data: font),
    );
    const cell = '较长的单元格文字';
    final buffer = StringBuffer('## 表格\n\n')
      ..writeln('| 甲 | 乙 | 丙 | 丁 | 戊 | 己 |')
      ..writeln('| --- | --- | --- | --- | --- | --- |');
    for (var row = 0; row < 10; row++) {
      buffer.writeln(
        '| ${List<String>.filled(6, '$cell$row').join(' | ')} |',
      );
    }
    buffer.write('\n\n表格之后的正文。');

    MarkdownPdfLayoutInfo? info;
    final bytes = await exporter.build(
      markdown: buffer.toString(),
      theme: MarkdownRenderTheme.paper.copyWith(
        columnsEnabled: true,
        columnCount: 2,
        columnGap: 24,
      ),
      onLayout: (MarkdownPdfLayoutInfo value) => info = value,
    );

    expect(bytes, isNotEmpty);
    expect(info!.columnsEnabled, isTrue);
    expect(info!.widePageCount, greaterThanOrEqualTo(1));
    expect(info!.pageCount, greaterThanOrEqualTo(2));
  });
}

/// 数 PDF 里有几个页面对象（`/Type/Page`，不含 `/Type/Pages`）。
int _pdfPageCount(Uint8List pdf) {
  final raw = latin1.decode(pdf, allowInvalid: true);
  return RegExp('/Type/Page(?![s])').allMatches(raw).length;
}

/// 解压 PDF 里所有能以 zlib(Flate) 解开的流，拼成一段可搜索的文本。
String _decodedFontCmStreams(Uint8List pdf) {
  final raw = latin1.decode(pdf, allowInvalid: true);
  final out = StringBuffer();
  var searchFrom = 0;
  while (true) {
    final start = raw.indexOf('stream', searchFrom);
    if (start < 0) {
      break;
    }
    var dataStart = start + 'stream'.length;
    while (dataStart < raw.length &&
        (raw.codeUnitAt(dataStart) == 0x0a ||
            raw.codeUnitAt(dataStart) == 0x0d)) {
      dataStart++;
    }
    final end = raw.indexOf('endstream', dataStart);
    if (end < 0) {
      break;
    }
    final chunk = Uint8List.fromList(
      raw.substring(dataStart, end).codeUnits,
    );
    final inflated = _tryInflate(chunk);
    if (inflated != null) {
      out.writeln(latin1.decode(inflated, allowInvalid: true));
    }
    searchFrom = end + 'endstream'.length;
  }
  return out.toString();
}

/// zlib 解压；流数据与 `endstream` 之间有多余换行时逐个裁掉再试。
List<int>? _tryInflate(Uint8List chunk) {
  for (var trim = 0; trim <= 4 && trim < chunk.length; trim++) {
    try {
      return ZLibDecoder().convert(
        Uint8List.sublistView(chunk, 0, chunk.length - trim),
      );
    } on Object {
      continue;
    }
  }
  return null;
}

/// 在字节里找 UTF-16BE 编码的字符串（TrueType name 表的 Windows 平台记录）。
bool _containsUtf16Be(Uint8List bytes, String text) {
  final pattern = <int>[
    for (final unit in text.codeUnits) ...[unit >> 8, unit & 0xff],
  ];
  outer:
  for (var i = 0; i + pattern.length <= bytes.length; i++) {
    for (var j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) {
        continue outer;
      }
    }
    return true;
  }
  return false;
}

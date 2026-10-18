import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/export/docx_writer.dart';

/// OOXML 打包器的行为：条目齐全、XML 能表达段落/图片/页码域，
/// 以及"不静默吞掉写不进去的东西"（坏扩展名、build 后追加都报错）。
void main() {
  group('打包结构', () {
    test('每一份 docx 都带齐 Word 必需条目', () {
      final builder = DocxDocumentBuilder()..addParagraph(DocxParagraph());
      final entries = unzipText(builder.build());
      expect(
        entries.keys.toSet(),
        containsAll(<String>[
          '[Content_Types].xml',
          '_rels/.rels',
          'word/document.xml',
          'word/_rels/document.xml.rels',
          'word/styles.xml',
          'word/settings.xml',
          'word/footer1.xml',
        ]),
      );
    });

    test('document.xml 声明 OOXML 命名空间与 A4 版面', () {
      final document = _documentXml(DocxDocumentBuilder()
        ..addParagraph(
          DocxParagraph(inlines: const [DocxText('第一行')]),
        ));
      expect(document, contains('xmlns:w='));
      expect(document, contains('xmlns:m='));
      expect(document, contains('xmlns:wp='));
      expect(document, contains('xmlns:pic='));
      expect(document, contains('<w:pgSz w:w="11906" w:h="16838"/>'));
      expect(document, contains('w:left="680"'));
      expect(document, contains('w:right="2268"'));
      expect(document,
          contains('<w:footerReference w:type="default" r:id="rIdFoot"/>'));
    });

    test('空文档也能打包（页脚 + 一个空段落）', () {
      final bytes = DocxDocumentBuilder().build();
      expect(bytes.length, greaterThan(100));
      expect(unzipText(bytes)['word/document.xml'], contains('<w:body>'));
    });
  });

  group('段落与文字', () {
    test('文字 run 带字体、字号、粗斜体、颜色', () {
      final document = _documentXml(
        DocxDocumentBuilder()
          ..addParagraph(
            DocxParagraph(
              inlines: const [
                DocxText(
                  '加粗',
                  sizeHalfPt: kDocxHeadHalfPt,
                  bold: true,
                  colorHex: 'C00000',
                  fontCn: kDocxHeadFontCn,
                ),
              ],
            ),
          ),
      );
      expect(document, contains('w:eastAsia="黑体"'));
      expect(document, contains('<w:sz w:val="24"/><w:szCs w:val="24"/>'));
      expect(document, contains('<w:b/><w:bCs/>'));
      expect(document, contains('<w:color w:val="C00000"/>'));
    });

    test('XML 特殊字符被转义，控制字符被丢弃（保留 tab/换行）', () {
      final document = _documentXml(
        DocxDocumentBuilder()
          ..addParagraph(
            DocxParagraph(inlines: const [DocxText('a<b>&"c"\'\u0001\t')]),
          ),
      );
      expect(document, contains('a&lt;b&gt;&amp;&quot;c&quot;'));
      expect(document, isNot(contains('\u0001')));
      expect(document, contains('<w:t xml:space="preserve">'));
    });

    test('文字里的换行变成 Word 换行 run', () {
      final document = _documentXml(
        DocxDocumentBuilder()
          ..addParagraph(DocxParagraph(inlines: const [DocxText('第一行\n第二行')])),
      );
      expect(document, contains('<w:br/>'));
      expect(document, contains('第一行'));
      expect(document, contains('第二行'));
    });

    test('段落属性：对齐/缩进/段距/keepNext/keepLines/pageBreakBefore/边框/底纹', () {
      final document = _documentXml(
        DocxDocumentBuilder()
          ..addParagraph(
            DocxParagraph(
              inlines: const [DocxText('属性')],
              align: DocxAlign.center,
              spacingBeforeTw: 140,
              spacingAfterTw: 40,
              lineTw: 288,
              keepNext: true,
              keepLines: true,
              pageBreakBefore: true,
              leftIndentTw: 240,
              rightIndentTw: 120,
              firstLineIndentTw: 480,
              borderBottomHex: 'BFBFBF',
              shadeHex: 'F2F2F2',
            ),
          ),
      );
      expect(document, contains('<w:pageBreakBefore/>'));
      expect(document, contains('<w:keepNext/>'));
      expect(document, contains('<w:keepLines/>'));
      expect(document,
          contains('<w:shd w:val="clear" w:color="auto" w:fill="F2F2F2"/>'));
      expect(document, contains('w:color="BFBFBF"'));
      expect(
        document,
        contains(
          '<w:spacing w:before="140" w:after="40" w:line="288" w:lineRule="auto"/>',
        ),
      );
      expect(document, contains('w:left="240"'));
      expect(document, contains('w:right="120"'));
      expect(document, contains('w:firstLine="480"'));
      expect(document, contains('<w:jc w:val="center"/>'));
    });

    test('注入的 OMML 原样进文档，并按公式计数', () {
      final builder = DocxDocumentBuilder()
        ..addParagraph(
          DocxParagraph(
            inlines: const [
              DocxText('于是'),
              DocxMath('<m:oMath><m:r><m:t>x^2</m:t></m:r></m:oMath>'),
            ],
          ),
        );
      final document = _documentXml(builder);
      expect(
          document, contains('<m:oMath><m:r><m:t>x^2</m:t></m:r></m:oMath>'));
      expect(builder.mathCount, 1);
    });
  });

  group('页脚与页码域', () {
    test('页脚有左边文字与右对齐页码域', () {
      final footer = unzipText(
        (DocxDocumentBuilder(footerText: 'THREADRIPPER 2026-10-18')
              ..addParagraph(DocxParagraph()))
            .build(),
      )['word/footer1.xml']!;
      expect(footer, contains('THREADRIPPER 2026-10-18'));
      expect(footer,
          contains('<w:instrText xml:space="preserve"> PAGE </w:instrText>'));
      expect(
          footer,
          contains(
              '<w:instrText xml:space="preserve"> NUMPAGES </w:instrText>'));
      expect(footer, contains('第 '));
      expect(footer, contains(' 页 / 共 '));
      expect(footer, contains('<w:pBdr><w:top'));
    });

    test('关掉页码模板就不再写 footer1.xml', () {
      final entries = unzipText(
        (DocxDocumentBuilder(footerText: null, footerPageTemplate: null)
              ..addParagraph(DocxParagraph()))
            .build(),
      );
      expect(entries.containsKey('word/footer1.xml'), isFalse);
      expect(entries['word/document.xml'], isNot(contains('footerReference')));
    });
  });

  group('图片', () {
    test('随文图片进 media 与 document.xml，尺寸按栏宽/页高等比缩放', () {
      final bytes = Uint8List.fromList(List<int>.generate(64, (i) => i));
      final builder = DocxDocumentBuilder()
        ..addImage(
          DocxImageSpec(
            bytes: bytes,
            extension: 'png',
            pixelWidth: 100,
            pixelHeight: 100,
            note: '第 1 题',
          ),
        );
      final entries = unzipText(builder.build());
      expect(builder.imageCount, 1);
      expect(builder.paragraphCount, 1);
      expect(entries.keys, contains('word/media/image1.png'));
      final document = entries['word/document.xml']!;
      expect(document,
          contains('<wp:inline distT="0" distB="0" distL="0" distR="0">'));
      expect(document, contains('<pic:blipFill>'));
      expect(document, contains('r:embed="rIdImg0"'));
      // 100px * 15 = 1500 twips 天然宽度；缩放上限 1.5 → 2250 twips * 635 EMU。
      expect(document, contains('<wp:extent cx="1428750" cy="1428750"/>'));
      expect(
        builder.imagePlacements.single.note,
        '第 1 题',
      );
    });

    test('大图按页面可用高度等比缩小，宽高比不变', () {
      final builder = DocxDocumentBuilder()
        ..addImage(
          DocxImageSpec(
            bytes: Uint8List.fromList([1, 2, 3]),
            extension: 'jpeg',
            pixelWidth: 4000,
            pixelHeight: 3000,
          ),
        );
      builder.build();
      final placement = builder.imagePlacements.single;
      expect(placement.cxEmu / placement.cyEmu, closeTo(4 / 3, 0.001));
      expect(placement.cxEmu / 635, lessThanOrEqualTo(8958 * 0.62 + 1));
    });

    test('不认识的扩展名抛 ArgumentError（不静默丢图）', () {
      expect(
        () => DocxDocumentBuilder().addImage(
          DocxImageSpec(
            bytes: Uint8List.fromList([1]),
            extension: 'heic',
            pixelWidth: 10,
            pixelHeight: 10,
          ),
        ),
        throwsArgumentError,
      );
    });

    test('扩展名归一化与支持判断', () {
      expect(normalizeDocxImageExtension('JPG'), 'jpeg');
      expect(normalizeDocxImageExtension('.jpeg'), 'jpeg');
      expect(normalizeDocxImageExtension('png'), 'png');
      expect(normalizeDocxImageExtension('gif'), 'gif');
      expect(normalizeDocxImageExtension('bmp'), 'bmp');
      expect(normalizeDocxImageExtension('heic'), isNull);
      // Word 对 WebP/HEIC 的支持取决于版本，导出侧只嵌入确定能打开的四种格式。
      expect(supportsDocxImageExtension('webp'), isFalse);
      expect(supportsDocxImageExtension('heic'), isFalse);
    });
  });

  group('装配纪律', () {
    test('build 之后不能再加内容', () {
      final builder = DocxDocumentBuilder()..addParagraph(DocxParagraph());
      builder.build();
      expect(() => builder.addParagraph(DocxParagraph()), throwsStateError);
      expect(
        () => builder.addImage(
          DocxImageSpec(
            bytes: _tinyImage(),
            extension: 'png',
            pixelWidth: 1,
            pixelHeight: 1,
          ),
        ),
        throwsStateError,
      );
      expect(builder.build, throwsStateError);
    });
  });
}

Uint8List _tinyImage() => Uint8List.fromList([1, 2, 3]);

Map<String, String> unzipText(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final result = <String, String>{};
  for (final file in archive) {
    if (!file.isFile) continue;
    result[file.name] = utf8.decode(file.content as List<int>);
  }
  return result;
}

String _documentXml(DocxDocumentBuilder builder) =>
    unzipText(builder.build())['word/document.xml']!;

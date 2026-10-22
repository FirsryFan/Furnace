import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/questions/question_stem_segments.dart';

QuestionStemLayout split(String stem, int imageCount) =>
    splitQuestionStemImages(stem, imageCount: imageCount);

/// 把切分结果压成好断言的形状：文字段 `text:...`、图片段 `img<n>`、末尾 `unplaced:<逗号>`。
List<String> shape(QuestionStemLayout layout) => <String>[
      for (final segment in layout.segments)
        segment.isImage ? 'img${segment.imageOrder}' : 'text:${segment.text}',
      if (layout.unplacedImageOrders.isNotEmpty)
        'unplaced:${layout.unplacedImageOrders.join(',')}',
    ];

void main() {
  group('无占位', () {
    test('无占位、无图：整段是一个文字段', () {
      final layout = split('已知函数，求单调区间。', 0);
      expect(shape(layout), <String>['text:已知函数，求单调区间。']);
      expect(layout.referencedImageCount, 0);
      expect(layout.hasImages, isFalse);
      expect(layout.hasUnplacedImages, isFalse);
      expect(layout.isEmpty, isFalse);
    });

    test('无占位、有 3 张图：文字照旧，三张图都算未引用', () {
      final layout = split('纯文字题干', 3);
      expect(shape(layout), <String>['text:纯文字题干', 'unplaced:0,1,2']);
      expect(layout.hasImages, isTrue);
      expect(layout.hasUnplacedImages, isTrue);
    });

    test('空题干、无图：isEmpty', () {
      final layout = split('', 0);
      expect(layout.segments, isEmpty);
      expect(layout.unplacedImageOrders, isEmpty);
      expect(layout.isEmpty, isTrue);
      expect(layout.hasImages, isFalse);
    });

    test('空题干、有两张图：只有未引用图，不算 isEmpty', () {
      final layout = split('', 2);
      expect(layout.segments, isEmpty);
      expect(layout.unplacedImageOrders, <int>[0, 1]);
      expect(layout.isEmpty, isFalse);
      expect(layout.hasUnplacedImages, isTrue);
    });
  });

  group('占位识别', () {
    test('中间一张图', () {
      final layout = split('已知函数［图1］，求单调区间。', 1);
      expect(shape(layout), <String>[
        'text:已知函数',
        'img0',
        'text:，求单调区间。',
      ]);
      expect(layout.referencedImageCount, 1);
      expect(layout.unplacedImageOrders, isEmpty);
    });

    test('占位在开头', () {
      final layout = split('［图1］正文', 1);
      expect(shape(layout), <String>['img0', 'text:正文']);
    });

    test('占位在结尾', () {
      final layout = split('正文［图1］', 1);
      expect(shape(layout), <String>['text:正文', 'img0']);
    });

    test('题干只有一个占位', () {
      final layout = split('［图1］', 1);
      expect(shape(layout), <String>['img0']);
    });

    test('只引用第二张，第一张列为未引用', () {
      final layout = split('［图2］', 3);
      expect(shape(layout), <String>['img1', 'unplaced:0,2']);
    });

    test('两个占位相邻', () {
      final layout = split('［图1］［图2］', 2);
      expect(shape(layout), <String>['img0', 'img1']);
    });

    test('全角方括号、半角方括号、方头括号都认', () {
      final layout = split('前［图1］中[图2]后【图3】', 3);
      expect(shape(layout), <String>[
        'text:前',
        'img0',
        'text:中',
        'img1',
        'text:后',
        'img2',
      ]);
    });

    test('括号内允许空格', () {
      final layout = split('前[ 图 2 ]后', 2);
      expect(shape(layout), <String>['text:前', 'img1', 'text:后', 'unplaced:0']);
    });

    test('全角数字也认', () {
      final layout = split('［图２］', 2);
      expect(shape(layout), <String>['img1', 'unplaced:0']);
    });

    test('前导零按数值算', () {
      final layout = split('[图01]', 1);
      expect(shape(layout), <String>['img0']);
    });

    test('连续文字段不拆碎（占位之间夹一个字）', () {
      final layout = split('a［图1］b［图2］c', 2);
      expect(shape(layout), <String>[
        'text:a',
        'img0',
        'text:b',
        'img1',
        'text:c',
      ]);
    });

    test('未引用的图排在后边并升序', () {
      final layout = split('a［图2］b', 3);
      expect(
          shape(layout), <String>['text:a', 'img1', 'text:b', 'unplaced:0,2']);
      expect(layout.referencedImageCount, 1);
    });
  });

  group('越界、重复与不吞字', () {
    test('N 超出图片数：占位原文保留', () {
      final layout = split('［图3］', 2);
      expect(shape(layout), <String>['text:［图3］', 'unplaced:0,1']);
      expect(layout.referencedImageCount, 0);
    });

    test('N 为 0：占位原文保留', () {
      final layout = split('前［图0］后', 2);
      expect(shape(layout), <String>['text:前［图0］后', 'unplaced:0,1']);
    });

    test('越界占位夹在合法占位之间', () {
      final layout = split('［图1］越界［图9］', 1);
      expect(shape(layout), <String>['img0', 'text:越界［图9］']);
      expect(layout.hasUnplacedImages, isFalse);
    });

    test('同一个 N 出现两次：两处都渲染同一张图，只计一次引用', () {
      final layout = split('［图 1］和［图1］', 1);
      expect(shape(layout), <String>['img0', 'text:和', 'img0']);
      expect(layout.referencedImageCount, 1);
      expect(layout.unplacedImageOrders, isEmpty);
    });

    test('数字超过 3 位不认，原文保留', () {
      final layout = split('[图1234]', 2);
      expect(shape(layout), <String>['text:[图1234]', 'unplaced:0,1']);
    });

    test('没有括号的「图1」只是文字', () {
      final layout = split('如图1所示', 1);
      expect(shape(layout), <String>['text:如图1所示', 'unplaced:0']);
    });

    test('「图片1」不认', () {
      final layout = split('［图片1］', 1);
      expect(shape(layout), <String>['text:［图片1］', 'unplaced:0']);
    });

    test('「[图]」没有数字不认', () {
      final layout = split('[图]', 1);
      expect(shape(layout), <String>['text:[图]', 'unplaced:0']);
    });

    test('普通方括号文字不动', () {
      final layout = split('见注释[注1]', 0);
      expect(shape(layout), <String>['text:见注释[注1]']);
    });

    test('左右括号种类不配对也认（宽松匹配，宁可多插入图片）', () {
      final layout = split('[图1］', 1);
      expect(shape(layout), <String>['img0']);
    });
  });

  group('imageCount 边界', () {
    test('imageCount 为 0 时占位就是文字', () {
      final layout = split('前［图1］后', 0);
      expect(shape(layout), <String>['text:前［图1］后']);
      expect(layout.hasImages, isFalse);
      expect(layout.unplacedImageOrders, isEmpty);
    });

    test('imageCount 为负按 0 处理', () {
      final layout = split('前［图1］后', -3);
      expect(shape(layout), <String>['text:前［图1］后']);
      expect(layout.unplacedImageOrders, isEmpty);
    });

    test('空题干、imageCount 为负：空结果', () {
      final layout = split('', -1);
      expect(layout.isEmpty, isTrue);
    });
  });

  group('工具与值对象', () {
    test('questionStemPlainText 去掉图片段', () {
      final layout = split('前［图1］后', 1);
      expect(questionStemPlainText(layout), '前后');
    });

    test('questionStemPlainText 保留没认出的占位原文', () {
      final layout = split('前［图3］后', 1);
      expect(questionStemPlainText(layout), '前［图3］后');
    });

    test('segments 与 unplacedImageOrders 不可变', () {
      final layout = split('a［图1］', 2);
      expect(
        () => layout.segments.add(const QuestionStemSegment.text('x')),
        throwsUnsupportedError,
      );
      expect(() => layout.unplacedImageOrders.add(9), throwsUnsupportedError);
    });

    test('文字段与图片段的值语义', () {
      const text = QuestionStemSegment.text('abc');
      const image = QuestionStemSegment.image(2);
      expect(text.isText, isTrue);
      expect(text.isImage, isFalse);
      expect(text.imageOrder, isNull);
      expect(image.isImage, isTrue);
      expect(image.text, '');
      expect(image.imageOrder, 2);
      expect(const QuestionStemSegment.text('abc'), text);
      expect(const QuestionStemSegment.image(2), image);
      expect(const QuestionStemSegment.image(2).hashCode, image.hashCode);
      expect(text == image, isFalse);
      expect(text.toString(), contains('abc'));
      expect(image.toString(), contains('2'));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/questions/question_stem_preview.dart';

/// 题干可读摘要（轮次一百四十一，task-127）。
///
/// 这些例子都来自真实抓题包的形状：行内公式、[图N] 占位、Markdown 残留、
/// 以及题库列表里最难看的「公式定界符 + 方括号占位」混排。
void main() {
  group('基础与空白', () {
    test('空题干返回空串', () {
      expect(questionStemPreview(''), '');
      expect(questionStemPreview('   '), '');
    });

    test('普通题干原样返回（首尾空白去掉）', () {
      expect(
        questionStemPreview('  已知函数 f(x)=x^2，求单调区间。 '),
        '已知函数 f(x)=x^2，求单调区间。',
      );
    });

    test('换行、制表、全角空格折叠成一个半角空格', () {
      expect(
        questionStemPreview('第一行\n\n第二行\t第三行\u3000\u3000第四行'),
        '第一行 第二行 第三行 第四行',
      );
    });
  });

  group('LaTeX 定界符', () {
    test('行内公式去掉美元符保留内部', () {
      expect(
          questionStemPreview(r'已知 $f(x)=x^2$，求单调区间。'), '已知 f(x)=x^2，求单调区间。');
    });

    test('多个行内公式都去定界符', () {
      expect(
        questionStemPreview(r'设 $a=1$，$b=2$，求 $a+b$。'),
        '设 a=1，b=2，求 a+b。',
      );
    });

    test('块级公式也去定界符', () {
      expect(
        questionStemPreview(r'由 $$\frac{a}{b}=\frac{c}{d}$$ 可得比例式。'),
        r'由 \frac{a}{b}=\frac{c}{d} 可得比例式。',
      );
    });

    test('没配对的美元符直接删掉', () {
      expect(questionStemPreview(r'价格是 $5 元'), '价格是 5 元');
      expect(questionStemPreview(r'半截公式 $x^2'), '半截公式 x^2');
    });

    test('公式里的花括号与反斜杠原样保留', () {
      expect(
        questionStemPreview(r'化简 $\sqrt{x^2+1}$ 的结果。'),
        r'化简 \sqrt{x^2+1} 的结果。',
      );
    });
  });

  group('图片占位', () {
    test('半角方括号占位换成 [图]', () {
      expect(questionStemPreview('如图所示[图1]，求面积。'), '如图所示［图］，求面积。');
    });

    test('全角方括号占位换成 [图]', () {
      expect(questionStemPreview('如图［图2］所示。'), '如图［图］所示。');
    });

    test('中文方头括号占位也认', () {
      expect(questionStemPreview('据图【图12】回答。'), '据图［图］回答。');
    });

    test('全角数字占位也认', () {
      expect(questionStemPreview('如图［图１］所示。'), '如图［图］所示。');
    });

    test('占位在开头/结尾时不吞掉相邻文字', () {
      expect(questionStemPreview('[图1]求面积'), '［图］求面积');
      expect(questionStemPreview('求面积[图1]'), '求面积［图］');
    });

    test('没有数字的方括号原样保留', () {
      expect(questionStemPreview('这是［图］不是占位'), '这是［图］不是占位');
    });

    test('多张图片占位都换掉', () {
      expect(questionStemPreview('[图1] 与 [图2] 哪个对？'), '［图］ 与 ［图］ 哪个对？');
    });
  });

  group('Markdown 残留', () {
    test('Markdown 图片删掉', () {
      expect(questionStemPreview('如图 ![图1](http://x/a.png) 所示。'), '如图 所示。');
    });

    test('Markdown 链接只留文字', () {
      expect(
          questionStemPreview('详见[资料](https://example.com/x)说明。'), '详见资料说明。');
    });
  });

  group('截断', () {
    test('默认 60 个 runes 截断并补省略号', () {
      final stem = '甲' * 80;
      final preview = questionStemPreview(stem);
      expect(preview.runes.length, kQuestionStemPreviewMaxLength + 1);
      expect(preview.endsWith('…'), isTrue);
    });

    test('刚好等于上限不截断', () {
      final stem = '乙' * kQuestionStemPreviewMaxLength;
      expect(questionStemPreview(stem), stem);
    });

    test('自定义 maxLength 生效', () {
      expect(questionStemPreview('一二三四五六', maxLength: 3), '一二三…');
    });

    test('按 runes 截断不切坏 emoji', () {
      expect(questionStemPreview('😀😀😀😀', maxLength: 2), '😀😀…');
    });

    test('maxLength <= 0 返回空串', () {
      expect(questionStemPreview('一二三', maxLength: 0), '');
      expect(questionStemPreview('一二三', maxLength: -5), '');
    });
  });

  group('组合与真实形状', () {
    test('公式 + 图片占位的真实题干', () {
      expect(
        questionStemPreview(
          r'已知函数 $f(x)=x^2-2x$，其图象如图［图1］所示，求 $f(x)$ 的最小值。',
        ),
        r'已知函数 f(x)=x^2-2x，其图象如图［图］所示，求 f(x) 的最小值。',
      );
    });

    test('只有标记的题干返回空串', () {
      expect(questionStemPreview(r'$$ $$'), '');
      expect(questionStemPreview(r'$ $'), '');
    });

    test('摘要里不再出现美元符', () {
      final preview = questionStemPreview(r'求 $a$ 与 $b$ 的和');
      expect(preview.contains('\$'), isFalse);
    });
  });
}

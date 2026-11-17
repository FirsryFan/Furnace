/// 题目文本的 Markdown 小工具：填空空位、卡片摘要、题干图占位。
///
/// 三件事都是纯逻辑（不碰 Flutter），但都直接影响用户在卡片/详情页看到什么：
///  * 第一组钉住「`______` 变成空位标记（组件化下划线），公式/代码里的 `_` 不动」；
///  * 卡片摘要要能安全交给渲染器（结构完整），不然半截语法会吞掉后面的文字；
///  * 题干图占位要能翻成渲染器认得的图片语法，且越界占位不吞字。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/questions/question_blank_markup.dart';
import 'package:furnace/domain/services/questions/question_image_markdown.dart';
import 'package:furnace/domain/services/questions/question_markdown_source.dart';
import 'package:furnace/domain/services/questions/question_stem_excerpt.dart';
import 'package:furnace/features/questions/presentation/question_markdown_view.dart';

void main() {
  group('填空空位（组件化下划线的标记）', () {
    test('3+ 连续下划线换成空位标记，公式保持原样', () {
      const text = r'宏观上 $\Delta H=$ ______。';
      final source = questionMarkdownWithBlankWidgets(text);
      expect(source, contains('question-blank:6'));
      expect(source, isNot(contains('______')));
      expect(source, contains(r'$\Delta H=$'));
      expect(_rendersAsMarkdown(source), isTrue);
    });

    test('公式里的下划线是 LaTeX 下标，不能动', () {
      const text = r'求和 $\sum_{i=1}^{n} a_i$ 的值。';
      expect(questionMarkdownWithBlankWidgets(text), text);
    });

    test('单个下划线（snake_case / 普通标识符）不动', () {
      const text = '字段名 fullcard_stem 与 a_b。';
      expect(questionMarkdownWithBlankWidgets(text), text);
    });

    test('代码栅栏里的下划线不动', () {
      const text = '示例：\n\n```dart\nfinal long_name = 1;\n```\n\n答案 ______。';
      final source = questionMarkdownWithBlankWidgets(text);
      expect(source, contains('final long_name = 1;'));
      expect(source, contains('question-blank:6'));
    });

    test('人工转义过的下划线不算空位', () {
      const text = r'答案 \_\_\_\_\_\_。';
      expect(questionMarkdownWithBlankWidgets(text), text);
    });

    test('没有下划线的题面一个字都不改', () {
      const text = '求二次函数的最小值，并说明理由。';
      expect(questionMarkdownWithBlankWidgets(text), text);
    });

    test('空位尺寸随字号与下划线个数变化并夹取', () {
      final short = questionBlankDisplaySize(3, 16);
      final long = questionBlankDisplaySize(6, 16);
      expect(short.width, lessThan(long.width));
      expect(short.height, closeTo(20, 0.01));
      // 宽度夹在 2.2em–10em。
      expect(questionBlankDisplaySize(100, 16).width, closeTo(160, 0.01));
      expect(questionBlankDisplaySize(1, 16).width, closeTo(35.2, 0.01));
    });

    test('questionTextHasBlanks / parseQuestionBlanks 只认公式外 3+', () {
      expect(questionTextHasBlanks('填空 ______ 在这里'), isTrue);
      expect(questionTextHasBlanks(r'公式 $a_i$ 与 x_1'), isFalse);
      expect(questionTextHasBlanks('一个_下划线不算空'), isFalse);
      final blanks = parseQuestionBlanks('甲____乙，丙______丁');
      expect(blanks, hasLength(2));
      expect(blanks[0].underscores, 4);
      expect(blanks[1].underscores, 6);
      expect(blanks[0].start, 1);
    });

    test('questionBlankCountFromUrl 解析下划线个数，非法返回 null', () {
      expect(questionBlankCountFromUrl('question-blank:6'), 6);
      expect(questionBlankCountFromUrl('question-blank:2'), isNull);
      expect(questionBlankCountFromUrl('question-image:1'), isNull);
      expect(questionBlankCountFromUrl('https://example.com'), isNull);
    });

    test('渲染入口 questionMarkdownSource = 公式归一 + 空位标记', () {
      const text = r'宏观上 $5\Delta H$ 与 ______。';
      final source = questionMarkdownSource(text);
      expect(source, contains(r'\(5\Delta H\)'));
      expect(source, contains('question-blank:6'));
    });
  });

  group('公式定界符归一（绕开价格启发式）', () {
    test('数字开头的行内公式换成 \\(\\)，不再被当正文', () {
      const text = r'使得 $5\cos x-\cos(5x+\varphi)\le b$ 恒成立。';
      final source = questionMathForRenderer(text);
      expect(source, contains(r'\(5\cos x-\cos(5x+\varphi)\le b\)'));
      expect(source, isNot(contains(r'$')));
    });

    test('价格里的孤立美元符保持原样（不当公式）', () {
      const text = '价格 \$5 到 \$9。';
      expect(questionMathForRenderer(text), text);
    });

    test('块级公式换成 \\[\\]', () {
      const text = r'计算 $$t_2t_3<4$$ 的值。';
      expect(questionMathForRenderer(text), contains(r'\[t_2t_3<4\]'));
    });

    test('代码栅栏与转义美元不动', () {
      const text = '示例：\n\n```text\necho \$HOME\n```\n\n价格 '
          r'\$5。';
      expect(questionMathForRenderer(text), text);
    });

    test('questionMarkdownSource = 公式归一 + 空位标记', () {
      const text = r'宏观上 $5\Delta H$ 与 ______。';
      final source = questionMarkdownSource(text);
      expect(source, contains(r'\(5\Delta H\)'));
      expect(source, contains('question-blank:6'));
    });
  });

  group('卡片题干摘要', () {
    test('短题干原样返回，不补省略号', () {
      expect(questionCardStemExcerpt('求二次函数最小值'), '求二次函数最小值');
    });

    test('长题干按 rune 截断并补省略号', () {
      final stem = '甲' * 200;
      final excerpt = questionCardStemExcerpt(stem, maxLength: 20);
      expect(excerpt.endsWith('…'), isTrue);
      expect(excerpt.runes.length, 21);
    });

    test('截断落在公式里时退到定界符之前，不留半个美元符', () {
      final stem = '前缀' r'$x^2+2x+1$' '${'后缀' * 50}';
      final excerpt = questionCardStemExcerpt(stem, maxLength: 6);
      expect(excerpt.contains(r'$'), isFalse);
      expect(_rendersAsMarkdown(excerpt), isTrue);
    });

    test('markdown 图片删掉、图片占位收成［图］、代码块不留', () {
      const stem = '如图 ![示意图](a.png) 所示。\n'
          '［图1］与【图2】。\n\n'
          '```text\n代码 ______\n```\n\n'
          '求最小值。';
      final excerpt = questionCardStemExcerpt(stem);
      expect(excerpt, isNot(contains('![')));
      expect(excerpt, isNot(contains('```')));
      expect(excerpt, isNot(contains('示意图')));
      expect(excerpt, contains('［图］'));
      expect(excerpt, contains('求最小值'));
    });

    test('算法竞赛题面：跳过标题前的来源元信息，从正文开始', () {
      const stem = 'P1120 [CERC 1995] 小木棍\n\n'
          '来源：洛谷 https://www.luogu.com.cn/problem/P1120\n'
          '洛谷难度：提高+/省选-\n'
          '算法标签：搜索、DFS、剪枝\n\n'
          '## 题目描述\n'
          '乔治有一些同样长的小木棍，他把这些木棍随意砍成几段。\n\n'
          '## 输入格式\n'
          '第一行是一个整数 \$n\$。';
      final excerpt = questionCardStemExcerpt(stem);
      expect(excerpt, isNot(contains('来源：')));
      expect(excerpt, isNot(contains('洛谷难度')));
      expect(excerpt, isNot(contains('https://')));
      expect(excerpt, isNot(contains('##')));
      expect(excerpt, contains('乔治有一些同样长的小木棍'));
    });

    test('表格行不进摘要（列联表这类表交给详情页）', () {
      const stem = '15．得到如下列联表：\n\n'
          '| 组别 | 正常 | 合计 |\n'
          '| --- | --- | --- |\n'
          '| 患该疾病 | 20 | 200 |\n\n'
          '(1) 求 p 的估计值。';
      final excerpt = questionCardStemExcerpt(stem);
      expect(excerpt, isNot(contains('|')));
      expect(excerpt, contains('得到如下列联表'));
      expect(excerpt, contains('求 p 的估计值'));
    });

    test('空题干返回空串', () {
      expect(questionCardStemExcerpt('   \n\n '), '');
    });

    test('源格式 {{asset:...}} 占位收成［图］，卡片上不出现原始占位符', () {
      final excerpt = questionCardStemExcerpt(
        '利用铁基、钙基物质的化学循环（{{asset:q14_img01.wmf}}'
        '{{asset:q14_img02.png}}）可从高炉煤气中分离气体',
      );
      expect(excerpt.contains('{{asset:'), isFalse);
      expect(excerpt.contains('［图］'), isTrue);
      expect(_rendersAsMarkdown(excerpt), isTrue);
    });

    test('摘要始终是结构完整的 Markdown（可交给渲染器）', () {
      final stems = <String>[
        '求函数 \$f(x)=x^2\$ 的最小值',
        r'求 $$\frac{1}{2}$$ 的值',
        '见 [链接](https://example.com) 与 **重点**。',
        '算式 `a_1` 与 ______。',
      ];
      for (final stem in stems) {
        final excerpt = questionCardStemExcerpt(stem);
        expect(
          _rendersAsMarkdown(excerpt),
          isTrue,
          reason: '摘要不可渲染：$stem → $excerpt',
        );
      }
    });
  });

  group('题干图占位 → Markdown 图片', () {
    test('行内占位带高度，独立成行的占位标记为插图', () {
      const text = '加入［图1］溶液，结果如图。\n［图2］';
      final markup = questionMarkdownWithImagePlaceholders(
        text,
        imageCount: 2,
        heightOf: (placeholder) => placeholder.ownLine ? 320 : 20,
      );
      expect(markup.markdown, contains('![x20](question-image:1)'));
      expect(markup.markdown, contains('![x320](question-image:2)'));
      expect(markup.placeholders, hasLength(2));
      expect(markup.placeholders[0].ownLine, isFalse);
      expect(markup.placeholders[1].ownLine, isTrue);
    });

    test('比行高高得多的公式单独成段，避免整行被撑高', () {
      const text = '调节［图1］时，需加入［图2］';
      final markup = questionMarkdownWithImagePlaceholders(
        text,
        imageCount: 2,
        heightOf: (placeholder) => placeholder.order == 0 ? 20 : 63,
      );
      expect(markup.markdown, contains('\n\n![x63](question-image:2)\n\n'));
      expect(markup.markdown, contains('![x20](question-image:1)'));
    });

    test('越界占位保持原文，不吞字', () {
      const text = '［图1］与［图9］都在。';
      final markup =
          questionMarkdownWithImagePlaceholders(text, imageCount: 1);
      expect(markup.markdown, contains('![图](question-image:1)'));
      expect(markup.markdown, contains('［图9］'));
      expect(markup.placeholders, hasLength(1));
    });

    test('没有图片时原样返回', () {
      const text = '［图1］';
      final markup =
          questionMarkdownWithImagePlaceholders(text, imageCount: 0);
      expect(markup.markdown, text);
      expect(markup.hasImages, isFalse);
    });

    test('url 解析：1-based 换成 0-based，非法返回 null', () {
      expect(questionImageOrderFromUrl('question-image:1'), 0);
      expect(questionImageOrderFromUrl('question-image:18'), 17);
      expect(questionImageOrderFromUrl('question-image:0'), isNull);
      expect(questionImageOrderFromUrl('https://example.com/a.png'), isNull);
    });

    test('全角数字占位也认', () {
      const text = '［图１］';
      final markup =
          questionMarkdownWithImagePlaceholders(text, imageCount: 1);
      expect(markup.markdown, contains('question-image:1'));
    });
  });
}

/// 「摘要结构完整、能交给 Markdown 渲染器」的判定（生产函数在
/// `question_markdown_view.dart`）。
bool _rendersAsMarkdown(String text) =>
    questionMarkdownRendersAsMarkdown(text);

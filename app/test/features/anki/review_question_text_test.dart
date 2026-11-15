import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/anki/presentation/review_question_text.dart';
import 'package:furnace/features/questions/presentation/question_blank_view.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

/// 2×2 合法 PNG（纯红色）：让 `Image.memory` 真的解码，而不是拿垃圾字节糊弄。
final Uint8List tinyPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEklEQVR4nGO8pKHBwMDAxAAGAA5sASaNUVj9AAAAAElFTkSuQmCC',
);

/// 24 字节 PNG 头：足以创建 Image widget，解码会失败 → 走 errorBuilder 占位。
final Uint8List brokenPngBytes =
    Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

/// 闪存卡题干富文本：纯文本回归、LaTeX、［图N］占位、Markdown 图片路径、坏图不崩。
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
    );
    await tester.pump();
  }

  Future<void> waitForFinder(
    WidgetTester tester,
    Finder finder, {
    int rounds = 50,
  }) async {
    for (var i = 0; i < rounds; i++) {
      if (finder.evaluate().isNotEmpty) {
        return;
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    fail('等了 5 秒也没等到：$finder');
  }

  ReviewQuestionImage image({Uint8List? bytes}) =>
      ReviewQuestionImage(bytes: bytes ?? tinyPngBytes);

  group('纯文本与公式', () {
    testWidgets('纯文本模板卡内容照旧渲染，不出现图片也不崩', (tester) async {
      await pump(
        tester,
        const ReviewQuestionText(text: '光合作用的场所是叶绿体。'),
      );

      expect(find.byKey(reviewQuestionTextKey), findsOneWidget);
      expect(find.text('光合作用的场所是叶绿体。'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('行内 LaTeX 被排成数学，不留下字面美元定界符', (tester) async {
      await pump(
        tester,
        const ReviewQuestionText(text: r'已知 $x^2-5x+6=0$，求两根之和。'),
      );

      expect(find.byType(GptMarkdown), findsWidgets);
      final plainTexts = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
          .toList(growable: false);
      expect(
        plainTexts.where((text) => text.contains(r'$')),
        isEmpty,
        reason: '公式应被渲染，不能留下字面定界符',
      );
    });

    testWidgets('整段 Markdown 标题也能渲染', (tester) async {
      await pump(
        tester,
        const ReviewQuestionText(
          text: '# 题干标题\n\n' r'已知 $x=1$。',
          markdown: true,
        ),
      );

      expect(find.byType(GptMarkdown), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('［图N］占位', () {
    testWidgets('两个占位按顺序插进文字，占位原文不再出现', (tester) async {
      await pump(
        tester,
        ReviewQuestionText(
          text: '如图［图1］所示，求［图2］的面积。',
          images: <ReviewQuestionImage>[image(), image()],
        ),
      );

      expect(find.byKey(reviewQuestionTextKey), findsOneWidget);
      await waitForFinder(tester, find.byKey(reviewQuestionImageKey(0)));
      expect(find.byKey(reviewQuestionImageKey(0)), findsOneWidget);
      expect(find.byKey(reviewQuestionImageKey(1)), findsOneWidget);
      expect(find.textContaining('［图1］'), findsNothing);
      expect(find.textContaining('［图2］'), findsNothing);
    });

    testWidgets('没有占位时图接在文字末尾', (tester) async {
      await pump(
        tester,
        ReviewQuestionText(
          text: '一张没有占位的照片卡。',
          images: <ReviewQuestionImage>[image()],
        ),
      );

      await waitForFinder(tester, find.byKey(reviewQuestionImageKey(0)));
      expect(find.text('一张没有占位的照片卡。'), findsOneWidget);
      expect(find.byKey(reviewQuestionImageKey(0)), findsOneWidget);
    });

    testWidgets('没有图可用时占位原文保留，不吞字', (tester) async {
      await pump(
        tester,
        const ReviewQuestionText(text: '如图［图1］，这道卡没有配图。'),
      );

      expect(find.textContaining('［图1］'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('越界占位保留原文，图仍按未引用图接到末尾', (tester) async {
      await pump(
        tester,
        ReviewQuestionText(
          text: '［图9］越界的占位。',
          images: <ReviewQuestionImage>[image()],
        ),
      );

      await waitForFinder(tester, find.byKey(reviewQuestionImageKey(0)));
      expect(find.textContaining('［图9］'), findsOneWidget);
      expect(find.byKey(reviewQuestionImageKey(0)), findsOneWidget);
    });

    testWidgets('坏图字节只画坏图占位：不抛异常、不吞掉同一段的文字', (tester) async {
      await pump(
        tester,
        ReviewQuestionText(
          text: '前面的文字［图1］后面的文字。',
          images: <ReviewQuestionImage>[
            ReviewQuestionImage(bytes: brokenPngBytes),
          ],
        ),
      );

      await waitForFinder(
        tester,
        find.byKey(reviewQuestionBrokenImageKey(0)),
      );
      expect(find.byKey(reviewQuestionBrokenImageKey(0)), findsOneWidget);
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
      expect(find.textContaining('前面的文字'), findsOneWidget);
      expect(find.textContaining('后面的文字'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('文本渲染口径（Markdown 检测）', () {
    bool asMarkdown(String text, {String? textFormat}) =>
        reviewCardTextRendersAsMarkdown(text: text, textFormat: textFormat);

    test('普通中文句子与价格里的美元符号不切换 Markdown', () {
      expect(asMarkdown('光合作用的场所是叶绿体。'), isFalse);
      expect(asMarkdown(r'价格 $5 到 $9。'), isFalse);
      expect(asMarkdown('注意：* 不是强调'), isFalse);
      expect(
        asMarkdown('1. 光合作用的第一步。'),
        isFalse,
        reason: '单行 "1." 是普通句子，不是列表',
      );
      expect(asMarkdown('填空题的 ______ 还在'), isFalse);
    });

    test('闭合公式/块级公式/标题/列表/表格/代码/链接按 Markdown', () {
      expect(asMarkdown(r'已知 $x^2-5x+6=0$，求两根之和。'), isTrue);
      expect(asMarkdown(r'求 $$\Delta H$$ 的值。'), isTrue);
      expect(asMarkdown('# 题干标题\n\n正文'), isTrue);
      expect(asMarkdown('**重点**内容'), isTrue);
      expect(asMarkdown('1. 第一步\n2. 第二步'), isTrue);
      expect(asMarkdown('| 量 | 值 |\n| --- | --- |\n| a | 1 |'), isTrue);
      expect(asMarkdown('```\ncode\n```'), isTrue);
      expect(asMarkdown('见 [链接](https://example.com)'), isTrue);
      expect(asMarkdown('![图](a.png)'), isTrue);
    });

    test('结构不完整的文本不切换（不吞后面的文字）', () {
      expect(asMarkdown('```\n没闭合的代码栅栏'), isFalse);
      expect(asMarkdown(r'落单的 $x^2'), isFalse);
    });

    test('显式格式优先于检测', () {
      expect(asMarkdown('普通文本', textFormat: 'markdown'), isTrue);
      expect(asMarkdown('**加粗**', textFormat: 'plain'), isFalse);
      expect(asMarkdown('**加粗**', textFormat: '  Markdown  '), isTrue);
    });

    testWidgets('检测到 Markdown 的题干能排出标题与列表，不留下语法字符', (tester) async {
      await pump(
        tester,
        const ReviewQuestionText(
          text: '# 题干标题\n\n- 甲\n- 乙',
          markdown: true,
        ),
      );
      expect(find.byType(GptMarkdown), findsWidgets);
      expect(
        find.textContaining('# 题干标题', findRichText: true),
        findsNothing,
      );
      expect(find.textContaining('- 甲', findRichText: true), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('填空卡的 ______ 渲染成下划线组件（不再是被 Markdown 吃掉的字符）',
        (tester) async {
      await pump(
        tester,
        const ReviewQuestionText(
          text: r'宏观上 $\Delta H=$ ______。',
          markdown: true,
        ),
      );
      expect(find.byType(GptMarkdown), findsWidgets);
      // 2026-11-15（task-117）：空位改成真正的空白下划线组件；卡片/详情/复习页
      // 同一套。渲染文字里不再有 `______` 字符，但空位看得见。
      expect(find.byType(QuestionBlankUnderline), findsOneWidget);
      final blank = tester.widget<QuestionBlankUnderline>(
        find.byType(QuestionBlankUnderline),
      );
      expect(blank.width, greaterThan(30));
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
          .join();
      expect(texts, isNot(contains(r'$')));
      expect(texts, isNot(contains('______')));
    });
  });

  group('Markdown 图片路径', () {
    testWidgets('路径能解析到字节时渲染成图片，路径本身不再显示', (tester) async {
      await pump(
        tester,
        ReviewQuestionText(
          text: '如图![示意图](E:/imgs/a.png)所示。',
          imageByPath: <String, ReviewQuestionImage>{
            'E:/imgs/a.png': image(),
          },
        ),
      );

      await waitForFinder(tester, find.byKey(reviewQuestionImageKey(0)));
      expect(find.byKey(reviewQuestionImageKey(0)), findsOneWidget);
      expect(find.textContaining('![示意图]'), findsNothing);
    });

    testWidgets('纯文本模式解析不到路径时保留原文，不联网', (tester) async {
      await pump(
        tester,
        const ReviewQuestionText(text: '见 ![](E:/missing.png) 处。'),
      );

      expect(find.byType(Image), findsNothing);
      expect(find.textContaining('![](E:/missing.png)'), findsOneWidget);
    });

    testWidgets('Markdown 模式解析不到路径时转成行内代码，不让渲染器去拉网络图', (tester) async {
      await pump(
        tester,
        const ReviewQuestionText(
          text: '见 ![](https://example.com/a.png) 处。',
          markdown: true,
        ),
      );

      expect(find.byType(GptMarkdown), findsWidgets);
      expect(find.byType(Image), findsNothing);
      // 行内代码可能由 GptMarkdown 包在 RichText 里，连 RichText 一起找。
      expect(
        find.textContaining('https://example.com/a.png', findRichText: true),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}

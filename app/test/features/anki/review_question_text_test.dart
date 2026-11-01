import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/anki/presentation/review_question_text.dart';
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

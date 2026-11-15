// 学生页“我有问题”入口的 widget 测试（P0 B11）。
//
// 钉四件事：
// 1) 学生页有“我有问题”入口，默认折叠；简单题的 DAG/答案/解析不自动展开；
// 2) 输入问题后能拿到基于这道题内容的回答（步骤/公式/错因）；
// 3) 无命中时明确说“这题没有直接对应内容”，不把别的内容塞进回答；
// 4) 回答里不出现开发者/证据/信任字段；可以连续追问。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/design_board/domain/design_board.dart';
import 'package:furnace/features/design_board/presentation/content_sample_page.dart';

Future<DesignBoardData> _loadAsset() async {
  final file = File('assets/design_board.json');
  expect(await file.exists(), isTrue, reason: 'assets/design_board.json 必须存在');
  return DesignBoardData.decode(await file.readAsString());
}

void main() {
  late DesignBoardData assetData;

  setUpAll(() async {
    assetData = await _loadAsset();
  });

  DesignBoardCard sampleOf(String id) =>
      assetData.realContentSamples.firstWhere((sample) => sample.id == id);

  Future<void> openPage(WidgetTester tester, DesignBoardCard card) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: ContentSamplePage(sample: card)));
    await tester.pumpAndSettle();
  }

  Future<void> ask(WidgetTester tester, String id, String question) async {
    await tester.tap(find.byKey(Key('feedback-panel-$id')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(Key('feedback-input-$id')), question);
    await tester.tap(find.byKey(Key('feedback-send-$id')));
    await tester.pumpAndSettle();
  }

  Finder answerOf(String id, int index) =>
      find.byKey(Key('feedback-answer-$id-$index'));

  group('我有问题入口', () {
    testWidgets('入口存在且默认折叠；简单题 DAG/答案/解析不自动展开', (tester) async {
      final physics = sampleOf('Q-PH0001');
      await openPage(tester, physics);

      expect(find.text('我有问题'), findsOneWidget);
      expect(find.byKey(const Key('feedback-panel-Q-PH0001')), findsOneWidget);
      // 折叠时不渲染输入框。
      expect(find.byKey(const Key('feedback-input-Q-PH0001')), findsNothing);
      // 简单题（单选）不自动展开 DAG、答案、解析；简单题选板里没有 DAG。
      expect(find.text('Thinking DAG'), findsNothing);
      expect(find.byKey(const Key('dag-flow-Q-PH0001')), findsNothing);
      expect(find.byKey(const Key('answer-content-Q-PH0001')), findsNothing);
      expect(find.byKey(const Key('solution-panel-Q-PH0001')), findsNothing);
      // 单选题不给答题区（既有规则不回归）。
      expect(find.text('答题区'), findsNothing);
    });

    testWidgets('展开入口后有输入框和提问按钮', (tester) async {
      await openPage(tester, sampleOf('Q-PH0001'));
      await tester.tap(find.byKey(const Key('feedback-panel-Q-PH0001')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('feedback-input-Q-PH0001')), findsOneWidget);
      expect(find.byKey(const Key('feedback-send-Q-PH0001')), findsOneWidget);
      expect(find.text('还没有提问。'), findsOneWidget);
    });
  });

  group('提问 → 基于内容的回答', () {
    testWidgets('为什么 C 不对：简单题没有 DAG 步骤，只按错因回答，不编解析', (tester) async {
      await openPage(tester, sampleOf('Q-PH0001'));
      await ask(tester, 'Q-PH0001', '为什么 C 不对？');

      expect(answerOf('Q-PH0001', 0), findsOneWidget);
      final answer = answerOf('Q-PH0001', 0);
      // 简单题选板不含 Thinking DAG → 回答里没有“相关步骤与公式”。
      expect(
        find.descendant(
          of: answer,
          matching: find.textContaining('相关步骤与公式'),
        ),
        findsNothing,
      );
      // 但题目记录了“错选 C”的错因，按已有内容回答。
      expect(
        find.descendant(of: answer, matching: find.textContaining('易错点')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: answer,
          matching: find.textContaining('错选 C'),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: answer,
          matching: find.textContaining('仍不明白可以继续问'),
        ),
        findsOneWidget,
      );
      // 提问不会顺带展开答案（先做题原则）；简单题没有 DAG 卡。
      expect(find.text('Thinking DAG'), findsNothing);
      expect(find.byKey(const Key('answer-content-Q-PH0001')), findsNothing);
      // 提问后输入框清空，方便继续追问。
      final field = tester.widget<TextField>(
        find.byKey(const Key('feedback-input-Q-PH0001')),
      );
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('问公式：简单题无 DAG 步骤，只引错因，不冒充公式解析', (tester) async {
      await openPage(tester, sampleOf('Q-PH0001'));
      await ask(tester, 'Q-PH0001', '速度大小的表达式是什么？');

      final answer = answerOf('Q-PH0001', 0);
      expect(answer, findsOneWidget);
      // 没有 DAG 节点 → 不出现“相关步骤与公式”。
      expect(
        find.descendant(
          of: answer,
          matching: find.textContaining('相关步骤与公式'),
        ),
        findsNothing,
      );
      // 命中错因（速度大小混淆）并按已有内容回答，不编公式解析。
      expect(
        find.descendant(of: answer, matching: find.textContaining('易错点')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: answer, matching: find.textContaining('速度大小')),
        findsWidgets,
      );
    });

    testWidgets('数学题：独立性检验怎么问都能引到对应步骤', (tester) async {
      await openPage(tester, sampleOf('Q-MA0001'));
      await ask(tester, 'Q-MA0001', '独立性检验怎么做？');

      final answer = answerOf('Q-MA0001', 0);
      expect(answer, findsOneWidget);
      expect(
        find.descendant(of: answer, matching: find.textContaining('独立性检验')),
        findsWidgets,
      );
    });

    testWidgets('可追问：连续两个问题各自保留回答', (tester) async {
      await openPage(tester, sampleOf('Q-PH0001'));
      await ask(tester, 'Q-PH0001', '为什么 C 不对？');
      await ask(tester, 'Q-PH0001', '那为什么？');

      expect(answerOf('Q-PH0001', 0), findsOneWidget);
      expect(answerOf('Q-PH0001', 1), findsOneWidget);
      expect(find.text('你问：那为什么？'), findsOneWidget);
      // 追问继承上文：第二个回答仍有内容，不是“没有对应内容”。
      expect(
        find.descendant(
          of: answerOf('Q-PH0001', 1),
          matching: find.byKey(const Key('feedback-nomatch-Q-PH0001-1')),
        ),
        findsNothing,
      );
    });
  });

  group('无命中与开发者边界', () {
    testWidgets('无关问题：明确说这题没有直接对应内容，不串内容', (tester) async {
      await openPage(tester, sampleOf('Q-PH0001'));
      await ask(tester, 'Q-PH0001', '唐朝诗人为什么这样写？');

      final answer = answerOf('Q-PH0001', 0);
      expect(
        find.byKey(const Key('feedback-nomatch-Q-PH0001-0')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: answer,
          matching: find.textContaining('这题没有直接对应内容'),
        ),
        findsOneWidget,
      );
      // 不把这道题的内容塞进无命中回答。
      expect(
        find.descendant(of: answer, matching: find.textContaining('平抛')),
        findsNothing,
      );
      expect(
        find.descendant(of: answer, matching: find.textContaining('机械能')),
        findsNothing,
      );
    });

    testWidgets('回答里不出现开发者/证据/信任字段', (tester) async {
      await openPage(tester, sampleOf('Q-PH0001'));
      await ask(tester, 'Q-PH0001', '为什么 C 不对？');

      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data ?? '')
          .join('\n');
      for (final token in <String>[
        'trust',
        'hash',
        'sha256',
        'evidence',
        'Source',
        'B_independently_verified',
        'expert_authored',
        '盲解',
        '未独立审核',
        '内容包',
        'N-Q1',
      ]) {
        expect(texts, isNot(contains(token)), reason: '回答里泄露了 "$token"');
      }
    });
  });
}

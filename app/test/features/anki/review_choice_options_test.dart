import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/anki/presentation/review_choice_options.dart';

/// 闪存卡选择题的选项面板：四个按钮、单选/多选、提交后对错、自判只记录不判分。
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
    );
    await tester.pump();
  }

  const options = <String>['甲选项', '乙选项', '丙选项', '丁选项'];

  group('单选', () {
    testWidgets('四个选项按钮带 A/B/C/D 字母与文本', (tester) async {
      await pump(
        tester,
        ReviewChoiceOptions(
          options: options,
          selected: const <int>{},
          onChanged: (_) {},
        ),
      );

      expect(find.byKey(reviewOptionsKey), findsOneWidget);
      for (var i = 0; i < options.length; i++) {
        expect(find.byKey(reviewOptionButtonKey(i)), findsOneWidget);
      }
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
      expect(find.text('D'), findsOneWidget);
      expect(find.text('甲选项'), findsOneWidget);
      expect(find.text('丁选项'), findsOneWidget);
    });

    testWidgets('点击选项上报单个下标，点另一个是替换而不是累加', (tester) async {
      final events = <Set<int>>[];
      await pump(
        tester,
        ReviewChoiceOptions(
          options: options,
          selected: const <int>{},
          onChanged: events.add,
        ),
      );

      await tester.tap(find.byKey(reviewOptionButtonKey(2)));
      await tester.pump();
      await tester.tap(find.byKey(reviewOptionButtonKey(0)));
      await tester.pump();

      expect(events, <Set<int>>[
        <int>{2},
        <int>{0},
      ]);
    });
  });

  group('多选', () {
    testWidgets('多人选择可以勾多个，再点一次取消', (tester) async {
      final events = <Set<int>>[];
      await pump(
        tester,
        _ChoiceHost(options: options, onChanged: events.add, multiple: true),
      );

      await tester.tap(find.byKey(reviewOptionButtonKey(0)));
      await tester.pump();
      await tester.tap(find.byKey(reviewOptionButtonKey(2)));
      await tester.pump();
      await tester.tap(find.byKey(reviewOptionButtonKey(0)));
      await tester.pump();

      expect(events, <Set<int>>[
        <int>{0},
        <int>{0, 2},
        <int>{2},
      ]);
      // 多选用方框图标而不是单选的圆点。
      expect(find.byIcon(Icons.check_box_outlined), findsOneWidget);
    });
  });

  group('提交后', () {
    testWidgets('正确选项画勾、选错的画叉，且按钮整体禁用', (tester) async {
      var changed = false;
      await pump(
        tester,
        const ReviewChoiceOptions(
          options: options,
          selected: <int>{0},
          // 答案为 B（下标 1），用户选了 A。
          correctIndexes: <int>{1},
          onChanged: null,
        ),
      );

      expect(changed, isFalse);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);

      // 禁用：点了也不抛、不改变任何东西。
      await tester.tap(find.byKey(reviewOptionButtonKey(2)));
      await tester.pump();
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('自判模式不自动判分：留下已选高亮，但没有任何对错标记', (tester) async {
      final events = <Set<int>>[];
      await pump(
        tester,
        ReviewChoiceOptions(
          options: options,
          selected: const <int>{0},
          correctIndexes: const <int>{1},
          selfJudged: true,
          onChanged: events.add,
        ),
      );

      expect(find.byIcon(Icons.check_circle_outline), findsNothing);
      expect(find.byIcon(Icons.cancel_outlined), findsNothing);
      // 已选的那项仍有指示（自判只记录选择）。
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);

      // 还能改选：自判模式下选择事件照常上报。
      await tester.tap(find.byKey(reviewOptionButtonKey(3)));
      await tester.pump();
      expect(events, <Set<int>>[
        <int>{3},
      ]);
      expect(find.byIcon(Icons.check_circle_outline), findsNothing);
    });
  });

  group('边界', () {
    testWidgets('六个选项按 A-F 编号', (tester) async {
      await pump(
        tester,
        ReviewChoiceOptions(
          options: const <String>['一', '二', '三', '四', '五', '六'],
          selected: const <int>{},
          onChanged: (_) {},
        ),
      );
      expect(find.text('E'), findsOneWidget);
      expect(find.text('F'), findsOneWidget);
      expect(reviewOptionLetter(0), 'A');
      expect(reviewOptionLetter(25), 'Z');
      expect(reviewOptionLetter(26), '27');
    });

    testWidgets('没有选项时整块不占版面', (tester) async {
      await pump(
        tester,
        const ReviewChoiceOptions(
          options: <String>[],
          selected: <int>{},
          onChanged: null,
        ),
      );
      expect(find.byKey(reviewOptionsKey), findsNothing);
    });
  });
}

/// 受控面板的测试宿主：像 review_page 一样自己持有 [selected]，点一下重建一次，
/// 这样多选的"勾第二个"才有真实的上一次选择可累加。
class _ChoiceHost extends StatefulWidget {
  const _ChoiceHost({
    required this.options,
    required this.onChanged,
    this.multiple = false,
  });

  final List<String> options;
  final ValueChanged<Set<int>> onChanged;
  final bool multiple;

  @override
  State<_ChoiceHost> createState() => _ChoiceHostState();
}

class _ChoiceHostState extends State<_ChoiceHost> {
  Set<int> _selected = <int>{};

  @override
  Widget build(BuildContext context) {
    return ReviewChoiceOptions(
      options: widget.options,
      selected: _selected,
      multiple: widget.multiple,
      onChanged: (next) {
        setState(() => _selected = next);
        widget.onChanged(next);
      },
    );
  }
}

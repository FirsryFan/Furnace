/// 选项排布判定（短选项两列 / 长选项单列 / 窄屏单列）的纯逻辑测试。
///
/// 这些值直接决定化学 Q15 这类「四个短选项」会不会两列、英语阅读那种长选项
/// 会不会被挤成两列，所以把边界单独钉住。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/questions/question_option_layout.dart';

void main() {
  group('可见文字长度', () {
    test('纯文字按 rune 数（空白折叠不计）', () {
      expect(questionOptionVisibleLength('增大'), 2);
      expect(questionOptionVisibleLength(' 增 大 '), 2);
      expect(questionOptionVisibleLength('无法确定'), 4);
    });

    test('公式记 1 个字符，图片占位/图片语法不计', () {
      expect(questionOptionVisibleLength(r'$x^2$'), 1);
      expect(questionOptionVisibleLength(r'$$\frac{1}{2}$$'), 1);
      expect(questionOptionVisibleLength('［图12］'), 0);
      expect(questionOptionVisibleLength('[图 3]'), 0);
      expect(questionOptionVisibleLength('![示意](a.png)'), 0);
      expect(questionOptionVisibleLength('［图1］与［图2］'), 1);
    });

    test('化学 Q15 的四个选项都算短', () {
      const contents = <String>[
        '丁线所示物种为［图12］',
        '调节［图14］时，需加入［图5］',
        '［图15］点［图16］',
        '［图17］点：［图18］',
      ];
      for (final content in contents) {
        expect(
          questionOptionVisibleLength(content),
          lessThanOrEqualTo(kShortOptionMaxRunes),
          reason: content,
        );
      }
    });
  });

  group('两列 / 单列判定', () {
    const shortOptions = <String>['增大', '减小', '不变', '无法确定'];

    test('四个短选项 + 宽屏 → 两列', () {
      expect(
        questionOptionsFlowIntoTwoColumns(
          optionContents: shortOptions,
          availableWidth: 1200,
        ),
        isTrue,
      );
    });

    test('窄屏 → 单列（两列各格至少 320px、间距 12）', () {
      expect(
        questionOptionsFlowIntoTwoColumns(
          optionContents: shortOptions,
          availableWidth: 640,
        ),
        isFalse,
      );
      // 652 = 320*2 + 12：刚好够两列，652 以下不够。
      expect(
        questionOptionsFlowIntoTwoColumns(
          optionContents: shortOptions,
          availableWidth: 651,
        ),
        isFalse,
      );
      expect(
        questionOptionsFlowIntoTwoColumns(
          optionContents: shortOptions,
          availableWidth: 652,
        ),
        isTrue,
      );
    });

    test('任一长选项 → 单列', () {
      const longOptions = <String>[
        '增大',
        '减小',
        '升高温度会同时加快正逆反应速率，但平衡不发生移动',
        '无法确定',
      ];
      expect(
        questionOptionsFlowIntoTwoColumns(
          optionContents: longOptions,
          availableWidth: 1200,
        ),
        isFalse,
      );
    });

    test('多行 / 代码块 / 空选项 → 单列', () {
      expect(
        questionOptionsFlowIntoTwoColumns(
          optionContents: const <String>['甲\n乙', '丙', '丁', '戊'],
          availableWidth: 1200,
        ),
        isFalse,
      );
      expect(
        questionOptionsFlowIntoTwoColumns(
          optionContents: const <String>['```dart\nx\n```', '丙', '丁', '戊'],
          availableWidth: 1200,
        ),
        isFalse,
      );
      expect(
        questionOptionsFlowIntoTwoColumns(
          optionContents: const <String>['甲', '［图1］', '丙', '丁'],
          availableWidth: 1200,
        ),
        isFalse,
      );
    });

    test('少于两个选项不排两列', () {
      expect(
        questionOptionsFlowIntoTwoColumns(
          optionContents: const <String>['只有一个'],
          availableWidth: 1200,
        ),
        isFalse,
      );
      expect(
        questionOptionsFlowIntoTwoColumns(
          optionContents: const <String>[],
          availableWidth: 1200,
        ),
        isFalse,
      );
    });
  });
}

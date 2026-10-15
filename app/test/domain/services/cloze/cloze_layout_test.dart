import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/cloze/cloze_layout.dart';

/// 挖空就地呈现的纯切分逻辑测试。
///
/// 输入的 `question` 就是 `ReviewService._clozeItem` 现场渲染出来的那一串
/// （app/lib/features/anki/application/review_service.dart:655-657：
/// `content.substring(0, start) + '______' + content.substring(start + length)`），
/// `slotStart` 是 `ReviewItem.slotStart`。这里只做「按既有下标切开」，不重新找空。
void main() {
  group('ClozeLayout.of', () {
    test('按 slotStart 切出空格前后两段，并能把答案填回原句', () {
      const question = '光合作用的主要场所是______。';
      final layout = ClozeLayout.of(question: question, slotStart: 10);

      expect(layout, isNotNull);
      expect(layout!.prefix, '光合作用的主要场所是');
      expect(layout.suffix, '。');
      expect(layout.blank, '______');
      expect(layout.blankWidth, 6);
      // 拼接回原句必须逐字符相等（不丢不改任何字）。
      expect(layout.masked, question);
      expect(layout.reveal('叶绿体'), '光合作用的主要场所是叶绿体。');
    });

    test('比 6 个更长的下划线一样能切（沿用 _renderBlank 的 3+ 口径）', () {
      const question = '答案是________这里。';
      final layout = ClozeLayout.of(question: question, slotStart: 3);

      expect(layout, isNotNull);
      expect(layout!.blankWidth, 8);
      expect(layout.prefix, '答案是');
      expect(layout.suffix, '这里。');
      expect(layout.reveal('甲'), '答案是甲这里。');
    });

    test('空格在开头 / 结尾时不产生多余字符', () {
      final head = ClozeLayout.of(question: '____是开头', slotStart: 0);
      expect(head!.prefix, '');
      expect(head.suffix, '是开头');
      expect(head.reveal('这'), '这是开头');

      final tail = ClozeLayout.of(question: '结尾是____', slotStart: 3);
      expect(tail!.suffix, '');
      expect(tail.reveal('这个'), '结尾是这个');
    });

    test('一个句子里有两个空时只切 slotStart 指的那一个', () {
      const question = '____和______。';
      final layout = ClozeLayout.of(question: question, slotStart: 5);

      expect(layout!.prefix, '____和');
      expect(layout.suffix, '。');
      expect(layout.reveal('甲'), '____和甲。');
    });

    test('slotStart 为空 / 越界 / 对不上下划线时返回 null（调用方回退旧渲染）', () {
      expect(ClozeLayout.of(question: '光合作用的主要场所是______。', slotStart: null),
          isNull);
      expect(
          ClozeLayout.of(question: '光合作用的主要场所是______。', slotStart: -1), isNull);
      expect(ClozeLayout.of(question: '光合作用的主要场所是______。', slotStart: 100),
          isNull);
      // slotStart 落在答案文本上而不是下划线上：不猜，直接回退。
      expect(
          ClozeLayout.of(question: '光合作用的主要场所是______。', slotStart: 0), isNull);
      // 只有 1 个下划线：不算空（与 _renderBlank 的 3+ 口径一致）。
      expect(ClozeLayout.of(question: '一个_下划线', slotStart: 2), isNull);
    });

    test('空字符串 / 全空白等退化输入不抛异常', () {
      expect(ClozeLayout.of(question: '', slotStart: null), isNull);
      expect(ClozeLayout.of(question: '', slotStart: 0), isNull);
      expect(ClozeLayout.of(question: '   ', slotStart: 1), isNull);
      expect(
          ClozeLayout.of(question: '______', slotStart: 0)!.reveal('x'), 'x');
    });
  });
}

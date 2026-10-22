import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/questions/question_snapshot_summary.dart';
import 'package:furnace/domain/services/questions/question_stem_display.dart';
import 'package:furnace/domain/services/questions/question_stem_preview.dart';

QuestionStemDisplay _display(
  String stem, {
  int imageCount = 0,
  int maxLength = kQuestionStemPreviewMaxLength,
}) {
  return resolveQuestionStemDisplay(
    stem: stem,
    imageCount: imageCount,
    maxLength: maxLength,
  );
}

void main() {
  group('快照（只传数量，走 B2）', () {
    test('有正文摘录时用摘录，标签与占位计数一起给出', () {
      final QuestionStemDisplay display =
          _display('已知函数图像［图1］与［图2］', imageCount: 1);
      expect(display.isSnapshot, isTrue);
      expect(display.label, '整题截图 · 2 处公式/图');
      expect(display.hasExcerpt, isTrue);
      expect(display.text, '已知函数图像与');
      expect(display.imageCount, 1);
      expect(display.placeholderCount, 2);
      expect(display.isEmpty, isFalse);
    });

    test('纯占位题没有摘录 → 用标签兜底', () {
      final QuestionStemDisplay display = _display('［图1］［图2］', imageCount: 1);
      expect(display.isSnapshot, isTrue);
      expect(display.hasExcerpt, isFalse);
      expect(display.text, '整题截图 · 2 处公式/图');
      expect(display.text, display.label);
      expect(display.isEmpty, isFalse);
    });

    test('正文不足 4 个 runes → 没有摘录，退回标签', () {
      final QuestionStemDisplay display = _display('如图［图1］［图2］', imageCount: 1);
      expect(display.isSnapshot, isTrue);
      expect(display.hasExcerpt, isFalse);
      expect(display.text, '整题截图 · 2 处公式/图');
    });

    test('摘录按 maxLength 截断', () {
      final QuestionStemDisplay display = _display(
        '一二三四五六七八九十［图1］［图2］',
        imageCount: 1,
        maxLength: 5,
      );
      expect(display.isSnapshot, isTrue);
      expect(display.hasExcerpt, isTrue);
      expect(display.text, '一二三四五…');
      expect(display.text.runes.length, 6);
    });

    test('maxLength=0 的快照 → 摘录为空，退回标签', () {
      final QuestionStemDisplay display = _display(
        '已知函数［图1］［图2］',
        imageCount: 1,
        maxLength: 0,
      );
      expect(display.isSnapshot, isTrue);
      expect(display.hasExcerpt, isFalse);
      expect(display.text, '整题截图 · 2 处公式/图');
    });

    test('占位 3 个 + 正文够长 → 标签数字与占位计数一致', () {
      final QuestionStemDisplay display = _display(
        '甲乙丙丁［图1］［图2］［图3］',
        imageCount: 1,
      );
      expect(display.label, '整题截图 · 3 处公式/图');
      expect(display.placeholderCount, 3);
      expect(display.hasExcerpt, isTrue);
      expect(display.text, '甲乙丙丁');
    });

    test('imageCount=2 时 B2 不触发 → 走普通题口径', () {
      const String stem = '题干内容［图1］［图2］';
      final QuestionStemDisplay display = _display(stem, imageCount: 2);
      expect(display.isSnapshot, isFalse);
      expect(display.label, '');
      expect(display.hasExcerpt, isFalse);
      expect(display.text, '题干内容［图］［图］');
      expect(display.text, questionStemPreview(stem));
      expect(display.imageCount, 2);
      expect(display.placeholderCount, 2);
    });
  });

  group('普通题', () {
    test('0 图普通题 → preview 文本，无标签无摘录', () {
      const String stem = '已知函数\$x^2\$求值。';
      final QuestionStemDisplay display = _display(stem);
      expect(display.isSnapshot, isFalse);
      expect(display.label, '');
      expect(display.hasExcerpt, isFalse);
      expect(display.text, questionStemPreview(stem));
      expect(display.placeholderCount, 0);
      expect(display.imageCount, 0);
      expect(display.isEmpty, isFalse);
    });

    test('1 图 1 占位 → 数量不够 B2，普通题', () {
      const String stem = '题干［图1］';
      final QuestionStemDisplay display = _display(stem, imageCount: 1);
      expect(display.isSnapshot, isFalse);
      expect(display.text, '题干［图］');
      expect(display.text, questionStemPreview(stem));
      expect(display.placeholderCount, 1);
    });

    test('有图但没有占位 → 普通题', () {
      final QuestionStemDisplay display = _display('纯文字题干', imageCount: 3);
      expect(display.isSnapshot, isFalse);
      expect(display.text, '纯文字题干');
      expect(display.imageCount, 3);
      expect(display.placeholderCount, 0);
    });

    test('长题干按 maxLength 截断', () {
      final String stem = '已知${'函数' * 20}';
      final QuestionStemDisplay display = _display(stem, maxLength: 10);
      expect(display.text, questionStemPreview(stem, maxLength: 10));
      expect(display.text.endsWith('…'), isTrue);
      expect(display.text.runes.length, 11);
    });

    test('maxLength=0 → 空文本、isEmpty', () {
      final QuestionStemDisplay display = _display('已知函数', maxLength: 0);
      expect(display.text, '');
      expect(display.label, '');
      expect(display.hasExcerpt, isFalse);
      expect(display.isEmpty, isTrue);
    });

    test('markdown 图片与公式按 preview 口径处理', () {
      const String stem = '![题图](http://a/b.png) 已知 \$x^2\$ 求值';
      final QuestionStemDisplay display = _display(stem);
      expect(display.text, questionStemPreview(stem));
      expect(display.text.contains('!['), isFalse);
      expect(display.text.contains('\$'), isFalse);
    });

    test('空题干 → 空文本、isEmpty、不抛', () {
      final QuestionStemDisplay display = _display('');
      expect(display.text, '');
      expect(display.isEmpty, isTrue);
      expect(display.isSnapshot, isFalse);
      expect(display.label, '');
      expect(display.imageCount, 0);
      expect(display.placeholderCount, 0);
    });

    test('全空白题干 + 有图数 → 文本仍为空', () {
      final QuestionStemDisplay display = _display('   \n\t ', imageCount: 5);
      expect(display.text, '');
      expect(display.isEmpty, isTrue);
      expect(display.isSnapshot, isFalse);
      expect(display.imageCount, 5);
      expect(display.placeholderCount, 0);
    });

    test('非快照 hasExcerpt 恒为 false（即使 text 非空）', () {
      final QuestionStemDisplay display = _display('普通题干');
      expect(display.hasExcerpt, isFalse);
      expect(display.text, '普通题干');
      expect(display.label, '');
      expect(display.isEmpty, isFalse);
    });
  });

  group('边界与不抛', () {
    test('负 imageCount 归一成 0', () {
      final QuestionStemDisplay display = _display('题干', imageCount: -4);
      expect(display.isSnapshot, isFalse);
      expect(display.imageCount, 0);
      expect(display.text, '题干');
    });

    test('负 imageCount 时占位仍计数', () {
      const String stem = '题干［图1］［图2］';
      final QuestionStemDisplay display = _display(stem, imageCount: -3);
      expect(display.imageCount, 0);
      expect(display.placeholderCount, 2);
      expect(display.isSnapshot, isFalse);
      expect(display.text, '题干［图］［图］');
    });

    test('空题干 + 负数图数不抛', () {
      final QuestionStemDisplay display = _display('', imageCount: -1);
      expect(display.text, '');
      expect(display.isEmpty, isTrue);
      expect(display.imageCount, 0);
    });

    test('3000 字题干不崩，按 runes 截断', () {
      final String stem = '啊' * 3000;
      final QuestionStemDisplay display = _display(stem);
      expect(display.text.runes.length, kQuestionStemPreviewMaxLength + 1);
      expect(display.text.startsWith('啊'), isTrue);
      expect(display.text.endsWith('…'), isTrue);
    });

    test('maxLength=1 普通题 → 一个 rune + 省略号', () {
      final QuestionStemDisplay display = _display('已知函数', maxLength: 1);
      expect(display.text, '已…');
      expect(display.isEmpty, isFalse);
    });

    test('maxLength=1 快照题 → 摘录不足 4 runes，退回标签', () {
      final QuestionStemDisplay display = _display(
        '已知函数［图1］［图2］',
        imageCount: 1,
        maxLength: 1,
      );
      expect(display.isSnapshot, isTrue);
      expect(display.hasExcerpt, isFalse);
      expect(display.text, display.label);
    });

    test('题干首尾空白 → preview 自己收掉，结果无首尾空格', () {
      final QuestionStemDisplay display = _display('  已知函数  ');
      expect(display.text, '已知函数');
    });

    test('快照题首尾空白 → 摘录清洗掉', () {
      final QuestionStemDisplay display = _display(
        '  已知函数  ［图1］［图2］',
        imageCount: 1,
      );
      expect(display.isSnapshot, isTrue);
      expect(display.hasExcerpt, isTrue);
      expect(display.text, '已知函数');
    });

    test('快照 text 与 summarize 结果一致（不重复实现）', () {
      const String stem = '已知函数图像［图1］与［图2］';
      final QuestionSnapshotSummary summary = summarizeQuestionStemSnapshot(
        stem: stem,
        stemImageCount: 1,
      );
      final QuestionStemDisplay display = _display(stem, imageCount: 1);
      expect(display.text, summary.textExcerpt);
      expect(display.label, summary.labelZh);
      expect(display.hasExcerpt, summary.hasTextExcerpt);
      expect(display.placeholderCount, summary.placeholderCount);
    });

    test('快照摘录里不残留占位 token', () {
      final QuestionStemDisplay display =
          _display('已知函数图像［图1］与［图2］', imageCount: 1);
      expect(display.text.contains('［图'), isFalse);
      expect(display.text.contains('图1'), isFalse);
    });
  });

  group('值语义', () {
    test('相同输入相等且 hashCode 一致', () {
      final QuestionStemDisplay a = _display('已知函数［图1］［图2］', imageCount: 1);
      final QuestionStemDisplay b = _display('已知函数［图1］［图2］', imageCount: 1);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('maxLength 不同 → 文本不同、值不相等', () {
      const String stem = '一二三四五六七八九十';
      final QuestionStemDisplay short = _display(stem, maxLength: 5);
      final QuestionStemDisplay long = _display(stem, maxLength: 10);
      expect(short.text, isNot(long.text));
      expect(short == long, isFalse);
    });

    test('快照与非快照不相等（同题干不同图数）', () {
      const String stem = '题干内容［图1］与［图2］';
      final QuestionStemDisplay snapshot = _display(stem, imageCount: 1);
      final QuestionStemDisplay plain = _display(stem, imageCount: 2);
      expect(snapshot.isSnapshot, isTrue);
      expect(plain.isSnapshot, isFalse);
      expect(snapshot == plain, isFalse);
      expect(snapshot, isNot(equals(plain)));
    });

    test('toString 带关键字段', () {
      final String text = _display('已知函数［图1］［图2］', imageCount: 1).toString();
      expect(text, contains('QuestionStemDisplay'));
      expect(text, contains('isSnapshot: true'));
      expect(text, contains('label: 整题截图 · 2 处公式/图'));
      expect(text, contains('placeholderCount: 2'));
    });

    test('isEmpty：快照用标签兜底 → 非空', () {
      final QuestionStemDisplay display = _display('［图1］［图2］', imageCount: 1);
      expect(display.text, isNotEmpty);
      expect(display.isEmpty, isFalse);
    });

    test('isEmpty 只按 trim 后的文本判断', () {
      final QuestionStemDisplay display = _display('   ', maxLength: 0);
      expect(display.text, '');
      expect(display.isEmpty, isTrue);
    });
  });
}

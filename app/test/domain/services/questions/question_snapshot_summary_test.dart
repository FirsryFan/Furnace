import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/questions/question_snapshot_summary.dart';
import 'package:furnace/domain/services/questions/question_stem_image_plan.dart';
import 'package:furnace/domain/services/questions/question_stem_preview.dart';

const QuestionStemImageSize _big = QuestionStemImageSize(1640, 808);
const QuestionStemImageSize _small = QuestionStemImageSize(400, 300);

const List<QuestionStemImageSize?> _noSizes = <QuestionStemImageSize?>[];

QuestionSnapshotSummary _snap(
  String stem, {
  int imageCount = 1,
  List<QuestionStemImageSize?> imageSizes = const <QuestionStemImageSize?>[
    _big
  ],
  int excerptMaxLength = kQuestionSnapshotExcerptMaxLength,
}) {
  return summarizeQuestionStemSnapshot(
    stem: stem,
    stemImageCount: imageCount,
    imageSizes: imageSizes,
    excerptMaxLength: excerptMaxLength,
  );
}

String _placeholders(int count) =>
    List<String>.generate(count, (int i) => '［图${i + 1}］').join();

void main() {
  group('整卡快照（B1 尺寸触发）', () {
    test('真实包式：12 处占位 + 1 张 1640x808 → 快照，占位全变省略号', () {
      final String stem =
          List<String>.generate(12, (int i) => '第${i + 1}段题干内容［图${i + 1}］')
              .join();
      final QuestionSnapshotSummary summary = _snap(stem);
      expect(summary.isSnapshot, isTrue);
      expect(summary.placeholderCount, 12);
      expect(summary.imageCount, 1);
      expect(summary.labelZh, '整题截图 · 12 处公式/图');
      final String expectedNeutralized = List<String>.generate(
        12,
        (int i) => '第${i + 1}段题干内容…',
      ).join();
      expect(summary.neutralizedStem, expectedNeutralized);
      expect(summary.neutralizedStem.contains('［图'), isFalse);
      expect(summary.hasTextExcerpt, isTrue);
      expect(summary.textExcerpt.contains('［图'), isFalse);
      expect(summary.textExcerpt.runes.length,
          kQuestionSnapshotExcerptMaxLength + 1);
      expect(summary.textExcerpt.endsWith('…'), isTrue);
    });

    test('单处占位 + 大图 → 快照，摘录只留正文', () {
      final QuestionSnapshotSummary summary = _snap('已知函数图像如图。［图1］');
      expect(summary.isSnapshot, isTrue);
      expect(summary.placeholderCount, 1);
      expect(summary.labelZh, '整题截图 · 1 处公式/图');
      expect(summary.neutralizedStem, '已知函数图像如图。…');
      expect(summary.textExcerpt, '已知函数图像如图');
      expect(summary.hasTextExcerpt, isTrue);
    });

    test('快照但正文没有占位 → 标签只写「整题截图」', () {
      final QuestionSnapshotSummary summary = _snap('整题截图题面');
      expect(summary.isSnapshot, isTrue);
      expect(summary.placeholderCount, 0);
      expect(summary.labelZh, '整题截图');
      expect(summary.neutralizedStem, '整题截图题面');
      expect(summary.textExcerpt, '整题截图题面');
    });

    test('两张图都够大 → 快照，imageCount 记 2', () {
      final QuestionSnapshotSummary summary = _snap(
        '题面［图1］续［图2］',
        imageCount: 2,
        imageSizes: const <QuestionStemImageSize?>[_big, _big],
      );
      expect(summary.isSnapshot, isTrue);
      expect(summary.imageCount, 2);
      expect(summary.placeholderCount, 2);
      expect(summary.labelZh, '整题截图 · 2 处公式/图');
      expect(summary.neutralizedStem, '题面…续…');
    });

    test('空题干 + 大图 → 快照但没有正文，isEmpty 为真', () {
      final QuestionSnapshotSummary summary = _snap('');
      expect(summary.isSnapshot, isTrue);
      expect(summary.placeholderCount, 0);
      expect(summary.imageCount, 1);
      expect(summary.labelZh, '整题截图');
      expect(summary.neutralizedStem, '');
      expect(summary.textExcerpt, '');
      expect(summary.hasTextExcerpt, isFalse);
      expect(summary.isEmpty, isTrue);
    });
  });

  group('数量兜底（B2 无尺寸）', () {
    test('1 图 + 2 占位无尺寸 → 快照', () {
      final QuestionSnapshotSummary summary = _snap(
        '题干内容［图1］与［图2］',
        imageSizes: _noSizes,
      );
      expect(summary.isSnapshot, isTrue);
      expect(summary.placeholderCount, 2);
      expect(summary.labelZh, '整题截图 · 2 处公式/图');
      expect(summary.neutralizedStem, '题干内容…与…');
      expect(summary.textExcerpt, '题干内容与');
      expect(summary.hasTextExcerpt, isTrue);
    });

    test('纯占位 12 个无尺寸 → 快照、摘录为空但摘要非空', () {
      final String stem = _placeholders(12);
      final QuestionSnapshotSummary summary = _snap(stem, imageSizes: _noSizes);
      expect(summary.isSnapshot, isTrue);
      expect(summary.placeholderCount, 12);
      expect(summary.labelZh, '整题截图 · 12 处公式/图');
      expect(summary.neutralizedStem, '…' * 12);
      expect(summary.textExcerpt, '');
      expect(summary.hasTextExcerpt, isFalse);
      expect(summary.isEmpty, isFalse);
    });

    test('1 图 + 1 占位无尺寸 → 不是快照（数量不够）', () {
      const String stem = '题干［图1］';
      final QuestionSnapshotSummary summary = _snap(stem, imageSizes: _noSizes);
      expect(summary.isSnapshot, isFalse);
      expect(summary.labelZh, '');
      expect(summary.neutralizedStem, stem);
      expect(summary.textExcerpt, questionStemPreview(stem));
      expect(summary.hasTextExcerpt, isTrue);
    });

    test('1 图 + 2 占位但有一张已知小尺寸 → 不是快照', () {
      const String stem = '题干内容［图1］与［图2］';
      final QuestionSnapshotSummary summary = _snap(
        stem,
        imageSizes: const <QuestionStemImageSize?>[_small],
      );
      expect(summary.isSnapshot, isFalse);
      expect(summary.labelZh, '');
      expect(summary.neutralizedStem, stem);
    });

    test('尺寸数组含 null 项仍按未知处理 → B2 触发快照', () {
      final QuestionSnapshotSummary summary = _snap(
        '题干内容［图1］与［图2］',
        imageSizes: const <QuestionStemImageSize?>[null],
      );
      expect(summary.isSnapshot, isTrue);
      expect(summary.labelZh, '整题截图 · 2 处公式/图');
    });
  });

  group('非快照语义不变', () {
    test('0 图 → 不是快照，摘录等同 questionStemPreview', () {
      const String stem = '已知\$x^2\$求值。';
      final QuestionSnapshotSummary summary =
          _snap(stem, imageCount: 0, imageSizes: _noSizes);
      expect(summary.isSnapshot, isFalse);
      expect(summary.imageCount, 0);
      expect(summary.placeholderCount, 0);
      expect(summary.labelZh, '');
      expect(summary.neutralizedStem, stem);
      expect(summary.textExcerpt, questionStemPreview(stem));
      expect(summary.hasTextExcerpt, isTrue);
    });

    test('负 imageCount 归一成 0', () {
      const String stem = '题干［图1］';
      final QuestionSnapshotSummary summary =
          _snap(stem, imageCount: -3, imageSizes: _noSizes);
      expect(summary.isSnapshot, isFalse);
      expect(summary.imageCount, 0);
      expect(summary.neutralizedStem, stem);
      expect(summary.textExcerpt, questionStemPreview(stem));
    });

    test('2 图 2 占位但尺寸都小 → 不是快照，占位仍计数', () {
      const String stem = '题干［图1］与［图2］';
      final QuestionSnapshotSummary summary = _snap(
        stem,
        imageCount: 2,
        imageSizes: const <QuestionStemImageSize?>[_small, _small],
      );
      expect(summary.isSnapshot, isFalse);
      expect(summary.imageCount, 2);
      expect(summary.placeholderCount, 2);
      expect(summary.labelZh, '');
      expect(summary.neutralizedStem, stem);
    });

    test('非快照 excerptMaxLength=0 → 摘录为空但摘要不空', () {
      final QuestionSnapshotSummary summary = _snap(
        '题干',
        imageCount: 0,
        imageSizes: _noSizes,
        excerptMaxLength: 0,
      );
      expect(summary.textExcerpt, '');
      expect(summary.hasTextExcerpt, isFalse);
      expect(summary.neutralizedStem, '题干');
      expect(summary.isEmpty, isFalse);
    });

    test('非快照空题干 → isEmpty 且不抛', () {
      final QuestionSnapshotSummary summary =
          _snap('', imageCount: 0, imageSizes: _noSizes);
      expect(summary.isSnapshot, isFalse);
      expect(summary.neutralizedStem, '');
      expect(summary.textExcerpt, '');
      expect(summary.hasTextExcerpt, isFalse);
      expect(summary.isEmpty, isTrue);
    });
  });

  group('快照摘录清洗', () {
    test('剥掉首尾标点与空白', () {
      final QuestionSnapshotSummary summary = _snap('，。 已知 ［图1］ 函数 ！？');
      expect(summary.textExcerpt, '已知 函数');
      expect(summary.hasTextExcerpt, isTrue);
    });

    test('折叠换行/制表/连续空白成一个半角空格', () {
      final QuestionSnapshotSummary summary = _snap('已知（1）\n\n\t ［图1］  函数');
      expect(summary.textExcerpt, '已知（1） 函数');
    });

    test('连续省略号压成一个', () {
      final QuestionSnapshotSummary summary = _snap('已知……［图1］……函数');
      expect(summary.neutralizedStem, '已知……………函数');
      expect(summary.textExcerpt, '已知…函数');
      expect(summary.hasTextExcerpt, isTrue);
    });

    test('按 runes 截断并补省略号', () {
      final QuestionSnapshotSummary summary = _snap(
        '一二三四五六七八九十',
        excerptMaxLength: 8,
      );
      expect(summary.textExcerpt, '一二三四五六七八…');
      expect(summary.textExcerpt.runes.length, 9);
    });

    test('截断后不足 4 个 runes → 视为没有摘录', () {
      final QuestionSnapshotSummary summary = _snap(
        '一二三四五六七八九十',
        excerptMaxLength: 2,
      );
      expect(summary.textExcerpt, '');
      expect(summary.hasTextExcerpt, isFalse);
    });

    test('excerptMaxLength <= 0 → 空摘录', () {
      for (final int limit in <int>[0, -5]) {
        final QuestionSnapshotSummary summary =
            _snap('一二三四五', excerptMaxLength: limit);
        expect(summary.textExcerpt, '', reason: 'limit=$limit');
        expect(summary.hasTextExcerpt, isFalse, reason: 'limit=$limit');
      }
    });

    test('runes 截断不切坏 emoji', () {
      final QuestionSnapshotSummary summary = _snap(
        '😀😀😀😀😀',
        excerptMaxLength: 3,
      );
      expect(summary.textExcerpt, '😀😀😀…');
      expect(summary.textExcerpt.runes.length, 4);
    });

    test('正文恰好 3 个 runes → 空摘录', () {
      final QuestionSnapshotSummary summary = _snap('已知解。［图1］');
      expect(summary.textExcerpt, '');
      expect(summary.hasTextExcerpt, isFalse);
    });

    test('正文恰好 4 个 runes → 保留', () {
      final QuestionSnapshotSummary summary = _snap('已知函数［图1］');
      expect(summary.textExcerpt, '已知函数');
      expect(summary.hasTextExcerpt, isTrue);
    });

    test('全角数字与【图】占位一并移除', () {
      final QuestionSnapshotSummary summary = _snap('【图２】已知［图 1］函数');
      expect(summary.placeholderCount, 2);
      expect(summary.textExcerpt, '已知函数');
    });

    test('半角占位 [图3] 也移除', () {
      final QuestionSnapshotSummary summary = _snap('[图3]已知函数');
      expect(summary.placeholderCount, 1);
      expect(summary.textExcerpt, '已知函数');
    });
  });

  group('值语义与健壮性', () {
    test('相同输入两次结果相等且 hashCode 一致', () {
      const String stem = '已知［图1］函数';
      final QuestionSnapshotSummary a = _snap(stem);
      final QuestionSnapshotSummary b = _snap(stem);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('快照与非快照摘要不相等', () {
      const String stem = '题干内容［图1］与［图2］';
      final QuestionSnapshotSummary snapshot = _snap(stem);
      final QuestionSnapshotSummary inline =
          _snap(stem, imageCount: 0, imageSizes: _noSizes);
      expect(snapshot == inline, isFalse);
      expect(snapshot, isNot(equals(inline)));
    });

    test('toString 带类型名与关键字段', () {
      final String text = _snap('已知函数［图1］').toString();
      expect(text, contains('QuestionSnapshotSummary'));
      expect(text, contains('isSnapshot: true'));
      expect(text, contains('placeholderCount: 1'));
      expect(text, contains('labelZh: 整题截图 · 1 处公式/图'));
    });

    test('空题干 + 负图数 + 含 null 尺寸数组不抛', () {
      final QuestionSnapshotSummary summary = summarizeQuestionStemSnapshot(
        stem: '',
        stemImageCount: -2,
        imageSizes: const <QuestionStemImageSize?>[null],
      );
      expect(summary.isSnapshot, isFalse);
      expect(summary.imageCount, 0);
      expect(summary.neutralizedStem, '');
      expect(summary.isEmpty, isTrue);
    });

    test('尺寸数组短于图数：已知大图仍触发快照', () {
      final QuestionSnapshotSummary summary = _snap(
        '题干内容［图1］与［图2］',
        imageCount: 3,
        imageSizes: const <QuestionStemImageSize?>[_big],
      );
      expect(summary.isSnapshot, isTrue);
      expect(summary.imageCount, 3);
      expect(summary.placeholderCount, 2);
      expect(summary.neutralizedStem, '题干内容…与…');
    });

    test('无占位快照保留原始空白与公式定界符', () {
      const String stem = '已知 \$x^2\$ 求值';
      final QuestionSnapshotSummary summary = _snap(stem);
      expect(summary.isSnapshot, isTrue);
      expect(summary.placeholderCount, 0);
      expect(summary.neutralizedStem, stem);
      expect(summary.textExcerpt, stem);
      expect(summary.hasTextExcerpt, isTrue);
    });

    test('excerptMaxLength 很大 → 不截断、无省略号', () {
      final QuestionSnapshotSummary summary =
          _snap('已知函数图像', excerptMaxLength: 1000);
      expect(summary.textExcerpt, '已知函数图像');
      expect(summary.textExcerpt.endsWith('…'), isFalse);
    });

    test('非快照也统计占位数量，但不给标签', () {
      const String stem = '题干［图1］［图2］';
      final QuestionSnapshotSummary summary =
          _snap(stem, imageCount: 0, imageSizes: _noSizes);
      expect(summary.placeholderCount, 2);
      expect(summary.isSnapshot, isFalse);
      expect(summary.labelZh, '');
      expect(summary.textExcerpt, questionStemPreview(stem));
    });
  });
}

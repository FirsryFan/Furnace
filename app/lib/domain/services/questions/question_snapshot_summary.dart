/// 题干「整卡快照」摘要（纯逻辑，不 import Flutter / dart:io）。
///
/// 真实抓题包里经常出现：一道题只配了 1 张整题截图（实测 PNG 1640x808），
/// 题干正文里却留着 1~44 处「［图N］」公式/内联图占位。列表页、题目卡片、
/// 导出提示需要一句话说明「这题的图是整张截图，正文里的占位只是公式位置」，
/// 同时给一个可读的正文摘录。本文件把这件事抽成 [QuestionSnapshotSummary]：
///
/// * 快照判定与占位中性化完全复用 [planQuestionStemRender]（B1 真实尺寸 /
///   B2 「1 图 + 多个占位但没尺寸」的数量兜底），本层不重复实现判定；
/// * 非快照题的语义不变：`neutralizedStem` 是原题干，摘录用
///   [questionStemPreview]；
/// * 纯函数、不抛异常、结果确定。
library;

import 'question_stem_image_plan.dart';
import 'question_stem_preview.dart';

/// 题干快照摘要的默认摘录长度（runes。与 [questionStemPreview] 默认一致）。
const int kQuestionSnapshotExcerptMaxLength = 60;

/// 占位：全角/半角方括号或【】包住的「图」+ 1~3 位数字（含全角数字）。
///
/// 与 `question_stem_segments.dart` / `question_stem_preview.dart` 的私有
/// 实现同口径；那边没有导出，这里按契约照抄一份，改一处要同步其它处。
final RegExp _snapshotPlaceholderPattern = RegExp(
  r'[［\[【]\s*图\s*[0-9０-９]{1,3}\s*[］\]】]',
);

/// 连续的省略号（U+2026）折叠成一个。
final RegExp _ellipsisRunPattern = RegExp('…+');

/// 连续空白（含换行、制表、全角空格）折叠成一个半角空格。
final RegExp _whitespaceRunPattern = RegExp(r'\s+');

/// 摘录首尾要剥掉的标点（全角/半角各一份；不含省略号，省略号是正文的一部分）。
const String _excerptEdgePunctuation = '，。；、：！？,.!?;:';

/// 一道题题干的快照摘要（不可变值对象）。
///
/// 由 [summarizeQuestionStemSnapshot] 生成。非快照题的 [isSnapshot] 为 false、
/// [labelZh] 为空、[neutralizedStem] 是原题干。
class QuestionSnapshotSummary {
  const QuestionSnapshotSummary({
    required this.isSnapshot,
    required this.placeholderCount,
    required this.imageCount,
    required this.neutralizedStem,
    required this.labelZh,
    required this.textExcerpt,
    required this.hasTextExcerpt,
  });

  /// 这题的题干图是不是「整题截图」（快照模式）。
  final bool isSnapshot;

  /// 题干里「［图N］」占位出现的总次数（含越界 N）。
  final int placeholderCount;

  /// 归一后的题干图数量（负数当 0）。
  final int imageCount;

  /// 快照模式：正文占位已被替换成「…」的题干；非快照：原题干。
  final String neutralizedStem;

  /// 界面标签：非快照为空串；快照是「整题截图」或「整题截图 · N 处公式/图」。
  final String labelZh;

  /// 可读正文摘录；太短（不足 4 个 runes）或没有正文时为空串。
  final String textExcerpt;

  /// [textExcerpt] 是否足够展示（非空且 >= 4 个 runes）。
  final bool hasTextExcerpt;

  /// 没有任何可展示内容（题干与摘录都为空）。
  bool get isEmpty => neutralizedStem.isEmpty && textExcerpt.isEmpty;

  @override
  String toString() => 'QuestionSnapshotSummary(isSnapshot: $isSnapshot, '
      'placeholderCount: $placeholderCount, imageCount: $imageCount, '
      'labelZh: $labelZh, textExcerpt: $textExcerpt, '
      'hasTextExcerpt: $hasTextExcerpt)';

  @override
  bool operator ==(Object other) =>
      other is QuestionSnapshotSummary &&
      other.isSnapshot == isSnapshot &&
      other.placeholderCount == placeholderCount &&
      other.imageCount == imageCount &&
      other.neutralizedStem == neutralizedStem &&
      other.labelZh == labelZh &&
      other.textExcerpt == textExcerpt &&
      other.hasTextExcerpt == hasTextExcerpt;

  @override
  int get hashCode => Object.hash(
        isSnapshot,
        placeholderCount,
        imageCount,
        neutralizedStem,
        labelZh,
        textExcerpt,
        hasTextExcerpt,
      );
}

/// 汇总一道题的题干快照信息。
///
/// [stem] 是题干正文；[stemImageCount] 是题干图数量（负数当 0）；[imageSizes]
/// 是各图像素尺寸（下标即 0-based order，缺项/`null` 表示未知）。快照判定交给
/// [planQuestionStemRender]：B1 真实尺寸够大，或 B2 1 图 + >=2 占位且没有任何
/// 已知尺寸。
///
/// 口径：
/// * [QuestionSnapshotSummary.neutralizedStem]：快照模式拼所有文字段（占位已
///   变「…」）；非快照模式原样返回 [stem]；
/// * [QuestionSnapshotSummary.labelZh]：非快照为空串；快照有占位时为
///   「整题截图 · N 处公式/图」；没有占位时为「整题截图」；
/// * [QuestionSnapshotSummary.textExcerpt]：快照模式从**原** [stem] 删掉占位
///   token，折叠空白与连续省略号、剥掉首尾标点与空白，再按 runes 截到
///   [excerptMaxLength]（超出补「…」）；截断后不足 4 个 runes 视为没有摘录，
///   置空并让 `hasTextExcerpt = false`。非快照模式直接叫 [questionStemPreview]；
/// * 空题干、负 [stemImageCount]、尺寸数组长度任意都不抛，按上述退化。
QuestionSnapshotSummary summarizeQuestionStemSnapshot({
  required String stem,
  required int stemImageCount,
  List<QuestionStemImageSize?> imageSizes = const <QuestionStemImageSize?>[],
  int excerptMaxLength = kQuestionSnapshotExcerptMaxLength,
}) {
  final QuestionStemRenderPlan plan = planQuestionStemRender(
    stem,
    imageCount: stemImageCount,
    imageSizes: imageSizes,
  );
  final bool isSnapshot = plan.isSnapshot;
  final int imageCount = plan.imageCount;

  String neutralizedStem;
  if (isSnapshot) {
    final StringBuffer buffer = StringBuffer();
    for (final segment in plan.segments) {
      if (segment.isText) {
        buffer.write(segment.text);
      }
    }
    neutralizedStem = buffer.toString();
  } else {
    neutralizedStem = stem;
  }

  final int placeholderCount = plan.placeholderCount;
  final String labelZh;
  if (!isSnapshot) {
    labelZh = '';
  } else if (placeholderCount >= 1) {
    labelZh = '整题截图 · $placeholderCount 处公式/图';
  } else {
    labelZh = '整题截图';
  }

  String textExcerpt;
  bool hasTextExcerpt;
  if (isSnapshot) {
    final String cleaned = _cleanSnapshotExcerpt(stem);
    final String truncated = _truncateByRunes(cleaned, excerptMaxLength);
    if (truncated.runes.length >= 4) {
      textExcerpt = truncated;
      hasTextExcerpt = true;
    } else {
      textExcerpt = '';
      hasTextExcerpt = false;
    }
  } else {
    textExcerpt = questionStemPreview(stem, maxLength: excerptMaxLength);
    hasTextExcerpt = textExcerpt.isNotEmpty;
  }

  return QuestionSnapshotSummary(
    isSnapshot: isSnapshot,
    placeholderCount: placeholderCount,
    imageCount: imageCount,
    neutralizedStem: neutralizedStem,
    labelZh: labelZh,
    textExcerpt: textExcerpt,
    hasTextExcerpt: hasTextExcerpt,
  );
}

/// 快照摘录清洗：删占位 → 折叠空白 → 压缩连续省略号 → 剥首尾标点/空白。
String _cleanSnapshotExcerpt(String stem) {
  var text = stem.replaceAll(_snapshotPlaceholderPattern, '');
  text = text.replaceAll(_whitespaceRunPattern, ' ');
  text = text.replaceAll(_ellipsisRunPattern, '…');
  return _trimExcerptEdges(text);
}

/// 剥掉首尾的标点（[_excerptEdgePunctuation]）与半角空格。
String _trimExcerptEdges(String text) {
  var start = 0;
  var end = text.length;
  while (start < end && _isExcerptEdgeChar(text[start])) {
    start++;
  }
  while (end > start && _isExcerptEdgeChar(text[end - 1])) {
    end--;
  }
  return text.substring(start, end);
}

bool _isExcerptEdgeChar(String char) =>
    char == ' ' || _excerptEdgePunctuation.contains(char);

/// 按 runes 截断；超出补一个「…」；[maxLength] <= 0 或空串返回空串。
String _truncateByRunes(String text, int maxLength) {
  if (maxLength <= 0 || text.isEmpty) {
    return '';
  }
  final List<int> runes = text.runes.toList(growable: false);
  if (runes.length <= maxLength) {
    return text;
  }
  return '${String.fromCharCodes(runes.take(maxLength))}…';
}

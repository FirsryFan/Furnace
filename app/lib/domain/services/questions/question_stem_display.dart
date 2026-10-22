/// 题干的一行显示文本（纯逻辑，不 import Flutter / dart:io）。
///
/// 题库列表、组卷候选、相似题这些地方手里只有题干字符串，却要把「［图N］」
/// 占位与整卡快照题收成一行。口径分散在各页面很容易做歪：有的把占位原样
/// 吐出来，有的把整卡快照题的正文画到列表里。本文件把它收口成一个纯函数：
///
/// * 快照题（整卡截图）交给 [summarizeQuestionStemSnapshot]，**不传图片
///   尺寸**——列表不读图片字节，只靠 B2「1 图 + >=2 占位且无尺寸」数量兜底；
///   有正文摘录就用摘录，没有就用「整题截图」标签兜底；
/// * 普通题交给 [questionStemPreview]，占位统一成「［图］」、公式去定界符、
///   按 runes 截断；
/// * 不抛异常、结果确定、不改题干本身（收尾清洗都在被调函数里）。
library;

import 'question_snapshot_summary.dart';
import 'question_stem_preview.dart';

/// 列表一行文本的解析结果（不可变值对象）。
///
/// 由 [resolveQuestionStemDisplay] 生成。
class QuestionStemDisplay {
  const QuestionStemDisplay({
    required this.text,
    required this.label,
    required this.isSnapshot,
    required this.hasExcerpt,
    required this.imageCount,
    required this.placeholderCount,
  });

  /// 列表要显示的那一行：
  ///
  /// * 快照题有正文摘录时是摘录；没有摘录时退回 [label]；
  /// * 普通题是 [questionStemPreview] 的结果；
  /// * 题干为空或全空白时是空串。
  final String text;

  /// 快照标签（「整题截图」/「整题截图 · N 处公式/图」）；普通题为空串。
  final String label;

  /// 这题的题干图是不是「整题截图」。
  final bool isSnapshot;

  /// 快照题是否有可用的正文摘录（普通题恒为 false）。
  final bool hasExcerpt;

  /// 归一后的题干图数量（负数当 0）。
  final int imageCount;

  /// 题干里「［图N］」占位出现的总次数（与显示模式无关，含越界 N）。
  final int placeholderCount;

  /// 没有任何可显示内容（[text] 去掉首尾空白后为空）。
  bool get isEmpty => text.trim().isEmpty;

  @override
  String toString() => 'QuestionStemDisplay(text: $text, label: $label, '
      'isSnapshot: $isSnapshot, hasExcerpt: $hasExcerpt, '
      'imageCount: $imageCount, placeholderCount: $placeholderCount)';

  @override
  bool operator ==(Object other) =>
      other is QuestionStemDisplay &&
      other.text == text &&
      other.label == label &&
      other.isSnapshot == isSnapshot &&
      other.hasExcerpt == hasExcerpt &&
      other.imageCount == imageCount &&
      other.placeholderCount == placeholderCount;

  @override
  int get hashCode => Object.hash(
        text,
        label,
        isSnapshot,
        hasExcerpt,
        imageCount,
        placeholderCount,
      );
}

/// 把题干解析成列表要显示的一行文本。
///
/// [stem] 是题干正文；[imageCount] 是题干图数量（负数当 0）；[maxLength]
/// 是一行文本的目标长度（runes，默认与 [questionStemPreview] 一致）。
///
/// 口径：
/// 1. 内部调 `summarizeQuestionStemSnapshot(stem: stem, stemImageCount:
///    imageCount, excerptMaxLength: maxLength)`，不传 `imageSizes`；
/// 2. 快照题：`isSnapshot = true`、`label = summary.labelZh`、
///    `hasExcerpt = summary.hasTextExcerpt`、`text` 有摘录用摘录，否则用
///    [label]（纯占位题不会在列表里留下半行省略号）；
/// 3. 普通题：`isSnapshot = false`、`label = ''`、`hasExcerpt = false`、
///    `text = questionStemPreview(stem, maxLength: maxLength)`；
/// 4. 题干为空或全空白时 `text = ''`（普通题 preview 自然给空串；快照题
///    没有占位也就不可能走 B2 快照）；
/// 5. [QuestionStemDisplay.imageCount] / [QuestionStemDisplay.placeholderCount]
///    直接用 summarize 的归一结果。
QuestionStemDisplay resolveQuestionStemDisplay({
  required String stem,
  required int imageCount,
  int maxLength = kQuestionStemPreviewMaxLength,
}) {
  final QuestionSnapshotSummary summary = summarizeQuestionStemSnapshot(
    stem: stem,
    stemImageCount: imageCount,
    excerptMaxLength: maxLength,
  );
  if (summary.isSnapshot) {
    return QuestionStemDisplay(
      text: summary.hasTextExcerpt ? summary.textExcerpt : summary.labelZh,
      label: summary.labelZh,
      isSnapshot: true,
      hasExcerpt: summary.hasTextExcerpt,
      imageCount: summary.imageCount,
      placeholderCount: summary.placeholderCount,
    );
  }
  return QuestionStemDisplay(
    text: questionStemPreview(stem, maxLength: maxLength),
    label: '',
    isSnapshot: false,
    hasExcerpt: false,
    imageCount: summary.imageCount,
    placeholderCount: summary.placeholderCount,
  );
}

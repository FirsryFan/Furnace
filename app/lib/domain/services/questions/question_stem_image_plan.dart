/// 题干图片的渲染计划（纯逻辑，不碰 Flutter / dart:io）。
///
/// 抓题包常把「整题截图」挂在题上（实测一张 PNG 1640x808 就是整道题），题干
/// 里却留着「［图1］…［图44］」这类占位（原网页公式/内联图的位置）。若照
/// [splitQuestionStemImages] 直接把整题截图插进第一个占位，正文中间会冒出一
/// 张巨图、其余占位仍是裸标记。这个文件把「图该怎么摆」抽成可测的决策：
///
/// * [QuestionStemImageMode.none]：没有题干图，题干原样一个文字段；
/// * [QuestionStemImageMode.inline]：图是正文内联图，按占位插到文字之间，没
///   被任何占位引用的图追加到正文末尾；
/// * [QuestionStemImageMode.snapshot]：整卡快照（尺寸够大，或 1 图 + 多个占位
///   却拿不到尺寸），图全部放正文末尾，正文里每个占位替换成「…」，避免整卡
///   截图出现在正文中间。
///
/// 占位正则与 `question_stem_segments.dart` 里的私有实现逐字一致（那边没有
/// 导出，只能照抄一份；改一处必须同步另一处）。本文件不抛异常、结果确定、
/// 返回的列表不可修改。
library;

import 'question_stem_segments.dart';

/// 判定整卡快照的默认最小宽度（像素）。
const int defaultStemSnapshotMinWidth = 1000;

/// 判定整卡快照的默认最小高度（像素）。
const int defaultStemSnapshotMinHeight = 400;

/// 题干图片的渲染方式。
enum QuestionStemImageMode {
  /// 没有题干图（`imageCount <= 0`），题干原样显示。
  none,

  /// 图是正文内联图：按占位插进文字之间。
  inline,

  /// 整卡快照：图放正文末尾，正文占位中性化成「…」。
  snapshot,
}

/// 一张题干图的像素尺寸。
class QuestionStemImageSize {
  const QuestionStemImageSize(this.width, this.height);

  /// 宽（像素）。
  final int width;

  /// 高（像素）。
  final int height;

  @override
  String toString() => 'QuestionStemImageSize($width x $height)';

  @override
  bool operator ==(Object other) =>
      other is QuestionStemImageSize &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}

/// 一道题题干的一次渲染决策（不可变值对象）。
///
/// 由 [planQuestionStemRender] 生成。[segments] 是正文流（文字段/图片段按
/// 顺序排），[trailingImageOrders] 是接在正文末尾显示的大图下标（0-based、
/// 升序），[snapshotImageOrders] 是被判成整卡快照的图下标。三个列表都是
/// 不可修改副本。
class QuestionStemRenderPlan {
  QuestionStemRenderPlan({
    required this.mode,
    required List<QuestionStemSegment> segments,
    required List<int> trailingImageOrders,
    required List<int> snapshotImageOrders,
    required this.imageCount,
    required this.placeholderCount,
    required this.referencedImageCount,
    required this.neutralizedPlaceholderCount,
  })  : segments = List<QuestionStemSegment>.unmodifiable(segments),
        trailingImageOrders = List<int>.unmodifiable(trailingImageOrders),
        snapshotImageOrders = List<int>.unmodifiable(snapshotImageOrders);

  /// 渲染模式。
  final QuestionStemImageMode mode;

  /// 正文流。inline 模式是文字/图片混排；snapshot 模式只有文字段。
  final List<QuestionStemSegment> segments;

  /// 接在正文末尾显示的大图下标（0-based、升序）。
  final List<int> trailingImageOrders;

  /// 被判成整卡快照的图下标（0-based、升序）；非 snapshot 模式为空。
  final List<int> snapshotImageOrders;

  /// 归一后的题干图数量（负数当 0）。
  final int imageCount;

  /// 题干里「［图N］」占位出现的总次数（含越界/非法 N）。
  final int placeholderCount;

  /// 有效占位引用到的不同图片数（inline 模式；其余模式为 0）。
  final int referencedImageCount;

  /// 被中性化成「…」的占位次数。
  final int neutralizedPlaceholderCount;

  /// 题干是否真的有图（按归一后的 [imageCount] 判断）。
  bool get hasImages => imageCount > 0;

  /// 是不是整卡快照模式。
  bool get isSnapshot => mode == QuestionStemImageMode.snapshot;

  /// 有没有要追加到正文末尾的图。
  bool get hasTrailingImages => trailingImageOrders.isNotEmpty;

  /// 有没有占位被中性化成「…」。
  bool get hasNeutralizedPlaceholders => neutralizedPlaceholderCount > 0;

  @override
  String toString() => 'QuestionStemRenderPlan(mode: ${mode.name}, '
      'segments: ${segments.length}, trailing: $trailingImageOrders, '
      'snapshot: $snapshotImageOrders, images: $imageCount, '
      'placeholders: $placeholderCount, referenced: $referencedImageCount, '
      'neutralized: $neutralizedPlaceholderCount)';

  @override
  bool operator ==(Object other) =>
      other is QuestionStemRenderPlan &&
      other.mode == mode &&
      other.imageCount == imageCount &&
      other.placeholderCount == placeholderCount &&
      other.referencedImageCount == referencedImageCount &&
      other.neutralizedPlaceholderCount == neutralizedPlaceholderCount &&
      _listEquals(other.segments, segments) &&
      _listEquals(other.trailingImageOrders, trailingImageOrders) &&
      _listEquals(other.snapshotImageOrders, snapshotImageOrders);

  @override
  int get hashCode => Object.hash(
        mode,
        imageCount,
        placeholderCount,
        referencedImageCount,
        neutralizedPlaceholderCount,
        Object.hashAll(segments),
        Object.hashAll(trailingImageOrders),
        Object.hashAll(snapshotImageOrders),
      );
}

/// 占位：全角/半角方括号或【】包住的「图」+ 1~3 位数字（全角数字也认）。
///
/// 与 `question_stem_segments.dart` 的 `_placeholderPattern` 逐字一致；那边
/// 是私有的，这里按契约照抄一份。
final RegExp _placeholderPattern = RegExp(
  r'[［\[【]\s*图\s*([0-9０-９]{1,3})\s*[］\]】]',
);

/// 规划一道题的题干图片怎么摆。
///
/// [stem] 是题干正文；[imageCount] 是题干图数量；[imageSizes] 是各图的像素
/// 尺寸（下标即 0-based order，缺项或 `null` 表示不知道尺寸，尺寸为 0 或负数
/// 视为不满足阈值）。[snapshotMinWidth] / [snapshotMinHeight] 是整卡快照的
/// 最小宽高，按原样比较不夹取（传 <= 0 等于不设下限）。
///
/// 判定（按顺序）：
///
/// * A. `imageCount <= 0` → [QuestionStemImageMode.none]：题干原样一个文字段，
///   占位不改写，`neutralizedPlaceholderCount == 0`；
/// * B. 整卡快照 → [QuestionStemImageMode.snapshot]：
///   * B1. 存在 order < imageCount 的已知尺寸，宽 >= 阈值且高 >= 阈值；
///   * B2. 所有尺寸都未知（没传、或每个都是 `null`）且 `imageCount == 1` 且
///     占位 >= 2（没有像素尺寸时的数量兜底）。
///   snapshot 行为：`trailingImageOrders` = `0..imageCount-1` 全部；
///   `snapshotImageOrders` = B1 命中的 order（B2 时 `[0]`）；`segments` 只有
///   文字——题干里每个占位替换成一个「…」、相邻文字合并、不 trim；
///   `neutralizedPlaceholderCount == placeholderCount`；
/// * C. 其余 → [QuestionStemImageMode.inline]：交给 [splitQuestionStemImages]
///   按占位内联；越界占位（N < 1 或 N > imageCount）的原文替换成「…」并计入
///   `neutralizedPlaceholderCount`；没被任何占位引用的图进
///   `trailingImageOrders`；`snapshotImageOrders` 为空。
///
/// 空题干不抛：none 模式仍返回一个空文字段；inline/snapshot 模式没有文字可
/// 显示，`segments` 为空。
QuestionStemRenderPlan planQuestionStemRender(
  String stem, {
  required int imageCount,
  List<QuestionStemImageSize?> imageSizes = const <QuestionStemImageSize?>[],
  int snapshotMinWidth = defaultStemSnapshotMinWidth,
  int snapshotMinHeight = defaultStemSnapshotMinHeight,
}) {
  final int count = imageCount < 0 ? 0 : imageCount;
  final int placeholderCount = _placeholderPattern.allMatches(stem).length;

  if (count == 0) {
    return QuestionStemRenderPlan(
      mode: QuestionStemImageMode.none,
      segments: <QuestionStemSegment>[QuestionStemSegment.text(stem)],
      trailingImageOrders: const <int>[],
      snapshotImageOrders: const <int>[],
      imageCount: 0,
      placeholderCount: placeholderCount,
      referencedImageCount: 0,
      neutralizedPlaceholderCount: 0,
    );
  }

  final List<int> oversizedOrders = <int>[];
  var allSizesMissing = true;
  for (var order = 0; order < imageSizes.length; order++) {
    final QuestionStemImageSize? size = imageSizes[order];
    if (size == null) {
      continue;
    }
    allSizesMissing = false;
    if (order < count &&
        size.width >= snapshotMinWidth &&
        size.height >= snapshotMinHeight) {
      oversizedOrders.add(order);
    }
  }

  final bool isSnapshot = oversizedOrders.isNotEmpty ||
      (allSizesMissing && count == 1 && placeholderCount >= 2);

  if (isSnapshot) {
    final List<int> snapshotOrders =
        oversizedOrders.isNotEmpty ? oversizedOrders : const <int>[0];
    return QuestionStemRenderPlan(
      mode: QuestionStemImageMode.snapshot,
      segments: _neutralizedTextSegments(stem),
      trailingImageOrders: List<int>.generate(count, (index) => index),
      snapshotImageOrders: snapshotOrders,
      imageCount: count,
      placeholderCount: placeholderCount,
      referencedImageCount: 0,
      neutralizedPlaceholderCount: placeholderCount,
    );
  }

  final QuestionStemLayout layout = splitQuestionStemImages(
    stem,
    imageCount: count,
  );
  final List<QuestionStemSegment> segments = <QuestionStemSegment>[];
  var neutralized = 0;
  for (final QuestionStemSegment segment in layout.segments) {
    if (segment.isImage) {
      segments.add(segment);
      continue;
    }
    final (String text, int replaced) = _neutralizeOutOfRange(
      segment.text,
      count,
    );
    neutralized += replaced;
    segments.add(QuestionStemSegment.text(text));
  }

  return QuestionStemRenderPlan(
    mode: QuestionStemImageMode.inline,
    segments: segments,
    trailingImageOrders: layout.unplacedImageOrders,
    snapshotImageOrders: const <int>[],
    imageCount: count,
    placeholderCount: placeholderCount,
    referencedImageCount: layout.referencedImageCount,
    neutralizedPlaceholderCount: neutralized,
  );
}

/// 把题干里每个占位替换成「…」，返回单个文字段（空题干返回空列表）。
List<QuestionStemSegment> _neutralizedTextSegments(String stem) {
  final StringBuffer buffer = StringBuffer();
  var cursor = 0;
  for (final RegExpMatch match in _placeholderPattern.allMatches(stem)) {
    buffer.write(stem.substring(cursor, match.start));
    buffer.write('…');
    cursor = match.end;
  }
  buffer.write(stem.substring(cursor));
  final String text = buffer.toString();
  if (text.isEmpty) {
    return const <QuestionStemSegment>[];
  }
  return <QuestionStemSegment>[QuestionStemSegment.text(text)];
}

/// 把越界占位（N < 1 或 N > [imageCount]）替换成「…」，返回新文字与被替换次数。
(String, int) _neutralizeOutOfRange(String text, int imageCount) {
  final StringBuffer buffer = StringBuffer();
  var cursor = 0;
  var replaced = 0;
  for (final RegExpMatch match in _placeholderPattern.allMatches(text)) {
    final int? value = _digitValue(match.group(1)!);
    final int? order = value == null ? null : value - 1;
    if (order != null && order >= 0 && order < imageCount) {
      continue;
    }
    buffer.write(text.substring(cursor, match.start));
    buffer.write('…');
    cursor = match.end;
    replaced++;
  }
  if (replaced == 0) {
    return (text, 0);
  }
  buffer.write(text.substring(cursor));
  return (buffer.toString(), replaced);
}

/// 全角数字也认；返回 null 表示不是合法数字（与 segments 文件同一实现）。
int? _digitValue(String raw) {
  var value = 0;
  for (final rune in raw.runes) {
    final digit = switch (rune) {
      >= 0x30 && <= 0x39 => rune - 0x30,
      >= 0xFF10 && <= 0xFF19 => rune - 0xFF10,
      _ => null,
    };
    if (digit == null) {
      return null;
    }
    value = value * 10 + digit;
  }
  return value;
}

/// 列表逐项相等（值语义，不依赖 Flutter 的 listEquals）。
bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

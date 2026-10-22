/// 题干里的图片占位切分（纯逻辑，不碰 Flutter / dart:io）。
///
/// 抓题管线把图片位置写成「［图1］［图2］」这样的占位（`tqb.mjs` 的
/// `runsToPlainText` 就是 img → 「［图N］」），导入后题干的文字里就留着这些
/// 标记，图片本身在 attachments 表里按 role/sortOrder 排。界面要「图文混排」
/// 就得知道每张图应该插在哪一段文字后面——这份逻辑只做这件事：把题干切成
/// 文字段与图片段，把「没被任何占位引用的图」单独列出来让调用方追加到末尾。
///
/// 口径：
/// * 占位接受全角/半角方括号与【】：「［图1］」「[图 1]」「【图1】」都认；
/// * N 从 1 开始，对应该题第 N 张题干图（返回 0-based [QuestionStemSegment.imageOrder]）；
/// * 越界（N > imageCount，或 N = 0）时**原文保留**，不吞字；同一个 N 出现多次时每处都按同一张图渲染，但只计一次引用；
/// * imageCount <= 0 时整段题干原样返回（没有图可用，占位符就是文字）；
/// * 不 trim、不改写文字，只把相邻文字段合并。
library;

/// 一个题干片段的类型。
enum QuestionStemSegmentKind {
  /// 普通文字（含没被识别的占位原文）。
  text,

  /// 一张题干图，位置在 [QuestionStemSegment.imageOrder].
  image,
}

/// 题干切分后的一个片段。
class QuestionStemSegment {
  /// 文字段。
  const QuestionStemSegment.text(this.text)
      : kind = QuestionStemSegmentKind.text,
        imageOrder = null;

  /// 图片段；[imageOrder] 是该题题干图列表的 0-based 下标。
  const QuestionStemSegment.image(this.imageOrder)
      : kind = QuestionStemSegmentKind.image,
        text = '';

  final QuestionStemSegmentKind kind;

  /// 文字段的内容；图片段是空串。
  final String text;

  /// 图片段在题干图列表里的下标；文字段是 null。
  final int? imageOrder;

  bool get isText => kind == QuestionStemSegmentKind.text;

  bool get isImage => kind == QuestionStemSegmentKind.image;

  @override
  String toString() => isImage
      ? 'QuestionStemSegment.image($imageOrder)'
      : 'QuestionStemSegment.text($text)';

  @override
  bool operator ==(Object other) =>
      other is QuestionStemSegment &&
      other.kind == kind &&
      other.text == text &&
      other.imageOrder == imageOrder;

  @override
  int get hashCode => Object.hash(kind, text, imageOrder);
}

/// 切分结果。
class QuestionStemLayout {
  const QuestionStemLayout({
    required this.segments,
    required this.unplacedImageOrders,
    required this.referencedImageCount,
  });

  /// 按题干顺序排列的文字/图片片段。
  final List<QuestionStemSegment> segments;

  /// 没被任何占位引用的题干图下标（升序），调用方应把它们追加到题干末尾。
  final List<int> unplacedImageOrders;

  /// 被占位引用到的不同图片数（同一 N 出现两次只算一张）。
  final int referencedImageCount;

  bool get isEmpty => segments.isEmpty && unplacedImageOrders.isEmpty;

  /// 题干里有没有图片（被引用或未引用都算）。
  bool get hasImages =>
      referencedImageCount > 0 || unplacedImageOrders.isNotEmpty;

  /// 有没有「没被占位引用、需要追加到末尾」的图。
  bool get hasUnplacedImages => unplacedImageOrders.isNotEmpty;
}

/// 占位：全角/半角方括号或【】包住的「图」+ 1~3 位数字。
final RegExp _placeholderPattern = RegExp(
  r'[［\[【]\s*图\s*([0-9０-９]{1,3})\s*[］\]】]',
);

/// 把题干按图片占位切成文字段与图片段。
///
/// [imageCount] 是这道题**题干图**的数量（role 为 null 或 'stem'）。
QuestionStemLayout splitQuestionStemImages(
  String stem, {
  required int imageCount,
}) {
  final count = imageCount < 0 ? 0 : imageCount;
  if (stem.isEmpty || count == 0) {
    return QuestionStemLayout(
      segments: stem.isEmpty
          ? const <QuestionStemSegment>[]
          : <QuestionStemSegment>[QuestionStemSegment.text(stem)],
      unplacedImageOrders: count == 0
          ? const <int>[]
          : List<int>.unmodifiable(List<int>.generate(count, (i) => i)),
      referencedImageCount: 0,
    );
  }

  final segments = <QuestionStemSegment>[];
  final referenced = <int>{};
  final text = StringBuffer();

  void flushText() {
    if (text.isEmpty) {
      return;
    }
    segments.add(QuestionStemSegment.text(text.toString()));
    text.clear();
  }

  var cursor = 0;
  for (final match in _placeholderPattern.allMatches(stem)) {
    final value = _digitValue(match.group(1)!);
    final order = value == null ? null : value - 1;
    final placeable = order != null && order >= 0 && order < count;
    if (!placeable) {
      // 越界或者根本不是数字：占位原文留在文字里，不吞字。
      text.write(stem.substring(cursor, match.end));
      cursor = match.end;
      continue;
    }
    text.write(stem.substring(cursor, match.start));
    flushText();
    segments.add(QuestionStemSegment.image(order));
    referenced.add(order);
    cursor = match.end;
  }
  text.write(stem.substring(cursor));
  flushText();

  final unplaced = <int>[
    for (var i = 0; i < count; i++)
      if (!referenced.contains(i)) i,
  ];

  return QuestionStemLayout(
    segments: List<QuestionStemSegment>.unmodifiable(segments),
    unplacedImageOrders: List<int>.unmodifiable(unplaced),
    referencedImageCount: referenced.length,
  );
}

/// 全角数字也认；返回 null 表示不是合法数字。
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

/// 把片段摊平成纯文字（调试/摘要用；图片段记为空，图片位置信息不丢在
/// [QuestionStemLayout] 里）。
String questionStemPlainText(QuestionStemLayout layout) => layout.segments
    .where((segment) => segment.isText)
    .map((s) => s.text)
    .join();

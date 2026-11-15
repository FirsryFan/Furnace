/// 题干「［图N］」占位与统一 Markdown 渲染器之间的桥（纯逻辑，不碰 Flutter）。
///
/// 抓题管线把公式/图片的位置写成 `［图1］…［图N］`，图片本身在 attachments 表里
/// 按顺序排。详情页原来的做法是把题干切成「文字段 / 图片段」再竖着摆（图片各占
/// 一整行），公式多一点的题（化学 Q15 有 18 处公式图）就会变成一列大图 + 碎文字。
///
/// 这里把占位翻成 Markdown 图片语法 `![x24](question-image:3)`，交给共享
/// `MarkdownRenderer`（gpt_markdown 的图片是**行内 widget span**）排版：
///
///  * 公式图与文字回到同一行，题干读起来是一句话，而不是一列图；
///  * 高度写进 alt（`x<height>`，gpt_markdown 的 `WxH` 尺寸约定），渲染器按
///    需要缩放；不写高度时由渲染层按图片像素尺寸决定；
///  * **独立成行**的占位（前后都是换行/行首行尾）视为插图，渲染层按原尺寸显示；
///    行内占位视为行内公式，按正文比例缩放；比行高高得多的行内公式（分式）会
///    被单独成段，避免整行被撑高、文字掉到图片下面；
///  * 越界占位（N < 1 或 N > 图片数）保持原文，不吞字、不改写其他文字。
library;

/// 一个题干图片占位的解析结果。
class QuestionImagePlaceholder {
  const QuestionImagePlaceholder({
    required this.order,
    required this.start,
    required this.end,
    required this.ownLine,
  });

  /// 0-based 图片下标（`［图1］` → 0）。
  final int order;

  /// 占位在原文里的起止偏移（`[start, end)`）。
  final int start;
  final int end;

  /// 这个占位是不是独立成行（前后只有空白或换行）。
  final bool ownLine;

  @override
  String toString() =>
      'QuestionImagePlaceholder(order: $order, ownLine: $ownLine, '
      'start: $start, end: $end)';

  @override
  bool operator ==(Object other) =>
      other is QuestionImagePlaceholder &&
      other.order == order &&
      other.start == start &&
      other.end == end &&
      other.ownLine == ownLine;

  @override
  int get hashCode => Object.hash(order, start, end, ownLine);
}

/// 一次转换的结果。
class QuestionImageMarkup {
  const QuestionImageMarkup({
    required this.markdown,
    required this.placeholders,
  });

  /// 把有效占位换成 Markdown 图片语法后的文本。
  final String markdown;

  /// 文本里所有**有效**占位（按出现顺序）。
  final List<QuestionImagePlaceholder> placeholders;

  bool get hasImages => placeholders.isNotEmpty;
}

/// 题干图片占位：全角/半角方括号或【】包住的「图」+ 1~3 位数字。
final RegExp _placeholderPattern = RegExp(
  r'[［\[【]\s*图\s*([0-9０-９]{1,3})\s*[］\]】]',
);

/// 解析所有有效占位（不修改文本）。
List<QuestionImagePlaceholder> parseQuestionImagePlaceholders(
  String text, {
  required int imageCount,
}) {
  return _scan(text, imageCount).placeholders;
}

/// 把 `［图N］` 换成 `![x<height>](question-image:N)`。
///
/// [heightOf] 给某个占位决定显示高度（逻辑像素）；返回 null 时不写高度，由
/// 渲染层按图片像素尺寸决定。越界占位不动。
///
/// [blockAboveHeight]：显示高度超过这个值的公式图**单独成段**。渲染器里的
/// 图片是行内 widget（底部对齐），一张比行高高得多的公式（分式 60px 上下）留在
/// 行内会把整行撑高、行内文字掉到图片下面，读起来像"顺序错了"；单独成段后
/// 顺序仍然是原文顺序，只是公式自己占一行。
QuestionImageMarkup questionMarkdownWithImagePlaceholders(
  String text, {
  required int imageCount,
  double? Function(QuestionImagePlaceholder placeholder)? heightOf,
  double blockAboveHeight = 40,
}) {
  final scan = _scan(text, imageCount);
  if (scan.placeholders.isEmpty) {
    return QuestionImageMarkup(markdown: text, placeholders: const []);
  }
  final buffer = StringBuffer();
  var cursor = 0;
  final ordered = <QuestionImagePlaceholder>[];
  for (final placeholder in scan.placeholders) {
    buffer.write(text.substring(cursor, placeholder.start));
    final height = heightOf?.call(placeholder);
    final alt = height == null || !height.isFinite || height <= 0
        ? '图'
        : 'x${height.round()}';
    final markup = '![$alt](question-image:${placeholder.order + 1})';
    final isBlock = height != null && height.isFinite && height > blockAboveHeight;
    if (isBlock) {
      buffer.write('\n\n$markup\n\n');
    } else {
      buffer.write(markup);
    }
    cursor = placeholder.end;
    ordered.add(placeholder);
  }
  buffer.write(text.substring(cursor));
  return QuestionImageMarkup(markdown: buffer.toString(), placeholders: ordered);
}

/// 解析 `![…](question-image:N)` 里的图片下标（0-based）；不是这种 url 返回 null。
int? questionImageOrderFromUrl(String url) {
  const prefix = 'question-image:';
  if (!url.startsWith(prefix)) {
    return null;
  }
  final value = int.tryParse(url.substring(prefix.length).trim());
  if (value == null || value < 1) {
    return null;
  }
  return value - 1;
}

({String text, List<QuestionImagePlaceholder> placeholders}) _scan(
  String text,
  int imageCount,
) {
  if (text.isEmpty || imageCount <= 0) {
    return (text: text, placeholders: const <QuestionImagePlaceholder>[]);
  }
  final placeholders = <QuestionImagePlaceholder>[];
  for (final match in _placeholderPattern.allMatches(text)) {
    final value = _digitValue(match.group(1)!);
    final order = value == null ? null : value - 1;
    if (order == null || order < 0 || order >= imageCount) {
      // 越界/非法：保持原文，不吞字。
      continue;
    }
    placeholders.add(
      QuestionImagePlaceholder(
        order: order,
        start: match.start,
        end: match.end,
        ownLine: _isOwnLine(text, match.start, match.end),
      ),
    );
  }
  return (text: text, placeholders: placeholders);
}

/// 占位前后是不是只有空白（或行首行尾）。
bool _isOwnLine(String text, int start, int end) {
  var before = start - 1;
  while (before >= 0 && (text[before] == ' ' || text[before] == '\t')) {
    before--;
  }
  if (before >= 0 && text[before] != '\n' && text[before] != '\r') {
    return false;
  }
  var after = end;
  while (after < text.length && (text[after] == ' ' || text[after] == '\t')) {
    after++;
  }
  if (after < text.length && text[after] != '\n' && text[after] != '\r') {
    return false;
  }
  return true;
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

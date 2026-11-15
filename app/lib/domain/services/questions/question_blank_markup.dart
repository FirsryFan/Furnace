/// 题干里的「填空空位」识别与渲染标记（纯逻辑，不碰 Flutter）。
///
/// 题面数据里填空是连续下划线（`______`、`____`）。**不能**把它当 Markdown
/// 文本交给渲染器（会被当强调/分隔线吃掉），也不应该只转义成字符（观感是一条
/// 细字符线、字号/主题不跟手）。这里统一成「空位」语义：
///
///  * 识别：**3 个及以上连续下划线**算一个空位（与 `cloze_layout.dart` /
///    `review_service._renderBlank` 的 `_{3,}` 同口径）；公式（`$…$`、`$$…$$`、
///    `\(…\)`、`\[…\]`）里的 `_` 是 LaTeX 下标、代码栅栏/行内代码里的 `_` 是
///    代码，都不算空位；
///  * Markdown 路径：把空位换成 `![宽x高](question-blank:N)`（N=下划线个数），
///    由题目渲染层用 `imageBuilder` 画成**真正的空白下划线组件**（固定高度的
///    底线，深色主题也可见，随文字行高走）；
///  * 纯文本路径：直接给出 [QuestionBlankSpan] 列表，调用方用 WidgetSpan 排版。
///
/// 不新造空位：没有下划线的题一个字都不改。
library;

/// 一个空位最少要几个连续下划线（与填空/闪存卡同一口径）。
const int questionBlankMinUnderscores = 3;

/// Markdown 里空位用的 URL scheme；后面跟下划线个数。
const String questionBlankUrlScheme = 'question-blank:';

/// 纯文本路径里的一个空位（`[start, end)` 是原文偏移）。
class QuestionBlankSpan {
  const QuestionBlankSpan({
    required this.start,
    required this.end,
    required this.underscores,
  });

  final int start;
  final int end;

  /// 原文里连续下划线的个数（决定空位显示多宽）。
  final int underscores;

  @override
  String toString() =>
      'QuestionBlankSpan($start..$end, ${underscores}x_)';

  @override
  bool operator ==(Object other) =>
      other is QuestionBlankSpan &&
      other.start == start &&
      other.end == end &&
      other.underscores == underscores;

  @override
  int get hashCode => Object.hash(start, end, underscores);
}

final RegExp _blankPattern = RegExp(r'_{3,}');

/// 文本里有没有「空位」（3+ 连续下划线，公式/代码里的不算）。
bool questionTextHasBlanks(String text) => parseQuestionBlanks(text).isNotEmpty;

/// 解析纯文本里的所有空位（按 [start] 升序；公式/代码里的不算）。
///
/// 纯文本路径不认代码栅栏（原文就是数据）；公式区域会跳过。
List<QuestionBlankSpan> parseQuestionBlanks(String text) {
  if (!text.contains('_')) {
    return const <QuestionBlankSpan>[];
  }
  final blanks = <QuestionBlankSpan>[];
  var cursor = 0;
  for (final range in _mathRanges(text)) {
    _collectBlanks(text.substring(cursor, range.start), cursor, blanks);
    cursor = range.end;
  }
  _collectBlanks(text.substring(cursor), cursor, blanks);
  return blanks;
}

void _collectBlanks(
  String segment,
  int offset,
  List<QuestionBlankSpan> out,
) {
  for (final match in _blankPattern.allMatches(segment)) {
    // 已经是 `\_\_\_`（人工转义）的不算空位：保留原意。
    if (match.start > 0 && segment[match.start - 1] == r'\') {
      continue;
    }
    out.add(
      QuestionBlankSpan(
        start: offset + match.start,
        end: offset + match.end,
        underscores: match.end - match.start,
      ),
    );
  }
}

/// 把 Markdown 题面里的空位换成渲染器认得的图片语法
/// `![宽x高](question-blank:N)`。
///
/// [fontSize] 用来估算空位的显示宽度/高度（渲染层按 alt 里的像素值画底线）：
/// 宽度随下划线个数增长（`0.5em`/个，最少 `2.2em`，最多 `10em`），高度取
/// `1.25em`（够放一条贴底的线，又不会把行距撑得很夸张）。
String questionMarkdownWithBlankWidgets(
  String markdown, {
  double fontSize = 16,
}) {
  if (!markdown.contains('_')) {
    return markdown;
  }
  final buffer = StringBuffer();
  final lines = markdown.split('\n');
  var inFence = false;
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final trimmed = line.trimLeft();
    final isFence = trimmed.startsWith('```') || trimmed.startsWith('~~~');
    if (isFence) {
      inFence = !inFence;
      buffer.write(line);
    } else if (inFence) {
      buffer.write(line);
    } else {
      buffer.write(_embedBlanksInLine(line, fontSize));
    }
    if (index != lines.length - 1) {
      buffer.write('\n');
    }
  }
  return buffer.toString();
}

/// 空位在 [fontSize] 下的显示尺寸（逻辑像素）。
///
/// 宽度随下划线个数增长（每个 `0.5em`，夹在 `2.2em`–`10em`），高度 `1.25em`；
/// Markdown 路径与纯文本路径共用这一份，空位宽度不会因为渲染入口不同而变。
({double width, double height}) questionBlankDisplaySize(
  int underscores,
  double fontSize,
) {
  final width = (underscores * fontSize * 0.5)
      .clamp(fontSize * 2.2, fontSize * 10)
      .toDouble();
  return (width: width, height: fontSize * 1.25);
}

String _embedBlanksInLine(String line, double fontSize) {
  if (!_blankPattern.hasMatch(line)) {
    return line;
  }
  final buffer = StringBuffer();
  var cursor = 0;
  for (final range in _mathRanges(line)) {
    _writeWithBlanks(line, cursor, range.start, fontSize, buffer);
    buffer.write(line.substring(range.start, range.end));
    cursor = range.end;
  }
  _writeWithBlanks(line, cursor, line.length, fontSize, buffer);
  return buffer.toString();
}

void _writeWithBlanks(
  String line,
  int start,
  int end,
  double fontSize,
  StringBuffer buffer,
) {
  if (start >= end) {
    return;
  }
  final text = line.substring(start, end);
  var cursor = 0;
  for (final match in _blankPattern.allMatches(text)) {
    if (match.start > 0 && text[match.start - 1] == r'\') {
      continue;
    }
    buffer.write(text.substring(cursor, match.start));
    final count = match.end - match.start;
    final size = questionBlankDisplaySize(count, fontSize);
    buffer.write(
      '![${size.width.round()}x${size.height.round()}]'
      '($questionBlankUrlScheme$count)',
    );
    cursor = match.end;
  }
  buffer.write(text.substring(cursor));
}

/// 从 `question-blank:N` 里取下划线个数；不是空位 URL 返回 null。
int? questionBlankCountFromUrl(String url) {
  if (!url.startsWith(questionBlankUrlScheme)) {
    return null;
  }
  final value = int.tryParse(url.substring(questionBlankUrlScheme.length));
  if (value == null || value < questionBlankMinUnderscores) {
    return null;
  }
  return value;
}

/// 一行里所有公式区间的 `[start, end)`。
///
/// 认 `$…$`、`$$…$$`、`\(…\)`、`\[…\]`；没闭合的定界符按正文处理。
List<({int start, int end})> _mathRanges(String line) {
  final ranges = <({int start, int end})>[];
  var index = 0;
  while (index < line.length) {
    final char = line[index];
    if (char == r'\') {
      final next = index + 1 < line.length ? line[index + 1] : '';
      if (next == '(') {
        final close = line.indexOf(r'\)', index + 2);
        if (close >= 0) {
          ranges.add((start: index, end: close + 2));
          index = close + 2;
          continue;
        }
      } else if (next == '[') {
        final close = line.indexOf(r'\]', index + 2);
        if (close >= 0) {
          ranges.add((start: index, end: close + 2));
          index = close + 2;
          continue;
        }
      }
      index += 2;
      continue;
    }
    if (char != r'$') {
      index++;
      continue;
    }
    if (index + 1 < line.length && line[index + 1] == r'$') {
      final close = line.indexOf(r'$$', index + 2);
      if (close >= 0) {
        ranges.add((start: index, end: close + 2));
        index = close + 2;
        continue;
      }
      index += 2;
      continue;
    }
    // 单个 `$`：后面紧跟空白时是正文（价格），不构成公式。
    if (index + 1 >= line.length || _isWhitespace(line[index + 1])) {
      index++;
      continue;
    }
    final close = _closingInlineDollar(line, index + 1);
    if (close < 0) {
      index++;
      continue;
    }
    ranges.add((start: index, end: close + 1));
    index = close + 1;
  }
  return ranges;
}

/// 闭合 [from] 之前那个 `$` 的下标；找不到返回 -1。
int _closingInlineDollar(String line, int from) {
  var index = from;
  while (index < line.length) {
    if (line[index] == r'\') {
      index += 2;
      continue;
    }
    if (line[index] == r'$') {
      if (index + 1 < line.length && line[index + 1] == r'$') {
        index += 2;
        continue;
      }
      if (!_isWhitespace(line[index - 1])) {
        return index;
      }
    }
    index++;
  }
  return -1;
}

bool _isWhitespace(String char) =>
    char == ' ' || char == '\t' || char == '\n' || char == '\r';

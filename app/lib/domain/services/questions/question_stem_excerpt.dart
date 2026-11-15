/// 题库卡片上的题干摘要（纯逻辑，不碰 Flutter / dart:io）。
///
/// 题库列表改成「设置页同款卡片」后，卡片既要认出是哪道题，也要能看出题面里
/// 的公式（`$…$` 交给统一 Markdown 渲染器排真公式）。旧的一行摘要
/// [questionStemPreview] 会把公式定界符剥掉（`$x^2$` → `x^2`），适合纯文字
/// 列表；卡片要的是**还能渲染的 Markdown 片段**，所以单独一个函数：
///
///  * 去掉代码块、图片语法、表格行、标题行、来源/难度/标签这类元信息行
///    （算法竞赛题面开头那一串），只留正文；
///  * 有 `## 题目描述` 这类标题时从第一个标题之后开始取（跳过标题前的元信息）；
///  * 图片占位 `［图N］` 收成 `［图］`，读者知道这里有图；
///  * 折叠所有空白成一行，按 rune 截断；截断点落在公式/链接/强调里时退到安全
///    位置，保证交给渲染器的片段结构完整（不会把后面的文字吞进构造里）。
///
/// 返回的片段适合 `MarkdownQuestionText(markdown: true)` 渲染；空题干返回空串。
library;

/// 卡片摘要默认长度（rune）。
const int kQuestionCardStemMaxLength = 120;

/// 图片占位统一写法（与 `question_stem_preview.dart` 一致）。
const String kQuestionCardImageToken = '［图］';

final RegExp _fenceLine = RegExp(r'^[ \t]*(?:```|~~~)');
final RegExp _headingLine = RegExp(r'^[ \t]{0,6}#{1,6}[ \t]+');
final RegExp _tableLine = RegExp(r'^[ \t]*\|');
final RegExp _markdownImage = RegExp(r'!\[[^\]\n]*\]\([^)\n]*\)');
final RegExp _markdownLink = RegExp(r'\[([^\]\n]+)\]\([^)\n]*\)');
final RegExp _imagePlaceholder = RegExp(
  r'[［\[【]\s*图\s*[0-9０-９]{1,3}\s*[］\]】]',
);
final RegExp _urlOnly = RegExp(r'^(?:https?://|www\.)\S+$');
final RegExp _metaLine = RegExp(
  r'^(?:来源|题目来源|洛谷难度|算法标签|难度|标签|时间限制|内存限制|数据范围)\s*[：:]',
);
final RegExp _listMarker = RegExp(r'^[ \t]*(?:[-*+]|\d{1,3}[.)])[ \t]+');
final RegExp _quoteMarker = RegExp(r'^[ \t]*>[ \t]?');
final RegExp _displayMath = RegExp(r'\$\$([\s\S]*?)\$\$');

/// 把完整题干收成卡片可渲染的一行摘要。
String questionCardStemExcerpt(
  String stem, {
  int maxLength = kQuestionCardStemMaxLength,
}) {
  if (maxLength <= 0 || stem.trim().isEmpty) {
    return '';
  }
  final lines = _contentLines(stem);
  final collapsed = lines
      .join(' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (collapsed.isEmpty) {
    return '';
  }
  final cut = _safeCut(collapsed, maxLength);
  final trimmed = cut.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  // 只有真的截短了才加省略号：短题干原样显示，卡片上不出现莫名的「…」。
  final wasTruncated = cut.length < collapsed.length ||
      collapsed.runes.length > maxLength;
  return wasTruncated && !trimmed.endsWith('…') ? '$trimmed…' : trimmed;
}

/// 从题干里挑出值得上卡片的行。
List<String> _contentLines(String stem) {
  final raw = stem.split('\n');
  final withoutFences = <String>[];
  var inFence = false;
  for (final line in raw) {
    if (_fenceLine.hasMatch(line)) {
      inFence = !inFence;
      continue;
    }
    if (inFence) {
      continue;
    }
    withoutFences.add(line);
  }

  // 有标题时从第一个标题之后开始：标题前通常是题面元信息（洛谷来源那一串）。
  var start = 0;
  for (var index = 0; index < withoutFences.length; index++) {
    if (_headingLine.hasMatch(withoutFences[index])) {
      start = index + 1;
      break;
    }
  }

  final kept = <String>[];
  for (var index = start; index < withoutFences.length; index++) {
    var line = withoutFences[index].trim();
    if (line.isEmpty) {
      continue;
    }
    if (_headingLine.hasMatch(line) || _tableLine.hasMatch(line)) {
      continue;
    }
    if (_urlOnly.hasMatch(line) || _metaLine.hasMatch(line)) {
      continue;
    }
    line = line.replaceAll(_markdownImage, ' ');
    line = line.replaceAllMapped(
      _markdownLink,
      (match) => match.group(1) ?? '',
    );
    line = line.replaceAll(_imagePlaceholder, kQuestionCardImageToken);
    line = line.replaceAll(_listMarker, '');
    line = line.replaceAll(_quoteMarker, '');
    if (line.trim().isEmpty) {
      continue;
    }
    kept.add(line.trim());
  }
  return kept;
}

/// 从 [text] 开头截取最多 [maxLength] 个 rune，且不破坏结构。
String _safeCut(String text, int maxLength) {
  final runes = text.runes.toList(growable: false);
  if (runes.length <= maxLength) {
    return text;
  }
  var cut = String.fromCharCodes(runes.take(maxLength));
  // 落单的 `$`：退到安全位置，避免半个定界符把后面的文字吞进公式。
  cut = _fixDanglingMath(cut);
  // 截断点落在 `[文字](地址` 里：退到 `[` 之前。
  cut = _fixDanglingLink(cut);
  // 截断点落在行内代码里：退到反引号之前。
  if (_count(cut, '`').isOdd) {
    final last = cut.lastIndexOf('`');
    if (last > 0) {
      cut = cut.substring(0, last);
    }
  }
  // 落单的 `**`：去掉末尾那半个加粗标记。
  if (_count(cut, '**').isOdd) {
    final last = cut.lastIndexOf('**');
    if (last > 0) {
      cut = cut.substring(0, last);
    }
  }
  return cut;
}

/// 截断后如果 `$`（单/双）没闭合：退到开定界符之前（宁短勿吞）。
String _fixDanglingMath(String cut) {
  var index = 0;
  while (index < cut.length) {
    final char = cut[index];
    if (char == r'\') {
      index += 2;
      continue;
    }
    if (char != r'$') {
      index++;
      continue;
    }
    if (index + 1 < cut.length && cut[index + 1] == r'$') {
      final close = cut.indexOf(r'$$', index + 2);
      if (close < 0) {
        return cut.substring(0, index);
      }
      index = close + 2;
      continue;
    }
    final close = _closingInlineDollar(cut, index + 1);
    if (close < 0) {
      return cut.substring(0, index);
    }
    index = close + 1;
  }
  return cut;
}

/// 在 [cut] 里从 [from] 找闭合 `$`；找不到返回 -1。
int _closingInlineDollar(String cut, int from) {
  var index = from;
  while (index < cut.length) {
    if (cut[index] == r'\') {
      index += 2;
      continue;
    }
    if (cut[index] == r'$') {
      if (index + 1 < cut.length && cut[index + 1] == r'$') {
        index += 2;
        continue;
      }
      if (index > 0 && !_isWhitespace(cut[index - 1])) {
        return index;
      }
    }
    index++;
  }
  return -1;
}

/// `[文字](地址` 被截断时退到 `[` 之前；没有链接返回原样。
String _fixDanglingLink(String cut) {
  final lastOpen = cut.lastIndexOf('(');
  if (lastOpen < 0) {
    return cut;
  }
  final lastClose = cut.lastIndexOf(')');
  if (lastClose > lastOpen) {
    return cut;
  }
  // `(` 之后没有 `)`：如果它前面是 `](`，退到 `[` 之前。
  final bracket = cut.lastIndexOf('[', lastOpen);
  if (bracket >= 0 && lastOpen - bracket >= 2) {
    return cut.substring(0, bracket);
  }
  return cut;
}

int _count(String text, String pattern) {
  var count = 0;
  var index = 0;
  while (true) {
    final found = text.indexOf(pattern, index);
    if (found < 0) {
      return count;
    }
    count++;
    index = found + pattern.length;
  }
}

bool _isWhitespace(String char) =>
    char == ' ' || char == '\t' || char == '\n' || char == '\r';

/// 摘要里是否含有可用于渲染的公式（`$…$` / `$$…$$`）。
bool questionCardExcerptHasMath(String excerpt) =>
    _displayMath.hasMatch(excerpt) ||
    RegExp(r'\$[^$\n]+?\$').hasMatch(excerpt);

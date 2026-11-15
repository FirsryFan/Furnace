/// 题目文本交给共享 `MarkdownRenderer` 之前的预处理（纯逻辑，不碰 Flutter）。
///
/// 两件事，都是"题面是数据"带来的：
///
///  1. **公式定界符归一**：`gpt_markdown` 的 `$…$` 公式有一条价格启发式——
///     开定界符后面是数字时，闭合 `$` 必须出现在第一个空白之前（为了不把
///     「价格 $5 到 $9」当公式）。于是 `$5\cos x-\cos(5x+\varphi)\le b$` 这类
///     **数字开头且带空格**的公式会被当成正文，题面上直接露出 LaTeX 源码。
///     这里把合法的 `$…$` / `$$…$$` 换成 `\(…\)` / `\[…\]`（包的原生形式，
///     没有那条启发式），公式就能真正排版；价格那种不闭合的写法保持原样。
///  2. **填空下划线可见**：3+ 连续下划线转义成字面量，避免被 Markdown 当成
///     强调/分隔线吃掉（口径见 `question_blank_markup.dart`）。
///
/// 代码栅栏与行内代码里的内容一律不动（那是代码，不是题面公式/填空）。
library;

import 'question_blank_markup.dart';

/// 题目文本 → 可交给 `MarkdownRenderer` 的 Markdown 源。
///
/// [fontSize] 用来估算填空空位的显示尺寸（空位是组件，不是字符）。
String questionMarkdownSource(String text, {double fontSize = 16}) =>
    questionMarkdownWithBlankWidgets(
      questionMathForRenderer(text),
      fontSize: fontSize,
    );

/// 把行内/块级公式换成 `\(…\)` / `\[…\]`；价格那样的孤立 `$` 保持原样。
String questionMathForRenderer(String text) {
  if (!text.contains(r'$')) {
    return text;
  }
  final buffer = StringBuffer();
  final lines = text.split('\n');
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
      buffer.write(_convertLine(line));
    }
    if (index != lines.length - 1) {
      buffer.write('\n');
    }
  }
  return buffer.toString();
}

String _convertLine(String line) {
  if (!line.contains(r'$')) {
    return line;
  }
  final buffer = StringBuffer();
  var index = 0;
  while (index < line.length) {
    final char = line[index];
    if (char == r'\') {
      // `\$`（转义美元）与其它转义整体跳过：字面量，不改写。
      buffer.write(line.substring(index, index + 2 > line.length
          ? line.length
          : index + 2));
      index += 2;
      continue;
    }
    if (char == '`') {
      final close = line.indexOf('`', index + 1);
      if (close > index) {
        buffer.write(line.substring(index, close + 1));
        index = close + 1;
        continue;
      }
    }
    if (char != r'$') {
      buffer.write(char);
      index++;
      continue;
    }
    if (index + 1 < line.length && line[index + 1] == r'$') {
      final end = line.indexOf(r'$$', index + 2);
      if (end > index) {
        final tex = line.substring(index + 2, end).trim();
        buffer.write(tex.isEmpty ? '' : '\\[$tex\\]');
        index = end + 2;
        continue;
      }
      // 没闭合的 `$$`：原样保留，不猜。
      buffer.write(r'$$');
      index += 2;
      continue;
    }
    final end = _inlineMathClose(line, index + 1);
    if (end < 0) {
      buffer.write(r'$');
      index++;
      continue;
    }
    final tex = line.substring(index + 1, end).trim();
    if (tex.isEmpty) {
      buffer.write(line.substring(index, end + 1));
    } else {
      buffer.write('\\($tex\\)');
    }
    index = end + 1;
  }
  return buffer.toString();
}

/// 闭合 [from] 之前那个 `$` 的下标；找不到返回 -1。
///
/// 判定与 `gpt_markdown` 的 `DollarMathCloser` 对齐（闭合 `$` 前不能是空白、
/// 后不能是数字、不能紧挨 `$` 或反斜杠），**但不加**「数字开头时必须在空白前
/// 闭合」那条价格启发式——那正是要绕开的限制。
int _inlineMathClose(String line, int from) {
  var index = from;
  while (index < line.length) {
    if (line[index] == r'\') {
      index += 2;
      continue;
    }
    if (line[index] == r'$') {
      final before = line[index - 1];
      final after = index + 1 < line.length ? line[index + 1] : '';
      final afterIsDigit = after.isNotEmpty &&
          after.codeUnitAt(0) >= 0x30 &&
          after.codeUnitAt(0) <= 0x39;
      final valid = index > 0 &&
          line[index] != r'\' &&
          before != r'$' &&
          after != r'$' &&
          !_isWhitespace(before) &&
          !afterIsDigit;
      if (valid) {
        return index;
      }
    }
    index++;
  }
  return -1;
}

bool _isWhitespace(String char) =>
    char == ' ' || char == '\t' || char == '\n' || char == '\r';

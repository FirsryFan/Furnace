/// 题目区整段 Markdown + LaTeX 的渲染入口（handoff 规范 §7 M1）。
///
/// 题目文本按 Markdown 还是按「原文 + 行内公式」渲染，由题目记录的
/// `text_format` 决定（.tqb v1 可选字段）：
///
///  * `plain` / 缺省 / 未知值 → [QuestionRichText]：原文是数据，只有闭合的
///    行内公式交给 Markdown 渲染，`*`、`_`、`#` 原样显示（历史题行为不变）；
///  * `markdown` → 整段交给 [GptMarkdown]（打开 `useDollarSignsForLatex`），
///    `$…$`、`$$…$$`、标题、列表、代码块、表格都会被解析。
///
/// Markdown 只有结构完整时才交给渲染器：未闭合的代码栅栏或 `$`/`$$` 定界符
/// 会把后面的整段文本吞进去，此时退回 [SelectableText] 原文。检查口径与 AI
/// 消息体（`ai_message_markup.dart` 的 `aiMessageRendersAsMarkdown`）一致，
/// 但这里独立实现，题目区不依赖 AI 层。
library;

import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import 'question_media_view.dart';

/// 题目记录的 `text_format` 是否要求整段 Markdown 渲染。
///
/// null、空串、`plain` 以及任何不认识的值都返回 false：历史题库没有这一列，
/// 行为必须和以前完全一致。
bool questionTextFormatIsMarkdown(String? textFormat) =>
    textFormat != null && textFormat.trim().toLowerCase() == 'markdown';

/// Markdown 文本是否完整到可以交给渲染器。
///
/// 只检查会把后续文本吞进构造里的两类语法——代码栅栏与公式定界符；强调、
/// 列表、表格、行内代码即使只写了一半，渲染器也只会按字面显示，不会误解后面
/// 的内容，因此不算「不完整」。
bool questionMarkdownRendersAsMarkdown(String text) =>
    !_hasUnterminatedFence(text) && !_hasUnterminatedMath(text);

/// 题目原文的渲染：按 [markdown] 选择整段 Markdown 或行内公式口径。
///
/// 两种模式都保持可选、可复制：纯文本由 [QuestionRichText] 走
/// [SelectableText]，Markdown 包在 [SelectionArea] 里。
class MarkdownQuestionText extends StatelessWidget {
  const MarkdownQuestionText({
    super.key,
    required this.text,
    this.style,
    this.textAlign,
    this.markdown = false,
  });

  /// 要渲染的原文。
  final String text;

  /// 正文样式；Markdown 的标题、列表等按包内默认比例派生。
  final TextStyle? style;

  /// 段落水平对齐。
  final TextAlign? textAlign;

  /// true 时按整段 Markdown 渲染；缺省 false 与 [QuestionRichText] 一致。
  final bool markdown;

  @override
  Widget build(BuildContext context) {
    if (!markdown) {
      return QuestionRichText(text: text, style: style, textAlign: textAlign);
    }
    if (!questionMarkdownRendersAsMarkdown(text)) {
      return SelectableText(text, style: style, textAlign: textAlign);
    }
    final theme = Theme.of(context);
    return SelectionArea(
      child: GptMarkdown(
        text,
        style: style,
        textAlign: textAlign ?? TextAlign.start,
        useDollarSignsForLatex: true,
        styleSheet: GptMarkdownStyleSheet(
          link: LinkStyle(color: theme.colorScheme.primary),
        ),
      ),
    );
  }
}

/// 有没有落单的代码栅栏行（行首 ``` 或 ~~~ 的计数为奇数）。
bool _hasUnterminatedFence(String text) {
  var backticks = 0;
  var tildes = 0;
  for (final line in text.split('\n')) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('```')) {
      backticks++;
    } else if (trimmed.startsWith('~~~')) {
      tildes++;
    }
  }
  return backticks.isOdd || tildes.isOdd;
}

/// 有没有落单的 `$` / `$$` 定界符。
bool _hasUnterminatedMath(String text) {
  var index = 0;
  while (index < text.length) {
    final char = text[index];
    if (char == r'\') {
      // 转义的字符是字面量：`\$` 既不能开也不能闭公式。跳过两个字符也让
      // 末尾的反斜杠不会被当成下一个定界符的转义。
      index += 2;
      continue;
    }
    if (char != r'$') {
      index++;
      continue;
    }
    if (_isDollar(text, index + 1)) {
      final close = _closingDisplayDollar(text, index + 2);
      if (close < 0) {
        return true;
      }
      index = close + 2;
      continue;
    }
    if (index + 1 >= text.length) {
      // 文本末尾的 `$` 后面没有东西能闭合它。
      return true;
    }
    // `$` 后面跟空白不构成行内公式开头，它是正文。
    if (_isWhitespace(text[index + 1])) {
      index++;
      continue;
    }
    final close = _closingInlineDollar(text, index + 1);
    if (close < 0) {
      return true;
    }
    index = close + 1;
  }
  return false;
}

/// [index] 处是不是 `$` 的字面量。
bool _isDollar(String text, int index) =>
    index < text.length && text[index] == r'$';

/// 闭合 [from] 之前那个 `$$` 的 `$` 下标；找不到返回 -1。
int _closingDisplayDollar(String text, int from) {
  var index = from;
  while (index < text.length) {
    if (text[index] == r'\') {
      index += 2;
      continue;
    }
    if (_isDollar(text, index) && _isDollar(text, index + 1)) {
      return index;
    }
    index++;
  }
  return -1;
}

/// 闭合 [from] 之前那个行内公式的 `$` 下标；找不到返回 -1。
///
/// `$$` 不能闭合行内公式；前面是空白的 `$` 是正文（`价格 $5 到 $9` 不能把
/// 从未打开过的公式闭合掉）。
int _closingInlineDollar(String text, int from) {
  var index = from;
  while (index < text.length) {
    if (text[index] == r'\') {
      index += 2;
      continue;
    }
    if (text[index] == r'$') {
      if (_isDollar(text, index + 1)) {
        index += 2;
        continue;
      }
      if (!_isWhitespace(text[index - 1])) {
        return index;
      }
    }
    index++;
  }
  return -1;
}

bool _isWhitespace(String char) =>
    char == ' ' || char == '\t' || char == '\n' || char == '\r';

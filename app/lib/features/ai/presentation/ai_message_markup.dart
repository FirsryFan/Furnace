import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

/// Renders one message body of the AI conversation.
///
/// Two rules live here, and they are deliberately in one place:
///
///  * **the user's own text is never parsed as markup.** What the user typed is
///    data. Running it through a markdown parser would silently change what they
///    see - a pasted `*` or `$` is a literal `*` or `$`, not the start of
///    emphasis or a formula - and would let a message the user wrote alter the
///    layout of the reply next to it.
///  * **the model's text is parsed, but only when it is structurally
///    complete** - see [aiMessageRendersAsMarkdown]. A reply is streamed in
///    fragments, and a half-arrived delimiter changes the meaning of everything
///    after it, so the incomplete states are shown literally and the message
///    switches to markdown as soon as the construct closes.
class AiMessageBody extends StatelessWidget {
  const AiMessageBody({super.key, required this.text, required this.isUser});

  final String text;

  /// True for a message the user wrote, false for a model reply.
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Literal rendering is not a degraded fallback: for a user message it is the
    // only correct rendering, and for an incomplete model reply it is the only
    // one that cannot misinterpret a fragment.
    if (isUser || !aiMessageRendersAsMarkdown(text)) {
      return SelectableText(text);
    }
    // `SelectionArea` keeps the reply selectable, which is what the plain-text
    // rendering this replaced already offered. Colours are left to the ambient
    // theme: the package derives code blocks, tables and inline code from
    // `ColorScheme`, so the only value that has to be supplied is the link
    // colour, whose package default is a hard-coded blue.
    return SelectionArea(
      child: GptMarkdown(
        text,
        style: theme.textTheme.bodyMedium,
        useDollarSignsForLatex: true,
        styleSheet: GptMarkdownStyleSheet(
          link: LinkStyle(color: theme.colorScheme.primary),
        ),
      ),
    );
  }
}

/// Whether [text] is complete enough to hand to the markdown renderer.
///
/// The rule is a pairing check on the two constructs that swallow everything
/// after them, because those are the ones a streaming fragment can turn into a
/// broken document rather than an unstyled one:
///
///  1. **Fenced code blocks** - the number of fence lines (a line whose first
///     non-space characters are ``` or ~~~) must be even, counted per fence
///     character. An unclosed fence would put the rest of the reply inside a
///     code block.
///  2. **Math** - every `$`/`$$` delimiter must find its partner, honouring
///     `\$` as an escaped literal. A `$` opening an inline formula must not be
///     followed by whitespace, and its closing `$` must not be preceded by
///     whitespace, which is what keeps ordinary prose such as `花了 $5` from
///     being read as the start of a formula. Display `$$…$$` has no such
///     spacing rule.
///
/// Everything else markdown defines - emphasis, lists, tables, links, inline
/// code, headings - is intentionally *not* checked: those degrade to literal
/// text in the parser rather than reinterpreting the rest of the message, so a
/// fragment of them is ugly but not wrong, and treating them as blocking would
/// drop the whole answer to plain text for a stray `*` or backtick.
bool aiMessageRendersAsMarkdown(String text) {
  return !_hasUnterminatedFence(text) && !_hasUnterminatedMath(text);
}

/// Whether [text] holds a fence line with no partner. See
/// [aiMessageRendersAsMarkdown] rule 1.
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

/// Whether [text] holds a math delimiter with no partner. See
/// [aiMessageRendersAsMarkdown] rule 2.
bool _hasUnterminatedMath(String text) {
  var index = 0;
  while (index < text.length) {
    final char = text[index];
    if (char == r'\') {
      // An escaped character is literal, `\$` included: it can neither open nor
      // close a formula. Skipping both characters also stops a trailing
      // backslash from being read as an escape of the next delimiter.
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
      // A `$` at the very end of the text has nothing that could close it.
      return true;
    }
    // A `$` followed by whitespace opens nothing; it is prose, not a delimiter.
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

/// Whether [text] has the literal `$` of a `$$` pair at [index].
bool _isDollar(String text, int index) =>
    index < text.length && text[index] == r'$';

/// Index of the `$$` closing a display formula opened before [from], or -1.
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

/// Index of the `$` closing an inline formula opened before [from], or -1.
///
/// A `$$` is not a valid closing delimiter for an inline formula, and a `$`
/// preceded by whitespace is prose: `价格 $5 到 $9` must not close a formula
/// that was never opened.
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

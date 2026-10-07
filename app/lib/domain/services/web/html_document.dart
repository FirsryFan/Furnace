/// A deliberately small, bounded HTML scanner: enough to read text and to pick
/// elements out of an ordinary page, and nothing more.
///
/// **This is not a browser and it does not build a correct DOM.** It is a
/// single-pass tag scanner that keeps the elements it actually saw, with these
/// limits spelled out so no caller can mistake it for a real parser:
///
///  * no tree repair: a missing `</div>` or a `<p>` implicitly closed by a block
///    element is not fixed. Whatever nesting the source wrote is the nesting the
///    caller gets, so an unbalanced page can produce a "wrong" tree;
///  * raw-text elements (`<script>`, `<style>`, `<textarea>`, `<title>`) are
///    consumed up to their own closing tag instead of being parsed;
///  * no character-encoding work (that happens before the text arrives), no
///    `<template>` content expansion, no foreign-content (SVG/MathML) rules, no
///    CSS cascade;
///  * node count and nesting depth are capped ([HtmlDocument.maxNodes],
///    [_maxDepth]) so a hostile or huge page cannot exhaust memory or the call
///    stack. Truncation at the cap is reported, never silent.
///
/// The selector engine next to it implements a documented subset of CSS
/// selectors and **refuses** anything outside that subset instead of returning
/// an empty match, because "selector matched nothing" and "selector was not
/// understood" must not look the same to the model.
library;

import 'html_entities.dart';

/// One element or text run in the scanned page.
///
/// A text node has a null [tag]; an element node has a null [text]. Exactly one
/// of the two is set, which keeps the tree one type instead of a class hierarchy
/// this file does not need.
class HtmlNode {
  HtmlNode.element(this.tag, this.attributes)
      : text = null;

  HtmlNode.text(this.text)
      : tag = null,
        attributes = const {};

  /// Lower-cased tag name, or null for a text node.
  final String? tag;

  /// Attributes exactly as written, name lower-cased, value entity-decoded.
  final Map<String, String> attributes;

  /// Raw (still entity-encoded) text, or null for an element node.
  final String? text;

  final List<HtmlNode> children = [];

  /// The parent, or null for the page root. Set by [HtmlDocument.parse].
  HtmlNode? parent;

  bool get isElement => tag != null;

  /// The first attribute named [name] (case-insensitive), or null.
  String? attribute(String name) {
    final wanted = name.toLowerCase();
    for (final entry in attributes.entries) {
      if (entry.key == wanted) {
        return entry.value;
      }
    }
    return null;
  }

  /// The `class` attribute split on whitespace, without empties.
  List<String> get classNames {
    final value = attribute('class');
    if (value == null) {
      return const [];
    }
    return [
      for (final part in value.split(RegExp(r'\s+')))
        if (part.isNotEmpty) part,
    ];
  }

  /// The first element named [tag] in this subtree (document order), or null.
  HtmlNode? firstWithTag(String tag) {
    if (isElement && this.tag == tag) {
      return this;
    }
    for (final child in children) {
      final found = child.firstWithTag(tag);
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  /// The page title: the text of the first `<title>` element, trimmed.
  ///
  /// `title` is a raw-text element, so its content is not a child text node -
  /// that is why this reads the recorded content range instead of walking
  /// children.
  String get title {
    final element = firstWithTag('title');
    if (element == null) {
      return '';
    }
    return element.rawTextContent.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// The decoded raw text this node holds, or '' for a real element.
  ///
  /// Only raw-text elements (`script`/`style`/`textarea`/`title`) have content
  /// that is not markup; [documentSource] is where it is read from.
  String get rawTextContent {
    final start = _contentStart;
    final end = _contentEnd;
    if (start == null || end == null || end <= start) {
      return '';
    }
    final source = documentSource;
    if (start >= source.length) {
      return '';
    }
    return decodeHtmlEntities(source.substring(start, end > source.length ? source.length : end));
  }

  /// The source this node came from, needed by [rawTextContent] only.
  ///
  /// Stored on the root and read up the parent chain: every node holding its own
  /// copy of the page would waste memory proportional to page size times node
  /// count, and copying it is exactly what a "keep it simple" version of this does
  /// by mistake.
  String get documentSource {
    HtmlNode? node = this;
    while (node != null) {
      final source = node._source;
      if (source != null) {
        return source;
      }
      node = node.parent;
    }
    return '';
  }

  String? _source;
  int? _contentStart;
  int? _contentEnd;

  /// Tags ignored by [HtmlDocument.extractText].
  ///
  /// `script`/`style` are required (their content is code, not prose);
  /// `head`/`template`/`noscript` are here because their usual contents are
  /// metadata, and shipping a page's `<noscript>` boilerplate as "readable
  /// text" would be noise for the model.
  static const Set<String> textSkippedTags = {
    'script',
    'style',
    'head',
    'template',
    'noscript',
  };

  /// Elements that start a new visual line. Used only to keep words apart when
  /// stripping tags: without it `</p><p>` would join the last word of one
  /// paragraph to the first word of the next.
  static const Set<String> blockTags = {
    'address', 'article', 'aside', 'blockquote', 'br', 'dd', 'div',
    'dl', 'dt', 'fieldset', 'figcaption', 'figure', 'footer', 'form',
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'header', 'hr', 'li', 'main',
    'nav', 'ol', 'p', 'pre', 'section', 'table', 'tbody', 'td', 'tfoot',
    'th', 'thead', 'tr', 'ul', //
  };

  /// Elements that cannot have children, so the scanner must not push them.
  static const Set<String> voidTags = {
    'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link',
    'meta', 'param', 'source', 'track', 'wbr', //
  };

  /// Elements whose content is raw text (never markup).
  static const Set<String> rawTextTags = {'script', 'style', 'textarea', 'title'};
}

/// The scanned page: a root node plus the source it was scanned from.
class HtmlDocument {
  HtmlDocument._(this.root, this.source);

  /// Not a real DOM: see the library doc comment.
  final HtmlNode root;

  /// The decoded source, kept so raw-text ranges can be read lazily.
  final String source;

  /// True when the node cap was hit and the tail of the page was dropped.
  bool get nodesTruncated => _nodesTruncated;
  bool _nodesTruncated = false;

  /// Scans [html] into a node tree.
  ///
  /// Never throws on malformed markup: a stray `<`, an unclosed tag or a
  /// truncated final tag just end the interesting part of the scan. The one
  /// thing it does refuse to do is grow without bound - past [maxNodes] it stops
  /// adding nodes and sets [nodesTruncated].
  ///
  /// Elements and text runs are placed in **one pass over the source, in source
  /// order**. That single ordering guarantee is what makes the extracted text
  /// read in the right order, and it is why text is not attached in a second
  /// loop: any later pass would append text nodes after elements that actually
  /// follow them, turning "Hello <b>world</b>!" into "worldHello".
  static HtmlDocument parse(String html, {int maxNodes = defaultMaxNodes}) {
    final document = HtmlDocument._(HtmlNode.element('#document', const {}), html)
      .._nodesTruncated = false;
    document.root._source = html;

    final scan = _findOpenTags(html, maxNodes);
    final tags = scan.tags;
    // Report the cap rather than silently dropping the tail of a huge page: the
    // model must be able to tell "the page ends here" from "I stopped reading".
    document._nodesTruncated = scan.truncated;
    final runs = _findTextRuns(html, tags);
    final stack = <HtmlNode>[document.root];

    // Both lists are in source order, so one merge walks the page exactly as it
    // was written: a text run is placed with whichever element is open at that
    // point, and a close tag pops one frame before the next run is placed. That
    // ordering is the whole reason a run after `</a>` ends up in the enclosing
    // element instead of being dropped.
    var tagIndex = 0;
    var runIndex = 0;
    while (tagIndex < tags.length || runIndex < runs.length) {
      final hasTag = tagIndex < tags.length;
      final hasRun = runIndex < runs.length;
      final takeRun = hasRun &&
          (!hasTag || runs[runIndex].position < tags[tagIndex].tagStart);

      if (takeRun) {
        _attach(stack.last, runs[runIndex].node);
        runIndex++;
        continue;
      }

      final tag = tags[tagIndex++];
      if (!tag.isOpen) {
        // A close tag with a name pops; a marker (comment/declaration) does
        // nothing at all.
        final name = tag.closeTag;
        if (name != null) {
          _popMatching(stack, name);
        }
        continue;
      }

      final node = tag.node!;
      // A repeated unclosed tag (`<p>one<p>two`) is treated as a sibling rather
      // than a nesting: the source gives no closing tag to tell them apart, and
      // nesting identical tags would hide the first one's text from any
      // per-element extraction.
      if (stack.length > 1 && stack.last.tag == node.tag) {
        _attach(stack[stack.length - 2], stack.removeLast());
      }
      _attach(stack.last, node);

      final container = !tag.isRawText && !HtmlNode.voidTags.contains(node.tag);
      if (container && stack.length < _maxDepth) {
        stack.add(node);
      }
      // Past the depth guard the node stays a child of the deepest container
      // rather than becoming one; the text still lands somewhere reachable.
    }

    // Anything still open at end of input belongs to the tree regardless.
    while (stack.length > 1) {
      final open = stack.removeLast();
      _attach(stack.last, open);
    }
    return document;
  }

  /// Every element in document order (the root is not included).
  List<HtmlNode> elements() {
    final out = <HtmlNode>[];
    final queue = <HtmlNode>[...root.children];
    while (queue.isNotEmpty) {
      final node = queue.removeAt(0);
      if (node.isElement) {
        out.add(node);
      }
      queue.addAll(node.children);
    }
    return out;
  }

  /// All elements matching [selector], in document order.
  ///
  /// Throws [SelectorSyntaxException] for any syntax outside the supported
  /// subset - see [parseSelector].
  List<HtmlNode> select(String selector) {
    final steps = parseSelector(selector);
    var current = [root];
    for (final step in steps) {
      final next = <HtmlNode>[];
      for (final node in current) {
        _descendantsMatching(node, step, next);
      }
      current = next;
    }
    return current;
  }

  /// The readable text of [node] and its descendants.
  ///
  /// - skips [HtmlNode.textSkippedTags] entirely (its text is not prose);
  /// - decodes entities;
  /// - joins at [HtmlNode.blockTags] boundaries and collapses every run of
  ///   whitespace (including `&nbsp;`) to a single space;
  /// - caps nesting at [_maxDepth] so a deep page cannot overflow the stack;
  /// - truncates the result at [maxChars] and says so explicitly.
  String extractText(HtmlNode node, {int maxChars = 8000}) {
    final out = StringBuffer();
    _collectText(node, out, 0);
    final collapsed = _collapseText(out.toString());
    if (collapsed.length <= maxChars) {
      return collapsed;
    }
    final note = ' ... [截断：页面文本超过 $maxChars 字符，这里只是开头部分]';
    final keep = maxChars > note.length ? maxChars - note.length : 0;
    return '${collapsed.substring(0, keep).trimRight()}$note';
  }

  /// The trimmed, collapsed text inside one element.
  ///
  /// Used for one selector match, so the cap is per element and much smaller
  /// than a page-wide [extractText].
  String extractElementText(HtmlNode element, {int maxChars = 500}) {
    final out = StringBuffer();
    _collectText(element, out, 0);
    final collapsed = _collapseText(out.toString());
    if (collapsed.length <= maxChars) {
      return collapsed;
    }
    const note = ' ... [截断]';
    final keep = maxChars > note.length ? maxChars - note.length : 0;
    return '${collapsed.substring(0, keep).trimRight()}$note';
  }

  /// One rendered match, ready to hand to the model as JSON.
  Map<String, Object?> matchJson(HtmlNode element, {required int index}) {
    final tag = element.tag ?? '';
    final id = element.attribute('id');
    final classes = element.classNames;
    final row = <String, Object?>{
      'index': index,
      'tag': tag,
      if (id != null && id.trim().isNotEmpty) 'id': id.trim(),
      if (classes.isNotEmpty) 'class': classes.join(' '),
      'text': extractElementText(element),
      // The useful per-tag attribute set, spread inline so an `a` does not also
      // carry `target`/`rel` noise and an unknown tag still shows everything.
      ..._usefulAttributes(tag, element),
    };
    final href = element.attribute('href');
    if (tag == 'a' && href != null) {
      row['href'] = href;
    }
    final src = element.attribute('src');
    if (tag == 'img' && src != null) {
      row['src'] = src;
    }
    final alt = element.attribute('alt');
    if (tag == 'img' && alt != null) {
      row['alt'] = alt;
    }
    final value = element.attribute('value');
    if (_isFormField(tag) && value != null) {
      row['value'] = value;
    }
    final name = element.attribute('name');
    if (_isFormField(tag) && name != null) {
      row['name'] = name;
    }
    return row;
  }

  /// Which attributes are worth showing for a tag.
  ///
  /// A link gets `href`; an image gets the media attributes; a form field gets
  /// what it submits and how it is labelled; everything else gets all of them,
  /// because for an unknown tag the model is the one who knows what matters.
  Map<String, String> _usefulAttributes(String tag, HtmlNode element) {
    const linkAttributes = {'href', 'title', 'rel', 'target'};
    const imageAttributes = {'src', 'alt', 'title', 'width', 'height'};
    const fieldAttributes = {
      'name',
      'type',
      'value',
      'placeholder',
      'required',
      'checked',
      'selected',
      'disabled',
    };
    final Set<String>? keep = switch (tag) {
      'a' => linkAttributes,
      'img' => imageAttributes,
      'input' || 'textarea' || 'select' || 'option' || 'button' => fieldAttributes,
      _ => null,
    };
    if (keep == null) {
      return element.attributes;
    }
    return {
      for (final entry in element.attributes.entries)
        if (keep.contains(entry.key)) entry.key: entry.value,
    };
  }

  static bool _isFormField(String tag) =>
      tag == 'input' ||
      tag == 'textarea' ||
      tag == 'select' ||
      tag == 'option' ||
      tag == 'button';

  // ---------------------------------------------------------------------------
  // Scanning internals.
  // ---------------------------------------------------------------------------

  /// The default node cap. A generous page is a few thousand tags; this is far
  /// above that and still small enough to keep one tool call predictable.
  static const int defaultMaxNodes = 20000;

  /// One tag as found in the source, with the offsets needed to place it and
  /// where it ends.
  ///
  /// Text runs are **not** carried here: they are scanned separately
  /// ([_findTextRuns]) and merged with the tags by source position, because a
  /// text run after a close tag belongs to the element that was just closed, not
  /// to the close tag. Keeping the two streams apart is what makes that
  /// attributable; folding them together is how an earlier version of this file
  /// dropped every `</p> following text` run.
  static ({List<_Tag> tags, bool truncated}) _findOpenTags(
    String html,
    int maxNodes,
  ) {
    final found = <_Tag>[];

    var index = 0;
    while (index < html.length && found.length < maxNodes) {
      final lt = html.indexOf('<', index);
      if (lt < 0) {
        break;
      }
      final kind = _classify(html, lt);
      if (kind == null) {
        index = lt + 1;
        continue;
      }
      if (kind.isComment) {
        final end = html.indexOf('-->', lt + 4);
        // Recorded as a marker so the text scanner steps over it: otherwise the
        // comment's own markup would be read as page text.
        final stop = end < 0 ? html.length : end + 3;
        found.add(_Tag.marker(lt, stop));
        index = stop;
        continue;
      }
      if (kind.isDeclaration) {
        final end = _skipTag(html, lt);
        final stop = end < 0 ? html.length : end;
        found.add(_Tag.marker(lt, stop));
        index = stop;
        continue;
      }
      if (kind.isClose) {
        final end = _skipTag(html, lt);
        if (end < 0) {
          break;
        }
        found.add(_Tag.close(kind.name, lt, end));
        index = end;
        continue;
      }

      final end = _skipTag(html, lt);
      if (end < 0) {
        // A `<` that never closes: the rest of the input is not markup.
        break;
      }
      final name = kind.name!;
      final node = HtmlNode.element(name, _parseAttributes(html, lt, end));
      if (HtmlNode.rawTextTags.contains(name) &&
          !HtmlNode.voidTags.contains(name)) {
        // The close tag may be missing on a truncated page; the content then
        // simply runs to the end of the input.
        final close = _indexOfCloseTag(html, name, end);
        node
          .._contentStart = end
          .._contentEnd = close < 0 ? html.length : close;
        found.add(_Tag.rawText(node, lt, end,
            contentEnd: close < 0 ? html.length : close));
        index = close < 0 ? html.length : _skipTag(html, close);
        continue;
      }
      found.add(_Tag.open(node, lt, end));
      index = end;
    }
    return (tags: found, truncated: found.length >= maxNodes && index < html.length);
  }

  /// The non-blank text runs between tags, in source order.
  ///
  /// Each run records where it starts, so the tree pass can interleave it with
  /// the tags by position. Raw-text element content (`<script>`) is skipped here
  /// by the same rule the tag scan uses to jump over it.
  static List<_TextRun> _findTextRuns(String html, List<_Tag> tags) {
    final runs = <_TextRun>[];
    var cursor = 0;
    for (final tag in tags) {
      final gap = _textNodeAt(html, cursor, tag.tagStart);
      if (gap != null) {
        runs.add(_TextRun(gap, cursor));
      }
      // Skip the element's raw content entirely: it is not prose.
      cursor = tag.contentEnd ?? tag.tagEnd;
    }
    final tail = _textNodeAt(html, cursor, html.length);
    if (tail != null) {
      runs.add(_TextRun(tail, cursor));
    }
    return runs;
  }

  /// The text node for the run between two offsets, or null when it is blank.
  ///
  /// A whitespace-only run between two tags carries no reading value and would
  /// only add nodes, so it is dropped here rather than in every consumer.
  static HtmlNode? _textNodeAt(String html, int start, int end) {
    if (end <= start || start >= html.length) {
      return null;
    }
    final stop = end > html.length ? html.length : end;
    final raw = html.substring(start, stop);
    return raw.trim().isEmpty ? null : HtmlNode.text(raw);
  }

  /// What kind of `<` construct starts at [lt], or null when the `<` is just a
  /// less-than sign in text.
  static _TagKind? _classify(String html, int lt) {
    if (lt + 1 >= html.length) {
      return null;
    }
    final next = html.codeUnitAt(lt + 1);
    if (next == _slash) {
      if (lt + 2 >= html.length || !_isNameStart(html.codeUnitAt(lt + 2))) {
        return null;
      }
      return _TagKind.close(_readTagName(html, lt + 2));
    }
    if (next == _bang) {
      if (html.startsWith('<!--', lt)) {
        return const _TagKind.comment();
      }
      return const _TagKind.declaration();
    }
    if (next == _question) {
      return const _TagKind.declaration();
    }
    if (!_isNameStart(next)) {
      return null;
    }
    return _TagKind.open(_readTagName(html, lt + 1));
  }

  /// Index just past the `>` that ends the tag starting at [lt], or -1 when the
  /// tag never ends. Quoted attribute values may contain `>`.
  static int _skipTag(String html, int lt) {
    var i = lt + 1;
    int? quote;
    while (i < html.length) {
      final code = html.codeUnitAt(i);
      if (quote != null) {
        if (code == quote) {
          quote = null;
        }
      } else if (code == _doubleQuote || code == _singleQuote) {
        quote = code;
      } else if (code == _gt) {
        return i + 1;
      }
      i++;
    }
    return -1;
  }

  /// Attributes of the tag that starts at [start] and ends at [end].
  ///
  /// Deliberately permissive: an attribute with no value becomes `''`, a
  /// duplicate keeps the first occurrence, and anything that does not look like
  /// `name` / `name=value` is skipped rather than turning into a parse error.
  static Map<String, String> _parseAttributes(String html, int start, int end) {
    final attributes = <String, String>{};
    if (end <= start + 1) {
      return attributes;
    }
    var i = start + 1;
    // Skip the tag name.
    while (i < end && !_isWhitespace(html.codeUnitAt(i)) && html.codeUnitAt(i) != _gt) {
      i++;
    }
    while (i < end) {
      while (i < end && _isWhitespace(html.codeUnitAt(i))) {
        i++;
      }
      if (i >= end || html.codeUnitAt(i) == _gt) {
        break;
      }
      if (html.codeUnitAt(i) == _slash) {
        // The `/` of `<br/>`: not an attribute.
        i++;
        continue;
      }

      final nameStart = i;
      while (i < end &&
          !_isWhitespace(html.codeUnitAt(i)) &&
          html.codeUnitAt(i) != _equals &&
          html.codeUnitAt(i) != _gt &&
          html.codeUnitAt(i) != _slash) {
        i++;
      }
      if (i == nameStart) {
        i++;
        continue;
      }
      final name = html.substring(nameStart, i).toLowerCase();

      var value = '';
      var afterName = i;
      while (afterName < end && _isWhitespace(html.codeUnitAt(afterName))) {
        afterName++;
      }
      if (afterName < end && html.codeUnitAt(afterName) == _equals) {
        var valueStart = afterName + 1;
        while (valueStart < end && _isWhitespace(html.codeUnitAt(valueStart))) {
          valueStart++;
        }
        if (valueStart < end &&
            (html.codeUnitAt(valueStart) == _doubleQuote ||
                html.codeUnitAt(valueStart) == _singleQuote)) {
          final quote = html.codeUnitAt(valueStart);
          final close = html.indexOf(String.fromCharCode(quote), valueStart + 1);
          final stop = close < 0 || close > end ? end : close;
          value = html.substring(valueStart + 1, stop);
          i = stop < end ? stop + 1 : end;
        } else {
          var valueEnd = valueStart;
          while (valueEnd < end &&
              !_isWhitespace(html.codeUnitAt(valueEnd)) &&
              html.codeUnitAt(valueEnd) != _gt) {
            valueEnd++;
          }
          value = html.substring(valueStart, valueEnd);
          i = valueEnd;
        }
      }
      if (!attributes.containsKey(name)) {
        attributes[name] = decodeHtmlEntities(value);
      }
    }
    return attributes;
  }

  /// The index of the `</name` that closes a raw-text element, or -1.
  ///
  /// Used for `script`/`style`/`title`: their content is source text, not
  /// markup, so it must not be scanned for tags.
  static int _indexOfCloseTag(String html, String name, int from) {
    final needle = '</$name';
    final lower = html.toLowerCase();
    var at = lower.indexOf(needle, from);
    while (at >= 0) {
      final after = at + needle.length;
      if (after >= html.length ||
          _isWhitespace(html.codeUnitAt(after)) ||
          html.codeUnitAt(after) == _gt) {
        return at;
      }
      at = lower.indexOf(needle, at + 1);
    }
    return -1;
  }

  static String? _readTagName(String html, int at) {
    var i = at;
    while (i < html.length && _isNameChar(html.codeUnitAt(i))) {
      i++;
    }
    return i == at ? null : html.substring(at, i).toLowerCase();
  }

  static void _attach(HtmlNode parent, HtmlNode child) {
    if (identical(child.parent, parent)) {
      return;
    }
    // Re-parenting must also drop the child from its old parent's list: leaving
    // the stale reference in place puts the same node under two parents, and the
    // tree walk then shows its text twice.
    final previous = child.parent;
    if (previous != null) {
      previous.children.remove(child);
    }
    child.parent = parent;
    parent.children.add(child);
  }

  /// Pops the innermost element named [tag].
  ///
  /// A close tag with no matching open element (a stray `</div>`) pops nothing,
  /// which keeps malformed markup from restructuring the tree. Any elements left
  /// open inside the closed one are closed with it - that is the only "repair"
  /// this scanner does, and it exists so `<div><p>a<p>b</div>` does not leave the
  /// paragraphs dangling for the rest of the page.
  static void _popMatching(List<HtmlNode> stack, String tag) {
    for (var i = stack.length - 1; i > 0; i--) {
      if (stack[i].tag != tag) {
        continue;
      }
      while (stack.length > i + 1) {
        final inner = stack.removeLast();
        _attach(stack.last, inner);
      }
      final closed = stack.removeLast();
      _attach(stack.last, closed);
      return;
    }
  }

  static void _descendantsMatching(
    HtmlNode node,
    SelectorStep step,
    List<HtmlNode> out,
  ) {
    for (final child in node.children) {
      if (child.isElement) {
        if (step.matches(child)) {
          out.add(child);
        }
        // Text nodes cannot match, but they never have children either, so the
        // recursion below is only for elements.
        _descendantsMatching(child, step, out);
      }
    }
  }

  static void _collectText(HtmlNode node, StringBuffer out, int depth) {
    if (depth > _maxDepth) {
      return;
    }
    for (final child in node.children) {
      if (child.isElement) {
        if (HtmlNode.textSkippedTags.contains(child.tag)) {
          continue;
        }
        final block = HtmlNode.blockTags.contains(child.tag);
        if (block && out.isNotEmpty) {
          out.write(' ');
        }
        _collectText(child, out, depth + 1);
        if (block) {
          out.write(' ');
        }
        continue;
      }
      final raw = child.text;
      if (raw == null || raw.isEmpty) {
        continue;
      }
      out.write(decodeHtmlEntities(raw));
    }
  }

  /// Collapses whitespace runs to one space and trims the ends.
  ///
  /// `&nbsp;` (U+00A0) collapses too: in HTML it is a space that does not wrap,
  /// and keeping runs of it serves nobody reading the text.
  static String _collapseText(String text) {
    if (text.isEmpty) {
      return '';
    }
    final out = StringBuffer();
    var pendingSpace = false;
    for (final rune in text.runes) {
      if (rune == 0x20 || rune == 0x09 || rune == 0x0A || rune == 0x0D ||
          rune == 0x0C || rune == 0xA0) {
        if (out.isNotEmpty) {
          pendingSpace = true;
        }
        continue;
      }
      if (pendingSpace) {
        out.write(' ');
        pendingSpace = false;
      }
      out.writeCharCode(rune);
    }
    return out.toString();
  }

  static bool _isWhitespace(int code) =>
      code == 0x20 || code == 0x09 || code == 0x0A || code == 0x0D || code == 0x0C;

  static bool _isNameStart(int code) =>
      (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);

  static bool _isNameChar(int code) =>
      _isNameStart(code) ||
      (code >= 0x30 && code <= 0x39) ||
      code == 0x2D ||
      code == 0x5F ||
      code == 0x3A;

  /// Max nesting the scanner will descend into. Deeper nodes are still attached
  /// (so their text is reachable through a shallow walk) but never become a
  /// container, which is what keeps the walk from growing without bound.
  static const int _maxDepth = 256;

  static const int _slash = 0x2F;
  static const int _bang = 0x21;
  static const int _question = 0x3F;
  static const int _gt = 0x3E;
  static const int _equals = 0x3D;
  static const int _doubleQuote = 0x22;
  static const int _singleQuote = 0x27;
}

/// A tag as found by the scanner: an open tag with a node, or a close tag with
/// only a name.
///
/// Text runs are deliberately **not** stored here; they are a separate stream
/// merged with these by source position. See [_TextRun].
class _Tag {
  /// A close tag: a name and where it sits, with no node.
  const _Tag.close(this.closeTag, this.tagStart, this.tagEnd)
      : node = null,
        isRawText = false,
        contentEnd = null;

  /// An open tag, void or not.
  const _Tag.open(this.node, this.tagStart, this.tagEnd)
      : closeTag = null,
        isRawText = false,
        contentEnd = null;

  /// A raw-text element (`script`/`style`/`textarea`/`title`) whose content is
  /// source text, not markup. [contentEnd] is where that content stops, so the
  /// text scanner can skip over it.
  const _Tag.rawText(this.node, this.tagStart, this.tagEnd, {this.contentEnd})
      : closeTag = null,
        isRawText = true;

  /// A comment or a `<!doctype>`/`<?...?>` declaration: it occupies source range
  /// but produces no node and no text.
  ///
  /// It is still recorded so the text scanner advances past it; otherwise the
  /// markup of a comment between two words would end up inside the page text.
  const _Tag.marker(this.tagStart, this.tagEnd)
      : node = null,
        closeTag = null,
        isRawText = false,
        contentEnd = null;

  final HtmlNode? node;

  /// Where the tag itself starts (`<`) and ends (just past `>`).
  final int tagStart;
  final int tagEnd;

  /// The tag name on a close tag; null on open tags.
  final String? closeTag;

  final bool isRawText;

  /// For a raw-text element: where its content stops (the close tag, or the end
  /// of the input).
  final int? contentEnd;

  /// Whether this is an open tag (as opposed to a close tag or a marker).
  bool get isOpen => node != null;
}

/// One text run and where it starts in the source.
///
/// The position is what lets the tree pass place it between the right tags; a
/// text run holds no parent reference because it does not know one until the tags
/// around it have been placed.
class _TextRun {
  const _TextRun(this.node, this.position);

  final HtmlNode node;
  final int position;
}

/// What kind of `<` construct the scanner found: `<!doctype>`/`<?...?>`,
/// `<!--...-->`, a close tag, or an open tag.
class _TagKind {
  const _TagKind.open(this.name)
      : isClose = false,
        isComment = false,
        isDeclaration = false;

  const _TagKind.close(this.name)
      : isClose = true,
        isComment = false,
        isDeclaration = false;

  const _TagKind.comment()
      : name = null,
        isClose = false,
        isComment = true,
        isDeclaration = false;

  const _TagKind.declaration()
      : name = null,
        isClose = false,
        isComment = false,
        isDeclaration = true;

  final String? name;
  final bool isClose;
  final bool isComment;
  final bool isDeclaration;
}

// -----------------------------------------------------------------------------
// Selectors.
// -----------------------------------------------------------------------------

/// One compound step of a selector, e.g. `div.item[data-x]`.
class SelectorStep {
  SelectorStep({this.tag, this.id, this.classes = const [], this.attributes = const []});

  /// As written (lower-cased); null means "any tag".
  final String? tag;
  final String? id;
  final List<String> classes;
  final List<AttributeTest> attributes;

  /// Whether [element] satisfies this step alone (combinators are the caller's
  /// job).
  bool matches(HtmlNode element) {
    final elementTag = element.tag;
    if (elementTag == null) {
      return false;
    }
    if (tag != null && elementTag != tag) {
      return false;
    }
    if (id != null && element.attribute('id') != id) {
      return false;
    }
    for (final wanted in classes) {
      if (!element.classNames.contains(wanted)) {
        return false;
      }
    }
    for (final test in attributes) {
      final value = element.attribute(test.name);
      if (value == null) {
        return false;
      }
      if (test.value != null && value != test.value) {
        return false;
      }
    }
    return true;
  }

  /// How this step looks in an error message.
  String describe() {
    final buffer = StringBuffer(tag ?? '');
    if (id != null) {
      buffer.write('#$id');
    }
    for (final className in classes) {
      buffer.write('.$className');
    }
    for (final test in attributes) {
      buffer.write(test.value == null ? '[${test.name}]' : '[${test.name}="${test.value}"]');
    }
    return buffer.toString();
  }
}

/// One attribute condition: presence when [value] is null, equality otherwise.
class AttributeTest {
  const AttributeTest(this.name, this.value);

  final String name;
  final String? value;
}

/// A selector outside the supported subset.
///
/// Its whole purpose is to be *catchable*: the tool turns this into a tool
/// result naming the offending token, so "I did not understand that selector"
/// can never be mistaken for "the page had nothing matching".
class SelectorSyntaxException implements Exception {
  SelectorSyntaxException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The exact selector subset this scanner supports.
///
/// Supported (whitespace separates steps, i.e. the descendant combinator):
///
///  * type - `div`
///  * id - `#main`
///  * class - `.item`
///  * type + class - `div.item`
///  * several classes - `.a.b`
///  * attribute presence - `[data-x]`
///  * attribute equality, quotes optional - `[name="q"]`, `[name=q]`
///  * descendant combinator - `main .item a`
///  * any combination of the above in one step - `div.item#lead[data-x]`
///
/// **Not supported** (each refused by name): `>` `+` `~` `:pseudo`,
/// `nth-child`, `*` (and other namespace/universal syntax), attribute operators
/// other than `=` (`~= |= ^= $= *=`), and comma-separated selector lists.
List<SelectorStep> parseSelector(String selector) {
  final trimmed = selector.trim();
  if (trimmed.isEmpty) {
    throw SelectorSyntaxException('选择器为空');
  }

  final unsupported = _findUnsupported(trimmed);
  if (unsupported != null) {
    throw SelectorSyntaxException(
      '选择器里出现不支持的语法 `$unsupported`。'
      '本工具只支持：类型 div、id #main、类 .item、类型+类 div.item、多类 .a.b、'
      '属性存在 [data-x]、属性相等 [name="q"]、以及空格分隔的后代组合（main .item a）。'
      '**不支持** > + ~ :伪类 nth-child * 逗号列表 和除 = 外的属性运算符。',
    );
  }

  final steps = <SelectorStep>[];
  for (final raw in trimmed.split(RegExp(r'\s+'))) {
    if (raw.isEmpty) {
      continue;
    }
    steps.add(_parseStep(raw));
  }
  if (steps.isEmpty) {
    throw SelectorSyntaxException('选择器为空');
  }
  return steps;
}

/// The first unsupported token in [selector], or null when there is none.
///
/// An attribute operator is checked first so `[class~="item"]` is reported as
/// `~=` (what the author wrote) rather than as a bare `~`, which would suggest a
/// sibling combinator instead. The `[` is part of the reported token because a
/// bare `*` is ambiguous: inside brackets it is an operator, standalone it is the
/// universal selector.
String? _findUnsupported(String selector) {
  // `[attr~=`, `[attr|=`, `[attr^=`, `[attr$=`, `[attr*=`, `[attr!=`.
  final operator = RegExp(r'\[\s*[A-Za-z_][-\w]*\s*[~|^$!*]=');
  final match = operator.firstMatch(selector);
  if (match != null) {
    return match.group(0)!.replaceAll(RegExp(r'\s+'), '');
  }
  for (var i = 0; i < selector.length; i++) {
    final char = selector[i];
    if (char == '>' || char == '+' || char == '~' || char == '*' || char == ':' || char == ',') {
      return char;
    }
  }
  return null;
}

SelectorStep _parseStep(String step) {
  var index = 0;
  String? tag;
  String? id;
  final classes = <String>[];
  final attributes = <AttributeTest>[];

  if (step.isNotEmpty && _isIdentifierStart(step[0])) {
    final name = _readIdentifier(step, index);
    if (name.isEmpty) {
      throw SelectorSyntaxException('选择器 `$step` 里 `$index` 处不是合法的标签名');
    }
    tag = name.toLowerCase();
    index += name.length;
  }

  while (index < step.length) {
    final char = step[index];
    if (char == '.') {
      final name = _readIdentifier(step, index + 1);
      if (name.isEmpty) {
        throw SelectorSyntaxException('选择器 `$step` 里的 `.` 后面没有类名');
      }
      classes.add(name);
      index += name.length + 1;
      continue;
    }
    if (char == '#') {
      final name = _readIdentifier(step, index + 1);
      if (name.isEmpty) {
        throw SelectorSyntaxException('选择器 `$step` 里的 `#` 后面没有 id');
      }
      id = name;
      index += name.length + 1;
      continue;
    }
    if (char == '[') {
      final close = step.indexOf(']', index);
      if (close < 0) {
        throw SelectorSyntaxException('选择器 `$step` 里的 `[` 没有对应的 `]`');
      }
      attributes.add(_parseAttributeTest(step.substring(index + 1, close)));
      index = close + 1;
      continue;
    }
    throw SelectorSyntaxException(
      '选择器 `$step` 里不认识的字符 `$char`（位置 ${index + 1}）。'
      '每个空格分隔的步骤只能由 类型 / #id / .类 / [属性] 组成。',
    );
  }

  if (tag == null && id == null && classes.isEmpty && attributes.isEmpty) {
    throw SelectorSyntaxException('选择器 `$step` 没有指定任何条件');
  }
  return SelectorStep(tag: tag, id: id, classes: classes, attributes: attributes);
}

/// Parses the inside of `[...]`: `name` or `name=value`.
AttributeTest _parseAttributeTest(String body) {
  final trimmed = body.trim();
  if (trimmed.isEmpty) {
    throw SelectorSyntaxException('选择器里有空的 `[]`');
  }
  final equals = trimmed.indexOf('=');
  if (equals < 0) {
    final name = trimmed.toLowerCase();
    if (!_isAttributeName(name)) {
      throw SelectorSyntaxException('属性名 `$trimmed` 不合法');
    }
    return AttributeTest(name, null);
  }

  final name = trimmed.substring(0, equals).trim().toLowerCase();
  if (!_isAttributeName(name)) {
    throw SelectorSyntaxException('属性名 `$name` 不合法');
  }
  var value = trimmed.substring(equals + 1).trim();
  if (value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'")))) {
    value = value.substring(1, value.length - 1);
  }
  return AttributeTest(name, decodeHtmlEntities(value));
}

/// Reads `[A-Za-z_][A-Za-z0-9_-]*` from [from] in [text] (empty when absent).
String _readIdentifier(String text, int from) {
  var index = from;
  while (index < text.length && _isIdentifierPart(text[index])) {
    index++;
  }
  return text.substring(from, index);
}

bool _isIdentifierStart(String char) {
  final code = char.codeUnitAt(0);
  return (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);
}

bool _isIdentifierPart(String char) {
  final code = char.codeUnitAt(0);
  return _isIdentifierStart(char) ||
      (code >= 0x30 && code <= 0x39) ||
      char == '-' ||
      char == '_';
}

bool _isAttributeName(String name) {
  if (name.isEmpty || !_isIdentifierStart(name[0])) {
    return false;
  }
  return name.split('').every((char) => _isIdentifierPart(char));
}

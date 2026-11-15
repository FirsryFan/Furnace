/// 统一 Markdown 解析层：把 Markdown 源码变成一份与渲染目标无关的
/// 中间结构（块 + 带样式的行内片段）。PDF 导出用它；界面预览走
/// `MarkdownRenderer`（gpt_markdown/LaTeX）。
///
/// 为什么不让预览和 PDF 各自解析一遍：
///
///  * 预览（Flutter 控件）和 PDF（`pdf` 包）是两套完全不同的布局引擎，但
///    它们必须对"这是标题还是代码块、这段是粗体还是链接"给出同一个答案；
///  * 两边共用本文件的 [MarkdownBlock]，差异只剩"怎么画"，主题和字号/行距
///    这些参数因此也只定义一次。
///
/// 解析本身交给 `package:markdown`（GFM 扩展集），不自己写正则——表格、
/// 嵌套列表、任务列表这些边界由成熟解析器处理。本文件只做一次 AST 归一化。
library;

import 'package:markdown/markdown.dart' as md;

/// 一段行内文本及其简单样式。
///
/// Markdown 的行内样式是可以叠加的（粗体里的斜体、链接里的代码），所以每个
/// 片段带一组布尔标记，而不是嵌套结构：两个渲染器都只需要"给这段文字挑一个
/// TextStyle"。
class MarkdownRun {
  const MarkdownRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.code = false,
    this.strikethrough = false,
    this.href,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool code;
  final bool strikethrough;

  /// 链接目标；非链接片段为 null。预览只负责让它看起来像链接（下划线 +
  /// 主题链接色），不负责打开浏览器——见 MARKDOWN-STUDIO-2026-11-15.md。
  final String? href;

  /// 和 [other] 的样式标记完全相同（不含文本）。
  bool sameStyleAs(MarkdownRun other) =>
      bold == other.bold &&
      italic == other.italic &&
      code == other.code &&
      strikethrough == other.strikethrough &&
      href == other.href;

  @override
  String toString() => 'MarkdownRun("$text", bold: $bold, italic: $italic, '
      'code: $code, strike: $strikethrough, href: $href)';
}

/// 一个块级元素。
sealed class MarkdownBlock {
  const MarkdownBlock();
}

/// `#` 标题，[level] 为 1..6。
class MarkdownHeading extends MarkdownBlock {
  const MarkdownHeading({required this.level, required this.runs});

  final int level;
  final List<MarkdownRun> runs;
}

/// 普通段落。
class MarkdownParagraph extends MarkdownBlock {
  const MarkdownParagraph(this.runs);

  final List<MarkdownRun> runs;
}

/// 列表项：行内内容在前，嵌套块（通常是子列表、代码块、引用）在后。
class MarkdownListItem {
  const MarkdownListItem({
    required this.runs,
    this.children = const <MarkdownBlock>[],
    this.taskChecked,
  });

  final List<MarkdownRun> runs;
  final List<MarkdownBlock> children;

  /// 任务列表项：null = 普通列表项，false = 未勾选，true = 已勾选。
  final bool? taskChecked;
}

/// 有序/无序列表。
class MarkdownListBlock extends MarkdownBlock {
  const MarkdownListBlock({
    required this.ordered,
    required this.items,
    this.start = 1,
  });

  final bool ordered;
  final List<MarkdownListItem> items;
  final int start;
}

/// 引用块，内部可以再嵌套任意块。
class MarkdownQuote extends MarkdownBlock {
  const MarkdownQuote(this.blocks);

  final List<MarkdownBlock> blocks;
}

/// 围栏代码块（```lang）。
class MarkdownCodeBlock extends MarkdownBlock {
  const MarkdownCodeBlock({required this.code, this.language});

  final String code;
  final String? language;
}

/// GFM 表格。表头行与数据行都按"行 → 单元格 → 行内片段"三层组织。
///
/// GFM 只有一行表头；没有表头（只有数据行）时 [header] 为 null。
class MarkdownTable extends MarkdownBlock {
  const MarkdownTable({this.header, required this.rows});

  /// 表头行的单元格；每个单元格是一组行内片段。
  final List<List<MarkdownRun>>? header;

  /// 数据行：每行是若干单元格，每个单元格是若干行内片段。
  final List<List<List<MarkdownRun>>> rows;
}

/// 分隔线（`---`）。
class MarkdownRule extends MarkdownBlock {
  const MarkdownRule();
}

/// 解析入口。空文本返回空列表，调用方不必特判。
List<MarkdownBlock> parseMarkdownBlocks(String source) {
  if (source.trim().isEmpty) {
    return const <MarkdownBlock>[];
  }
  final document = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
  return _toBlocks(document.parse(source));
}

/// 子块可能出现的标签：列表项里遇到它们就要切到"块"模式。
const Set<String> _blockTags = <String>{
  'p',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'ul',
  'ol',
  'pre',
  'blockquote',
  'table',
  'hr',
  'html',
};

List<MarkdownBlock> _toBlocks(List<md.Node> nodes) {
  final blocks = <MarkdownBlock>[];
  for (final node in nodes) {
    if (node is md.Text) {
      // 顶层裸文本只会在极端输入下出现；当段落处理，不丢内容。
      if (node.text.trim().isNotEmpty) {
        blocks.add(MarkdownParagraph(<MarkdownRun>[MarkdownRun(node.text)]));
      }
      continue;
    }
    if (node is! md.Element) {
      continue;
    }
    switch (node.tag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        blocks.add(
          MarkdownHeading(
            level: int.parse(node.tag.substring(1)),
            runs: _toRuns(node.children ?? const <md.Node>[]),
          ),
        );
      case 'p':
        blocks.add(
          MarkdownParagraph(
            _toRuns(node.children ?? const <md.Node>[]),
          ),
        );
      case 'blockquote':
        blocks.add(
          MarkdownQuote(
            _toBlocks(node.children ?? const <md.Node>[]),
          ),
        );
      case 'ul':
      case 'ol':
        blocks.add(_toList(node));
      case 'pre':
        blocks.add(_toCode(node));
      case 'table':
        blocks.add(_toTable(node));
      case 'hr':
        blocks.add(const MarkdownRule());
      default:
        // 未知块（html 等）：退化成纯文本段落，保证内容不丢。
        final text = node.textContent;
        if (text.trim().isNotEmpty) {
          blocks.add(MarkdownParagraph(<MarkdownRun>[MarkdownRun(text)]));
        }
    }
  }
  return blocks;
}

MarkdownListBlock _toList(md.Element node) {
  final ordered = node.tag == 'ol';
  final start = int.tryParse(node.attributes['start'] ?? '') ?? 1;
  final items = <MarkdownListItem>[];
  for (final child in node.children ?? const <md.Node>[]) {
    if (child is! md.Element || child.tag != 'li') {
      continue;
    }
    bool? checked;
    final runs = <MarkdownRun>[];
    final children = <MarkdownBlock>[];
    var inBlocks = false;
    for (final liChild in child.children ?? const <md.Node>[]) {
      if (liChild is md.Element &&
          liChild.tag == 'input' &&
          liChild.attributes['type'] == 'checkbox') {
        checked = liChild.attributes.containsKey('checked');
        continue;
      }
      final isBlock = liChild is md.Element && _blockTags.contains(liChild.tag);
      if (isBlock) {
        inBlocks = true;
        children.addAll(_toBlocks(<md.Node>[liChild]));
        continue;
      }
      if (inBlocks) {
        // 块之后又出现行内内容：独立成段，不塞回上一段。
        children.add(
          MarkdownParagraph(_toRuns(<md.Node>[liChild])),
        );
      } else {
        runs.addAll(_toRuns(<md.Node>[liChild]));
      }
    }
    items.add(
      MarkdownListItem(runs: runs, children: children, taskChecked: checked),
    );
  }
  return MarkdownListBlock(ordered: ordered, items: items, start: start);
}

MarkdownCodeBlock _toCode(md.Element node) {
  final children = node.children ?? const <md.Node>[];
  md.Element? code;
  for (final child in children) {
    if (child is md.Element && child.tag == 'code') {
      code = child;
      break;
    }
  }
  if (code == null) {
    return MarkdownCodeBlock(
      code: _decodeHtmlEntities(node.textContent),
      language: null,
    );
  }
  String? language;
  final classes = (code.attributes['class'] ?? '').split(' ');
  for (final name in classes) {
    if (name.startsWith('language-')) {
      language = name.substring('language-'.length);
      break;
    }
  }
  // 代码块内容在 AST 里是 HTML 转义过的（`=>` 会变成 `=&gt;`），渲染前必须
  // 还原，否则预览和 PDF 都会把实体当成正文显示。
  return MarkdownCodeBlock(
    code: _decodeHtmlEntities(code.textContent),
    language: language,
  );
}

/// 还原 `package:markdown` 在代码块里做的 HTML 转义。
///
/// 只处理代码路径：普通文本的 Text 节点没有转义，提前 decode 反而会改坏
/// 用户原文里的 `&lt;`。
String _decodeHtmlEntities(String input) => input
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');

MarkdownTable _toTable(md.Element node) {
  List<List<MarkdownRun>>? header;
  final rows = <List<List<MarkdownRun>>>[];
  for (final section in node.children ?? const <md.Node>[]) {
    if (section is! md.Element) {
      continue;
    }
    final isHeaderSection = section.tag == 'thead';
    for (final row in section.children ?? const <md.Node>[]) {
      if (row is! md.Element || row.tag != 'tr') {
        continue;
      }
      final cells = <List<MarkdownRun>>[];
      var hasHeaderCell = false;
      for (final cell in row.children ?? const <md.Node>[]) {
        if (cell is! md.Element || (cell.tag != 'td' && cell.tag != 'th')) {
          continue;
        }
        if (cell.tag == 'th') {
          hasHeaderCell = true;
        }
        cells.add(_toRuns(cell.children ?? const <md.Node>[]));
      }
      if (isHeaderSection || hasHeaderCell) {
        header ??= cells;
      } else {
        rows.add(cells);
      }
    }
  }
  return MarkdownTable(header: header, rows: rows);
}

/// 行内 AST → 带样式的片段。相邻同样式片段合并，减少 TextSpan 数量。
List<MarkdownRun> _toRuns(
  List<md.Node> nodes, {
  bool bold = false,
  bool italic = false,
  bool code = false,
  bool strikethrough = false,
  String? href,
}) {
  final runs = <MarkdownRun>[];

  void walk(
    md.Node node, {
    required bool bold,
    required bool italic,
    required bool code,
    required bool strikethrough,
    required String? href,
  }) {
    if (node is md.Text) {
      runs.add(
        MarkdownRun(
          node.text,
          bold: bold,
          italic: italic,
          code: code,
          strikethrough: strikethrough,
          href: href,
        ),
      );
      return;
    }
    if (node is! md.Element) {
      return;
    }
    // 行内样式可叠加：每一层只翻转自己的那个标记，其余沿用外层。
    void childrenWith({
      bool bold = false,
      bool italic = false,
      bool code = false,
      bool strikethrough = false,
      String? href,
    }) {
      for (final child in node.children ?? const <md.Node>[]) {
        walk(
          child,
          bold: bold,
          italic: italic,
          code: code,
          strikethrough: strikethrough,
          href: href,
        );
      }
    }

    switch (node.tag) {
      case 'strong':
      case 'b':
        childrenWith(
          bold: true,
          italic: italic,
          code: code,
          strikethrough: strikethrough,
          href: href,
        );
      case 'em':
      case 'i':
        childrenWith(
          bold: bold,
          italic: true,
          code: code,
          strikethrough: strikethrough,
          href: href,
        );
      case 'del':
      case 's':
      case 'strike':
        childrenWith(
          bold: bold,
          italic: italic,
          code: code,
          strikethrough: true,
          href: href,
        );
      case 'code':
        // 行内代码内部不再解析：`*` 在代码里就是星号。内容同样是 HTML 转义过的。
        runs.add(
          MarkdownRun(
            _decodeHtmlEntities(node.textContent),
            bold: bold,
            italic: italic,
            code: true,
            strikethrough: strikethrough,
            href: href,
          ),
        );
      case 'a':
        childrenWith(
          bold: bold,
          italic: italic,
          code: code,
          strikethrough: strikethrough,
          href: node.attributes['href'],
        );
      case 'br':
        runs.add(
          MarkdownRun(
            '\n',
            bold: bold,
            italic: italic,
            code: code,
            strikethrough: strikethrough,
            href: href,
          ),
        );
      case 'img':
        final alt = node.attributes['alt'];
        runs.add(
          MarkdownRun(
            alt == null || alt.isEmpty ? '[图片]' : '[图片：$alt]',
            bold: bold,
            italic: italic,
            strikethrough: strikethrough,
            href: href,
          ),
        );
      case 'input':
        break;
      default:
        childrenWith(
          bold: bold,
          italic: italic,
          code: code,
          strikethrough: strikethrough,
          href: href,
        );
    }
  }

  for (final node in nodes) {
    walk(
      node,
      bold: bold,
      italic: italic,
      code: code,
      strikethrough: strikethrough,
      href: href,
    );
  }

  // 合并相邻同样式片段：`**a****b**` 这种输入会给出两个相邻粗体片段。
  final merged = <MarkdownRun>[];
  for (final run in runs) {
    if (run.text.isEmpty) {
      continue;
    }
    if (merged.isNotEmpty && merged.last.sameStyleAs(run)) {
      final previous = merged.removeLast();
      merged.add(
        MarkdownRun(
          previous.text + run.text,
          bold: run.bold,
          italic: run.italic,
          code: run.code,
          strikethrough: run.strikethrough,
          href: run.href,
        ),
      );
      continue;
    }
    merged.add(run);
  }
  return merged;
}


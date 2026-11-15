/// 预览/PDF 的左右分栏：把一份 Markdown 源码按平衡的行数切成 N 栏。
///
/// 为什么按行切而不是按 AST：预览交给 `gpt_markdown` 只吃字符串，拿不到块级
/// 结构；按"顶层空行"切块、按字符数均衡，能保证：
///
///  * 不把围栏代码块/块级公式切到两栏（进出 fence 的行数配对）；
///  * 不丢行：去掉的只是分栏处的空行，`join('\n')` 的文本内容与原文一致；
///  * 每一栏都非空（分栏数大于可用块数时返回实际能分的栏数）。
library;

/// 把 [source] 切成 [columns] 栏，返回的每一栏都是完整的 Markdown 片段。
List<String> splitMarkdownIntoColumns(String source, int columns) {
  if (columns <= 1 || source.trim().isEmpty) {
    return <String>[source];
  }
  final lines = source.split('\n');
  final totalChars = source.length;
  final target = totalChars / columns;

  final chunks = <String>[];
  final buffer = <String>[];
  var inFence = false;
  String? fenceMarker;
  var accumulated = 0;
  var columnIndex = 1;

  void flush() {
    final text = buffer.join('\n');
    if (text.trim().isNotEmpty) {
      chunks.add(text);
    }
    buffer.clear();
  }

  for (final line in lines) {
    final trimmed = line.trimLeft();
    final openFence = trimmed.startsWith('```')
        ? '```'
        : trimmed.startsWith('~~~')
            ? '~~~'
            : null;
    if (openFence != null) {
      if (!inFence) {
        inFence = true;
        fenceMarker = openFence;
      } else if (fenceMarker == openFence) {
        inFence = false;
        fenceMarker = null;
      }
      buffer.add(line);
      accumulated += line.length + 1;
      continue;
    }

    // 只在围栏之外、空行处换栏；这样块级公式/代码/表格不会被拆开。
    if (line.trim().isEmpty && !inFence) {
      if (columnIndex < columns && accumulated >= target * columnIndex) {
        flush();
        columnIndex += 1;
        accumulated = 0;
        continue;
      }
    }
    buffer.add(line);
    accumulated += line.length + 1;
  }
  flush();
  return chunks.isEmpty ? <String>[source] : chunks;
}

/// PDF 双栏排页（纯计算）：测量在 exporter 里做，这里只决定"哪个块上哪一页
/// 哪一栏"。
///
/// 为什么需要自己分页：`pdf` 包的 `Partitions` 是"两条互相独立的栏流"（左栏
/// 排到页底后，下一段继续在下一页左栏，不会回到本页右栏），`Row` 又不可跨页；
/// 而 Markdown 文档要的是报纸式阅读顺序——本页左栏排满→本页右栏→下一页。
/// 所以分页必须自己算，`pdf` 包只负责把每页画出来。
///
/// 本文件是纯函数（不碰字体、不碰控件），所以可以直接单测；高度由调用方用
/// `pdf` 包自己的 layout 测量后传进来，不是按字数猜的。
///
/// 已知限制：
///
///  * 分页粒度是"顶层块"（列表按项拆开）；一个块不会被切到两栏/两页里，
///    所以超长代码块/大表格要么通栏独占一页，要么（比整页还高时）让调用方
///    退回单栏；
///  * 标题"带下一块"只做一次前移：标题在栏底时搬到下一栏/下一页顶部，搬过去
///    放不下就留在原地（不递归腾挪）。
library;

/// 每栏宽度：正文宽度减去栏缝后平分。
///
/// 双栏时就是 `(contentWidth - gap) / 2`；栏缝只占两栏之间的空隙，不靠
/// `Expanded` 把内容硬挤成两栏，因此不会出现"半栏宽度 + 半栏宽度 + 栏缝 >
/// 正文宽度"导致页面溢出。
double pdfColumnWidth({
  required double contentWidth,
  required double gap,
  required int columns,
}) {
  if (columns <= 1) {
    return contentWidth;
  }
  return (contentWidth - gap * (columns - 1)) / columns;
}

/// 一个排版单元（顶层块；列表按项拆开）的高度信息。
class ColumnBlockHeight {
  const ColumnBlockHeight(
    this.height, {
    this.isHeading = false,
    this.wideHeight,
  });

  /// 在"栏宽"下测出的高度。
  final double height;

  /// 标题（用于"标题不落在栏底"的前移规则）。
  final bool isHeading;

  /// 非 null = 这个块半栏放不下、但整页（通栏宽）放得下，需要独占一个
  /// 通栏页；值是在通栏宽度下测出的高度。
  final double? wideHeight;
}

/// 一页的分栏计划：`columns[i]` 是第 i 栏要放的单元下标（指向传入的高度
/// 列表）。
///
/// [isWide] 为 true 时是"通栏页"：`columns` 只有一个元素，里面只放一个块
/// （超长代码块/大表格），不画栏缝。
class PdfColumnPagePlan {
  const PdfColumnPagePlan(this.columns, {this.isWide = false});

  final List<List<int>> columns;
  final bool isWide;
}

/// 把按顺序排好的块装进"每页 [columnCount] 栏"。
///
/// 返回 null 表示拿不到可靠分页：有块比整页还高（且没被调用方标成通栏），
/// 或通栏后仍比整页高——这种情况调用方必须退回单栏（单栏能跨页切块）。
List<PdfColumnPagePlan>? paginateColumnBlocks({
  required List<ColumnBlockHeight> blocks,
  required double columnHeight,
  required double pageHeight,
  required int columnCount,
}) {
  if (columnCount < 2 || columnHeight <= 0 || pageHeight <= 0) {
    return null;
  }

  final pages = <PdfColumnPagePlan>[];
  var current = List<List<int>>.generate(columnCount, (_) => <int>[]);
  var column = 0;
  var used = 0.0;

  void finishPage() {
    if (current.any((List<int> indexes) => indexes.isNotEmpty)) {
      pages.add(PdfColumnPagePlan(current));
    }
    current = List<List<int>>.generate(columnCount, (_) => <int>[]);
    column = 0;
    used = 0.0;
  }

  for (var index = 0; index < blocks.length; index++) {
    final block = blocks[index];
    final wideHeight = block.wideHeight;
    if (wideHeight != null) {
      // 通栏块独占一页：先把手上的页收尾，再插一个通栏页。
      if (wideHeight > pageHeight + 1e-9) {
        return null;
      }
      finishPage();
      pages.add(
        PdfColumnPagePlan(<List<int>>[
          <int>[index]
        ], isWide: true),
      );
      continue;
    }
    if (block.height > pageHeight + 1e-9 ||
        block.height > columnHeight + 1e-9) {
      // 调用方应先把"半栏放不下"的块标成通栏；没标说明分页不可靠。
      return null;
    }
    if (used + block.height > columnHeight + 1e-9) {
      if (column + 1 < columnCount) {
        column += 1;
        used = 0.0;
      } else {
        finishPage();
      }
    }
    current[column].add(index);
    used += block.height;
  }
  finishPage();

  if (pages.isEmpty) {
    return pages;
  }
  return _pullHeadingsForward(pages, blocks, columnHeight);
}

/// 标题不留在栏底：如果一栏的最后一个块是标题，而下一栏（或下一页第一栏）
/// 还放得下它，就把标题搬到那边顶部。
///
/// 只搬一层，不做递归腾挪；搬过去放不下就保持原样（见文件头"已知限制"）。
List<PdfColumnPagePlan> _pullHeadingsForward(
  List<PdfColumnPagePlan> pages,
  List<ColumnBlockHeight> blocks,
  double columnHeight,
) {
  final result = <PdfColumnPagePlan>[
    for (final page in pages)
      PdfColumnPagePlan(
        <List<int>>[
          for (final indexes in page.columns) List<int>.of(indexes),
        ],
        isWide: page.isWide,
      ),
  ];

  double heightOf(List<int> indexes) =>
      indexes.fold<double>(0, (sum, index) => sum + blocks[index].height);

  for (var pageIndex = 0; pageIndex < result.length; pageIndex++) {
    final page = result[pageIndex];
    if (page.isWide) {
      continue;
    }
    for (var columnIndex = 0;
        columnIndex < page.columns.length;
        columnIndex++) {
      final indexes = page.columns[columnIndex];
      if (indexes.isEmpty) {
        continue;
      }
      final last = indexes.last;
      if (!blocks[last].isHeading) {
        continue;
      }
      List<int>? next;
      if (columnIndex + 1 < page.columns.length) {
        next = page.columns[columnIndex + 1];
      } else if (pageIndex + 1 < result.length &&
          !result[pageIndex + 1].isWide) {
        next = result[pageIndex + 1].columns.first;
      }
      if (next == null) {
        continue;
      }
      if (heightOf(next) + blocks[last].height > columnHeight + 1e-9) {
        continue;
      }
      indexes.removeLast();
      next.insert(0, last);
    }
  }

  // 搬走标题可能留下全空页；空页不该进 PDF。
  result.removeWhere(
    (PdfColumnPagePlan page) =>
        !page.isWide &&
        page.columns.every((List<int> indexes) => indexes.isEmpty),
  );
  return result;
}

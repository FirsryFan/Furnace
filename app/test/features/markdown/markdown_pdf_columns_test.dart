// PDF 双栏分页的纯计算测试：栏宽公式、按顺序装栏/翻页、通栏页、标题前移。
//
// 这里不碰字体/PDF 字节，只钉"哪个块上哪一页哪一栏"；真正的 PDF 渲染在
// markdown_pdf_exporter_test.dart 里断言。
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/markdown/domain/markdown_pdf_columns.dart';

void main() {
  test('栏宽公式：双栏是 (contentWidth - gap) / 2，三栏按栏缝数扣', () {
    // 500 - 24 = 476，两栏各 238。
    expect(
      pdfColumnWidth(contentWidth: 500, gap: 24, columns: 2),
      closeTo(238, 1e-9),
    );
    // 500 - 24*2 = 452，三栏各 150.666…
    expect(
      pdfColumnWidth(contentWidth: 500, gap: 24, columns: 3),
      closeTo(452 / 3, 1e-9),
    );
    // 单栏 = 正文宽度。
    expect(pdfColumnWidth(contentWidth: 500, gap: 24, columns: 1), 500);
  });

  test('按顶层块顺序装栏：左栏装满→右栏→下一页', () {
    final plan = paginateColumnBlocks(
      blocks: const <ColumnBlockHeight>[
        ColumnBlockHeight(40),
        ColumnBlockHeight(40),
        ColumnBlockHeight(40),
        ColumnBlockHeight(40),
        ColumnBlockHeight(40),
      ],
      columnHeight: 100,
      pageHeight: 400,
      columnCount: 2,
    );

    expect(plan, isNotNull);
    expect(plan!.length, 2);
    expect(plan[0].isWide, isFalse);
    // 40+40 装满左栏；接下来两块进右栏；最后一块翻到下一页左栏。
    expect(plan[0].columns[0], <int>[0, 1]);
    expect(plan[0].columns[1], <int>[2, 3]);
    expect(plan[1].columns[0], <int>[4]);
    expect(plan[1].columns[1], isEmpty);
  });

  test('块高度跨栏/跨页时顺序不丢', () {
    final plan = paginateColumnBlocks(
      blocks: const <ColumnBlockHeight>[
        ColumnBlockHeight(70),
        ColumnBlockHeight(60),
        ColumnBlockHeight(35),
        ColumnBlockHeight(35),
        ColumnBlockHeight(35),
      ],
      columnHeight: 100,
      pageHeight: 400,
      columnCount: 2,
    )!;

    // 阅读顺序：把每页每栏展开后必须还是 0,1,2,3,4。
    final order = <int>[
      for (final page in plan)
        if (!page.isWide)
          for (final column in page.columns) ...column
        else
          ...page.columns.single,
    ];
    expect(order, <int>[0, 1, 2, 3, 4]);
    for (final page in plan) {
      for (final column in page.columns) {
        final height = column.fold<double>(
          0,
          (sum, index) => sum + <double>[70, 60, 35, 35, 35][index],
        );
        expect(height, lessThanOrEqualTo(100 + 1e-9));
      }
    }
  });

  test('半栏放不下、整页放得下的块 → 通栏独占一页', () {
    final plan = paginateColumnBlocks(
      blocks: const <ColumnBlockHeight>[
        ColumnBlockHeight(30),
        ColumnBlockHeight(120, wideHeight: 300),
        ColumnBlockHeight(30),
      ],
      columnHeight: 100,
      pageHeight: 400,
      columnCount: 2,
    )!;

    expect(plan.length, 3);
    expect(plan[0].isWide, isFalse);
    expect(plan[0].columns[0], <int>[0]);
    expect(plan[1].isWide, isTrue);
    expect(plan[1].columns.single, <int>[1]);
    expect(plan[2].columns[0], <int>[2]);
  });

  test('比整页还高的块 → 返回 null（调用方退回单栏）', () {
    expect(
      paginateColumnBlocks(
        blocks: const <ColumnBlockHeight>[
          ColumnBlockHeight(120, wideHeight: 500),
        ],
        columnHeight: 100,
        pageHeight: 400,
        columnCount: 2,
      ),
      isNull,
    );
  });

  test('没标通栏、却比半栏还高的块 → 返回 null，不猜', () {
    expect(
      paginateColumnBlocks(
        blocks: const <ColumnBlockHeight>[ColumnBlockHeight(150)],
        columnHeight: 100,
        pageHeight: 400,
        columnCount: 2,
      ),
      isNull,
    );
  });

  test('标题不落栏底：搬到下一栏顶部', () {
    final plan = paginateColumnBlocks(
      blocks: const <ColumnBlockHeight>[
        ColumnBlockHeight(60), // 正文
        ColumnBlockHeight(20, isHeading: true), // 标题落在左栏底
        ColumnBlockHeight(60), // 正文
      ],
      columnHeight: 100,
      pageHeight: 200,
      columnCount: 2,
    )!;

    expect(plan.length, 1);
    // 左栏只剩正文，标题搬到右栏顶部（60+20 <= 100）。
    expect(plan[0].columns[0], <int>[0]);
    expect(plan[0].columns[1], <int>[1, 2]);
  });

  test('标题搬到下一栏放不下时留在原地，不硬塞', () {
    final plan = paginateColumnBlocks(
      blocks: const <ColumnBlockHeight>[
        ColumnBlockHeight(60),
        ColumnBlockHeight(20, isHeading: true),
        ColumnBlockHeight(90),
      ],
      columnHeight: 100,
      pageHeight: 200,
      columnCount: 2,
    )!;

    expect(plan[0].columns[0], <int>[0, 1]);
    expect(plan[0].columns[1], <int>[2]);
  });

  test('空文档返回空计划（不是 null）', () {
    final plan = paginateColumnBlocks(
      blocks: const <ColumnBlockHeight>[],
      columnHeight: 100,
      pageHeight: 400,
      columnCount: 2,
    );
    expect(plan, isNotNull);
    expect(plan, isEmpty);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/questions/question_stem_image_plan.dart';
import 'package:furnace/domain/services/questions/question_stem_segments.dart';

QuestionStemSegment textSegment(String text) => QuestionStemSegment.text(text);

QuestionStemSegment imageSegment(int order) => QuestionStemSegment.image(order);

List<int> imageOrdersOf(QuestionStemRenderPlan plan) => <int>[
      for (final QuestionStemSegment segment in plan.segments)
        if (segment.isImage) segment.imageOrder!,
    ];

String textOf(QuestionStemRenderPlan plan) => plan.segments
    .where((QuestionStemSegment segment) => segment.isText)
    .map((QuestionStemSegment segment) => segment.text)
    .join();

void main() {
  group('A：没有题干图（none 模式）', () {
    test('imageCount 0 且无占位：一个文字段、没有图', () {
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        '求 x 的值。',
        imageCount: 0,
      );
      expect(plan.mode, QuestionStemImageMode.none);
      expect(plan.segments, <QuestionStemSegment>[textSegment('求 x 的值。')]);
      expect(plan.trailingImageOrders, isEmpty);
      expect(plan.snapshotImageOrders, isEmpty);
      expect(plan.imageCount, 0);
      expect(plan.placeholderCount, 0);
      expect(plan.referencedImageCount, 0);
      expect(plan.neutralizedPlaceholderCount, 0);
      expect(plan.hasImages, isFalse);
      expect(plan.isSnapshot, isFalse);
      expect(plan.hasTrailingImages, isFalse);
      expect(plan.hasNeutralizedPlaceholders, isFalse);
    });

    test('imageCount 0 但有占位：统计占位次数、绝不改写原文', () {
      const String stem = '如图［图1］所示，再看［图2］';
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        stem,
        imageCount: 0,
      );
      expect(plan.mode, QuestionStemImageMode.none);
      expect(plan.placeholderCount, 2);
      expect(plan.neutralizedPlaceholderCount, 0);
      expect(plan.segments, <QuestionStemSegment>[textSegment(stem)]);
    });

    test('负数 imageCount 归一成 0', () {
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        '题干［图1］',
        imageCount: -3,
      );
      expect(plan.mode, QuestionStemImageMode.none);
      expect(plan.imageCount, 0);
      expect(plan.placeholderCount, 1);
      expect(plan.neutralizedPlaceholderCount, 0);
      expect(plan.segments, <QuestionStemSegment>[textSegment('题干［图1］')]);
    });

    test('空题干不抛，返回一个空文字段', () {
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        '',
        imageCount: 0,
      );
      expect(plan.mode, QuestionStemImageMode.none);
      expect(plan.segments.length, 1);
      expect(textOf(plan), '');
    });
  });

  group('B1：尺寸触发的整卡快照', () {
    test('实测 1640x808 整卡截图 + 12 处占位：全部放末尾、正文只留 …', () {
      final String stem = List<String>.generate(
        12,
        (int index) => '［图${index + 1}］',
      ).join();
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        stem,
        imageCount: 1,
        imageSizes: const <QuestionStemImageSize?>[
          QuestionStemImageSize(1640, 808),
        ],
      );
      expect(plan.mode, QuestionStemImageMode.snapshot);
      expect(plan.isSnapshot, isTrue);
      expect(plan.trailingImageOrders, <int>[0]);
      expect(plan.snapshotImageOrders, <int>[0]);
      expect(plan.hasTrailingImages, isTrue);
      expect(imageOrdersOf(plan), isEmpty);
      expect(plan.segments.length, 1);
      expect(textOf(plan), '…' * 12);
      expect(plan.placeholderCount, 12);
      expect(plan.neutralizedPlaceholderCount, 12);
      expect(plan.hasNeutralizedPlaceholders, isTrue);
      expect(plan.referencedImageCount, 0);
    });

    test('多图且只有一张够大：所有图都进 trailing 且升序', () {
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        'A［图1］B［图2］C',
        imageCount: 2,
        imageSizes: const <QuestionStemImageSize?>[
          QuestionStemImageSize(1640, 808),
          QuestionStemImageSize(400, 300),
        ],
      );
      expect(plan.mode, QuestionStemImageMode.snapshot);
      expect(plan.trailingImageOrders, <int>[0, 1]);
      expect(plan.snapshotImageOrders, <int>[0]);
      expect(imageOrdersOf(plan), isEmpty);
      expect(textOf(plan), 'A…B…C');
      expect(plan.neutralizedPlaceholderCount, 2);
    });

    test('阈值边界：1000x400 恰好触发', () {
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        '甲［图1］乙',
        imageCount: 1,
        imageSizes: const <QuestionStemImageSize?>[
          QuestionStemImageSize(1000, 400),
        ],
      );
      expect(plan.mode, QuestionStemImageMode.snapshot);
      expect(textOf(plan), '甲…乙');
    });

    test('宽 999 或高 399 不触发', () {
      final QuestionStemRenderPlan narrow = planQuestionStemRender(
        '甲［图1］乙',
        imageCount: 1,
        imageSizes: const <QuestionStemImageSize?>[
          QuestionStemImageSize(999, 400),
        ],
      );
      final QuestionStemRenderPlan short = planQuestionStemRender(
        '甲［图1］乙',
        imageCount: 1,
        imageSizes: const <QuestionStemImageSize?>[
          QuestionStemImageSize(1000, 399),
        ],
      );
      expect(narrow.mode, QuestionStemImageMode.inline);
      expect(short.mode, QuestionStemImageMode.inline);
    });

    test('大图在第 2 张也触发，snapshot 记录真实 order', () {
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        '甲［图1］乙［图2］',
        imageCount: 2,
        imageSizes: const <QuestionStemImageSize?>[
          QuestionStemImageSize(400, 300),
          QuestionStemImageSize(1640, 808),
        ],
      );
      expect(plan.mode, QuestionStemImageMode.snapshot);
      expect(plan.snapshotImageOrders, <int>[1]);
      expect(plan.trailingImageOrders, <int>[0, 1]);
      expect(textOf(plan), '甲…乙…');
    });

    test('尺寸列表首项是 null 时不影响后面的大图判定', () {
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        'A［图1］B［图2］C',
        imageCount: 2,
        imageSizes: const <QuestionStemImageSize?>[
          null,
          QuestionStemImageSize(1640, 808),
        ],
      );
      expect(plan.mode, QuestionStemImageMode.snapshot);
      expect(plan.snapshotImageOrders, <int>[1]);
    });

    test('order >= imageCount 的大尺寸被忽略：不会把小题判成快照', () {
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        '甲［图1］乙［图2］丙',
        imageCount: 2,
        imageSizes: const <QuestionStemImageSize?>[
          QuestionStemImageSize(400, 300),
          QuestionStemImageSize(400, 300),
          QuestionStemImageSize(1640, 808),
        ],
      );
      expect(plan.mode, QuestionStemImageMode.inline);
      expect(plan.snapshotImageOrders, isEmpty);
      expect(imageOrdersOf(plan), <int>[0, 1]);
    });

    test('snapshot 保留原空白、不做 trim', () {
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        '  引言［图1］尾注  ',
        imageCount: 1,
        imageSizes: const <QuestionStemImageSize?>[
          QuestionStemImageSize(1640, 808),
        ],
      );
      expect(plan.mode, QuestionStemImageMode.snapshot);
      expect(textOf(plan), '  引言…尾注  ');
    });

    test('snapshot 相邻文字合并成一个文字段', () {
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        'a［图1］b［图1］c',
        imageCount: 1,
        imageSizes: const <QuestionStemImageSize?>[
          QuestionStemImageSize(1640, 808),
        ],
      );
      expect(plan.segments.length, 1);
      expect(textOf(plan), 'a…b…c');
      expect(plan.placeholderCount, 2);
      expect(plan.neutralizedPlaceholderCount, 2);
    });

    test('B1 命中但题干没有占位：正文原样、不中性化', () {
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        '无占位题干',
        imageCount: 1,
        imageSizes: const <QuestionStemImageSize?>[
          QuestionStemImageSize(1640, 808),
        ],
      );
      expect(plan.mode, QuestionStemImageMode.snapshot);
      expect(textOf(plan), '无占位题干');
      expect(plan.placeholderCount, 0);
      expect(plan.neutralizedPlaceholderCount, 0);
      expect(plan.hasNeutralizedPlaceholders, isFalse);
      expect(plan.trailingImageOrders, <int>[0]);
    });

    test('空题干 + 大图：不抛，正文没有文字段', () {
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        '',
        imageCount: 1,
        imageSizes: const <QuestionStemImageSize?>[
          QuestionStemImageSize(1640, 808),
        ],
      );
      expect(plan.mode, QuestionStemImageMode.snapshot);
      expect(plan.segments, isEmpty);
      expect(plan.trailingImageOrders, <int>[0]);
    });

    test('自定义阈值参与判定', () {
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        '甲［图1］乙',
        imageCount: 1,
        imageSizes: const <QuestionStemImageSize?>[
          QuestionStemImageSize(400, 300),
        ],
        snapshotMinWidth: 400,
        snapshotMinHeight: 300,
      );
      expect(plan.mode, QuestionStemImageMode.snapshot);
    });
  });

  group('B2：无尺寸时的数量兜底', () {
    test('无尺寸 + 1 图 + 2 占位 → snapshot', () {
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        '由［图1］可得［图2］',
        imageCount: 1,
      );
      expect(plan.mode, QuestionStemImageMode.snapshot);
      expect(plan.trailingImageOrders, <int>[0]);
      expect(plan.snapshotImageOrders, <int>[0]);
      expect(textOf(plan), '由…可得…');
      expect(plan.placeholderCount, 2);
      expect(plan.neutralizedPlaceholderCount, 2);
    });

    test('无尺寸 + 1 图 + 1 占位 → inline（B2 边界不成立）', () {
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        '如图［图1］所示',
        imageCount: 1,
      );
      expect(plan.mode, QuestionStemImageMode.inline);
      expect(plan.snapshotImageOrders, isEmpty);
      expect(imageOrdersOf(plan), <int>[0]);
      expect(plan.trailingImageOrders, isEmpty);
      expect(plan.referencedImageCount, 1);
    });

    test('无尺寸 + 2 图 + 2 占位 → inline（数量兜底只认 1 图）', () {
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        '［图1］与［图2］',
        imageCount: 2,
      );
      expect(plan.mode, QuestionStemImageMode.inline);
      expect(imageOrdersOf(plan), <int>[0, 1]);
      expect(plan.trailingImageOrders, isEmpty);
      expect(plan.referencedImageCount, 2);
    });

    test('尺寸列表全是 null + 1 图 + 2 占位 → snapshot', () {
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        '［图1］与［图2］',
        imageCount: 1,
        imageSizes: const <QuestionStemImageSize?>[null, null],
      );
      expect(plan.mode, QuestionStemImageMode.snapshot);
      expect(plan.trailingImageOrders, <int>[0]);
      expect(plan.snapshotImageOrders, <int>[0]);
    });

    test('有非空小尺寸时不走 B2（按尺寸判 inline）', () {
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        '［图1］与［图2］',
        imageCount: 1,
        imageSizes: const <QuestionStemImageSize?>[
          QuestionStemImageSize(400, 300),
        ],
      );
      expect(plan.mode, QuestionStemImageMode.inline);
      expect(imageOrdersOf(plan), <int>[0]);
      expect(textOf(plan), '与…');
      expect(plan.neutralizedPlaceholderCount, 1);
    });
  });

  group('C：inline 内联模式', () {
    test('两图两占位按题干顺序内联', () {
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        '题干［图1］中间［图2］结尾',
        imageCount: 2,
      );
      expect(plan.mode, QuestionStemImageMode.inline);
      expect(plan.segments, <QuestionStemSegment>[
        textSegment('题干'),
        imageSegment(0),
        textSegment('中间'),
        imageSegment(1),
        textSegment('结尾'),
      ]);
      expect(plan.referencedImageCount, 2);
      expect(plan.trailingImageOrders, isEmpty);
      expect(plan.neutralizedPlaceholderCount, 0);
    });

    test('占位顺序换位时按占位位置排图片段', () {
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        '［图2］先［图1］后',
        imageCount: 2,
      );
      expect(imageOrdersOf(plan), <int>[1, 0]);
      expect(plan.referencedImageCount, 2);
      expect(textOf(plan), '先后');
    });

    test('同一张图被重复引用：每处都内联、引用计数只算一次', () {
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        '［图1］甲［图1］',
        imageCount: 2,
      );
      expect(imageOrdersOf(plan), <int>[0, 0]);
      expect(plan.referencedImageCount, 1);
      expect(plan.trailingImageOrders, <int>[1]);
    });

    test('没被引用的图进 trailing（升序）', () {
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        '只看［图1］［图3］',
        imageCount: 3,
      );
      expect(imageOrdersOf(plan), <int>[0, 2]);
      expect(plan.trailingImageOrders, <int>[1]);
      expect(plan.referencedImageCount, 2);
      expect(plan.hasTrailingImages, isTrue);
    });

    test('越界占位中性化成 … 并计入 neutralized', () {
      // 传一张已知小尺寸，避免 1 图 + 2 占位触发 B2 数量兜底。
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        'a［图2］b［图0］c',
        imageCount: 1,
        imageSizes: const <QuestionStemImageSize?>[
          QuestionStemImageSize(400, 300),
        ],
      );
      expect(plan.mode, QuestionStemImageMode.inline);
      expect(plan.segments.length, 1);
      expect(textOf(plan), 'a…b…c');
      expect(plan.placeholderCount, 2);
      expect(plan.neutralizedPlaceholderCount, 2);
      expect(plan.referencedImageCount, 0);
      expect(plan.trailingImageOrders, <int>[0]);
    });

    test('全角数字与【图1】都识别为占位', () {
      // 传一张已知小尺寸，避免 1 图 + 2 占位触发 B2 数量兜底。
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        '【图１】甲[图 1]',
        imageCount: 1,
        imageSizes: const <QuestionStemImageSize?>[
          QuestionStemImageSize(400, 300),
        ],
      );
      expect(imageOrdersOf(plan), <int>[0, 0]);
      expect(plan.referencedImageCount, 1);
      expect(textOf(plan), '甲');
      expect(plan.neutralizedPlaceholderCount, 0);
    });

    test('三位数占位与带前导零的占位都能识别', () {
      final QuestionStemRenderPlan hundred = planQuestionStemRender(
        '［图100］',
        imageCount: 100,
      );
      final QuestionStemRenderPlan zeroPadded = planQuestionStemRender(
        '［图01］',
        imageCount: 2,
      );
      expect(imageOrdersOf(hundred), <int>[99]);
      expect(imageOrdersOf(zeroPadded), <int>[0]);
    });

    test('题干没有占位：图全部进 trailing，引用数为 0', () {
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        '纯文字题干',
        imageCount: 2,
      );
      expect(plan.mode, QuestionStemImageMode.inline);
      expect(plan.segments, <QuestionStemSegment>[textSegment('纯文字题干')]);
      expect(plan.trailingImageOrders, <int>[0, 1]);
      expect(plan.referencedImageCount, 0);
      expect(plan.placeholderCount, 0);
    });

    test('题干只有占位：没有空文字段', () {
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        '［图1］',
        imageCount: 1,
      );
      expect(plan.segments, <QuestionStemSegment>[imageSegment(0)]);
      expect(textOf(plan), '');
      expect(plan.trailingImageOrders, isEmpty);
      expect(plan.referencedImageCount, 1);
    });

    test('尺寸 0 或负数不影响内联判定', () {
      final QuestionStemRenderPlan zero = planQuestionStemRender(
        '［图1］',
        imageCount: 1,
        imageSizes: const <QuestionStemImageSize?>[
          QuestionStemImageSize(0, 0),
        ],
      );
      final QuestionStemRenderPlan negative = planQuestionStemRender(
        '［图1］',
        imageCount: 1,
        imageSizes: const <QuestionStemImageSize?>[
          QuestionStemImageSize(-5, -5),
        ],
      );
      expect(zero.mode, QuestionStemImageMode.inline);
      expect(negative.mode, QuestionStemImageMode.inline);
    });

    test('尺寸数组比图数短也不影响内联', () {
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        '［图1］［图2］［图3］',
        imageCount: 3,
        imageSizes: const <QuestionStemImageSize?>[
          QuestionStemImageSize(400, 300),
        ],
      );
      expect(plan.mode, QuestionStemImageMode.inline);
      expect(imageOrdersOf(plan), <int>[0, 1, 2]);
      expect(plan.referencedImageCount, 3);
      expect(plan.trailingImageOrders, isEmpty);
    });

    test('有效占位与越界占位混用：计数各归各', () {
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        '［图1］［图5］［图2］',
        imageCount: 2,
      );
      expect(imageOrdersOf(plan), <int>[0, 1]);
      expect(textOf(plan), '…');
      expect(plan.placeholderCount, 3);
      expect(plan.neutralizedPlaceholderCount, 1);
      expect(plan.referencedImageCount, 2);
      expect(plan.trailingImageOrders, isEmpty);
    });

    test('相同输入两次得到相等的计划（确定性）', () {
      const String stem = '题干［图1］中间［图3］';
      const List<QuestionStemImageSize?> sizes = <QuestionStemImageSize?>[
        QuestionStemImageSize(400, 300),
        QuestionStemImageSize(200, 100),
        QuestionStemImageSize(300, 200),
      ];
      final QuestionStemRenderPlan first = planQuestionStemRender(
        stem,
        imageCount: 3,
        imageSizes: sizes,
      );
      final QuestionStemRenderPlan second = planQuestionStemRender(
        stem,
        imageCount: 3,
        imageSizes: sizes,
      );
      expect(second, first);
      expect(second.hashCode, first.hashCode);
    });
  });

  group('不可变、值语义与常量', () {
    test('snapshot 计划的三个列表都不可修改', () {
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        '甲［图1］乙［图2］',
        imageCount: 1,
        imageSizes: const <QuestionStemImageSize?>[
          QuestionStemImageSize(1640, 808),
        ],
      );
      expect(
        () => plan.segments.add(textSegment('x')),
        throwsUnsupportedError,
      );
      expect(() => plan.trailingImageOrders.add(9), throwsUnsupportedError);
      expect(() => plan.snapshotImageOrders.add(9), throwsUnsupportedError);
    });

    test('inline 计划的两个空列表也不可修改', () {
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        '［图1］',
        imageCount: 3,
      );
      expect(() => plan.snapshotImageOrders.add(0), throwsUnsupportedError);
      expect(() => plan.trailingImageOrders.add(1), throwsUnsupportedError);
    });

    test('相等性：同一输入相等，不同模式不等', () {
      final QuestionStemRenderPlan inline = planQuestionStemRender(
        '［图1］',
        imageCount: 1,
      );
      final QuestionStemRenderPlan sameInline = planQuestionStemRender(
        '［图1］',
        imageCount: 1,
      );
      final QuestionStemRenderPlan snapshot = planQuestionStemRender(
        '［图1］',
        imageCount: 1,
        imageSizes: const <QuestionStemImageSize?>[
          QuestionStemImageSize(1640, 808),
        ],
      );
      expect(sameInline, inline);
      expect(sameInline.hashCode, inline.hashCode);
      expect(snapshot, isNot(inline));
      expect(snapshot.mode, QuestionStemImageMode.snapshot);
      expect(snapshot.toString(), contains('snapshot'));
      expect(inline.toString(), contains('QuestionStemRenderPlan'));
    });

    test('QuestionStemImageSize 是值对象', () {
      const QuestionStemImageSize a = QuestionStemImageSize(1640, 808);
      const QuestionStemImageSize b = QuestionStemImageSize(1640, 808);
      const QuestionStemImageSize c = QuestionStemImageSize(808, 1640);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a.toString(), 'QuestionStemImageSize(1640 x 808)');
    });

    test('snapshot 不变量：正文无图片段，快照下标都在 trailing 里', () {
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        'A［图1］B［图2］C',
        imageCount: 2,
        imageSizes: const <QuestionStemImageSize?>[
          QuestionStemImageSize(1640, 808),
          QuestionStemImageSize(1640, 808),
        ],
      );
      expect(plan.segments.every((QuestionStemSegment s) => s.isText), isTrue);
      expect(plan.snapshotImageOrders, <int>[0, 1]);
      for (final int order in plan.snapshotImageOrders) {
        expect(plan.trailingImageOrders, contains(order));
      }
      expect(plan.trailingImageOrders.length, plan.imageCount);
    });

    test('默认阈值常量是 1000x400', () {
      expect(defaultStemSnapshotMinWidth, 1000);
      expect(defaultStemSnapshotMinHeight, 400);
    });
  });

  group('B0：fullcard_ 前缀优先判整卡快照（handoff 管线 v1 §4.6）', () {
    test('尺寸不够但文件名带 fullcard_：仍按快照处理', () {
      const String stem = '一、选择题［图1］\n如图所示的电路中，电源电动势为 E。';
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        stem,
        imageCount: 1,
        imageSizes: const <QuestionStemImageSize?>[
          QuestionStemImageSize(800, 300),
        ],
        hasFullcardImage: true,
      );
      expect(plan.mode, QuestionStemImageMode.snapshot);
      expect(plan.snapshotImageOrders, <int>[0]);
      expect(plan.trailingImageOrders, <int>[0]);
      expect(plan.neutralizedPlaceholderCount, 1);
      expect(textOf(plan), isNot(contains('［图1］')));
      expect(
        plan.segments.every((QuestionStemSegment s) => s.isText),
        isTrue,
        reason: '快照模式正文里不内联插图',
      );
    });

    test('同一尺寸、没有 fullcard_ 时仍是 inline（对照）', () {
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        '题干［图1］后续文字',
        imageCount: 1,
        imageSizes: const <QuestionStemImageSize?>[
          QuestionStemImageSize(800, 300),
        ],
      );
      expect(plan.mode, QuestionStemImageMode.inline);
      expect(plan.snapshotImageOrders, isEmpty);
    });

    test('fullcard_ 与已知大尺寸同时存在：快照图下标优先给命中尺寸的那张', () {
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        '题干［图1］［图2］',
        imageCount: 2,
        imageSizes: const <QuestionStemImageSize?>[
          QuestionStemImageSize(300, 200),
          QuestionStemImageSize(1640, 900),
        ],
        hasFullcardImage: true,
      );
      expect(plan.mode, QuestionStemImageMode.snapshot);
      expect(plan.snapshotImageOrders, <int>[1]);
      expect(plan.trailingImageOrders, <int>[0, 1]);
    });

    test('没有题干图时 fullcard_ 不改变 none 判定', () {
      final QuestionStemRenderPlan plan = planQuestionStemRender(
        '纯文本题干',
        imageCount: 0,
        hasFullcardImage: true,
      );
      expect(plan.mode, QuestionStemImageMode.none);
      expect(plan.segments, <QuestionStemSegment>[textSegment('纯文本题干')]);
    });
  });
}

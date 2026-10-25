import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart' show Offset, Size;
import 'package:furnace/features/cognitive/presentation/cognitive_graph_layout.dart';

/// 「知识网络图」的布局是纯函数：同一份数据必须永远画出同一张图，否则截图会漂、
/// 测试也没法断言。v2 的口径是**按标签分簇**：钉住确定性、簇的归属与间距、
/// 无标签知识点在中心、坐标不越界、以及命中测试。
void main() {
  const size = Size(800, 800);
  const points = <CognitiveGraphPointInput>[
    CognitiveGraphPointInput(
      id: 'kp-1',
      title: '二次函数',
      cardCount: 3,
      tagIds: <String>{'tag-a'},
    ),
    CognitiveGraphPointInput(
      id: 'kp-2',
      title: '条件概率',
      cardCount: 1,
      tagIds: <String>{'tag-a', 'tag-b'},
    ),
    CognitiveGraphPointInput(
      id: 'kp-3',
      title: '牛顿定律',
      cardCount: 2,
      tagIds: <String>{'tag-b'},
    ),
  ];
  const tags = <CognitiveGraphTagInput>[
    CognitiveGraphTagInput(id: 'tag-a', title: '函数'),
    CognitiveGraphTagInput(id: 'tag-b', title: '概率'),
  ];

  CognitiveGraphLayout layoutOf({
    Size canvas = size,
    List<CognitiveGraphPointInput> graphPoints = points,
    List<CognitiveGraphTagInput> graphTags = tags,
  }) =>
      layoutCognitiveGraph(
        size: canvas,
        points: graphPoints,
        tags: graphTags,
      );

  test('同一份输入画两次是同一张图（确定性）', () {
    final first = layoutOf();
    final second = layoutOf();

    expect(
      first.points.map((point) => point.center).toList(),
      second.points.map((point) => point.center).toList(),
    );
    expect(
      first.tags.map((tag) => tag.center).toList(),
      second.tags.map((tag) => tag.center).toList(),
    );
    expect(
      first.tags.map((tag) => tag.clusterCenter).toList(),
      second.tags.map((tag) => tag.clusterCenter).toList(),
    );
  });

  test('按主标签分簇：函数/概率两个簇中心离得远，同簇成员围绕各自簇中心', () {
    final layout = layoutOf();
    final functionTag = layout.tags.firstWhere((tag) => tag.id == 'tag-a');
    final probabilityTag = layout.tags.firstWhere((tag) => tag.id == 'tag-b');

    // 两个簇不重叠：中心相距超过一个簇半径量级。
    expect(
      (functionTag.clusterCenter - probabilityTag.clusterCenter).distance,
      greaterThan(100),
    );

    // 每个知识点只进一个簇：主标签是它挂的标签里按标题排序的第一个。
    final one = layout.points.firstWhere((point) => point.id == 'kp-1');
    final two = layout.points.firstWhere((point) => point.id == 'kp-2');
    final three = layout.points.firstWhere((point) => point.id == 'kp-3');
    expect(one.groupTagId, 'tag-a');
    expect(two.groupTagId, 'tag-a');
    expect(three.groupTagId, 'tag-b');

    // 同簇成员都在簇半径内（黄金角螺旋 r = 间距·√k 的最大半径）。
    for (final point in layout.points) {
      final tag = layout.tags.firstWhere((tag) => tag.id == point.groupTagId);
      expect(
        (point.center - tag.clusterCenter).distance,
        lessThanOrEqualTo(tag.clusterRadius + 1e-6),
      );
    }
    // 两个簇的点不会跑到对方簇里。
    expect(
      (one.center - three.center).distance,
      greaterThan(100),
    );
  });

  test('簇内任意两个知识点不重叠：圆心距离不短于间距常量', () {
    final layout = layoutOf();
    for (var i = 0; i < layout.points.length; i++) {
      for (var j = i + 1; j < layout.points.length; j++) {
        expect(
          (layout.points[i].center - layout.points[j].center).distance,
          greaterThanOrEqualTo(kCognitiveGraphPointSpacing - 1e-6),
        );
      }
    }
  });

  test('多标签知识点进了主标签的簇，但每个标签都拿到完整的挂载数', () {
    final layout = layoutOf();
    final functionTag = layout.tags.firstWhere((tag) => tag.id == 'tag-a');
    final probabilityTag = layout.tags.firstWhere((tag) => tag.id == 'tag-b');
    expect(functionTag.memberCount, 2);
    expect(probabilityTag.memberCount, 2);
    // 主成员数：tag-b 只有 kp-3 把它当主标签（kp-2 的主标签是函数）。
    expect(probabilityTag.clusterRadius, 0);
    expect(layout.links.length, 1 + 2 + 1);
    expect(layout.links.map((link) => link.tagId).toSet(), {'tag-a', 'tag-b'});
  });

  test('没有标签的知识点放在画布中心区', () {
    final layout = layoutOf(
      graphPoints: [
        ...points,
        const CognitiveGraphPointInput(
          id: 'kp-4',
          title: '自由落体',
          cardCount: 1,
        ),
      ],
    );
    final orphan = layout.points.firstWhere((point) => point.id == 'kp-4');
    expect(orphan.groupTagId, isNull);
    expect(
      (orphan.center - layout.center).distance,
      lessThanOrEqualTo(0.25 * size.shortestSide),
    );
  });

  test('标签名画在簇的外侧：离画布中心比簇中心更远', () {
    final layout = layoutOf();
    for (final tag in layout.tags) {
      expect(
        (tag.center - layout.center).distance,
        greaterThan((tag.clusterCenter - layout.center).distance),
      );
    }
  });

  test('卡片多的知识点画得更大', () {
    final layout = layoutOf();
    final three = layout.points.firstWhere((point) => point.id == 'kp-1');
    final one = layout.points.firstWhere((point) => point.id == 'kp-2');
    expect(three.radius, greaterThan(one.radius));
  });

  test('空输入不画图（也不除零）', () {
    expect(
      layoutCognitiveGraph(size: size, points: const [], tags: tags).isEmpty,
      isTrue,
    );
    final zero = layoutCognitiveGraph(
      size: Size.zero,
      points: points,
      tags: tags,
    );
    expect(zero.isEmpty, isTrue);
  });

  test('完全没挂标签时只有中心区的知识点，没有标签也没有连线', () {
    final layout = layoutOf(
      graphPoints: const [
        CognitiveGraphPointInput(id: 'kp-1', title: '甲', cardCount: 1),
        CognitiveGraphPointInput(id: 'kp-2', title: '乙', cardCount: 2),
      ],
    );
    expect(layout.tags, isEmpty);
    expect(layout.links, isEmpty);
    for (final point in layout.points) {
      expect(point.groupTagId, isNull);
      expect(
        (point.center - layout.center).distance,
        lessThanOrEqualTo(0.25 * size.shortestSide),
      );
    }
  });

  test('画布边长随知识点数增长，但有上限', () {
    expect(cognitiveGraphCanvasSide(0), kCognitiveGraphBaseSide);
    expect(cognitiveGraphCanvasSide(2), kCognitiveGraphBaseSide);
    expect(cognitiveGraphCanvasSide(15), kCognitiveGraphBaseSide);
    expect(cognitiveGraphCanvasSide(60), closeTo(1680, 1e-9));
    expect(cognitiveGraphCanvasSide(400), kCognitiveGraphMaxCanvasSide);
  });

  test('知识点更多时坐标不越界（大画布也一样）', () {
    const canvasSide = 1680.0;
    const manyTags = <CognitiveGraphTagInput>[
      CognitiveGraphTagInput(id: 'g-1', title: '甲'),
      CognitiveGraphTagInput(id: 'g-2', title: '乙'),
      CognitiveGraphTagInput(id: 'g-3', title: '丙'),
    ];
    final manyPoints = <CognitiveGraphPointInput>[
      for (var index = 0; index < 60; index++)
        CognitiveGraphPointInput(
          id: 'kp-$index',
          title: '知识点 $index',
          cardCount: index % 4,
          tagIds: <String>{manyTags[index % manyTags.length].id},
        ),
    ];
    final layout = layoutOf(
      canvas: const Size.square(canvasSide),
      graphPoints: manyPoints,
      graphTags: manyTags,
    );
    for (final point in layout.points) {
      expect(point.center.dx, inInclusiveRange(0, canvasSide));
      expect(point.center.dy, inInclusiveRange(0, canvasSide));
    }
    for (final tag in layout.tags) {
      final halfWidth = cognitiveGraphTagBoxWidth(tag) / 2;
      expect(tag.center.dx, greaterThanOrEqualTo(halfWidth));
      expect(tag.center.dx, lessThanOrEqualTo(canvasSide - halfWidth));
      expect(
        tag.center.dy,
        greaterThanOrEqualTo(kCognitiveGraphTagBoxHeight / 2),
      );
      expect(
        tag.center.dy,
        lessThanOrEqualTo(canvasSide - kCognitiveGraphTagBoxHeight / 2),
      );
    }
  });

  test('命中测试：点在节点上选中它，空白返回 null，标签也能命中', () {
    final layout = layoutOf();
    final point = layout.points.firstWhere((node) => node.id == 'kp-1');

    final hit = hitTestCognitiveGraph(layout, point.center);
    expect(hit?.point?.id, point.id);

    // 圆点外面留 14px 的额外半径（手指比圆点粗）。
    final near = hitTestCognitiveGraph(
      layout,
      point.center + const Offset(0, kGraphPointHitSlop + 2),
    );
    expect(near?.point?.id, point.id);

    // 画布中心：离所有知识点与标签都远。
    final misses = layout.points.every(
          (node) =>
              (node.center - layout.center).distance >
              node.radius + kGraphPointHitSlop,
        ) &&
        layout.tags.every(
          (tag) =>
              (tag.center - layout.center).distance >
              cognitiveGraphTagBoxWidth(tag) / 2 + kGraphTagHitSlop,
        );
    expect(misses, isTrue);
    expect(hitTestCognitiveGraph(layout, layout.center), isNull);

    // 标签方块中心命中标签，并带出挂载数。
    final tag = layout.tags.firstWhere((node) => node.id == 'tag-b');
    final tagHit = hitTestCognitiveGraph(layout, tag.center);
    expect(tagHit?.tag?.id, tag.id);
    expect(tagHit?.tag?.memberCount, 2);
  });
}

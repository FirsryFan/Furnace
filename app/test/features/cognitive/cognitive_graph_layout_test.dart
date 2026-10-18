import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart' show Offset, Size;
import 'package:furnace/features/cognitive/presentation/cognitive_graph_layout.dart';

/// 「知识网络图」的布局是纯函数：同一份数据必须永远画出同一张图，否则截图会漂、
/// 测试也没法断言。这里钉住四件事：确定性、节点在环上、标签在环内、命中测试。
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

  test('同一份输入画两次是同一张图（确定性）', () {
    final first = layoutCognitiveGraph(size: size, points: points, tags: tags);
    final second = layoutCognitiveGraph(size: size, points: points, tags: tags);

    expect(
      first.points.map((point) => point.center).toList(),
      second.points.map((point) => point.center).toList(),
    );
    expect(
      first.tags.map((tag) => tag.center).toList(),
      second.tags.map((tag) => tag.center).toList(),
    );
  });

  test('知识点在大小一致的外环上，标签在内环里，连线数=挂载数', () {
    final layout = layoutCognitiveGraph(size: size, points: points, tags: tags);

    expect(layout.center, const Offset(400, 400));
    expect(layout.outerRadius, greaterThan(layout.innerRadius));
    for (final point in layout.points) {
      expect((point.center - layout.center).distance,
          closeTo(layout.outerRadius, 1e-6));
      expect(point.radius, greaterThan(0));
    }
    for (final tag in layout.tags) {
      expect((tag.center - layout.center).distance,
          closeTo(layout.innerRadius, 1e-6));
      expect(tag.memberCount, greaterThan(0));
    }
    expect(layout.links.length, 1 + 2 + 1);
    expect(layout.links.map((link) => link.tagId).toSet(), {'tag-a', 'tag-b'});
  });

  test('卡片多的知识点画得更大', () {
    final layout = layoutCognitiveGraph(size: size, points: points, tags: tags);
    final three = layout.points.firstWhere((point) => point.id == 'kp-1');
    final one = layout.points.firstWhere((point) => point.id == 'kp-2');
    expect(three.radius, greaterThan(one.radius));
  });

  test('空输入不画图（也不除零）', () {
    expect(
        layoutCognitiveGraph(size: size, points: const [], tags: tags).isEmpty,
        isTrue);
    expect(
      layoutCognitiveGraph(size: Size.zero, points: points, tags: tags).isEmpty,
      isTrue,
    );
  });

  test('标签放在成员角度的圆周均值上：两个相反方向的成员不会让标签跑到 NaN 或对面', () {
    // kp-1 在 -90°，kp-2 在 +90°（两者正好相反）：atan2(Σsin=0, Σcos=0) 会退化，
    // 布局用第一个成员的角度兜底 —— 位置必须有限。
    final layout = layoutCognitiveGraph(
      size: size,
      points: const <CognitiveGraphPointInput>[
        CognitiveGraphPointInput(
            id: 'kp-1', title: '甲', cardCount: 1, tagIds: {'tag-a'}),
        CognitiveGraphPointInput(
            id: 'kp-2', title: '乙', cardCount: 1, tagIds: {'tag-a'}),
      ],
      tags: tags,
    );
    final tag = layout.tags.single;
    expect(tag.center.dx.isFinite, isTrue);
    expect(tag.center.dy.isFinite, isTrue);
    expect((tag.center - layout.center).distance,
        closeTo(layout.innerRadius, 1e-6));
    // 兜底用的是第一个成员的角度：-90° → 标签在正上方。
    expect(tag.center.dx, closeTo(layout.center.dx, 1e-6));
    expect(tag.center.dy, lessThan(layout.center.dy));
  });

  test('命中测试：点在节点上选中它，点空白返回 null', () {
    final layout = layoutCognitiveGraph(size: size, points: points, tags: tags);
    final point = layout.points.first;

    final hit = hitTestCognitiveGraph(layout, point.center);
    expect(hit?.point?.id, point.id);

    // 圆心附近 14px 的额外半径（手指比圆点粗）。
    final near = hitTestCognitiveGraph(
      layout,
      point.center + const Offset(0, kGraphPointHitSlop + 2),
    );
    expect(near?.point?.id, point.id);

    // 两个环之间的空白处：离所有节点都远。
    final gap = layout.center + Offset(layout.innerRadius * 0.7, 0);
    final misses = layout.points.every(
          (node) =>
              (node.center - gap).distance > node.radius + kGraphPointHitSlop,
        ) &&
        layout.tags.every((tag) => (tag.center - gap).distance > 18);
    if (misses) {
      expect(hitTestCognitiveGraph(layout, gap), isNull);
    }
  });
}

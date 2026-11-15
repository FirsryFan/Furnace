/// 标签图纯布局（tag_graph_layout.dart）。
///
/// 钉住：根在左、每层一列、子树带垂直居中、父子连线端点与矩形一致、
/// 折叠后节点/连线一起消失、图宽随深度增长（超过视口时页面才好降级）。
library;

import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/tags/tag_tree_view.dart';
import 'package:furnace/features/tags/presentation/tag_graph_layout.dart';

TagTreeViewTag tag(String id, {String? parentId, String? name}) =>
    TagTreeViewTag(
      id: id,
      parentId: parentId,
      name: name ?? id,
      createdAt: DateTime.utc(2026, 1, 1),
    );

/// alpha 下挂 alpha-a / alpha-b，另有 beta、gamma 两个根。
TagTreeView fixture() => buildTagTreeView(
      tags: [
        tag('t-alpha', name: 'alpha'),
        tag('t-alpha-a', parentId: 't-alpha', name: 'alpha-a'),
        tag('t-alpha-b', parentId: 't-alpha', name: 'alpha-b'),
        tag('t-beta', name: 'beta'),
        tag('t-gamma', name: 'gamma'),
      ],
    );

/// 7 层单链（宽度不够时必须让页面降级成平移/缩放）。
TagTreeView deepChain(int levels) {
  final tags = <TagTreeViewTag>[tag('t0', name: 'n0')];
  for (var index = 1; index < levels; index++) {
    tags.add(
      tag('t$index', parentId: 't${index - 1}', name: 'n$index'),
    );
  }
  return buildTagTreeView(tags: tags);
}

void main() {
  test('空输入：空图、尺寸为 0', () {
    final layout = layoutTagGraph(const <TagTreeViewNode>[]);
    expect(layout.isEmpty, isTrue);
    expect(layout.nodes, isEmpty);
    expect(layout.edges, isEmpty);
    expect(layout.size, const Size(0, 0));
    expect(layout.fitsWidth(0), isTrue);
  });

  test('节点数 = 可见数，边数 = 可见数 - 根数', () {
    final layout = layoutTagGraph(fixture().preorder);
    expect(layout.nodes, hasLength(5));
    // alpha→alpha-a、alpha→alpha-b；beta/gamma 无子。
    expect(layout.edges, hasLength(2));
    expect(layout.edges.map((edge) => '${edge.parentId}->${edge.childId}'),
        ['t-alpha->t-alpha-a', 't-alpha->t-alpha-b']);
  });

  test('根在左（x 只由深度决定），子节点在父节点右侧一列', () {
    final layout = layoutTagGraph(fixture().preorder);
    final alpha = layout.byId['t-alpha']!;
    final child = layout.byId['t-alpha-a']!;
    final siblingRoot = layout.byId['t-beta']!;

    expect(alpha.rect.left, kTagGraphPadding);
    expect(siblingRoot.rect.left, kTagGraphPadding);
    expect(child.rect.left, alpha.rect.right + kTagGraphColumnGap);
    expect(alpha.depth, 0);
    expect(child.depth, 1);
  });

  test('同一层共享 x，子树带垂直居中；节点矩形互不重叠', () {
    final layout = layoutTagGraph(fixture().preorder);
    final a = layout.byId['t-alpha']!;
    final childA = layout.byId['t-alpha-a']!;
    final childB = layout.byId['t-alpha-b']!;
    final beta = layout.byId['t-beta']!;

    expect(childA.rect.left, childB.rect.left);
    // 父节点落在两个孩子带子的垂直中心。
    final bandCenter = (childA.rect.top + childB.rect.bottom) / 2;
    expect(a.rect.center.dy, closeTo(bandCenter, 0.001));
    // 根按顺序往下排，互不重叠。
    expect(a.rect.bottom, lessThan(beta.rect.top));

    final rects = layout.nodes.map((node) => node.rect).toList();
    for (var i = 0; i < rects.length; i++) {
      for (var j = i + 1; j < rects.length; j++) {
        expect(rects[i].overlaps(rects[j]), isFalse,
            reason: '节点 $i 与 $j 重叠: ${rects[i]} vs ${rects[j]}');
      }
    }
  });

  test('连线端点贴着父右 / 子左，拐点在列间中线', () {
    final layout = layoutTagGraph(fixture().preorder);
    final edge = layout.edges.first;
    final parent = layout.byId[edge.parentId]!;
    final child = layout.byId[edge.childId]!;
    expect(edge.from, Offset(parent.rect.right, parent.rect.center.dy));
    expect(edge.to, Offset(child.rect.left, child.rect.center.dy));
    expect(edge.midX, parent.rect.right + kTagGraphColumnGap / 2);
  });

  test('折叠后的可见节点集会一起缩掉节点与连线', () {
    final view = fixture();
    // 折叠 alpha：只剩三个根，没有边。
    final collapsed = <TagTreeViewNode>[
      for (final node in view.preorder)
        if (node.tagId != 't-alpha-a' && node.tagId != 't-alpha-b') node,
    ];
    final layout = layoutTagGraph(collapsed);
    expect(layout.nodes, hasLength(3));
    expect(layout.edges, isEmpty);
    expect(layout.byId.containsKey('t-alpha-a'), isFalse);
  });

  test('被搜索收窄的子集也能画：父不在子集里的节点当根', () {
    final view = fixture();
    final only = <TagTreeViewNode>[
      for (final node in view.preorder)
        if (node.tagId == 't-alpha-a') node,
    ];
    final layout = layoutTagGraph(only);
    expect(layout.nodes, hasLength(1));
    expect(layout.edges, isEmpty);
    expect(layout.byId['t-alpha-a']!.rect.left, kTagGraphPadding);
  });

  test('图宽随深度线性增长；超出视口时 fitsWidth 为 false', () {
    final layout = layoutTagGraph(deepChain(7).preorder);
    expect(layout.nodes, hasLength(7));
    expect(layout.edges, hasLength(6));
    expect(layout.depthCount, 7);
    const expectedWidth = kTagGraphPadding * 2 +
        7 * kTagGraphNodeWidth +
        6 * kTagGraphColumnGap;
    expect(layout.size.width, expectedWidth);
    expect(layout.fitsWidth(1000), isFalse);
    expect(layout.fitsWidth(expectedWidth), isTrue);
  });

  test('同输入同输出：两次布局的矩形/连线完全一致', () {
    final view = fixture();
    final first = layoutTagGraph(view.preorder);
    final second = layoutTagGraph(view.preorder);
    expect(first.size, second.size);
    for (final node in first.nodes) {
      expect(second.byId[node.node.tagId]!.rect, node.rect);
    }
    expect(
      [for (final edge in first.edges) '${edge.parentId}->${edge.childId}'],
      [for (final edge in second.edges) '${edge.parentId}->${edge.childId}'],
    );
  });
}

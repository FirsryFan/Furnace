/// 标签图的**纯布局**：根在左，分支向右逐层展开的整齐树（tidy tree）。
///
/// 页面只负责把这里算好的矩形放进 Stack、把连线交给 painter，因此布局本身
/// 可以脱离 Widget 单测：同一份可见节点 + 同一块视口，永远算出同一组坐标。
///
/// 布局规则：
///  * x 只由深度决定：`padding + depth * (节点宽 + 列间距)`；
///  * 每个节点在垂直方向占一条「子树带」：叶子带高 = 节点高，父节点的带高 =
///    所有子带的带高之和 + 行间距；节点自己落在带子的垂直中心，所以连线从
///    父节点右侧中点出发、到子节点左侧中点，天然不会穿过兄弟节点；
///  * 根与根之间再加一段根间距，顶层不会糊在一起；
///  * 折叠只影响输入：页面先把被折叠节点的后代过滤掉，这里自然就不给它们
///    分配坐标，也就不画边；
///  * 图宽随深度线性增长、图高随叶子数增长。标签树通常 2-4 层，一屏能放下，
///    不需要横向滚动；更深的树由页面降级为可平移/缩放（见 tag_tree_page）。
///
/// 坐标是逻辑像素，未做主题/文字测量：节点宽高固定，避免受字体影响导致
/// 不同测试机器上布局抖动。
library;

import 'dart:ui' show Offset, Rect, Size;

import '../../../domain/services/tags/tag_tree_view.dart';

/// 单个标签节点的宽度。
const double kTagGraphNodeWidth = 176;

/// 单个标签节点的高度（固定，布局与命中都不依赖文字测量）。
const double kTagGraphNodeHeight = 56;

/// 相邻两层之间的水平间距（连线走这里）。
const double kTagGraphColumnGap = 48;

/// 同一父节点下相邻子树的垂直间距。
const double kTagGraphRowGap = 12;

/// 根与根之间的垂直间距。
const double kTagGraphRootGap = 24;

/// 画布四周留白。
const double kTagGraphPadding = 16;

/// 一个节点在画布上的位置。
class TagGraphNodePlacement {
  const TagGraphNodePlacement({
    required this.node,
    required this.rect,
  });

  /// 对应的树节点（含 children / depth / objectCount）。
  final TagTreeViewNode node;

  /// 节点卡片矩形（左上角 + 固定宽高）。
  final Rect rect;

  /// 节点所在层：根为 0。
  int get depth => node.depth;

  @override
  String toString() =>
      'TagGraphNodePlacement(${node.tagId}, depth: $depth, rect: $rect)';
}

/// 一条父 → 子的连线：正交折线（父右 → 层间中线 → 子左）。
class TagGraphEdge {
  const TagGraphEdge({
    required this.parentId,
    required this.childId,
    required this.from,
    required this.to,
    required this.midX,
  });

  final String parentId;
  final String childId;

  /// 父节点右侧中点。
  final Offset from;

  /// 子节点左侧中点。
  final Offset to;

  /// 折线拐弯的 x：父节点右侧与子节点左侧之间。
  final double midX;

  @override
  String toString() => 'TagGraphEdge($parentId -> $childId, midX: $midX)';
}

/// 画好的一张标签图。
class TagGraphLayout {
  TagGraphLayout({
    required this.size,
    required List<TagGraphNodePlacement> nodes,
    required List<TagGraphEdge> edges,
    required Map<String, TagGraphNodePlacement> byId,
  })  : nodes = List<TagGraphNodePlacement>.unmodifiable(nodes),
        edges = List<TagGraphEdge>.unmodifiable(edges),
        byId = Map<String, TagGraphNodePlacement>.unmodifiable(byId);

  /// 空图（没有任何可见节点）。
  static final TagGraphLayout empty = TagGraphLayout(
    size: Size.zero,
    nodes: const <TagGraphNodePlacement>[],
    edges: const <TagGraphEdge>[],
    byId: const <String, TagGraphNodePlacement>{},
  );

  /// 内容尺寸（不含视口；页面据此决定是否需要平移降级）。
  final Size size;

  /// 全部可见节点，顺序 = 输入的前序顺序。
  final List<TagGraphNodePlacement> nodes;

  /// 全部可见父子连线，顺序 = 输入的前序顺序。
  final List<TagGraphEdge> edges;

  /// tagId -> 位置。
  final Map<String, TagGraphNodePlacement> byId;

  /// 没有可见节点。
  bool get isEmpty => nodes.isEmpty;

  /// 内容宽度是否装得进 [viewportWidth]（页面据此选择滚动还是平移）。
  bool fitsWidth(double viewportWidth) => size.width <= viewportWidth;

  /// 图的层数（没有节点时为 0）。
  int get depthCount {
    var depth = 0;
    for (final node in nodes) {
      if (node.depth + 1 > depth) {
        depth = node.depth + 1;
      }
    }
    return depth;
  }

  @override
  String toString() =>
      'TagGraphLayout(size: $size, nodes: ${nodes.length}, '
      'edges: ${edges.length}, depth: $depthCount)';
}

/// 把前序的可见节点排成整齐树。
///
/// 只依赖输入顺序：同层顺序 = `visibleNodes` 里的顺序（页面来自
/// `tagGraphVisibleNodes`，也就是用户选的排序）。父节点不在输入里的节点按根
/// 处理（与 `buildTagTreeView` 的孤儿/断环口径一致），因此传入一个被搜索
/// 过滤过的子集也不会丢节点。
TagGraphLayout layoutTagGraph(List<TagTreeViewNode> visibleNodes) {
  if (visibleNodes.isEmpty) {
    return TagGraphLayout.empty;
  }

  final visibleById = <String, TagTreeViewNode>{
    for (final node in visibleNodes) node.tagId: node,
  };

  // 1) 可见子表 + 根：父不可见的节点当根，保证输入子集也能画。
  final childrenOf = <String, List<TagTreeViewNode>>{};
  final roots = <TagTreeViewNode>[];
  for (final node in visibleNodes) {
    final parentId = node.parentId;
    if (parentId == null || !visibleById.containsKey(parentId)) {
      roots.add(node);
    } else {
      (childrenOf[parentId] ??= <TagTreeViewNode>[]).add(node);
    }
  }

  // 2) 子树带高：叶子 = 节点高；父 = 子带之和 + 行间距。
  final bandHeights = <String, double>{};
  double bandHeightOf(TagTreeViewNode node) {
    final cached = bandHeights[node.tagId];
    if (cached != null) {
      return cached;
    }
    final children = childrenOf[node.tagId] ?? const <TagTreeViewNode>[];
    var height = kTagGraphNodeHeight;
    if (children.isNotEmpty) {
      height = 0;
      for (var index = 0; index < children.length; index++) {
        if (index > 0) {
          height += kTagGraphRowGap;
        }
        height += bandHeightOf(children[index]);
      }
    }
    bandHeights[node.tagId] = height;
    return height;
  }

  // 3) 自顶向下分配矩形：x 按深度，y 按子树带中心。
  final nodes = <TagGraphNodePlacement>[];
  final byId = <String, TagGraphNodePlacement>{};
  var maxDepth = 0;

  void place(TagTreeViewNode node, int depth, double top) {
    if (depth > maxDepth) {
      maxDepth = depth;
    }
    final band = bandHeightOf(node);
    final x = kTagGraphPadding + depth * (kTagGraphNodeWidth + kTagGraphColumnGap);
    final y = top + (band - kTagGraphNodeHeight) / 2;
    final placement = TagGraphNodePlacement(
      node: node,
      rect: Rect.fromLTWH(x, y, kTagGraphNodeWidth, kTagGraphNodeHeight),
    );
    nodes.add(placement);
    byId[node.tagId] = placement;
    final children = childrenOf[node.tagId] ?? const <TagTreeViewNode>[];
    var cursor = top;
    for (var index = 0; index < children.length; index++) {
      if (index > 0) {
        cursor += kTagGraphRowGap;
      }
      final child = children[index];
      place(child, depth + 1, cursor);
      cursor += bandHeightOf(child);
    }
  }

  var cursor = kTagGraphPadding;
  for (var index = 0; index < roots.length; index++) {
    if (index > 0) {
      cursor += kTagGraphRootGap;
    }
    final root = roots[index];
    place(root, 0, cursor);
    cursor += bandHeightOf(root);
  }

  // 4) 连线：每个可见父节点到它的每个可见子节点。
  final edges = <TagGraphEdge>[];
  for (final node in nodes) {
    final parentId = node.node.parentId;
    if (parentId == null) {
      continue;
    }
    final parent = byId[parentId];
    if (parent == null) {
      continue;
    }
    edges.add(
      TagGraphEdge(
        parentId: parentId,
        childId: node.node.tagId,
        from: Offset(parent.rect.right, parent.rect.center.dy),
        to: Offset(node.rect.left, node.rect.center.dy),
        midX: parent.rect.right + kTagGraphColumnGap / 2,
      ),
    );
  }

  final contentWidth = kTagGraphPadding * 2 +
      (maxDepth + 1) * kTagGraphNodeWidth +
      maxDepth * kTagGraphColumnGap;
  final contentHeight = kTagGraphPadding * 2 + cursor - kTagGraphPadding;

  return TagGraphLayout(
    size: Size(contentWidth, contentHeight),
    nodes: nodes,
    edges: edges,
    byId: byId,
  );
}

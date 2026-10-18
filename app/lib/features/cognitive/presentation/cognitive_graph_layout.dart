/// 认知模型可视化（只读）的**纯布局**：知识点排外环、标签排内环、成员关系连成弦。
///
/// 为什么是"知识点 ↔ 标签"而不是知识点互相连线：认知模型（tierB 快层、发展区扩散、
/// 元认知行）跑的图节点就是**标签**（`domain/services/cognitive/cognitive_graph.dart`
/// 的节点取自 `tags.id`），而页面手里的是知识点（`kp-…`）。`knowledgePointTagIdsProvider`
/// 存在的理由就是这两套 id 不是一回事（Q8）。所以这张图照实画"知识点挂在哪些标签上"，
/// 不发明知识点之间的边（线索边有自己的页面）。
///
/// 确定性的代价与收益：同一份数据永远得到同一张图（输入先排序，角度按序分配），
/// 于是它可以被单元测试钉住；没有力导向迭代，画一张图是 O(n)。
library;

import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

/// 一个知识点的输入（读数与颜色由页面决定，布局只关心位置与大小）。
class CognitiveGraphPointInput {
  const CognitiveGraphPointInput({
    required this.id,
    required this.title,
    required this.cardCount,
    this.tagIds = const <String>{},
  });

  final String id;
  final String title;

  /// 这个知识点下的卡片数（决定圆点大小：读数为空的知识点也能画）。
  final int cardCount;
  final Set<String> tagIds;
}

/// 一个标签的输入。
class CognitiveGraphTagInput {
  const CognitiveGraphTagInput({required this.id, required this.title});

  final String id;
  final String title;
}

/// 画好的一个知识点节点。
class GraphPointNode {
  const GraphPointNode({
    required this.id,
    required this.title,
    required this.cardCount,
    required this.center,
    required this.radius,
  });

  final String id;
  final String title;
  final int cardCount;
  final Offset center;
  final double radius;
}

/// 画好的一个标签节点。
class GraphTagNode {
  const GraphTagNode({
    required this.id,
    required this.title,
    required this.memberCount,
    required this.center,
  });

  final String id;
  final String title;
  final int memberCount;
  final Offset center;
}

/// 一条"知识点挂在标签上"的连线。
class GraphLink {
  const GraphLink({required this.pointId, required this.tagId});

  final String pointId;
  final String tagId;
}

/// 一张图的完整布局。
class CognitiveGraphLayout {
  const CognitiveGraphLayout({
    required this.size,
    required this.points,
    required this.tags,
    required this.links,
    required this.center,
    required this.outerRadius,
    required this.innerRadius,
  });

  static const CognitiveGraphLayout empty = CognitiveGraphLayout(
    size: Size.zero,
    points: <GraphPointNode>[],
    tags: <GraphTagNode>[],
    links: <GraphLink>[],
    center: Offset.zero,
    outerRadius: 0,
    innerRadius: 0,
  );

  final Size size;
  final List<GraphPointNode> points;
  final List<GraphTagNode> tags;
  final List<GraphLink> links;
  final Offset center;

  /// 知识点外环半径（画环参考线用）。
  final double outerRadius;

  /// 标签内环半径。
  final double innerRadius;

  bool get isEmpty => points.isEmpty;
}

/// 点的命中半径：圆点本身太小，手指更粗。
const double kGraphPointHitSlop = 14;

/// 一个被点中的节点。
class GraphSelection {
  const GraphSelection.point(this.point) : tag = null;
  const GraphSelection.tag(this.tag) : point = null;

  final GraphPointNode? point;
  final GraphTagNode? tag;
}

/// 把"知识点与标签"排成一张图。
///
/// 布局：知识点按"主标签标题 → 标题 → id"排序后均匀分布在外环；标签放在它成员角度
/// 的**圆周均值**处（`atan2(Σsin, Σcos)`，不是角度的算术平均 —— 否则越过 ±π 的
/// 成员会把标签放到对面去），半径是外环的 42%。
CognitiveGraphLayout layoutCognitiveGraph({
  required Size size,
  required List<CognitiveGraphPointInput> points,
  required List<CognitiveGraphTagInput> tags,
}) {
  if (points.isEmpty || size.shortestSide <= 0) {
    return CognitiveGraphLayout.empty;
  }

  final titleById = <String, String>{
    for (final tag in tags) tag.id: tag.title,
  };
  final sortedPoints = <CognitiveGraphPointInput>[...points]..sort((a, b) {
      String primary(CognitiveGraphPointInput p) {
        if (p.tagIds.isEmpty) return '';
        final ids = p.tagIds.toList()..sort();
        return ids.first;
      }

      final byTag = (titleById[primary(a)] ?? primary(a))
          .compareTo(titleById[primary(b)] ?? primary(b));
      if (byTag != 0) return byTag;
      final byTitle = a.title.compareTo(b.title);
      return byTitle != 0 ? byTitle : a.id.compareTo(b.id);
    });

  final center = Offset(size.width / 2, size.height / 2);
  final outerRadius = size.shortestSide / 2 * 0.72;
  final innerRadius = outerRadius * 0.42;

  final angles = <String, double>{};
  final pointNodes = <GraphPointNode>[];
  for (var i = 0; i < sortedPoints.length; i++) {
    final input = sortedPoints[i];
    final angle = -math.pi / 2 + 2 * math.pi * i / sortedPoints.length;
    angles[input.id] = angle;
    pointNodes.add(
      GraphPointNode(
        id: input.id,
        title: input.title,
        cardCount: input.cardCount,
        center: center + Offset(math.cos(angle), math.sin(angle)) * outerRadius,
        radius: 5 + math.min(input.cardCount, 8) * 1.6,
      ),
    );
  }

  // 标签 → 成员角度（只保留真的被挂上的标签）。
  final membersByTag = <String, List<double>>{};
  final links = <GraphLink>[];
  for (final point in sortedPoints) {
    for (final tagId in point.tagIds) {
      links.add(GraphLink(pointId: point.id, tagId: tagId));
      (membersByTag[tagId] ??= <double>[]).add(angles[point.id]!);
    }
  }

  final tagNodes = <GraphTagNode>[
    for (final tag in tags)
      if (membersByTag[tag.id] != null)
        GraphTagNode(
          id: tag.id,
          title: tag.title,
          memberCount: membersByTag[tag.id]!.length,
          center: center +
              Offset(
                    math.cos(_circularMean(membersByTag[tag.id]!)),
                    math.sin(_circularMean(membersByTag[tag.id]!)),
                  ) *
                  innerRadius,
        ),
  ]..sort((a, b) {
      final byTitle = a.title.compareTo(b.title);
      return byTitle != 0 ? byTitle : a.id.compareTo(b.id);
    });

  return CognitiveGraphLayout(
    size: size,
    points: List<GraphPointNode>.unmodifiable(pointNodes),
    tags: List<GraphTagNode>.unmodifiable(tagNodes),
    links: List<GraphLink>.unmodifiable(links),
    center: center,
    outerRadius: outerRadius,
    innerRadius: innerRadius,
  );
}

/// 被点中的节点（最近且在命中半径内）；点空白返回 null。
GraphSelection? hitTestCognitiveGraph(
  CognitiveGraphLayout layout,
  Offset position,
) {
  if (layout.isEmpty) {
    return null;
  }
  GraphPointNode? bestPoint;
  var bestDistance = double.infinity;
  for (final point in layout.points) {
    final distance = (point.center - position).distance;
    if (distance <= point.radius + kGraphPointHitSlop &&
        distance < bestDistance) {
      bestDistance = distance;
      bestPoint = point;
    }
  }
  if (bestPoint != null) {
    return GraphSelection.point(bestPoint);
  }
  GraphTagNode? bestTag;
  var bestTagDistance = double.infinity;
  for (final tag in layout.tags) {
    final distance = (tag.center - position).distance;
    if (distance <= 18 && distance < bestTagDistance) {
      bestTagDistance = distance;
      bestTag = tag;
    }
  }
  return bestTag == null ? null : GraphSelection.tag(bestTag);
}

double _circularMean(List<double> angles) {
  var sin = 0.0;
  var cos = 0.0;
  for (final angle in angles) {
    sin += math.sin(angle);
    cos += math.cos(angle);
  }
  if (sin.abs() < 1e-9 && cos.abs() < 1e-9) {
    // 完全对称（例如正好两个相反方向的成员）：用第一个角度，避免 atan2(0,0)。
    return angles.first;
  }
  return math.atan2(sin, cos);
}

/// 认知模型可视化（只读）的**纯布局**：按标签分簇，知识点散在各自簇里。
///
/// 为什么是"知识点 ↔ 标签"而不是知识点互相连线：认知模型（tierB 快层、发展区扩散、
/// 元认知行）跑的图节点就是**标签**（`domain/services/cognitive/cognitive_graph.dart`
/// 的节点取自 `tags.id`），而页面手里的是知识点（`kp-…`）。`knowledgePointTagIdsProvider`
/// 存在的理由就是这两套 id 不是一回事（Q8）。所以这张图照实画"知识点挂在哪些标签上"，
/// 不发明知识点之间的边（线索边有自己的页面）。
///
/// 布局（v2，轮次一百二十六）：
///
/// * 每个被挂上的标签占圆周上的一段**扇区**，扇区角度按"主成员数"加权并保留最小角度，
///   所以成员多的标签周围空间大、成员少的标签也不会被挤成一条线。
/// * 知识点只进**一个**簇：在它挂的标签里按"标题 → id"排序取第一个做主标签（确定性）。
///   多挂的标签照实保留连线（画在图上会跨簇，选中时提亮）。
/// * 簇中心落在扇区中角的环上；簇内成员按**黄金角螺旋**（`r = 间距·√k`，角度差 137.5°）
///   散开 —— 这种螺旋的相邻点距离恒等于间距（k=0 与 k=1 刚好一个间距），不会叠成一团。
/// * 没有标签的知识点放在画布中心区，同样用螺旋。
/// * 标签名（方块）放在簇的**外侧**（沿扇区中角再往外），远离画布中心，不压住圆点。
/// * 所有坐标都夹在画布内；画布边长随知识点数增长（`cognitiveGraphCanvasSide`），
///   页面再用 `InteractiveViewer` 把它装进视口。
///
/// 确定性的代价与收益：同一份数据永远得到同一张图（输入先排序，角度按序分配），
/// 于是它可以被单元测试钉住；没有力导向迭代，画一张图是 O(n)。
library;

import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

/// 画布基线边长（逻辑像素）：约 15 个知识点时的舒适尺寸。
const double kCognitiveGraphBaseSide = 840;

/// 画布边长上限：再多知识点也只在 2400 里排，剩下的靠缩放看。
const double kCognitiveGraphMaxCanvasSide = 2400;

/// 同一簇内相邻知识点的圆心间距（黄金角螺旋的径向步长）。
const double kCognitiveGraphPointSpacing = 26;

/// 标签名方块的高度（命中测试与绘制共用）。
const double kCognitiveGraphTagBoxHeight = 20;

/// 点的命中半径：圆点本身太小，手指更粗。
const double kGraphPointHitSlop = 14;

/// 标签方块的命中外扩（方块本身比手指小）。
const double kGraphTagHitSlop = 4;

/// 黄金角（弧度）：相邻成员的角差，保证螺旋散点均匀。
const double _goldenAngle = 2.399963229728653;

/// 画布内边距：节点圆心不贴边。
const double _canvasMargin = 56;

/// 标签方块离簇边缘的额外距离。
const double _tagLabelGap = 26;

/// 标签方块自身尺寸的估算斜边余量（夹取时留出位置）。
const double _tagLabelInset = 40;

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
    this.groupTagId,
  });

  final String id;
  final String title;
  final int cardCount;
  final Offset center;
  final double radius;

  /// 它被画进哪个标签簇（主标签）；没有标签的知识点为 null（画在中心）。
  final String? groupTagId;
}

/// 画好的一个标签节点。
class GraphTagNode {
  const GraphTagNode({
    required this.id,
    required this.title,
    required this.memberCount,
    required this.center,
    this.clusterCenter = Offset.zero,
    this.clusterRadius = 0,
  });

  final String id;
  final String title;

  /// 挂在它上面的知识点数（含只把该标签当"次标签"的知识点）。
  final int memberCount;

  /// 标签名方块的中心（簇的外侧，页面按它绘制与命中）。
  final Offset center;

  /// 簇的几何中心：成员围绕它散开。
  final Offset clusterCenter;

  /// 簇的半径（=最远成员到簇中心的距离；没有主成员时为 0）。
  final double clusterRadius;
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
  });

  static const CognitiveGraphLayout empty = CognitiveGraphLayout(
    size: Size.zero,
    points: <GraphPointNode>[],
    tags: <GraphTagNode>[],
    links: <GraphLink>[],
    center: Offset.zero,
  );

  final Size size;
  final List<GraphPointNode> points;
  final List<GraphTagNode> tags;
  final List<GraphLink> links;

  /// 画布中心。
  final Offset center;

  bool get isEmpty => points.isEmpty;
}

/// 一个被点中的节点。
class GraphSelection {
  const GraphSelection.point(this.point) : tag = null;
  const GraphSelection.tag(this.tag) : point = null;

  final GraphPointNode? point;
  final GraphTagNode? tag;
}

/// 画布逻辑边长：知识点越多越大（840 → 2400），让密度保持大致恒定。
double cognitiveGraphCanvasSide(int pointCount) {
  if (pointCount <= 0) {
    return kCognitiveGraphBaseSide;
  }
  final scaled = kCognitiveGraphBaseSide * math.sqrt(pointCount / 15);
  return math.min(
    kCognitiveGraphMaxCanvasSide,
    math.max(kCognitiveGraphBaseSide, scaled),
  );
}

/// 标签方块宽度（随挂载数变宽；绘制与命中测试共用）。
double cognitiveGraphTagBoxWidth(GraphTagNode tag) =>
    26 + math.min(tag.memberCount, 8) * 6;

/// 把"知识点与标签"排成一张分簇图（见文件头）。
CognitiveGraphLayout layoutCognitiveGraph({
  required Size size,
  required List<CognitiveGraphPointInput> points,
  required List<CognitiveGraphTagInput> tags,
}) {
  if (points.isEmpty || size.shortestSide <= 0) {
    return CognitiveGraphLayout.empty;
  }

  final side = size.shortestSide;
  final center = Offset(size.width / 2, size.height / 2);
  final titleById = <String, String>{
    for (final tag in tags) tag.id: tag.title,
  };

  String titleOf(String tagId) => titleById[tagId] ?? tagId;

  // 主标签：与 cognitiveGraphPrimaryTagId 同一口径（确定性；不受 Set 顺序影响）。
  String? primaryTagOf(CognitiveGraphPointInput point) =>
      cognitiveGraphPrimaryTagId(point, titleById);

  final sortedPoints = <CognitiveGraphPointInput>[...points]..sort((a, b) {
      final primaryA = primaryTagOf(a);
      final primaryB = primaryTagOf(b);
      final keyA = primaryA == null ? '' : titleOf(primaryA);
      final keyB = primaryB == null ? '' : titleOf(primaryB);
      final byTag = keyA.compareTo(keyB);
      if (byTag != 0) {
        return byTag;
      }
      final byTitle = a.title.compareTo(b.title);
      return byTitle != 0 ? byTitle : a.id.compareTo(b.id);
    });

  final primaryByPoint = <String, String?>{
    for (final point in sortedPoints) point.id: primaryTagOf(point),
  };
  final tagIdsByPoint = <String, List<String>>{};
  final primaryCounts = <String, int>{};
  final memberCounts = <String, int>{};
  for (final point in sortedPoints) {
    final ids = <String>[
      for (final id in point.tagIds)
        if (id.trim().isNotEmpty) id,
    ]..sort();
    tagIdsByPoint[point.id] = ids;
    for (final id in ids) {
      memberCounts[id] = (memberCounts[id] ?? 0) + 1;
    }
    final primary = primaryByPoint[point.id];
    if (primary != null) {
      primaryCounts[primary] = (primaryCounts[primary] ?? 0) + 1;
    }
  }

  final clusterIds = <String>[
    for (final id in memberCounts.keys) id,
  ]..sort((a, b) {
      final byTitle = titleOf(a).compareTo(titleOf(b));
      return byTitle != 0 ? byTitle : a.compareTo(b);
    });

  double clusterRadiusOf(int memberCount) => memberCount <= 1
      ? 0
      : kCognitiveGraphPointSpacing * math.sqrt(memberCount - 1.0);

  var maxClusterRadius = 0.0;
  for (final id in clusterIds) {
    maxClusterRadius = math.max(
      maxClusterRadius,
      clusterRadiusOf(primaryCounts[id] ?? 0),
    );
  }

  // 扇区：每个簇至少 minAngle，剩余角度按主成员数分；成员多的簇更宽。
  final clusterCount = clusterIds.length;
  final totalPrimary = primaryCounts.values.fold<int>(0, (sum, c) => sum + c);
  final minAngle = math.min(
    0.22,
    clusterCount == 0 ? 0.0 : 2 * math.pi / (clusterCount * 3),
  );
  final extraAngle = 2 * math.pi - minAngle * clusterCount;
  final midAngles = <String, double>{};
  var cursor = -math.pi / 2;
  for (final id in clusterIds) {
    final weight = primaryCounts[id] ?? 0;
    final share = totalPrimary == 0 ? 1 / clusterCount : weight / totalPrimary;
    final span = minAngle + extraAngle * share;
    midAngles[id] = cursor + span / 2;
    cursor += span;
  }

  // 环半径：既要装得下所有簇（周长约束），又不能把簇顶出画布。
  var circumferenceNeed = 0.0;
  for (final id in clusterIds) {
    circumferenceNeed += 2 * clusterRadiusOf(primaryCounts[id] ?? 0) + 40;
  }
  final requiredRadius =
      clusterCount == 0 ? 0.0 : circumferenceNeed / (2 * math.pi);
  final baseRadius = side * 0.28;
  final maxRadius =
      side / 2 - _canvasMargin - maxClusterRadius - _tagLabelInset - 36;
  final ringRadius = maxRadius <= 0
      ? side * 0.15
      : math.min(math.max(requiredRadius, baseRadius), maxRadius);

  final clusterCenters = <String, Offset>{
    for (final id in clusterIds)
      id: center +
          Offset(math.cos(midAngles[id]!), math.sin(midAngles[id]!)) *
              ringRadius,
  };

  Offset clampToCanvas(Offset position) {
    final clampedX = math.min(
      math.max(position.dx, _canvasMargin),
      size.width - _canvasMargin,
    );
    final clampedY = math.min(
      math.max(position.dy, _canvasMargin),
      size.height - _canvasMargin,
    );
    return Offset(clampedX, clampedY);
  }

  Offset spiralOffset(int index, double spacing) {
    final angle = index * _goldenAngle;
    final radius = spacing * math.sqrt(index.toDouble());
    return Offset(math.cos(angle) * radius, math.sin(angle) * radius);
  }

  final clusterUsed = <String, int>{};
  var untaggedIndex = 0;
  final pointNodes = <GraphPointNode>[];
  for (final point in sortedPoints) {
    final primary = primaryByPoint[point.id];
    final Offset position;
    if (primary == null) {
      position = clampToCanvas(
        center + spiralOffset(untaggedIndex++, kCognitiveGraphPointSpacing),
      );
    } else {
      final used = clusterUsed[primary] ?? 0;
      clusterUsed[primary] = used + 1;
      position = clampToCanvas(
        clusterCenters[primary]! +
            spiralOffset(used, kCognitiveGraphPointSpacing),
      );
    }
    pointNodes.add(
      GraphPointNode(
        id: point.id,
        title: point.title,
        cardCount: point.cardCount,
        center: position,
        radius: 5 + math.min(math.max(point.cardCount, 0), 8) * 1.6,
        groupTagId: primary,
      ),
    );
  }

  final tagNodes = <GraphTagNode>[
    for (final id in clusterIds)
      GraphTagNode(
        id: id,
        title: titleOf(id),
        memberCount: memberCounts[id] ?? 0,
        center: clampToCanvas(
          clusterCenters[id]! +
              Offset(
                    math.cos(midAngles[id]!),
                    math.sin(midAngles[id]!),
                  ) *
                  (clusterRadiusOf(primaryCounts[id] ?? 0) + _tagLabelGap),
        ),
        clusterCenter: clusterCenters[id]!,
        clusterRadius: clusterRadiusOf(primaryCounts[id] ?? 0),
      ),
  ]..sort((a, b) {
      final byTitle = a.title.compareTo(b.title);
      return byTitle != 0 ? byTitle : a.id.compareTo(b.id);
    });

  final links = <GraphLink>[
    for (final point in sortedPoints)
      for (final tagId in tagIdsByPoint[point.id]!)
        GraphLink(pointId: point.id, tagId: tagId),
  ];

  return CognitiveGraphLayout(
    size: size,
    points: List<GraphPointNode>.unmodifiable(pointNodes),
    tags: List<GraphTagNode>.unmodifiable(tagNodes),
    links: List<GraphLink>.unmodifiable(links),
    center: center,
  );
}

/// 被点中的节点（最近且在命中范围内）；点空白返回 null。
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
    final delta = (tag.center - position);
    final halfWidth = cognitiveGraphTagBoxWidth(tag) / 2 + kGraphTagHitSlop;
    const halfHeight = kCognitiveGraphTagBoxHeight / 2 + kGraphTagHitSlop;
    if (delta.dx.abs() > halfWidth || delta.dy.abs() > halfHeight) {
      continue;
    }
    final distance = delta.distance;
    if (distance < bestTagDistance) {
      bestTagDistance = distance;
      bestTag = tag;
    }
  }
  return bestTag == null ? null : GraphSelection.tag(bestTag);
}

/// 一个知识点在图上进哪个簇：它挂的标签里按「标题 → id」排序取第一个。
///
/// 与 layoutCognitiveGraph 内部是同一口径（列表视图与测试都靠它解释"主标签"）。
/// 标题未知时退回 id，所以结果不依赖 Set 的遍历顺序。
String? cognitiveGraphPrimaryTagId(
  CognitiveGraphPointInput point,
  Map<String, String> tagTitles,
) {
  String titleOf(String tagId) => tagTitles[tagId] ?? tagId;
  final ids = <String>[
    for (final id in point.tagIds)
      if (id.trim().isNotEmpty) id,
  ]..sort((a, b) {
      final byTitle = titleOf(a).compareTo(titleOf(b));
      return byTitle != 0 ? byTitle : a.compareTo(b);
    });
  return ids.isEmpty ? null : ids.first;
}

/// 搜索 / 标签筛选：返回需要画（或列）的知识点，保持输入顺序。
///
/// 口径（页面与测试共用，所以放在这里）：
/// * query 先 trim，空串等于不搜索；匹配大小写不敏感。
/// * 命中 = 知识点标题 或 它挂的任一标签标题 包含 query（用户常常只记得标签名）。
/// * tagFilterId 非空时只保留挂了该标签的知识点。
/// * 两个条件同时给出取交集。
List<CognitiveGraphPointInput> filterCognitiveGraphPoints({
  required List<CognitiveGraphPointInput> points,
  Map<String, String> pointTitles = const <String, String>{},
  Map<String, String> tagTitles = const <String, String>{},
  String query = '',
  String? tagFilterId,
}) {
  final needle = query.trim().toLowerCase();
  final rawFilter = tagFilterId?.trim();
  final filter = rawFilter == null || rawFilter.isEmpty ? null : rawFilter;
  if (needle.isEmpty && filter == null) {
    return List<CognitiveGraphPointInput>.unmodifiable(points);
  }
  bool matchesQuery(CognitiveGraphPointInput point) {
    if (needle.isEmpty) {
      return true;
    }
    final title = (pointTitles[point.id] ?? point.title).toLowerCase();
    if (title.contains(needle)) {
      return true;
    }
    for (final id in point.tagIds) {
      final tagTitle = (tagTitles[id] ?? id).toLowerCase();
      if (tagTitle.contains(needle)) {
        return true;
      }
    }
    return false;
  }

  return List<CognitiveGraphPointInput>.unmodifiable(<CognitiveGraphPointInput>[
    for (final point in points)
      if ((filter == null || point.tagIds.contains(filter)) &&
          matchesQuery(point))
        point,
  ]);
}

/// 列表视图的一组：同一个主标签下的知识点。
class CognitiveGraphPointGroup {
  const CognitiveGraphPointGroup({
    required this.tagId,
    required this.title,
    required this.points,
  });

  /// 主标签 id；没挂标签的组为 null。
  final String? tagId;

  /// 标签标题；没挂标签的组为 null（页面用 l10n 的"未挂标签"）。
  final String? title;

  final List<CognitiveGraphPointInput> points;
}

/// 列表视图的分组：按主标签分组，组按标签标题排序，没挂标签的组排最后。
List<CognitiveGraphPointGroup> groupCognitiveGraphPointsByPrimaryTag({
  required List<CognitiveGraphPointInput> points,
  Map<String, String> pointTitles = const <String, String>{},
  Map<String, String> tagTitles = const <String, String>{},
}) {
  final grouped = <String?, List<CognitiveGraphPointInput>>{};
  final titles = <String, String>{};
  for (final point in points) {
    final tagId = cognitiveGraphPrimaryTagId(point, tagTitles);
    (grouped[tagId] ??= <CognitiveGraphPointInput>[]).add(point);
    if (tagId != null) {
      titles[tagId] = tagTitles[tagId] ?? tagId;
    }
  }
  final keys = <String?>[...grouped.keys]..sort((a, b) {
      if (a == null && b == null) {
        return 0;
      }
      if (a == null) {
        return 1;
      }
      if (b == null) {
        return -1;
      }
      final byTitle = (titles[a] ?? a).compareTo(titles[b] ?? b);
      return byTitle != 0 ? byTitle : a.compareTo(b);
    });
  String pointTitleOf(CognitiveGraphPointInput point) =>
      pointTitles[point.id] ?? point.title;
  return List<CognitiveGraphPointGroup>.unmodifiable(<CognitiveGraphPointGroup>[
    for (final key in keys)
      CognitiveGraphPointGroup(
        tagId: key,
        title: key == null ? null : (titles[key] ?? key),
        points: List<CognitiveGraphPointInput>.unmodifiable(
          <CognitiveGraphPointInput>[...grouped[key]!]..sort((a, b) {
              final byTitle = pointTitleOf(a).compareTo(pointTitleOf(b));
              return byTitle != 0 ? byTitle : a.id.compareTo(b.id);
            }),
        ),
      ),
  ]);
}

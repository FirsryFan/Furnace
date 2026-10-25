/// 认知模型的**只读可视化**：一张"知识点 ↔ 标签"的网络图。
///
/// 为什么这样画（而不是画成"思维导图"或"仪表盘"）：
///
/// * 认知模型跑的那张图，节点是**标签**（`cognitive_graph.dart` 的节点直接取 `tags.id`），
///   而页面手里的是知识点；`knowledgePointTagIdsProvider` 存在的理由就是这两套 id 不是
///   一回事（Q8）。所以这张图照实画"每个知识点挂在哪些标签上"，不发明知识点之间的边
///   —— 线索边有自己的页面（`knowledge_edge_page.dart`）。
/// * 颜色 = 这张知识点的认知区域（`ReviewZone`，与读数页同一个词表 `zoneLabel`）；
///   圆点大小 = 卡片数；方块 = 标签。图上的每个数字都来自 `cognitiveReadingsProvider`，
///   页面不自己算 R、不改到期时间、不改排序 —— 它只是同一批数字的另一种画法。
/// * 标签分簇（`cognitive_graph_layout.dart`）：成员围绕簇中心散开，标签名画在簇的外侧。
///   读图顺序因此是"先看哪个簇挤、再点开看具体知识点"，而不是在一张大饼上找点。
///
/// 可读性（v2）：画布边长随知识点数增长，视口用 `InteractiveViewer` 装下它 ——
/// 首次进入自动缩放居中（所以总能一眼看全），之后可以拖动平移、双指/滚轮缩放；
/// 缩放小于 [kCognitiveGraphLabelMinScale] 时隐藏文字只留圆点，避免小图上文字糊成一团。
/// 右上角"重置视图"回到自动缩放的位置。
///
/// 只读是构造性保证：本页只 `watch` provider（那些 provider 全是 `select`），
/// 没有任何写库调用；测试用"整库指纹不变"钉住。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../anki/application/review_advisory.dart' show ReviewZone;
import '../../tags/presentation/tag_tree_page.dart' show allTagsProvider;
import 'cognitive_graph_layout.dart';
import 'cognitive_model_page.dart'
    show
        CognitiveCardReading,
        cognitiveReadingsProvider,
        knowledgePointTagIdsProvider,
        zoneLabel;

/// 画布 widget 的 key（测试按它取画布矩形，再算节点屏幕坐标）。
const Key cognitiveGraphCanvasKey = Key('cognitive-graph-canvas');

/// 缩放容器的 key（测试按它取视口矩形、读 TransformationController）。
const Key cognitiveGraphViewportKey = Key('cognitive-graph-viewport');

/// "重置视图"按钮的 key。
const Key cognitiveGraphResetViewKey = Key('cognitive-graph-reset-view');

/// 小于这个缩放比（相对"自动适配"后的 zoom 语义是绝对比例）时隐藏文字。
const double kCognitiveGraphLabelMinScale = 0.8;

/// 一个知识点在图上的读数（详情面板用）。
class CognitiveGraphPointReading {
  const CognitiveGraphPointReading({
    required this.zone,
    required this.cardCount,
    required this.meanR,
  });

  final ReviewZone zone;
  final int cardCount;

  /// 这个知识点下所有卡的 R 均值；没有卡片（不可能出现在图上）时 null。
  final double? meanR;
}

/// 图的数据：布局输入 + 详情。
class CognitiveGraphData {
  const CognitiveGraphData({
    required this.points,
    required this.tags,
    required this.readingsByPoint,
    required this.pointTitles,
    required this.tagTitles,
  });

  static const CognitiveGraphData empty = CognitiveGraphData(
    points: <CognitiveGraphPointInput>[],
    tags: <CognitiveGraphTagInput>[],
    readingsByPoint: <String, CognitiveGraphPointReading>{},
    pointTitles: <String, String>{},
    tagTitles: <String, String>{},
  );

  final List<CognitiveGraphPointInput> points;
  final List<CognitiveGraphTagInput> tags;
  final Map<String, CognitiveGraphPointReading> readingsByPoint;
  final Map<String, String> pointTitles;
  final Map<String, String> tagTitles;

  bool get isEmpty => points.isEmpty;

  int get linkCount =>
      points.fold<int>(0, (sum, point) => sum + point.tagIds.length);
}

/// 把读数与标签挂载关系拼成图的输入（纯函数，可单测）。
///
/// 区域聚合用**最坏的那个**：一个知识点挂了好几张卡时，只要有一张卡在危险区，
/// 这个点就该显示成危险区 —— 取平均或取第一个都会把问题画淡。
CognitiveGraphData buildCognitiveGraphData({
  required List<CognitiveCardReading> cards,
  required Map<String, List<String>> tagIdsByPoint,
  required Map<String, String> tagTitles,
}) {
  if (cards.isEmpty) {
    return CognitiveGraphData.empty;
  }
  const priority = <ReviewZone>[
    ReviewZone.danger,
    ReviewZone.deadEnd,
    ReviewZone.empty,
    ReviewZone.overload,
    ReviewZone.slow,
    ReviewZone.offGoal,
    ReviewZone.proximal,
    ReviewZone.healthy,
    ReviewZone.unavailable,
  ];
  int rank(ReviewZone zone) => priority.indexOf(zone);

  final byPoint = <String, List<CognitiveCardReading>>{};
  for (final card in cards) {
    (byPoint[card.knowledgePointId] ??= <CognitiveCardReading>[]).add(card);
  }

  final readings = <String, CognitiveGraphPointReading>{};
  final titles = <String, String>{};
  final points = <CognitiveGraphPointInput>[];
  final usedTagIds = <String>{};
  for (final entry in byPoint.entries) {
    final rows = entry.value;
    final worst = rows.map((row) => row.zone).reduce(
          (a, b) => rank(b) < rank(a) ? b : a,
        );
    final meanR =
        rows.map((row) => row.r).reduce((a, b) => a + b) / rows.length;
    final tagIds = <String>{
      ...?tagIdsByPoint[entry.key],
    }..removeWhere((id) => id.trim().isEmpty);
    usedTagIds.addAll(tagIds);
    titles[entry.key] = rows.first.knowledgePointTitle;
    readings[entry.key] = CognitiveGraphPointReading(
      zone: worst,
      cardCount: rows.length,
      meanR: meanR,
    );
    points.add(
      CognitiveGraphPointInput(
        id: entry.key,
        title: rows.first.knowledgePointTitle,
        cardCount: rows.length,
        tagIds: tagIds,
      ),
    );
  }

  return CognitiveGraphData(
    points: points,
    tags: <CognitiveGraphTagInput>[
      for (final tagId in usedTagIds)
        CognitiveGraphTagInput(
          id: tagId,
          title: tagTitles[tagId] ?? tagId,
        ),
    ],
    readingsByPoint: readings,
    pointTitles: titles,
    tagTitles: <String, String>{
      for (final tagId in usedTagIds) tagId: tagTitles[tagId] ?? tagId,
    },
  );
}

/// 图的数据：读数 + 知识点→标签 + 标签名。只读（上游全是 select）。
final cognitiveGraphProvider =
    FutureProvider.autoDispose<CognitiveGraphData>((ref) async {
  final readings = await ref.watch(cognitiveReadingsProvider.future);
  final tagIds = await ref.watch(knowledgePointTagIdsProvider.future);
  final tags = await ref.watch(allTagsProvider.future);
  return buildCognitiveGraphData(
    cards: readings.cards,
    tagIdsByPoint: tagIds,
    tagTitles: <String, String>{
      for (final tag in tags) tag.id: tag.name,
    },
  );
});

/// 认知区域的显示颜色（读数页与这张图共用一个词表；颜色只在本页用）。
Color cognitiveGraphZoneColor(ThemeData theme, ReviewZone zone) =>
    switch (zone) {
      ReviewZone.danger => theme.colorScheme.error,
      ReviewZone.deadEnd => theme.colorScheme.tertiary,
      ReviewZone.empty => theme.colorScheme.secondary,
      ReviewZone.overload => theme.colorScheme.error.withValues(alpha: 0.55),
      ReviewZone.slow => theme.colorScheme.primary.withValues(alpha: 0.55),
      ReviewZone.offGoal => theme.colorScheme.outline,
      ReviewZone.proximal => theme.colorScheme.primary,
      ReviewZone.healthy => Colors.green.shade600,
      ReviewZone.unavailable =>
        theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
    };

/// 只读的知识网络图。
class CognitiveGraphPage extends ConsumerStatefulWidget {
  const CognitiveGraphPage({super.key});

  @override
  ConsumerState<CognitiveGraphPage> createState() => _CognitiveGraphPageState();
}

class _CognitiveGraphPageState extends ConsumerState<CognitiveGraphPage> {
  final GlobalKey<_GraphBodyState> _bodyKey = GlobalKey<_GraphBodyState>();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final graph = ref.watch(cognitiveGraphProvider);
    final data = graph.valueOrNull;
    final hasGraph = data != null && !data.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.cognitiveGraphTitle),
        actions: [
          if (hasGraph)
            IconButton(
              key: cognitiveGraphResetViewKey,
              tooltip: l10n.cognitiveGraphResetView,
              icon: const Icon(Icons.center_focus_strong),
              onPressed: () => _bodyKey.currentState?.resetView(),
            ),
        ],
      ),
      body: graph.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('${l10n.cognitiveErrorTitle}: $error')),
        data: (data) => data.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l10n.cognitiveGraphEmpty,
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : _GraphBody(key: _bodyKey, data: data),
      ),
    );
  }
}

class _GraphBody extends StatefulWidget {
  const _GraphBody({super.key, required this.data});

  final CognitiveGraphData data;

  @override
  State<_GraphBody> createState() => _GraphBodyState();
}

class _GraphBodyState extends State<_GraphBody> {
  /// 视口矩阵：自动适配时是"居中 + 等比缩放"，之后由拖动/缩放改写。
  final TransformationController _controller = TransformationController();

  GraphSelection? _selection;

  /// 用户动过视图（拖动/缩放/点了重置之外的手势）后，视口变化不再自动适配。
  bool _userAdjusted = false;

  Size? _viewport;
  double? _side;
  Size? _fittedViewport;
  double? _fittedSide;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 回到"自动缩放 + 居中"（AppBar 的"重置视图"）。
  void resetView() {
    _userAdjusted = false;
    final viewport = _viewport;
    final side = _side;
    if (viewport != null && side != null) {
      _fitView(viewport, side);
      setState(() {});
    }
  }

  void _fitView(Size viewport, double side) {
    if (viewport.isEmpty || side <= 0) {
      return;
    }
    final scale = math.min(viewport.width / side, viewport.height / side);
    _fittedViewport = viewport;
    _fittedSide = side;
    _controller.value = Matrix4.identity()
      ..translateByDouble(
        (viewport.width - side * scale) / 2,
        (viewport.height - side * scale) / 2,
        0.0,
        1.0,
      )
      ..scaleByDouble(scale, scale, scale, 1.0);
  }

  void _ensureFitted(Size viewport, double side) {
    if (_userAdjusted || (_fittedViewport == viewport && _fittedSide == side)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _userAdjusted) {
        return;
      }
      if (_viewport != viewport || _side != side) {
        return;
      }
      _fitView(viewport, side);
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final data = widget.data;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.cognitiveGraphHint,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                l10n.cognitiveGraphSummary(
                  data.points.length,
                  data.tags.length,
                  data.linkCount,
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final viewport = constraints.biggest;
              final side = cognitiveGraphCanvasSide(data.points.length);
              _viewport = viewport;
              _side = side;
              _ensureFitted(viewport, side);

              final layout = layoutCognitiveGraph(
                size: Size.square(side),
                points: data.points,
                tags: data.tags,
              );
              final fitScale = math.min(
                viewport.width / side,
                viewport.height / side,
              );

              return Stack(
                children: [
                  Positioned.fill(
                    child: InteractiveViewer(
                      key: cognitiveGraphViewportKey,
                      transformationController: _controller,
                      constrained: false,
                      boundaryMargin: const EdgeInsets.all(double.infinity),
                      minScale: math.min(0.4, fitScale),
                      maxScale: 4,
                      onInteractionStart: (_) => _userAdjusted = true,
                      child: SizedBox(
                        width: side,
                        height: side,
                        child: GestureDetector(
                          key: cognitiveGraphCanvasKey,
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (details) => setState(() {
                            _selection = hitTestCognitiveGraph(
                              layout,
                              details.localPosition,
                            );
                          }),
                          child: AnimatedBuilder(
                            animation: _controller,
                            builder: (context, _) => CustomPaint(
                              painter: CognitiveGraphPainter(
                                layout: layout,
                                data: data,
                                selection: _selection,
                                theme: theme,
                                scale: _controller.value.getMaxScaleOnAxis(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    bottom: 6,
                    child: IgnorePointer(
                      child: Text(
                        l10n.cognitiveGraphPanHint,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        _Legend(theme: theme),
        if (_selection == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              l10n.cognitiveGraphTapHint,
              style: theme.textTheme.bodySmall,
            ),
          )
        else
          _SelectionDetails(
            selection: _selection!,
            data: data,
          ),
      ],
    );
  }
}

class _SelectionDetails extends StatelessWidget {
  const _SelectionDetails({required this.selection, required this.data});

  final GraphSelection selection;
  final CognitiveGraphData data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final point = selection.point;
    final tag = selection.tag;

    final String title;
    final String detail;
    if (point != null) {
      final reading = data.readingsByPoint[point.id];
      title = point.title;
      detail = l10n.cognitiveGraphPointDetail(
        reading == null ? '—' : zoneLabel(l10n, reading.zone),
        reading?.cardCount ?? 0,
        reading?.meanR == null ? '—' : reading!.meanR!.toStringAsFixed(2),
      );
    } else if (tag != null) {
      title = '「${tag.title}」';
      detail = l10n.cognitiveGraphTagDetail(tag.memberCount);
    } else {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: ListTile(
        leading:
            Icon(Icons.visibility_outlined, color: theme.colorScheme.primary),
        title: Text(title),
        subtitle: Text(detail),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 只列会出现在图上的四种：有读数时不可用/健康是剩下的两端，其余是按颜色的
    // 语义分组展示（同色的不同区域在图例里不重复，颜色才是图的语言）。
    const shown = <ReviewZone>[
      ReviewZone.danger,
      ReviewZone.deadEnd,
      ReviewZone.empty,
      ReviewZone.overload,
      ReviewZone.slow,
      ReviewZone.offGoal,
      ReviewZone.proximal,
      ReviewZone.healthy,
      ReviewZone.unavailable,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
      child: Wrap(
        spacing: 10,
        runSpacing: 2,
        children: [
          for (final zone in shown)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: cognitiveGraphZoneColor(theme, zone),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  zoneLabel(l10n, zone),
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// 画图：簇轮廓 + 连线 + 标签方块 + 知识点圆点。
///
/// `scale` 是当前视口缩放比；小于 [kCognitiveGraphLabelMinScale] 时只画圆点与簇轮廓，
/// 文字全部省略 —— 小图上文字只会互相压住，读不出来。
class CognitiveGraphPainter extends CustomPainter {
  CognitiveGraphPainter({
    required this.layout,
    required this.data,
    required this.selection,
    required this.theme,
    required this.scale,
  });

  final CognitiveGraphLayout layout;
  final CognitiveGraphData data;
  final GraphSelection? selection;
  final ThemeData theme;
  final double scale;

  bool get showLabels => scale >= kCognitiveGraphLabelMinScale;

  @override
  void paint(Canvas canvas, Size size) {
    if (layout.isEmpty) {
      return;
    }

    final pointById = <String, GraphPointNode>{
      for (final point in layout.points) point.id: point,
    };
    final tagById = <String, GraphTagNode>{
      for (final tag in layout.tags) tag.id: tag,
    };

    final selectedPointId = selection?.point?.id;
    final selectedTagId = selection?.tag?.id;

    // 簇的范围：只画有成员的簇（半径 0 的簇没有轮廓可画）。
    final clusterPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = theme.colorScheme.outlineVariant.withValues(alpha: 0.45);
    for (final tag in layout.tags) {
      if (tag.clusterRadius <= 0) {
        continue;
      }
      canvas.drawCircle(
        tag.clusterCenter,
        tag.clusterRadius + kCognitiveGraphPointSpacing / 2,
        clusterPaint,
      );
    }

    // 连线：选中时把与它相连的线提亮，其余压暗。
    for (final link in layout.links) {
      final point = pointById[link.pointId];
      final tag = tagById[link.tagId];
      if (point == null || tag == null) {
        continue;
      }
      final active = selectedPointId == point.id || selectedTagId == tag.id;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? 2.2 : 1
        ..color =
            theme.colorScheme.outline.withValues(alpha: active ? 0.5 : 0.12);
      canvas.drawLine(point.center, tag.center, paint);
    }

    if (showLabels) {
      // 标签（方块）：画在簇的外侧，方块宽度随挂载数增加。
      for (final tag in layout.tags) {
        final selected = selectedTagId == tag.id;
        final paint = Paint()
          ..style = PaintingStyle.fill
          ..color = theme.colorScheme.surfaceContainerHighest;
        final stroke = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2.2 : 1
          ..color =
              selected ? theme.colorScheme.primary : theme.colorScheme.outline;
        final rect = Rect.fromCenter(
          center: tag.center,
          width: cognitiveGraphTagBoxWidth(tag),
          height: kCognitiveGraphTagBoxHeight,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(5)),
          paint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(5)),
          stroke,
        );
        _drawText(
          canvas,
          _truncate(tag.title, 6),
          tag.center,
          theme.textTheme.labelSmall ?? const TextStyle(fontSize: 10),
          kCognitiveGraphTagBoxHeight,
          center: true,
        );
      }
    }

    // 知识点（圆点），颜色 = 认知区域。
    final clusterCenterByTagId = <String, Offset>{
      for (final tag in layout.tags) tag.id: tag.clusterCenter,
    };
    for (final point in layout.points) {
      final reading = data.readingsByPoint[point.id];
      final color = reading == null
          ? theme.colorScheme.onSurfaceVariant
          : cognitiveGraphZoneColor(theme, reading.zone);
      final selected = selectedPointId == point.id;
      canvas.drawCircle(point.center, point.radius, Paint()..color = color);
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2.6 : 1.2
        ..color =
            selected ? theme.colorScheme.onSurface : theme.colorScheme.surface;
      canvas.drawCircle(
        point.center,
        point.radius + (selected ? 1.5 : 0),
        stroke,
      );

      if (!showLabels) {
        continue;
      }
      // 文字放在径向外侧（相对所属簇中心）；左半边右对齐，避免压到圆点。
      final origin = clusterCenterByTagId[point.groupTagId] ?? layout.center;
      final direction = point.center - origin;
      final unit = direction.distance <= 0
          ? const Offset(0, -1)
          : direction / direction.distance;
      final anchor = point.center + unit * (point.radius + 4);
      final onLeft = unit.dx < 0;
      _drawText(
        canvas,
        _truncate(point.title, 8),
        anchor,
        theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface,
            ) ??
            const TextStyle(fontSize: 10),
        _textWidth(theme, point.title),
        rightAlign: onLeft,
      );
    }
  }

  double _textWidth(ThemeData theme, String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: _truncate(text, 8),
        style: theme.textTheme.labelSmall,
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset anchor,
    TextStyle style,
    double width, {
    bool center = false,
    bool rightAlign = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: width + 8);
    final dx = center
        ? anchor.dx - painter.width / 2
        : rightAlign
            ? anchor.dx - painter.width
            : anchor.dx;
    final dy = anchor.dy - painter.height / 2;
    painter.paint(canvas, Offset(dx, dy));
  }

  String _truncate(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max)}…';

  @override
  bool shouldRepaint(covariant CognitiveGraphPainter oldDelegate) =>
      oldDelegate.layout != layout ||
      oldDelegate.selection != selection ||
      oldDelegate.data != data ||
      oldDelegate.theme != theme ||
      oldDelegate.scale != scale;
}

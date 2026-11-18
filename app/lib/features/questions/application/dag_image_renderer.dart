/// 把一条 AI 解题思维链（`reasoning_chains` / `reasoning_steps`）画成一张
/// 可读的 **PNG 图片**：每步一个节点、步骤之间用箭头连起来、左侧编号表示分层，
/// 节点颜色/风险条表示卡点风险。
///
/// 为什么在 Dart 里画（`dart:ui` 的 Canvas → `Picture.toImage` → PNG）而不是抓
/// 一个 Flutter widget 的 `RepaintBoundary`：
///
///  * 详情页在任何屏幕宽度下都显示同一张图，图片本身与视口无关；
///  * 生成发生在数据侧（`DagImageStore`），不依赖 widget 已经上屏、不依赖
///    `afterFirstFrame`，失败能带着原因回给界面；
///  * 图片可以真的落盘（`question_dag_images/<chainId>.png`），下次打开直接读缓存。
///
/// 字体：用应用内置的 Noto Sans SC（`assets/fonts/noto-sans-sc-regular.ttf`，
/// 与 PDF 导出同一份资产），保证 Windows / Android 上中文都真的画得出来；字体
/// 加载失败时退回引擎默认字体（英文/数字可读、中文取决于系统回退），**不**因为
/// 字体问题让整张图失败。
///
/// 这里只画"图"：节点内容是每步的目标（goal）与能力动作标签，完整文字链
/// （justification / checkMethod / 知识点）留在页面的文字明细里。图片不是把
/// 整段文字抄进白底。
library;

import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import '../../../domain/services/reasoning/reasoning_prompt.dart';

/// 生成失败（可把 message 直接显示给用户）。
class DagImageRenderException implements Exception {
  const DagImageRenderException(this.message);

  final String message;

  @override
  String toString() => 'DagImageRenderException: $message';
}

/// 一张画好的 DAG 图片。
class DagImageRenderResult {
  const DagImageRenderResult({
    required this.bytes,
    required this.width,
    required this.height,
    required this.nodeCount,
    required this.edgeCount,
  });

  final Uint8List bytes;
  final int width;
  final int height;

  /// 画了多少个步骤节点 / 多少条箭头。测试与诊断用；正常链是 `steps.length`
  /// 与 `steps.length - 1`。
  final int nodeCount;
  final int edgeCount;

  bool get isPng =>
      bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47;
}

/// 思维链 → PNG。
class DagImageRenderer {
  DagImageRenderer({Future<ByteData> Function(String path)? loadAsset})
      : _loadAsset = loadAsset;

  /// 内置中文字体资产（与 `MarkdownPdfFontResolver` 用的是同一份 TTF）。
  static const String fontAssetPath = 'assets/fonts/noto-sans-sc-regular.ttf';

  /// 注册到引擎里的字体族名；与资产里的真实字体名无关，只是本渲染器自己的
  /// 句柄。
  static const String fontFamily = 'FurnaceDagImageFont';

  /// 画布宽度固定：图片是给详情页读的，不做响应式（下一版才做自适应渲染）。
  static const double imageWidth = 960;

  /// null = 用内置字体资产（默认行为）。测试可注入自己的加载函数。
  final Future<ByteData> Function(String path)? _loadAsset;

  /// 字体只装一次；`false` 表示资产不可用，之后都用默认字体。
  ///
  /// 默认资产加载在**进程级**缓存，并且刻意缓存"已注册"这个**同步标记**而不是
  /// 缓存一个 Future：widget 测试每个用例都在自己的 fake-async zone 里，跨用例
  /// await 上一个 zone 创建的 Future 会把微任务排进已经停掉的队列，渲染就永远
  /// 不会继续（本仓库的测试确实踩到过）。注入 loader 的渲染器不共享缓存。
  static Uint8List? _bundledFontBytes;
  static bool _bundledFontRegistered = false;

  Future<bool>? _fontReady;

  Future<bool> _ensureFont() {
    final loader = _loadAsset;
    if (loader != null) {
      return _fontReady ??= _loadWith(loader);
    }
    if (_bundledFontRegistered) {
      return Future<bool>.value(true);
    }
    return _fontReady ??= _loadBundled();
  }

  Future<bool> _loadBundled() async {
    try {
      final bytes = _bundledFontBytes ??= await _loadBundledBytes();
      final loader = FontLoader(fontFamily)
        ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      await loader.load();
      _bundledFontRegistered = true;
      return true;
    } on Object {
      // 字体只是排版的一部分：缺了它图片仍然要生成（灰底黑框 + 默认字体）。
      return false;
    }
  }

  static Future<Uint8List> _loadBundledBytes() async {
    final data = await rootBundle.load(fontAssetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  Future<bool> _loadWith(
    Future<ByteData> Function(String path) loadAsset,
  ) async {
    try {
      final data = await loadAsset(fontAssetPath);
      final loader = FontLoader(fontFamily)..addFont(Future<ByteData>.value(data));
      await loader.load();
      return true;
    } on Object {
      // 字体只是排版的一部分：缺了它图片仍然要生成（灰底黑框 + 默认字体）。
      return false;
    }
  }

  /// 把 [chain] 画成 PNG。
  ///
  /// 空链直接抛 [DagImageRenderException]——"没有步骤"是页面该显示空态的情况，
  /// 不该生成一张只有标题的白图。
  Future<DagImageRenderResult> render(
    ParsedChain chain, {
    String title = '思维 DAG',
  }) async {
    if (chain.steps.isEmpty) {
      throw const DagImageRenderException('这条思维链没有步骤，画不出 DAG 图片');
    }
    final fontLoaded = await _ensureFont();
    final family = fontLoaded ? fontFamily : null;

    final plan = _Layout.build(chain, title: title, fontFamily: family);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, plan.width, plan.height),
    );
    try {
      plan.paint(canvas);
      final picture = recorder.endRecording();
      ui.Image? image;
      try {
        image = await picture.toImage(
          plan.width.round(),
          plan.height.round(),
        );
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) {
          throw const DagImageRenderException('图片编码失败：引擎没有返回 PNG 字节');
        }
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        if (bytes.isEmpty) {
          throw const DagImageRenderException('图片编码失败：PNG 字节为空');
        }
        return DagImageRenderResult(
          bytes: bytes,
          width: image.width,
          height: image.height,
          nodeCount: plan.nodes.length,
          edgeCount: plan.edges.length,
        );
      } finally {
        image?.dispose();
        picture.dispose();
      }
    } finally {
      plan.dispose();
    }
  }
}

// ---------------------------------------------------------------------------
// 布局与绘制
// ---------------------------------------------------------------------------

const double _margin = 32;
const double _railWidth = 64;
const double _nodePad = 16;
const double _nodeStripe = 6;
const double _nodeGap = 36;
const double _nodeRadius = 10;

const ui.Color _ink = ui.Color(0xFF101820);
const ui.Color _bodyInk = ui.Color(0xFF27313A);
const ui.Color _muted = ui.Color(0xFF5B6770);
const ui.Color _border = ui.Color(0xFFC5CFD6);
const ui.Color _hairline = ui.Color(0xFFE3E8EC);
const ui.Color _barTrack = ui.Color(0xFFE8EDF1);
const ui.Color _white = ui.Color(0xFFFFFFFF);

/// 卡点风险 → 颜色：低绿、中橙、高红。颜色是图片里唯一的"语义颜色"。
ui.Color _riskColor(double risk) {
  if (risk >= 0.67) {
    return const ui.Color(0xFFB3261E);
  }
  if (risk >= 0.34) {
    return const ui.Color(0xFFB26A00);
  }
  return const ui.Color(0xFF1E7B4B);
}

ui.Color _riskTint(double risk) {
  if (risk >= 0.67) {
    return const ui.Color(0xFFFCE8E6);
  }
  if (risk >= 0.34) {
    return const ui.Color(0xFFFDF1DE);
  }
  return const ui.Color(0xFFE7F4EC);
}

class _Layout {
  _Layout({
    required this.width,
    required this.height,
    required this.nodes,
    required this.edges,
    required this.title,
    required this.summary,
    required this.legend,
    required this.footer,
    required this.fontFamily,
  });

  final double width;
  final double height;
  final List<_NodePlan> nodes;
  final List<_EdgePlan> edges;
  final _TextPlan title;
  final _TextPlan summary;
  final _TextPlan legend;
  final _TextPlan footer;
  final String? fontFamily;

  factory _Layout.build(
    ParsedChain chain, {
    required String title,
    required String? fontFamily,
  }) {
    const nodeX = _margin + _railWidth;
    const nodeWidth = DagImageRenderer.imageWidth - nodeX - _margin;
    const innerWidth = nodeWidth - _nodePad * 2 - _nodeStripe - 4;

    final titleText = title.trim().isEmpty ? '思维 DAG' : title.trim();
    final titlePlan = _TextPlan(
      titleText,
      _paragraph(
        titleText,
        size: 25,
        weight: ui.FontWeight.w700,
        color: _ink,
        maxWidth: DagImageRenderer.imageWidth - _margin * 2,
        maxLines: 1,
        family: fontFamily,
      ),
      x: _margin,
      y: 0,
    );
    final summaryText = chain.summary.trim();
    final summaryPlan = _TextPlan(
      summaryText,
      _paragraph(
        summaryText,
        size: 14,
        color: _bodyInk,
        maxWidth: DagImageRenderer.imageWidth - _margin * 2,
        maxLines: 3,
        lineHeight: 1.4,
        family: fontFamily,
      ),
      x: _margin,
      y: 0,
    );
    const legendText = '方框 = 一步 · 箭头 = 先后顺序 · 左侧编号 = 第几步（每步一层）'
        ' · 颜色 = 卡点风险（绿低 / 橙中 / 红高）';
    final legendPlan = _TextPlan(
      legendText,
      _paragraph(
        legendText,
        size: 12,
        color: _muted,
        maxWidth: DagImageRenderer.imageWidth - _margin * 2,
        maxLines: 1,
        family: fontFamily,
      ),
      x: _margin,
      y: 0,
    );

    var y = 26.0;
    titlePlan.y = y;
    y += titlePlan.height + 6;
    if (summaryText.isNotEmpty) {
      summaryPlan.y = y;
      y += summaryPlan.height + 8;
    } else {
      summaryPlan.y = y;
    }
    legendPlan.y = y;
    y += legendPlan.height + 14;

    final nodes = <_NodePlan>[];
    var nodeTop = y + 16;
    final steps = List<ParsedStep>.of(chain.steps)
      ..sort((a, b) => a.index.compareTo(b.index));
    for (final step in steps) {
      final actionLabel = _actionLabel(step);
      final known = step.action != null;
      final risk = step.stuckRisk.clamp(0.0, 1.0).toDouble();
      final badgeText = '卡点 ${(risk * 100).round()}%';
      final badge = _TextPlan(
        badgeText,
        _paragraph(
          badgeText,
          size: 11.5,
          weight: ui.FontWeight.w600,
          color: _riskColor(risk),
          maxWidth: 140,
          maxLines: 1,
          family: fontFamily,
        ),
        x: 0,
        y: 0,
      );
      final badgeWidth = badge.width + 18;
      final actionLabelPlan = _TextPlan(
        actionLabel,
        _paragraph(
          actionLabel,
          size: 16,
          weight: ui.FontWeight.w700,
          color: _ink,
          maxWidth: innerWidth - badgeWidth - 8,
          maxLines: 1,
          family: fontFamily,
        ),
        x: 0,
        y: 0,
      );
      final goalText =
          step.goal.trim().isEmpty ? '（这一步没有写目标）' : step.goal.trim();
      final goal = _TextPlan(
        goalText,
        _paragraph(
          goalText,
          size: 14.5,
          color: _bodyInk,
          maxWidth: innerWidth,
          maxLines: 3,
          lineHeight: 1.42,
          family: fontFamily,
        ),
        x: 0,
        y: 0,
      );
      final headerHeight =
          actionLabelPlan.height > 20 ? actionLabelPlan.height : 20.0;
      final nodeHeight =
          _nodePad + headerHeight + 6 + goal.height + 10 + 4 + 12;
      nodes.add(_NodePlan(
        step: step,
        x: nodeX,
        y: nodeTop,
        width: nodeWidth,
        height: nodeHeight,
        innerWidth: innerWidth,
        risk: risk,
        knownAction: known,
        action: actionLabelPlan,
        goal: goal,
        badge: badge,
        badgeWidth: badgeWidth,
        headerHeight: headerHeight,
      ));
      nodeTop += nodeHeight + _nodeGap;
    }

    final edges = <_EdgePlan>[];
    const centerX = nodeX + nodeWidth / 2;
    for (var i = 0; i + 1 < nodes.length; i++) {
      final from = nodes[i];
      final to = nodes[i + 1];
      edges.add(_EdgePlan(
        fromX: centerX,
        fromY: from.y + from.height + 2,
        toX: centerX,
        toY: to.y - 3,
      ));
    }

    final footerText = 'Furnace · AI 解题思维链 · 共 ${nodes.length} 步';
    final footer = _TextPlan(
      footerText,
      _paragraph(
        footerText,
        size: 11,
        color: _muted,
        maxWidth: DagImageRenderer.imageWidth - _margin * 2,
        maxLines: 1,
        family: fontFamily,
      ),
      x: _margin,
      y: nodeTop - _nodeGap + 18,
    );
    final height = footer.y + footer.height + 22;

    return _Layout(
      width: DagImageRenderer.imageWidth,
      height: height < 240 ? 240 : height,
      nodes: nodes,
      edges: edges,
      title: titlePlan,
      summary: summaryPlan,
      legend: legendPlan,
      footer: footer,
      fontFamily: fontFamily,
    );
  }

  static String _actionLabel(ParsedStep step) {
    final known = step.action?.labelZh.trim() ?? '';
    if (known.isNotEmpty) {
      return known;
    }
    final raw = step.actionType.trim();
    return raw.isEmpty ? '未知动作' : raw;
  }

  void paint(ui.Canvas canvas) {
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width, height),
      ui.Paint()..color = _white,
    );

    title.draw(canvas);
    if (summary.text.isNotEmpty) {
      summary.draw(canvas);
    }
    legend.draw(canvas);
    final lineY = legend.y + legend.height + 8;
    canvas.drawLine(
      ui.Offset(_margin, lineY),
      ui.Offset(width - _margin, lineY),
      ui.Paint()
        ..color = _hairline
        ..strokeWidth = 1,
    );

    // 左侧竖向轨道（分层）：把每一步的编号串起来。
    if (nodes.length > 1) {
      const railX = _margin + 24;
      _dashedLine(
        canvas,
        ui.Offset(railX, nodes.first.y + nodes.first.height / 2),
        ui.Offset(railX, nodes.last.y + nodes.last.height / 2),
        _border,
      );
    }
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final centerY = node.y + node.height / 2;
      _paintRailBadge(
        canvas,
        centerX: _margin + 24,
        centerY: centerY,
        index: i + 1,
        risk: node.risk,
        fontFamily: fontFamily,
      );
    }

    for (final edge in edges) {
      _paintArrow(canvas, edge);
    }
    for (final node in nodes) {
      node.paint(canvas);
    }

    footer.draw(canvas);
  }

  void dispose() {
    title.dispose();
    summary.dispose();
    legend.dispose();
    footer.dispose();
    for (final node in nodes) {
      node.dispose();
    }
  }
}

class _NodePlan {
  _NodePlan({
    required this.step,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.innerWidth,
    required this.risk,
    required this.knownAction,
    required this.action,
    required this.goal,
    required this.badge,
    required this.badgeWidth,
    required this.headerHeight,
  });

  final ParsedStep step;
  final double x;
  final double y;
  final double width;
  final double height;
  final double innerWidth;
  final double risk;
  final bool knownAction;
  final _TextPlan action;
  final _TextPlan goal;
  final _TextPlan badge;
  final double badgeWidth;
  final double headerHeight;

  void paint(ui.Canvas canvas) {
    final riskColor = _riskColor(risk);
    final rect = ui.Rect.fromLTWH(x, y, width, height);
    final rrect = ui.RRect.fromRectAndRadius(
      rect,
      const ui.Radius.circular(_nodeRadius),
    );
    canvas.drawRRect(
      rrect,
      ui.Paint()..color = _white,
    );
    canvas.drawRRect(
      rrect,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = knownAction ? _border : riskColor,
    );
    // 左边缘的粗色条：颜色即卡点风险。
    final stripe = ui.RRect.fromRectAndCorners(
      ui.Rect.fromLTWH(x, y, _nodeStripe, height),
      topLeft: const ui.Radius.circular(_nodeRadius),
      bottomLeft: const ui.Radius.circular(_nodeRadius),
    );
    canvas.drawRRect(stripe, ui.Paint()..color = riskColor);

    final contentX = x + _nodePad + _nodeStripe + 4;
    action.x = contentX;
    action.y = y + _nodePad;
    action.draw(canvas);

    // 右上角风险徽标。
    final badgeLeft = x + width - _nodePad - badgeWidth;
    final badgeTop = y + _nodePad - 2;
    final badgeRect = ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(badgeLeft, badgeTop, badgeWidth, 20),
      const ui.Radius.circular(10),
    );
    canvas.drawRRect(badgeRect, ui.Paint()..color = _riskTint(risk));
    badge.x = badgeLeft + 9;
    badge.y = badgeTop + 3;
    badge.draw(canvas);

    goal.x = contentX;
    goal.y = y + _nodePad + headerHeight + 6;
    goal.draw(canvas);

    // 风险进度条。
    final barTop = goal.y + goal.height + 10;
    final barLeft = contentX;
    final barWidth = x + width - _nodePad - contentX;
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(barLeft, barTop, barWidth, 4),
        const ui.Radius.circular(2),
      ),
      ui.Paint()..color = _barTrack,
    );
    if (risk > 0) {
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(barLeft, barTop, barWidth * risk, 4),
          const ui.Radius.circular(2),
        ),
        ui.Paint()..color = riskColor,
      );
    }
  }

  void dispose() {
    action.dispose();
    goal.dispose();
    badge.dispose();
  }
}

class _EdgePlan {
  const _EdgePlan({
    required this.fromX,
    required this.fromY,
    required this.toX,
    required this.toY,
  });

  final double fromX;
  final double fromY;
  final double toX;
  final double toY;
}

class _TextPlan {
  _TextPlan(this.text, this.paragraph, {required this.x, required this.y});

  final String text;
  final ui.Paragraph paragraph;
  double x;
  double y;

  double get width => paragraph.maxIntrinsicWidth;
  double get height => paragraph.height;

  void draw(ui.Canvas canvas) {
    canvas.drawParagraph(paragraph, ui.Offset(x, y));
  }

  void dispose() => paragraph.dispose();
}

ui.Paragraph _paragraph(
  String text, {
  required double size,
  required ui.Color color,
  required double maxWidth,
  ui.FontWeight weight = ui.FontWeight.w400,
  int maxLines = 1,
  double lineHeight = 1.3,
  String? family,
}) {
  final builder = ui.ParagraphBuilder(
    ui.ParagraphStyle(
      textDirection: ui.TextDirection.ltr,
      fontFamily: family,
      fontSize: size,
      maxLines: maxLines,
      ellipsis: '…',
      height: lineHeight,
    ),
  )
    ..pushStyle(ui.TextStyle(
      color: color,
      fontSize: size,
      fontWeight: weight,
      fontFamily: family,
      height: lineHeight,
    ))
    ..addText(text);
  return builder.build()..layout(ui.ParagraphConstraints(width: maxWidth));
}

void _dashedLine(
  ui.Canvas canvas,
  ui.Offset from,
  ui.Offset to,
  ui.Color color,
) {
  final paint = ui.Paint()
    ..color = color
    ..strokeWidth = 1.4;
  const dash = 6.0;
  const gap = 5.0;
  var y = from.dy;
  while (y < to.dy) {
    final end = (y + dash).clamp(y, to.dy).toDouble();
    canvas.drawLine(ui.Offset(from.dx, y), ui.Offset(to.dx, end), paint);
    y = end + gap;
  }
}

void _paintRailBadge(
  ui.Canvas canvas, {
  required double centerX,
  required double centerY,
  required int index,
  required double risk,
  required String? fontFamily,
}) {
  const radius = 14.0;
  canvas.drawCircle(
    ui.Offset(centerX, centerY),
    radius,
    ui.Paint()..color = _white,
  );
  canvas.drawCircle(
    ui.Offset(centerX, centerY),
    radius,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..color = _riskColor(risk),
  );
  final label = _paragraph(
    '$index',
    size: 12,
    weight: ui.FontWeight.w700,
    color: _riskColor(risk),
    maxWidth: radius * 2,
    family: fontFamily,
  );
  canvas.drawParagraph(
    label,
    ui.Offset(centerX - label.maxIntrinsicWidth / 2, centerY - label.height / 2),
  );
  label.dispose();
}

void _paintArrow(ui.Canvas canvas, _EdgePlan edge) {
  final paint = ui.Paint()
    ..color = _muted
    ..strokeWidth = 1.8
    ..strokeCap = ui.StrokeCap.round;
  canvas.drawLine(
    ui.Offset(edge.fromX, edge.fromY),
    ui.Offset(edge.toX, edge.toY),
    paint,
  );
  const halfWidth = 5.0;
  const height = 9.0;
  final head = ui.Path()
    ..moveTo(edge.toX, edge.toY)
    ..lineTo(edge.toX - halfWidth, edge.toY - height)
    ..lineTo(edge.toX + halfWidth, edge.toY - height)
    ..close();
  canvas.drawPath(
    head,
    ui.Paint()..color = _muted,
  );
}

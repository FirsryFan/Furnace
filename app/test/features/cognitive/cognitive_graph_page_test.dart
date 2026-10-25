// 用户要求："认知模型我希望有一个只读的可视化界面"；第二轮反馈"知识网络图依旧完全没有可用性"。
//
// 这一页是同一批读数（`cognitiveReadingsProvider`）的另一种画法：知识点 ↔ 标签网络。
// 测试钉四件事：页面画出来什么、初始视图是否自动装下整张图、缩放后文字是否让位给圆点、
// 以及缩放/平移之后点节点还能不能看到只读详情。"只读"由结构保证（本页只 watch provider），
// 页面测试用同一个 fixture 驱动，不碰数据库。
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/anki/application/review_advisory.dart'
    show ReviewZone;
import 'package:furnace/features/cognitive/presentation/cognitive_graph_layout.dart';
import 'package:furnace/features/cognitive/presentation/cognitive_graph_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

void main() {
  late AppLocalizations zh;

  setUpAll(() async {
    zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  const tags = <CognitiveGraphTagInput>[
    CognitiveGraphTagInput(id: 'tag-a', title: '函数'),
    CognitiveGraphTagInput(id: 'tag-b', title: '概率'),
  ];
  const points = <CognitiveGraphPointInput>[
    CognitiveGraphPointInput(
      id: 'kp-1',
      title: '二次函数',
      cardCount: 2,
      tagIds: <String>{'tag-a'},
    ),
    CognitiveGraphPointInput(
      id: 'kp-2',
      title: '条件概率',
      cardCount: 1,
      tagIds: <String>{'tag-a', 'tag-b'},
    ),
  ];
  const graph = CognitiveGraphData(
    points: points,
    tags: tags,
    readingsByPoint: <String, CognitiveGraphPointReading>{
      'kp-1': CognitiveGraphPointReading(
        zone: ReviewZone.danger,
        cardCount: 2,
        meanR: 0.42,
      ),
      'kp-2': CognitiveGraphPointReading(
        zone: ReviewZone.proximal,
        cardCount: 1,
        meanR: 0.66,
      ),
    },
    pointTitles: <String, String>{'kp-1': '二次函数', 'kp-2': '条件概率'},
    tagTitles: <String, String>{'tag-a': '函数', 'tag-b': '概率'},
  );

  Future<void> pumpPage(WidgetTester tester, CognitiveGraphData data) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cognitiveGraphProvider.overrideWith((ref) async => data),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: CognitiveGraphPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  TransformationController controllerOf(WidgetTester tester) => tester
      .widget<InteractiveViewer>(find.byKey(cognitiveGraphViewportKey))
      .transformationController!;

  CognitiveGraphPainter painterOf(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint && widget.painter is CognitiveGraphPainter,
      ),
    );
    return paint.painter! as CognitiveGraphPainter;
  }

  /// 画布坐标 → 屏幕坐标：视口左上角 + 当前矩阵变换（child 用 constrained:false，
  /// 左上角与视口左上角重合；见 `_InteractiveViewerBuilt` 的 OverflowBox(topLeft)）。
  Offset screenOf(WidgetTester tester, Matrix4 matrix, Offset scene) {
    final rect = tester.getRect(find.byKey(cognitiveGraphViewportKey));
    return rect.topLeft + MatrixUtils.transformPoint(matrix, scene);
  }

  testWidgets('画出标题/说明/摘要/图例/缩放容器；首次进入自动缩放居中', (tester) async {
    await pumpPage(tester, graph);

    expect(find.text(zh.cognitiveGraphTitle), findsOneWidget);
    expect(find.text(zh.cognitiveGraphHint), findsOneWidget);
    // 2 个知识点 · 2 个标签 · 3 条连线（kp-1 一条 + kp-2 两条）。
    expect(find.text(zh.cognitiveGraphSummary(2, 2, 3)), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byKey(cognitiveGraphCanvasKey), findsOneWidget);
    expect(find.byKey(cognitiveGraphResetViewKey), findsOneWidget);
    expect(find.text(zh.cognitiveGraphPanHint), findsOneWidget);

    // 图例里有区域词（与读数页共用 zoneLabel）。
    expect(find.text(zh.cognitiveZoneDanger), findsOneWidget);
    expect(find.text(zh.cognitiveZoneProximal), findsOneWidget);

    // 初始矩阵不是单位阵：画布按视口等比缩放并居中（侧边留白对称）。
    final rect = tester.getRect(find.byKey(cognitiveGraphViewportKey));
    final controller = controllerOf(tester);
    final value = controller.value;
    const side = kCognitiveGraphBaseSide;
    final expectedScale = math.min(rect.width / side, rect.height / side);
    expect(value.getMaxScaleOnAxis(), closeTo(expectedScale, 1e-6));
    final translation = value.getTranslation();
    expect(
      translation.x,
      closeTo((rect.width - side * expectedScale) / 2, 1e-6),
    );
    expect(
      translation.y,
      closeTo((rect.height - side * expectedScale) / 2, 1e-6),
    );
  });

  testWidgets('缩得太小时只留圆点（文字隐藏），放大回来文字又出现', (tester) async {
    await pumpPage(tester, graph);

    final controller = controllerOf(tester);
    expect(painterOf(tester).showLabels, isTrue);

    controller.value = Matrix4.identity()..scaleByDouble(0.5, 0.5, 0.5, 1.0);
    await tester.pump();
    expect(painterOf(tester).showLabels, isFalse);

    controller.value = Matrix4.identity()..scaleByDouble(2.0, 2.0, 2.0, 1.0);
    await tester.pump();
    expect(painterOf(tester).showLabels, isTrue);
  });

  testWidgets('重置视图回到自动缩放的位置', (tester) async {
    await pumpPage(tester, graph);

    final controller = controllerOf(tester);
    final fitStorage = List<double>.from(controller.value.storage);

    controller.value = Matrix4.identity()
      ..translateByDouble(30.0, 40.0, 0.0, 1.0)
      ..scaleByDouble(2.0, 2.0, 2.0, 1.0);
    await tester.pump();

    await tester.tap(find.byKey(cognitiveGraphResetViewKey));
    await tester.pumpAndSettle();

    for (var index = 0; index < 16; index++) {
      expect(controller.value.storage[index], closeTo(fitStorage[index], 1e-9));
    }
  });

  testWidgets('缩放平移之后点节点与标签仍能选中', (tester) async {
    await pumpPage(tester, graph);

    final controller = controllerOf(tester);
    // 模拟用户手动缩放 + 平移（矩阵直接写入，等价于一次手势后的状态）。
    controller.value = Matrix4.identity()
      ..translateByDouble(20.0, 30.0, 0.0, 1.0)
      ..scaleByDouble(1.4, 1.4, 1.4, 1.0);
    await tester.pump();

    final layout = layoutCognitiveGraph(
      size: const Size.square(kCognitiveGraphBaseSide),
      points: graph.points,
      tags: graph.tags,
    );
    final point = layout.points.firstWhere((node) => node.id == 'kp-2');
    await tester.tapAt(screenOf(tester, controller.value, point.center));
    await tester.pumpAndSettle();

    // 详情是只读的一行字：区域 + 卡片数 + 平均 R。
    expect(
      find.text(
        zh.cognitiveGraphPointDetail(
          zh.cognitiveZoneProximal,
          1,
          '0.66',
        ),
      ),
      findsOneWidget,
    );

    // 点标签（方块）也能看挂载数；选中详情卡出现后视口高度可能变化，重新取矩阵与矩形。
    final tag = layout.tags.firstWhere((node) => node.id == 'tag-b');
    await tester.tapAt(screenOf(tester, controller.value, tag.center));
    await tester.pumpAndSettle();
    // 这份 fixture 里 tag-b（概率）只挂在 kp-2 上，挂载数是 1。
    expect(find.text(zh.cognitiveGraphTagDetail(1)), findsOneWidget);
  });

  testWidgets('没有读数时给出空态，而不是画一张空白画布', (tester) async {
    await pumpPage(tester, CognitiveGraphData.empty);

    expect(find.text(zh.cognitiveGraphEmpty), findsOneWidget);
    expect(find.byKey(cognitiveGraphCanvasKey), findsNothing);
    expect(find.byKey(cognitiveGraphViewportKey), findsNothing);
    expect(find.byKey(cognitiveGraphResetViewKey), findsNothing);
  });
}

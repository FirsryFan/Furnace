// 用户要求："认知模型我希望有一个只读的可视化界面"；随后两轮反馈"知识网络图依旧完全没有可用性"。
//
// 这一页是同一批读数（`cognitiveReadingsProvider`）的另一种画法：知识点 ↔ 标签网络。
// v3 的可用性补丁：顶部搜索框、点知识点弹底部详情（可点标签直接筛图）、右上角切列表视图。
// 测试钉住：页面画出来什么、初始自动缩放居中、缩小时文字让位给圆点、缩放/平移后点节点
// 仍能看到详情、搜索与标签筛选只布局命中的点、列表分组正确且点一行能回到图谱并居中。
// "只读"由结构保证（本页只 watch provider），页面测试用同一个 fixture 驱动，不碰数据库。
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
    CognitiveGraphPointInput(
      id: 'kp-3',
      title: '自由落体',
      cardCount: 1,
    ),
    CognitiveGraphPointInput(
      id: 'kp-4',
      title: '随机变量',
      cardCount: 3,
      tagIds: <String>{'tag-b'},
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
      'kp-3': CognitiveGraphPointReading(
        zone: ReviewZone.healthy,
        cardCount: 1,
        meanR: 0.80,
      ),
      'kp-4': CognitiveGraphPointReading(
        zone: ReviewZone.overload,
        cardCount: 3,
        meanR: 0.45,
      ),
    },
    pointTitles: <String, String>{
      'kp-1': '二次函数',
      'kp-2': '条件概率',
      'kp-3': '自由落体',
      'kp-4': '随机变量',
    },
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

  Set<String> painterPointIds(WidgetTester tester) =>
      painterOf(tester).layout.points.map((node) => node.id).toSet();

  /// 画布坐标 → 屏幕坐标：视口左上角 + 当前矩阵变换（child 用 constrained:false，
  /// 左上角与视口左上角重合；见 `_InteractiveViewerBuilt` 的 OverflowBox(topLeft)）。
  Offset screenOf(WidgetTester tester, Matrix4 matrix, Offset scene) {
    final rect = tester.getRect(find.byKey(cognitiveGraphViewportKey));
    return rect.topLeft + MatrixUtils.transformPoint(matrix, scene);
  }

  /// 按当前 graph 数据算一次布局，取某个知识点/标签的画布坐标。
  CognitiveGraphLayout layoutOf(WidgetTester tester) => layoutCognitiveGraph(
        size: Size.square(
          cognitiveGraphCanvasSide(painterOf(tester).layout.points.length),
        ),
        points: graph.points,
        tags: graph.tags,
      );

  Future<void> tapScene(WidgetTester tester, Offset scene) async {
    await tester.tapAt(screenOf(tester, controllerOf(tester).value, scene));
    await tester.pumpAndSettle();
  }

  testWidgets('画出标题/说明/摘要/图例/搜索框/缩放容器；首次进入自动缩放居中', (tester) async {
    await pumpPage(tester, graph);

    expect(find.text(zh.cognitiveGraphTitle), findsOneWidget);
    expect(find.text(zh.cognitiveGraphHint), findsOneWidget);
    // 4 个知识点 · 2 个标签 · 4 条连线（kp-1 一条 + kp-2 两条 + kp-4 一条）。
    expect(find.text(zh.cognitiveGraphSummary(4, 2, 4)), findsOneWidget);
    expect(find.byKey(cognitiveGraphSearchKey), findsOneWidget);
    expect(find.byKey(cognitiveGraphViewToggleKey), findsOneWidget);
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
    final side = cognitiveGraphCanvasSide(graph.points.length);
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

  testWidgets('缩放平移之后点知识点弹详情、点标签仍有选中详情', (tester) async {
    await pumpPage(tester, graph);

    final controller = controllerOf(tester);
    // 模拟用户手动缩放 + 平移（矩阵直接写入，等价于一次手势后的状态）。
    controller.value = Matrix4.identity()
      ..translateByDouble(20.0, 30.0, 0.0, 1.0)
      ..scaleByDouble(1.4, 1.4, 1.4, 1.0);
    await tester.pump();

    final layout = layoutOf(tester);
    final point = layout.points.firstWhere((node) => node.id == 'kp-2');
    await tapScene(tester, point.center);

    final sheet = find.byKey(cognitiveGraphDetailSheetKey);
    expect(sheet, findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.text('条件概率')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text(zh.cognitiveZoneProximal)),
      findsOneWidget,
    );
    expect(
        find.descendant(of: sheet, matching: find.text('1')), findsOneWidget);
    expect(
      find.descendant(
        of: sheet,
        matching: find.text(zh.cognitiveRetrievability('0.66')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
          of: sheet, matching: find.text(zh.cognitiveGraphDetailTags)),
      findsOneWidget,
    );

    // 点空白（barrier）关掉 sheet，再点标签方块：图下方出现标签的只读详情。
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byKey(cognitiveGraphDetailSheetKey), findsNothing);

    final tag = layout.tags.firstWhere((node) => node.id == 'tag-b');
    await tapScene(tester, tag.center);
    // 这份 fixture 里 tag-b（概率）挂在 kp-2 与 kp-4 上，挂载数是 2。
    expect(find.text(zh.cognitiveGraphTagDetail(2)), findsOneWidget);
  });

  testWidgets('搜索：只布局命中的知识点，摘要换成命中数', (tester) async {
    await pumpPage(tester, graph);

    await tester.enterText(find.byKey(cognitiveGraphSearchKey), '概率');
    await tester.pumpAndSettle();

    // kp-2（标题/标签都含"概率"）与 kp-4（标签是概率）命中。
    expect(find.text(zh.cognitiveGraphSearchCount(2)), findsOneWidget);
    expect(painterPointIds(tester), <String>{'kp-2', 'kp-4'});
    expect(find.byKey(cognitiveGraphCanvasKey), findsOneWidget);
    expect(find.byKey(cognitiveGraphSearchClearKey), findsOneWidget);
  });

  testWidgets('搜索没有命中时给空态与清除按钮，画布收起', (tester) async {
    await pumpPage(tester, graph);

    await tester.enterText(find.byKey(cognitiveGraphSearchKey), '不存在的东西');
    await tester.pumpAndSettle();

    expect(find.text(zh.cognitiveGraphSearchCount(0)), findsOneWidget);
    expect(find.text(zh.cognitiveGraphSearchEmpty), findsOneWidget);
    expect(find.byKey(cognitiveGraphCanvasKey), findsNothing);
    expect(find.byKey(cognitiveGraphSearchClearKey), findsOneWidget);
  });

  testWidgets('清除搜索恢复整张图', (tester) async {
    await pumpPage(tester, graph);

    await tester.enterText(find.byKey(cognitiveGraphSearchKey), '概率');
    await tester.pumpAndSettle();
    expect(find.text(zh.cognitiveGraphSearchCount(2)), findsOneWidget);

    await tester.tap(find.byKey(cognitiveGraphSearchClearKey));
    await tester.pumpAndSettle();

    expect(find.text(zh.cognitiveGraphSummary(4, 2, 4)), findsOneWidget);
    expect(find.byKey(cognitiveGraphSearchClearKey), findsNothing);
    expect(painterPointIds(tester), <String>{'kp-1', 'kp-2', 'kp-3', 'kp-4'});
  });

  testWidgets('详情 sheet 里点标签 chip：关掉 sheet 并按该标签筛图', (tester) async {
    await pumpPage(tester, graph);

    final layout = layoutOf(tester);
    final point = layout.points.firstWhere((node) => node.id == 'kp-2');
    await tapScene(tester, point.center);

    final sheet = find.byKey(cognitiveGraphDetailSheetKey);
    final chip = find.descendant(
      of: sheet,
      matching: find.widgetWithText(ActionChip, '概率'),
    );
    expect(chip, findsOneWidget);
    await tester.tap(chip);
    await tester.pumpAndSettle();

    expect(find.byKey(cognitiveGraphDetailSheetKey), findsNothing);
    expect(painterPointIds(tester), <String>{'kp-2', 'kp-4'});
    expect(find.byKey(cognitiveGraphFilterClearKey), findsOneWidget);
    // 筛选 chip 上写着标签标题。
    expect(find.text('概率'), findsOneWidget);
  });

  testWidgets('标签筛选 chip 可清除，清除后恢复整张图', (tester) async {
    await pumpPage(tester, graph);

    final layout = layoutOf(tester);
    final point = layout.points.firstWhere((node) => node.id == 'kp-2');
    await tapScene(tester, point.center);
    final chip = find.descendant(
      of: find.byKey(cognitiveGraphDetailSheetKey),
      matching: find.widgetWithText(ActionChip, '概率'),
    );
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(painterPointIds(tester), <String>{'kp-2', 'kp-4'});

    await tester.tap(find.byKey(cognitiveGraphFilterClearKey));
    await tester.pumpAndSettle();

    expect(find.byKey(cognitiveGraphFilterClearKey), findsNothing);
    expect(find.text(zh.cognitiveGraphSummary(4, 2, 4)), findsOneWidget);
    expect(painterPointIds(tester), <String>{'kp-1', 'kp-2', 'kp-3', 'kp-4'});
  });

  testWidgets('列表视图：按主标签分组、未挂标签排最后，行上有区域名与卡数', (tester) async {
    await pumpPage(tester, graph);

    await tester.tap(find.byKey(cognitiveGraphViewToggleKey));
    await tester.pumpAndSettle();

    expect(find.byKey(cognitiveGraphCanvasKey), findsNothing);
    expect(find.byKey(cognitiveGraphResetViewKey), findsNothing);
    // 组标题：函数、概率、未挂标签（无标签组排最后）。
    expect(find.text('函数'), findsOneWidget);
    expect(find.text(zh.cognitiveGraphListUntagged), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('函数')).dy,
      lessThan(tester.getTopLeft(find.text('概率')).dy),
    );
    expect(
      tester.getTopLeft(find.text('概率')).dy,
      lessThan(tester.getTopLeft(find.text(zh.cognitiveGraphListUntagged)).dy),
    );
    for (final title in <String>['二次函数', '条件概率', '自由落体', '随机变量']) {
      expect(find.text(title), findsOneWidget);
    }
    // 区域名（副标题）与卡数（trailing 的数字）。
    expect(find.text(zh.cognitiveZoneProximal), findsWidgets);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('列表里点一行回图谱，并把该知识点居中选中', (tester) async {
    await pumpPage(tester, graph);

    await tester.tap(find.byKey(cognitiveGraphViewToggleKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('随机变量'));
    await tester.pumpAndSettle();

    expect(find.byKey(cognitiveGraphCanvasKey), findsOneWidget);
    expect(painterPointIds(tester), <String>{'kp-1', 'kp-2', 'kp-3', 'kp-4'});

    final layout = layoutOf(tester);
    final node = layout.points.firstWhere((node) => node.id == 'kp-4');
    final rect = tester.getRect(find.byKey(cognitiveGraphViewportKey));
    final screen = screenOf(tester, controllerOf(tester).value, node.center);
    expect((screen - rect.center).distance, lessThan(0.5));
    // 选中它之后底部有只读详情（区域 / 卡数 / 平均 R）。
    expect(
      find.text(
          zh.cognitiveGraphPointDetail(zh.cognitiveZoneOverload, 3, '0.45')),
      findsOneWidget,
    );
  });

  testWidgets('没有读数时给出空态，而不是画一张空白画布', (tester) async {
    await pumpPage(tester, CognitiveGraphData.empty);

    expect(find.text(zh.cognitiveGraphEmpty), findsOneWidget);
    expect(find.byKey(cognitiveGraphCanvasKey), findsNothing);
    expect(find.byKey(cognitiveGraphViewportKey), findsNothing);
    expect(find.byKey(cognitiveGraphResetViewKey), findsNothing);
    expect(find.byKey(cognitiveGraphSearchKey), findsNothing);
    expect(find.byKey(cognitiveGraphViewToggleKey), findsNothing);
  });
}

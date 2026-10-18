// 用户要求："认知模型我希望有一个只读的可视化界面"。
//
// 这一页是同一批读数（`cognitiveReadingsProvider`）的另一种画法：知识点 ↔ 标签网络。
// 测试钉三件事：数据怎么拼（纯函数）、页面画出来什么、点节点能不能看到只读详情。
// "只读"由结构保证（本页只 watch provider），页面测试用同一个 fixture 驱动，不碰数据库。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/anki/application/review_advisory.dart'
    show ReviewZone;
import 'package:furnace/features/cognitive/presentation/cognitive_graph_page.dart';
import 'package:furnace/features/cognitive/presentation/cognitive_graph_layout.dart';
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

  testWidgets('画出标题/说明/摘要/图例与画布；点圆点看到只读详情', (tester) async {
    await pumpPage(tester, graph);

    expect(find.text(zh.cognitiveGraphTitle), findsOneWidget);
    expect(find.text(zh.cognitiveGraphHint), findsOneWidget);
    // 2 个知识点 · 2 个标签 · 3 条连线（kp-1 一条 + kp-2 两条）。
    expect(find.text(zh.cognitiveGraphSummary(2, 2, 3)), findsOneWidget);
    expect(find.byKey(cognitiveGraphCanvasKey), findsOneWidget);

    // 图例里有区域词（与读数页共用 zoneLabel）。
    expect(find.text(zh.cognitiveZoneDanger), findsOneWidget);
    expect(find.text(zh.cognitiveZoneProximal), findsOneWidget);

    // 按画布的实际矩形重算布局，点第一个知识点的圆心。
    final rect = tester.getRect(find.byKey(cognitiveGraphCanvasKey));
    final layout = layoutCognitiveGraph(
      size: Size(rect.width, rect.height),
      points: graph.points,
      tags: graph.tags,
    );
    final target = layout.points.firstWhere((point) => point.id == 'kp-2');
    await tester.tapAt(rect.topLeft + target.center);
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

    // 点标签（方块）也能看挂载数。详情卡出现后画布高度会变，所以重新取矩形再算布局。
    final rect2 = tester.getRect(find.byKey(cognitiveGraphCanvasKey));
    final layout2 = layoutCognitiveGraph(
      size: Size(rect2.width, rect2.height),
      points: graph.points,
      tags: graph.tags,
    );
    final tag = layout2.tags.firstWhere((tag) => tag.id == 'tag-b');
    await tester.tapAt(rect2.topLeft + tag.center);
    await tester.pumpAndSettle();
    expect(
      find.text(zh.cognitiveGraphTagDetail(1)),
      findsOneWidget,
    );
  });

  testWidgets('没有读数时给出空态，而不是画一张空白画布', (tester) async {
    await pumpPage(tester, CognitiveGraphData.empty);

    expect(find.text(zh.cognitiveGraphEmpty), findsOneWidget);
    expect(find.byKey(cognitiveGraphCanvasKey), findsNothing);
  });
}

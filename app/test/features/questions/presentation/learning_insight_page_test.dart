/// 学习洞察页的界面契约：只消费 learningInsightDataProvider，不重算口径。
///
/// 三条纪律：
/// 1. 页面不重新聚合解题链、不重新生成建议，读数全部来自 provider；
/// 2. 词表外动作要显式提示，不静默吞掉；
/// 3. 加载失败显示原文并可重试，空库给引导，不留空白页。
library;

import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/reasoning/capability_action_overlay.dart';
import 'package:furnace/domain/services/reasoning/chain_insights.dart';
import 'package:furnace/domain/services/reasoning/learning_advice.dart';
import 'package:furnace/features/questions/application/learning_insight_provider.dart';
import 'package:furnace/features/questions/presentation/learning_insight_page.dart';
import 'package:furnace/features/settings/presentation/capability_vocabulary_page.dart';
import 'package:furnace/features/settings/presentation/settings_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// 一条用满内置/未知动作与一个知识点的解题链：够产出建议、卡点与交叉读数。
ChainInsights _insights() {
  final steps = <ChainInsightStep>[
    ChainInsightStep(
      actionType: 'first_principles',
      index: 0,
      stuckRisk: 0.9,
      occurredAt: DateTime(2026, 10, 18, 9, 1),
    ),
    ChainInsightStep(
      actionType: 'first_principles',
      index: 1,
      stuckRisk: 0.9,
      occurredAt: DateTime(2026, 10, 18, 9, 3),
    ),
    ChainInsightStep(
      actionType: 'first_principles',
      index: 2,
      stuckRisk: 0.9,
      occurredAt: DateTime(2026, 10, 18, 11, 7),
    ),
    ChainInsightStep(
      actionType: 'made_up_move',
      index: 3,
      stuckRisk: 0.8,
      knowledgeHints: <String>['kp-1'],
      occurredAt: DateTime(2026, 10, 18, 9, 5),
    ),
  ];
  return ChainInsights.aggregate(
    chains: <ChainInsightChain>[
      ChainInsightChain(
        chainId: 'c-1',
        questionId: 'q-1',
        steps: steps,
        occurredAt: DateTime(2026, 10, 18, 9, 5),
      ),
    ],
  );
}

/// 有读数的页面数据：建议、内置动作、未知动作、卡点、交叉都会出现。
LearningInsightData _data({bool vocabOverlayFallback = false}) {
  final insights = _insights();
  return LearningInsightData.build(
    insights: insights,
    advices: LearningAdvicePlan.build(insights: insights),
    overlay: CapabilityActionOverlay.empty,
    knowledgePointTitles: const <String, String>{'kp-1': '二次函数最值'},
    vocabOverlayFallback: vocabOverlayFallback,
  );
}

/// 空库数据：零链零步，建议只有 noData。
LearningInsightData _emptyData() {
  final insights = ChainInsights.aggregate(chains: <ChainInsightChain>[]);
  return LearningInsightData.build(
    insights: insights,
    advices: LearningAdvicePlan.build(insights: insights),
    overlay: CapabilityActionOverlay.empty,
    knowledgePointTitles: const <String, String>{},
  );
}

void main() {
  late AppDatabase db;
  late AppLocalizations zh;

  setUpAll(() async {
    zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpInsightPage(
    WidgetTester tester, {
    required Future<LearningInsightData> Function() load,
    Size viewSize = const Size(1200, 8000),
  }) async {
    tester.view.physicalSize = viewSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          learningInsightDataProvider.overrideWith((ref) => load()),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LearningInsightPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('纯函数', () {
    test('只有无活动且建议全为 noData 才算空态', () {
      expect(learningInsightShowsEmpty(_emptyData()), isTrue);
      expect(learningInsightShowsEmpty(_data()), isFalse);
    });

    test('风险文案：未读数与百分比', () {
      expect(learningInsightRiskText(zh, null), zh.learningInsightRiskUnread);
      expect(
        learningInsightRiskText(zh, 0.9),
        zh.learningInsightRiskAverage('90%'),
      );
      expect(
        learningInsightRiskText(zh, 0),
        zh.learningInsightRiskAverage('0%'),
      );
    });

    test('动作状态文案区分内置与未知', () {
      final data = _data();
      expect(
        learningInsightActionStateText(
          zh,
          data.actionRows.firstWhere(
            (row) => row.actionType == 'first_principles',
          ),
        ),
        zh.learningInsightActionBuiltIn,
      );
      expect(
        learningInsightActionStateText(
          zh,
          data.actionRows.firstWhere(
            (row) => row.actionType == 'made_up_move',
          ),
        ),
        zh.learningInsightActionUnknown,
      );
    });

    test('最近时间：空值不显示，本地时间按 yyyy-MM-dd HH:mm', () {
      expect(learningInsightLastSeenText(zh, null), isNull);
      expect(
        learningInsightLastSeenText(zh, DateTime(2026, 10, 18, 9, 5)),
        zh.learningInsightLastSeen('2026-10-18 09:05'),
      );
    });

    test('五种建议各有不同图标，便于肉眼区分', () {
      final icons =
          LearningAdviceKind.values.map(learningInsightAdviceIcon).toSet();
      expect(icons.length, LearningAdviceKind.values.length);
    });
  });

  group('页面', () {
    testWidgets('没有解题链时显示引导空态而不是空白页', (tester) async {
      await pumpInsightPage(tester, load: () async => _emptyData());

      expect(find.byKey(learningInsightEmptyKey), findsOneWidget);
      expect(find.text(zh.learningInsightEmptyTitle), findsOneWidget);
      expect(find.text(zh.learningInsightEmptyBody), findsOneWidget);
      expect(find.text(zh.learningInsightAdviceSection), findsNothing);
      expect(find.text(zh.learningInsightActionSection), findsNothing);
    });

    testWidgets('加载失败显示原文，点重试后恢复', (tester) async {
      var fail = true;
      final data = _data();
      await pumpInsightPage(
        tester,
        load: () async {
          if (fail) {
            throw StateError('boom');
          }
          return data;
        },
      );

      expect(find.byKey(learningInsightErrorKey), findsOneWidget);
      expect(find.textContaining('Bad state: boom'), findsOneWidget);
      expect(find.text(zh.learningInsightRetry), findsOneWidget);

      fail = false;
      await tester.tap(find.text(zh.learningInsightRetry));
      await tester.pumpAndSettle();

      expect(find.byKey(learningInsightErrorKey), findsNothing);
      expect(find.text(zh.learningInsightAdviceSection), findsOneWidget);
    });

    testWidgets('有读数时渲染汇总、建议与动作分布', (tester) async {
      final data = _data();
      final card = data.adviceCards.first;
      final known = data.actionRows.firstWhere(
        (row) => row.actionType == 'first_principles',
      );
      await pumpInsightPage(tester, load: () async => data);

      expect(
        find.text(
          zh.learningInsightSummary(
            data.insights.chainCount,
            data.insights.stepCount,
            data.insights.questionCount,
          ),
        ),
        findsOneWidget,
      );
      expect(find.text(zh.learningInsightAdviceSection), findsOneWidget);
      expect(find.byKey(learningInsightAdviceCardKey(card)), findsOneWidget);
      expect(find.text(card.titleZh), findsOneWidget);
      expect(find.text(card.detailZh), findsOneWidget);

      expect(find.text(zh.learningInsightActionSection), findsOneWidget);
      final rowFinder = find.byKey(
        learningInsightActionRowKey('first_principles'),
      );
      expect(rowFinder, findsOneWidget);
      expect(
        find.descendant(
          of: rowFinder,
          matching: find.text(zh.learningInsightActionBuiltIn),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: rowFinder,
          matching: find.text(
            zh.learningInsightActionCounts(
              known.stepCount,
              known.questionCount,
              known.highRiskStepCount,
            ),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: rowFinder,
          matching: find.textContaining(
            learningInsightRiskText(zh, known.averageStuckRisk),
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('词表外动作单独提示并可跳词表页', (tester) async {
      final data = _data();
      expect(
        data.unknownRows.map((row) => row.actionType),
        contains('made_up_move'),
      );
      await pumpInsightPage(tester, load: () async => data);

      expect(find.byKey(learningInsightUnknownSectionKey), findsOneWidget);
      expect(
        find.text(zh.learningInsightUnknownSection(data.unknownRows.length)),
        findsOneWidget,
      );
      expect(find.text(zh.learningInsightUnknownHint), findsOneWidget);
      expect(find.text('- made_up_move'), findsOneWidget);

      final openButton = find.text(zh.learningInsightOpenVocabulary);
      await tester.ensureVisible(openButton);
      await tester.tap(openButton);
      await tester.pumpAndSettle();
      expect(find.byType(CapabilityVocabularyPage), findsOneWidget);
    });

    testWidgets('卡点热区显示知识点中文名与计数', (tester) async {
      final data = _data();
      final stuck = data.stuckRows.first;
      await pumpInsightPage(tester, load: () async => data);

      expect(find.text(zh.learningInsightStuckSection), findsOneWidget);
      final rowFinder = find.byKey(
        learningInsightStuckRowKey(stuck.knowledgePointId),
      );
      expect(rowFinder, findsOneWidget);
      expect(
        find.descendant(of: rowFinder, matching: find.text(stuck.titleZh)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: rowFinder,
          matching: find.text(
            zh.learningInsightStuckCounts(
              stuck.highRiskStepCount,
              stuck.questionCount,
              stuck.chainCount,
            ),
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('动作 × 知识点交叉行可读', (tester) async {
      final data = _data();
      final cross = data.actionKnowledgeRows.first;
      await pumpInsightPage(tester, load: () async => data);

      expect(find.text(zh.learningInsightCrossSection), findsOneWidget);
      final rowFinder = find.byKey(
        learningInsightCrossRowKey(
          cross.actionType,
          cross.knowledgePointId,
        ),
      );
      expect(rowFinder, findsOneWidget);
      expect(
        find.descendant(
          of: rowFinder,
          matching: find.text(
            '${cross.actionLabelZh} → ${cross.knowledgePointTitleZh}',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('自定义词表读不到时页顶显示退回提示条', (tester) async {
      final data = _data(vocabOverlayFallback: true);
      expect(learningInsightShowsFallback(data), isTrue);
      await pumpInsightPage(tester, load: () async => data);

      expect(find.byKey(learningInsightFallbackBannerKey), findsOneWidget);
      expect(find.text(zh.learningInsightOverlayFallback), findsOneWidget);
    });

    testWidgets('从没用过的动作单独列一块，不做有罪推定', (tester) async {
      final data = _data();
      expect(data.neverUsedActions, isNotEmpty);
      final unused = data.neverUsedActions.first;
      await pumpInsightPage(tester, load: () async => data);

      expect(find.text(zh.learningInsightNeverUsedSection), findsOneWidget);
      expect(find.text(zh.learningInsightNeverUsedHint), findsOneWidget);
      expect(find.text(unused.labelZh), findsOneWidget);
    });

    testWidgets('下拉刷新会重新读取数据', (tester) async {
      var builds = 0;
      await pumpInsightPage(
        tester,
        viewSize: const Size(1200, 1000),
        load: () async {
          builds += 1;
          return _data();
        },
      );
      expect(builds, 1);
      expect(find.byType(RefreshIndicator), findsOneWidget);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ListView).first),
      );
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(0, 120));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(builds, greaterThan(1));
    });

    testWidgets('设置页有学习洞察入口并能打开页面', (tester) async {
      tester.view.physicalSize = const Size(1200, 8000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            learningInsightDataProvider.overrideWith((ref) async => _data()),
          ],
          child: const MaterialApp(
            locale: Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: SettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final entry = find.text(zh.learningInsightSettingsTitle);
      expect(entry, findsOneWidget);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byKey(learningInsightPageKey), findsOneWidget);
    });
  });
}

// 用户层「学习状态」验收测试（task-103：MindNet/认知模型删繁就简）。
//
// 守五件事：
//   1. MindNet 首页只有四块用户内容：档位 / 强项弱项 / 今日 / 趋势；
//   2. 开发者字段（R0/Gain/Σ/band/zone/每卡 due/interval/calibration/fast layer/
//      prior count/机制参数/评测中心）默认**不可见**；
//   3. 入口只留「开始复习」「今日清单」「知识网络」；
//   4. 空态：证据不足显示 `?` /「证据不足」，不显示 0 或假精确；
//   5. 页面只读：读一遍数据库，前后整库快照一致。

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/cognitive/cognitive_model.dart';
import 'package:furnace/domain/services/cognitive/library_diagnosis.dart';
import 'package:furnace/features/cognitive/presentation/cognitive_developer_page.dart';
import 'package:furnace/features/cognitive/presentation/cognitive_graph_page.dart';
import 'package:furnace/features/cognitive/presentation/cognitive_model_page.dart';
import 'package:furnace/features/cognitive/presentation/learning_status_view.dart';
import 'package:furnace/features/cognitive/presentation/mindnet_page.dart';
import 'package:furnace/features/settings/presentation/settings_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// 固定读数的模型：每张卡的 R 都是 0.42（4 张有观测的卡 → 档位 C）。
class _FakeModel implements CognitiveModel {
  const _FakeModel();

  @override
  String get id => 'test-fake';

  @override
  double retrievabilityOf(CardState row, {required double nowHours}) => 0.42;

  @override
  double expectedGain(
    CardState row, {
    required double nowHours,
    double closeness = 0.5,
  }) =>
      2.0;

  @override
  List<AdvisorCandidate> orderAdvisory(
    List<AdvisorCandidate> candidates, {
    required double nowHours,
    Set<String> targetKpIds = const {},
  }) =>
      [...candidates]..sort((a, b) => a.row.id.compareTo(b.row.id));

  @override
  ({double r0, double sigma, double r}) modelReadingOf(
    CardState row, {
    required double nowHours,
  }) =>
      (r0: 0.7, sigma: 0.9, r: 0.42);

  @override
  ({double r0, double sigma}) modelStateAfterReview(
    CardState row, {
    required int rating,
    required double nowHours,
    bool reread = false,
    bool reviewedSolution = false,
    double closeness = 0.5,
  }) =>
      (r0: 0.7, sigma: 0.9);
}

CardState _row(String id, String kp) => CardState(
      id: id,
      dueAt: 1700000000000,
      intervalDays: 2,
      ease: 2.5,
      repetitions: 3,
      lapses: 0,
      state: 'review',
      lastReviewedAt: 1699500000000,
      createdAt: 1,
      updatedAt: 2,
      knowledgePointId: kp,
      unitKey: 'cloze:$id',
      stability: 5,
      difficulty: 5,
      encodingStrength: 0.8,
      savings: 0.8,
      forced: 0,
      forcedStreak: 0,
    );

/// 4 张有复习记录的卡（3 个知识点）+ 1 张新卡（不算证据）。
CognitiveObservationInputs _fixtureInputs() => CognitiveObservationInputs(
      units: [
        CognitiveObservedUnit(
          row: _row('cs-1', 'kp-1'),
          knowledgePointTitle: '光合作用',
          tagCount: 2,
          isNew: false,
        ),
        CognitiveObservedUnit(
          row: _row('cs-2', 'kp-1'),
          knowledgePointTitle: '光合作用',
          tagCount: 1,
          isNew: false,
        ),
        CognitiveObservedUnit(
          row: _row('cs-3', 'kp-2'),
          knowledgePointTitle: '呼吸作用',
          tagCount: 0,
          isNew: false,
        ),
        CognitiveObservedUnit(
          row: _row('cs-4', 'kp-3'),
          knowledgePointTitle: '运输作用',
          tagCount: 0,
          isNew: false,
        ),
        CognitiveObservedUnit(
          row: _row('cs-new', 'kp-4').copyWith(
            repetitions: 0,
            lastReviewedAt: const Value(null),
          ),
          knowledgePointTitle: '新知识点',
          tagCount: 0,
          isNew: true,
        ),
      ],
    );

List<Override> _overrides({
  AppDatabase? db,
  CognitiveObservationInputs? inputs,
}) =>
    <Override>[
      if (db != null) appDatabaseProvider.overrideWithValue(db),
      cognitiveObservationInputsProvider
          .overrideWith((ref) => inputs ?? _fixtureInputs()),
      cognitiveModelProvider.overrideWithValue(const _FakeModel()),
      cognitiveLibraryDiagnosisProvider
          .overrideWith((ref) async => LibraryDiagnosis.notRun),
      cognitivePriorsProvider.overrideWith((ref) async => const {}),
    ];

Future<void> _pump(
  WidgetTester tester,
  Widget page, {
  required List<Override> overrides,
}) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: page,
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      return;
    }
  }
}

/// 整库快照（只读校验用）。
Future<Map<String, Object?>> _dumpAll(AppDatabase db) async {
  final dump = <String, Object?>{};
  for (final table in await db.userTables()) {
    dump[table] = await db.dumpTable(table);
  }
  return dump;
}

void main() {
  late AppLocalizations zh;
  var db = AppDatabase.forTesting(NativeDatabase.memory());
  setUpAll(() {
    zh = lookupAppLocalizations(const Locale('zh'));
  });
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() async {
    await db.close();
  });

  testWidgets('MindNet 首页 = 四块用户内容 + 两个入口，没有开发者字段', (tester) async {
    await _pump(tester, const MindNetPage(), overrides: _overrides(db: db));

    // 1) 档位：3 个有复习记录的知识点、平均 R=0.42 → C 档；依据是「几个知识点
    //    有复习记录」，不是「几张卡」（task-113：认知模型不再以闪存卡为主）。
    expect(find.byKey(learningStatusBandKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(learningStatusBandKey),
        matching: find.text('C'),
      ),
      findsOneWidget,
    );
    expect(find.text(zh.mindnetBandEvidence(3)), findsOneWidget);
    expect(find.text(zh.mindnetBandHint), findsOneWidget);
    // 依据行不再出现"张卡"口径（4 张卡只算 3 个知识点）。
    expect(find.textContaining('张复习过的卡片'), findsNothing);

    // 2) 强项/弱项：按保持度排名，每条只带证据状态（「实测」，不再带张卡数）。
    expect(find.byKey(learningStatusStrengthsKey), findsOneWidget);
    expect(find.byKey(learningStatusWeaknessesKey), findsOneWidget);
    expect(find.text('光合作用').evaluate().length, greaterThanOrEqualTo(1));
    // 3 个有观测的知识点 → 强项 2 + 弱项 1，不重叠；
    // 4 张有观测的卡不再进用户层文案。
    expect(find.text(zh.mindnetEvidenceMeasured), findsNWidgets(3));
    expect(find.textContaining('张卡'), findsNothing);

    // 3) 今日：待复习/任务 + 主按钮。
    expect(find.byKey(learningStatusTodayKey), findsOneWidget);
    expect(find.text(zh.mindnetStartReview), findsOneWidget);
    expect(find.byKey(mindnetStartReviewKey), findsOneWidget);

    // 4) 趋势：复习日志说了算；空库 → 证据不足。
    expect(find.byKey(learningStatusTrendKey), findsOneWidget);
    expect(find.text(zh.mindnetTrendEmpty), findsOneWidget);

    // 入口只有今日清单 + 知识网络。
    expect(find.byKey(mindnetTodayPlanEntryKey), findsOneWidget);
    expect(find.byKey(mindnetGraphEntryKey), findsOneWidget);

    // 开发者字段默认不可见。
    for (final hidden in <String>[
      'R0',
      '增益',
      'Σ',
      '分组',
      '发展区',
      'Brier',
      '模型 test-fake',
      '测评先验',
      '清掉这',
    ]) {
      expect(
        find.textContaining(hidden),
        findsNothing,
        reason: '开发者字段 "$hidden" 不应出现在用户首页',
      );
    }
    // 机制参数 / 评测中心不再是 MindNet 主入口。
    expect(find.text(zh.mechanismPanelTitle), findsNothing);
    expect(find.text(zh.assessmentCenterTitle), findsNothing);
    expect(find.byType(CognitiveDeveloperPage), findsNothing);
  });

  testWidgets('空库 / 证据不足：档位是 ?，四块都说「证据不足」，不显示 0 分', (tester) async {
    await _pump(
      tester,
      const MindNetPage(),
      overrides: _overrides(
        db: db,
        inputs: const CognitiveObservationInputs(units: []),
      ),
    );

    expect(
      find.descendant(
        of: find.byKey(learningStatusBandKey),
        matching: find.text('?'),
      ),
      findsOneWidget,
    );
    expect(find.text(zh.mindnetBandInsufficient(3)), findsOneWidget);
    expect(find.text(zh.mindnetStrengthsEmpty), findsOneWidget);
    expect(find.text(zh.mindnetWeaknessesEmpty), findsOneWidget);
    expect(find.text(zh.mindnetTrendEmpty), findsOneWidget);
    // 没有证据时也不显示"0 分/0%".
    expect(find.textContaining('0%'), findsNothing);
  });

  testWidgets('设置页不再放「认知模型」原页（用户入口只到学习状态模块）', (tester) async {
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsPage(),
        ),
      ),
    );
    await _settle(tester);

    // 普通设置视图里既没有「认知模型」这一行，也没有旧的入口 key。
    expect(find.text('认知模型'), findsNothing);
    expect(find.byKey(const Key('settings-cognitive-model-tile')), findsNothing);
    // 开发者分区里仍有原始读数入口（展开后才构建）。
    expect(find.byKey(settingsCognitiveDeveloperTileKey), findsNothing);
    await tester.tap(find.byKey(settingsDeveloperToggleKey));
    await tester.pumpAndSettle();
    expect(find.byKey(settingsCognitiveDeveloperTileKey), findsOneWidget);
  });

  testWidgets('点「知识网络」入口打开图页（只读）', (tester) async {
    await _pump(
      tester,
      const MindNetPage(),
      overrides: [
        ..._overrides(db: db),
        // 图的数据只验入口与空态：给空图，不在这里等真实读表。
        cognitiveGraphProvider
            .overrideWith((ref) async => CognitiveGraphData.empty),
      ],
    );

    await tester.ensureVisible(find.byKey(mindnetGraphEntryKey));
    await tester.pump();
    await tester.tap(find.byKey(mindnetGraphEntryKey));
    await tester.pumpAndSettle();

    expect(find.byType(CognitiveGraphPage), findsOneWidget);
    // 空库 → 图页如实给空态（不是一张空白画布）。
    expect(find.text(zh.cognitiveGraphEmpty), findsOneWidget);
  });

  testWidgets('用户层页面只读：读一遍前后整库快照一致', (tester) async {
    await db.into(db.knowledgePoints).insert(
          KnowledgePointsCompanion.insert(
            id: 'kp-1',
            title: '光合作用',
            content: '把光能变成化学能',
            createdAt: 1,
            updatedAt: 1,
          ),
        );
    await db.into(db.cardStates).insert(
          CardStatesCompanion.insert(
            id: 'cs-1',
            createdAt: 1,
            updatedAt: 2,
            dueAt: const Value(1700000000000),
            repetitions: const Value(4),
            knowledgePointId: const Value('kp-1'),
            unitKey: const Value('cloze:0'),
            stability: const Value(12.5),
            difficulty: const Value(6.0),
            encodingStrength: const Value(0.9),
            savings: const Value(0.85),
          ),
        );
    final before = await _dumpAll(db);

    await _pump(tester, const MindNetPage(), overrides: _overrides(db: db));

    final after = await _dumpAll(db);
    expect(after, before, reason: '用户层页面必须只 SELECT');
  });
}

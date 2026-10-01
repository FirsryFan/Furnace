// Widget tests for the read-only "认知模型" page (t19).
//
// Three things are pinned here:
//
// 1. **the disclaimers are on the page** - advisor mode and the uncalibrated
//    weights are the deliverable, not decoration;
// 2. **the readings come from the injected `CognitiveModel`** - a fake with
//    fixed numbers, so the assertions are exact rather than "something showed";
// 3. **the page writes nothing** - it is pumped against a real in-memory
//    database and every user table is dumped before and after.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/cognitive/cognitive_model.dart';
import 'package:furnace/features/anki/application/review_advisory.dart';
import 'package:furnace/features/cognitive/presentation/cognitive_model_page.dart';
import 'package:furnace/features/settings/presentation/settings_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// A model with fixed, assertable answers. Everything the page shows about a
/// card's model side must come from here.
class _FakeModel implements CognitiveModel {
  const _FakeModel();

  @override
  String get id => 'test-fake';

  @override
  double retrievabilityOf(CardState row, {required double nowHours}) => 0.5;

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
    double closeness = 0.5,
  }) =>
      (r0: 0.7, sigma: 0.9);
}

CardState _row(String id, String knowledgePointId) => CardState(
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
      knowledgePointId: knowledgePointId,
      unitKey: 'cloze:$id',
      stability: 5,
      difficulty: 5,
      encodingStrength: 0.8,
      savings: 0.8,
      forced: 0,
      forcedStreak: 0,
    );

CognitiveObservationInputs _fixtureInputs() => CognitiveObservationInputs(
      units: [
        CognitiveObservedUnit(
          row: _row('cs-boost', 'kp-1'),
          knowledgePointTitle: '光合作用',
          tagCount: 2,
          isNew: false,
        ),
        CognitiveObservedUnit(
          row: _row('cs-model', 'kp-2'),
          knowledgePointTitle: '呼吸作用',
          tagCount: 0,
          isNew: false,
        ),
        CognitiveObservedUnit(
          row: _row('cs-new', 'kp-2'),
          knowledgePointTitle: '呼吸作用',
          tagCount: 0,
          isNew: true,
        ),
      ],
      boostFactorByKnowledgePoint: const {'kp-1': 1.8},
    );

Future<void> _pumpPage(
  WidgetTester tester, {
  required List<Override> overrides,
  Locale locale = const Locale('zh'),
}) async {
  // A tall surface so every card in the fixture is actually built: the page is
  // a ListView, and an off-screen card is not in the widget tree to be found.
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const CognitiveModelPage(),
      ),
    ),
  );
  await _settleProviders(tester);
}

/// Yields to the event loop until the loading spinner is gone. `pumpAndSettle`
/// cannot be used while a `CircularProgressIndicator` is on screen: it animates
/// forever and would time out.
Future<void> _settleProviders(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      return;
    }
  }
}

/// Every user table, as JSON-safe maps (drift's own `.tfpkg` dump helpers).
Future<Map<String, Object?>> _dumpAll(AppDatabase db) async {
  final dump = <String, Object?>{};
  for (final table in await db.userTables()) {
    dump[table] = await db.dumpTable(table);
  }
  return dump;
}

Future<void> _seed(AppDatabase db) async {
  await db.into(db.knowledgePoints).insert(KnowledgePointsCompanion.insert(
        id: 'kp-1',
        title: '光合作用',
        content: '把光能变成化学能',
        createdAt: 1,
        updatedAt: 1,
      ));
  await db.into(db.cardStates).insert(CardStatesCompanion.insert(
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
      ));
  await db.into(db.tags).insert(TagsCompanion.insert(
        id: 't-1',
        name: '生物',
        createdAt: 1,
        updatedAt: 1,
      ));
  await db.into(db.objectTags).insert(ObjectTagsCompanion.insert(
        id: 'ot-1',
        tagId: 't-1',
        objectType: 'knowledge_point',
        objectId: 'kp-1',
        createdAt: 1,
      ));
  await db.into(db.boostEntries).insert(BoostEntriesCompanion.insert(
        id: 'b-1',
        knowledgePointId: 'kp-1',
        factor: 1.8,
        createdAt: 1,
      ));
}

void main() {
  testWidgets('shows both disclaimers and the read-only note', (tester) async {
    await _pumpPage(
      tester,
      overrides: [
        cognitiveObservationInputsProvider.overrideWith((ref) => _fixtureInputs()),
        cognitiveModelProvider.overrideWithValue(const _FakeModel()),
      ],
    );

    expect(find.text('顾问模式：不改到期时间'), findsOneWidget);
    expect(find.text('ls 等边权未标定'), findsOneWidget);
    expect(find.text('只读页面：不会写入数据库'), findsOneWidget);
    expect(find.text('认知模型'), findsOneWidget);
  });

  testWidgets('renders the injected model\'s numbers, bands and zones',
      (tester) async {
    await _pumpPage(
      tester,
      overrides: [
        cognitiveObservationInputsProvider.overrideWith((ref) => _fixtureInputs()),
        cognitiveModelProvider.overrideWithValue(const _FakeModel()),
      ],
    );

    // R and gain are the fake's, exactly.
    expect(find.text('R 0.420'), findsNWidgets(3));
    expect(find.text('增益 2.000'), findsNWidgets(3));
    expect(find.text('R0 0.70'), findsNWidgets(3));
    expect(find.text('Σ 0.90'), findsNWidgets(3));

    // Bands come from ReviewAdvisory, not from the page.
    expect(find.textContaining('分组: 标签扩散提升（启发式） ×1.8'), findsOneWidget);
    expect(find.textContaining('分组: 模型排序'), findsOneWidget);
    expect(find.textContaining('分组: 新卡'), findsOneWidget);
    // No diagnosis map is passed, so §9.5's rule gives `unavailable` - and the
    // page says so in the zone vocabulary rather than inventing "healthy".
    expect(find.textContaining('发展区/死角: 不可用（未做诊断）'), findsNWidgets(3));
    expect(find.textContaining('新卡不交由模型评分与排序（D4）'), findsOneWidget);

    // Titles and ids prove the rows themselves are shown.
    expect(find.text('光合作用'), findsOneWidget);
    expect(find.text('呼吸作用'), findsNWidgets(2));
    expect(find.text('卡 cs-model'), findsOneWidget);
  });

  testWidgets('all nine zone labels and four band labels are wired',
      (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(ReviewZone.values, hasLength(9));
    expect(ReviewBand.values, hasLength(4));
    for (final zone in ReviewZone.values) {
      expect(zoneLabel(l10n, zone), isNotEmpty);
    }
    // The two values that must never be conflated carry distinct words.
    expect(
      zoneLabel(l10n, ReviewZone.unavailable),
      isNot(zoneLabel(l10n, ReviewZone.healthy)),
    );
  });

  testWidgets('writes nothing to the database it reads', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seed(db);
    final before = await _dumpAll(db);

    await _pumpPage(
      tester,
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        cognitiveModelProvider.overrideWithValue(const _FakeModel()),
      ],
    );

    // The reading really came from the seeded row.
    expect(find.text('光合作用'), findsOneWidget);
    expect(find.text('R 0.420'), findsOneWidget);

    final after = await _dumpAll(db);
    expect(after, before, reason: 'the page must only SELECT');
  });

  testWidgets('the settings entry opens the page', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seed(db);
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          cognitiveModelProvider.overrideWithValue(const _FakeModel()),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsPage(),
        ),
      ),
    );
    await _settleProviders(tester);

    final entry = find.widgetWithText(ListTile, '认知模型');
    expect(entry, findsOneWidget);
    await tester.ensureVisible(entry);
    await tester.pump();
    await tester.tap(entry);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _settleProviders(tester);

    expect(find.byType(CognitiveModelPage), findsOneWidget);
    expect(find.text('顾问模式：不改到期时间'), findsOneWidget);
  });
}

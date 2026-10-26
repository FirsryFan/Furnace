// 能力画像页测试：只读页面，直接往内存库的 ability_scores 落记录再断言。
//
// 钉六件事：四项全无记录时是空态（不是四张 0 分卡）、只测一项时其它三项显示没测过、
// 同一项多条记录取最新且次数是总条数、分数四舍五入、读库失败有错误文案（不装空态）、
// 以及写完一条新分数后页面自动刷新（watchDatabaseRevision + instrumentWrites）。
// 趋势小图另钉：只测一次给「至少测两次」提示、够两次画折线并给方向词
// （升/降/差 1 分持平）、窄窗口 400x900 不溢出、趋势读失败只坏那张卡。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ability_score_repository.dart';
import 'package:furnace/data/repositories/repository_providers.dart';
import 'package:furnace/domain/services/cognitive/ability_assessment.dart';
import 'package:furnace/features/cognitive/presentation/ability_profile_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// 读库失败的替身：只把「最近一次」这条查询打断，其余接口照常走真库。
class _FailingAbilityScoreRepository extends AbilityScoreRepository {
  _FailingAbilityScoreRepository(super.db);

  @override
  Future<Map<AbilityKey, AbilityScoreEntry>> latestByAbility() async {
    throw StateError('读库失败');
  }
}

/// 只有趋势读数失败的替身：最近一次/次数照常，「历史」这条查询打断。
/// 用来钉「趋势坏了只坏那张卡，整页不打成错误态」。
class _FailingTrendRepository extends AbilityScoreRepository {
  _FailingTrendRepository(super.db);

  @override
  Future<List<AbilityScoreEntry>> historyFor(
    AbilityKey key, {
    int limit = 50,
  }) async {
    throw StateError('趋势读库失败');
  }
}

void main() {
  late AppLocalizations zh;

  setUpAll(() async {
    zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// [liveWrites] 为真时装上 `instrumentWrites`：写库会进 `DataChangeBus`，
  /// 自动刷新那条用例靠它；其余用例不装（断言的是读出来的值）。
  Future<AppDatabase> openDatabase({bool liveWrites = false}) async {
    final executor = liveWrites
        ? instrumentWrites(NativeDatabase.memory())
        : NativeDatabase.memory();
    final db = AppDatabase.forTesting(executor);
    addTearDown(db.close);
    return db;
  }

  Future<void> pumpPage(
    WidgetTester tester,
    AppDatabase db, {
    List<Override> overrides = const <Override>[],
    Size size = const Size(1000, 1600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          ...overrides,
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AbilityProfilePage(),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> seed(
    AppDatabase db,
    AbilityKey key,
    double score,
    DateTime capturedAt,
  ) {
    return AbilityScoreRepository(db).record(
      key: key,
      score: score,
      now: capturedAt,
    );
  }

  Finder cardOf(AbilityKey key) =>
      find.byKey(Key('ability-profile-card-${key.code}'));
  Finder scoreOf(AbilityKey key) =>
      find.byKey(Key('ability-profile-score-${key.code}'));
  Finder neverOf(AbilityKey key) =>
      find.byKey(Key('ability-profile-never-${key.code}'));
  Finder timeOf(AbilityKey key) =>
      find.byKey(Key('ability-profile-time-${key.code}'));

  testWidgets('四项都没测过时给出空态，而不是四张 0 分卡', (tester) async {
    final db = await openDatabase();
    await pumpPage(tester, db);

    expect(find.text(zh.abilityProfileTitle), findsOneWidget);
    expect(find.text(zh.abilityProfileEmpty), findsOneWidget);
    for (final ability in AbilityKey.values) {
      expect(cardOf(ability), findsNothing);
      expect(neverOf(ability), findsNothing);
    }
  });

  testWidgets('只有反应速度测过一次：分数/次数/时间都在，其它三项显示没测过', (tester) async {
    final db = await openDatabase();
    await seed(
        db, AbilityKey.reactionSpeed, 87.4, DateTime(2026, 10, 24, 9, 5));
    await pumpPage(tester, db);

    expect(find.text(zh.abilityProfileEmpty), findsNothing);
    expect(find.text(zh.abilityProfileLatest), findsOneWidget);
    for (final ability in AbilityKey.values) {
      expect(cardOf(ability), findsOneWidget);
    }
    expect(
      tester.widget<Text>(scoreOf(AbilityKey.reactionSpeed)).data,
      zh.abilityScoreLabel(87),
    );
    expect(find.text(zh.abilityProfileCount(1)), findsOneWidget);
    expect(
      tester.widget<Text>(timeOf(AbilityKey.reactionSpeed)).data,
      '2026-10-24 09:05',
    );

    for (final ability in const [
      AbilityKey.workingMemory,
      AbilityKey.patternRecognition,
      AbilityKey.attentionStability,
    ]) {
      expect(neverOf(ability), findsOneWidget);
      expect(scoreOf(ability), findsNothing);
      expect(timeOf(ability), findsNothing);
    }
  });

  testWidgets('同一项测过多次：显示最新分数与总次数', (tester) async {
    final db = await openDatabase();
    await seed(db, AbilityKey.workingMemory, 40, DateTime(2026, 10, 20, 8));
    await seed(db, AbilityKey.workingMemory, 55, DateTime(2026, 10, 21, 8));
    await seed(db, AbilityKey.workingMemory, 91.6, DateTime(2026, 10, 22, 8));
    await pumpPage(tester, db);

    expect(
      tester.widget<Text>(scoreOf(AbilityKey.workingMemory)).data,
      zh.abilityScoreLabel(92),
    );
    expect(
      tester.widget<Text>(timeOf(AbilityKey.workingMemory)).data,
      '2026-10-22 08:00',
    );
    expect(find.text(zh.abilityProfileCount(3)), findsOneWidget);
  });

  testWidgets('分数按四舍五入显示：66.5→67、66.4→66、99.6→100、0→0', (tester) async {
    final db = await openDatabase();
    final capturedAt = DateTime(2026, 10, 23, 10);
    await seed(db, AbilityKey.reactionSpeed, 66.5, capturedAt);
    await seed(db, AbilityKey.workingMemory, 66.4, capturedAt);
    await seed(db, AbilityKey.patternRecognition, 99.6, capturedAt);
    await seed(db, AbilityKey.attentionStability, 0, capturedAt);
    await pumpPage(tester, db);

    expect(
      tester.widget<Text>(scoreOf(AbilityKey.reactionSpeed)).data,
      zh.abilityScoreLabel(67),
    );
    expect(
      tester.widget<Text>(scoreOf(AbilityKey.workingMemory)).data,
      zh.abilityScoreLabel(66),
    );
    expect(
      tester.widget<Text>(scoreOf(AbilityKey.patternRecognition)).data,
      zh.abilityScoreLabel(100),
    );
    expect(
      tester.widget<Text>(scoreOf(AbilityKey.attentionStability)).data,
      zh.abilityScoreLabel(0),
    );
  });

  testWidgets('读库失败时显示错误文案，而不是空态', (tester) async {
    final db = await openDatabase();
    await pumpPage(
      tester,
      db,
      overrides: [
        abilityScoreRepositoryProvider.overrideWithValue(
          _FailingAbilityScoreRepository(db),
        ),
      ],
    );

    expect(find.textContaining('读取能力分数失败'), findsOneWidget);
    expect(find.textContaining('读库失败'), findsOneWidget);
    expect(find.text(zh.abilityProfileEmpty), findsNothing);
  });

  testWidgets('写进一条新分数后画像自动刷新（不用重进页面）', (tester) async {
    final db = await openDatabase(liveWrites: true);
    await pumpPage(tester, db);
    expect(find.text(zh.abilityProfileEmpty), findsOneWidget);

    await seed(
      db,
      AbilityKey.attentionStability,
      72.2,
      DateTime(2026, 10, 25, 21, 30),
    );
    await settle(tester);

    expect(find.text(zh.abilityProfileEmpty), findsNothing);
    expect(
      tester.widget<Text>(scoreOf(AbilityKey.attentionStability)).data,
      zh.abilityScoreLabel(72),
    );
    expect(find.text(zh.abilityProfileCount(1)), findsOneWidget);
  });

  // ---- 趋势小图（task-204） ----
  Finder trendChartOf(AbilityKey key) =>
      find.byKey(Key('ability-trend-chart-${key.code}'));
  Finder trendHintOf(AbilityKey key) =>
      find.byKey(Key('ability-trend-hint-${key.code}'));
  Finder trendDirectionOf(AbilityKey key) =>
      find.byKey(Key('ability-trend-direction-${key.code}'));

  testWidgets('只测过一次：给「至少测两次」提示，不画折线', (tester) async {
    final db = await openDatabase();
    await seed(
      db,
      AbilityKey.reactionSpeed,
      87.4,
      DateTime(2026, 10, 24, 9, 5),
    );
    await pumpPage(tester, db);

    expect(trendHintOf(AbilityKey.reactionSpeed), findsOneWidget);
    expect(
      tester.widget<Text>(trendHintOf(AbilityKey.reactionSpeed)).data,
      zh.abilityTrendHint,
    );
    expect(trendChartOf(AbilityKey.reactionSpeed), findsNothing);
    // 没测过的卡不显示趋势提示（只显示还没测过）。
    expect(trendHintOf(AbilityKey.workingMemory), findsNothing);
    expect(find.text(zh.abilityTrendHint), findsOneWidget);
  });

  testWidgets('测过三次且分数走高：画折线、显示最近 3 次与方向「变好」', (tester) async {
    final db = await openDatabase();
    await seed(db, AbilityKey.reactionSpeed, 40, DateTime(2026, 10, 20, 8));
    await seed(db, AbilityKey.reactionSpeed, 55, DateTime(2026, 10, 21, 8));
    await seed(db, AbilityKey.reactionSpeed, 90, DateTime(2026, 10, 22, 8));
    await pumpPage(tester, db);

    expect(trendChartOf(AbilityKey.reactionSpeed), findsOneWidget);
    expect(trendHintOf(AbilityKey.reactionSpeed), findsNothing);
    expect(
      find.text(zh.abilityTrendRecent(3)),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(trendDirectionOf(AbilityKey.reactionSpeed)).data,
      zh.abilityTrendImproving,
    );
    // 方向词用 primary 色（变好）。
    final chart = trendChartOf(AbilityKey.reactionSpeed);
    final primary = Theme.of(tester.element(chart)).colorScheme.primary;
    expect(
      tester
          .widget<Text>(trendDirectionOf(AbilityKey.reactionSpeed))
          .style
          ?.color,
      primary,
    );
  });

  testWidgets('分数走低：方向「变差」，颜色用 error', (tester) async {
    final db = await openDatabase();
    await seed(db, AbilityKey.workingMemory, 90, DateTime(2026, 10, 20, 8));
    await seed(db, AbilityKey.workingMemory, 60, DateTime(2026, 10, 21, 8));
    await seed(db, AbilityKey.workingMemory, 41, DateTime(2026, 10, 22, 8));
    await pumpPage(tester, db);

    expect(trendChartOf(AbilityKey.workingMemory), findsOneWidget);
    expect(
      tester.widget<Text>(trendDirectionOf(AbilityKey.workingMemory)).data,
      zh.abilityTrendDeclining,
    );
    final error = Theme.of(
      tester.element(trendChartOf(AbilityKey.workingMemory)),
    ).colorScheme.error;
    expect(
      tester
          .widget<Text>(trendDirectionOf(AbilityKey.workingMemory))
          .style
          ?.color,
      error,
    );
  });

  testWidgets('首尾只差 1 分：方向「持平」', (tester) async {
    final db = await openDatabase();
    await seed(
        db, AbilityKey.patternRecognition, 50, DateTime(2026, 10, 20, 8));
    await seed(
        db, AbilityKey.patternRecognition, 60, DateTime(2026, 10, 21, 8));
    await seed(
        db, AbilityKey.patternRecognition, 51, DateTime(2026, 10, 22, 8));
    await pumpPage(tester, db);

    expect(trendChartOf(AbilityKey.patternRecognition), findsOneWidget);
    expect(
      tester.widget<Text>(trendDirectionOf(AbilityKey.patternRecognition)).data,
      zh.abilityTrendFlat,
    );
    expect(
      find.text(zh.abilityTrendRecent(3)),
      findsOneWidget,
    );
  });

  testWidgets('窄窗口 400x900 不溢出，折线撑满卡片内容宽', (tester) async {
    final db = await openDatabase();
    await seed(db, AbilityKey.reactionSpeed, 40, DateTime(2026, 10, 20, 8));
    await seed(db, AbilityKey.reactionSpeed, 50, DateTime(2026, 10, 21, 8));
    await seed(db, AbilityKey.reactionSpeed, 60, DateTime(2026, 10, 22, 8));
    await pumpPage(tester, db, size: const Size(400, 900));

    expect(tester.takeException(), isNull);
    final card = cardOf(AbilityKey.reactionSpeed);
    final chart = trendChartOf(AbilityKey.reactionSpeed);
    expect(chart, findsOneWidget);
    // 卡片 padding 16 左右各一：折线宽度 = 卡片宽 - 32。
    expect(
      tester.getSize(chart).width,
      closeTo(tester.getSize(card).width - 32, 0.5),
    );
    // 迷你折线高度在 32–40 之间。
    expect(tester.getSize(chart).height, inInclusiveRange(32, 40));
  });

  testWidgets('趋势读失败：只有那张卡给短错误，整页不变成错误态', (tester) async {
    final db = await openDatabase();
    await seed(
        db, AbilityKey.reactionSpeed, 87.4, DateTime(2026, 10, 24, 9, 5));
    await pumpPage(
      tester,
      db,
      overrides: [
        abilityScoreRepositoryProvider.overrideWithValue(
          _FailingTrendRepository(db),
        ),
      ],
    );

    expect(
      find.byKey(const Key('ability-trend-error-reaction_speed')),
      findsOneWidget,
    );
    expect(find.textContaining('趋势读库失败'), findsOneWidget);
    // 分数与次数照常显示，页面没有整页错误态。
    expect(
      tester.widget<Text>(scoreOf(AbilityKey.reactionSpeed)).data,
      zh.abilityScoreLabel(87),
    );
    expect(find.byKey(const Key('ability-profile-error')), findsNothing);
    expect(find.text(zh.abilityProfileEmpty), findsNothing);
  });
}

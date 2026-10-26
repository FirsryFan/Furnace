// 能力画像页测试：只读页面，直接往内存库的 ability_scores 落记录再断言。
//
// 钉六件事：四项全无记录时是空态（不是四张 0 分卡）、只测一项时其它三项显示没测过、
// 同一项多条记录取最新且次数是总条数、分数四舍五入、读库失败有错误文案（不装空态）、
// 以及写完一条新分数后页面自动刷新（watchDatabaseRevision + instrumentWrites）。
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
  }) async {
    tester.view.physicalSize = const Size(1000, 1600);
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
}

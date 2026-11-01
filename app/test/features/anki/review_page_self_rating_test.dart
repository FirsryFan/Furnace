/// 复习页 7 档自判 + 默认自判 + 按卡组严格的界面验收点。
///
///  * 默认（没写过偏好）打开就是自判：提交后给 7 档按钮，不自动判分；
///  * 严格卡组：不出现 7 档按钮，走客观判分；答错仍走「对过答案吗」；
///  * 自判卡组覆盖全局严格：以卡组为准，出现 7 档按钮；
///  * 点档位写一条 self 日志，档位到 FSRS rating 的映射见纯逻辑测试。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/review_plan_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/features/anki/application/judge_mode_preference.dart';
import 'package:furnace/features/anki/presentation/review_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

void main() {
  late AppDatabase db;
  late AnkiRepository anki;
  late TagRepository tags;
  late ReviewPlanRepository plans;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    anki = AnkiRepository(db);
    tags = TagRepository(db);
    plans = ReviewPlanRepository(db, anki);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<CardTemplate> addCard(
    WidgetTester tester, {
    String? groupTagId,
    String answer = '叶绿体',
  }) async {
    final point = await anki.createKnowledgePoint(
      title: '光合作用场所',
      content: '光合作用的主要场所是叶绿体。',
    );
    if (groupTagId != null) {
      await tags.addTagToObject(
        tagId: groupTagId,
        objectType: 'knowledge_point',
        objectId: point.id,
      );
    }
    final template = await anki.createTemplate(
      knowledgePointId: point.id,
      type: 'fill_blank',
      question: '光合作用的场所是？',
      answer: answer,
    );
    await anki.getOrCreateCardState(template.id);
    return template;
  }

  Future<void> pumpReview(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: ReviewPage()),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('默认自判：提交后不判分，出现 7 档按钮；选档位才写一条 self 日志', (tester) async {
    await addCard(tester);
    await pumpReview(tester);

    await tester.enterText(find.byType(TextField), '叶绿体');
    await tester.tap(find.byTooltip('提交'));
    await settle(tester);

    // 默认自判：没有自动对错，答案与 7 个档位都在屏上。
    expect(await db.select(db.reviewLogs).get(), isEmpty);
    expect(find.text('刚才这张，你的状态是？'), findsOneWidget);
    for (final label in <String>[
      '完全熟练',
      '比较熟练',
      '艰难想起',
      '想起一部分',
      '没想起·有印象',
      '完全没印象',
      '新知识',
    ]) {
      expect(find.text(label), findsOneWidget, reason: '缺档位：$label');
    }

    await tester.tap(find.text('完全熟练'));
    await settle(tester);

    final log = (await db.select(db.reviewLogs).get()).single;
    expect(log.judgeMode, 'self');
    expect(log.correct, 1);
    expect(log.ratingFsrs, 4, reason: '完全熟练 → FSRS Easy');
    expect(log.reviewedSolution, isNull);
    expect(log.closeness, isNull);
  });

  testWidgets('严格卡组：没有 7 档按钮，客观判分直接写 auto 日志', (tester) async {
    final tag = await tags.createTag(name: '数学');
    await plans.setGroupPlan(
      tagId: tag.id,
      newCardsPerDay: 10,
      reviewCardsPerDay: 50,
    );
    await plans.setGroupJudgeMode(tag.id, JudgeModePreference.strict);
    await addCard(tester, groupTagId: tag.id);
    await pumpReview(tester);

    await tester.enterText(find.byType(TextField), '叶绿体');
    await tester.tap(find.byTooltip('提交'));
    await settle(tester);

    expect(find.text('刚才这张，你的状态是？'), findsNothing);
    expect(find.byType(ReviewRatingBar), findsNothing);
    final log = (await db.select(db.reviewLogs).get()).single;
    expect(log.judgeMode, 'auto');
    expect(log.correct, 1);
    expect(log.ratingFsrs, 3, reason: '自动判对 → FSRS Good');
  });

  testWidgets('严格卡组答错：仍走「对过答案吗」，不是 7 档', (tester) async {
    final tag = await tags.createTag(name: '数学');
    await plans.setGroupPlan(
      tagId: tag.id,
      newCardsPerDay: 10,
      reviewCardsPerDay: 50,
    );
    await plans.setGroupJudgeMode(tag.id, JudgeModePreference.strict);
    await addCard(tester, groupTagId: tag.id);
    await pumpReview(tester);

    await tester.enterText(find.byType(TextField), '线粒体');
    await tester.tap(find.byTooltip('提交'));
    await settle(tester);

    expect(find.text('对答案后，你想起来多少？'), findsOneWidget);
    expect(find.byType(ReviewRatingBar), findsNothing);
    expect(await db.select(db.reviewLogs).get(), isEmpty);

    await tester.tap(find.text('还是不会'));
    await settle(tester);
    final log = (await db.select(db.reviewLogs).get()).single;
    expect(log.judgeMode, 'auto');
    expect(log.correct, 0);
    expect(log.reviewedSolution, isFalse);
  });

  testWidgets('自判卡组覆盖全局严格：仍按卡组走 7 档', (tester) async {
    await plans.setJudgeModePreference(JudgeModePreference.strict);
    final tag = await tags.createTag(name: '语文');
    await plans.setGroupPlan(
      tagId: tag.id,
      newCardsPerDay: 10,
      reviewCardsPerDay: 50,
    );
    await plans.setGroupJudgeMode(tag.id, JudgeModePreference.self);
    await addCard(tester, groupTagId: tag.id);
    await pumpReview(tester);

    await tester.enterText(find.byType(TextField), '叶绿体');
    await tester.tap(find.byTooltip('提交'));
    await settle(tester);

    expect(find.text('刚才这张，你的状态是？'), findsOneWidget, reason: '卡组的自判覆盖全局严格');
    expect(await db.select(db.reviewLogs).get(), isEmpty);

    await tester.tap(find.text('比较熟练'));
    await settle(tester);
    final log = (await db.select(db.reviewLogs).get()).single;
    expect(log.judgeMode, 'self');
    expect(log.correct, 1);
    expect(log.ratingFsrs, 3);
  });
}

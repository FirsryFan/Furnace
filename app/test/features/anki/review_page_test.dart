import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/features/anki/application/review_advisory.dart';
import 'package:furnace/features/anki/presentation/review_page.dart';
import 'package:furnace/features/cognitive/presentation/cognitive_model_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// The practice screen's half of the contract: the mode control is reachable
/// while answering, the hint waits for the user, and the card type decides how
/// the answer is given - and what the review log records.
void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> pumpReview(
    WidgetTester tester,
    AppDatabase db, {
    List<Override> extra = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          ...extra,
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

  Future<(AppDatabase, AnkiRepository)> openDatabase() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    return (db, AnkiRepository(db));
  }

  Future<CardTemplate> addCard(
    AnkiRepository anki, {
    required String type,
    required String question,
    required String answer,
    List<String> options = const [],
    String? hint,
  }) async {
    final point = await anki.createKnowledgePoint(
      title: '光合作用场所',
      content: '光合作用的主要场所是叶绿体。',
    );
    final template = await anki.createTemplate(
      knowledgePointId: point.id,
      type: type,
      question: question,
      answer: answer,
      options: options,
      hint: hint,
    );
    await anki.getOrCreateCardState(template.id);
    return template;
  }

  testWidgets(
      'the hint is revealed by the button, never on its own, and is '
      'not a graded event', (tester) async {
    final (db, anki) = await openDatabase();
    await addCard(
      anki,
      type: 'fill_blank',
      question: '光合作用的场所是？',
      answer: '叶绿体',
      hint: '想想叶子的颜色',
    );

    await pumpReview(tester, db);

    expect(find.text('提示'), findsOneWidget,
        reason: 'the queue must have loaded with the card');
    expect(find.text('想想叶子的颜色'), findsNothing,
        reason: 'the hint must not auto-reveal');
    expect(await db.select(db.reviewLogs).get(), isEmpty);

    await tester.tap(find.text('提示'));
    await tester.pump();

    expect(find.text('想想叶子的颜色'), findsOneWidget);
    expect(find.text('提示'), findsNothing);
    expect(await db.select(db.reviewLogs).get(), isEmpty,
        reason: 'revealing the hint is not an answer');
  });

  testWidgets('a card without a hint offers no hint button', (tester) async {
    final (db, anki) = await openDatabase();
    await addCard(
      anki,
      type: 'fill_blank',
      question: '光合作用的场所是？',
      answer: '叶绿体',
    );

    await pumpReview(tester, db);

    expect(find.byType(TextField), findsOneWidget,
        reason: 'the queue must have loaded with the card');
    expect(find.text('提示'), findsNothing);
  });

  testWidgets('strict mode rejects a typo that lenient mode accepts',
      (tester) async {
    final (db, anki) = await openDatabase();
    await addCard(
      anki,
      type: 'fill_blank',
      question: '光合作用的场所是？',
      answer: '叶绿体',
    );

    await pumpReview(tester, db);
    await tester.enterText(find.byType(TextField), '叶绿休');
    await tester.tap(find.byTooltip('提交'));
    await settle(tester);

    // A failed recall is not written yet: "I just missed it" and "I did not know
    // it" are two different model events, and writing a guess would apply two
    // events to one review.
    expect(await db.select(db.reviewLogs).get(), isEmpty,
        reason: 'the review is written once, after the solution question');
    expect(find.text('对答案后，你想起来多少？'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.arrow_forward))
          .onPressed,
      isNull,
      reason: 'there is nothing to advance from until the review is recorded',
    );

    await tester.tap(find.text('差点想起来'));
    await settle(tester);

    final log = (await db.select(db.reviewLogs).get()).single;
    expect(log.correct, 0, reason: 'strict compares characters exactly');
    expect(log.judgeMode, 'auto');
    expect(log.format, 'fill');
    expect(log.reviewedSolution, isTrue);
    expect(log.closeness, closeTo(0.6, 1e-9));
  });

  testWidgets(
      'a correct answer never asks the solution question and is written '
      'immediately', (tester) async {
    final (db, anki) = await openDatabase();
    await addCard(
      anki,
      type: 'fill_blank',
      question: '光合作用的场所是？',
      answer: '叶绿体',
    );

    await pumpReview(tester, db);
    await tester.enterText(find.byType(TextField), '叶绿体');
    await tester.tap(find.byTooltip('提交'));
    await settle(tester);

    expect(find.text('对答案后，你想起来多少？'), findsNothing);

    final log = (await db.select(db.reviewLogs).get()).single;
    expect(log.correct, 1);
    expect(log.reviewedSolution, isNull,
        reason: 'the question was never asked, so the column stays unknown - '
            'not a fabricated "no"');
    expect(log.closeness, isNull);
  });

  testWidgets('the mode control turns the same typo into a correct answer',
      (tester) async {
    final (db, anki) = await openDatabase();
    await addCard(
      anki,
      type: 'fill_blank',
      question: '光合作用的场所是？',
      answer: '叶绿体',
    );

    await pumpReview(tester, db);
    await tester.enterText(find.byType(TextField), '叶绿休');
    await tester.tap(find.text('宽松'));
    await tester.pump();
    await tester.tap(find.byTooltip('提交'));
    await settle(tester);

    final log = (await db.select(db.reviewLogs).get()).single;
    expect(log.correct, 1);
    expect(log.judgeMode, 'auto',
        reason: 'the column says who judged, and the app judged');
  });

  testWidgets('self mode shows the answer and records the user verdict',
      (tester) async {
    final (db, anki) = await openDatabase();
    await addCard(
      anki,
      type: 'fill_blank',
      question: '光合作用的场所是？',
      answer: '叶绿体',
    );

    await pumpReview(tester, db);
    await tester.enterText(find.byType(TextField), '线粒体');
    await tester.tap(find.text('自判'));
    await tester.pump();
    await tester.tap(find.byTooltip('提交'));
    await settle(tester);

    expect(find.textContaining('自己判分'), findsOneWidget);
    expect(find.text('答案: 叶绿体'), findsOneWidget);
    expect(await db.select(db.reviewLogs).get(), isEmpty,
        reason: 'nothing is graded until the user judges');

    await tester.tap(find.byTooltip('记得'));
    await settle(tester);

    final log = (await db.select(db.reviewLogs).get()).single;
    expect(log.judgeMode, 'self');
    expect(log.correct, 1, reason: 'the user said they remembered it');
  });

  testWidgets('an essay card is always judged by the user', (tester) async {
    final (db, anki) = await openDatabase();
    await addCard(
      anki,
      type: 'essay',
      question: '光合作用的意义是什么？',
      answer: '把光能转成化学能。',
    );

    await pumpReview(tester, db);
    await tester.tap(find.byTooltip('提交'));
    await settle(tester);

    expect(find.textContaining('自己判分'), findsOneWidget);
    expect(await db.select(db.reviewLogs).get(), isEmpty);

    await tester.tap(find.byTooltip('忘记'));
    await settle(tester);
    expect(await db.select(db.reviewLogs).get(), isEmpty,
        reason: 'the failed recall still waits for the solution question');

    await tester.tap(find.text('还是不会'));
    await settle(tester);

    final log = (await db.select(db.reviewLogs).get()).single;
    expect(log.judgeMode, 'self');
    expect(log.correct, 0);
    expect(log.format, 'essay');
    expect(log.reviewedSolution, isFalse,
        reason: 'the user was asked and said no');
    expect(log.closeness, isNull, reason: 'a bare lapse carries no closeness');
  });

  testWidgets('a choice card renders its options and records the tapped one',
      (tester) async {
    final (db, anki) = await openDatabase();
    final template = await addCard(
      anki,
      type: 'mcq',
      question: '光合作用的场所是？',
      answer: '叶绿体',
      options: ['线粒体', '叶绿体', '细胞核'],
    );

    await pumpReview(tester, db);

    expect(find.text('线粒体'), findsOneWidget);
    expect(find.text('叶绿体'), findsOneWidget);
    expect(find.text('细胞核'), findsOneWidget);

    await tester.tap(find.text('叶绿体'));
    await tester.pump();
    await tester.tap(find.text('提交'));
    await settle(tester);

    final log = (await db.select(db.reviewLogs).get()).single;
    expect(log.correct, 1, reason: 'judged by option identity');
    expect(log.format, 'mcq');
    expect(log.judgeMode, 'auto');
    expect(log.cardTemplateId, template.id);
  });

  testWidgets('a choice card records a wrong option as wrong', (tester) async {
    final (db, anki) = await openDatabase();
    await addCard(
      anki,
      type: 'mcq',
      question: '光合作用的场所是？',
      answer: '叶绿体',
      options: ['线粒体', '叶绿体', '细胞核'],
    );

    await pumpReview(tester, db);
    await tester.tap(find.text('线粒体'));
    await tester.pump();
    await tester.tap(find.text('提交'));
    await settle(tester);

    // The options plus the feedback make this card tall, so the question the
    // buttons live in can sit below the fold on the test's small viewport.
    await tester.ensureVisible(find.text('还是不会'));
    await tester.pump();
    await tester.tap(find.text('还是不会'));
    await settle(tester);

    final log = (await db.select(db.reviewLogs).get()).single;
    expect(log.correct, 0);
    expect(log.format, 'mcq');
    expect(log.reviewedSolution, isFalse);
  });

  // The chip is the only place the fast layer's verdict reaches the user while
  // practising, and it must be the *same* verdict the 认知模型 page reports: this
  // test hands the screen the very reading the page would hand it.
  CognitiveReadings readingsWith(Map<String, ReviewZone> zones) =>
      CognitiveReadings(
        modelId: 'test',
        nowHours: 0,
        nowUtc: DateTime.utc(2024),
        cards: const [],
        bandByCardStateId: const {},
        scoreByCardStateId: const {},
        zoneByKnowledgePoint: zones,
        fastLayerRan: true,
      );

  testWidgets(
      'a diagnosed knowledge point shows the fast layer verdict as a '
      'chip that acts on nothing', (tester) async {
    final (db, anki) = await openDatabase();
    final template = await addCard(
      anki,
      type: 'fill_blank',
      question: '光合作用的场所是？',
      answer: '叶绿体',
      hint: '想想叶子的颜色',
    );

    await pumpReview(
      tester,
      db,
      extra: [
        cognitiveReadingsProvider.overrideWith(
          (ref) async =>
              readingsWith({template.knowledgePointId: ReviewZone.empty}),
        ),
      ],
    );

    expect(find.text('模型看这块：空（进不去）'), findsOneWidget);
    expect(find.text('提示'), findsOneWidget,
        reason: 'the chip must not displace the answer controls');
    expect(await db.select(db.reviewLogs).get(), isEmpty,
        reason: 'a diagnosis is context, not an answer');
  });

  testWidgets('an undiagnosed knowledge point shows no chip at all',
      (tester) async {
    final (db, anki) = await openDatabase();
    final template = await addCard(
      anki,
      type: 'fill_blank',
      question: '光合作用的场所是？',
      answer: '叶绿体',
    );

    await pumpReview(
      tester,
      db,
      extra: [
        // The layer ran and had nothing to report, and the other arm: it did not
        // run at all. Neither may be dressed up as a finding.
        cognitiveReadingsProvider.overrideWith(
          (ref) async =>
              readingsWith({template.knowledgePointId: ReviewZone.healthy}),
        ),
      ],
    );
    expect(find.textContaining('模型看这块'), findsNothing);

    await pumpReview(
      tester,
      db,
      extra: [
        cognitiveReadingsProvider.overrideWith(
          (ref) async =>
              readingsWith({template.knowledgePointId: ReviewZone.unavailable}),
        ),
      ],
    );
    expect(find.textContaining('模型看这块'), findsNothing);
  });

  testWidgets('「读过，没测自己」：不写复习记录、不动到期日，只留一条曝光', (tester) async {
    final (db, anki) = await openDatabase();
    await addCard(
      anki,
      type: 'fill_blank',
      question: '光合作用的场所是？',
      answer: '叶绿体',
    );
    final before = (await db.select(db.cardStates).get()).single;

    await pumpReview(tester, db);
    await tester.tap(find.byTooltip('显示答案'));
    await tester.pump();

    // The button only exists in the one state it describes: the answer is on
    // screen and nothing has been written yet.
    final exposure = find.byTooltip('只算读过，不算一次复习：不改到期日，也不进复习记录');
    expect(exposure, findsOneWidget);

    await tester.tap(exposure);
    await settle(tester);

    final rows = await db.select(db.exposureLogs).get();
    expect(rows, hasLength(1));
    expect(rows.single.cardStateId, before.id);
    expect(rows.single.source, kExposureSourceAnswerReveal);
    expect(await db.select(db.reviewLogs).get(), isEmpty,
        reason: '读了没测不是一次测试，复习记录必须仍然是空的');

    final after = (await db.select(db.cardStates).get()).single;
    expect(after.dueAt, before.dueAt, reason: '到期日不变');
    expect(after.repetitions, before.repetitions);
    expect(after.lastReviewedAt, before.lastReviewedAt);

    // The press answers its own question out loud: it did not count as a review.
    expect(find.text('已记下「读过、没测」：这次不算复习，到期日不变'), findsOneWidget);
  });
}

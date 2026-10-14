/// The assessment flow, checked against the rows it writes.
///
/// The reading page's test can only check pixels (it is select-only); this page
/// is where the model gets its first real input, so the interesting assertions
/// are the session, the steps and the priors - and, just as importantly, that
/// *nothing* is written before the last step.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/features/assessment/presentation/assessment_page.dart';
import 'package:furnace/features/cognitive/presentation/cognitive_model_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// Pumps an arbitrary page against [db] (the reading page's entry test needs a
/// different `home` than the assessment flow itself).
Future<void> _pumpPage(WidgetTester tester, AppDatabase db, Widget home) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _pump(WidgetTester tester, AppDatabase db) async {
  // A tall surface so the five rating rows and the three recall cards are all
  // built: they live in a ListView, and an off-screen row cannot be tapped.
  await _pumpPage(tester, db, const AssessmentPage());
}

/// Yields to the event loop until the loading spinner is gone. `pumpAndSettle`
/// cannot be used while a `CircularProgressIndicator` is on screen: it animates
/// forever and would time out.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      return;
    }
  }
  fail('still loading after 30 pumps');
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await _settle(tester);
}

/// Two tags, one of them a child, and five knowledge points on the child.
///
/// The parent tag is the one the test selects: the child's points must come
/// along, because "选一块范围" means the subtree, not the single tag.
Future<void> _seed(AppDatabase db) async {
  await db.into(db.tags).insert(TagsCompanion.insert(
        id: 't-root',
        name: '生物',
        path: const Value('生物'),
        createdAt: 1,
        updatedAt: 1,
      ));
  await db.into(db.tags).insert(TagsCompanion.insert(
        id: 't-cell',
        parentId: const Value('t-root'),
        name: '细胞',
        path: const Value('生物/细胞'),
        createdAt: 1,
        updatedAt: 1,
      ));
  const titles = ['A', 'B', 'C', 'D', 'E'];
  for (final title in titles) {
    final id = 'kp-${title.toLowerCase()}';
    await db.into(db.knowledgePoints).insert(KnowledgePointsCompanion.insert(
          id: id,
          title: title,
          content: '内容 $title',
          createdAt: 1,
          updatedAt: 1,
        ));
    await db.into(db.objectTags).insert(ObjectTagsCompanion.insert(
          id: 'ot-$id',
          tagId: 't-cell',
          objectType: 'knowledge_point',
          objectId: id,
          createdAt: 1,
        ));
  }
}

void main() {
  testWidgets('the flow writes one session, four steps, and the scope priors',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seed(db);
    await _pump(tester, db);

    expect(find.text('给模型一个起点'), findsOneWidget);

    await _tap(tester, find.widgetWithText(FilterChip, '生物'));
    expect(
      find.text('这块里有 5 个知识点'),
      findsOneWidget,
      reason: 'selecting 生物 must pull in the knowledge points of 细胞',
    );
    expect(
      await db.select(db.assessmentSessions).get(),
      isEmpty,
      reason: 'nothing may be written before the last step',
    );

    await _tap(tester, find.text('下一步'));
    await _tap(tester, find.byKey(const ValueKey('self-kp-a-4')));
    await _tap(tester, find.byKey(const ValueKey('self-kp-b-2')));
    expect(find.text('已自评 2 / 5 个'), findsOneWidget);

    await _tap(tester, find.text('下一步'));
    // The three prompts are the two ends and the middle: A, C, E - never the
    // "weakest" points, which would turn the instrument into a card drill.
    for (final id in ['kp-a', 'kp-c', 'kp-e']) {
      expect(find.byKey(ValueKey('recall-answer-$id')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('recall-answer-kp-b')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('recall-answer-kp-a')),
      '光反应在类囊体膜上',
    );
    await _tap(tester, find.byKey(const ValueKey('recall-kp-a-3')));
    await _tap(tester, find.byKey(const ValueKey('recall-kp-e-1')));

    await _tap(tester, find.text('下一步'));
    await _tap(tester, find.widgetWithText(FilledButton, '完成并重算先验'));
    expect(find.text('这一轮的读数'), findsOneWidget);
    expect(find.text('写入 4 步证据，重算 3 个知识点的先验。'), findsOneWidget);
    expect(find.textContaining('平均起点 R0 '), findsOneWidget);
    expect(
      find.textContaining('未标定'),
      findsWidgets,
      reason:
          'the uncalibrated disclaimer is part of the reading, not optional',
    );

    final sessions = await db.select(db.assessmentSessions).get();
    expect(sessions, hasLength(1));
    expect(sessions.single.scopeTagIds, '["t-root"]');
    expect(sessions.single.finishedAt, isNotNull);

    final steps = await db.select(db.assessmentResponses).get();
    expect(steps, hasLength(4));
    expect(
      steps.map((step) => step.stepKind).toList()..sort(),
      ['recall', 'recall', 'self_report', 'self_report'],
    );
    expect(steps.every((step) => step.judgedBy == 'self'), isTrue);
    expect(
      steps
          .firstWhere((step) =>
              step.stepKind == 'recall' && step.knowledgePointId == 'kp-a')
          .answer,
      '光反应在类囊体膜上',
    );

    final priors = await db.select(db.cognitivePriors).get();
    expect(priors, hasLength(3));
    expect(
      priors.map((prior) => prior.knowledgePointId).toList()..sort(),
      ['kp-a', 'kp-b', 'kp-e'],
    );
  });

  testWidgets('a fully skipped round writes no evidence and says so',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seed(db);
    await _pump(tester, db);

    await _tap(tester, find.widgetWithText(FilterChip, '生物'));
    await _tap(tester, find.text('下一步'));
    await _tap(tester, find.text('下一步'));
    await _tap(tester, find.text('下一步'));
    await _tap(tester, find.widgetWithText(FilledButton, '完成并重算先验'));

    expect(find.textContaining('一步证据都没写'), findsWidgets);
    expect(
      await db.select(db.assessmentResponses).get(),
      isEmpty,
      reason: 'a skipped point stays absent rather than becoming a 0',
    );
    expect(
      await db.select(db.cognitivePriors).get(),
      isEmpty,
      reason: 'an empty round must not wipe or fabricate priors',
    );
    expect(
      await db.select(db.assessmentSessions).get(),
      hasLength(1),
      reason: 'the round itself is still a recorded measurement event',
    );
  });

  testWidgets('the reading page entry opens the measurement page',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seed(db);
    expect(
      await db.select(db.tags).get(),
      hasLength(2),
      reason: 'the seed must be visible before the page reads it',
    );
    await _pumpPage(tester, db, const CognitiveModelPage());

    final entry = find.widgetWithText(FilledButton, '测一测（给模型一个起点）');
    expect(
      entry,
      findsOneWidget,
      reason: 'the reading page is where a user notices the model has no data',
    );

    await tester.tap(entry);
    // The pushed page loads its tag list asynchronously, and `_settle` can
    // return on the frame before that future is even registered; pump a fixed
    // number of frames instead of trusting the spinner.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.byType(AssessmentPage), findsOneWidget);
    expect(find.text('给模型一个起点'), findsWidgets);
    expect(
      find.widgetWithText(FilterChip, '生物'),
      findsOneWidget,
      reason: 'the measurement page picks up the same database',
    );
  });

  test('the recall picks are the two ends and the middle', () {
    List<KnowledgePoint> points(int count) => [
          for (var i = 0; i < count; i++)
            KnowledgePoint(
              id: 'k$i',
              title: 'T$i',
              content: 'c',
              createdAt: 1,
              updatedAt: 1,
            ),
        ];

    expect(recallPicks(points(5)).map((kp) => kp.id), ['k0', 'k2', 'k4']);
    expect(recallPicks(points(2)).map((kp) => kp.id), ['k0', 'k1']);
    expect(recallPicks(points(0)), isEmpty);
  });
}

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/features/anki/presentation/review_plan_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// The deck-settings screen's answer to "why is there nothing to set?".
///
/// The load-bearing claims:
///
///  * cards with no tag are **named** on the page instead of being invisible -
///    a card group is a tag, so an untagged card is in no group and no daily
///    target can reach it;
///  * the one-tap fix actually links every such card to the picked tag, and the
///    group's daily target editor opens straight after, because tagging alone
///    still leaves the group unlimited;
///  * the empty plan state still offers the "add a group target" action, which
///    is the entry the user was missing.
void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> pumpPlan(
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
          home: ReviewPlanPage(),
        ),
      ),
    );
    await settle(tester);
  }

  Future<(AppDatabase, AnkiRepository, TagRepository)> openDatabase() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    return (db, AnkiRepository(db), TagRepository(db));
  }

  testWidgets(
      'ungrouped cards are called out, and the empty plan still has '
      'an add action', (tester) async {
    final (db, anki, _) = await openDatabase();
    await anki.createKnowledgePoint(title: 'first', content: 'one');
    await anki.createKnowledgePoint(title: 'second', content: 'two');

    await pumpPlan(tester, db);

    expect(find.text('有 2 张卡还没有卡组'), findsOneWidget);
    expect(find.text('把它们归到一个卡组'), findsOneWidget);
    // The plan list is empty, but the way to fill it must be on screen - this
    // is exactly the entry that looked missing.
    expect(find.text('添加卡组任务量'), findsOneWidget);
  });

  testWidgets('one tap tags every ungrouped card, then opens its daily target',
      (tester) async {
    final (db, anki, tags) = await openDatabase();
    final tag = await tags.createTag(name: '语文');
    await anki.createKnowledgePoint(title: 'first', content: 'one');
    await anki.createKnowledgePoint(title: 'second', content: 'two');

    await pumpPlan(tester, db);

    await tester.tap(find.text('把它们归到一个卡组'));
    await settle(tester);
    expect(find.text('选择卡组'), findsOneWidget);

    await tester.tap(find.text('语文'));
    await settle(tester);

    // The editor opens on its own: "which group" alone does not set a number.
    expect(find.text('语文 的每日任务量'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '20');
    await tester.tap(find.text('保存'));
    await settle(tester);

    expect((await db.select(db.objectTags).get()).length, 2);
    final plan = (await db.select(db.reviewGroupPlans).get()).single;
    expect(plan.tagId, tag.id);
    expect(plan.newCardsPerDay, 20);
    // The page now lists the configured group with its target.
    expect(find.text('目标：新卡 20 · 复习 0'), findsOneWidget);
  });

  testWidgets('no tags at all: points at creating the tag instead of failing',
      (tester) async {
    final (db, anki, _) = await openDatabase();
    await anki.createKnowledgePoint(title: 'first', content: 'one');

    await pumpPlan(tester, db);

    await tester.tap(find.text('把它们归到一个卡组'));
    await settle(tester);

    expect(find.text('还没有标签：卡组就是标签，请先建标签。'), findsOneWidget);
    expect(await db.select(db.objectTags).get(), isEmpty);
  });
}

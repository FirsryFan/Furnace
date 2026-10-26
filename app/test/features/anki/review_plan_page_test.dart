import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/domain/services/tags/tag_usage.dart';
import 'package:furnace/features/anki/application/flashcard_tag_scope.dart';
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

  Future<void> waitUntil(
    WidgetTester tester,
    bool Function() condition, {
    String reason = '条件',
  }) async {
    for (var i = 0; i < 150; i++) {
      if (condition()) {
        return;
      }
      await tester.pump(const Duration(milliseconds: 20));
    }
    fail('$reason 在 3 秒模拟时间内未满足');
  }

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(ReviewPlanPage)));

  testWidgets(
      'ungrouped cards are called out, and the empty plan still has '
      'an add action', (tester) async {
    final (db, anki, _) = await openDatabase();
    await anki.createKnowledgePoint(title: 'first', content: 'one');
    await anki.createKnowledgePoint(title: 'second', content: 'two');

    await pumpPlan(tester, db);

    expect(find.text('有 2 张卡还没有卡组'), findsOneWidget);
    expect(find.text('把它们归到一个卡组'), findsOneWidget);
    // The plan list is empty, but the way to fill it must be reachable - this
    // is exactly the entry that looked missing. The preferences card above
    // grew (review spacing section), so on the default 800x600 surface the
    // lazy list has not built the empty-plan button yet.
    await tester.scrollUntilVisible(
      find.text('添加卡组任务量'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
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

  // v37 起标签行带用途声明：卡组选择器只列「纳入闪卡」的标签；过滤后为空
  // 不许静默返回，要和「一个标签都没有」区分开。
  testWidgets('卡组选择器只列「纳入闪卡」的标签，并常显过滤提示', (tester) async {
    final (db, anki, tags) = await openDatabase();
    final flashTag = await tags.createTag(name: '闪卡标签');
    final questionTag = await tags.createTag(name: '题库标签');
    await tags.updateTagUsageCodes(flashTag.id, {TagUsage.flashcard});
    await tags.updateTagUsageCodes(questionTag.id, {TagUsage.question});
    await anki.createKnowledgePoint(title: 'first', content: 'one');
    await pumpPlan(tester, db);
    final l10n = l10nOf(tester);

    await tester.tap(find.text('把它们归到一个卡组'));
    await settle(tester);
    expect(find.text('选择卡组'), findsOneWidget);
    expect(find.text('闪卡标签'), findsOneWidget);
    expect(
      find.text('题库标签'),
      findsNothing,
      reason: '只声明了题库用途的标签不能出现在卡组选择器里',
    );
    expect(
      find.text(l10n.tagUsageScopeHintFlashcard),
      findsOneWidget,
      reason: '过滤提示常显，用户不用点开才知道规则',
    );
    expect(await db.select(db.objectTags).get(), isEmpty);
  });

  testWidgets('有用途声明但没有闪卡标签：说明空态而不是静默返回', (tester) async {
    final (db, anki, tags) = await openDatabase();
    final questionTag = await tags.createTag(name: '题库标签');
    await tags.updateTagUsageCodes(questionTag.id, {TagUsage.question});
    await anki.createKnowledgePoint(title: 'first', content: 'one');
    await pumpPlan(tester, db);
    final l10n = l10nOf(tester);

    await tester.tap(find.text('把它们归到一个卡组'));
    await waitUntil(
      tester,
      () => find.byKey(flashcardTagScopeEmptyKey).evaluate().isNotEmpty,
      reason: '空态说明框未出现',
    );
    expect(find.text(l10n.tagUsageScopeEmptyFlashcard), findsOneWidget);
    expect(find.byType(SimpleDialogOption), findsNothing);
    expect(find.text('题库标签'), findsNothing);
    expect(
      find.text('还没有标签：卡组就是标签，请先建标签。'),
      findsNothing,
      reason: '有标签、只是都不是闪卡：不该说「还没有标签」',
    );
    expect(await db.select(db.objectTags).get(), isEmpty);
  });

  testWidgets('整树没有用途声明时不过滤：卡组选择器列出全部标签', (tester) async {
    final (db, anki, tags) = await openDatabase();
    await tags.createTag(name: '标签甲');
    await tags.createTag(name: '标签乙');
    await anki.createKnowledgePoint(title: 'first', content: 'one');
    await pumpPlan(tester, db);

    await tester.tap(find.text('把它们归到一个卡组'));
    await settle(tester);
    expect(find.text('选择卡组'), findsOneWidget);
    expect(find.text('标签甲'), findsOneWidget);
    expect(find.text('标签乙'), findsOneWidget);
  });
}

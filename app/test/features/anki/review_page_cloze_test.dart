import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/features/anki/presentation/review_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// Q26 的界面两半：**自由挖空就地呈现**，以及**会话内强制重做闭环**（D11）。
///
/// 两件事以前都不存在：句子里的 `______` 是一段死文本（只是把原答案换成下划线，
/// 没有位置信息可用），而「答错今天之内再出现、连续两次答对才解除」只能等到下一
/// 轮 `buildQueue`——同一个会话里看不到。
///
/// 10 分钟到点之后的行为不在这里测：`ReviewPage` 读的是真实时钟，widget test 里
/// 没有可注入的钟，所以「到点放行 / 连续两次解除」由
/// `test/domain/services/cloze/forced_loop_test.dart`（纯规则）和
/// `test/features/anki/review_service_test.dart`（streak 真的写在行上）覆盖，
/// 这里只钉住「没到点不显示」这一半。
void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> pumpReview(WidgetTester tester, AppDatabase db) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
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

  /// 一个内容推导出来的空：没有模板，`ClozeEngine.discoverCandidates` 从内容里
  /// 挖出「叶绿体」，所以 `clozeSlotKey` / `slotStart` 是有的。
  Future<KnowledgePoint> addClozePoint(AnkiRepository anki) {
    return anki.createKnowledgePoint(
      title: '光合作用场所',
      content: '光合作用的主要场所是叶绿体。',
    );
  }

  /// 就地渲染的那一句（含空格位置的整句）。
  String clozeSentence(WidgetTester tester) {
    final selectable = tester.widget<SelectableText>(
      find.descendant(
        of: find.byKey(const ValueKey('cloze-sentence')),
        matching: find.byType(SelectableText),
      ),
    );
    return selectable.textSpan!.toPlainText();
  }

  Future<void> tapNext(WidgetTester tester) async {
    await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_forward));
    await settle(tester);
  }

  testWidgets('自由挖空留在句子的原位，作答后把答案填回那个空', (tester) async {
    final (db, anki) = await openDatabase();
    await addClozePoint(anki);

    await pumpReview(tester, db);

    // 就地呈现：整句还是原来那句，只有被抽走的那一段变成下划线。
    expect(clozeSentence(tester), '光合作用的主要场所是______。');
    expect(find.text('新空'), findsOneWidget, reason: '第一次抽到、还没复习过的空');

    await tester.enterText(find.byType(TextField), '叶绿体');
    await tester.tap(find.byTooltip('提交'));
    await settle(tester);

    // 答案填回原位，而不是只出现在下面那张反馈卡里。
    expect(clozeSentence(tester), '光合作用的主要场所是叶绿体。');
    expect(clozeSentence(tester), isNot(contains('______')));
  });

  testWidgets('答错后（队列只剩这一张）同一张卡连续重做，答对一次先进等待态', (tester) async {
    final (db, anki) = await openDatabase();
    await addClozePoint(anki);

    await pumpReview(tester, db);

    // 1) 答错：还没写日志，先问「读了答案想起来多少」。
    await tester.enterText(find.byType(TextField), '线粒体');
    await tester.tap(find.byTooltip('提交'));
    await settle(tester);
    expect(find.text('对答案后，你想起来多少？'), findsOneWidget);
    expect(await db.select(db.reviewLogs).get(), isEmpty);

    await tester.tap(find.text('还是不会'));
    await settle(tester);

    // 2) 队列只有这一张、后面没有空卡：按用户新口径它只能连续出现 —— 会话内
    // 闭环，不用等下一轮队列。
    await tapNext(tester);
    expect(clozeSentence(tester), '光合作用的主要场所是______。');
    expect(find.text('新空'), findsNothing, reason: '重做不是一张新空');

    // 3) 这次答对：仍在强制期内，位置隔 gap 张（这里没有别的卡），约 10 分钟后
    // 才会再出现。
    await tester.enterText(find.byType(TextField), '叶绿体');
    await tester.tap(find.byTooltip('提交'));
    await settle(tester);
    expect(
      find.text('答错了：这个空会在今天之内再出现，直到连续两次答对。'),
      findsOneWidget,
      reason: '这一轮还没结束，不能告诉用户「下次复习 N 天后」',
    );

    await tapNext(tester);

    // 4) 还没到点：老实等着，不提前放它出来。
    expect(find.text('这个空刚答对一次，要过一会儿才再出现：还有 10 分钟。'), findsOneWidget);
    expect(find.text('到点了，继续'), findsOneWidget);
    expect(find.byKey(const ValueKey('cloze-sentence')), findsNothing,
        reason: '没到下限的空不许提前显示');
  });

  testWidgets('模板卡走原来的渲染：不套用就地挖空', (tester) async {
    final (db, anki) = await openDatabase();
    final point = await anki.createKnowledgePoint(
      title: '光合作用场所',
      content: '光合作用的主要场所是叶绿体。',
    );
    final template = await anki.createTemplate(
      knowledgePointId: point.id,
      type: 'fill_blank',
      question: '光合作用的场所是？',
      answer: '叶绿体',
    );
    await anki.getOrCreateCardState(template.id);

    await pumpReview(tester, db);

    expect(find.byKey(const ValueKey('cloze-sentence')), findsNothing);
    expect(find.text('光合作用的场所是？'), findsOneWidget);
    expect(find.text('新空'), findsNothing);
  });
}

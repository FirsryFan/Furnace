import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/features/anki/presentation/anki_manage_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// The manage list can only preview two lines of a knowledge point, and a tap
/// used to open the tag dialog rather than the card itself. These tests pin the
/// bottom sheet that now carries the whole, selectable card text together with
/// the actions (auto blank / new template / edit / delete) the row already had.
void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// Pumps until [condition] holds without demanding a quiescent tree: an open
  /// text field keeps scheduling frames for its blinking cursor, so
  /// pumpAndSettle can time out while a dialog is up.
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

  Future<(AppDatabase, AnkiRepository)> openDatabase() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    return (db, AnkiRepository(db));
  }

  void useTallView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpManage(WidgetTester tester, AppDatabase db) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AnkiManagePage(),
        ),
      ),
    );
    await settle(tester);
  }

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(AnkiManagePage)));

  SelectableText sheetContent(WidgetTester tester) =>
      tester.widget<SelectableText>(find.byKey(ankiKnowledgeContentKey));

  bool dialogVisible() => find.byType(AlertDialog).evaluate().isNotEmpty;

  Finder sheetOf(String id) => find.byKey(ankiKnowledgeDetailKeyFor(id));

  Future<void> openDetail(
    WidgetTester tester,
    String title,
    String id,
  ) async {
    await tester.tap(find.text(title));
    await waitUntil(
      tester,
      () => sheetOf(id).evaluate().isNotEmpty,
      reason: '详情弹层未出现',
    );
    await settle(tester);
  }

  testWidgets('列表行只预览两行，点行后弹层显示完整正文', (tester) async {
    useTallView(tester);
    final (db, anki) = await openDatabase();
    const sentence = '光合作用的场所是叶绿体，产物是葡萄糖和氧气。';
    final content = sentence * 30;
    final point = await anki.createKnowledgePoint(
      title: '光合作用场所',
      content: content,
    );
    await pumpManage(tester, db);

    final preview = find.descendant(
      of: find.byType(ListTile),
      matching: find.text(content),
    );
    expect(preview, findsOneWidget);
    final previewText = tester.widget<Text>(preview);
    expect(previewText.maxLines, 2);
    expect(previewText.overflow, TextOverflow.ellipsis);

    await openDetail(tester, '光合作用场所', point.id);
    expect(sheetOf(point.id), findsOneWidget);
    final body = sheetContent(tester);
    expect(body.data, content);
    expect(body.data!.length, greaterThan(200));
    expect(body.maxLines, isNull);
  });

  testWidgets('弹层显示卡片内容标题与知识点标签', (tester) async {
    useTallView(tester);
    final (db, anki) = await openDatabase();
    final tags = TagRepository(db);
    final point = await anki.createKnowledgePoint(
      title: '细胞器',
      content: '线粒体负责呼吸作用，叶绿体负责光合作用。',
    );
    final tag = await tags.createTag(name: '生物');
    await tags.addTagToObject(
      tagId: tag.id,
      objectType: 'knowledge_point',
      objectId: point.id,
    );
    await pumpManage(tester, db);
    final l10n = l10nOf(tester);

    await openDetail(tester, '细胞器', point.id);
    final sheet = sheetOf(point.id);
    expect(sheet, findsOneWidget);
    expect(
      find.descendant(
          of: sheet, matching: find.text(l10n.ankiCardContentTitle)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text(tag.path ?? tag.name)),
      findsOneWidget,
    );
    expect(sheetContent(tester).data, '线粒体负责呼吸作用，叶绿体负责光合作用。');
  });

  testWidgets('弹层的模板列表可点开模板编辑对话框', (tester) async {
    useTallView(tester);
    final (db, anki) = await openDatabase();
    final point = await anki.createKnowledgePoint(
      title: '动量守恒',
      content: '系统不受外力时总动量守恒。',
    );
    await anki.createTemplate(
      knowledgePointId: point.id,
      type: 'fill_blank',
      question: '动量守恒的条件是？',
      answer: '系统不受外力',
    );
    await pumpManage(tester, db);
    final l10n = l10nOf(tester);

    await openDetail(tester, '动量守恒', point.id);
    final sheet = sheetOf(point.id);
    final question = find.descendant(
      of: sheet,
      matching: find.text('动量守恒的条件是？'),
    );
    expect(question, findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.text(l10n.ankiTypeFillBlank)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: sheet,
        matching: find.text(l10n.handwritingProposalCardCount(1)),
      ),
      findsOneWidget,
    );

    await tester.tap(question);
    await waitUntil(tester, dialogVisible, reason: '模板编辑对话框未打开');
    final dialog = find.byType(AlertDialog);
    expect(
      find.descendant(of: dialog, matching: find.text(l10n.ankiQuestion)),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: dialog, matching: find.text(l10n.commonCancel)),
    );
    await waitUntil(
      tester,
      () => !dialogVisible(),
      reason: '模板编辑对话框未关闭',
    );
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('在弹层里编辑正文，保存后弹层正文即时刷新', (tester) async {
    useTallView(tester);
    final (db, anki) = await openDatabase();
    final point = await anki.createKnowledgePoint(
      title: '待编辑卡',
      content: '旧内容',
    );
    await pumpManage(tester, db);
    final l10n = l10nOf(tester);

    await openDetail(tester, '待编辑卡', point.id);
    final sheet = sheetOf(point.id);
    await tester.tap(
      find.descendant(of: sheet, matching: find.text(l10n.commonEdit)),
    );
    await waitUntil(tester, dialogVisible, reason: '编辑对话框未打开');

    final dialog = find.byType(AlertDialog);
    final fields = find.descendant(
      of: dialog,
      matching: find.byType(TextField),
    );
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(1), '新的完整内容：叶绿体');
    await tester.tap(
      find.descendant(of: dialog, matching: find.text(l10n.commonSave)),
    );
    await waitUntil(
      tester,
      () => !dialogVisible(),
      reason: '编辑对话框未关闭',
    );
    await waitUntil(
      tester,
      () =>
          find.byKey(ankiKnowledgeContentKey).evaluate().isNotEmpty &&
          sheetContent(tester).data == '新的完整内容：叶绿体',
      reason: '弹层正文未刷新',
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(sheetContent(tester).data, '新的完整内容：叶绿体');
  });

  testWidgets('正文只有空白时弹层显示占位而不是空块', (tester) async {
    useTallView(tester);
    final (db, anki) = await openDatabase();
    final point = await anki.createKnowledgePoint(
      title: '空白卡',
      content: '   ',
    );
    await pumpManage(tester, db);

    await openDetail(tester, '空白卡', point.id);
    expect(sheetOf(point.id), findsOneWidget);
    expect(sheetContent(tester).data, '—');
  });

  testWidgets('旧标签/模板对话框仍可达：长按行与弹层「更多」', (tester) async {
    useTallView(tester);
    final (db, anki) = await openDatabase();
    final point = await anki.createKnowledgePoint(
      title: '可达卡',
      content: '内容',
    );
    await pumpManage(tester, db);
    final l10n = l10nOf(tester);

    await tester.longPress(find.text('可达卡'));
    await waitUntil(tester, dialogVisible, reason: '长按未打开标签/模板对话框');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(l10n.commonClose),
      ),
    );
    await waitUntil(tester, () => !dialogVisible(), reason: '对话框未关闭');

    await openDetail(tester, '可达卡', point.id);
    await tester.tap(
      find.descendant(
        of: sheetOf(point.id),
        matching: find.text(l10n.knowledgeMoreActions),
      ),
    );
    await waitUntil(tester, dialogVisible, reason: '弹层「更多」未打开旧对话框');
    await waitUntil(
      tester,
      () => sheetOf(point.id).evaluate().isEmpty,
      reason: '详情弹层未关闭',
    );
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}

/// 材料入库页的测试（`docs/MINDNET_ROADMAP.md` §2-C ① 的界面入口）。
///
/// 钉的是这一页的唯一价值：**看到的就是会写的**。
///
///  - 贴信封 → 提案上屏（知识点 + 出处），连接如实标"先不动"；
///  - 勾选 → 确认之后知识点真的进 `knowledge_points`，同名的不重复建；
///  - 不合规的信封整份拒绝，且一行都不写（材料入库是"要么整批进、要么不进"）；
///  - 只有"问"的材料不算"没事做了一半"：明说没有要动的东西。
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/features/cognitive/application/material_intake_reader.dart';
import 'package:furnace/features/cognitive/presentation/material_intake_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// 三行材料：句（含词）+ 词（能造句）+ 问（不进图）。
Map<String, Object?> envelopeJson({
  String protocol = 'mindnet.material/1',
  String batchId = 'b-page',
  List<Map<String, Object?>>? items,
}) =>
    <String, Object?>{
      'protocol': protocol,
      'batch_id': batchId,
      'source': <String, Object?>{
        'kind': 'book',
        'refs': <String>['词汇书 p12'],
        'material': '词汇书',
      },
      'topic': 'travel',
      'language': 'en',
      'items': items ??
          <Map<String, Object?>>[
            <String, Object?>{
              'id': 'm1',
              'mark': '句',
              'text': 'I relied on him.',
              'page': 12,
              'line': 3,
              'contains': <String>['m2'],
              'margin_note': '整句要能说出来',
            },
            <String, Object?>{
              'id': 'm2',
              'mark': '词',
              'text': 'rely on',
              'page': 12,
              'line': 3,
              'context': 'I relied on him.',
              'meaning': '依靠',
              'meaning_source': 'user',
              'margin_note': '搭配',
              'produce': true,
            },
            <String, Object?>{
              'id': 'm3',
              'mark': '问',
              'text': 'rely on 和 depend on 的区别？',
              'page': 12,
              'line': 4,
              'margin_note': '先别建点',
            },
          ],
    };

List<Map<String, Object?>> questionOnly() => <Map<String, Object?>>[
      <String, Object?>{
        'id': 'm3',
        'mark': '问',
        'text': 'rely on 和 depend on 的区别？',
        'page': 12,
        'line': 4,
        'margin_note': '先别建点',
      },
    ];

void main() {
  /// 提案列表是 `ListView`（懒构建）：屏幕太小的话后面的卡片根本不会 build，
  /// `find.text` 自然找不到。测试给一块足够高的画布（真实手机上用户会滚动）。
  void bigSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('decodeMaterialEnvelope', () {
    test('对象与 JSON 文本等价', () {
      final fromMap = decodeMaterialEnvelope(envelopeJson());
      final fromText = decodeMaterialEnvelope(jsonEncode(envelopeJson()));
      expect(fromText.batchId, fromMap.batchId);
      expect(fromText.items.length, 3);
    });

    test('不是 JSON 文本就说清楚', () {
      expect(
        () => decodeMaterialEnvelope('这不是 JSON'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('不是合法的 JSON 文本'),
          ),
        ),
      );
    });

    test('空字符串也是信封缺失', () {
      expect(
        () => decodeMaterialEnvelope('   '),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('信封是空的'),
          ),
        ),
      );
    });

    test('别的类型直接拒绝', () {
      expect(
        () => decodeMaterialEnvelope(42),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('必须是对象或 JSON 文本'),
          ),
        ),
      );
    });
  });

  group('MaterialIntakePage', () {
    late AppDatabase db;
    late AnkiRepository anki;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      anki = AnkiRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    Widget harness() => ProviderScope(
          overrides: <Override>[appDatabaseProvider.overrideWithValue(db)],
          child: const MaterialApp(
            locale: Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MaterialIntakePage(),
          ),
        );

    AppLocalizations l10nOf(WidgetTester tester) =>
        AppLocalizations.of(tester.element(find.byType(MaterialIntakePage)));

    Future<void> preview(WidgetTester tester, Map<String, Object?> json) async {
      await tester.enterText(find.byType(TextField), jsonEncode(json));
      await tester.pump();
      await tester.tap(find.text(l10nOf(tester).materialIntakePreview));
      await tester.pumpAndSettle();
    }

    Future<void> confirm(WidgetTester tester, int count) async {
      final button = find.text(l10nOf(tester).materialIntakeConfirm(count));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets('看提案 → 确认：知识点进库，连接先不动', (WidgetTester tester) async {
      bigSurface(tester);
      await tester.pumpWidget(harness());
      await preview(tester, envelopeJson());

      final l10n = l10nOf(tester);
      // 两条知识点提案（句、词）与它们的出处。
      expect(find.text('I relied on him.'), findsOneWidget);
      expect(find.text('rely on'), findsOneWidget);
      expect(find.textContaining('出处：词汇书'), findsWidgets);
      expect(
        find.textContaining(l10n.materialIntakeProposals(4)),
        findsOneWidget,
      );
      // 两条连接：如实标"先不动"，而且勾不动（没有落点）。
      expect(
        find.textContaining(l10n.materialIntakeConnectionDeferred),
        findsNWidgets(2),
      );
      final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
      expect(boxes.where((box) => box.onChanged == null).length, 2);

      await confirm(tester, 2);
      expect(find.textContaining('写入 2 个知识点'), findsOneWidget);

      final points = await anki.getKnowledgePoints();
      expect(
        points.map((point) => point.title),
        containsAll(<String>['I relied on him.', 'rely on']),
      );
    });

    testWidgets('同名知识点标"已存在"，确认时不重复建', (WidgetTester tester) async {
      bigSurface(tester);
      await anki.createKnowledgePoint(title: 'rely on', content: '早就有了');
      await tester.pumpWidget(harness());
      await preview(tester, envelopeJson());

      expect(
        find.textContaining(l10nOf(tester).materialIntakeExisting),
        findsOneWidget,
      );

      await confirm(tester, 2);
      expect(find.textContaining('写入 1 个知识点'), findsOneWidget);
      expect(find.textContaining('1 个已存在'), findsOneWidget);

      final points = await anki.getKnowledgePoints();
      expect(points.length, 2);
      expect(points.where((point) => point.title == 'rely on').length, 1);
    });

    testWidgets('不合规的信封整份拒绝，一行都不写', (WidgetTester tester) async {
      bigSurface(tester);
      await tester.pumpWidget(harness());
      await preview(tester, envelopeJson(protocol: 'mindnet.material/2'));

      expect(find.textContaining('整份拒绝'), findsOneWidget);
      expect(find.text(l10nOf(tester).materialIntakeConfirm(2)), findsNothing);
      expect(await anki.getKnowledgePoints(), isEmpty);
    });

    testWidgets('只有"问"的材料：明说没有要动的东西', (WidgetTester tester) async {
      bigSurface(tester);
      await tester.pumpWidget(harness());
      await preview(tester, envelopeJson(items: questionOnly()));

      expect(
        find.text(l10nOf(tester).materialIntakeNothingToDo),
        findsOneWidget,
      );
      expect(find.text(l10nOf(tester).materialIntakeConfirm(0)), findsNothing);
      expect(await anki.getKnowledgePoints(), isEmpty);
    });
  });
}

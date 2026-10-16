/// 材料入库页的测试（`docs/MINDNET_ROADMAP.md` §2-C ① 的界面入口）。
///
/// 钉的是这一页的唯一价值：**看到的就是会写的**。
///
///  - 贴信封 → 提案上屏（知识点 + 出处），连接标清它们是线索边（严格有向、ls 未标定）；
///  - 勾选 → 确认之后知识点真的进 `knowledge_points`、连接进 `knowledge_edges`，
///    同名的不重复建、缺端的不编边；
///  - 关掉页面之后，那批还没点头的提案还在"待确认清单"里，接着确认的就是当初那一份；
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
import 'package:furnace/data/repositories/material_intake_repository.dart';
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

    testWidgets('看提案 → 确认：知识点与线索边都进库', (WidgetTester tester) async {
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
      // 两条连接：标清它们是线索边（严格有向、ls 未标定），而且**可以勾**。
      expect(
        find.textContaining(l10n.materialIntakeConnectionClue),
        findsNWidgets(2),
      );
      final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
      expect(boxes.where((box) => box.onChanged == null), isEmpty);

      await confirm(tester, 4);
      expect(find.textContaining('写入 4 条'), findsOneWidget);

      final points = await anki.getKnowledgePoints();
      expect(
        points.map((point) => point.title),
        containsAll(<String>['I relied on him.', 'rely on']),
      );
      final edges = await db.select(db.knowledgeEdges).get();
      expect(edges, hasLength(2));
      expect(edges.map((edge) => edge.origin), everyElement(isNotNull));
      expect(edges.map((edge) => edge.lsCalibrated), everyElement(isFalse));
    });

    testWidgets('从待确认清单恢复：接着确认的就是当初那一份', (WidgetTester tester) async {
      bigSurface(tester);
      // 先"看过一次提案"（登记成待确认），然后像关掉页面一样把它丢下。
      final repository = MaterialIntakeRepository(db);
      final moment = DateTime(2026, 10, 16, 12);
      final draft = await readMaterialPlan(
        repository: repository,
        raw: envelopeJson(),
        moment: moment,
      );
      await recordMaterialPlan(
        repository: repository,
        draft: draft,
        moment: moment,
      );

      // 重新打开页面：那批还没点头的还在清单里等着（关掉页面不会丢）。
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
      final l10n = l10nOf(tester);
      expect(find.text(l10n.materialIntakePendingTitle(1)), findsOneWidget);
      expect(find.textContaining('b-page'), findsWidgets);
      expect(find.text(l10n.materialIntakeRestore), findsOneWidget);
      // 还没恢复：提案没上屏。
      expect(find.text('I relied on him.'), findsNothing);
      expect(await anki.getKnowledgePoints(), isEmpty);

      await tester.tap(find.text(l10n.materialIntakeRestore));
      await tester.pumpAndSettle();

      // 恢复出来的是当初那四条：两条知识点 + 两条线索边（不重算，直接读库）。
      expect(find.text('I relied on him.'), findsOneWidget);
      expect(find.text('rely on'), findsWidgets);
      expect(
        find.textContaining(l10n.materialIntakeConnectionClue),
        findsNWidgets(2),
      );

      await confirm(tester, 4);
      expect(find.textContaining('写入 4 条'), findsOneWidget);

      final points = await anki.getKnowledgePoints();
      expect(
        points.map((point) => point.title),
        containsAll(<String>['I relied on him.', 'rely on']),
      );
      expect(await db.select(db.knowledgeEdges).get(), hasLength(2));
      // 欠账还清了，清单就不再出现。
      expect(find.text(l10n.materialIntakePendingTitle(1)), findsNothing);
      expect(find.text(l10n.materialIntakeRestore), findsNothing);
    });

    testWidgets('确认一部分之后，清单里剩下的接着等着', (WidgetTester tester) async {
      bigSurface(tester);
      await tester.pumpWidget(harness());
      await preview(tester, envelopeJson());

      // 把"句"那条知识点取消勾选，剩下三条（另一条知识点 + 两条连接）确认。
      // 两条连接都指向没被建出来的那条知识点，所以它们如实报"落不了"；
      // 取消勾选的那一条留在待办里 —— 这一批因此还在清单上。
      // 注意第 0 个 `Checkbox` 是"顺便建主题分组"那个开关，提案从第 1 个开始。
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pumpAndSettle();

      await confirm(tester, 3);
      // 落不了的两条连接**也算没确认**（`deferred` 不标 `applied_at`），
      // 所以"还剩"是 1（没勾的那条知识点）+ 2（两条连接）= 3，与清单读数一致。
      expect(find.textContaining('写入 1 条'), findsOneWidget);
      expect(find.textContaining('2 条连接落不了'), findsOneWidget);
      expect(find.textContaining('还剩 3 条待确认'), findsOneWidget);
      expect(find.textContaining('已登记为待确认（3 条）'), findsOneWidget);
      expect(
        find.text(l10nOf(tester).materialIntakePendingTitle(1)),
        findsOneWidget,
        reason: '还剩 3 条没确认，这一批应当留在待确认清单里',
      );
      // 还有欠账的批次不许同时挂到"已经确认完的"那张单子上。
      expect(
        find.text(l10nOf(tester).materialIntakeDoneTitle(1)),
        findsNothing,
        reason: '这一批还有 3 条没落地，不能说它确认完了',
      );
    });

    testWidgets('确认完之后，这批从"待确认"挪到"已经确认完的"', (WidgetTester tester) async {
      bigSurface(tester);
      await tester.pumpWidget(harness());
      await preview(tester, envelopeJson());
      await confirm(tester, 4);

      final l10n = l10nOf(tester);
      expect(find.textContaining('写入 4 条'), findsOneWidget);
      // 欠账还清：待确认那张单子上不再有它，历史那张单子上出现它。
      expect(find.text(l10n.materialIntakePendingTitle(1)), findsNothing);
      expect(find.text(l10n.materialIntakeDoneTitle(1)), findsOneWidget);
      expect(
          find.text(l10n.materialIntakeDoneBatch(4, 'b-page')), findsOneWidget);

      // 点开看：当初确认的四条都在（两条知识点 + 两条线索边），只读。
      await tester.tap(find.text(l10n.materialIntakeDoneOpen));
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.materialIntakeDoneDialogTitle('b-page')),
        findsOneWidget,
      );
      expect(find.text(l10n.materialIntakeDoneNote), findsOneWidget);
      expect(find.textContaining(l10n.materialIntakeKindPoint), findsWidgets);
      expect(
        find.textContaining(l10n.materialIntakeKindConnection),
        findsWidgets,
      );
      // 历史里没有勾选框：这些都是已经写下去的东西（页面背后那批提案还在，别数它们）。
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(Checkbox),
        ),
        findsNothing,
      );
    });

    testWidgets('历史里说清哪几条是"本来就有的"', (WidgetTester tester) async {
      bigSurface(tester);
      // 带 external_id 的老点：升级/重贴同一份材料时它就是"本来就有的"。
      await anki.createKnowledgePoint(
        title: 'rely on（先有的）',
        content: '早就有了',
        externalId: 'en::w::rely-on',
      );
      await tester.pumpWidget(harness());
      await preview(tester, envelopeJson());
      await confirm(tester, 4);

      final l10n = l10nOf(tester);
      // 一条老的 + 这次新建的一条点与两条边 ⇒ 全落地，整批挪进历史。
      expect(find.textContaining('写入 3 条'), findsOneWidget);
      expect(find.textContaining('1 条已存在'), findsOneWidget);
      expect(find.text(l10n.materialIntakeDoneTitle(1)), findsOneWidget);

      await tester.tap(find.text(l10n.materialIntakeDoneOpen));
      await tester.pumpAndSettle();
      // 那一条被标出来："已存在，不重复建"；其余是这次才写下去的。
      // 只数那一条提案的副标题 —— 页面背后那批提案也带着同一个标记，
      // 而对话框末尾的说明里也会提到这几个字。
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining(
              '${l10n.materialIntakeKindPoint} · ${l10n.materialIntakeExisting}'),
        ),
        findsOneWidget,
        reason: '成绩单只活在那一次调用里，这句历史随提案落库了',
      );
      expect(find.text(l10n.materialIntakeDoneNote), findsOneWidget);
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

      await confirm(tester, 4);
      expect(find.textContaining('写入 1 条'), findsOneWidget);
      expect(find.textContaining('1 条已存在'), findsOneWidget);
      expect(find.textContaining('2 条连接落不了'), findsOneWidget);

      final points = await anki.getKnowledgePoints();
      expect(points.length, 2);
      expect(points.where((point) => point.title == 'rely on').length, 1);
      // 那条老行没有 `external_id`，所以两条边都落不了：如实报 deferred，不编边。
      expect(await db.select(db.knowledgeEdges).get(), isEmpty);
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
    test('两张单子按库里现在的数分：没点头的在待确认，点头了的进历史', () async {
      final repository = MaterialIntakeRepository(db);
      final moment = DateTime(2026, 10, 16, 12);

      // 没有这批。
      expect(
        await readPendingBatch(repository: repository, batchId: '没有这批'),
        isNull,
      );
      expect(await readPendingBatches(repository: repository), isEmpty);
      expect(await readAppliedBatches(repository: repository), isEmpty);
      expect(
        await readAppliedBatch(repository: repository, batchId: '没有这批'),
        isNull,
      );

      // 登记成待确认（一个都没点头）：只在待确认那张单子上。
      final draft = await readMaterialPlan(
        repository: repository,
        raw: envelopeJson(),
        moment: moment,
      );
      await recordMaterialPlan(
        repository: repository,
        draft: draft,
        moment: moment,
      );
      final pending = await readPendingBatches(repository: repository);
      expect(pending, hasLength(1));
      expect(pending.single.unappliedCount, 4);
      expect(pending.single.appliedCount, 0);
      expect(await readAppliedBatches(repository: repository), isEmpty);

      // 全部点头：挪到历史，而且历史里读得到的正是**已经写下去**的那四条。
      await repository.apply(batchId: 'b-page', appliedAt: moment);
      expect(await readPendingBatches(repository: repository), isEmpty);
      final done = await readAppliedBatches(repository: repository);
      expect(done, hasLength(1));
      expect(done.single.appliedCount, 4);
      expect(done.single.unappliedCount, 0);
      final applied = await readAppliedBatch(
        repository: repository,
        batchId: 'b-page',
      );
      expect(applied, isNotNull);
      expect(applied!.proposals, hasLength(4));
      expect(
        applied.proposals.map((applied) => applied.proposal.title),
        containsAll(<String>['I relied on him.', 'rely on']),
      );
      // 全新建（库里本来没有）：成绩单上那句"这次新建的"随提案一起落库。
      expect(
        applied.proposals.where((applied) => applied.alreadyExisted),
        isEmpty,
      );
    });
  });
}

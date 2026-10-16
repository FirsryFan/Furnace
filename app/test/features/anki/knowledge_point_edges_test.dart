/// 知识点详情里那一段线索边的测试
/// （`app/lib/features/anki/presentation/knowledge_point_edges.dart`）。
///
/// 钉的是这一段的分寸：**不同的"没有"要说不同的话**。
///
///  - 这个点没有 `external_id`（手写的知识点，从没进过图）⇒ 说"它不在图里"，
///    不说"它没有边"——后者听起来像"查过了，确实没有"；
///  - 进了图但库里没有边 ⇒ 说"还没有线索边（确认之后才会有）"；
///  - 出边和入边都站在这个点的角度说方向（它指向谁 / 谁指向它），并带关系名；
///  - 手写一条边（`origin: 'manual'`）从这一段就能做，方向可选；同一个方向已有边就
///    如实说"已经有一条了（谁写的）"，不重复加；
///  - 删除只给手写边：材料边那一行没有删除按钮；
///  - 端点可点时才可点：给了 [KnowledgeEdgeEndpointRef] 回调就能顺着走到另一端，
///    没给就只是文本（不假装能跳）。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/features/anki/presentation/knowledge_edge_page.dart';
import 'package:furnace/features/anki/presentation/knowledge_point_edges.dart';
import 'package:furnace/l10n/app_localizations.dart';

void main() {
  late AppDatabase db;
  late AnkiRepository anki;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    anki = AnkiRepository(db);
  });

  tearDown(() => db.close());

  Widget harness({
    required String? externalId,
    ValueChanged<KnowledgeEdgeEndpointRef>? onOpenPoint,
  }) =>
      ProviderScope(
        overrides: <Override>[appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: KnowledgePointEdgesSection(
              externalId: externalId,
              onOpenPoint: onOpenPoint,
            ),
          ),
        ),
      );

  Future<void> addPoint(String title, String externalId) => anki
      .createKnowledgePoint(
        title: title,
        content: title,
        externalId: externalId,
      )
      .then((_) {});

  Future<void> addEdge({
    required String id,
    required String fromId,
    required String toId,
    String origin = 'produce',
    required int createdAt,
  }) async {
    await db.into(db.knowledgeEdges).insert(
          KnowledgeEdgesCompanion.insert(
            id: id,
            fromId: fromId,
            toId: toId,
            origin: origin,
            createdAt: createdAt,
            updatedAt: createdAt,
          ),
        );
  }

  testWidgets('没有 external_id：说它不在图里，不说它没有边', (tester) async {
    await tester.pumpWidget(harness(externalId: null));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(KnowledgePointEdgesSection)),
    );
    expect(find.text(l10n.knowledgePointEdgesNotInGraph), findsOneWidget);
    expect(find.text(l10n.knowledgePointEdgesEmpty), findsNothing);
  });

  testWidgets('在图里但一条边都没有：说还没有，并说清什么时候才有', (tester) async {
    await addPoint('rely on', 'en::w::rely-on');

    await tester.pumpWidget(harness(externalId: 'en::w::rely-on'));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(KnowledgePointEdgesSection)),
    );
    expect(find.text(l10n.knowledgePointEdgesEmpty), findsOneWidget);
    expect(find.text(l10n.knowledgePointEdgesNotInGraph), findsNothing);
  });

  testWidgets('出边和入边都算它自己的，方向和关系名都说出来', (tester) async {
    await addPoint('rely on', 'en::w::rely-on');
    await addPoint('I relied on him.', 'en::s::abc');
    await addPoint('depend on', 'en::w::depend-on');
    await addEdge(
      id: 'e_out',
      fromId: 'en::w::rely-on',
      toId: 'en::s::abc',
      createdAt: 1000,
    );
    await addEdge(
      id: 'e_in',
      fromId: 'en::w::depend-on',
      toId: 'en::w::rely-on',
      origin: 'contains',
      createdAt: 2000,
    );

    await tester.pumpWidget(harness(externalId: 'en::w::rely-on'));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(KnowledgePointEdgesSection)),
    );
    expect(
      find.text(l10n.knowledgePointEdgesOutgoing('I relied on him.')),
      findsOneWidget,
    );
    expect(
      find.text(l10n.knowledgePointEdgesIncoming('depend on')),
      findsOneWidget,
    );
    expect(find.text(l10n.knowledgeEdgesOriginProduce), findsOneWidget);
    expect(find.text(l10n.knowledgeEdgesOriginContains), findsOneWidget);
  });

  testWidgets('端点名字可点：给出的是"另一端"的 id 与显示名', (tester) async {
    await addPoint('rely on', 'en::w::rely-on');
    await addPoint('I relied on him.', 'en::s::abc');
    await addPoint('depend on', 'en::w::depend-on');
    await addEdge(
      id: 'e_out',
      fromId: 'en::w::rely-on',
      toId: 'en::s::abc',
      createdAt: 1000,
    );
    await addEdge(
      id: 'e_in',
      fromId: 'en::w::depend-on',
      toId: 'en::w::rely-on',
      origin: 'contains',
      createdAt: 2000,
    );

    final opened = <KnowledgeEdgeEndpointRef>[];
    await tester.pumpWidget(
      harness(externalId: 'en::w::rely-on', onOpenPoint: opened.add),
    );
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(KnowledgePointEdgesSection)),
    );
    // 出边那一行点下去给的是终点；入边那一行给的是起点 —— 都是"另一端"。
    await tester.tap(
      find.text(l10n.knowledgePointEdgesOutgoing('I relied on him.')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(l10n.knowledgePointEdgesIncoming('depend on')),
    );
    await tester.pumpAndSettle();

    expect(opened, [
      (externalId: 'en::s::abc', label: 'I relied on him.'),
      (externalId: 'en::w::depend-on', label: 'depend on'),
    ]);
  });

  testWidgets('没给回调时那句话只是文本：不假装能点', (tester) async {
    await addPoint('rely on', 'en::w::rely-on');
    await addPoint('I relied on him.', 'en::s::abc');
    await addEdge(
      id: 'e_out',
      fromId: 'en::w::rely-on',
      toId: 'en::s::abc',
      createdAt: 1000,
    );

    await tester.pumpWidget(harness(externalId: 'en::w::rely-on'));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(KnowledgePointEdgesSection)),
    );
    expect(
      find.text(l10n.knowledgePointEdgesOutgoing('I relied on him.')),
      findsOneWidget,
    );
    expect(find.byTooltip(l10n.knowledgeEdgeWalkTooltip), findsNothing);
  });

  Future<void> addManualEdge({
    required String fromId,
    required String toId,
    required String id,
  }) async {
    await db.into(db.knowledgeEdges).insert(
          KnowledgeEdgesCompanion.insert(
            id: id,
            fromId: fromId,
            toId: toId,
            origin: 'manual',
            createdAt: 3000,
            updatedAt: 3000,
          ),
        );
  }

  /// 打开"加一条线索边"，选另一端与方向，然后确认。
  Future<void> addEdgeThroughUi(
    WidgetTester tester,
    AppLocalizations l10n, {
    required String other,
    bool incoming = false,
  }) async {
    await tester.tap(find.text(l10n.knowledgeEdgeAdd));
    await tester.pumpAndSettle();
    if (incoming) {
      await tester.tap(find.text(l10n.knowledgeEdgeDirectionIncoming));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(other).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.commonConfirm));
    await tester.pumpAndSettle();
  }

  testWidgets('手写一条边：它指向 X —— 落库成 manual，界面也立刻看得见', (tester) async {
    await addPoint('rely on', 'en::w::rely-on');
    await addPoint('I relied on him.', 'en::s::abc');

    await tester.pumpWidget(harness(externalId: 'en::w::rely-on'));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(KnowledgePointEdgesSection)),
    );

    await addEdgeThroughUi(tester, l10n, other: 'I relied on him.');

    expect(find.text(l10n.knowledgeEdgeCreated), findsOneWidget);
    final row = await db.select(db.knowledgeEdges).getSingle();
    expect(row.id, 'manual:en::w::rely-on->en::s::abc');
    expect(row.origin, 'manual');
    expect(row.fromId, 'en::w::rely-on');
    expect(row.toId, 'en::s::abc');
    expect(row.ls, isNull);
    // 写完就重读：这一段现在显示这条边（手写边带删除按钮）。
    expect(
      find.text(l10n.knowledgePointEdgesOutgoing('I relied on him.')),
      findsOneWidget,
    );
    expect(
      find.byTooltip(l10n.knowledgeEdgeDeleteTooltip),
      findsOneWidget,
    );
  });

  testWidgets('手写一条边也可以反过来：X 指向它', (tester) async {
    await addPoint('rely on', 'en::w::rely-on');
    await addPoint('depend on', 'en::w::depend-on');

    await tester.pumpWidget(harness(externalId: 'en::w::rely-on'));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(KnowledgePointEdgesSection)),
    );

    await addEdgeThroughUi(
      tester,
      l10n,
      other: 'depend on',
      incoming: true,
    );

    final row = await db.select(db.knowledgeEdges).getSingle();
    expect(row.fromId, 'en::w::depend-on');
    expect(row.toId, 'en::w::rely-on');
    expect(
      find.text(l10n.knowledgePointEdgesIncoming('depend on')),
      findsOneWidget,
    );
  });

  testWidgets('这个方向已经有一条边：说清是谁写的，不重复加', (tester) async {
    await addPoint('rely on', 'en::w::rely-on');
    await addPoint('I relied on him.', 'en::s::abc');
    await addEdge(
      id: 'e_material',
      fromId: 'en::w::rely-on',
      toId: 'en::s::abc',
      createdAt: 1000,
    );

    await tester.pumpWidget(harness(externalId: 'en::w::rely-on'));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(KnowledgePointEdgesSection)),
    );

    await addEdgeThroughUi(tester, l10n, other: 'I relied on him.');

    expect(
      find.text(
        l10n.knowledgeEdgeAlreadyExists(l10n.knowledgeEdgesOriginProduce),
      ),
      findsOneWidget,
    );
    expect(await db.select(db.knowledgeEdges).get(), hasLength(1));
  });

  testWidgets('图里只有它自己：说没有可连的另一端，确认钮不可按', (tester) async {
    await addPoint('rely on', 'en::w::rely-on');

    await tester.pumpWidget(harness(externalId: 'en::w::rely-on'));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(KnowledgePointEdgesSection)),
    );

    await tester.tap(find.text(l10n.knowledgeEdgeAdd));
    await tester.pumpAndSettle();

    expect(find.text(l10n.knowledgeEdgeNoOtherPoints), findsOneWidget);
    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, l10n.commonConfirm),
    );
    expect(confirm.onPressed, isNull);
  });

  testWidgets('删除只给手写边：材料边那一行没有删除按钮', (tester) async {
    await addPoint('rely on', 'en::w::rely-on');
    await addPoint('I relied on him.', 'en::s::abc');
    await addEdge(
      id: 'e_material',
      fromId: 'en::w::rely-on',
      toId: 'en::s::abc',
      createdAt: 1000,
    );

    await tester.pumpWidget(harness(externalId: 'en::w::rely-on'));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(KnowledgePointEdgesSection)),
    );

    expect(find.byTooltip(l10n.knowledgeEdgeDeleteTooltip), findsNothing);
  });

  testWidgets('手写边删得掉：先问一次，再真的删', (tester) async {
    await addPoint('rely on', 'en::w::rely-on');
    await addPoint('I relied on him.', 'en::s::abc');
    await addManualEdge(
      id: 'manual:en::w::rely-on->en::s::abc',
      fromId: 'en::w::rely-on',
      toId: 'en::s::abc',
    );

    await tester.pumpWidget(harness(externalId: 'en::w::rely-on'));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(KnowledgePointEdgesSection)),
    );

    await tester.tap(find.byTooltip(l10n.knowledgeEdgeDeleteTooltip));
    await tester.pumpAndSettle();
    expect(find.text(l10n.knowledgeEdgeDeleteConfirm), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, l10n.commonDelete));
    await tester.pumpAndSettle();

    expect(find.text(l10n.knowledgeEdgeDeleted), findsOneWidget);
    expect(await db.select(db.knowledgeEdges).get(), isEmpty);
    expect(find.text(l10n.knowledgePointEdgesEmpty), findsOneWidget);
  });
}

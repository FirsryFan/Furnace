/// 线索边清单页的测试（`knowledge_edges` 的第一个读者）。
///
/// 钉的是这一页的诚实：库里有什么就说什么。
///
///  - 空库明说"还没有线索边"，而不是摆一个空列表；
///  - 两端都有名字时显示 `A → B`，并带上关系、出处、`ls …（未标定）`；
///  - 有一端不在库里就按 id 显示并说明原因（不编名字）；
///  - 材料没给 `ls` 时说"没给"，不显示 0 也不显示"未标定"的假权重；
///  - 端点名字可点：顺着这条线走到那一端，看它自己的边（一层层翻，只读）。
library;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/features/anki/presentation/knowledge_edge_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

void main() {
  late AppDatabase db;
  late AnkiRepository anki;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    anki = AnkiRepository(db);
  });

  tearDown(() => db.close());

  Widget harness() => ProviderScope(
        overrides: <Override>[appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: KnowledgeEdgePage(),
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
    double? ls,
    String? source,
  }) async {
    await db.into(db.knowledgeEdges).insert(
          KnowledgeEdgesCompanion.insert(
            id: id,
            fromId: fromId,
            toId: toId,
            origin: origin,
            ls: Value(ls),
            source: Value(source),
            createdAt: 1000,
            updatedAt: 1000,
          ),
        );
  }

  testWidgets('没有边就明说，不摆一个空列表', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(KnowledgeEdgePage)),
    );
    expect(find.text(l10n.knowledgeEdgesEmpty), findsOneWidget);
    expect(find.textContaining('条线索边'), findsNothing);
  });

  testWidgets('一条边：两端名字、关系、出处、未标定的 ls 都在', (tester) async {
    await addPoint('I relied on him.', 'en::s::abc');
    await addPoint('rely on', 'en::w::rely-on');
    await addEdge(
      id: 'e_1',
      fromId: 'en::w::rely-on',
      toId: 'en::s::abc',
      origin: 'produce',
      ls: 0.6,
      source: '材料：词汇书（第 12 页）',
    );

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(KnowledgeEdgePage)),
    );
    expect(find.text('rely on'), findsOneWidget);
    expect(find.text('I relied on him.'), findsOneWidget);
    expect(find.text(l10n.knowledgeEdgesCount(1)), findsOneWidget);
    expect(
      find.text(
        '${l10n.knowledgeEdgesOriginProduce} · 材料：词汇书（第 12 页） · '
        '${l10n.knowledgeEdgesLs('0.60')}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('点端点顺着走：A → B → C，一层层翻（只读）', (tester) async {
    await addPoint('A', 'n::a');
    await addPoint('B', 'n::b');
    await addPoint('C', 'n::c');
    await addEdge(id: 'e_ab', fromId: 'n::a', toId: 'n::b');
    await addEdge(id: 'e_bc', fromId: 'n::b', toId: 'n::c');

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(KnowledgeEdgePage)),
    );
    // 清单页第一行是 A → B：点 A，就看 A 自己的边（只读，且能继续走）。
    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.knowledgeEdgeWalkTitle('A')), findsOneWidget);
    expect(find.text(l10n.knowledgeEdgeWalkHint), findsOneWidget);
    expect(
      find.text(l10n.knowledgePointEdgesOutgoing('B')),
      findsOneWidget,
    );

    // 再点 B：展开 B 的边 —— 出边到 C，入边来自 A（方向站在 B 的角度说）。
    await tester.tap(find.text(l10n.knowledgePointEdgesOutgoing('B')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.knowledgeEdgeWalkTitle('B')), findsOneWidget);
    expect(
      find.text(l10n.knowledgePointEdgesOutgoing('C')),
      findsOneWidget,
    );
    expect(
      find.text(l10n.knowledgePointEdgesIncoming('A')),
      findsOneWidget,
    );
  });

  testWidgets('缺一端：按 id 显示并说明，不编名字', (tester) async {
    await addPoint('rely on', 'en::w::rely-on');
    await addEdge(id: 'e_2', fromId: 'en::w::rely-on', toId: 'en::s::abc');

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(KnowledgeEdgePage)),
    );
    expect(find.text('rely on'), findsOneWidget);
    expect(find.text('en::s::abc'), findsOneWidget);
    expect(find.textContaining(l10n.knowledgeEdgesMissingEnd), findsOneWidget);
  });

  testWidgets('材料没给 ls：说没给，不显示 0 也不标未标定', (tester) async {
    await addPoint('rely on', 'en::w::rely-on');
    await addPoint('I relied on him.', 'en::s::abc');
    await addEdge(id: 'e_3', fromId: 'en::w::rely-on', toId: 'en::s::abc');

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(KnowledgeEdgePage)),
    );
    expect(find.text('rely on'), findsOneWidget);
    expect(find.text('I relied on him.'), findsOneWidget);
    expect(find.textContaining(l10n.knowledgeEdgesNoLs), findsOneWidget);
    expect(find.textContaining('ls 0.00'), findsNothing);
  });
}

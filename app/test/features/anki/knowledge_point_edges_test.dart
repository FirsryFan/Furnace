/// 知识点详情里那一段线索边的测试
/// （`app/lib/features/anki/presentation/knowledge_point_edges.dart`）。
///
/// 钉的是这一段的分寸：**不同的"没有"要说不同的话**。
///
///  - 这个点没有 `external_id`（手写的知识点，从没进过图）⇒ 说"它不在图里"，
///    不说"它没有边"——后者听起来像"查过了，确实没有"；
///  - 进了图但库里没有边 ⇒ 说"还没有线索边（确认之后才会有）"；
///  - 出边和入边都站在这个点的角度说方向（它指向谁 / 谁指向它），并带关系名。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
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

  Widget harness({required String? externalId}) => ProviderScope(
        overrides: <Override>[appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: KnowledgePointEdgesSection(externalId: externalId),
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
}

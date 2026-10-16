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
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/material_intake_repository.dart';
import 'package:furnace/domain/services/cognitive/cognitive_model.dart';
import 'package:furnace/domain/services/ingest/material_ingest.dart';
import 'package:furnace/domain/services/ingest/material_intake_plan.dart';
import 'package:furnace/domain/services/ingest/run_executor.dart';
import 'package:furnace/features/cognitive/application/material_intake_reader.dart';
import 'package:furnace/features/cognitive/application/run_intake.dart';
import 'package:furnace/features/cognitive/application/run_rehearsal.dart';
import 'package:furnace/features/ai/application/ai_providers.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart';
import 'package:furnace/features/ai/domain/vision_payload.dart';
import 'package:furnace/features/ai/infrastructure/fake_model_adapter.dart';
import 'package:furnace/features/cognitive/presentation/material_intake_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// 只报尺寸、不真的解码的编码器：widget 测试的假时钟走不完 `dart:ui` 的解码
/// （真编码在 `photo_transcribe_service_test.dart` 里验）。
class _FakeEncoder implements VisionImageEncoder {
  const _FakeEncoder();

  @override
  int get longSide => VisionImageEncoder.defaultLongSide;

  @override
  int get maxBytes => VisionImageEncoder.defaultMaxBytes;

  @override
  Future<VisionImageResult> encode(Uint8List raw) async =>
      VisionImageReady(bytes: raw, width: 24, height: 12);
}

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

/// 一份合法的 `mindnet.run/1`（那条 review 指着图里已有的 `kp`）。
Map<String, Object?> runJson() => <String, Object?>{
      'protocol': 'mindnet.run/1',
      'run_id': 'run-1',
      'time': const <String, Object?>{'model_hours': 480},
      'actions': <Object?>[
        <String, Object?>{
          'kind': 'review',
          'at': const <String, Object?>{'model_hours': 480},
          'evidence': const <String, Object?>{
            'source': 'page-1.jpg',
            'region': '第 3 题',
            'quote': 'x = 2',
          },
          'confidence': 0.8,
          'node': 'kp',
          'outcome': 'correct',
        },
      ],
    };

/// 一份演练读数：两个节点 + 一条边（就是"交给人确认"要落成提案的那三样）。
///
/// [stoppedAt] 给了就是"没跑完"的一跑（那一跑的整份都不算）。
RunRehearsal rehearsalOf({int? stoppedAt}) => RunRehearsal(
      report: RunExecutionReport(
        runId: 'run-1',
        traces: <RunActionTrace>[
          for (final node in <List<String>>[
            <String>['en::w::a', 'alpha'],
            <String>['en::w::b', 'beta'],
          ])
            RunActionTrace(
              index: 0,
              kind: 'knowledge',
              mechanism: 'graph.add_node',
              summary: '新增节点 ${node[0]}',
              delta: <String, Object?>{
                'added': 'node',
                'node': <String, Object?>{
                  'id': node[0],
                  'name': node[1],
                  'type': 'word',
                },
              },
            ),
          const RunActionTrace(
            index: 2,
            kind: 'knowledge',
            mechanism: 'graph.add_edge',
            summary: '新增边 en::w::a → en::w::b',
            delta: <String, Object?>{
              'added': 'edge',
              'edge': <String, Object?>{
                'id': 'e_3_a__b',
                'from': 'en::w::a',
                'to': 'en::w::b',
                'ls': 0.8,
              },
            },
          ),
        ],
        assumptions: const <String>[],
        hoursBefore: 0,
        hoursAfter: 0,
        stoppedAt: stoppedAt,
      ),
      seedNodeIds: const <String>[],
      seedEdgeIds: const <String>[],
      nodesWithoutMs: const <String>[],
      unknownNodeIds: const <String>[],
    );

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

    Widget harness({List<Override> overrides = const <Override>[]}) =>
        ProviderScope(
          overrides: <Override>[
            appDatabaseProvider.overrideWithValue(db),
            ...overrides,
          ],
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

      // 四条都勾着的时候两条边都落得了：谁也不喊缺（还没点头就先说清不是白说）。
      expect(
        find.byIcon(Icons.link_off),
        findsNothing,
        reason: '两端都在这一批里，现在没有落不了的边',
      );

      // 把"句"那条知识点取消勾选，剩下三条（另一条知识点 + 两条连接）确认。
      // 两条连接都指向没被建出来的那条知识点，所以它们如实报"落不了"；
      // 取消勾选的那一条留在待办里 —— 这一批因此还在清单上。
      // 注意第 0 个 `Checkbox` 是"顺便建主题分组"那个开关，提案从第 1 个开始。
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pumpAndSettle();

      // 勾一去掉，两条边当场说"落不了"：不用等确认完才在成绩单上看到（轮次八十）。
      expect(find.byIcon(Icons.link_off), findsNWidgets(2));

      await confirm(tester, 3);
      // 落不了的两条连接**也算没确认**（`deferred` 不标 `applied_at`），
      // 所以"还剩"是 1（没勾的那条知识点）+ 2（两条连接）= 3，与清单读数一致。
      expect(find.textContaining('写入 1 条'), findsOneWidget);
      expect(find.textContaining('2 条连接落不了'), findsOneWidget);
      expect(find.textContaining('还剩 3 条待确认'), findsOneWidget);
      expect(find.textContaining('已登记为待确认（3 条）'), findsOneWidget);
      // 确认之后那两句话还在（而且现在它们说的事已经写在成绩单上了）。
      expect(find.byIcon(Icons.link_off), findsNWidgets(2));
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

    testWidgets('缺的那一端补进图里之后，这句话自己消失（它是现算的，不落库）', (
      WidgetTester tester,
    ) async {
      bigSurface(tester);
      await tester.pumpWidget(harness());
      await preview(tester, envelopeJson());

      // 先造出"缺一端"的局面：勾掉"句"，只确认另一条知识点 → 两条边落不了。
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pumpAndSettle();
      await confirm(tester, 3);
      expect(find.byIcon(Icons.link_off), findsNWidgets(2));

      // 把缺的那一端（"句"的 external_id）自己在库里建出来。
      final repository = MaterialIntakeRepository(db);
      final proposals = await repository.proposals('b-page');
      final sentence = proposals.firstWhere(
        (proposal) =>
            proposal.kind == MaterialIntakeKind.knowledgePoint &&
            proposal.title == 'I relied on him.',
      );
      await anki.createKnowledgePoint(
        title: 'I relied on him.',
        content: '整句要能说出来',
        externalId: sentence.nodeId,
      );

      // 再恢复一次这一批：那句话不该还在（它算的是"库里现在缺不缺"）。
      await tester.tap(find.text(l10nOf(tester).materialIntakeRestore));
      await tester.pumpAndSettle();
      expect(
        find.byIcon(Icons.link_off),
        findsNothing,
        reason: '缺的那一端已经进图了，这时再说"落不了"就是瞎说',
      );

      // 而且真落得下去：再确认一次，两条边都写进去。
      await confirm(tester, 3);
      expect(find.textContaining('2 条连接落不了'), findsNothing);
      expect(find.textContaining('写入 2 条'), findsOneWidget);
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

    testWidgets('撤回这一批：删掉这次新建的，提案回到待确认', (WidgetTester tester) async {
      bigSurface(tester);
      await tester.pumpWidget(harness());
      await preview(tester, envelopeJson());
      await confirm(tester, 4);

      final l10n = l10nOf(tester);
      await tester.tap(find.text(l10n.materialIntakeDoneOpen));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.materialIntakeUndo));
      await tester.pumpAndSettle();
      // 删之前先问一句，并说清边界：本来就有的、卡片、标签、别的边都不动。
      expect(find.text(l10n.materialIntakeUndoTitle), findsOneWidget);
      expect(find.text(l10n.materialIntakeUndoBody), findsOneWidget);

      await tester.tap(find.text(l10n.materialIntakeUndoConfirm));
      await tester.pumpAndSettle();

      // 成绩单：删了两个知识点、两条线索边，四条提案退回待确认。
      expect(find.text(l10n.materialIntakeUndone(2, 2, 4)), findsOneWidget);
      expect(await anki.getKnowledgePoints(), isEmpty);
      expect(await db.select(db.knowledgeEdges).get(), isEmpty);
      // 这一批又回到"待确认"那张单子上，而且提案重新上屏。
      expect(find.text(l10n.materialIntakePendingTitle(1)), findsOneWidget);
      expect(find.text(l10n.materialIntakeDoneTitle(1)), findsNothing);
      expect(find.text('I relied on him.'), findsOneWidget);
      expect(find.text(l10n.materialIntakeConfirm(4)), findsOneWidget);
    });

    testWidgets('撤回这一批：撤不掉时一条也不删，理由照说', (WidgetTester tester) async {
      bigSurface(tester);
      await tester.pumpWidget(harness());
      await preview(tester, envelopeJson());
      await confirm(tester, 4);

      // 这条知识点已经长出卡片了：撤它就是连卡片一起删，所以整批不撤。
      final point = (await anki.getKnowledgePoints())
          .singleWhere((point) => point.title == 'I relied on him.');
      await anki.getOrCreateUnitCardState(point.id, 'essay:${point.id}');

      final l10n = l10nOf(tester);
      await tester.tap(find.text(l10n.materialIntakeDoneOpen));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.materialIntakeUndo));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.materialIntakeUndoConfirm));
      await tester.pumpAndSettle();

      expect(find.text(l10n.materialIntakeUndoBlockedTitle), findsOneWidget);
      expect(find.text(l10n.materialIntakeUndoBlockedNote), findsOneWidget);
      // 照原样摆出拦路理由（连"为什么拦"一起说），不是编一句"撤不了"。
      expect(find.textContaining('这个知识点下面已经有卡片了'), findsOneWidget);
      // 一个字没动：知识点、线索边、历史那张单子都还在原处。
      expect(await anki.getKnowledgePoints(), hasLength(2));
      expect(await db.select(db.knowledgeEdges).get(), hasLength(2));
      expect(find.text(l10n.materialIntakeDoneTitle(1)), findsOneWidget);
    });

    testWidgets('撤回流水：撤过之后，屏幕上说得清"这批被撤过几次"', (WidgetTester tester) async {
      bigSurface(tester);
      await tester.pumpWidget(harness());
      await preview(tester, envelopeJson());

      final l10n = l10nOf(tester);
      // 还没撤过：这句话不该出现。
      expect(find.text(l10n.materialIntakeUndoLogLine(1)), findsNothing);

      await confirm(tester, 4);
      expect(find.text(l10n.materialIntakeUndoLogLine(1)), findsNothing);

      await tester.tap(find.text(l10n.materialIntakeDoneOpen));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.materialIntakeUndo));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.materialIntakeUndoConfirm));
      await tester.pumpAndSettle();

      // 撤回把行删了，屏幕上只剩"又回到待确认"——这笔账由流水说，当场 +1。
      expect(find.text(l10n.materialIntakeUndoLogLine(1)), findsOneWidget);
      expect(await db.select(db.materialIntakeUndoLogs).get(), hasLength(1));

      // 点一下看得见那一次撤掉了什么（流水只读：删掉的行不会因为看得见就回来）。
      await tester.tap(find.text(l10n.materialIntakeUndoLogLine(1)));
      await tester.pumpAndSettle();
      // 只看对话框里那几条：屏幕上（对话框背后）也摆着同一份成绩单。
      final dialog = find.byType(AlertDialog);
      Finder inside(Finder matching) =>
          find.descendant(of: dialog, matching: matching);
      expect(
          inside(find.text(l10n.materialIntakeUndoLogTitle)), findsOneWidget);
      expect(
        inside(find.textContaining(' · ${l10n.materialIntakeUndoLogDone}')),
        findsOneWidget,
      );
      expect(inside(find.text(l10n.materialIntakeUndone(2, 2, 4))),
          findsOneWidget);
      expect(inside(find.text('· I relied on him.')), findsOneWidget);
      expect(inside(find.text('· rely on')), findsOneWidget);
      // 删掉的两条线索边按"从 → 到"摆出来。
      expect(inside(find.textContaining(' → ')), findsNWidgets(2));
      await tester.tap(find.text(l10n.commonClose));
      await tester.pumpAndSettle();
      // 看完还是"没确认"：流水不是回放。
      expect(find.text(l10n.materialIntakeConfirm(4)), findsOneWidget);

      // 把这批放下再"从清单恢复"回来：账跟着这一批（它落在库里，不看内存）。
      await tester.tap(find.text(l10n.materialIntakeClear));
      await tester.pumpAndSettle();
      expect(find.text(l10n.materialIntakeUndoLogLine(1)), findsNothing);

      await tester.tap(find.text(l10n.materialIntakeRestore));
      await tester.pumpAndSettle();
      expect(find.text(l10n.materialIntakeUndoLogLine(1)), findsOneWidget);
    });

    testWidgets('撤回流水：没撤成的那一次也留着，理由照说', (WidgetTester tester) async {
      bigSurface(tester);
      await tester.pumpWidget(harness());
      await preview(tester, envelopeJson());
      await confirm(tester, 4);

      // 这条知识点已经长出卡片了：这次撤回会被拦住（库里一个字不动）。
      final point = (await anki.getKnowledgePoints())
          .singleWhere((point) => point.title == 'I relied on him.');
      await anki.getOrCreateUnitCardState(point.id, 'essay:${point.id}');

      final l10n = l10nOf(tester);
      await tester.tap(find.text(l10n.materialIntakeDoneOpen));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.materialIntakeUndo));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.materialIntakeUndoConfirm));
      await tester.pumpAndSettle();
      expect(find.text(l10n.materialIntakeUndoBlockedTitle), findsOneWidget);
      await tester.tap(find.text(l10n.commonClose));
      await tester.pumpAndSettle();

      // "点过撤回"这件事留下了：`undone = false` + 第一条理由。
      final rows = await db.select(db.materialIntakeUndoLogs).get();
      expect(rows, hasLength(1));
      expect(rows.single.undone, isFalse);
      expect(rows.single.restoredCount, 0);
      expect(rows.single.blockedReason, contains('卡片'));

      // 卡片挪走之后再撤一次：这次撤成 —— 两次都在这批的流水里。
      await (db.delete(db.cardStates)).go();
      await (db.delete(db.cardTemplates)).go();
      await tester.tap(find.text(l10n.materialIntakeDoneOpen));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.materialIntakeUndo));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.materialIntakeUndoConfirm));
      await tester.pumpAndSettle();
      expect(find.text(l10n.materialIntakeUndoLogLine(2)), findsOneWidget);

      await tester.tap(find.text(l10n.materialIntakeUndoLogLine(2)));
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      Finder inside(Finder matching) =>
          find.descendant(of: dialog, matching: matching);
      expect(
          inside(find.text(l10n.materialIntakeUndoLogTitle)), findsOneWidget);
      // 没撤成那一次留下的是"为什么"（而且说清当时一共几条理由）。
      expect(
        inside(find.textContaining(' · ${l10n.materialIntakeUndoLogNotDone}')),
        findsOneWidget,
      );
      expect(
        inside(find.text(l10n.materialIntakeUndoLogBlocked(
          '这个知识点下面已经有卡片了，撤掉会连卡片一起删',
          1,
        ))),
        findsOneWidget,
      );
      // 撤成那一次留下的是"删了什么"。
      expect(
        inside(find.textContaining(' · ${l10n.materialIntakeUndoLogDone}')),
        findsOneWidget,
      );
      expect(
        inside(find.text(l10n.materialIntakeUndone(2, 2, 4))),
        findsOneWidget,
      );
      await tester.tap(find.text(l10n.commonClose));
      await tester.pumpAndSettle();
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

    testWidgets('选一张照片：读成请求、摆出自检结果、一个字都不写库', (WidgetTester tester) async {
      bigSurface(tester);
      // 图里已经有一个点：模型的清单与"已有的节点 id"都从库里现读。
      await anki.createKnowledgePoint(
        title: 'I relied on him.',
        content: '说过的一句话',
        externalId: 'kp',
      );
      final png = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final adapter = FakeModelAdapter(<List<ModelEvent>>[
        FakeModelAdapter.answer('好的：\n```json\n${jsonEncode(runJson())}\n```'),
      ]);
      await tester.pumpWidget(
        harness(
          overrides: <Override>[
            modelAdapterProvider.overrideWithValue(adapter),
            photoPickerProvider.overrideWithValue(() async => png),
            visionEncoderProvider.overrideWithValue(const _FakeEncoder()),
          ],
        ),
      );

      final l10n = l10nOf(tester);
      await tester.tap(find.text(l10n.materialIntakePickPhoto));
      await tester.pumpAndSettle();

      // 对话框：合不合法的自检 + 真正发出去的图（压过，不是原图）+ 模型原话。
      expect(find.text(l10n.materialPhotoReportTitle), findsOneWidget);
      expect(find.text(l10n.materialPhotoReportValid), findsOneWidget);
      expect(
        find.textContaining(l10n.materialPhotoReportSize(24, 12)),
        findsOneWidget,
      );
      expect(find.textContaining('run-1'), findsOneWidget);

      // 清单来自库：模型看到的 id 就是库里那个，图也跟着出去了。
      expect(adapter.requests, hasLength(1));
      final sent = adapter.requests.single.messages.single;
      expect(sent.images, hasLength(1));
      expect(sent.content, contains('kp → I relied on him.'));

      // 照片这条路只读：不执行请求，也不写库。
      expect(await db.select(db.knowledgeEdges).get(), isEmpty);
      expect(await db.select(db.materialIntakeProposals).get(), isEmpty);
    });

    testWidgets('照片报告里"试跑一遍"：真的跑进引擎，还是一个字节都不写库', (
      WidgetTester tester,
    ) async {
      bigSurface(tester);
      await anki.createKnowledgePoint(
        title: 'I relied on him.',
        content: '说过的一句话',
        externalId: 'kp',
      );
      final png = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final adapter = FakeModelAdapter(<List<ModelEvent>>[
        FakeModelAdapter.answer('好的：\n```json\n${jsonEncode(runJson())}\n```'),
      ]);
      MaterialRunRequest? rehearsed;
      await tester.pumpWidget(
        harness(
          overrides: <Override>[
            modelAdapterProvider.overrideWithValue(adapter),
            photoPickerProvider.overrideWithValue(() async => png),
            visionEncoderProvider.overrideWithValue(const _FakeEncoder()),
            // 用真的那种跑法（同一个库、同一个模型），只把"跑的是哪一份"记下来。
            runRehearsalRunnerProvider.overrideWithValue((
              MaterialRunRequest request,
            ) {
              rehearsed = request;
              return rehearseRun(
                request: request,
                db: db,
                model: const MindNetCognitiveModel(),
                now: DateTime(2026, 10, 17, 12),
              );
            }),
          ],
        ),
      );

      final l10n = l10nOf(tester);
      await tester.tap(find.text(l10n.materialIntakePickPhoto));
      await tester.pumpAndSettle();

      // 合法的那一份才摆这个按钮：按一下才知道引擎会走到哪一步。
      expect(find.text(l10n.materialPhotoReportRehearse), findsOneWidget);
      await tester.tap(find.text(l10n.materialPhotoReportRehearse));
      await tester.pumpAndSettle();

      expect(
        rehearsed?.runId,
        'run-1',
        reason: '试跑的就是刚才那份请求本身，不是把模型原话再解一遍',
      );
      expect(find.text(l10n.materialPhotoReportRehearseHeader), findsOneWidget);
      expect(find.textContaining('演练（只跑不落库'), findsOneWidget);
      expect(
        find.text(l10n.materialPhotoReportRehearseTrails),
        findsOneWidget,
        reason: '一条动作一行：引擎的原话摆出来，不是我在这里转述',
      );
      // `kp` 在库里没有卡片：模型读不出 r0，引擎按默认 0.8 算 —— 这件事要说出来。
      expect(
        find.textContaining(l10n.materialPhotoReportRehearseNoMs('kp')),
        findsOneWidget,
      );
      // 只读：演练真的跑了，库还是一个字节都没变。
      expect(await db.select(db.knowledgeEdges).get(), isEmpty);
      expect(await db.select(db.materialIntakeProposals).get(), isEmpty);
      expect(await db.select(db.knowledgePoints).get(), hasLength(1));
    });

    testWidgets('照片报告里"改一改再跑"：带着这份请求进可编辑的那张，跑的是改过的那份', (
      WidgetTester tester,
    ) async {
      bigSurface(tester);
      await anki.createKnowledgePoint(
        title: 'I relied on him.',
        content: '说过的一句话',
        externalId: 'kp',
      );
      final png = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final adapter = FakeModelAdapter(<List<ModelEvent>>[
        FakeModelAdapter.answer('好的：\n```json\n${jsonEncode(runJson())}\n```'),
      ]);
      MaterialRunRequest? rehearsed;
      await tester.pumpWidget(
        harness(
          overrides: <Override>[
            modelAdapterProvider.overrideWithValue(adapter),
            photoPickerProvider.overrideWithValue(() async => png),
            visionEncoderProvider.overrideWithValue(const _FakeEncoder()),
            runRehearsalRunnerProvider.overrideWithValue((
              MaterialRunRequest request,
            ) {
              rehearsed = request;
              return rehearseRun(
                request: request,
                db: db,
                model: const MindNetCognitiveModel(),
              );
            }),
          ],
        ),
      );

      final l10n = l10nOf(tester);
      await tester.tap(find.text(l10n.materialIntakePickPhoto));
      await tester.pumpAndSettle();

      // "改一改再跑"把照片那张关掉，换成可编辑的那张 —— 框里就是这一份请求。
      await tester.tap(find.text(l10n.materialPhotoReportEditAndRun));
      await tester.pumpAndSettle();

      expect(
        find.text(l10n.materialIntakeRunDialogTitleEdited),
        findsOneWidget,
      );
      final field = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      expect(field, findsOneWidget);
      expect(
          tester.widget<TextField>(field).controller!.text, contains('run-1'));
      // 一进来就校验过一遍：用户看见的是"现在这份"，不用先按一次再看见。
      expect(find.text(l10n.materialPhotoReportValid), findsOneWidget);

      // 改一处（换掉 run_id），校验，再试跑 —— 跑的是改过的那份。
      final edited = Map<String, Object?>.from(runJson())..['run_id'] = 'run-2';
      await tester.enterText(field, jsonEncode(edited));
      await tester.tap(find.text(l10n.materialIntakeRunCheck));
      await tester.pumpAndSettle();
      expect(find.text(l10n.materialPhotoReportValid), findsOneWidget);

      await tester.tap(find.text(l10n.materialPhotoReportRehearse));
      await tester.pumpAndSettle();

      expect(rehearsed, isNotNull);
      expect(rehearsed!.runId, 'run-2');
      expect(adapter.requests, hasLength(1), reason: '改请求不该再去读一遍照片');
      // 还是只读：库一个字节都没变。
      expect(await db.select(db.knowledgeEdges).get(), isEmpty);
      expect(await db.select(db.materialIntakeProposals).get(), isEmpty);
      expect(await db.select(db.knowledgePoints).get(), hasLength(1));
    });

    testWidgets('试跑炸了也不带走报告：说人话，自检结果还在，还能再按一次', (
      WidgetTester tester,
    ) async {
      bigSurface(tester);
      await anki.createKnowledgePoint(
        title: 'I relied on him.',
        content: '说过的一句话',
        externalId: 'kp',
      );
      final png = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final adapter = FakeModelAdapter(<List<ModelEvent>>[
        FakeModelAdapter.answer('好的：\n```json\n${jsonEncode(runJson())}\n```'),
      ]);
      await tester.pumpWidget(
        harness(
          overrides: <Override>[
            modelAdapterProvider.overrideWithValue(adapter),
            photoPickerProvider.overrideWithValue(() async => png),
            visionEncoderProvider.overrideWithValue(const _FakeEncoder()),
            runRehearsalRunnerProvider.overrideWithValue((
              MaterialRunRequest request,
            ) async {
              throw StateError('引擎没装好');
            }),
          ],
        ),
      );

      final l10n = l10nOf(tester);
      await tester.tap(find.text(l10n.materialIntakePickPhoto));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.materialPhotoReportRehearse));
      await tester.pumpAndSettle();

      expect(find.text(l10n.materialPhotoReportRehearseFailed), findsOneWidget);
      expect(find.textContaining('引擎没装好'), findsOneWidget);
      expect(
        find.text(l10n.materialPhotoReportValid),
        findsOneWidget,
        reason: '合不合法跟跑不跑得完是两件事：报告本身不许被带走',
      );
      expect(
        find.text(l10n.materialPhotoReportRehearse),
        findsOneWidget,
        reason: '还能再按一次',
      );
    });

    testWidgets('不合法的请求不摆"试跑一遍"：没得跑', (WidgetTester tester) async {
      bigSurface(tester);
      // 故意不建 `kp`：review 指着一个图里没有的点，整份判不合法。
      final png = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final adapter = FakeModelAdapter(<List<ModelEvent>>[
        FakeModelAdapter.answer('好的：\n```json\n${jsonEncode(runJson())}\n```'),
      ]);
      await tester.pumpWidget(
        harness(
          overrides: <Override>[
            modelAdapterProvider.overrideWithValue(adapter),
            photoPickerProvider.overrideWithValue(() async => png),
            visionEncoderProvider.overrideWithValue(const _FakeEncoder()),
            runRehearsalRunnerProvider.overrideWithValue((
              MaterialRunRequest request,
            ) async {
              fail('不合法的请求不该被拿去试跑');
            }),
          ],
        ),
      );

      final l10n = l10nOf(tester);
      await tester.tap(find.text(l10n.materialIntakePickPhoto));
      await tester.pumpAndSettle();

      expect(find.text(l10n.materialPhotoReportInvalid), findsOneWidget);
      expect(find.text(l10n.materialPhotoReportRehearse), findsNothing);
    });

    testWidgets('照片读不成请求（没配模型）：说人话，还是一个字都不写', (WidgetTester tester) async {
      bigSurface(tester);
      final png = Uint8List.fromList(<int>[9, 9, 9]);
      await tester.pumpWidget(
        harness(
          overrides: <Override>[
            modelAdapterProvider.overrideWithValue(null),
            photoPickerProvider.overrideWithValue(() async => png),
            visionEncoderProvider.overrideWithValue(const _FakeEncoder()),
          ],
        ),
      );

      final l10n = l10nOf(tester);
      await tester.tap(find.text(l10n.materialIntakePickPhoto));
      await tester.pumpAndSettle();

      expect(find.text(l10n.materialPhotoReportFailed), findsOneWidget);
      expect(find.textContaining('设置'), findsOneWidget, reason: '要告诉用户去哪儿配模型');
      expect(
        find.text(l10n.materialPhotoReportRetry),
        findsNothing,
        reason: '模型都没配好，按"重试"还是同一句话：不摆这个按钮',
      );
      expect(await db.select(db.knowledgeEdges).get(), isEmpty);
    });

    testWidgets('照片报告里"换一张"：不用先关掉对话框，原地再读一张', (
      WidgetTester tester,
    ) async {
      bigSurface(tester);
      // 请求里 `review` 指向的那个点得先在图里，不然整份会被判不合法。
      await anki.createKnowledgePoint(
        title: 'I relied on him.',
        content: '说过的一句话',
        externalId: 'kp',
      );
      final png = Uint8List.fromList(<int>[1, 2, 3, 4]);
      var picks = 0;
      final adapter = FakeModelAdapter(<List<ModelEvent>>[
        FakeModelAdapter.answer('第一张：\n```json\n${jsonEncode(runJson())}\n```'),
        FakeModelAdapter.answer('第二张：\n```json\n${jsonEncode(runJson())}\n```'),
      ]);
      await tester.pumpWidget(
        harness(
          overrides: <Override>[
            modelAdapterProvider.overrideWithValue(adapter),
            photoPickerProvider.overrideWithValue(() async {
              picks++;
              return png;
            }),
            visionEncoderProvider.overrideWithValue(const _FakeEncoder()),
          ],
        ),
      );

      final l10n = l10nOf(tester);
      await tester.tap(find.text(l10n.materialIntakePickPhoto));
      await tester.pumpAndSettle();
      expect(find.text(l10n.materialPhotoReportTitle), findsOneWidget);
      expect(picks, 1);

      await tester.tap(find.text(l10n.materialPhotoReportPickAnother));
      await tester.pumpAndSettle();

      expect(picks, 2, reason: '按一下就直接再选一张，不用退出去找那个按钮');
      expect(find.text(l10n.materialPhotoReportTitle), findsOneWidget);
      expect(find.text(l10n.materialPhotoReportValid), findsOneWidget);
      expect(adapter.requests, hasLength(2), reason: '第二张也真的发出去了');
      // 两次都只读：一个字都没写库。
      expect(await db.select(db.knowledgeEdges).get(), isEmpty);
      expect(await db.select(db.materialIntakeProposals).get(), isEmpty);
    });

    testWidgets('照片读不成（模型跑偏）：对话框里"重试"，第二次读成就算数', (
      WidgetTester tester,
    ) async {
      bigSurface(tester);
      await anki.createKnowledgePoint(
        title: 'I relied on him.',
        content: '说过的一句话',
        externalId: 'kp',
      );
      final png = Uint8List.fromList(<int>[9, 9, 9]);
      var picks = 0;
      final adapter = FakeModelAdapter(<List<ModelEvent>>[
        FakeModelAdapter.answer('这张照片我看不清。'),
        FakeModelAdapter.answer(
            '再看一眼：\n```json\n${jsonEncode(runJson())}\n```'),
      ]);
      await tester.pumpWidget(
        harness(
          overrides: <Override>[
            modelAdapterProvider.overrideWithValue(adapter),
            photoPickerProvider.overrideWithValue(() async {
              picks++;
              return png;
            }),
            visionEncoderProvider.overrideWithValue(const _FakeEncoder()),
          ],
        ),
      );

      final l10n = l10nOf(tester);
      await tester.tap(find.text(l10n.materialIntakePickPhoto));
      await tester.pumpAndSettle();
      expect(find.text(l10n.materialPhotoReportFailed), findsOneWidget);
      expect(picks, 1);

      await tester.tap(find.text(l10n.materialPhotoReportRetry));
      await tester.pumpAndSettle();

      expect(picks, 2);
      expect(
        find.text(l10n.materialPhotoReportValid),
        findsOneWidget,
        reason: '第二次读成了，摆的就是第二次的结果',
      );
      expect(find.text(l10n.materialPhotoReportFailed), findsNothing);
      expect(await db.select(db.materialIntakeProposals).get(), isEmpty);
    });

    testWidgets('贴一份 run/1：校验成、原地试跑，还是一个字节都不写库', (
      WidgetTester tester,
    ) async {
      bigSurface(tester);
      // 图里已经有一个点：贴进来的那份请求指着它，`reviewTranscribedRun` 才认得出。
      await anki.createKnowledgePoint(
        title: 'I relied on him.',
        content: '说过的一句话',
        externalId: 'kp',
      );
      MaterialRunRequest? rehearsed;
      await tester.pumpWidget(
        harness(
          overrides: <Override>[
            runRehearsalRunnerProvider.overrideWithValue((
              MaterialRunRequest request,
            ) {
              rehearsed = request;
              return rehearseRun(
                request: request,
                db: db,
                model: const MindNetCognitiveModel(),
                now: DateTime(2026, 10, 17, 12),
              );
            }),
          ],
        ),
      );

      final l10n = l10nOf(tester);
      await tester.tap(find.text(l10n.materialIntakePasteRun));
      await tester.pumpAndSettle();
      expect(find.text(l10n.materialIntakeRunDialogTitle), findsOneWidget);

      // 还没校验之前：没有结论、也没有试跑按钮（先看合不合法，再谈跑）。
      // 页面上还有一个贴信封的 `TextField`：只认对话框里那一个。
      final field = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(field, jsonEncode(runJson()));
      await tester.tap(find.text(l10n.materialIntakeRunCheck));
      await tester.pumpAndSettle();

      expect(find.text(l10n.materialPhotoReportValid), findsOneWidget);
      // 清单来自库：那份请求指着 `kp`，库里正好有它，于是"会做什么"摆得出来。
      expect(find.text(l10n.materialPhotoReportPreviews), findsOneWidget);

      await tester.tap(find.text(l10n.materialPhotoReportRehearse));
      await tester.pumpAndSettle();

      expect(
        rehearsed?.runId,
        'run-1',
        reason: '试跑的就是贴进来那一份请求本身，不是重新解一遍文本',
      );
      expect(find.text(l10n.materialPhotoReportRehearseHeader), findsOneWidget);
      expect(find.textContaining('演练（只跑不落库'), findsOneWidget);
      // 只读：真的跑进引擎了，库还是一个字节都没变。
      expect(await db.select(db.knowledgeEdges).get(), isEmpty);
      expect(await db.select(db.materialIntakeProposals).get(), isEmpty);
      expect(await db.select(db.knowledgePoints).get(), hasLength(1));
    });

    testWidgets('贴的东西读不成 run/1：说解码器那句人话，不给试跑按钮', (
      WidgetTester tester,
    ) async {
      bigSurface(tester);
      await tester.pumpWidget(harness());
      final l10n = l10nOf(tester);

      await tester.tap(find.text(l10n.materialIntakePasteRun));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        '这不是信封',
      );
      await tester.tap(find.text(l10n.materialIntakeRunCheck));
      await tester.pumpAndSettle();

      expect(find.textContaining('不是合法的 JSON 文本'), findsOneWidget);
      expect(find.text(l10n.materialPhotoReportValid), findsNothing);
      expect(
        find.text(l10n.materialPhotoReportRehearse),
        findsNothing,
        reason: '读都没读成，谈不上试跑',
      );
    });

    testWidgets('贴的 run/1 结构上不合法：硬错摆出来，也不给试跑按钮', (
      WidgetTester tester,
    ) async {
      bigSurface(tester);
      await tester.pumpWidget(harness());
      final l10n = l10nOf(tester);

      await tester.tap(find.text(l10n.materialIntakePasteRun));
      await tester.pumpAndSettle();

      // `unknown` 不是允许的动作种类：`decodeRunRequest` 会认出它、自检会判它不合法。
      final broken = runJson();
      broken['actions'] = <Object?>[
        <String, Object?>{
          'kind': 'unknown',
          'at': const <String, Object?>{'model_hours': 480},
        },
      ];
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        jsonEncode(broken),
      );
      await tester.tap(find.text(l10n.materialIntakeRunCheck));
      await tester.pumpAndSettle();

      expect(find.text(l10n.materialPhotoReportInvalid), findsOneWidget);
      expect(find.text(l10n.materialPhotoReportErrors), findsOneWidget);
      expect(
        find.text(l10n.materialPhotoReportRehearse),
        findsNothing,
        reason: '不合法的整份会被拒绝：先修它，别急着跑',
      );
    });

    testWidgets('试跑完按"交给人确认"：落成待确认清单，知识点一行都还没建', (
      WidgetTester tester,
    ) async {
      bigSurface(tester);
      // `runJson()` 里那条 review 指着 `kp`：库里得有它，整份才算合法。
      await anki.createKnowledgePoint(
        title: 'I relied on him.',
        content: '说过的一句话',
        externalId: 'kp',
      );
      await tester.pumpWidget(
        harness(
          overrides: <Override>[
            runRehearsalRunnerProvider.overrideWithValue((
              MaterialRunRequest request,
            ) async {
              return rehearsalOf();
            }),
            // 用真的那一层：同一个库、同一个 anki —— 钉的是"这一步到底写了哪几张表"。
            runIntakeRecorderProvider.overrideWithValue(
              (RunExecutionReport report) => recordRunKnowledge(
                report: report,
                db: db,
                anki: anki,
                now: DateTime(2026, 10, 17, 13),
                sourceRef: '贴进来的 run/1',
              ),
            ),
          ],
        ),
      );
      final l10n = l10nOf(tester);

      await tester.tap(find.text(l10n.materialIntakePasteRun));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        jsonEncode(runJson()),
      );
      await tester.tap(find.text(l10n.materialIntakeRunCheck));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.materialPhotoReportRehearse));
      await tester.pumpAndSettle();

      expect(find.text(l10n.materialPhotoReportHandOver), findsOneWidget);
      await tester.tap(find.text(l10n.materialPhotoReportHandOver));
      await tester.pumpAndSettle();

      expect(
        find.text(l10n.materialPhotoReportHandOverDone('run-1')),
        findsOneWidget,
        reason: '幂等键就是这一跑的 run_id',
      );

      final batches = await db.select(db.materialIntakeBatches).get();
      expect(batches, hasLength(1));
      expect(batches.single.sourceKind, 'run');
      final proposals = await db.select(db.materialIntakeProposals).get();
      expect(proposals, hasLength(3));
      expect(proposals.where((row) => row.kind == 'connection'), hasLength(1));

      // 这一步只写清单：线索边一行都没有，知识点还是测试自己建的那一个。
      expect(await db.select(db.knowledgePoints).get(), hasLength(1));
      expect(await db.select(db.knowledgeEdges).get(), isEmpty);

      // 再按一次：同一跑落的还是那一批，不翻倍。
      await tester.tap(find.text(l10n.materialPhotoReportHandOver));
      await tester.pumpAndSettle();
      expect(await db.select(db.materialIntakeBatches).get(), hasLength(1));
      expect(await db.select(db.materialIntakeProposals).get(), hasLength(3));
    });

    testWidgets('没跑完的一跑：交给人确认说人话，清单一行都不落', (
      WidgetTester tester,
    ) async {
      bigSurface(tester);
      await anki.createKnowledgePoint(
        title: 'I relied on him.',
        content: '说过的一句话',
        externalId: 'kp',
      );
      await tester.pumpWidget(
        harness(
          overrides: <Override>[
            runRehearsalRunnerProvider.overrideWithValue((
              MaterialRunRequest request,
            ) async {
              return rehearsalOf(stoppedAt: 2);
            }),
            runIntakeRecorderProvider.overrideWithValue(
              (RunExecutionReport report) => recordRunKnowledge(
                report: report,
                db: db,
                anki: anki,
              ),
            ),
          ],
        ),
      );
      final l10n = l10nOf(tester);

      await tester.tap(find.text(l10n.materialIntakePasteRun));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        jsonEncode(runJson()),
      );
      await tester.tap(find.text(l10n.materialIntakeRunCheck));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.materialPhotoReportRehearse));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.materialPhotoReportHandOver));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(l10n.materialPhotoReportHandOverFailed('')),
        findsOneWidget,
      );
      expect(find.textContaining('没跑完'), findsOneWidget);
      expect(await db.select(db.materialIntakeBatches).get(), isEmpty);
      expect(await db.select(db.materialIntakeProposals).get(), isEmpty);
    });
  });
}

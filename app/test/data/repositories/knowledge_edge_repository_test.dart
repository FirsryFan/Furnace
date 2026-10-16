/// 线索边读法的测试（`app/lib/data/repositories/knowledge_edge_repository.dart`）。
///
/// 钉的是这一层唯一的价值：**库里那行被翻译成什么样**。
///
///  - 两端的标题按 `knowledge_points.external_id` 解出来，新的边在前；
///  - 有一端不在库里就如实留空（界面按 id 显示），不替图编一个名字；
///  - `ls` 与 `ls_calibrated` 原样带出来 —— 读法不许把"未标定"洗掉，
///    也不许把"材料没给 ls"读成 0。
library;

// drift 也导出 `isNull`（那是 SQL 的），测试里要的是 matcher 的那个。
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/knowledge_edge_repository.dart';

void main() {
  late AppDatabase db;
  late AnkiRepository anki;
  late KnowledgeEdgeRepository edges;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    anki = AnkiRepository(db);
    edges = KnowledgeEdgeRepository(db);
  });

  tearDown(() => db.close());

  Future<void> addPoint({
    required String title,
    required String externalId,
  }) async {
    await anki.createKnowledgePoint(
      title: title,
      content: title,
      externalId: externalId,
    );
  }

  Future<void> addEdge({
    required String id,
    required String fromId,
    required String toId,
    required int createdAt,
    String origin = 'produce',
    double? ls,
    bool lsCalibrated = false,
    String? source,
  }) async {
    await db.into(db.knowledgeEdges).insert(
          KnowledgeEdgesCompanion.insert(
            id: id,
            fromId: fromId,
            toId: toId,
            origin: origin,
            ls: Value(ls),
            lsCalibrated: Value(lsCalibrated),
            source: Value(source),
            createdAt: createdAt,
            updatedAt: createdAt,
          ),
        );
  }

  test('两端按 external_id 解出标题，新的在前，严格有向各算一条', () async {
    await addPoint(title: 'I relied on him.', externalId: 'en::s::abc');
    await addPoint(title: 'rely on', externalId: 'en::w::rely-on');
    await addEdge(
      id: 'e_old',
      fromId: 'en::s::abc',
      toId: 'en::w::rely-on',
      createdAt: 1000,
    );
    await addEdge(
      id: 'e_new',
      fromId: 'en::w::rely-on',
      toId: 'en::s::abc',
      createdAt: 2000,
      origin: 'contains',
      ls: 0.6,
      source: '材料：词汇书（第 12 页）',
    );

    final all = await edges.all();

    expect(all.map((e) => e.id), <String>['e_new', 'e_old']);
    expect(all.first.fromTitle, 'rely on');
    expect(all.first.toTitle, 'I relied on him.');
    expect(all.first.origin, 'contains');
    expect(all.first.ls, 0.6);
    expect(all.first.lsCalibrated, isFalse);
    expect(all.first.source, '材料：词汇书（第 12 页）');
    expect(all.first.hasMissingEndpoint, isFalse);
    // 反过来那条是另一条边（不自动反向）。
    expect(all.last.fromId, 'en::s::abc');
    expect(all.last.toId, 'en::w::rely-on');
  });

  test('有一端不在库里：那一端留空，hasMissingEndpoint 说真话', () async {
    await addPoint(title: 'rely on', externalId: 'en::w::rely-on');
    await addEdge(
      id: 'e_missing',
      fromId: 'en::w::rely-on',
      toId: 'en::s::abc',
      createdAt: 1000,
    );

    final all = await edges.all();

    expect(all.single.fromTitle, 'rely on');
    expect(all.single.toTitle, isNull);
    expect(all.single.hasMissingEndpoint, isTrue);
  });

  test('ls 没给就留空 —— 读法不把"没有权重"读成 0', () async {
    await addEdge(id: 'e_no_ls', fromId: 'a', toId: 'b', createdAt: 1000);

    final all = await edges.all();

    expect(all.single.ls, isNull);
    expect(all.single.lsCalibrated, isFalse);
    // 图上有一条边、点上没有名字，照样读得出来。
    expect(all.single.hasMissingEndpoint, isTrue);
  });

  test('没有边就是空，不报错', () async {
    expect(await edges.all(), isEmpty);
  });
}

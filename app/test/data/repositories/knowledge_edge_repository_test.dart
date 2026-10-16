/// 线索边读法的测试（`app/lib/data/repositories/knowledge_edge_repository.dart`）。
///
/// 钉的是这一层唯一的价值：**库里那行被翻译成什么样**。
///
///  - 两端的标题按 `knowledge_points.external_id` 解出来，新的边在前；
///  - 有一端不在库里就如实留空（界面按 id 显示），不替图编一个名字；
///  - `ls` 与 `ls_calibrated` 原样带出来 —— 读法不许把"未标定"洗掉，
///    也不许把"材料没给 ls"读成 0；
///  - `forPoint(id)` 把一个点的出边和入边一起读回来（方向留给调用方判断），
///    别人的边不许混进来；
///  - 手写边（`origin: 'manual'`）那几条硬约束：两端必须在图里、同一个方向只留一条
///    （材料写过的不再手写一条平行的）、`ls` 留空、只能删手写的。
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

  test('forPoint：出边和入边都算它自己的，别处的边不许混进来', () async {
    await addPoint(title: 'rely on', externalId: 'en::w::rely-on');
    await addPoint(title: 'I relied on him.', externalId: 'en::s::abc');
    await addPoint(title: 'depend on', externalId: 'en::w::depend-on');
    await addEdge(
      id: 'e_out',
      fromId: 'en::w::rely-on',
      toId: 'en::s::abc',
      createdAt: 1000,
    );
    await addEdge(
      id: 'e_in',
      fromId: 'en::s::abc',
      toId: 'en::w::rely-on',
      createdAt: 2000,
      origin: 'contains',
    );
    await addEdge(
      id: 'e_other',
      fromId: 'en::w::depend-on',
      toId: 'en::s::abc',
      createdAt: 3000,
    );

    final mine = await edges.forPoint('en::w::rely-on');

    expect(mine.map((e) => e.id), <String>['e_in', 'e_out']);
    expect(mine.map((e) => e.fromId), <String>['en::s::abc', 'en::w::rely-on']);
    // 另一端解出名字：出边看 to、入边看 from —— 详情里要按这个说方向。
    expect(mine.first.toTitle, 'rely on');
    expect(mine.last.toTitle, 'I relied on him.');
  });

  test('forPoint：端点查无此点就是空，不替它编身份', () async {
    await addEdge(id: 'e_1', fromId: 'en::w::rely-on', toId: 'x', createdAt: 1);

    expect(await edges.forPoint('没有这个点'), isEmpty);
  });

  test('graphPoints：只有图里有 id 的点能当端点，重复 id 只算一个，按标题排', () async {
    await addPoint(title: 'rely on', externalId: 'en::w::rely-on');
    await addPoint(title: 'dedupe me', externalId: 'en::w::rely-on');
    await addPoint(title: 'I relied on him.', externalId: 'en::s::abc');
    // 手写的知识点：没有 external_id，连不了边，所以不在候选里。
    await anki.createKnowledgePoint(title: '手写的', content: '手写的');

    final points = await edges.graphPoints();

    expect(points.map((p) => p.externalId),
        <String>['en::s::abc', 'en::w::rely-on']);
    expect(points.first.title, 'I relied on him.');
    // 同一个 external_id 取第一个（与解标题同一套规则）。
    expect(points.last.title, 'rely on');
  });

  test('手写一条边：origin 是 manual、ls 留空、严格有向不自动反向', () async {
    await addPoint(title: 'rely on', externalId: 'en::w::rely-on');
    await addPoint(title: 'I relied on him.', externalId: 'en::s::abc');

    final created = await edges.createManualEdge(
      fromId: 'en::w::rely-on',
      toId: 'en::s::abc',
      now: 5000,
    );
    expect(created.outcome, ManualEdgeOutcome.created);
    expect(created.edgeId, 'manual:en::w::rely-on->en::s::abc');

    final row = await db.select(db.knowledgeEdges).getSingle();
    expect(row.origin, 'manual');
    expect(row.ls, isNull);
    expect(row.lsCalibrated, isFalse);
    expect(row.source, isNull);
    expect(row.batchId, isNull);
    expect(row.createdAt, 5000);

    // 反方向是另一条边（严格有向）：手写一条不算反向也写了。
    final reversed = await edges.createManualEdge(
      fromId: 'en::s::abc',
      toId: 'en::w::rely-on',
      now: 5001,
    );
    expect(reversed.outcome, ManualEdgeOutcome.created);
    expect(await db.select(db.knowledgeEdges).get(), hasLength(2));
  });

  test('同一个方向已经有一条边（不管谁写的）：手写不再加一条平行的', () async {
    await addPoint(title: 'rely on', externalId: 'en::w::rely-on');
    await addPoint(title: 'I relied on him.', externalId: 'en::s::abc');
    await addEdge(
      id: 'e_material',
      fromId: 'en::w::rely-on',
      toId: 'en::s::abc',
      createdAt: 1000,
      origin: 'produce',
    );

    final result = await edges.createManualEdge(
      fromId: 'en::w::rely-on',
      toId: 'en::s::abc',
      now: 5000,
    );

    expect(result.outcome, ManualEdgeOutcome.alreadyExists);
    expect(result.edgeId, 'e_material');
    expect(result.existingOrigin, 'produce');
    expect(await db.select(db.knowledgeEdges).get(), hasLength(1));
  });

  test('手写边：缺端点不加、自己连自己不加', () async {
    await addPoint(title: 'rely on', externalId: 'en::w::rely-on');

    final missing = await edges.createManualEdge(
      fromId: 'en::w::rely-on',
      toId: 'en::s::abc',
      now: 5000,
    );
    expect(missing.outcome, ManualEdgeOutcome.unknownEndpoint);

    final same = await edges.createManualEdge(
      fromId: 'en::w::rely-on',
      toId: 'en::w::rely-on',
      now: 5000,
    );
    expect(same.outcome, ManualEdgeOutcome.samePoint);
    expect(await db.select(db.knowledgeEdges).get(), isEmpty);
  });

  test('删手写边：删得掉；材料边与不存在的 id 都不删', () async {
    await addPoint(title: 'rely on', externalId: 'en::w::rely-on');
    await addPoint(title: 'I relied on him.', externalId: 'en::s::abc');
    await addEdge(
      id: 'e_material',
      fromId: 'en::w::rely-on',
      toId: 'en::s::abc',
      createdAt: 1000,
      origin: 'produce',
    );
    await edges.createManualEdge(
      fromId: 'en::s::abc',
      toId: 'en::w::rely-on',
      now: 5000,
    );

    expect(await edges.deleteManualEdge('e_material'),
        ManualEdgeDeleteOutcome.notManual);
    expect(
        await edges.deleteManualEdge('没有这条'), ManualEdgeDeleteOutcome.notFound);
    expect(await db.select(db.knowledgeEdges).get(), hasLength(2));

    expect(
      await edges.deleteManualEdge('manual:en::s::abc->en::w::rely-on'),
      ManualEdgeDeleteOutcome.deleted,
    );
    final left = await db.select(db.knowledgeEdges).get();
    expect(left.single.id, 'e_material');
  });
}

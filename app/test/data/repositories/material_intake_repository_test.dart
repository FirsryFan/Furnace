/// 材料摄取的落库与确认写入（roadmap §2-C ① / §3 第 6 行）。
///
/// 这一层只做两件事：把**待确认的提案**记下来（`record`），以及用户确认之后把它们写进
/// `knowledge_points` 与 `knowledge_edges`（`apply`）。所以这里钉的是这两件事里容易坏的部分：
///
///  1. 幂等：批次主键就是信封的 `batch_id`，重算同一批不该长出第二份提案，更不该把用户
///     已经确认过的记录抹掉（那是"重算覆盖人工决定"，比丢数据更坏）；
///  2. 去重：同名看标题、改名之后看 `external_id`（材料决定的内容 id），两道都要有；
///  3. 连接落成**线索边**（§2-C ④）：严格有向、`ls` 带"未标定"标记、边 id 幂等；
///     两端必须都在库里（本批刚建的或原有的）—— 缺一端就如实报 `deferred` 留在待办里，
///     不能编出一条边来（`MEMORY_RECORD.md` §3.5：包含语义只在标签树，线索才进图）。
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/material_intake_repository.dart';
import 'package:furnace/domain/services/ingest/material_intake_plan.dart';

MaterialIntakeEvidence evidenceOf(String batchId, {double? page = 12}) =>
    MaterialIntakeEvidence(
      source: '词汇书',
      page: page,
      region: page == null ? '第 ? 页' : '第 ${page.round()} 页',
      quote: '搭配',
      batchId: batchId,
    );

MaterialIntakeProposal point({
  required String batchId,
  required String nodeId,
  required String title,
  String body = '释义：依靠',
  bool exists = false,
  double? page = 12,
}) =>
    MaterialIntakeProposal(
      id: 'kp:$nodeId',
      kind: MaterialIntakeKind.knowledgePoint,
      title: title,
      nodeId: nodeId,
      body: body,
      why: '材料里标了「词」（要能复习的单元）',
      exists: exists,
      evidence: evidenceOf(batchId, page: page),
    );

MaterialIntakeProposal connection(
        {required String batchId, required String id}) =>
    MaterialIntakeProposal(
      id: 'edge:$id',
      kind: MaterialIntakeKind.connection,
      title: 'rely on → I relied on him.',
      from: 'en::w::rely-on',
      to: 'en::s::abc',
      ls: 0.6,
      origin: 'produce',
      body: '',
      why: '用它造出这句话（词 → 句）',
      exists: false,
      evidence: MaterialIntakeEvidence(
        source: '词汇书',
        page: 12,
        region: '边：produce',
        batchId: batchId,
      ),
    );

MaterialIntakePlan planOf({
  String batchId = 'b1',
  bool withSentence = true,
  bool withConnections = true,
  bool relyOnExists = false,
}) =>
    MaterialIntakePlan(
      batchId: batchId,
      topic: 'travel',
      sourceRef: '词汇书',
      proposals: <MaterialIntakeProposal>[
        if (withSentence)
          point(
              batchId: batchId,
              nodeId: 'en::s::abc',
              title: 'I relied on him.'),
        point(
          batchId: batchId,
          nodeId: 'en::w::rely-on',
          title: 'rely on',
          exists: relyOnExists,
        ),
        if (withConnections) connection(batchId: batchId, id: 'e_1'),
        if (withConnections) connection(batchId: batchId, id: 'e_2'),
      ],
      skipped: <MaterialIntakeSkip>[
        const MaterialIntakeSkip(ref: 'm3', reason: '疑问不进图（先答复）'),
      ],
    );

void main() {
  late AppDatabase db;
  late AnkiRepository anki;
  late MaterialIntakeRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    anki = AnkiRepository(db);
    repository = MaterialIntakeRepository(
      db,
      ankiRepository: anki,
      clock: () => DateTime.fromMillisecondsSinceEpoch(1789000000000),
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<MaterialIntakeBatch> record(MaterialIntakePlan plan) =>
      repository.record(
        plan,
        summaryText: '批次 ${plan.batchId}：3 条 → 2 节点 / 2 边',
        analyzedAt: DateTime.fromMillisecondsSinceEpoch(1789000000000),
        sourceKind: 'book',
      );

  test('record：同一批重算不长出第二份提案（幂等键就是 batch_id）', () async {
    await record(planOf());
    final first = (await repository.batch('b1'))!;
    expect(first.proposalCount, 4);
    expect(first.unappliedCount, 4);
    expect(first.topic, 'travel');
    expect(first.sourceRef, '词汇书');
    expect(first.sourceKind, 'book');
    expect(first.skipped, hasLength(1));
    expect(first.skipped.single.ref, 'm3');

    await record(planOf());
    expect(await repository.proposals('b1'), hasLength(4));
    expect((await repository.batch('b1'))!.proposalCount, 4);
  });

  test('record：重算替换"还没确认的"，已确认的行一个字不动', () async {
    // `applied_at` 是持久化的事，领域层的 `MaterialIntakeProposal` 不带它 ——
    // 直接看表，才不会把"读取顺序"当成"确认状态"。
    Future<List<MaterialIntakeProposalRow>> appliedRows() async {
      final rows = await db.select(db.materialIntakeProposals).get();
      return rows.where((row) => row.appliedAt != null).toList();
    }

    await record(planOf());
    await repository.apply(
      batchId: 'b1',
      proposalIds: <String>['kp:en::w::rely-on'],
    );
    expect(await appliedRows(), hasLength(1));
    expect((await appliedRows()).single.proposalId, 'kp:en::w::rely-on');

    // 重算：这次连句子都不标了（材料改过），但用户已经确认的那一条必须留着。
    await record(planOf(withSentence: false));

    expect(await appliedRows(), hasLength(1));
    expect((await appliedRows()).single.id, 'b1#kp:en::w::rely-on');
    expect(await repository.pendingProposals('b1'), hasLength(2));
    expect((await repository.batch('b1'))!.unappliedCount, 2);
  });

  test('batches：新的在前', () async {
    await record(planOf(batchId: 'b-old'));
    await repository.record(
      planOf(batchId: 'b-new'),
      summaryText: '新的',
      analyzedAt: DateTime.fromMillisecondsSinceEpoch(1789000009999),
    );

    final batches = await repository.batches();
    expect([for (final batch in batches) batch.batchId], ['b-new', 'b-old']);
    expect(batches.first.summaryText, '新的');
  });

  test('apply：知识点进库，连接落成线索边（严格有向、ls 未标定）', () async {
    await record(planOf());
    final outcome = await repository.apply(batchId: 'b1');

    expect(outcome.created, hasLength(2));
    expect(outcome.createdEdges, hasLength(2));
    expect(outcome.existing, isEmpty);
    expect(outcome.existingEdges, isEmpty);
    expect(outcome.deferred, isEmpty);
    expect(outcome.remaining, 0);
    expect(outcome.text, contains('新建 2 个知识点'));
    expect(outcome.text, contains('新建 2 条连接'));
    expect(outcome.text, isNot(contains('还剩')));

    final rows = await db.select(db.knowledgePoints).get();
    expect(rows, hasLength(2));
    final relyOn =
        rows.singleWhere((row) => row.externalId == 'en::w::rely-on');
    expect(relyOn.title, 'rely on');
    expect(relyOn.content, '释义：依靠');
    expect(relyOn.source, '材料：词汇书（第 12 页）');

    // 线索边：严格有向（词 → 句），出处与批次都记上，`ls` 带着"未标定"的标记。
    final edges = await db.select(db.knowledgeEdges).get();
    expect([for (final edge in edges) edge.id]..sort(), ['e_1', 'e_2']);
    final edge = edges.first;
    expect(edge.fromId, 'en::w::rely-on');
    expect(edge.toId, 'en::s::abc');
    expect(edge.origin, 'produce');
    expect(edge.ls, 0.6);
    expect(edge.lsCalibrated, isFalse, reason: 'ls 还没有标定来源，默认不许当真');
    expect(edge.batchId, 'b1');
    expect(edge.source, '材料：词汇书（第 12 页）');

    // 全部处理完：待办空了（连接也落了，不再报 deferred）。
    expect(await repository.pendingProposals('b1'), isEmpty);
    expect(outcome.created.map((point) => point.nodeId),
        containsAll(<String>['en::s::abc', 'en::w::rely-on']));
    expect(outcome.createdEdges.map((e) => e.edgeId),
        containsAll(<String>['e_1', 'e_2']));
  });

  test('apply：同名已存在不重复建（第二道去重认 external_id）', () async {
    await anki.createKnowledgePoint(title: 'rely on', content: '先有的点');
    await record(planOf(relyOnExists: true));

    final outcome = await repository.apply(batchId: 'b1');
    expect(outcome.created, hasLength(1));
    expect(outcome.created.single.title, 'I relied on him.');
    expect(outcome.existing, <String>['kp:en::w::rely-on']);
    // 那条老行没有 `external_id`，所以应用侧**证明不了**它就是这个节点：
    // 两条边的起点都落不下去，如实 deferred（宁可留着，也不编一条边）。
    expect(outcome.createdEdges, isEmpty);
    expect(outcome.deferred, hasLength(2));
    expect(await db.select(db.knowledgePoints).get(), hasLength(2));
    expect(await db.select(db.knowledgeEdges).get(), isEmpty);

    // 历史那边读得出来：这一条是"本来就有的"（成绩单只活在这次调用里）。
    // 落不了的两条边没被标 `applied_at`，所以不在这份名单里。
    final applied = await repository.appliedProposals('b1');
    expect(applied, hasLength(2));
    final byId = <String, bool>{
      for (final row in applied) row.proposal.id: row.alreadyExisted,
    };
    expect(byId['kp:en::w::rely-on'], isTrue);
    expect(byId['kp:en::s::abc'], isFalse);
  });

  test('apply：用户改过标题也能认出来（external_id 是材料决定的内容 id）', () async {
    await anki.createKnowledgePoint(
      title: '依赖（我改的名字）',
      content: '自己改过',
      externalId: 'en::w::rely-on',
    );
    await record(planOf());

    final outcome = await repository.apply(
      batchId: 'b1',
      proposalIds: <String>['kp:en::w::rely-on'],
    );
    expect(outcome.created, isEmpty);
    expect(outcome.existing, <String>['kp:en::w::rely-on']);
    expect(await db.select(db.knowledgePoints).get(), hasLength(1));
  });

  test('apply：确认两次是幂等的（同一条提案不会建出两个知识点或两条边）', () async {
    await record(planOf());
    final first = await repository.apply(batchId: 'b1');
    expect(first.created, hasLength(2));
    expect(first.createdEdges, hasLength(2));

    final second = await repository.apply(batchId: 'b1');
    expect(second.created, isEmpty);
    expect(second.createdEdges, isEmpty);
    expect(second.remaining, 0, reason: '第一遍已经把这一批全部处理完了');
    expect(await db.select(db.knowledgePoints).get(), hasLength(2));
    expect(await db.select(db.knowledgeEdges).get(), hasLength(2));

    // 第二遍"发现它们都存在"，但历史记的是**第一次点头时**的判断：
    // 这几条是那时新建的，不该被改写成"本来就有的"。
    final applied = await repository.appliedProposals('b1');
    expect(applied, hasLength(4));
    expect(
      applied.where((row) => row.alreadyExisted),
      isEmpty,
      reason: '第一次确认时它们都是新建的，再确认一次不覆盖这句历史',
    );
  });

  test('apply(proposalIds:)：只处理选中的那几条', () async {
    await record(planOf());
    final outcome = await repository.apply(
      batchId: 'b1',
      proposalIds: <String>['kp:en::s::abc', 'edge:e_1'],
    );

    expect(outcome.created, hasLength(1));
    expect(outcome.created.single.nodeId, 'en::s::abc');
    // 选中的边缺起点（`en::w::rely-on` 这一遍没选，库里也还没有）⇒ 落不了。
    expect(outcome.createdEdges, isEmpty);
    expect(outcome.deferred, <String>['edge:e_1']);
    expect(outcome.remaining, 3);
    expect(await repository.pendingProposals('b1'), hasLength(3));
    expect(await db.select(db.knowledgeEdges).get(), isEmpty);

    // 端点补齐之后，再确认同一批的边就落了（缺端不是永久拒绝）。
    final second = await repository.apply(
      batchId: 'b1',
      proposalIds: <String>['kp:en::w::rely-on', 'edge:e_1', 'edge:e_2'],
    );
    expect(second.created, hasLength(1));
    expect(second.createdEdges, hasLength(2));
    expect(second.deferred, isEmpty);
    expect(second.remaining, 0);
    expect(await db.select(db.knowledgeEdges).get(), hasLength(2));
  });

  test('apply：不存在的批次要报错，不是静默成功', () async {
    await expectLater(
      repository.apply(batchId: 'b-none'),
      throwsA(isA<MaterialApplyException>().having(
        (error) => error.message,
        'message',
        contains('没有这个批次'),
      )),
    );
  });

  test('坏 payload：库里的提案行还原不回来就抛 FormatException', () async {
    await db.into(db.materialIntakeBatches).insert(
          MaterialIntakeBatchesCompanion.insert(
            batchId: 'b-bad',
            analyzedAt: 1,
            summaryText: '坏行',
            skippedJson: '[]',
            proposalCount: 1,
            createdAt: 1,
            updatedAt: 1,
          ),
        );
    await db.into(db.materialIntakeProposals).insert(
          MaterialIntakeProposalsCompanion.insert(
            id: 'b-bad#kp:x',
            batchId: 'b-bad',
            proposalId: 'kp:x',
            sortIndex: 0,
            kind: 'knowledge_point',
            payloadJson: '[]',
            createdAt: 1,
            updatedAt: 1,
          ),
        );

    await expectLater(
      repository.pendingProposals('b-bad'),
      throwsA(isA<FormatException>()),
    );
  });
}

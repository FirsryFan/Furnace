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

import 'package:drift/drift.dart' show OrderingTerm, Value;
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

  // --- 撤回一次确认（roadmap §4（十六））-------------------------------------
  //
  // 撤回的边界只有一条：**只删这一批自己新建的行**。所以这里钉的是那几种"撤了就
  // 会伤到别的东西"的情形 —— 卡片、标签、别人挂上来的边，一律整批不撤、理由交回界面。

  /// 这一批全确认：2 个知识点 + 2 条线索边。
  Future<MaterialApplyOutcome> applyAll() async {
    await record(planOf());
    return repository.apply(batchId: 'b1');
  }

  Future<KnowledgePoint> pointRow(String externalId) =>
      (db.select(db.knowledgePoints)
            ..where((t) => t.externalId.equals(externalId)))
          .getSingle();

  test('undoBatch：撤掉这一批新建的知识点与线索边，提案退回待确认', () async {
    final applied = await applyAll();
    expect(applied.created, hasLength(2));
    expect(applied.createdEdges, hasLength(2));

    final outcome = await repository.undoBatch('b1');

    expect(outcome.undone, isTrue);
    expect(outcome.blocked, isEmpty);
    expect(outcome.removedPoints, hasLength(2));
    expect(outcome.removedEdges, hasLength(2));
    expect(outcome.restored, 4);
    expect(outcome.text, contains('删掉 2 个知识点'));
    // 库里真的空了：知识点与线索边都不剩。
    expect(await db.select(db.knowledgePoints).get(), isEmpty);
    expect(await db.select(db.knowledgeEdges).get(), isEmpty);
    // 提案回到待确认：两张单子上的读数跟着翻过去。
    expect(await repository.appliedProposals('b1'), isEmpty);
    expect(await repository.pendingProposals('b1'), hasLength(4));
    final batch = (await repository.batch('b1'))!;
    expect(batch.appliedCount, 0);
    expect(batch.unappliedCount, 4);
  });

  test('undoBatch："本来就有的"只退提案，库里那行一个字段不动', () async {
    final mine = await anki.createKnowledgePoint(
      title: 'rely on（我自己建的）',
      content: '释义：依靠',
      externalId: 'en::w::rely-on',
    );
    await applyAll();
    final rely = (await repository.appliedProposals('b1'))
        .firstWhere((entry) => entry.proposal.nodeId == 'en::w::rely-on');
    expect(rely.alreadyExisted, isTrue);

    final outcome = await repository.undoBatch('b1');

    expect(outcome.undone, isTrue);
    expect(outcome.removedPoints, hasLength(1));
    expect(outcome.removedPoints.single.nodeId, 'en::s::abc');
    expect(outcome.restored, 4);
    final rows = await db.select(db.knowledgePoints).get();
    expect(rows, hasLength(1));
    expect(rows.single.id, mine.id);
    expect(rows.single.title, 'rely on（我自己建的）');
    expect(await db.select(db.knowledgeEdges).get(), isEmpty);
  });

  test('undoBatch：知识点下面已经有卡片 —— 整批不撤，库里一个字没动', () async {
    await applyAll();
    final point = await pointRow('en::s::abc');
    await anki.getOrCreateUnitCardState(point.id, 'essay:${point.id}');

    final outcome = await repository.undoBatch('b1');

    expect(outcome.undone, isFalse);
    expect(outcome.restored, 0);
    expect(outcome.blocked, hasLength(1));
    expect(outcome.blocked.single.reason, contains('卡片'));
    expect(outcome.text, contains('撤不了'));
    expect(await db.select(db.knowledgePoints).get(), hasLength(2));
    expect(await db.select(db.knowledgeEdges).get(), hasLength(2));
    expect(await repository.appliedProposals('b1'), hasLength(4));
  });

  test('undoBatch：卡片模板也算卡片（还没答题就撤不了）', () async {
    await applyAll();
    final point = await pointRow('en::s::abc');
    await anki.createTemplate(
      knowledgePointId: point.id,
      type: 'basic',
      question: 'I relied on him.',
      answer: '我依靠了他。',
    );

    final outcome = await repository.undoBatch('b1');

    expect(outcome.undone, isFalse);
    expect(outcome.blocked.single.reason, contains('卡片'));
  });

  test('undoBatch：知识点上还挂着别的线索边 —— 撤不了', () async {
    await applyAll();
    await db.into(db.knowledgeEdges).insert(
          KnowledgeEdgesCompanion.insert(
            id: 'e_manual',
            fromId: 'en::s::abc',
            toId: 'en::w::other',
            origin: 'manual',
            ls: const Value(0.5),
            createdAt: 1,
            updatedAt: 1,
          ),
        );

    final outcome = await repository.undoBatch('b1');

    expect(outcome.undone, isFalse);
    expect(outcome.blocked.single.reason, contains('别的线索边'));
    // 这一批的两条边也留着：整批不撤是一条也不删。
    expect(await db.select(db.knowledgeEdges).get(), hasLength(3));
    expect(await db.select(db.knowledgePoints).get(), hasLength(2));
  });

  test('undoBatch：知识点已经打过标签 —— 撤不了', () async {
    await applyAll();
    final point = await pointRow('en::s::abc');
    await db.into(db.tags).insert(
          TagsCompanion.insert(
            id: 't1',
            name: '雅思核心',
            createdAt: 1,
            updatedAt: 1,
          ),
        );
    await db.into(db.objectTags).insert(
          ObjectTagsCompanion.insert(
            id: 'ot1',
            tagId: 't1',
            objectType: 'knowledge_point',
            objectId: point.id,
            createdAt: 1,
          ),
        );

    final outcome = await repository.undoBatch('b1');

    expect(outcome.undone, isFalse);
    expect(outcome.blocked.single.reason, contains('标签'));
    expect(await db.select(db.knowledgePoints).get(), hasLength(2));
  });

  test('undoBatch：边在库里但不是这一批建的 —— 撤不了', () async {
    await applyAll();
    await (db.update(db.knowledgeEdges)..where((t) => t.id.equals('e_1')))
        .write(const KnowledgeEdgesCompanion(batchId: Value('other')));

    final outcome = await repository.undoBatch('b1');

    expect(outcome.undone, isFalse);
    // 这条边一变成"别人的"，它挂着的两个知识点也同时被拦住了 —— 三条理由。
    expect(
      outcome.blocked.where((b) => b.reason.contains('不是这一批建的')),
      hasLength(1),
    );
    expect(
      outcome.blocked.where((b) => b.reason.contains('别的线索边')),
      hasLength(2),
    );
    expect(await db.select(db.knowledgeEdges).get(), hasLength(2));
  });

  test('undoBatch：行已经被手删掉 —— 不算拦路，只退提案', () async {
    await record(planOf(withSentence: false, withConnections: false));
    await repository.apply(batchId: 'b1');
    await (db.delete(db.knowledgePoints)
          ..where((t) => t.externalId.equals('en::w::rely-on')))
        .go();

    final outcome = await repository.undoBatch('b1');

    expect(outcome.undone, isTrue);
    expect(outcome.removedPoints, isEmpty);
    expect(outcome.restored, 1);
    expect(outcome.text, contains('没有自己新建的行'));
    expect(await repository.pendingProposals('b1'), hasLength(1));
  });

  test('undoBatch：没确认过的一批 —— 什么都不删，也什么都不退', () async {
    await record(planOf());

    final outcome = await repository.undoBatch('b1');

    expect(outcome.undone, isTrue);
    expect(outcome.removedPoints, isEmpty);
    expect(outcome.removedEdges, isEmpty);
    expect(outcome.restored, 0);
    expect(await repository.pendingProposals('b1'), hasLength(4));
  });

  test('undoBatch：撤了之后再确认，还是同一条边（幂等键没变）', () async {
    await applyAll();
    await repository.undoBatch('b1');

    final again = await repository.apply(batchId: 'b1');

    expect(again.created, hasLength(2));
    expect(again.createdEdges, hasLength(2));
    expect(await db.select(db.knowledgeEdges).get(), hasLength(2));
    expect(await db.select(db.knowledgePoints).get(), hasLength(2));
  });

  test('撤回流水：撤成的留下删掉了什么（行删了就只剩这一格）', () async {
    await applyAll();
    expect(await repository.undoLogs('b1'), isEmpty);

    final outcome = await repository.undoBatch('b1');
    final logs = await repository.undoLogs('b1');

    expect(logs, hasLength(1));
    final log = logs.single;
    expect(log.batchId, 'b1');
    expect(log.undone, isTrue);
    expect(log.requestedAt, 1789000000000);
    expect(log.restored, outcome.restored);
    expect(log.blockedCount, 0);
    expect(log.blockedReason, isNull);
    // 删掉的行点名点姓地留着：以后要回答"我上次撤了什么"，读的就是它。
    expect(
      [for (final point in log.removedPoints) point.nodeId],
      containsAll(<String>['en::s::abc', 'en::w::rely-on']),
    );
    expect(
      [for (final edge in log.removedEdges) edge.edgeId],
      containsAll(<String>['e_1', 'e_2']),
    );
    expect(log.removedPoints.first.title, isNotEmpty);
    expect(log.text, contains('撤过一次'));
    expect(log.text, contains('删掉 2 个知识点'));
    // 知识点与边真的没了，流水还在。
    expect(await db.select(db.knowledgePoints).get(), isEmpty);
    expect(await repository.undoLogs('b1'), hasLength(1));
  });

  test('撤回流水：没撤成也记一笔 —— 被什么拦住了要回答得出来', () async {
    await applyAll();
    final point = await pointRow('en::s::abc');
    await anki.getOrCreateUnitCardState(point.id, 'essay:${point.id}');

    final outcome = await repository.undoBatch('b1');
    final log = (await repository.undoLogs('b1')).single;

    expect(outcome.undone, isFalse);
    expect(log.undone, isFalse);
    expect(log.removedPoints, isEmpty);
    expect(log.removedEdges, isEmpty);
    expect(log.restored, 0);
    expect(log.blockedCount, 1);
    expect(log.blockedReason, contains('卡片'));
    expect(log.text, contains('没撤成'));
    expect(log.text, contains('卡片'));
    // 记账没动库：点和边都还在。
    expect(await db.select(db.knowledgePoints).get(), hasLength(2));
    expect(await db.select(db.knowledgeEdges).get(), hasLength(2));
  });

  test('撤回流水：撤两次记两行，按时间正序读回来', () async {
    await applyAll();
    await repository.undoBatch('b1');
    await repository.apply(batchId: 'b1');
    await repository.undoBatch('b1');

    final logs = await repository.undoLogs('b1');

    expect(logs, hasLength(2));
    expect([for (final log in logs) log.undone], everyElement(isTrue));
    expect([for (final log in logs) log.removedPoints.length], [2, 2]);
    // 流水不按批次汇总：别人的账不串进这一批。
    expect(await repository.undoLogs('b2'), isEmpty);
  });

  test('撤回流水：没确认过的批次也留一行（撤了，但本来就没建过什么）', () async {
    await record(planOf());

    await repository.undoBatch('b1');
    final log = (await repository.undoLogs('b1')).single;

    expect(log.undone, isTrue);
    expect(log.removedPoints, isEmpty);
    expect(log.removedEdges, isEmpty);
    expect(log.restored, 0);
    expect(log.text, contains('没有自己新建的行'));
  });

  test('撤回流水：同一毫秒的两次也按写入次序读（不靠时间戳排）', () async {
    await applyAll();
    await repository.undoBatch('b1');
    await repository.apply(batchId: 'b1');
    await repository.undoBatch('b1');

    // 时钟是固定的：两行 requestedAt 一样，排序得靠自增 id。
    final logs = await repository.undoLogs('b1');
    expect([for (final log in logs) log.requestedAt],
        [1789000000000, 1789000000000]);
    final rows = await (db.select(db.materialIntakeUndoLogs)
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    expect(rows, hasLength(2));
    expect(rows.first.id, lessThan(rows.last.id));
  });

  group('点头之前能改一改（renamePointProposal）', () {
    test('还没点头的知识点提案：名字改得动，连"库里已经有同名的了"一起重算', () async {
      await record(planOf());
      // 库里先有这么一个知识点：改成它的名字，这一条就该自己标上"已存在"。
      await anki.createKnowledgePoint(
          title: 'I relied on him.', content: '说过的一句话');

      await repository.renamePointProposal(
        batchId: 'b1',
        proposalId: 'kp:en::w::rely-on',
        title: '  I relied on him.  ',
      );

      var renamed = (await repository.pendingProposals('b1'))
          .firstWhere((proposal) => proposal.id == 'kp:en::w::rely-on');
      expect(renamed.title, 'I relied on him.', reason: '首尾空白要剪掉');
      expect(renamed.exists, isTrue, reason: '"已经有同名的了"这句话是现算的，改名之后要跟着变');

      // 改回一个库里没有的名字：那个标记也得消失 —— 留着它就是骗人。
      await repository.renamePointProposal(
        batchId: 'b1',
        proposalId: 'kp:en::w::rely-on',
        title: 'rely upon',
      );
      renamed = (await repository.pendingProposals('b1'))
          .firstWhere((proposal) => proposal.id == 'kp:en::w::rely-on');
      expect(renamed.title, 'rely upon');
      expect(renamed.exists, isFalse);

      // 别的提案一个字没动（改名不该顺手替用户做别的事）。
      expect(
        [
          for (final proposal in await repository.pendingProposals('b1'))
            proposal.id
        ],
        <String>[
          'kp:en::s::abc',
          'kp:en::w::rely-on',
          'edge:e_1',
          'edge:e_2',
        ],
      );
      expect((await repository.batch('b1'))!.proposalCount, 4);
      // 库里还是只有刚才那一个知识点：改名不写知识点。
      expect((await anki.getKnowledgePoints()).length, 1);
    });

    test('已经点头过的不许改（它是历史），提案本身一个字不动', () async {
      await record(planOf());
      await repository.apply(
        batchId: 'b1',
        proposalIds: <String>['kp:en::w::rely-on'],
      );
      final before = (await repository.proposals('b1'))
          .firstWhere((proposal) => proposal.id == 'kp:en::w::rely-on');

      await expectLater(
        repository.renamePointProposal(
          batchId: 'b1',
          proposalId: 'kp:en::w::rely-on',
          title: '别名',
        ),
        throwsA(
          isA<MaterialApplyException>().having(
            (error) => error.message,
            'message',
            contains('已经点头过'),
          ),
        ),
      );

      final after = (await repository.proposals('b1'))
          .firstWhere((proposal) => proposal.id == 'kp:en::w::rely-on');
      expect(after.title, before.title);
      expect(after.exists, before.exists);
    });

    test('连接的标题不给改：它是按两端名字现算的', () async {
      await record(planOf());

      await expectLater(
        repository.renamePointProposal(
          batchId: 'b1',
          proposalId: 'edge:e_1',
          title: '随便起的名字',
        ),
        throwsA(
          isA<MaterialApplyException>().having(
            (error) => error.message,
            'message',
            contains('只有知识点提案能改'),
          ),
        ),
      );
    });

    test('空标题（或只有空白）不许存：那等于把这一条悄悄删掉', () async {
      await record(planOf());

      await expectLater(
        repository.renamePointProposal(
          batchId: 'b1',
          proposalId: 'kp:en::w::rely-on',
          title: '   ',
        ),
        throwsA(
          isA<MaterialApplyException>().having(
            (error) => error.message,
            'message',
            contains('标题不能是空的'),
          ),
        ),
      );

      final proposal = (await repository.pendingProposals('b1'))
          .firstWhere((row) => row.id == 'kp:en::w::rely-on');
      expect(proposal.title, 'rely on');
    });

    test('这一批里没有这条提案：说人话，不装作改了', () async {
      await record(planOf());

      await expectLater(
        repository.renamePointProposal(
          batchId: 'b1',
          proposalId: 'kp:en::w::nope',
          title: 'x',
        ),
        throwsA(
          isA<MaterialApplyException>().having(
            (error) => error.message,
            'message',
            contains('没有这条提案'),
          ),
        ),
      );
    });

    test('editPointProposal：只改正文不动标题，点头之后写进 content 的就是它', () async {
      await record(planOf());
      final before = (await repository.pendingProposals('b1'))
          .firstWhere((proposal) => proposal.id == 'kp:en::w::rely-on');

      await repository.editPointProposal(
        batchId: 'b1',
        proposalId: 'kp:en::w::rely-on',
        body: '  释义：依靠；搭配 rely on sb.  ',
      );

      final after = (await repository.pendingProposals('b1'))
          .firstWhere((proposal) => proposal.id == 'kp:en::w::rely-on');
      expect(after.body, '释义：依靠；搭配 rely on sb.', reason: '首尾空白要剪掉');
      expect(after.title, before.title, reason: '只改正文就不该碰标题');
      expect(after.exists, before.exists);

      await repository.apply(
        batchId: 'b1',
        proposalIds: <String>['kp:en::w::rely-on'],
      );
      final points = await anki.getKnowledgePoints();
      expect(
        points.singleWhere((point) => point.title == 'rely on').content,
        '释义：依靠；搭配 rely on sb.',
      );
    });

    test('editPointProposal：标题与正文一起改，exists 也跟着现算', () async {
      await record(planOf());
      await anki.createKnowledgePoint(title: 'I relied on him.', content: '句子');

      await repository.editPointProposal(
        batchId: 'b1',
        proposalId: 'kp:en::w::rely-on',
        title: 'I relied on him.',
        body: '整句：我依靠他。',
      );

      final edited = (await repository.pendingProposals('b1'))
          .firstWhere((proposal) => proposal.id == 'kp:en::w::rely-on');
      expect(edited.title, 'I relied on him.');
      expect(edited.body, '整句：我依靠他。');
      expect(edited.exists, isTrue, reason: '改到库里已有的名字，那句话就得跟着变');
    });

    test('editPointProposal：两个字段都不给就是没改什么', () async {
      await record(planOf());
      final before = (await repository.pendingProposals('b1'))
          .firstWhere((proposal) => proposal.id == 'kp:en::w::rely-on');

      await repository.editPointProposal(
        batchId: 'b1',
        proposalId: 'kp:en::w::rely-on',
      );

      final after = (await repository.pendingProposals('b1'))
          .firstWhere((proposal) => proposal.id == 'kp:en::w::rely-on');
      expect(after.title, before.title);
      expect(after.body, before.body);
    });

    test('editPointProposal 改正文也走同一条规矩：已点头的不许改', () async {
      await record(planOf());
      await repository.apply(
        batchId: 'b1',
        proposalIds: <String>['kp:en::w::rely-on'],
      );

      await expectLater(
        repository.editPointProposal(
          batchId: 'b1',
          proposalId: 'kp:en::w::rely-on',
          body: '改一改',
        ),
        throwsA(
          isA<MaterialApplyException>().having(
            (error) => error.message,
            'message',
            contains('已经点头过'),
          ),
        ),
      );
    });
  });
}

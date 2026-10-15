/// 材料摄取的落库与确认写入（roadmap §2-C ① / §3 第 6 行）。
///
/// 这一层只做两件事：把**待确认的提案**记下来（`record`），以及用户确认之后把它们写进
/// `knowledge_points`（`apply`）。所以这里钉的是这两件事里容易坏的部分：
///
///  1. 幂等：批次主键就是信封的 `batch_id`，重算同一批不该长出第二份提案，更不该把用户
///     已经确认过的记录抹掉（那是"重算覆盖人工决定"，比丢数据更坏）；
///  2. 去重：同名看标题、改名之后看 `external_id`（材料决定的内容 id），两道都要有；
///  3. 不乱写没定的事：连接（线索边 vs 包含边，§2-C ④）现在没有落点，confirm 了也只能
///     如实报 `deferred` 并留在待办里，不能编出一条边来。
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
      body: '',
      why: '用它造出这句话（词 → 句）',
      exists: false,
      evidence: MaterialIntakeEvidence(
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

  test('apply：知识点真的进库，带 external_id 与出处文案；连接如实报 deferred', () async {
    await record(planOf());
    final outcome = await repository.apply(batchId: 'b1');

    expect(outcome.created, hasLength(2));
    expect(outcome.existing, isEmpty);
    expect(outcome.deferred, hasLength(2));
    expect(outcome.remaining, 2);
    expect(outcome.text, contains('新建 2 个知识点'));
    expect(outcome.text, contains('2 条连接先不动'));
    expect(outcome.text, contains('还剩 2 条待确认'));

    final rows = await db.select(db.knowledgePoints).get();
    expect(rows, hasLength(2));
    final relyOn =
        rows.singleWhere((row) => row.externalId == 'en::w::rely-on');
    expect(relyOn.title, 'rely on');
    expect(relyOn.content, '释义：依靠');
    expect(relyOn.source, '材料：词汇书（第 12 页）');

    // 连接没有被标上：它们还在待办里等 §2-C ④（线索边 vs 包含边）。
    final pending = await repository.pendingProposals('b1');
    expect([for (final proposal in pending) proposal.id],
        ['edge:e_1', 'edge:e_2']);
    expect(outcome.created.map((point) => point.nodeId),
        containsAll(<String>['en::s::abc', 'en::w::rely-on']));
  });

  test('apply：同名已存在不重复建（第二道去重认 external_id）', () async {
    await anki.createKnowledgePoint(title: 'rely on', content: '先有的点');
    await record(planOf(relyOnExists: true));

    final outcome = await repository.apply(batchId: 'b1');
    expect(outcome.created, hasLength(1));
    expect(outcome.created.single.title, 'I relied on him.');
    expect(outcome.existing, <String>['kp:en::w::rely-on']);
    expect(await db.select(db.knowledgePoints).get(), hasLength(2));
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

  test('apply：确认两次是幂等的（同一条提案不会建出两个知识点）', () async {
    await record(planOf());
    final first = await repository.apply(batchId: 'b1');
    expect(first.created, hasLength(2));

    final second = await repository.apply(batchId: 'b1');
    expect(second.created, isEmpty);
    expect(second.remaining, 2);
    expect(await db.select(db.knowledgePoints).get(), hasLength(2));
  });

  test('apply(proposalIds:)：只处理选中的那几条', () async {
    await record(planOf());
    final outcome = await repository.apply(
      batchId: 'b1',
      proposalIds: <String>['kp:en::s::abc', 'edge:e_1'],
    );

    expect(outcome.created, hasLength(1));
    expect(outcome.created.single.nodeId, 'en::s::abc');
    expect(outcome.deferred, <String>['edge:e_1']);
    expect(outcome.remaining, 3);
    expect(await repository.pendingProposals('b1'), hasLength(3));
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

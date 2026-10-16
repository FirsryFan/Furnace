/// 待确认清单上"哪几条连接现在落不了"（roadmap 轮次八十：落不了的看得见）。
///
/// 这一份读数存在的理由只有一个：**在用户点头之前就说清楚**。[`pendingMissingEndpointsOf`]
/// 必须与 `MaterialIntakeRepository.apply` 里 `_createEdge` 的判据逐条对齐，所以这里既钉
/// 纯函数（三种缺法、影子图、边已在库里、提案自己缺端点），也真写一遍库：确认之后落不了
/// 的那条留在待确认清单上、说法与成绩单一致；缺的那一端补进图里之后这句话自己消失。
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/material_intake_repository.dart';
import 'package:furnace/domain/services/ingest/material_intake_plan.dart';
import 'package:furnace/features/cognitive/application/material_intake_reader.dart';

const String wordId = 'en::w::rely-on';
const String sentenceId = 'en::s::abc';
final DateTime moment = DateTime.fromMillisecondsSinceEpoch(1789000000000);

MaterialIntakeEvidence evidenceOf(String batchId, String region) =>
    MaterialIntakeEvidence(
      source: '词汇书',
      page: 12,
      region: region,
      quote: '搭配',
      batchId: batchId,
    );

MaterialIntakeProposal pointOf(
  String nodeId, {
  String batchId = 'b1',
  bool exists = false,
}) =>
    MaterialIntakeProposal(
      id: 'kp:$nodeId',
      kind: MaterialIntakeKind.knowledgePoint,
      title: nodeId == wordId ? 'rely on' : 'I relied on him.',
      nodeId: nodeId,
      body: '释义：依靠',
      why: '材料里标了「词」（要能复习的单元）',
      exists: exists,
      evidence: evidenceOf(batchId, '第 12 页'),
    );

MaterialIntakeProposal connectionOf({
  String batchId = 'b1',
  String id = 'e_1',
  String? from = wordId,
  String? to = sentenceId,
}) =>
    MaterialIntakeProposal(
      id: 'edge:$id',
      kind: MaterialIntakeKind.connection,
      title: 'rely on → I relied on him.',
      from: from,
      to: to,
      ls: 0.6,
      origin: 'produce',
      body: '',
      why: '用它造出这句话（词 → 句）',
      exists: false,
      evidence: evidenceOf(batchId, '边：produce'),
    );

void main() {
  group('pendingMissingEndpointsOf（纯函数：这一批 + 库里现在的 id）', () {
    test('两端都在库里：没有落不了的', () {
      expect(
        pendingMissingEndpointsOf(
          proposals: <MaterialIntakeProposal>[connectionOf()],
          knownNodeIds: <String>{wordId, sentenceId},
          knownEdgeIds: const <String>{},
        ),
        isEmpty,
      );
    });

    test('差一端：说出缺的是哪一端（说得让人能去补）', () {
      final missing = pendingMissingEndpointsOf(
        proposals: <MaterialIntakeProposal>[connectionOf()],
        knownNodeIds: <String>{wordId},
        knownEdgeIds: const <String>{},
      );
      expect(missing, <String, String>{
        'edge:e_1': '终点 $sentenceId 还不在库里',
      });
    });

    test('差起点：说的是起点（有向，不混）', () {
      final missing = pendingMissingEndpointsOf(
        proposals: <MaterialIntakeProposal>[connectionOf()],
        knownNodeIds: <String>{sentenceId},
        knownEdgeIds: const <String>{},
      );
      expect(missing['edge:e_1'], '起点 $wordId 还不在库里');
    });

    test('两端都差：就说两端', () {
      final missing = pendingMissingEndpointsOf(
        proposals: <MaterialIntakeProposal>[connectionOf()],
        knownNodeIds: const <String>{},
        knownEdgeIds: const <String>{},
      );
      expect(missing['edge:e_1'], '两端都还不在库里');
    });

    test('本批的点提案会把那一端送进图里：不算缺（同一次确认里先点后边）', () {
      expect(
        pendingMissingEndpointsOf(
          proposals: <MaterialIntakeProposal>[
            pointOf(sentenceId),
            connectionOf(),
          ],
          knownNodeIds: <String>{wordId},
          knownEdgeIds: const <String>{},
        ),
        isEmpty,
      );
    });

    test('"同名已存在"的点提案不算数：它不写行，边照样落不了', () {
      final missing = pendingMissingEndpointsOf(
        proposals: <MaterialIntakeProposal>[
          pointOf(sentenceId, exists: true),
          connectionOf(),
        ],
        knownNodeIds: <String>{wordId},
        knownEdgeIds: const <String>{},
      );
      expect(missing['edge:e_1'], '终点 $sentenceId 还不在库里');
    });

    test('点提案自己没有 nodeId：送不出可用的 id，不算数', () {
      final missing = pendingMissingEndpointsOf(
        proposals: <MaterialIntakeProposal>[
          MaterialIntakeProposal(
            id: 'kp:anon',
            kind: MaterialIntakeKind.knowledgePoint,
            title: 'I relied on him.',
            body: '释义：依靠',
            why: '材料里标了「句」',
            exists: false,
            evidence: evidenceOf('b1', '第 12 页'),
          ),
          connectionOf(),
        ],
        knownNodeIds: <String>{wordId},
        knownEdgeIds: const <String>{},
      );
      expect(missing['edge:e_1'], '终点 $sentenceId 还不在库里');
    });

    test('边已经在库里：不再说"落不了"（确认时会说"已存在"）', () {
      expect(
        pendingMissingEndpointsOf(
          proposals: <MaterialIntakeProposal>[connectionOf()],
          knownNodeIds: const <String>{},
          knownEdgeIds: const <String>{'e_1'},
        ),
        isEmpty,
      );
    });

    test('提案自己没带端点：与 `_createEdge` 同一句话', () {
      final missing = pendingMissingEndpointsOf(
        proposals: <MaterialIntakeProposal>[connectionOf(from: null)],
        knownNodeIds: const <String>{},
        knownEdgeIds: const <String>{},
      );
      expect(missing['edge:e_1'], MaterialIntakeRepository.noEndpointsNote);
    });

    test('知识点不在这张单子上（只有连接会被问"落不落得了"）', () {
      expect(
        pendingMissingEndpointsOf(
          proposals: <MaterialIntakeProposal>[pointOf(sentenceId)],
          knownNodeIds: const <String>{},
          knownEdgeIds: const <String>{},
        ),
        isEmpty,
      );
    });
  });

  group('库上走一遍（record → apply → 再读）', () {
    late AppDatabase db;
    late AnkiRepository anki;
    late MaterialIntakeRepository repository;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      anki = AnkiRepository(db);
      repository = MaterialIntakeRepository(
        db,
        ankiRepository: anki,
        clock: () => moment,
      );
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> record(List<MaterialIntakeProposal> proposals) =>
        repository.record(
          MaterialIntakePlan(
            batchId: 'b1',
            topic: 'travel',
            sourceRef: '词汇书',
            proposals: proposals,
            skipped: const <MaterialIntakeSkip>[],
          ),
          summaryText: '批次 b1',
          analyzedAt: moment,
          sourceKind: 'book',
        );

    Future<Set<String>> ids() async {
      final proposals = await repository.proposals('b1');
      return <String>{for (final proposal in proposals) proposal.id};
    }

    test('确认之后落不了的那条留在待确认清单上，说法与成绩单一致', () async {
      await record(<MaterialIntakeProposal>[
        pointOf(sentenceId),
        connectionOf(),
      ]);
      final outcome = await repository.apply(
        batchId: 'b1',
        proposalIds: (await ids()).toList(),
        appliedAt: moment,
      );
      expect(outcome.deferred, <String>['edge:e_1']);
      expect(
        await readPendingMissingEndpoints(
          repository: repository,
          batchId: 'b1',
        ),
        <String, String>{'edge:e_1': '起点 $wordId 还不在库里'},
      );
    });

    test('缺的那一端补进图里之后，这句话自己消失（派生量不落库）', () async {
      await record(<MaterialIntakeProposal>[
        pointOf(sentenceId),
        connectionOf(),
      ]);
      await repository.apply(
        batchId: 'b1',
        proposalIds: (await ids()).toList(),
        appliedAt: moment,
      );
      expect(
        await readPendingMissingEndpoints(
          repository: repository,
          batchId: 'b1',
        ),
        isNotEmpty,
      );

      // 手建那一个知识点（相当于用户自己在别处把它送进了图）。
      await anki.createKnowledgePoint(
        title: 'rely on',
        content: '释义：依靠',
        externalId: wordId,
      );

      expect(
        await readPendingMissingEndpoints(
          repository: repository,
          batchId: 'b1',
        ),
        isEmpty,
      );
      // 而且真的落得下去了：再点一次确认，这条边进库。
      final again = await repository.apply(
        batchId: 'b1',
        proposalIds: <String>['edge:e_1'],
        appliedAt: moment,
      );
      expect(again.deferred, isEmpty);
      expect(again.createdEdges.map((edge) => edge.edgeId), <String>['e_1']);
    });

    test('两端都在这一批里：确认前不说落不了，确认后真落下去', () async {
      await record(<MaterialIntakeProposal>[
        pointOf(sentenceId),
        pointOf(wordId),
        connectionOf(),
      ]);
      expect(
        await readPendingMissingEndpoints(
          repository: repository,
          batchId: 'b1',
        ),
        isEmpty,
      );
      final outcome = await repository.apply(
        batchId: 'b1',
        proposalIds: (await ids()).toList(),
        appliedAt: moment,
      );
      expect(outcome.created.length, 2);
      expect(outcome.createdEdges.map((edge) => edge.edgeId), <String>['e_1']);
      expect(outcome.deferred, isEmpty);
    });

    test('还没确认的批次里读到的就是那句话（不用先失败一次）', () async {
      await record(<MaterialIntakeProposal>[
        pointOf(sentenceId),
        connectionOf(),
      ]);
      expect(
        await readPendingMissingEndpoints(
          repository: repository,
          batchId: 'b1',
        ),
        <String, String>{'edge:e_1': '起点 $wordId 还不在库里'},
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/ingest/material_intake_plan.dart';
import 'package:furnace/domain/services/ingest/run_executor.dart';
import 'package:furnace/domain/services/ingest/run_knowledge_plan.dart';

/// 一次"跑完"的报告：给一串痕迹就成。
RunExecutionReport reportOf(
  List<RunActionTrace> traces, {
  int? stoppedAt,
  String runId = 'run-1',
}) =>
    RunExecutionReport(
      runId: runId,
      traces: traces,
      assumptions: const <String>[],
      hoursBefore: 0,
      hoursAfter: 0,
      stoppedAt: stoppedAt,
    );

RunActionTrace nodeTrace({
  int index = 0,
  Map<String, Object?> node = const <String, Object?>{
    'id': 'en::w::rely-on',
    'name': 'rely on',
    'type': 'word',
    'ms': 0.8,
  },
  Map<String, Object?> delta = const <String, Object?>{},
}) =>
    RunActionTrace(
      index: index,
      kind: 'knowledge',
      mechanism: 'graph.add_node',
      summary: '新增节点 en::w::rely-on（rely on / word）',
      delta: delta.isEmpty
          ? <String, Object?>{'added': 'node', 'node': node}
          : delta,
    );

RunActionTrace edgeTrace({
  int index = 1,
  Map<String, Object?> edge = const <String, Object?>{
    'id': 'e_2_a__b',
    'from': 'en::w::a',
    'to': 'en::w::b',
    'ls': 0.8,
  },
}) =>
    RunActionTrace(
      index: index,
      kind: 'knowledge',
      mechanism: 'graph.add_edge',
      summary: '新增边 en::w::a → en::w::b（ls 0.8）',
      delta: <String, Object?>{'added': 'edge', 'edge': edge},
    );

RunActionTrace reviewTrace({int index = 0}) => RunActionTrace(
      index: index,
      kind: 'review',
      mechanism: 'memory.dsr',
      summary: '复习了 en::w::rely-on',
    );

void main() {
  group('一份跑完的 run/1 ⇒ 待确认提案', () {
    test('节点与边各变成一条提案，出处指着第几条动作', () {
      final plan = planRunKnowledge(
        report: reportOf(<RunActionTrace>[
          nodeTrace(index: 0),
          edgeTrace(index: 1),
        ]),
        existingNodeIds: const <String>{},
        existingTitles: const <String>{},
        sourceRef: '照片（第 1 页）',
      );

      expect(plan.batchId, 'run-1');
      expect(plan.sourceRef, '照片（第 1 页）');
      expect(plan.proposals, hasLength(2));

      final node = plan.proposals.first;
      expect(node.id, 'kp:en::w::rely-on');
      expect(node.kind, MaterialIntakeKind.knowledgePoint);
      expect(node.nodeId, 'en::w::rely-on');
      expect(node.title, 'rely on');
      expect(node.body, isEmpty, reason: '正文这一跑没说就不编');
      expect(node.exists, isFalse);
      expect(node.evidence.batchId, 'run-1', reason: '幂等键是这一跑的 run_id');
      expect(node.evidence.source, '照片（第 1 页）');
      expect(node.evidence.region, 'run/1 第 1 条 knowledge 动作');
      expect(node.evidence.quote, '新增节点 en::w::rely-on（rely on / word）');
      expect(node.why, contains('新建一个节点'));
      expect(node.why, contains('word'));

      final edge = plan.proposals.last;
      expect(edge.id, 'edge:e_2_a__b');
      expect(edge.kind, MaterialIntakeKind.connection);
      expect(edge.from, 'en::w::a');
      expect(edge.to, 'en::w::b');
      expect(edge.ls, 0.8);
      expect(edge.origin, 'run');
      expect(edge.title, 'en::w::a → en::w::b');
      expect(edge.evidence.region, 'run/1 第 2 条 knowledge 动作');
      expect(edge.exists, isFalse);
    });

    test('库里已经有的点标 exists（按 external_id 或同名）', () {
      final plan = planRunKnowledge(
        report: reportOf(<RunActionTrace>[
          nodeTrace(index: 0),
          nodeTrace(
            index: 1,
            node: const <String, Object?>{
              'id': 'en::w::other',
              'name': '别的一句',
              'type': 'word',
            },
          ),
        ]),
        existingNodeIds: const <String>{'en::w::rely-on'},
        existingTitles: const <String>{'别的一句'},
      );

      expect(plan.proposals[0].exists, isTrue, reason: 'external_id 已经在库里');
      expect(plan.proposals[1].exists, isTrue, reason: '同名知识点也在库里');

      final fresh = planRunKnowledge(
        report: reportOf(<RunActionTrace>[nodeTrace()]),
        existingNodeIds: const <String>{},
        existingTitles: const <String>{'rely on'},
      );
      expect(fresh.proposals.single.exists, isTrue);
    });

    test('节点没给名字 ⇒ 标题退回 id；边没给 ls ⇒ 留空不编 0.8', () {
      final plan = planRunKnowledge(
        report: reportOf(<RunActionTrace>[
          nodeTrace(
            index: 0,
            node: const <String, Object?>{'id': 'n1', 'type': 'word'},
          ),
          edgeTrace(
            index: 1,
            edge: const <String, Object?>{
              'id': 'e1',
              'from': 'n1',
              'to': 'n2',
            },
          ),
        ]),
        existingNodeIds: const <String>{},
        existingTitles: const <String>{},
      );

      expect(plan.proposals[0].title, 'n1');
      expect(plan.proposals[0].why, contains('连名字都没给'));
      expect(plan.proposals[1].ls, isNull);
    });

    test('别的动作（review/exposure/goal/time）进"留在清单外"并说清原因', () {
      final plan = planRunKnowledge(
        report: reportOf(<RunActionTrace>[
          reviewTrace(index: 0),
          nodeTrace(index: 1),
        ]),
        existingNodeIds: const <String>{},
        existingTitles: const <String>{},
      );

      expect(plan.proposals, hasLength(1));
      expect(plan.skipped, hasLength(1));
      expect(plan.skipped.single.ref, 'action:1');
      expect(plan.skipped.single.reason, contains('review'));
      expect(plan.skipped.single.reason, contains('不建东西'));
    });

    test('knowledge 动作没回报增量 ⇒ 不编提案，留一句说明', () {
      final plan = planRunKnowledge(
        report: reportOf(<RunActionTrace>[
          const RunActionTrace(
            index: 0,
            kind: 'knowledge',
            mechanism: 'graph.add_node',
            summary: '新增节点 n1',
          ),
        ]),
        existingNodeIds: const <String>{},
        existingTitles: const <String>{},
      );

      expect(plan.isEmpty, isTrue);
      expect(plan.skipped.single.reason, contains('没回报增量'));
    });
  });

  group('没跑完的一跑不许变成提案', () {
    test('抛出来的说法里带着第一条没跑成的原因', () {
      final report = reportOf(
        <RunActionTrace>[
          nodeTrace(index: 0),
          const RunActionTrace(
            index: 1,
            kind: 'goal',
            mechanism: 'start_diffusion',
            summary: '扩散',
            error: '起点不在图里：n9',
          ),
        ],
        stoppedAt: 1,
      );

      expect(
        () => planRunKnowledge(
          report: report,
          existingNodeIds: const <String>{},
          existingTitles: const <String>{},
        ),
        throwsA(
          isA<RunKnowledgeException>()
              .having((error) => error.message, 'message', contains('没跑完'))
              .having((error) => error.message, 'message', contains('第 2 条'))
              .having((error) => error.message, 'message', contains('起点不在图里'))
              .having((error) => error.message, 'message', contains('要么整份算清')),
        ),
      );
    });

    test('跑了一半时前面那条节点的提案也不给（先抛，再谈摆什么）', () {
      final report = reportOf(
        <RunActionTrace>[
          nodeTrace(index: 0),
          const RunActionTrace(
            index: 1,
            kind: 'review',
            mechanism: 'memory.dsr',
            summary: '复习',
            error: '缺少时间基：至少要 at.model_hours',
          ),
        ],
        stoppedAt: 1,
      );

      expect(
        () => planRunKnowledge(
          report: report,
          existingNodeIds: const <String>{},
          existingTitles: const <String>{},
        ),
        throwsA(isA<RunKnowledgeException>()),
      );
    });

    test('连接的两端说人话：这一跑自己建的名字优先，其次调用方给的标签，最后才是 id', () {
      final plan = planRunKnowledge(
        report: reportOf(<RunActionTrace>[
          // 这一跑建了两个节点（名字 alpha / beta），然后把它们连起来。
          nodeTrace(
            index: 0,
            node: const <String, Object?>{
              'id': 'en::w::a',
              'name': 'alpha',
              'type': 'word',
            },
          ),
          nodeTrace(
            index: 1,
            node: const <String, Object?>{
              'id': 'en::w::b',
              'name': 'beta',
              'type': 'word',
            },
          ),
          edgeTrace(index: 2),
        ]),
        existingNodeIds: const <String>{},
        existingTitles: const <String>{},
      );

      final edge = plan.proposals.last;
      expect(edge.title, 'alpha → beta');
      expect(edge.from, 'en::w::a', reason: '两端真身还是 id，只有标题说人话');
    });

    test('这一跑没建那一端时，用调用方给的标签（库里那个节点叫什么）', () {
      final plan = planRunKnowledge(
        report: reportOf(<RunActionTrace>[edgeTrace(index: 0)]),
        existingNodeIds: const <String>{},
        existingTitles: const <String>{},
        nodeLabels: const <String, String>{'en::w::b': 'beta（库里那张卡）'},
      );

      expect(plan.proposals.single.title, 'en::w::a → beta（库里那张卡）');
    });
  });
}

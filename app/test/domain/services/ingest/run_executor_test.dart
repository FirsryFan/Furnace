/// Q49：`run/1` 的执行那一半 —— 校验过的动作真的跑进引擎
/// （`src/io/run.js` 的 `applyOne()` / `resolveAt()`）。
///
/// 这里钉住的是"**预告的那条路就是真跑的那条路**"：`reviewTranscribedRun` 说
/// `review` 会走 `retrieval_success` / `lapse` / `retrieval_failure_feedback`，
/// 执行完的痕迹里 `mechanism` 就必须是同一个名字；以及失败时**停在哪一条、
/// 为什么**，而不是抛异常或默默往下跑。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/cognitive/fast_engine.dart';
import 'package:furnace/domain/services/ingest/material_ingest.dart';
import 'package:furnace/domain/services/ingest/run_executor.dart';
import 'package:furnace/domain/services/ingest/transcribe_run.dart';

/// 两个知识点节点，时钟在 [hours]，记忆层按 [memory] 装或不装。
FastEngine engineWith({
  bool memory = true,
  double hours = 100,
  List<({String id, double ms})> nodes = const <({String id, double ms})>[
    (id: 'en::s::abc', ms: 0.8),
    (id: 'en::w::depend-on', ms: 0.8),
  ],
}) {
  final graph = FastGraph();
  for (final node in nodes) {
    graph.addNode(FastNode(
      id: node.id,
      name: node.id,
      type: 'knowledge',
      ms: node.ms,
      lastReviewTime: hours,
    ));
  }
  return FastEngine(
    graph: graph,
    mechanisms: FastMechanisms.fromModuleDefaults(
      const <String, Object?>{},
      ids: memory ? const <String>[FastMechanisms.memory] : const <String>[],
    ),
    hours: hours,
  );
}

/// 一份真请求：走 [decodeRunRequest] 的解码，而不是手搓对象。
MaterialRunRequest runOf(
  List<Map<String, Object?>> actions, {
  String runId = 'run-1',
}) =>
    decodeRunRequest(<String, Object?>{
      'protocol': MaterialIngest.runProtocol,
      'run_id': runId,
      'actions': actions,
    });

double bagNumber(FastNode node, String key) =>
    (FastEngine.dsrBagOf(node)![key]! as num).toDouble();

void main() {
  group('executeRun', () {
    test('空请求：什么都没动，报告如实说"跑完 0 条"', () {
      final engine = engineWith();

      final report = executeRun(
        runOf(const <Map<String, Object?>>[]),
        engine: engine,
      );

      expect(report.ok, isTrue);
      expect(report.traces, isEmpty);
      expect(report.appliedCount, 0);
      expect(engine.hours, 100);
      expect(report.text, contains('跑完 0 条动作'));
      expect(report.toJson()['applied'], 0);
    });

    test('time（elapsed_hours）：时钟前进，有记忆态的节点 ms 同步，S 不动', () {
      final engine = engineWith();
      final node = engine.graph.nodes['en::s::abc']!;
      engine.review('en::s::abc', const <String, Object?>{
        'type': 'retrieval_success',
        'grade': 3,
      });
      final sBefore = bagNumber(node, 'S');
      final msBefore = node.ms;

      final report = executeRun(
        runOf(<Map<String, Object?>>[
          <String, Object?>{
            'kind': 'time',
            'elapsed_hours': 24,
            'at': <String, Object?>{'model_hours': 124},
          },
        ]),
        engine: engine,
      );

      expect(report.ok, isTrue);
      expect(engine.hours, 124);
      // 曲线往前走：ms 掉下来，S 一点没变（时间不"复习"）。
      expect(node.ms, lessThan(msBefore));
      expect(bagNumber(node, 'S'), sBefore);
      final trace = report.traces.single;
      expect(trace.mechanism, 'hours.advance');
      expect(trace.delta['synced_nodes'], 1);
      expect(trace.delta['nodes'], 2);
      expect(report.hoursBefore, 100);
      expect(report.hoursAfter, 124);
    });

    test('time 只给 at.wall：用锚点换算，并把这次换算记进 assumptions', () {
      final engine = engineWith();

      final report = executeRun(
        runOf(<Map<String, Object?>>[
          <String, Object?>{
            'kind': 'time',
            'at': <String, Object?>{
              'model_hours': 100,
              'wall': '2026-10-17T08:00:00Z',
            },
          },
          <String, Object?>{
            'kind': 'time',
            'at': <String, Object?>{'wall': '2026-10-17T14:00:00Z'},
          },
        ]),
        engine: engine,
      );

      expect(report.ok, isTrue);
      expect(engine.hours, 106);
      expect(report.assumptions, hasLength(1));
      expect(report.assumptions.single, contains('2026-10-17T14:00:00.000Z'));
      expect(report.anchor!.modelHours, 106);
      expect(report.text, contains('换算（记下来）'));
    });

    test('只给 at.wall 而没有锚点：停在第一条，时钟一动不动', () {
      final engine = engineWith();

      final report = executeRun(
        runOf(<Map<String, Object?>>[
          <String, Object?>{
            'kind': 'review',
            'node': 'en::s::abc',
            'outcome': 'correct',
            'at': <String, Object?>{'wall': '2026-10-17T08:00:00Z'},
          },
        ]),
        engine: engine,
      );

      expect(report.ok, isFalse);
      expect(report.stoppedAt, 0);
      expect(report.failure!.error, contains('锚点'));
      expect(report.appliedCount, 0);
      expect(engine.hours, 100);
      expect(report.text, contains('第 1 条动作没跑成'));
    });

    test('review：三条 outcome 各走各的机制，方向也各不相同', () {
      // correct → retrieval_success：S 涨（增量在痕迹里，不在记忆袋里 ——
      // 袋子里只有慢层的 S/D/Sigma，`R_after`/`S_after` 是这次复习的回报；
      // 全新的节点在第一次复习之前**根本没有袋子**，所以先看痕迹）。
      final success = engineWith();
      final successNode = success.graph.nodes['en::s::abc']!;
      expect(FastEngine.dsrBagOf(successNode), isNull);
      final successReport = executeRun(
        runOf(<Map<String, Object?>>[
          <String, Object?>{
            'kind': 'review',
            'node': 'en::s::abc',
            'outcome': 'correct',
            'at': <String, Object?>{'model_hours': 101},
          },
        ]),
        engine: success,
      );
      expect(successReport.ok, isTrue);
      final successTrace = successReport.traces.single;
      expect(successTrace.mechanism, 'retrieval_success');
      expect(
        (successTrace.delta['R_after']! as num).toDouble(),
        greaterThan(0.8),
      );
      expect(
        (successTrace.delta['S_increase']! as num).toDouble(),
        greaterThan(0),
      );
      expect(FastEngine.dsrBagOf(successNode), isNotNull);

      // wrong → lapse，S 掉。
      final lapse = engineWith();
      final lapseNode = lapse.graph.nodes['en::s::abc']!;
      lapse.review('en::s::abc', const <String, Object?>{
        'type': 'retrieval_success',
        'grade': 3,
      });
      final sBeforeLapse = bagNumber(lapseNode, 'S');
      final lapseReport = executeRun(
        runOf(<Map<String, Object?>>[
          <String, Object?>{
            'kind': 'review',
            'node': 'en::s::abc',
            'outcome': 'wrong',
            'at': <String, Object?>{'model_hours': 200},
          },
        ]),
        engine: lapse,
      );
      expect(lapseReport.traces.single.mechanism, 'lapse');
      expect(bagNumber(lapseNode, 'S'), lessThan(sBeforeLapse));

      // wrong + reviewed_solution → retrieval_failure_feedback（学习路径）。
      final feedback = engineWith();
      final feedbackNode = feedback.graph.nodes['en::s::abc']!;
      feedback.review('en::s::abc', const <String, Object?>{
        'type': 'retrieval_success',
        'grade': 3,
      });
      final sBeforeFeedback = bagNumber(feedbackNode, 'S');
      final feedbackReport = executeRun(
        runOf(<Map<String, Object?>>[
          <String, Object?>{
            'kind': 'review',
            'node': 'en::s::abc',
            'outcome': 'wrong',
            'reviewed_solution': true,
            'at': <String, Object?>{'model_hours': 200},
          },
        ]),
        engine: feedback,
      );
      expect(
        feedbackReport.traces.single.mechanism,
        'retrieval_failure_feedback',
      );
      expect(bagNumber(feedbackNode, 'S'), greaterThan(sBeforeFeedback));
    });

    test('exposure：走 reread，只算再读增益', () {
      final engine = engineWith();

      final report = executeRun(
        runOf(<Map<String, Object?>>[
          <String, Object?>{
            'kind': 'exposure',
            'node': 'en::w::depend-on',
            'at': <String, Object?>{'model_hours': 120},
          },
        ]),
        engine: engine,
      );

      expect(report.ok, isTrue);
      final trace = report.traces.single;
      expect(trace.kind, 'exposure');
      expect(trace.mechanism, 'reread');
      expect(trace.outcome, 'reread');
      expect(trace.delta, isNotEmpty);
    });

    test('没装记忆机制：复习照样留下痕迹，但如实说"没改状态"', () {
      final engine = engineWith(memory: false);

      final report = executeRun(
        runOf(<Map<String, Object?>>[
          <String, Object?>{
            'kind': 'review',
            'node': 'en::s::abc',
            'outcome': 'correct',
            'at': <String, Object?>{'model_hours': 101},
          },
        ]),
        engine: engine,
      );

      expect(report.ok, isTrue);
      final trace = report.traces.single;
      expect(trace.mechanism, 'retrieval_success');
      expect(trace.delta, isEmpty);
      expect(trace.summary, contains('没有装记忆机制'));
      expect(engine.graph.nodes['en::s::abc']!.m, isEmpty);
    });

    test('knowledge：同一批次先建点、再建边，图上真的有了', () {
      final engine = engineWith(nodes: const <({String id, double ms})>[]);

      final report = executeRun(
        runOf(<Map<String, Object?>>[
          <String, Object?>{
            'kind': 'knowledge',
            'node': <String, Object?>{
              'id': 'kp:new',
              'name': '新知识点',
              'type': 'knowledge',
            },
            'at': <String, Object?>{'model_hours': 100},
          },
          <String, Object?>{
            'kind': 'knowledge',
            'edge': <String, Object?>{
              'id': 'edge:new',
              'from': 'kp:new',
              'to': 'kp:new',
              'ls': 0.6,
            },
            'at': <String, Object?>{'model_hours': 100},
          },
        ]),
        engine: engine,
      );

      expect(report.ok, isTrue);
      expect(engine.graph.hasNode('kp:new'), isTrue);
      expect(engine.graph.nodes['kp:new']!.name, '新知识点');
      expect(engine.graph.nodes['kp:new']!.lastReviewTime, 100);
      expect(engine.graph.edges.single.id, 'edge:new');
      expect(engine.graph.edges.single.ls, 0.6);
      expect(report.traces.map((trace) => trace.mechanism),
          <String>['graph.add_node', 'graph.add_edge']);
    });

    test('knowledge 建边时端点不在图里：停在那一"条，如实报原因', () {
      final engine = engineWith();

      final report = executeRun(
        runOf(<Map<String, Object?>>[
          <String, Object?>{
            'kind': 'knowledge',
            'edge': <String, Object?>{
              'from': 'en::s::abc',
              'to': 'en::s::不存在的',
            },
            'at': <String, Object?>{'model_hours': 100},
          },
        ]),
        engine: engine,
      );

      expect(report.ok, isFalse);
      expect(report.stoppedAt, 0);
      expect(report.failure!.error, contains('建不了边'));
      expect(engine.graph.edges, isEmpty);
    });

    test('goal：起点用 engine.starts，目标按 targets 起扩散（轮次归零）', () {
      final engine = engineWith();

      final report = executeRun(
        runOf(<Map<String, Object?>>[
          <String, Object?>{
            'kind': 'goal',
            'targets': <String>['en::w::depend-on'],
            'starts': <String>['en::s::abc'],
            'at': <String, Object?>{'model_hours': 100},
          },
        ]),
        engine: engine,
      );

      expect(report.ok, isTrue);
      expect(report.traces.single.mechanism, 'start_diffusion');
      expect(engine.starts, <String>['en::s::abc']);
      expect(engine.targets, <String>['en::w::depend-on']);
      expect(engine.running, isTrue);
    });

    test('未知动作：停在第一条（执行层不默认"上游一定校验过"）', () {
      final engine = engineWith();

      final report = executeRun(
        runOf(<Map<String, Object?>>[
          <String, Object?>{
            'kind': 'teleport',
            'at': <String, Object?>{'model_hours': 100},
          },
        ]),
        engine: engine,
      );

      expect(report.ok, isFalse);
      expect(report.failure!.error, contains('未知动作'));
      expect(report.failure!.mechanism, '(未执行)');
    });

    test('预告与执行对账：reviewTranscribedRun 说的机制就是真跑的那条', () {
      final engine = engineWith(memory: true);
      final request = runOf(<Map<String, Object?>>[
        <String, Object?>{
          'kind': 'review',
          'node': 'en::s::abc',
          'outcome': 'wrong',
          'reviewed_solution': true,
          'at': <String, Object?>{'model_hours': 130},
        },
        <String, Object?>{
          'kind': 'review',
          'node': 'en::w::depend-on',
          'outcome': 'correct',
          'at': <String, Object?>{'model_hours': 130},
        },
        <String, Object?>{
          'kind': 'exposure',
          'node': 'en::s::abc',
          'at': <String, Object?>{'model_hours': 131},
        },
      ]);

      final check = reviewTranscribedRun(
        request,
        existingNodeIds: const <String>{'en::s::abc', 'en::w::depend-on'},
      );
      final report = executeRun(request, engine: engine);

      expect(check.ok, isTrue);
      expect(report.ok, isTrue);
      for (final trace in report.traces) {
        final expected = check.previews.firstWhere(
            (preview) => preview.startsWith('第 ${trace.index + 1} 条 action'));
        expect(
          expected,
          contains('→ ${trace.mechanism}'),
          reason: '第 ${trace.index + 1} 条：预告与执行必须说同一条路',
        );
      }
    });
  });
}

/// 演练（Q56 / roadmap 切片 6 的下一步（二十一））：把一份 `mindnet.run/1` 请求真的
/// apply 进引擎，而库一个字不动。
///
/// 这里钉的是"装配"这一层的事 —— 也就是 `run_executor.dart` 从轮次七十八写下之后
/// 一直缺的那个调用者答的那几个问题：图从哪来（库里 `knowledge_points.external_id`）、
/// 节点的 `ms` 从哪来（库里代表卡片的模型读数）、读不出来时怎么办（如实列出来，不编）、
/// 边跟着谁走（两端都在仿真图里才接过来）、时间基从哪来（请求自己的 `time`，没有就用
/// 注入的"现在"），以及**只跑不落库**。
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/domain/services/cognitive/cognitive_model.dart';
import 'package:furnace/domain/services/cognitive/fast_engine.dart';
import 'package:furnace/domain/services/cognitive/mechanism_catalog.dart';
import 'package:furnace/domain/services/ingest/material_ingest.dart';
import 'package:furnace/domain/services/ingest/transcribe_run.dart';
import 'package:furnace/features/cognitive/application/run_rehearsal.dart';

/// 一条带 `at.model_hours` 的 `review`（wrong + 对答案 = 走反馈那条路径）。
Map<String, Object?> reviewAction(String nodeId, {Object? at}) =>
    <String, Object?>{
      'kind': 'review',
      'node': nodeId,
      'outcome': 'wrong',
      'reviewed_solution': true,
      if (at != null) 'at': at,
      'evidence': <String, Object?>{'quote': '我写成了 rely in'},
      'confidence': 0.7,
    };

const double kBase = 497321.25;

MaterialRunRequest requestOf(
  List<Map<String, Object?>> actions, {
  Map<String, Object?>? time = const <String, Object?>{'model_hours': kBase},
}) =>
    decodeRunRequest(<String, Object?>{
      'protocol': 'mindnet.run/1',
      'run_id': 'run-rehearsal-1',
      if (time != null) 'time': time,
      'actions': actions,
    });

void main() {
  late AppDatabase db;
  late AnkiRepository anki;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    anki = AnkiRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<KnowledgePoint> pointOf(String externalId) =>
      anki.createKnowledgePoint(
        title: '点 $externalId',
        content: '内容',
        externalId: externalId,
      );

  Future<void> edgeOf(String id, String from, String to) =>
      db.into(db.knowledgeEdges).insert(
            KnowledgeEdgesCompanion.insert(
              id: id,
              fromId: from,
              toId: to,
              origin: 'material',
              createdAt: 0,
              updatedAt: 0,
            ),
          );

  test('库里已有的节点摆进仿真图，ms 来自代表卡片；动作真的动了机制', () async {
    final point = await pointOf('kp-a');
    await anki.getOrCreateUnitCardState(point.id, 'unit-1');

    final rehearsal = await rehearseRun(
      request: requestOf(<Map<String, Object?>>[
        reviewAction('kp-a', at: <String, Object?>{'model_hours': kBase + 0.5}),
      ]),
      db: db,
      model: const MindNetCognitiveModel(),
    );

    expect(rehearsal.ok, isTrue, reason: rehearsal.report.text);
    expect(rehearsal.seedNodeIds, <String>['kp-a']);
    expect(rehearsal.seedEdgeIds, isEmpty);
    // 有卡片 ⇒ 读得出 `r0`（`encoding_strength` 没记就是 1.0），不是"没有 ms"。
    expect(rehearsal.nodesWithoutMs, isEmpty);
    expect(rehearsal.touchedMechanisms, 1);
    expect(rehearsal.report.hoursBefore, kBase);
    // `review` 不推时钟（推时钟只有 `time` 那条路），但这条动作自己的时刻被尊重。
    expect(rehearsal.report.hoursAfter, kBase);

    final trace = rehearsal.report.traces.single;
    expect(trace.kind, 'review');
    expect(trace.atModelHours, kBase + 0.5);
    expect(trace.delta['mechanism'], 'memory.dsr');
    expect(trace.delta['R_after'], isA<num>());

    // 只跑不落库：卡片还是那一张、知识点还是那一行、没有任何边被建出来。
    expect(await anki.getKnowledgePoints(), hasLength(1));
    expect(await db.select(db.cardStates).get(), hasLength(1));
    expect(await db.select(db.knowledgeEdges).get(), isEmpty);
  });

  test('没有卡片 ⇒ 读不出 ms：如实列出来，动作照样跑（引擎按默认 0.8）', () async {
    await pointOf('kp-a');

    final rehearsal = await rehearseRun(
      request: requestOf(<Map<String, Object?>>[
        reviewAction('kp-a', at: <String, Object?>{'model_hours': kBase}),
      ]),
      db: db,
      model: const MindNetCognitiveModel(),
    );

    expect(rehearsal.ok, isTrue, reason: rehearsal.report.text);
    expect(rehearsal.seedNodeIds, <String>['kp-a']);
    expect(rehearsal.nodesWithoutMs, <String>['kp-a']);
    expect(rehearsal.touchedMechanisms, 1);
    expect(rehearsal.text, contains('1 个节点没有 ms'));
  });

  test('边：两端都在仿真图里才接过来；库里没被提到的节点不摆', () async {
    await pointOf('kp-a');
    await pointOf('kp-b');
    await pointOf('kp-c');
    await edgeOf('e_ab', 'kp-a', 'kp-b');
    await edgeOf('e_ca', 'kp-c', 'kp-a');

    final rehearsal = await rehearseRun(
      request: requestOf(<Map<String, Object?>>[
        reviewAction('kp-a', at: <String, Object?>{'model_hours': kBase}),
        reviewAction('kp-b', at: <String, Object?>{'model_hours': kBase}),
      ]),
      db: db,
      model: const MindNetCognitiveModel(),
    );

    expect(rehearsal.ok, isTrue, reason: rehearsal.report.text);
    expect(rehearsal.seedNodeIds, <String>['kp-a', 'kp-b']);
    // `kp-c` 没被这份请求提到 ⇒ 不摆它，那条边也就接不过来。
    expect(rehearsal.seedEdgeIds, <String>['e_ab']);
    expect(rehearsal.touchedMechanisms, 2);
  });

  test('`knowledge` 动作要建的节点不预摆：那份请求自己建（库里那份不冒充）', () async {
    await pointOf('kp-a');

    final rehearsal = await rehearseRun(
      request: requestOf(<Map<String, Object?>>[
        <String, Object?>{
          'kind': 'knowledge',
          'at': <String, Object?>{'model_hours': kBase},
          'node': <String, Object?>{
            'id': 'kp-a',
            'name': '要建的点',
            'type': 'concept',
          },
        },
      ]),
      db: db,
      model: const MindNetCognitiveModel(),
    );

    // 演练跑的是**引擎**的语义：请求说要建，仿真图里就还没有它（库里那份不冒充请求
    // 要建的那份），所以这一步在建，不报"重复"。库里那行一个字没动。
    expect(rehearsal.ok, isTrue, reason: rehearsal.report.text);
    expect(rehearsal.seedNodeIds, isEmpty);
    expect(rehearsal.report.traces.single.kind, 'knowledge');
    expect(rehearsal.report.traces.single.ok, isTrue);
    expect(await anki.getKnowledgePoints(), hasLength(1));
  });

  test('先建后复习：请求自己建的节点，后面的动作接得上', () async {
    final rehearsal = await rehearseRun(
      request: requestOf(<Map<String, Object?>>[
        <String, Object?>{
          'kind': 'knowledge',
          'at': <String, Object?>{'model_hours': kBase},
          'node': <String, Object?>{
            'id': 'kp-new',
            'name': '新点',
            'type': 'concept',
          },
        },
        reviewAction('kp-new', at: <String, Object?>{'model_hours': kBase + 1}),
      ]),
      db: db,
      model: const MindNetCognitiveModel(),
    );

    expect(rehearsal.ok, isTrue, reason: rehearsal.report.text);
    expect(rehearsal.seedNodeIds, isEmpty);
    // 第一条建出了 `kp-new`（所以它不在 unknown 里），第二条复习接得上。
    expect(rehearsal.unknownNodeIds, isEmpty);
    expect(rehearsal.report.traces, hasLength(2));
    expect(rehearsal.report.traces.last.delta['mechanism'], 'memory.dsr');
    // 两条都留下了增量（建节点 + 复习），但只有复习那条动了机制钩子。
    expect(rehearsal.changedCount, 2);
    expect(rehearsal.touchedMechanisms, 1);
  });

  test('请求自己带 time.model_hours ⇒ 引擎从那刻起算（不拿"现在"冒充）', () async {
    await pointOf('kp-a');

    final rehearsal = await rehearseRun(
      request: requestOf(<Map<String, Object?>>[
        // 只有 `elapsed_hours` 的 `time` 动作：起点就是请求自己的 `time.model_hours`。
        <String, Object?>{'kind': 'time', 'elapsed_hours': 2},
      ]),
      db: db,
      model: const MindNetCognitiveModel(),
      now: DateTime.fromMillisecondsSinceEpoch(0),
    );

    expect(rehearsal.ok, isTrue, reason: rehearsal.report.text);
    expect(rehearsal.report.hoursBefore, kBase);
    expect(rehearsal.report.hoursAfter, kBase + 2);
    expect(rehearsal.report.traces.single.kind, 'time');
    expect(rehearsal.report.traces.single.mechanism, 'hours.advance');
  });

  test('请求没有时间基 ⇒ 用注入的"现在"当起点', () async {
    await pointOf('kp-a');
    final moment = DateTime.utc(2026, 10, 17, 4, 6);

    final rehearsal = await rehearseRun(
      request: requestOf(
        <Map<String, Object?>>[
          reviewAction('kp-a', at: <String, Object?>{'model_hours': 12}),
        ],
        time: null,
      ),
      db: db,
      model: const MindNetCognitiveModel(),
      now: moment,
    );

    expect(rehearsal.ok, isTrue, reason: rehearsal.report.text);
    expect(rehearsal.report.hoursBefore, modelHoursOf(moment));
    // 动作自己写了 `at.model_hours`（它那条事件发生在 12），但时钟没有跟着跳。
    expect(rehearsal.report.traces.single.atModelHours, 12);
    expect(rehearsal.report.hoursAfter, modelHoursOf(moment));
  });

  test('只给 `at.wall` 而没有锚点 ⇒ 如实报"没有锚点"，不拿"现在"冒充', () async {
    await pointOf('kp-a');

    final rehearsal = await rehearseRun(
      request: requestOf(
        <Map<String, Object?>>[
          reviewAction(
            'kp-a',
            at: <String, Object?>{'wall': '2026-10-17T04:06:00Z'},
          ),
        ],
        time: null,
      ),
      db: db,
      model: const MindNetCognitiveModel(),
      now: DateTime.utc(2026, 10, 17, 4, 6),
    );

    expect(rehearsal.ok, isFalse);
    expect(rehearsal.report.failure!.error, contains('锚点'));
    expect(rehearsal.report.stoppedAt, 0);
  });

  test('请求自己带 time.wall ⇒ 那份 time 就是锚点', () async {
    await pointOf('kp-a');

    final rehearsal = await rehearseRun(
      request: requestOf(
        <Map<String, Object?>>[
          reviewAction(
            'kp-a',
            at: <String, Object?>{'wall': '2026-10-17T05:06:00Z'},
          ),
        ],
        time: <String, Object?>{
          'model_hours': kBase,
          'wall': '2026-10-17T04:06:00Z',
        },
      ),
      db: db,
      model: const MindNetCognitiveModel(),
    );

    expect(rehearsal.ok, isTrue, reason: rehearsal.report.text);
    // 差一小时 ⇒ 锚点换算成 model_hours + 1，并把推算过程记进 assumptions；
    // 时钟仍然停在引擎起点（推时钟只有 `time` 那条路）。
    expect(rehearsal.report.traces.single.atModelHours, kBase + 1);
    expect(rehearsal.report.hoursAfter, kBase);
    expect(rehearsal.report.assumptions, hasLength(1));
    expect(rehearsal.report.assumptions.single, contains('→ model_hours'));
  });

  test('`toJson` 把"图里先摆了什么"原样带出去', () async {
    final point = await pointOf('kp-a');
    await anki.getOrCreateUnitCardState(point.id, 'unit-1');
    await edgeOf('e_self', 'kp-a', 'kp-a');

    final rehearsal = await rehearseRun(
      request: requestOf(<Map<String, Object?>>[
        reviewAction('kp-a', at: <String, Object?>{'model_hours': kBase}),
      ]),
      db: db,
      model: const MindNetCognitiveModel(),
    );

    final json = rehearsal.toJson();
    expect(json['seed_node_ids'], <String>['kp-a']);
    expect(json['seed_edge_ids'], <String>['e_self']);
    expect(json['nodes_without_ms'], isEmpty);
    expect(json['unknown_node_ids'], isEmpty);
    expect((json['report']! as Map<String, Object?>)['ok'], isTrue);
  });

  test('未知节点：动作指向、库里没有，也没有动作去建它 ⇒ 如实记下', () async {
    await pointOf('kp-a');

    final rehearsal = await rehearseRun(
      request: requestOf(<Map<String, Object?>>[
        reviewAction('kp-a', at: <String, Object?>{'model_hours': kBase}),
        reviewAction('kp-ghost', at: <String, Object?>{'model_hours': kBase}),
      ]),
      db: db,
      model: const MindNetCognitiveModel(),
    );

    expect(rehearsal.ok, isFalse);
    expect(rehearsal.seedNodeIds, <String>['kp-a']);
    expect(rehearsal.unknownNodeIds, <String>['kp-ghost']);
    expect(rehearsal.text, contains('1 个节点库里没有'));
  });

  test('装配：只装记忆层（`executeRun` 不跑轮次，逐轮那四个用不上）', () {
    expect(MechanismCatalog.runRehearsalIds, <String>[FastMechanisms.memory]);
    // 覆盖也照抄转录默认：点火阈值退化那条（D3）在每一跑里都一样。
    expect(
      MechanismCatalog.setups.map((setup) => setup.id),
      contains(MechanismCatalog.runRehearsal),
    );
  });
}

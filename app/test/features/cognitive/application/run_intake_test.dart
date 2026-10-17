import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/material_intake_repository.dart';
import 'package:furnace/domain/services/ingest/run_executor.dart';
import 'package:furnace/domain/services/ingest/run_knowledge_plan.dart';
import 'package:furnace/features/cognitive/application/material_intake_reader.dart';
import 'package:furnace/features/cognitive/application/run_intake.dart';

/// 一跑就建两个点、再把它们连起来 —— 这样 `apply` 那一步才有边可落
/// （两端都得在库里，否则如实报 `deferred`）。
RunExecutionReport reportOf({String runId = 'run-1'}) => RunExecutionReport(
      runId: runId,
      traces: <RunActionTrace>[
        const RunActionTrace(
          index: 0,
          kind: 'knowledge',
          mechanism: 'graph.add_node',
          summary: '新增节点 en::w::a（alpha / word）',
          delta: <String, Object?>{
            'added': 'node',
            'node': <String, Object?>{
              'id': 'en::w::a',
              'name': 'alpha',
              'type': 'word',
            },
          },
        ),
        const RunActionTrace(
          index: 1,
          kind: 'knowledge',
          mechanism: 'graph.add_node',
          summary: '新增节点 en::w::b（beta / word）',
          delta: <String, Object?>{
            'added': 'node',
            'node': <String, Object?>{
              'id': 'en::w::b',
              'name': 'beta',
              'type': 'word',
            },
          },
        ),
        const RunActionTrace(
          index: 2,
          kind: 'knowledge',
          mechanism: 'graph.add_edge',
          summary: '新增边 en::w::a → en::w::b（ls 0.8）',
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
    );

void main() {
  late AppDatabase db;
  late AnkiRepository anki;
  late MaterialIntakeRepository materials;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    anki = AnkiRepository(db);
    materials = MaterialIntakeRepository(db, ankiRepository: anki);
  });

  tearDown(() async {
    await db.close();
  });

  test('一次演练 ✅ 待确认提案：知识点一个字节没动，清单上摆着三样', () async {
    final batch = await recordRunKnowledge(
      report: reportOf(),
      db: db,
      anki: anki,
      now: DateTime(2026, 10, 17, 9),
      sourceRef: '照片（第 1 页）',
    );

    expect(batch.batchId, 'run-1', reason: '幂等键就是这一跑的 run_id');
    expect(batch.proposalCount, 3);

    final pending = await readPendingBatch(
      repository: materials,
      batchId: 'run-1',
    );
    expect(pending, isNotNull);
    expect(pending!.proposals, hasLength(3));
    expect(pending.batch.proposalCount, 3);
    expect(pending.proposals[0].nodeId, 'en::w::a');
    expect(pending.proposals[2].from, 'en::w::a');
    expect(pending.proposals[2].origin, 'run');
    expect(
      pending.batch.summaryText,
      contains('从一份 `run/1` 里读出来的待确认提案'),
    );
    // 演练不落库，但"这一跑当时做了什么"跟着批次存下来了（schema v23）：
    // 每条动作一行引擎原话，下面缩进它的读数。过几天回来点头时还看得见。
    expect(pending.batch.detailText, isNotNull);
    expect(
      pending.batch.detailText,
      contains('1 [knowledge] 新增节点 en::w::a（alpha / word）'),
    );
    expect(
      pending.batch.detailText,
      contains('3 [knowledge] 新增边 en::w::a → en::w::b（ls 0.8）'),
    );

    // 关键断言：这一步只写清单，知识点与线索边一行都没有。
    expect(await db.select(db.knowledgePoints).get(), isEmpty);
    expect(await db.select(db.knowledgeEdges).get(), isEmpty);
  });

  test('同一跑落两次 ⇒ 还是那一批、还是三条提案', () async {
    await recordRunKnowledge(report: reportOf(), db: db, anki: anki);
    await recordRunKnowledge(report: reportOf(), db: db, anki: anki);

    final batches = await db.select(db.materialIntakeBatches).get();
    expect(batches, hasLength(1));
    expect(await db.select(db.materialIntakeProposals).get(), hasLength(3));

    final pending = await readPendingBatch(
      repository: materials,
      batchId: 'run-1',
    );
    expect(pending!.proposals, hasLength(3));
  });

  test('清单上点头之后才真的建出来（点 + 线索边）', () async {
    await recordRunKnowledge(report: reportOf(), db: db, anki: anki);

    final outcome = await materials.apply(batchId: 'run-1');

    expect(outcome.created, hasLength(2));
    expect(outcome.createdEdges, hasLength(1));
    expect(outcome.deferred, isEmpty);

    final points = await db.select(db.knowledgePoints).get();
    expect(points, hasLength(2));
    expect(
      <String>{
        for (final point in points)
          if (point.externalId != null) point.externalId!,
      },
      <String>{'en::w::a', 'en::w::b'},
    );
    expect(<String>{for (final point in points) point.title},
        <String>{'alpha', 'beta'});

    final edges = await db.select(db.knowledgeEdges).get();
    expect(edges, hasLength(1));
    expect(edges.single.fromId, 'en::w::a');
    expect(edges.single.toId, 'en::w::b');
    expect(edges.single.origin, 'run');
    expect(edges.single.lsCalibrated, isFalse, reason: 'ls 没有标定来源');
  });

  test('只有 review 的一跑：不编一批空清单出来，人话说明为什么', () async {
    const report = RunExecutionReport(
      runId: 'run-2',
      traces: <RunActionTrace>[
        RunActionTrace(
          index: 0,
          kind: 'review',
          mechanism: 'memory.dsr',
          summary: '复习了 en::w::a',
        ),
      ],
      assumptions: <String>[],
      hoursBefore: 0,
      hoursAfter: 0,
    );

    await expectLater(
      recordRunKnowledge(report: report, db: db, anki: anki),
      throwsA(
        isA<RunKnowledgeException>()
            .having((error) => error.message, 'message', contains('没有要新建的东西')),
      ),
    );
    expect(await db.select(db.materialIntakeBatches).get(), isEmpty);
  });

  test('没跑完的一跑：整份不算，一行提案都不落', () async {
    const report = RunExecutionReport(
      runId: 'run-3',
      traces: <RunActionTrace>[
        RunActionTrace(
          index: 0,
          kind: 'knowledge',
          mechanism: 'graph.add_node',
          summary: '新增节点 n1',
          delta: <String, Object?>{
            'added': 'node',
            'node': <String, Object?>{'id': 'n1', 'name': 'n1', 'type': 'word'},
          },
        ),
        RunActionTrace(
          index: 1,
          kind: 'goal',
          mechanism: 'start_diffusion',
          summary: '扩散',
          error: '起点不在图里：n9',
        ),
      ],
      assumptions: <String>[],
      hoursBefore: 0,
      hoursAfter: 0,
      stoppedAt: 1,
    );

    await expectLater(
      recordRunKnowledge(report: report, db: db, anki: anki),
      throwsA(
        isA<RunKnowledgeException>()
            .having((error) => error.message, 'message', contains('没跑完')),
      ),
    );
    expect(await db.select(db.materialIntakeBatches).get(), isEmpty);
    expect(await db.select(db.knowledgePoints).get(), isEmpty);
  });
}

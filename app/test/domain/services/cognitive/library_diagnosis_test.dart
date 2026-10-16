import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/cognitive/cognitive_graph.dart';
import 'package:furnace/domain/services/cognitive/cognitive_model.dart';
import 'package:furnace/domain/services/cognitive/fast_diagnosis.dart'
    show BottleneckType;
import 'package:furnace/domain/services/cognitive/fast_engine.dart';
import 'package:furnace/domain/services/cognitive/library_diagnosis.dart';
import 'package:furnace/domain/services/cognitive/mechanism_catalog.dart';

/// The whole-library tierB run is a pure function of its inputs, so these tests
/// need no database: tags and rows are plain values.
///
/// What they pin, in order of importance:
///
/// * "nothing ran" (no graph) and "ran and had nothing to say" are different
///   results - the same distinction the page makes between `unavailable` and
///   `healthy`.
/// * `danger` comes from the metacognition layer and from nowhere else: the
///   runner counts every non-start node with a card row, hands its belief rows to
///   the classifier, and a node with no card row is *not* judged (test 6).
///   Whether a node lands in `danger` or in `anxiety` is a statement about the
///   clock, so tests 4 and 5 run the same graph at an early and a stale hour.
/// * ids outside the graph are dropped instead of crashing the engine, and a
///   start node never complains about itself.
void main() {
  const model = MindNetCognitiveModel();
  const nowHours = 1000.0;

  CardState rowOf(String knowledgePointId, {double? encodingStrength = 1.0}) =>
      CardState(
        id: 'cs-$knowledgePointId',
        knowledgePointId: knowledgePointId,
        unitKey: 'cloze:s1',
        dueAt: 995000,
        intervalDays: 5,
        ease: 2.5,
        repetitions: 4,
        lapses: 0,
        state: 'review',
        lastReviewedAt: 990000,
        createdAt: 1,
        updatedAt: 2,
        stability: 5,
        difficulty: 5,
        encodingStrength: encodingStrength,
        savings: 0.8,
        forced: 0,
        forcedStreak: 0,
      );

  CognitiveTag tag(String id, {String? parentId}) =>
      CognitiveTag(id: id, name: id, parentId: parentId);

  test('no graph means nothing ran', () {
    final result = LibraryDiagnosisRunner.run(
      tags: const [],
      rowsByKnowledgePoint: const {},
      model: model,
      nowHours: nowHours,
      targetKnowledgePointIds: const ['kp-1'],
    );

    expect(result.fastLayerRan, isFalse);
    expect(result.byKnowledgePoint, isEmpty);
    expect(result.nodesWithoutMs, isEmpty);
  });

  test('a graph with no usable start or target still does not run', () {
    final result = LibraryDiagnosisRunner.run(
      tags: [tag('kp-1'), tag('kp-2', parentId: 'kp-1')],
      rowsByKnowledgePoint: {
        'kp-1': rowOf('kp-1'),
        'kp-2': rowOf('kp-2'),
      },
      model: model,
      nowHours: nowHours,
      // Both ids are outside the graph: they must be dropped, not crash.
      startKnowledgePointIds: const ['nope'],
      targetKnowledgePointIds: const ['also-nope'],
    );

    expect(result.fastLayerRan, isFalse);
    expect(result.byKnowledgePoint, isEmpty);
    // The graph existed, so its "no R0 given" nodes are still reported.
    expect(result.nodesWithoutMs, isEmpty);
  });

  test('a start and a target are enough to run, and a start never complains',
      () {
    final result = LibraryDiagnosisRunner.run(
      tags: [
        tag('root'),
        tag('child', parentId: 'root'),
        tag('target', parentId: 'root'),
      ],
      rowsByKnowledgePoint: {
        'root': rowOf('root'),
        'child': rowOf('child'),
        'target': rowOf('target'),
      },
      model: model,
      nowHours: nowHours,
      startKnowledgePointIds: const ['root', 'not-a-node'],
      targetKnowledgePointIds: const ['target'],
    );

    expect(result.fastLayerRan, isTrue);
    expect(result.starts, const ['root']);
    expect(result.targets, const ['target']);
    expect(result.rounds, 4);
    expect(
      result.byKnowledgePoint.keys,
      everyElement(isIn(const ['root', 'child', 'target'])),
    );
    expect(result.byKnowledgePoint.containsKey('root'), isFalse);
    expect(
      result.byKnowledgePoint.values,
      everyElement(isIn(BottleneckType.values)),
    );
  });

  test('the belief reading skips the start and judges the rest', () {
    final result = LibraryDiagnosisRunner.run(
      tags: [
        tag('root'),
        tag('a', parentId: 'root'),
        tag('b', parentId: 'root'),
        tag('c', parentId: 'root'),
      ],
      rowsByKnowledgePoint: {
        for (final id in const ['root', 'a', 'b', 'c']) id: rowOf(id),
      },
      model: model,
      nowHours: nowHours,
      startKnowledgePointIds: const ['root'],
      targetKnowledgePointIds: const ['c'],
    );

    expect(result.metacognition.hasRows, isTrue);
    expect(
      result.metacognition.rows.map((row) => row.node),
      isNot(contains('root')),
    );
    expect(
      result.metacognition.rows.map((row) => row.node),
      containsAll(const ['a', 'b', 'c']),
    );
    // At this clock the cards are only ~1000 model hours old, so their belief
    // sits *below* what the cards can actually do: the layer reports the quieter
    // "you think you are worse off than you are", not danger.
    expect(result.metacognition.danger, isEmpty);
    expect(result.metacognition.anxiety, isNotEmpty);
    expect(
      result.byKnowledgePoint.values,
      isNot(contains(BottleneckType.danger)),
    );
  });

  test('the same graph turns dangerous once the cards go stale', () {
    // A danger verdict is a statement about the clock, not about the graph: the
    // diffusion still lights the same nodes, but their cards have not been
    // touched for ~100k model hours, so belief now sits far above reality.
    const staleHours = 100000.0;
    final result = LibraryDiagnosisRunner.run(
      tags: [
        tag('root'),
        tag('a', parentId: 'root'),
        tag('b', parentId: 'root'),
        tag('c', parentId: 'root'),
      ],
      rowsByKnowledgePoint: {
        for (final id in const ['root', 'a', 'b', 'c']) id: rowOf(id),
      },
      model: model,
      nowHours: staleHours,
      startKnowledgePointIds: const ['root'],
      targetKnowledgePointIds: const ['c'],
    );

    expect(result.metacognition.danger, isNotEmpty);
    for (final row in result.metacognition.danger) {
      expect(row.diff, greaterThan(0.2));
      expect(result.byKnowledgePoint[row.node], BottleneckType.danger);
    }
    // The target is judged too - and it is *not* the dangerous one here.
    expect(result.byKnowledgePoint['c'], isNot(BottleneckType.danger));
  });

  test('a node with no card row is not judged: its reality is unknown', () {
    final result = LibraryDiagnosisRunner.run(
      tags: [tag('root'), tag('target', parentId: 'root'), tag('no-row')],
      rowsByKnowledgePoint: {
        'root': rowOf('root'),
        'target': rowOf('target'),
      },
      model: model,
      nowHours: nowHours,
      startKnowledgePointIds: const ['root'],
      targetKnowledgePointIds: const ['target'],
    );

    // 'no-row' gets no belief row at all rather than a guessed retrievability.
    expect(
      result.metacognition.rows.map((row) => row.node),
      isNot(contains('no-row')),
    );
    expect(result.metacognition.calibration, isNot(0));
  });

  test('a node with no in-edges is the empty/no-entry complaint', () {
    // A lone tag has no parent edge and no sibling edge, so the projection gives
    // it in-degree 0: nothing can carry a cue into it.
    final result = LibraryDiagnosisRunner.run(
      tags: [tag('lonely'), tag('root'), tag('target', parentId: 'root')],
      rowsByKnowledgePoint: {
        for (final id in const ['lonely', 'root', 'target']) id: rowOf(id),
      },
      model: model,
      nowHours: nowHours,
      startKnowledgePointIds: const ['root'],
      targetKnowledgePointIds: const ['target'],
    );

    expect(result.fastLayerRan, isTrue);
    expect(result.byKnowledgePoint['lonely'], BottleneckType.empty);
  });

  test('a node without a card row is reported as missing its ms', () {
    final result = LibraryDiagnosisRunner.run(
      tags: [tag('root'), tag('target', parentId: 'root'), tag('no-row')],
      rowsByKnowledgePoint: {
        'root': rowOf('root'),
        'target': rowOf('target'),
      },
      model: model,
      nowHours: nowHours,
      startKnowledgePointIds: const ['root'],
      targetKnowledgePointIds: const ['target'],
    );

    expect(result.fastLayerRan, isTrue);
    expect(result.nodesWithoutMs, contains('no-row'));
    expect(result.nodesWithoutMs, isNot(contains('root')));
  });

  test('an illegal R0 is treated as not provided, not as a number', () {
    final result = LibraryDiagnosisRunner.run(
      tags: [tag('root'), tag('target', parentId: 'root')],
      rowsByKnowledgePoint: {
        'root': rowOf('root', encodingStrength: 0),
        'target': rowOf('target'),
      },
      model: model,
      nowHours: nowHours,
      startKnowledgePointIds: const ['root'],
      targetKnowledgePointIds: const ['target'],
    );

    expect(result.fastLayerRan, isTrue);
    expect(result.nodesWithoutMs, contains('root'));
  });

  test('the JSON handshake names the run and the verdicts', () {
    final result = LibraryDiagnosisRunner.run(
      tags: [tag('root'), tag('target', parentId: 'root')],
      rowsByKnowledgePoint: {
        'root': rowOf('root'),
        'target': rowOf('target'),
      },
      model: model,
      nowHours: nowHours,
      startKnowledgePointIds: const ['root'],
      targetKnowledgePointIds: const ['target'],
    );

    final json = result.toJson();
    expect(json['schema'], 'mindnet.library/1');
    expect(json['fast_layer_ran'], isTrue);
    expect(json['starts'], const ['root']);
    expect(json['targets'], const ['target']);
    expect(json['bottlenecks'], isA<Map<String, Object?>>());
    final metacognition = json['metacognition']! as Map<String, Object?>;
    expect(metacognition['schema'], 'mindnet.metacognition/1');
    expect(metacognition['calibration'], isA<double>());
    expect(metacognition['rows'], isA<List<Object?>>());
  });

  group('目标机制开关（roadmap §3 第 8 行第一个用户侧开关）', () {
    LibraryDiagnosis run({required bool goalMechanismEnabled}) =>
        LibraryDiagnosisRunner.run(
          tags: [tag('root'), tag('target', parentId: 'root')],
          rowsByKnowledgePoint: {
            'root': rowOf('root'),
            'target': rowOf('target'),
          },
          model: model,
          nowHours: nowHours,
          startKnowledgePointIds: const ['root'],
          targetKnowledgePointIds: const ['target'],
          goalMechanismEnabled: goalMechanismEnabled,
        );

    test('默认（用户没选过）：装目标机制，读数里写着它', () {
      final result = run(goalMechanismEnabled: true);
      expect(result.mechanismIds, MechanismCatalog.libraryDiagnosisIds);
      expect(result.mechanismIds, contains(FastMechanisms.goal));
      expect(result.fastLayerRan, isTrue);
    });

    test('关掉之后：这一次跑真的没有装它（读数自己说得清）', () {
      final result = run(goalMechanismEnabled: false);
      expect(result.mechanismIds, hasLength(3));
      expect(result.mechanismIds, isNot(contains(FastMechanisms.goal)));
      expect(result.mechanismIds, isNot(contains(FastMechanisms.memory)));
      // 关掉目标机制不改"跑没跑"：起点还在，扩散照跑。
      expect(result.fastLayerRan, isTrue);
      expect(result.starts, const ['root']);
      expect(result.targets, const ['target']);
    });

    test('JSON 里也写着这一次装了哪些机制', () {
      expect(
        run(goalMechanismEnabled: false).toJson()['mechanism_ids'],
        MechanismCatalog.libraryDiagnosisIdsFor(goalEnabled: false),
      );
      expect(
        run(goalMechanismEnabled: true).toJson()['mechanism_ids'],
        MechanismCatalog.libraryDiagnosisIds,
      );
    });

    test('没跑起来的那两次：什么都没装，清单是空的（不是"装了默认的"）', () {
      final noGraph = LibraryDiagnosisRunner.run(
        tags: const [],
        rowsByKnowledgePoint: const {},
        model: model,
        nowHours: nowHours,
        targetKnowledgePointIds: const ['kp-1'],
      );
      final noStart = LibraryDiagnosisRunner.run(
        tags: [tag('kp-1')],
        rowsByKnowledgePoint: {'kp-1': rowOf('kp-1')},
        model: model,
        nowHours: nowHours,
        startKnowledgePointIds: const ['nope'],
        targetKnowledgePointIds: const ['also-nope'],
      );
      expect(noGraph.mechanismIds, isEmpty);
      expect(noStart.mechanismIds, isEmpty);
    });
  });

  group('目标机制的第一个滑块（roadmap §3 第 8 行第一个用户侧滑块）', () {
    LibraryDiagnosis run({double? goalBeta}) => LibraryDiagnosisRunner.run(
          tags: [tag('root'), tag('target', parentId: 'root')],
          rowsByKnowledgePoint: {
            'root': rowOf('root'),
            'target': rowOf('target'),
          },
          model: model,
          nowHours: nowHours,
          startKnowledgePointIds: const ['root'],
          targetKnowledgePointIds: const ['target'],
          moduleDefaults: MechanismCatalog.goalBetaDefaults(
            installedIds: MechanismCatalog.libraryDiagnosisIds,
            goalBeta: goalBeta,
          ),
        );

    test('用户没调过（NULL）：这一次跑一个默认值都不传', () {
      final result = run();
      expect(result.moduleDefaults, isEmpty);
      expect(result.toJson()['module_defaults'], isEmpty);
    });

    test('用户调过：只有 context.goal.beta_goal 那一个键进去，读数带出来', () {
      final result = run(goalBeta: 1.2);
      expect(
        result.moduleDefaults,
        <String, Object?>{
          FastMechanisms.goal: <String, Object?>{'beta_goal': 1.2},
        },
      );
      expect(result.toJson()['module_defaults'], result.moduleDefaults);
    });

    test('滑块不改装了什么：机制清单与不调时一字不差', () {
      expect(run(goalBeta: 1.2).mechanismIds, run().mechanismIds);
      expect(
        run(goalBeta: 1.2).mechanismIds,
        MechanismCatalog.libraryDiagnosisIds,
      );
    });

    test('没跑起来的那两次：module_defaults 也是空的（没用的东西不写进读数）', () {
      final noGraph = LibraryDiagnosisRunner.run(
        tags: const [],
        rowsByKnowledgePoint: const {},
        model: model,
        nowHours: nowHours,
        moduleDefaults: MechanismCatalog.goalBetaDefaults(
          installedIds: MechanismCatalog.libraryDiagnosisIds,
          goalBeta: 2,
        ),
      );
      expect(noGraph.moduleDefaults, isEmpty);
    });
  });
}

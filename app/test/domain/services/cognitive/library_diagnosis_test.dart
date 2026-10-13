import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/cognitive/cognitive_graph.dart';
import 'package:furnace/domain/services/cognitive/cognitive_model.dart';
import 'package:furnace/domain/services/cognitive/fast_diagnosis.dart'
    show BottleneckType;
import 'package:furnace/domain/services/cognitive/library_diagnosis.dart';

/// The whole-library tierB run is a pure function of its inputs, so these tests
/// need no database: tags and rows are plain values.
///
/// What they pin, in order of importance:
///
/// * "nothing ran" (no graph) and "ran and had nothing to say" are different
///   results - the same distinction the page makes between `unavailable` and
///   `healthy`.
/// * `danger` can never appear: this app stores no metacognition rows, so the
///   hook gets an empty `dangerRows` list. The test asserts the *absence* so a
///   future change that starts inventing danger rows fails here.
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

  test('danger is never reported: no metacognition rows exist here', () {
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

    expect(result.byKnowledgePoint.values, isNot(contains(BottleneckType.danger)));
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
  });
}

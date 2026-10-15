import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/cognitive/assessment_prior.dart';
import 'package:furnace/domain/services/cognitive/fast_diagnosis.dart';
import 'package:furnace/domain/services/scheduling/cognitive_readings.dart';

void main() {
  AssessmentPriorEstimate prior(
    String id, {
    double r0 = 0.4,
    double confidence = 0.5,
  }) =>
      AssessmentPriorEstimate(
        knowledgePointId: id,
        r0: r0,
        difficulty: null,
        fluency: null,
        n: 3,
        confidence: confidence,
        basis: const ['self:3'],
      );

  group('diagnosis -> reading', () {
    test('danger becomes the danger zone, weak becomes the development zone',
        () {
      final readings = CognitiveReadingsAdapter.readingsFor(
        knowledgePointIds: ['kp-a', 'kp-b'],
        diagnosisByKnowledgePoint: {
          'kp-a': BottleneckType.danger,
          'kp-b': BottleneckType.weak,
        },
      );

      expect(readings.length, 2);
      expect(readings[0].knowledgePointId, 'kp-a');
      expect(readings[0].inDangerZone, isTrue);
      expect(readings[0].inDevelopmentZone, isFalse);
      expect(readings[1].knowledgePointId, 'kp-b');
      expect(readings[1].inDangerZone, isFalse);
      expect(readings[1].inDevelopmentZone, isTrue);
    });

    test('the other five bottleneck types are not an effectiveness signal',
        () {
      final readings = CognitiveReadingsAdapter.readingsFor(
        knowledgePointIds: ['kp-a', 'kp-b', 'kp-c', 'kp-d', 'kp-e'],
        diagnosisByKnowledgePoint: {
          'kp-a': BottleneckType.empty,
          'kp-b': BottleneckType.slow,
          'kp-c': BottleneckType.overload,
          'kp-d': BottleneckType.offGoal,
          'kp-e': BottleneckType.deadEnd,
        },
      );

      expect(readings, isEmpty);
    });

    test('a knowledge point absent from a ran diagnosis gets no reading', () {
      final readings = CognitiveReadingsAdapter.readingsFor(
        knowledgePointIds: ['kp-healthy'],
        diagnosisByKnowledgePoint: const <String, BottleneckType>{},
      );

      expect(readings, isEmpty);
    });
  });

  group('priors -> reading', () {
    test('a prior with confidence > 0 becomes a reading on its own', () {
      final readings = CognitiveReadingsAdapter.readingsFor(
        knowledgePointIds: ['kp-a'],
        priors: {'kp-a': prior('kp-a', r0: 0.25, confidence: 0.4)},
      );

      expect(readings.length, 1);
      expect(readings.single.priorR0, 0.25);
      expect(readings.single.priorConfidence, 0.4);
      expect(readings.single.inDangerZone, isFalse);
      expect(readings.single.inDevelopmentZone, isFalse);
    });

    test('a zero-confidence prior counts as "no signal"', () {
      final readings = CognitiveReadingsAdapter.readingsFor(
        knowledgePointIds: ['kp-a'],
        priors: {'kp-a': prior('kp-a', confidence: 0)},
      );

      expect(readings, isEmpty);
    });

    test('a null diagnosis map means the layer did not run (priors only)', () {
      final readings = CognitiveReadingsAdapter.readingsFor(
        knowledgePointIds: ['kp-a', 'kp-b'],
        diagnosisByKnowledgePoint: null,
        priors: {'kp-b': prior('kp-b')},
      );

      expect(readings.length, 1);
      expect(readings.single.knowledgePointId, 'kp-b');
    });

    test('an unknown knowledge point is skipped, duplicates collapse', () {
      final readings = CognitiveReadingsAdapter.readingsFor(
        knowledgePointIds: ['kp-a', 'kp-a', '  ', 'kp-unknown'],
        diagnosisByKnowledgePoint: {'kp-a': BottleneckType.danger},
      );

      expect(readings.length, 1);
      expect(readings.single.knowledgePointId, 'kp-a');
    });

    test('diagnosis and prior on the same knowledge point merge', () {
      final readings = CognitiveReadingsAdapter.readingsFor(
        knowledgePointIds: ['kp-a'],
        diagnosisByKnowledgePoint: {'kp-a': BottleneckType.danger},
        priors: {'kp-a': prior('kp-a', r0: 0.1)},
      );

      expect(readings.single.inDangerZone, isTrue);
      expect(readings.single.priorR0, 0.1);
    });

    test('out-of-range values are clamped into 0..1', () {
      final readings = CognitiveReadingsAdapter.readingsFor(
        knowledgePointIds: ['kp-a', 'kp-b'],
        priors: {
          'kp-a': prior('kp-a', r0: 1.4, confidence: 2),
          'kp-b': prior('kp-b', r0: -0.5),
        },
      );

      expect(readings[0].priorR0, 1.0);
      expect(readings[0].priorConfidence, 1.0);
      expect(readings[1].priorR0, 0.0);
    });

    test('output order is by knowledge point id, not by input order', () {
      final readings = CognitiveReadingsAdapter.readingsFor(
        knowledgePointIds: ['kp-z', 'kp-a', 'kp-m'],
        diagnosisByKnowledgePoint: {
          'kp-z': BottleneckType.danger,
          'kp-a': BottleneckType.weak,
          'kp-m': BottleneckType.danger,
        },
      );

      expect(
        readings.map((reading) => reading.knowledgePointId).toList(),
        ['kp-a', 'kp-m', 'kp-z'],
      );
    });
  });

  group('forTaskKnowledgePoints', () {
    test('gathers ids from every task and deduplicates them', () {
      final readings = CognitiveReadingsAdapter.forTaskKnowledgePoints(
        taskKnowledgePoints: {
          'task-1': ['kp-a', 'kp-b'],
          'task-2': ['kp-b', 'kp-c'],
        },
        diagnosisByKnowledgePoint: {
          'kp-a': BottleneckType.danger,
          'kp-c': BottleneckType.weak,
        },
      );

      expect(
        readings.map((reading) => reading.knowledgePointId).toList(),
        ['kp-a', 'kp-c'],
      );
    });

    test('empty mapping yields no readings', () {
      expect(
        CognitiveReadingsAdapter.forTaskKnowledgePoints(),
        isEmpty,
      );
    });
  });
}

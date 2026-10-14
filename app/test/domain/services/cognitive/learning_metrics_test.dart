import 'package:flutter_test/flutter_test.dart';

import 'package:furnace/domain/services/cognitive/learning_metrics.dart';

RetentionSample sample(
  String card, {
  required int ms,
  required bool recalled,
  double? interval,
  double? predicted,
  String? knowledgePointId,
}) {
  return RetentionSample(
    cardStateId: card,
    knowledgePointId: knowledgePointId,
    reviewedAtMs: ms,
    recalled: recalled,
    intervalDays: interval,
    predictedR: predicted,
  );
}

void main() {
  group('recalledFromReview', () {
    test('objective verdict wins over every rating', () {
      expect(recalledFromReview(rating: 2, ratingFsrs: 4, correct: false), false);
      expect(recalledFromReview(rating: 0, ratingFsrs: 1, correct: true), true);
    });

    test('fsrs rating counts Good and Easy as recalled, Hard as not', () {
      expect(recalledFromReview(ratingFsrs: 4), true);
      expect(recalledFromReview(ratingFsrs: 3), true);
      expect(recalledFromReview(ratingFsrs: 2), false);
      expect(recalledFromReview(ratingFsrs: 1), false);
    });

    test('the legacy rating needs full remembered, not fuzzy', () {
      expect(recalledFromReview(rating: 2), true);
      expect(recalledFromReview(rating: 1), false);
      expect(recalledFromReview(rating: 0), false);
    });

    test('a log with no verdict at all is a bug, not a false', () {
      expect(() => recalledFromReview(), throwsArgumentError);
    });
  });

  group('withIntervals', () {
    test('the first review of a card has no interval, later ones do', () {
      const day = Duration.millisecondsPerDay;
      final out = withIntervals([
        sample('c1', ms: 3 * day, recalled: true),
        sample('c1', ms: 5 * day, recalled: false),
        sample('c2', ms: 9 * day, recalled: true),
      ]);

      expect(out, hasLength(3));
      final c1 = out.where((s) => s.cardStateId == 'c1').toList();
      expect(c1.first.intervalDays, isNull);
      expect(c1.last.intervalDays, 2.0);
      expect(out.where((s) => s.cardStateId == 'c2').single.intervalDays, isNull);
    });

    test('unsorted input is sorted before the gaps are measured', () {
      const day = Duration.millisecondsPerDay;
      final out = withIntervals([
        sample('c1', ms: 7 * day, recalled: true),
        sample('c1', ms: day, recalled: true),
      ]);

      expect(out.first.reviewedAtMs, day);
      expect(out.first.intervalDays, isNull);
      expect(out.last.intervalDays, 6.0);
    });

    test('two reviews in the same millisecond are an interval of zero', () {
      final out = withIntervals([
        sample('c1', ms: 1000, recalled: true),
        sample('c1', ms: 1000, recalled: false),
      ]);

      expect(out.last.intervalDays, 0.0);
    });
  });

  group('LearningMetrics.read', () {
    test('no samples at all is empty, and the bins still exist', () {
      final metrics = LearningMetrics.read(samples: const []);

      expect(metrics.isEmpty, isTrue);
      expect(metrics.retention, 0);
      expect(metrics.hasCalibration, isFalse);
      expect(metrics.brier, isNull);
      expect(metrics.ece, isNull);
      expect(metrics.buckets, hasLength(5));
      expect(metrics.bins, hasLength(5));
      expect(metrics.buckets.every((b) => b.samples == 0), isTrue);
      expect(metrics.bins.every((b) => b.samples == 0), isTrue);
    });

    test('every interval lands in its own bucket, and the first review counts', () {
      final metrics = LearningMetrics.read(
        samples: [
          sample('c1', ms: 1, recalled: true, interval: 0.5),
          sample('c1', ms: 2, recalled: true, interval: 2),
          sample('c1', ms: 3, recalled: false, interval: 5),
          sample('c1', ms: 4, recalled: true, interval: 10),
          sample('c1', ms: 5, recalled: true, interval: 60),
          sample('c1', ms: 6, recalled: false),
        ],
      );

      expect(metrics.reviewedCount, 6);
      expect(metrics.recalledCount, 4);
      expect(metrics.retention, closeTo(0.666667, 1e-6));
      expect(metrics.buckets.map((b) => b.samples), [1, 1, 1, 1, 1]);
      expect(metrics.buckets.map((b) => b.recalled), [1, 1, 0, 1, 1]);
      expect(metrics.buckets[2].retention, 0);
      expect(metrics.buckets.last.hiDays, double.infinity);
    });

    test('an interval exactly on an edge belongs to the upper bucket', () {
      final metrics = LearningMetrics.read(
        samples: [
          sample('c1', ms: 1, recalled: true, interval: 1),
          sample('c1', ms: 2, recalled: true, interval: 30),
        ],
      );

      expect(metrics.buckets[0].samples, 0);
      expect(metrics.buckets[1].samples, 1);
      expect(metrics.buckets[4].samples, 1);
    });

    test('calibration bins carry prediction, observation and gap', () {
      final metrics = LearningMetrics.read(
        samples: [
          sample('c1', ms: 1, recalled: true, interval: 1, predicted: 0.9),
          sample('c2', ms: 2, recalled: true, interval: 1, predicted: 0.9),
          sample('c3', ms: 3, recalled: false, interval: 1, predicted: 0.9),
          sample('c4', ms: 4, recalled: false, interval: 1, predicted: 0.1),
        ],
      );

      expect(metrics.calibratedCount, 4);
      expect(metrics.bins[0].samples, 1);
      expect(metrics.bins[0].meanPredictedR, closeTo(0.1, 1e-9));
      expect(metrics.bins[0].observed, 0);
      expect(metrics.bins[0].gap, closeTo(0.1, 1e-9));
      expect(metrics.bins[4].samples, 3);
      expect(metrics.bins[4].meanPredictedR, closeTo(0.9, 1e-9));
      expect(metrics.bins[4].observed, closeTo(0.666667, 1e-6));
      expect(metrics.bins[4].gap, closeTo(0.233333, 1e-6));
      expect(metrics.brier, closeTo(0.21, 1e-9));
      expect(metrics.ece, closeTo(0.2, 1e-9));
    });

    test('R == 1 closes the last bin, out-of-range values clamp', () {
      final metrics = LearningMetrics.read(
        samples: [
          sample('c1', ms: 1, recalled: true, interval: 1, predicted: 1.0),
          sample('c2', ms: 2, recalled: false, interval: 1, predicted: -0.2),
          sample('c3', ms: 3, recalled: true, interval: 1, predicted: 1.5),
        ],
      );

      expect(metrics.bins.last.samples, 2);
      expect(metrics.bins.first.samples, 1);
      expect(metrics.bins.first.meanPredictedR, 0);
      expect(metrics.bins.last.meanPredictedR, 1.0);
    });

    test('a sample with no interval still counts towards retention', () {
      final metrics = LearningMetrics.read(
        samples: [sample('c1', ms: 1, recalled: true)],
      );

      expect(metrics.reviewedCount, 1);
      expect(metrics.retention, 1);
      expect(metrics.buckets.every((b) => b.samples == 0), isTrue);
    });

    test('nonsense bucket or bin settings are rejected, not repaired', () {
      expect(
        () => LearningMetrics.read(samples: const [], calibrationBinCount: 0),
        throwsArgumentError,
      );
      expect(
        () => LearningMetrics.read(samples: const [], bucketEdges: const [1]),
        throwsArgumentError,
      );
    });
  });

  group('json', () {
    test('the schema is pinned and an unbounded bucket says so with null', () {
      final json = LearningMetrics.read(
        samples: [sample('c1', ms: 1, recalled: true, interval: 1)],
      ).toJson();

      expect(json['schema'], 'mindnet.learning_metrics/1');
      expect(json['calibrated'], false);
      expect(json['retention'], 1.0);
      expect(json['brier'], isNull);
      final buckets = json['buckets']! as List<Object?>;
      expect((buckets.last! as Map)['hi_days'], isNull);
      expect((buckets.first! as Map)['hi_days'], 1.0);
      expect(json['bins'], hasLength(5));
    });

    test('a sample keeps null interval and null prediction as null', () {
      final json = sample('c1', ms: 5, recalled: false).toJson();

      expect(json['interval_days'], isNull);
      expect(json['predicted_r'], isNull);
      expect(json['card_state_id'], 'c1');
      expect(json['recalled'], false);
    });
  });
}

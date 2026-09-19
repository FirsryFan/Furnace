import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:knowflow/domain/services/srs/fsrs_scheduler.dart';

void main() {
  final now = DateTime.utc(2026, 9, 7, 12);

  group('FSRS-6 long-term scheduler basics', () {
    test('new card rated Good: init stability/difficulty and due in 3 days',
        () {
      final result = FsrsScheduler.schedule(
        memory: null,
        lastReview: now,
        now: now,
        rating: FsrsRating.good,
      );
      // S0(Good) = w[2] = 2.3065 -> raw 2 days, raised to hard+1 = 3 by the
      // monotonic family constraint.
      expect(result.scheduledDays, 3);
      expect(result.dueAt, now.add(const Duration(days: 3)));
      expect(result.memory.stability, closeTo(2.3065, 1e-6));
      // D0(Good) = w4 - e^((G-1)*w5) + 1 = w4 - e^(2*w5) + 1.
      final expectedD = 6.4133 - math.exp(2 * 0.8334) + 1;
      expect(result.memory.difficulty, closeTo(expectedD, 1e-6));
      expect(result.lapses, 0);
    });

    test('new card rated Again: 1 day, no lapse, S0 = w[0]', () {
      final result = FsrsScheduler.schedule(
        memory: null,
        lastReview: now,
        now: now,
        rating: FsrsRating.again,
      );
      expect(result.scheduledDays, 1);
      expect(result.lapses, 0);
      expect(result.memory.stability, closeTo(0.212, 1e-6));
    });

    test('new card rated Easy: longest first interval (w[3])', () {
      final result = FsrsScheduler.schedule(
        memory: null,
        lastReview: now,
        now: now,
        rating: FsrsRating.easy,
      );
      expect(result.scheduledDays, 8); // S0(Easy) = 8.2956
      expect(result.memory.stability, closeTo(8.2956, 1e-6));
    });

    test('Again on a mature card lapses and lowers stability', () {
      // Simulate a card 10 days after a Good review.
      final afterGood = FsrsScheduler.schedule(
        memory: null,
        lastReview: now,
        now: now,
        rating: FsrsRating.good,
      );
      final later = now.add(const Duration(days: 10));
      final again = FsrsScheduler.schedule(
        memory: afterGood.memory,
        lastReview: now,
        now: later,
        rating: FsrsRating.again,
      );
      expect(again.lapses, 1);
      expect(again.scheduledDays, 1);
      expect(again.memory.stability, lessThan(afterGood.memory.stability));
      // In FSRS-6 a failed recall raises difficulty (toward "harder").
      expect(again.memory.difficulty, greaterThan(afterGood.memory.difficulty));
      expect(again.memory.difficulty, lessThanOrEqualTo(10));
    });

    test('Good on a mature card raises stability', () {
      final first = FsrsScheduler.schedule(
        memory: null,
        lastReview: now,
        now: now,
        rating: FsrsRating.good,
      );
      final later = now.add(const Duration(days: 5));
      final second = FsrsScheduler.schedule(
        memory: first.memory,
        lastReview: now,
        now: later,
        rating: FsrsRating.good,
      );
      expect(second.memory.stability, greaterThan(first.memory.stability));
      expect(second.scheduledDays, greaterThan(1));
      expect(second.lapses, 0);
    });

    test('forgetting curve: R(0)=1 and decays with elapsed time', () {
      final w = const FsrsParameters().w;
      expect(
        FsrsScheduler.forgettingCurve(
            w: w, elapsedDays: 0, stability: 5),
        closeTo(1.0, 1e-6),
      );
      final r5 = FsrsScheduler.forgettingCurve(
          w: w, elapsedDays: 5, stability: 5);
      expect(r5, lessThan(1.0));
      expect(r5, greaterThan(0.0));
      final r10 = FsrsScheduler.forgettingCurve(
          w: w, elapsedDays: 10, stability: 5);
      expect(r10, lessThan(r5));
    });
  });

  group('monotonic ordering over simulated history', () {
    test('intervals stay ordered again <= hard <= good <= easy', () {
      FsrsMemory? memory;
      var last = now;
      // Random-ish deterministic walk of 12 reviews at irregular gaps.
      final seeds = <double, DateTime>{
        for (var i = 0; i < 12; i++)
          i.toDouble(): last.add(Duration(days: (i % 5) + (i % 3 == 0 ? 7 : 1))),
      };
      for (final entry in seeds.entries) {
        final reviewTime = entry.value;
        final rating = FsrsRating.values[entry.key.toInt() % 3 + 1];
        final result = FsrsScheduler.schedule(
          memory: memory,
          lastReview: last,
          now: reviewTime,
          rating: rating,
        );
        expect(result.scheduledDays, greaterThanOrEqualTo(1));
        expect(result.memory.stability, greaterThan(0));
        expect(result.memory.difficulty, inInclusiveRange(1, 10));
        // Interval of the same grade is monotone in memory quality.
        memory = result.memory;
        last = reviewTime;
      }
    });

    test('default weight table is a valid 21-length FSRS-6 table', () {
      final w = FsrsScheduler.normalizeWeights(
          const FsrsParameters().w);
      expect(w, hasLength(21));
      expect(w[20], closeTo(0.1542, 1e-9));
    });

    test('17-length (FSRS-5) tables are migrated to 21', () {
      const fsrs5 = [
        0.4072, 1.1829, 3.1262, 15.4722, 7.2102, 0.5316, 1.0651, 0.0234, 1.616,
        0.1544, 1.0824, 1.9813, 0.0953, 0.2975, 2.2042, 0.2407, 2.9466,
      ];
      final w = FsrsScheduler.normalizeWeights(fsrs5);
      expect(w, hasLength(21));
      expect(w[20], closeTo(0.1542, 1e-9));
    });
  });
}

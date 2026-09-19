import 'package:flutter_test/flutter_test.dart';
import 'package:knowflow/domain/services/srs/sm2_scheduler.dart';

void main() {
  final now = DateTime(2026, 8, 19, 12);

  group('Sm2Scheduler', () {
    test('new card is due immediately', () {
      const state = SrsState();
      expect(Sm2Scheduler.isDue(state, now), isTrue);
    });

    test('first remembered review schedules 1 day later', () {
      const state = SrsState();
      final result = Sm2Scheduler.review(
        current: state,
        rating: SrsRating.remembered,
        now: now,
      );

      expect(result.state.repetitions, 1);
      expect(result.state.intervalDays, 1);
      expect(result.nextDueAt, now.add(const Duration(days: 1)));
    });

    test('second remembered review schedules 6 days later', () {
      const state = SrsState(repetitions: 1, intervalDays: 1);
      final result = Sm2Scheduler.review(
        current: state,
        rating: SrsRating.remembered,
        now: now,
      );

      expect(result.state.repetitions, 2);
      expect(result.state.intervalDays, 6);
    });

    test('forgot resets repetitions', () {
      const state = SrsState(
        repetitions: 5,
        intervalDays: 30,
        easeFactor: 2.5,
      );
      final result = Sm2Scheduler.review(
        current: state,
        rating: SrsRating.forgot,
        now: now,
      );

      expect(result.state.repetitions, 0);
      expect(result.state.intervalDays, 1);
    });
  });
}

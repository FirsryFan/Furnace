import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/time/actual_time.dart';

void main() {
  final start = DateTime(2026, 9, 8, 20);

  group('actual duration is computed from two stamps, never timed', () {
    test('rounded down to whole minutes', () {
      final record = ActualTime.compute(
        startedAt: start,
        completedAt: start.add(const Duration(minutes: 30, seconds: 59)),
        estimateMinutes: 30,
      );
      expect(record.actualMinutes, 30);
      expect(record.suspicious, isFalse);
      expect(record.includeInModel, isTrue);
    });

    test('a completion before the start clamps to zero', () {
      final record = ActualTime.compute(
        startedAt: start,
        completedAt: start.subtract(const Duration(minutes: 5)),
      );
      expect(record.actualMinutes, 0);
      expect(record.suspicious, isFalse);
    });

    test('no estimate means nothing can be suspicious', () {
      final record = ActualTime.compute(
        startedAt: start,
        completedAt: start.add(const Duration(hours: 5)),
      );
      expect(record.actualMinutes, 300);
      expect(record.suspicious, isFalse);
      expect(record.includeInModel, isTrue);
    });
  });

  group('anomaly guard keeps "forgot to stop it" out of the model', () {
    test('far beyond estimate and long enough is suspicious by default', () {
      final record = ActualTime.compute(
        startedAt: start,
        completedAt: start.add(const Duration(minutes: 100)),
        estimateMinutes: 20,
      );
      expect(record.suspicious, isTrue);
      expect(record.includeInModel, isFalse);
    });

    test('over the multiplier but short is NOT suspicious (both required)', () {
      // 16 min vs estimate 5 -> over 3x, but under the 30 min floor.
      final record = ActualTime.compute(
        startedAt: start,
        completedAt: start.add(const Duration(minutes: 16)),
        estimateMinutes: 5,
      );
      expect(record.suspicious, isFalse);
      expect(record.includeInModel, isTrue);
    });

    test('long but within multiplier is NOT suspicious', () {
      final record = ActualTime.compute(
        startedAt: start,
        completedAt: start.add(const Duration(minutes: 45)),
        estimateMinutes: 40,
      );
      expect(record.suspicious, isFalse);
    });

    test('the user can override the verdict per record', () {
      final included = ActualTime.compute(
        startedAt: start,
        completedAt: start.add(const Duration(minutes: 100)),
        estimateMinutes: 20,
        userOverride: true,
      );
      expect(included.suspicious, isTrue);
      expect(included.includeInModel, isTrue);

      final excluded = ActualTime.compute(
        startedAt: start,
        completedAt: start.add(const Duration(minutes: 30)),
        estimateMinutes: 30,
        userOverride: false,
      );
      expect(excluded.suspicious, isFalse);
      expect(excluded.includeInModel, isFalse);
    });
  });
}

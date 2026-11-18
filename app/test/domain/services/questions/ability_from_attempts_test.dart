import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/questions/ability_from_attempts.dart';

void main() {
  test('能力聚合：只保留样本 >=3，按正确率升序，未知能力丢弃', () {
    final stats = aggregateAbilityStats(const <AbilityAttempt>[
      AbilityAttempt(capabilityJson: '["A1"]', isCorrect: false),
      AbilityAttempt(capabilityJson: '["A1"]', isCorrect: false),
      AbilityAttempt(capabilityJson: '["A1"]', isCorrect: true),
      AbilityAttempt(capabilityJson: '["A2"]', isCorrect: true),
      AbilityAttempt(capabilityJson: '["A2"]', isCorrect: true),
      AbilityAttempt(capabilityJson: '["A2"]', isCorrect: true),
      AbilityAttempt(capabilityJson: '["A9"]', isCorrect: false),
      AbilityAttempt(capabilityJson: '["A9"]', isCorrect: true),
      AbilityAttempt(capabilityJson: '["A9"]', isCorrect: true),
      AbilityAttempt(capabilityJson: 'not-json', isCorrect: true),
      AbilityAttempt(capabilityJson: '["A99"]', isCorrect: true),
      AbilityAttempt(capabilityJson: null, isCorrect: true),
    ]);
    expect(stats.map((e) => e.code), ['A1', 'A9', 'A2']);
    expect(stats.first.accuracy, closeTo(1 / 3, 0.001));
    expect(stats[1].accuracy, closeTo(2 / 3, 0.001));
    expect(stats[2].accuracy, closeTo(1, 0.001));
  });

  test('能力聚合：没有样本返回空表', () {
    expect(aggregateAbilityStats(const []), isEmpty);
  });
}

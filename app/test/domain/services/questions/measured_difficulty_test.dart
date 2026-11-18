import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/questions/measured_difficulty.dart';

void main() {
  test('少于 3 次样本不给实测难度', () {
    expect(
      measuredDifficultyFromAttempts(
        priorDifficulty: 6,
        attempts: 2,
        correct: 2,
      ),
      isNull,
    );
  });

  test('全对降低难度、全错提高难度，并钳到 1..10', () {
    final easy = measuredDifficultyFromAttempts(
      priorDifficulty: 6,
      attempts: 4,
      correct: 4,
    )!;
    final hard = measuredDifficultyFromAttempts(
      priorDifficulty: 6,
      attempts: 4,
      correct: 0,
    )!;
    expect(easy, lessThan(6));
    expect(hard, greaterThan(6));
    expect(easy, inInclusiveRange(1, 10));
    expect(hard, inInclusiveRange(1, 10));
  });

  test('没有先验时按 5 起算；正确率 0.5 不调整', () {
    expect(
      measuredDifficultyFromAttempts(
        priorDifficulty: null,
        attempts: 4,
        correct: 2,
      ),
      closeTo(5, 0.001),
    );
  });
}

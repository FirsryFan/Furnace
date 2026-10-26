import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/cognitive/ability_assessment.dart';

/// 运行期才确定的分数：用来故意构造非法 AbilityScore，避免 const 构造在编译期就报错。
double _runtimeScore(num value) => value.toDouble();

/// 所有评分函数的共同不变量：必须是 double 且落在 0–100。
void _expectScoreInRange(double score) {
  expect(score, isA<double>());
  expect(score, greaterThanOrEqualTo(0));
  expect(score, lessThanOrEqualTo(100));
}

void main() {
  group('AbilityKey.fromCode：编码双向与未知编码', () {
    test('四个维度与落库编码', () {
      expect(AbilityKey.values, hasLength(4));
      expect(AbilityKey.reactionSpeed.code, 'reaction_speed');
      expect(AbilityKey.workingMemory.code, 'working_memory');
      expect(AbilityKey.patternRecognition.code, 'pattern_recognition');
      expect(AbilityKey.attentionStability.code, 'attention_stability');
    });

    test('每个 code 都能 fromCode 找回原维度', () {
      for (final key in AbilityKey.values) {
        expect(AbilityKey.fromCode(key.code), key);
      }
    });

    test('未知编码返回 null（不猜、不抛）', () {
      expect(AbilityKey.fromCode('iq'), isNull);
      expect(AbilityKey.fromCode('reaction-spped'), isNull);
      expect(AbilityKey.fromCode('workingmemory'), isNull);
    });

    test('空白编码 null；两端空白容错；大小写敏感', () {
      expect(AbilityKey.fromCode(''), isNull);
      expect(AbilityKey.fromCode('   '), isNull);
      expect(AbilityKey.fromCode(' reaction_speed '), AbilityKey.reactionSpeed);
      expect(AbilityKey.fromCode('REACTION_SPEED'), isNull);
    });
  });

  group('medianReactionMillis：中位数与无效样本', () {
    test('空表 → 0', () {
      expect(medianReactionMillis(const <int>[]), 0);
    });

    test('单个样本 → 原值', () {
      expect(medianReactionMillis(const <int>[321]), 321);
    });

    test('奇数个取正中间', () {
      expect(medianReactionMillis(const <int>[500, 200, 900]), 500);
    });

    test('偶数个取中间两个的平均', () {
      expect(medianReactionMillis(const <int>[400, 200]), 300);
    });

    test('偶数个平均四舍五入（.5 进位）', () {
      expect(medianReactionMillis(const <int>[250, 251]), 251);
      expect(medianReactionMillis(const <int>[200, 201]), 201);
    });

    test('负数样本忽略', () {
      expect(medianReactionMillis(const <int>[-1, 300, -50, 500]), 400);
    });

    test('全是负数 → 0（没有有效读数）', () {
      expect(medianReactionMillis(const <int>[-300, -100]), 0);
    });

    test('0ms 是有效样本', () {
      expect(medianReactionMillis(const <int>[0, 500]), 250);
    });
  });

  group('scoreReactionSpeed：反应速度（250ms 满分 / 800ms 零分）', () {
    test('空表与全负样本 → 0', () {
      expect(scoreReactionSpeed(const <int>[]), 0);
      expect(scoreReactionSpeed(const <int>[-10, -200]), 0);
    });

    test('250ms → 100，更快仍 100', () {
      expect(scoreReactionSpeed(const <int>[250]), 100);
      expect(scoreReactionSpeed(const <int>[200]), 100);
      expect(scoreReactionSpeed(const <int>[1]), 100);
    });

    test('800ms → 0，更慢仍 0', () {
      expect(scoreReactionSpeed(const <int>[800]), 0);
      expect(scoreReactionSpeed(const <int>[799]), closeTo(0.1818, 0.0001));
      expect(scoreReactionSpeed(const <int>[1000]), 0);
    });

    test('525ms → 50（(800-525)/550*100）', () {
      expect(scoreReactionSpeed(const <int>[525]), 50);
    });

    test('中间线性', () {
      expect(scoreReactionSpeed(const <int>[300]), closeTo(90.909, 0.01));
      expect(scoreReactionSpeed(const <int>[700]), closeTo(18.1818, 0.01));
    });

    test('多样本先取中位再换算', () {
      expect(scoreReactionSpeed(const <int>[200, 900]), closeTo(45.4545, 0.01));
    });

    test('任意样本都落在 0–100', () {
      for (final samples in const <List<int>>[
        <int>[],
        <int>[1],
        <int>[250],
        <int>[525, 900],
        <int>[-5, 1000],
      ]) {
        _expectScoreInRange(scoreReactionSpeed(samples));
      }
    });
  });

  group('scoreWorkingMemory：工作记忆（3 跨度零分 / 9 跨度满分）', () {
    test('≤3 → 0（含 0 与负数）', () {
      expect(scoreWorkingMemory(3), 0);
      expect(scoreWorkingMemory(2), 0);
      expect(scoreWorkingMemory(0), 0);
      expect(scoreWorkingMemory(-1), 0);
    });

    test('≥9 → 100', () {
      expect(scoreWorkingMemory(9), 100);
      expect(scoreWorkingMemory(12), 100);
    });

    test('6 → 50', () {
      expect(scoreWorkingMemory(6), 50);
    });

    test('4 → 1/6，8 → 5/6', () {
      expect(scoreWorkingMemory(4), closeTo(16.6667, 0.01));
      expect(scoreWorkingMemory(8), closeTo(83.3333, 0.01));
    });

    test('任意跨度都落在 0–100', () {
      for (var span = -3; span <= 15; span++) {
        _expectScoreInRange(scoreWorkingMemory(span));
      }
    });
  });

  group('scorePatternRecognition：模式识别（正确率 70 + 速度 30）', () {
    test('total ≤0 → 0（不猜）', () {
      expect(
        scorePatternRecognition(correct: 0, total: 0, medianMillis: 1000),
        0,
      );
      expect(
        scorePatternRecognition(correct: 5, total: -1, medianMillis: 1000),
        0,
      );
    });

    test('全对且 1500ms → 100', () {
      expect(
        scorePatternRecognition(correct: 10, total: 10, medianMillis: 1500),
        100,
      );
    });

    test('全对且 6000ms → 70（只剩正确率分）', () {
      expect(
        scorePatternRecognition(correct: 10, total: 10, medianMillis: 6000),
        70,
      );
    });

    test('全对且 3750ms → 85（正确率 70 + 速度 15）', () {
      expect(
        scorePatternRecognition(correct: 10, total: 10, medianMillis: 3750),
        85,
      );
    });

    test('全错且 1500ms → 30（只有速度分）', () {
      expect(
        scorePatternRecognition(correct: 0, total: 10, medianMillis: 1500),
        30,
      );
    });

    test('全错且 6000ms → 0', () {
      expect(
        scorePatternRecognition(correct: 0, total: 10, medianMillis: 6000),
        0,
      );
    });

    test('半对且中速 → 50', () {
      expect(
        scorePatternRecognition(correct: 5, total: 10, medianMillis: 3750),
        50,
      );
    });

    test('正确数越界先夹到 0–1', () {
      expect(
        scorePatternRecognition(correct: 10, total: 5, medianMillis: 1500),
        100,
      );
      expect(
        scorePatternRecognition(correct: -2, total: 5, medianMillis: 1500),
        30,
      );
    });

    test('负的中位用时按最快算', () {
      expect(
        scorePatternRecognition(correct: 10, total: 10, medianMillis: -5),
        100,
      );
    });

    test('任意组合都落在 0–100', () {
      for (final correct in const <int>[-1, 0, 3, 10, 20]) {
        for (final median in const <int>[0, 1500, 3750, 6000, 9000]) {
          _expectScoreInRange(
            scorePatternRecognition(
              correct: correct,
              total: 10,
              medianMillis: median,
            ),
          );
        }
      }
    });
  });

  group('scoreAttentionStability：注意稳定性（灵敏度 + 特异度）', () {
    test('全命中且没错报 → 100', () {
      expect(
        scoreAttentionStability(
          hits: 10,
          misses: 0,
          falseAlarms: 0,
          targets: 10,
          nonTargets: 10,
        ),
        100,
      );
    });

    test('全漏（灵敏度 0）且没错报 → 50', () {
      expect(
        scoreAttentionStability(
          hits: 0,
          misses: 10,
          falseAlarms: 0,
          targets: 10,
          nonTargets: 10,
        ),
        50,
      );
    });

    test('targets ≤0 或 nonTargets ≤0 → 0', () {
      expect(
        scoreAttentionStability(
          hits: 0,
          misses: 0,
          falseAlarms: 0,
          targets: 0,
          nonTargets: 10,
        ),
        0,
      );
      expect(
        scoreAttentionStability(
          hits: 0,
          misses: 0,
          falseAlarms: 0,
          targets: -3,
          nonTargets: 10,
        ),
        0,
      );
      expect(
        scoreAttentionStability(
          hits: 0,
          misses: 0,
          falseAlarms: 0,
          targets: 10,
          nonTargets: 0,
        ),
        0,
      );
    });

    test('全错报（特异度 0）且全命中 → 50', () {
      expect(
        scoreAttentionStability(
          hits: 10,
          misses: 0,
          falseAlarms: 10,
          targets: 10,
          nonTargets: 10,
        ),
        50,
      );
    });

    test('命中数越界先夹到 1', () {
      expect(
        scoreAttentionStability(
          hits: 15,
          misses: 0,
          falseAlarms: 0,
          targets: 10,
          nonTargets: 10,
        ),
        100,
      );
    });

    test('错报数越界先夹到 0', () {
      expect(
        scoreAttentionStability(
          hits: 10,
          misses: 0,
          falseAlarms: 20,
          targets: 10,
          nonTargets: 10,
        ),
        50,
      );
    });

    test('负命中数夹到 0', () {
      expect(
        scoreAttentionStability(
          hits: -5,
          misses: 10,
          falseAlarms: 0,
          targets: 10,
          nonTargets: 10,
        ),
        50,
      );
    });

    test('misses 不进入公式（只保留读数）', () {
      final fewMisses = scoreAttentionStability(
        hits: 8,
        misses: 2,
        falseAlarms: 1,
        targets: 10,
        nonTargets: 20,
      );
      final manyMisses = scoreAttentionStability(
        hits: 8,
        misses: 200,
        falseAlarms: 1,
        targets: 10,
        nonTargets: 20,
      );
      expect(fewMisses, manyMisses);
      expect(fewMisses, closeTo(87.5, 0.001));
    });

    test('任意组合都落在 0–100', () {
      for (final hits in const <int>[-2, 0, 5, 10, 15]) {
        for (final falseAlarms in const <int>[-1, 0, 3, 10]) {
          _expectScoreInRange(
            scoreAttentionStability(
              hits: hits,
              misses: 0,
              falseAlarms: falseAlarms,
              targets: 10,
              nonTargets: 10,
            ),
          );
        }
      }
    });
  });

  group('AbilityScore：构造校验与 metrics', () {
    test('合法构造：字段原样保存、metrics 默认为空', () {
      const score = AbilityScore(key: AbilityKey.workingMemory, score: 50);
      expect(score.key, AbilityKey.workingMemory);
      expect(score.score, 50);
      expect(score.metrics, isEmpty);
    });

    test('metrics 可携带原始读数', () {
      const score = AbilityScore(
        key: AbilityKey.patternRecognition,
        score: 85,
        metrics: <String, Object?>{
          'correct': 8,
          'total': 10,
          'medianMillis': 3750,
        },
      );
      expect(score.metrics['correct'], 8);
      expect(score.metrics['medianMillis'], 3750);
    });

    test('0 与 100 都是合法边界', () {
      expect(
        const AbilityScore(key: AbilityKey.reactionSpeed, score: 0).score,
        0,
      );
      expect(
        const AbilityScore(key: AbilityKey.reactionSpeed, score: 100).score,
        100,
      );
    });

    test('101 分触发 assert', () {
      expect(
        () => AbilityScore(
          key: AbilityKey.reactionSpeed,
          score: _runtimeScore(101),
        ),
        throwsAssertionError,
      );
    });

    test('负分触发 assert', () {
      expect(
        () => AbilityScore(
          key: AbilityKey.attentionStability,
          score: _runtimeScore(-1),
        ),
        throwsAssertionError,
      );
    });
  });

  group('确定性与空输入', () {
    test('同一输入两次调用结果完全相同', () {
      const samples = <int>[250, 333, 900];
      expect(scoreReactionSpeed(samples), scoreReactionSpeed(samples));
      expect(medianReactionMillis(samples), medianReactionMillis(samples));
      expect(scoreWorkingMemory(6), scoreWorkingMemory(6));
      expect(
        scorePatternRecognition(correct: 7, total: 10, medianMillis: 2800),
        scorePatternRecognition(correct: 7, total: 10, medianMillis: 2800),
      );
      expect(
        scoreAttentionStability(
          hits: 7,
          misses: 3,
          falseAlarms: 2,
          targets: 10,
          nonTargets: 20,
        ),
        scoreAttentionStability(
          hits: 7,
          misses: 3,
          falseAlarms: 2,
          targets: 10,
          nonTargets: 20,
        ),
      );
    });

    test('空输入不抛、统一返回 0', () {
      expect(scoreReactionSpeed(const <int>[]), 0);
      expect(medianReactionMillis(const <int>[]), 0);
      expect(
        scorePatternRecognition(correct: 0, total: 0, medianMillis: 0),
        0,
      );
      expect(
        scoreAttentionStability(
          hits: 0,
          misses: 0,
          falseAlarms: 0,
          targets: 0,
          nonTargets: 0,
        ),
        0,
      );
    });
  });
}

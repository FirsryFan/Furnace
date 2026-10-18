import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/paper/question_quality.dart';
import 'package:furnace/domain/services/scheduling/domain_balance.dart';

/// MindNet 有效性质量投影的纯逻辑测试。
///
/// 这里钉的是**口径**，不是"这些数已经标定"：
/// 公式与 `DomainBalanceRanker._effectivenessOf` 同一份；
/// `EffectivenessTuning` 的 0.5 / 0.35 / 0.20 / 0.30 与
/// [kNeutralQuestionQuality] 都是**未标定默认值**，标定之后只改定义处，测试跟着改。
void main() {
  KnowledgePointReading reading(
    String id, {
    bool danger = false,
    bool development = false,
    double? r0,
    double confidence = 0,
  }) =>
      KnowledgePointReading(
        knowledgePointId: id,
        inDangerZone: danger,
        inDevelopmentZone: development,
        priorR0: r0,
        priorConfidence: confidence,
      );

  group('单知识点有效性（公式与 domain_balance 同口径）', () {
    test('没有任何读数 → 中性 0.5（不惩罚"不知道"）', () {
      expect(kNeutralQuestionQuality, 0.5);
      expect(
        questionQuality(
          knowledgePointIds: const ['kp-a'],
          readings: const {},
        ),
        kNeutralQuestionQuality,
      );
      // 空 id 列表 / 读不到的 id 也是中性。
      expect(
        questionQuality(
          knowledgePointIds: const [],
          readings: {'kp-a': reading('kp-a', danger: true)},
        ),
        kNeutralQuestionQuality,
      );
      expect(
        questionQuality(
          knowledgePointIds: const ['kp-missing'],
          readings: {'kp-a': reading('kp-a', danger: true)},
        ),
        kNeutralQuestionQuality,
      );
    });

    test('危险区 → 0.85；发展区 → 0.70；两者都有 → 1.0（clamp）', () {
      expect(
        questionQuality(
          knowledgePointIds: const ['kp-a'],
          readings: {'kp-a': reading('kp-a', danger: true)},
        ),
        closeTo(0.85, 1e-9),
      );
      expect(
        questionQuality(
          knowledgePointIds: const ['kp-a'],
          readings: {'kp-a': reading('kp-a', development: true)},
        ),
        closeTo(0.70, 1e-9),
      );
      // 0.5 + 0.35 + 0.20 = 1.05 → 夹到 1.0。
      expect(
        questionQuality(
          knowledgePointIds: const ['kp-a'],
          readings: {
            'kp-a': reading('kp-a', danger: true, development: true),
          },
        ),
        1.0,
      );
    });

    test('先验项：R0 越弱、置信度越高，质量分越高', () {
      // 0.5 + 0.30 * (1 - 0.2) * 1 = 0.74
      expect(
        questionQuality(
          knowledgePointIds: const ['kp-a'],
          readings: {'kp-a': reading('kp-a', r0: 0.2, confidence: 1)},
        ),
        closeTo(0.74, 1e-9),
      );
      // 0.5 + 0.30 * (1 - 0.9) * 1 = 0.53
      expect(
        questionQuality(
          knowledgePointIds: const ['kp-a'],
          readings: {'kp-a': reading('kp-a', r0: 0.9, confidence: 1)},
        ),
        closeTo(0.53, 1e-9),
      );
      // 置信度 0 → 先验项不参与。
      expect(
        questionQuality(
          knowledgePointIds: const ['kp-a'],
          readings: {'kp-a': reading('kp-a', r0: 0.1, confidence: 0)},
        ),
        closeTo(0.5, 1e-9),
      );
      // 没有 R0 → 先验项不参与。
      expect(
        questionQuality(
          knowledgePointIds: const ['kp-a'],
          readings: {'kp-a': reading('kp-a', confidence: 1)},
        ),
        closeTo(0.5, 1e-9),
      );
    });

    test('多知识点取 max（只要有一个现在最该练就值得推荐）', () {
      final quality = questionQuality(
        knowledgePointIds: const ['kp-a', 'kp-b', 'kp-c'],
        readings: {
          'kp-a': reading('kp-a'),
          'kp-b': reading('kp-b', development: true),
        },
      );
      expect(quality, closeTo(0.70, 1e-9));
    });

    test('空白 id 跳过，不抛异常', () {
      expect(
        questionQuality(
          knowledgePointIds: const ['', '  ', ' kp-a '],
          readings: {'kp-a': reading('kp-a', danger: true)},
        ),
        closeTo(0.85, 1e-9),
      );
    });

    test('自定义 tuning 生效（标定后只改这一处）', () {
      const tuning = EffectivenessTuning(
        neutral: 0.2,
        dangerBoost: 0.1,
        developmentBoost: 0.15,
        priorWeight: 1.0,
      );
      expect(
        questionQuality(
          knowledgePointIds: const ['kp-a'],
          readings: {'kp-a': reading('kp-a', danger: true)},
          tuning: tuning,
        ),
        closeTo(0.3, 1e-9),
      );
      expect(
        effectivenessFromReading(
          reading('kp-a', r0: 0, confidence: 1),
          tuning,
        ),
        closeTo(1.0, 1e-9),
      );
    });

    test('确定性：同一输入重复调用结果一致', () {
      final a = questionQuality(
        knowledgePointIds: const ['kp-a', 'kp-b'],
        readings: {
          'kp-a': reading('kp-a', r0: 0.4, confidence: 0.5),
          'kp-b': reading('kp-b', danger: true),
        },
      );
      final b = questionQuality(
        knowledgePointIds: const ['kp-a', 'kp-b'],
        readings: {
          'kp-a': reading('kp-a', r0: 0.4, confidence: 0.5),
          'kp-b': reading('kp-b', danger: true),
        },
      );
      expect(a, b);
      expect(a, greaterThan(0.5));
    });
  });
}

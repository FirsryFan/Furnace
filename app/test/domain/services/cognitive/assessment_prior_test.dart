import 'package:flutter_test/flutter_test.dart';

import 'package:furnace/domain/services/cognitive/assessment_prior.dart';

/// 测评先验层：只测**算法契约**，不碰数据库/UI。
///
/// 数值都是显式选定的粗映射（`AssessmentPrior` 的常数），所以这里钉住具体
/// 数字——改映射就该改测试，而不是让先验悄悄漂移。
void main() {
  group('evidence validation', () {
    test('自评超出 0–5 直接报错，而不是被钳掉', () {
      expect(
        () => AssessmentPrior.read(
          evidence: const [
            AssessmentEvidence(knowledgePointId: 'kp1', selfRating: 6),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => AssessmentPrior.read(
          evidence: const [
            AssessmentEvidence(knowledgePointId: 'kp1', selfRating: -1),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('空知识点 id 报错', () {
      expect(
        () => AssessmentPrior.read(
          evidence: const [
            AssessmentEvidence(knowledgePointId: '   ', selfRating: 3),
          ],
        ),
        throwsArgumentError,
      );
    });
  });

  group('no signal', () {
    test('既没自评也没抽检：不产出先验，只记账', () {
      final reading = AssessmentPrior.read(
        evidence: const [
          AssessmentEvidence(knowledgePointId: 'kp1', elapsedMs: 4200),
        ],
      );

      expect(reading.isEmpty, isTrue);
      expect(reading.estimates, isEmpty);
      expect(reading.ignoredCount, 1);
      expect(reading.judgedCount, 0);
      expect(reading.calibrationBias, 0);
    });

    test('空输入就是 empty 读数', () {
      final reading = AssessmentPrior.read(evidence: const []);
      expect(reading.isEmpty, isTrue);
      expect(reading.toJson()['schema'], AssessmentPriorReading.schema);
      expect(reading.toJson()['estimates'], isEmpty);
    });
  });

  group('self report only', () {
    test('只有自评：R0 由流畅度给，难度留空，置信度低', () {
      final reading = AssessmentPrior.read(
        evidence: const [
          AssessmentEvidence(knowledgePointId: 'kp1', selfRating: 4),
        ],
      );

      final e = reading.estimates.single;
      expect(e.fluency, 0.8);
      expect(e.r0, closeTo(0.77, 1e-9)); // 0.45 + 0.40 × 0.8
      expect(e.difficulty, isNull, reason: '没有抽检就不该编一个难度');
      expect(e.n, 1);
      expect(e.confidence, closeTo(0.25, 1e-9)); // 1 / (1 + 3)
      expect(e.basis, ['self:4']);
      expect(reading.calibrationBias, 0);
      expect(reading.judgedCount, 0);
      expect(reading.ignoredCount, 0);
    });
  });

  group('calibration bias', () {
    test('高自评 + 全错：压低 R0、偏置为正、修正后流畅度归零', () {
      final reading = AssessmentPrior.read(
        evidence: const [
          AssessmentEvidence(
            knowledgePointId: 'kp1',
            selfRating: 5,
            objectiveResults: [false, false, false],
          ),
        ],
      );

      final e = reading.estimates.single;
      expect(reading.calibrationBias, closeTo(1.0, 1e-9));
      expect(reading.judgedCount, 1);
      expect(e.fluency, 0.0, reason: '自评 1.0 减掉 1.0 的高估');
      expect(e.r0, closeTo(0.35, 1e-9), reason: '有抽检时以正确率定 R0');
      expect(e.difficulty, closeTo(9.0, 1e-9)); // 3 + 6 × 100% 错误率
      expect(e.confidence, closeTo(0.571429, 1e-6)); // 4 / 7
      expect(e.basis, ['self:5', 'objective:0/3']);
    });

    test('低自评 + 全对：抬高 R0、偏置为负、修正后流畅度顶到 1', () {
      final reading = AssessmentPrior.read(
        evidence: const [
          AssessmentEvidence(
            knowledgePointId: 'kp1',
            selfRating: 1,
            objectiveResults: [true, true],
          ),
        ],
      );

      final e = reading.estimates.single;
      expect(reading.calibrationBias, closeTo(-0.8, 1e-9));
      expect(e.fluency, 1.0, reason: '0.2 + 0.8，且钳在 1');
      expect(e.r0, closeTo(0.90, 1e-9));
      expect(e.difficulty, closeTo(3.0, 1e-9));
      expect(e.n, 3);
      expect(e.confidence, closeTo(0.5, 1e-9));
    });

    test('多个点的偏置取平均，逐个点各算各的 R0', () {
      final reading = AssessmentPrior.read(
        evidence: const [
          AssessmentEvidence(
            knowledgePointId: 'kp1',
            selfRating: 5, // 1.0 vs 0.5 -> +0.5
            objectiveResults: [true, false],
          ),
          AssessmentEvidence(
            knowledgePointId: 'kp2',
            selfRating: 3, // 0.6 vs 0.0 -> +0.6
            objectiveResults: [false],
          ),
          AssessmentEvidence(knowledgePointId: 'kp3', selfRating: 2),
        ],
      );

      expect(reading.calibrationBias, closeTo(0.55, 1e-9));
      expect(reading.judgedCount, 2);
      expect(reading.ignoredCount, 0);
      expect(reading.estimates.map((e) => e.knowledgePointId),
          ['kp1', 'kp2', 'kp3']);

      final byId = {for (final e in reading.estimates) e.knowledgePointId: e};
      expect(byId['kp1']!.r0, closeTo(0.625, 1e-9)); // 0.35 + 0.55 × 0.5
      expect(byId['kp1']!.fluency, closeTo(0.45, 1e-9));
      expect(byId['kp2']!.r0, closeTo(0.35, 1e-9));
      expect(byId['kp2']!.fluency, closeTo(0.05, 1e-9));
      // 0.4 − 0.55 → 钳到 0，所以退回纯自评的下限 0.45。
      expect(byId['kp3']!.fluency, 0.0);
      expect(byId['kp3']!.r0, closeTo(0.45, 1e-9));
    });

    test('偏置为负时，只有自评的点其修正流畅度顶到 1（钳制生效）', () {
      final reading = AssessmentPrior.read(
        evidence: const [
          AssessmentEvidence(
            knowledgePointId: 'kp1',
            selfRating: 0,
            objectiveResults: [true],
          ),
          AssessmentEvidence(knowledgePointId: 'kp2', selfRating: 5),
        ],
      );

      expect(reading.calibrationBias, closeTo(-1.0, 1e-9));
      final kp2 = reading.estimates.last;
      expect(kp2.fluency, 1.0);
      expect(kp2.r0, closeTo(0.85, 1e-9)); // 0.45 + 0.4 × 1
    });
  });

  group('json', () {
    test('读数带 schema、偏置与逐点依据', () {
      final json = AssessmentPrior.read(
        evidence: const [
          AssessmentEvidence(
            knowledgePointId: 'kp1',
            selfRating: 5,
            objectiveResults: [true, false],
          ),
        ],
      ).toJson();

      expect(json['schema'], 'mindnet.assessment_prior/1');
      expect(json['judged_count'], 1);
      expect(json['ignored_count'], 0);
      final estimates = json['estimates'] as List<Object?>;
      final first = estimates.single as Map<String, Object?>;
      expect(first['knowledge_point_id'], 'kp1');
      expect(first['basis'], ['self:5', 'objective:1/2']);
      expect(first['fluency'], closeTo(0.5, 1e-9)); // 1.0 − 0.5
    });
  });
}

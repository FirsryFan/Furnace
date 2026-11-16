// 「学习状态」用户层折算的单元测试（task-103）。
//
// 守住四件事：
//   1. 没有/不足证据时档位是 ?（不显示 0 / 假精确），证据够了才出 S–D；
//   2. 强项/弱项只从有复习记录的知识点里排名，分配规则确定性；
//   3. 没有观测的卡不算证据；
//   4. 最近一周趋势只数复习记录，两个窗口都没记录时说「证据不足」。

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/cognitive/ability_band.dart';
import 'package:furnace/domain/services/cognitive/learning_metrics.dart';
import 'package:furnace/domain/services/cognitive/learning_status.dart';
import 'package:furnace/domain/services/cognitive/preset_prior.dart';

LearningStatusCard _card(
  String kp,
  double r, {
  bool observed = true,
  String? title,
}) =>
    LearningStatusCard(
      knowledgePointId: kp,
      knowledgePointTitle: title ?? kp,
      retrievability: r,
      hasObservation: observed,
    );

void main() {
  group('档位（S/A/B/C/D/?）', () {
    test('没有任何卡片：? 且没有证据', () {
      final status = buildLearningStatus(cards: const <LearningStatusCard>[]);

      expect(status.band.band, AbilityBand.unknown);
      expect(status.band.unknownReason, AbilityUnknownReason.sourceUnknown);
      expect(status.hasEvidence, isFalse);
      expect(status.hasBand, isFalse);
      expect(status.strengths, isEmpty);
      expect(status.weaknesses, isEmpty);
    });

    test('选了预设且没有观测：从预设档位起步，不显示 ?', () {
      final status = buildLearningStatus(
        cards: [
          _card('kp-1', 0.9, observed: false),
        ],
        preset: PresetPrior.fromSelectionId('preset-above'),
      );

      expect(status.band.band, AbilityBand.a);
      expect(status.band.source, AbilitySource.preset);
      expect(status.hasBand, isTrue);
      expect(status.hasEvidence, isFalse);
      expect(status.observedKnowledgePointCount, 0);
    });

    test('只有没复习过的卡：不算证据，档位仍是 ?', () {
      final status = buildLearningStatus(cards: [
        _card('kp-1', 0.9, observed: false),
        _card('kp-2', 0.85, observed: false),
        _card('kp-3', 0.8, observed: false),
      ]);

      expect(status.hasEvidence, isFalse);
      expect(status.band.band, AbilityBand.unknown);
      expect(status.band.unknownReason, AbilityUnknownReason.sourceUnknown);
      expect(status.strengths, isEmpty);
      expect(status.weaknesses, isEmpty);
    });

    test('1–2 张有观测的卡：证据不足，给 ?', () {
      final one = buildLearningStatus(cards: [_card('kp-1', 0.8)]);
      expect(one.band.band, AbilityBand.unknown);
      expect(one.band.unknownReason, AbilityUnknownReason.tooFewObservations);
      expect(one.strengths, hasLength(1));
      expect(one.weaknesses, isEmpty);

      final two = buildLearningStatus(cards: [
        _card('kp-1', 0.8),
        _card('kp-2', 0.6),
      ]);
      expect(two.band.band, AbilityBand.unknown);
      expect(two.band.unknownReason, AbilityUnknownReason.tooFewObservations);
    });

    test('3 张一致的高保持度卡：出 A 档，且不把均值当档位显示', () {
      final status = buildLearningStatus(cards: [
        _card('kp-1', 0.80),
        _card('kp-2', 0.82),
        _card('kp-3', 0.81),
      ]);

      expect(status.band.band, AbilityBand.a);
      expect(status.band.display, 'A');
      expect(status.band.isMeasured, isTrue);
      // 页面只用 display；均值/区间属于开发者信息，不在用户层字段里。
      expect(status.band.source, AbilitySource.measured);
      expect(status.observedCardCount, 3);
    });

    test('3 张差异很大的卡：区间过宽，仍是 ?（不硬给档）', () {
      final status = buildLearningStatus(cards: [
        _card('kp-1', 0.10),
        _card('kp-2', 0.90),
        _card('kp-3', 0.50),
      ]);

      expect(status.hasEvidence, isTrue);
      expect(status.band.band, AbilityBand.unknown);
      expect(
        status.band.unknownReason,
        AbilityUnknownReason.uncertainInterval,
      );
    });

    // task-113：档位的观测单位是**知识点**，不是闪存卡。同一知识点下的多张卡
    // 先取平均，只算一个观测——否则"一张卡复习了很多次"会被读成"很多证据"，
    // 用户层看起来就全是闪存卡读数。
    test('同一知识点的多张卡只算 1 个观测：仍证据不足', () {
      final status = buildLearningStatus(cards: [
        _card('kp-1', 0.80),
        _card('kp-1', 0.82),
        _card('kp-1', 0.81),
      ]);

      expect(status.observedCardCount, 3);
      expect(status.observedKnowledgePointCount, 1);
      expect(status.strengths, hasLength(1));
      expect(status.weaknesses, isEmpty);
      // 1 个知识点 < minObservations(3) → 不给档。
      expect(status.band.band, AbilityBand.unknown);
      expect(status.band.unknownReason, AbilityUnknownReason.tooFewObservations);
      expect(status.band.nObs, 1);
    });

    test('档位的观测数 = 有复习记录的知识点数（不是卡片数）', () {
      final status = buildLearningStatus(cards: [
        // 3 个知识点，其中一个有 2 张卡：观测数仍是 3，均值按知识点先平均。
        _card('kp-1', 0.80),
        _card('kp-1', 0.60),
        _card('kp-2', 0.70),
        _card('kp-3', 0.75),
      ]);

      expect(status.observedCardCount, 4);
      expect(status.observedKnowledgePointCount, 3);
      expect(status.band.nObs, 3);
      expect(status.band.band, AbilityBand.b);
    });

    test('policy 的观测门槛被照抄进读数（页面不写死 3）', () {
      const policy = AbilityBandPolicy(
        thresholds: AbilityBandThresholds.masteryProbability,
        minObservations: 5,
      );
      final status = buildLearningStatus(
        cards: [
          _card('kp-1', 0.8),
          _card('kp-2', 0.81),
          _card('kp-3', 0.79),
        ],
        bandPolicy: policy,
      );

      expect(status.bandMinObservations, 5);
      expect(status.band.band, AbilityBand.unknown);
      expect(status.band.unknownReason, AbilityUnknownReason.tooFewObservations);
    });
  });

  group('强项 / 弱项', () {
    test('一个知识点：只进强项，不同时进弱项', () {
      final status = buildLearningStatus(
        cards: [_card('kp-1', 0.8, title: '光合作用')],
      );

      expect(status.strengths, hasLength(1));
      expect(status.strengths.single.knowledgePointTitle, '光合作用');
      expect(status.weaknesses, isEmpty);
    });

    test('两个知识点：1 强项 + 1 弱项，不重叠', () {
      final status = buildLearningStatus(cards: [
        _card('kp-strong', 0.9, title: '强'),
        _card('kp-weak', 0.3, title: '弱'),
      ]);

      expect(status.strengths.single.knowledgePointTitle, '强');
      expect(status.weaknesses.single.knowledgePointTitle, '弱');
      expect(status.observedKnowledgePointCount, 2);
    });

    test('四个知识点：强项 3 个、弱项 1 个，不重叠', () {
      final status = buildLearningStatus(cards: [
        _card('kp-1', 0.90),
        _card('kp-2', 0.80),
        _card('kp-3', 0.70),
        _card('kp-4', 0.50),
      ]);

      expect(status.strengths, hasLength(3));
      expect(status.weaknesses, hasLength(1));
      expect(status.weaknesses.single.knowledgePointId, 'kp-4');
      final strongIds = status.strengths.map((item) => item.knowledgePointId);
      expect(strongIds, containsAll(<String>['kp-1', 'kp-2', 'kp-3']));
    });

    test('六个知识点：强项 3 + 弱项 3 = 全部，且按强弱两方向排', () {
      final status = buildLearningStatus(cards: [
        _card('kp-1', 0.10),
        _card('kp-2', 0.20),
        _card('kp-3', 0.30),
        _card('kp-4', 0.90),
        _card('kp-5', 0.80),
        _card('kp-6', 0.70),
      ]);

      expect(status.strengths.map((item) => item.knowledgePointId),
          <String>['kp-4', 'kp-5', 'kp-6']);
      expect(status.weaknesses.map((item) => item.knowledgePointId),
          <String>['kp-1', 'kp-2', 'kp-3']);
    });

    test('同一知识点多张卡先取平均，没有观测的卡不参与', () {
      final status = buildLearningStatus(cards: [
        _card('kp-1', 0.9, title: '光合作用'),
        _card('kp-1', 0.9, title: '光合作用'),
        _card('kp-2', 0.5, title: '呼吸作用'),
        _card('kp-2', 0.5, title: '呼吸作用'),
        _card('kp-3', 0.1, title: '未复习', observed: false),
      ]);

      expect(status.observedKnowledgePointCount, 2);
      expect(status.knowledgePointCount, 3);
      expect(status.strengths.first.knowledgePointId, 'kp-1');
      expect(status.strengths.first.observedCards, 2);
      expect(status.weaknesses.single.knowledgePointId, 'kp-2');
      // 新卡（无复习记录）不进榜。
      expect(
        status.strengths.map((item) => item.knowledgePointId),
        isNot(contains('kp-3')),
      );
    });

    test('并列时排序确定（观测卡数 → id），同一输入同一输出', () {
      final status = buildLearningStatus(cards: [
        _card('kp-b', 0.6),
        _card('kp-a', 0.6),
        _card('kp-c', 0.6),
      ]);

      expect(status.strengths.map((item) => item.knowledgePointId),
          <String>['kp-a', 'kp-b']);
      expect(status.weaknesses.map((item) => item.knowledgePointId),
          <String>['kp-c']);
      // 再算一次，顺序完全一样。
      final again = buildLearningStatus(cards: [
        _card('kp-c', 0.6),
        _card('kp-a', 0.6),
        _card('kp-b', 0.6),
      ]);
      expect(again.strengths.map((item) => item.knowledgePointId),
          status.strengths.map((item) => item.knowledgePointId));
    });

    test('maxItems 可配置；榜没排满时 incomplete 为 true', () {
      final status = buildLearningStatus(
        cards: [
          _card('kp-1', 0.8),
          _card('kp-2', 0.6),
        ],
        maxItems: 2,
      );

      expect(status.maxItems, 2);
      expect(status.strengths, hasLength(1));
      expect(status.strengthsIncomplete, isTrue);
      expect(status.weaknessesIncomplete, isTrue);
    });

    test('非法 maxItems 抛 ArgumentError（调用方 bug 不静默降级）', () {
      expect(
        () => buildLearningStatus(
          cards: const <LearningStatusCard>[],
          maxItems: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  group('最近一周趋势', () {
    final now = DateTime.utc(2026, 11, 15, 12);
    int daysAgo(int days) =>
        now.subtract(Duration(days: days)).millisecondsSinceEpoch;

    RetentionSample sample(int days, {bool recalled = true}) => RetentionSample(
          cardStateId: 'cs-1',
          reviewedAtMs: daysAgo(days),
          recalled: recalled,
        );

    test('两周都没有记录：hasEvidence 为 false', () {
      final trend = WeeklyReviewTrend.read(
        samples: [sample(20)],
        now: now,
      );

      expect(trend.hasEvidence, isFalse);
      expect(trend.retention, isNull);
    });

    test('本周 3 次、记得 2 次：留存 2/3，并数出上周次数', () {
      final trend = WeeklyReviewTrend.read(
        samples: [
          sample(1),
          sample(2, recalled: false),
          sample(3),
          sample(9),
          sample(11),
        ],
        now: now,
      );

      expect(trend.reviewsThisWeek, 3);
      expect(trend.recalledThisWeek, 2);
      expect(trend.reviewsLastWeek, 2);
      expect(trend.retention, closeTo(2 / 3, 1e-9));
    });

    test('本周没有但上周有：hasThisWeek 假、hasEvidence 真', () {
      final trend = WeeklyReviewTrend.read(
        samples: [sample(8), sample(10)],
        now: now,
      );

      expect(trend.hasThisWeek, isFalse);
      expect(trend.hasEvidence, isTrue);
      expect(trend.reviewsLastWeek, 2);
    });

    test('边界：正好 7 天前算本周；晚于 now 的样本被忽略', () {
      final trend = WeeklyReviewTrend.read(
        samples: [
          RetentionSample(
            cardStateId: 'cs-1',
            reviewedAtMs: now
                .subtract(const Duration(days: 7))
                .millisecondsSinceEpoch,
            recalled: true,
          ),
          RetentionSample(
            cardStateId: 'cs-2',
            reviewedAtMs: now
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch,
            recalled: true,
          ),
        ],
        now: now,
      );

      expect(trend.reviewsThisWeek, 1);
      expect(trend.reviewsLastWeek, 0);
    });

    test('窗口长度可配置，并写进序列化', () {
      final trend = WeeklyReviewTrend.read(
        samples: [sample(1)],
        now: now,
        windowDays: 14,
      );

      expect(trend.windowDays, 14);
      expect(trend.reviewsThisWeek, 1);
      expect(trend.toJson()['window_days'], 14);
    });

    test('非法窗口抛 ArgumentError', () {
      expect(
        () => WeeklyReviewTrend.read(
          samples: const <RetentionSample>[],
          now: now,
          windowDays: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}

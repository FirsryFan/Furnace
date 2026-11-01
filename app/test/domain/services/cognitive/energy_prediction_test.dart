import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/cognitive/energy_prediction.dart';

void main() {
  // 统一用 UTC 构造时间，避免测试受本机时区影响；"本地时间"只由 utcOffset 决定。
  final now = DateTime.utc(2026, 11, 1, 12, 0);

  EnergyCompletion completion(
    DateTime at, {
    int? actual,
    int? estimate,
    bool includeInModel = true,
  }) =>
      EnergyCompletion(
        completedAt: at,
        actualMinutes: actual,
        estimateMinutes: estimate,
        includeInModel: includeInModel,
      );

  EnergyReview review(DateTime at, EnergyReviewResult result) =>
      EnergyReview(reviewedAt: at, result: result);

  // 一份"合理历史"：近 3 天 4 条完成 + 3 条复习，最近一次在 10 小时前，
  // 吞吐比约 0.84（不触发升/降），近 24 小时复习全对。
  List<EnergyCompletion> reasonableCompletions() => <EnergyCompletion>[
        completion(DateTime.utc(2026, 10, 30, 14), actual: 40, estimate: 45),
        completion(DateTime.utc(2026, 10, 31, 10), actual: 30, estimate: 40),
        completion(DateTime.utc(2026, 10, 31, 15), actual: 25, estimate: 30),
        completion(DateTime.utc(2026, 11, 1, 2), actual: 45, estimate: 50),
      ];

  List<EnergyReview> reasonableReviews() => <EnergyReview>[
        review(DateTime.utc(2026, 11, 1, 1, 0), EnergyReviewResult.good),
        review(DateTime.utc(2026, 11, 1, 1, 10), EnergyReviewResult.good),
        review(DateTime.utc(2026, 11, 1, 1, 20), EnergyReviewResult.good),
      ];

  EnergyPredictionInput reasonableInput() => EnergyPredictionInput(
        now: now,
        completions: reasonableCompletions(),
        reviews: reasonableReviews(),
        utcOffset: const Duration(hours: 8),
      );

  group('没有数据', () {
    test('空队列 ⇒ 中性 5、置信 0、不自动设定、2 小时后过期', () {
      final prediction =
          EnergyPredictor.predict(EnergyPredictionInput(now: now));
      expect(prediction.level, kEnergyNeutralLevel);
      expect(prediction.confidence, 0.0);
      expect(prediction.shouldAutoSet, isFalse);
      expect(prediction.expiresAt, now.add(kEnergyPredictionTtl));
      expect(prediction.basis.last, kEnergyPredictionUncalibratedNote);
      expect(
        prediction.basis.any((line) => line.contains('没有完成/复习记录')),
        isTrue,
      );
      expect(prediction.level, inInclusiveRange(1, 10));
    });

    test('只有晚于当前时刻的记录（时钟异常）⇒ 仍按无数据处理', () {
      final prediction = EnergyPredictor.predict(EnergyPredictionInput(
        now: now,
        completions: <EnergyCompletion>[
          completion(
            now.add(const Duration(hours: 1)),
            actual: 60,
            estimate: 60,
          ),
        ],
      ));
      expect(prediction.level, kEnergyNeutralLevel);
      expect(prediction.confidence, 0.0);
      expect(prediction.shouldAutoSet, isFalse);
      expect(
        prediction.basis.any((line) => line.contains('晚于当前时刻')),
        isTrue,
      );
      expect(prediction.basis.last, kEnergyPredictionUncalibratedNote);
    });

    test('有记录但没有时长/结果信号 ⇒ 低置信、不自动设定', () {
      final prediction = EnergyPredictor.predict(EnergyPredictionInput(
        now: now,
        completions: <EnergyCompletion>[
          completion(DateTime.utc(2026, 11, 1, 8))
        ],
        reviews: <EnergyReview>[
          review(DateTime.utc(2026, 11, 1, 7), EnergyReviewResult.unknown),
        ],
      ));
      expect(prediction.level, kEnergyNeutralLevel);
      expect(prediction.confidence, 0.0);
      expect(prediction.shouldAutoSet, isFalse);
      expect(
        prediction.basis.any((line) => line.contains('没有可用的时长/结果信号')),
        isTrue,
      );
    });
  });

  group('合理历史', () {
    test('最近一次在 10 小时前 ⇒ 休息恢复 +1，置信够高可自动设定', () {
      final prediction = EnergyPredictor.predict(reasonableInput());
      expect(prediction.level, 6); // 5 中性 + 1 休息恢复；其余信号都为 0
      expect(prediction.confidence, 1.0);
      expect(prediction.shouldAutoSet, isTrue);
      expect(prediction.expiresAt, now.add(kEnergyPredictionTtl));
      expect(
        prediction.basis.any((line) => line.contains('视为已休息')),
        isTrue,
      );
      expect(prediction.basis.last, kEnergyPredictionUncalibratedNote);
      expect(prediction.basis.join('\n'), contains('覆盖 3 个本地日'));
    });
  });

  group('近 2 小时重负荷', () {
    test('最近 2 小时 150 分钟 ⇒ 降 2 档，且比同样历史不带重负荷时低', () {
      final light = EnergyPredictor.predict(reasonableInput());
      final heavy = EnergyPredictor.predict(EnergyPredictionInput(
        now: now,
        completions: <EnergyCompletion>[
          ...reasonableCompletions(),
          completion(DateTime.utc(2026, 11, 1, 10, 30),
              actual: 75, estimate: 75),
          completion(DateTime.utc(2026, 11, 1, 11, 30),
              actual: 75, estimate: 75),
        ],
        reviews: reasonableReviews(),
        utcOffset: const Duration(hours: 8),
      ));
      expect(heavy.level, 3); // 5 - 2；刚完成所以没有休息恢复
      expect(heavy.level, lessThan(light.level));
      expect(heavy.shouldAutoSet, isTrue);
      expect(
        heavy.basis.any(
          (line) => line.contains('近 2 小时累计负荷约 150 分钟'),
        ),
        isTrue,
      );
    });

    test('正好 2 小时前的完成记录不算"近 2 小时"负荷', () {
      final boundary = EnergyPredictor.predict(EnergyPredictionInput(
        now: now,
        completions: <EnergyCompletion>[
          completion(
            now.subtract(const Duration(hours: 2)),
            actual: 150,
            estimate: 150,
          ),
        ],
      ));
      final inside = EnergyPredictor.predict(EnergyPredictionInput(
        now: now,
        completions: <EnergyCompletion>[
          completion(
            now.subtract(const Duration(hours: 2)).add(
                  const Duration(milliseconds: 1),
                ),
            actual: 150,
            estimate: 150,
          ),
        ],
      ));
      expect(boundary.level, kEnergyNeutralLevel); // 2h < 8h，也没有恢复加成
      expect(inside.level, 3); // floor(150/60) = 2 档
      expect(
        inside.basis.any((line) => line.contains('近 2 小时累计负荷约 150 分钟')),
        isTrue,
      );
    });
  });

  group('吞吐比与复习结果', () {
    test('近 N 天平均用时只有预估的一半 ⇒ 升 1 档', () {
      final prediction = EnergyPredictor.predict(EnergyPredictionInput(
        now: now,
        completions: <EnergyCompletion>[
          completion(DateTime.utc(2026, 11, 1, 7), actual: 20, estimate: 40),
          completion(DateTime.utc(2026, 10, 30, 6), actual: 20, estimate: 40),
        ],
      ));
      expect(prediction.level, 6); // 5 + 1；最近一次 5 小时前，不足恢复阈值
      expect(prediction.shouldAutoSet, isFalse); // 只有 2 条，置信 0.32
      expect(
        prediction.basis.any((line) => line.contains('0.50 倍')),
        isTrue,
      );
    });

    test('平均用时明显超过预估 ⇒ 降 1 档', () {
      final prediction = EnergyPredictor.predict(EnergyPredictionInput(
        now: now,
        completions: <EnergyCompletion>[
          completion(DateTime.utc(2026, 11, 1, 8), actual: 70, estimate: 40),
          completion(DateTime.utc(2026, 10, 31, 8), actual: 100, estimate: 60),
        ],
      ));
      expect(prediction.level, 4); // 5 - 1；4 小时前才完成，没有恢复加成
      expect(
        prediction.basis.any((line) => line.contains('实际用时平均是预估的')),
        isTrue,
      );
    });

    test('近 24 小时复习失败占比 ≥50% ⇒ 降 1 档', () {
      final prediction = EnergyPredictor.predict(EnergyPredictionInput(
        now: now,
        reviews: <EnergyReview>[
          review(DateTime.utc(2026, 11, 1, 7, 0), EnergyReviewResult.forgot),
          review(DateTime.utc(2026, 11, 1, 7, 5), EnergyReviewResult.forgot),
          review(DateTime.utc(2026, 11, 1, 7, 10), EnergyReviewResult.forgot),
          review(DateTime.utc(2026, 11, 1, 7, 15), EnergyReviewResult.good),
        ],
      ));
      expect(prediction.level, 4); // 5 - 1；最近一次 4.75 小时前，不到恢复阈值
      expect(prediction.confidence, closeTo(0.56, 1e-12));
      // 置信 0.56 过线，但 4 条记录全在同一个本地日 ⇒ 仍不自动设定
      expect(prediction.shouldAutoSet, isFalse);
      expect(
        prediction.basis.any((line) => line.contains('只覆盖 1 个本地日')),
        isTrue,
      );
      expect(
        prediction.basis.any((line) => line.contains('完全没想起来')),
        isTrue,
      );
    });
  });

  group('手工值优先', () {
    test('窗口内（30 分钟前）⇒ 直接采用手工值、不自动设定、到期时间跟着手工值', () {
      final manualAt = now.subtract(const Duration(minutes: 30));
      final prediction = EnergyPredictor.predict(EnergyPredictionInput(
        now: now,
        completions: <EnergyCompletion>[
          ...reasonableCompletions(),
          completion(DateTime.utc(2026, 11, 1, 10, 30),
              actual: 75, estimate: 75),
          completion(DateTime.utc(2026, 11, 1, 11, 30),
              actual: 75, estimate: 75),
        ],
        reviews: reasonableReviews(),
        utcOffset: const Duration(hours: 8),
        manual: EnergyManualOverride(level: 9, recordedAt: manualAt),
      ));
      expect(prediction.level, 9); // 历史预测是 3，手工值覆盖它
      expect(prediction.confidence, 1.0);
      expect(prediction.shouldAutoSet, isFalse);
      expect(prediction.expiresAt, manualAt.add(kEnergyManualWindow));
      expect(prediction.basis.first, contains('手工填写值 9'));
      expect(prediction.basis.last, kEnergyPredictionUncalibratedNote);
    });

    test('窗口外（3 小时前）⇒ 忽略手工值，回到历史预测并说明已过期', () {
      final prediction = EnergyPredictor.predict(EnergyPredictionInput(
        now: now,
        completions: reasonableCompletions(),
        reviews: reasonableReviews(),
        utcOffset: const Duration(hours: 8),
        manual: EnergyManualOverride(
          level: 9,
          recordedAt: now.subtract(const Duration(hours: 3)),
        ),
      ));
      expect(prediction.level, 6); // 回落到历史预测
      expect(prediction.shouldAutoSet, isTrue);
      expect(prediction.expiresAt, now.add(kEnergyPredictionTtl));
      expect(prediction.basis.any((line) => line.contains('已过期')), isTrue);
    });

    test('手工值越界 ⇒ clamp 到 1..10 并在依据里说明', () {
      final low = EnergyPredictor.predict(EnergyPredictionInput(
        now: now,
        manual: EnergyManualOverride(
          level: -3,
          recordedAt: now.subtract(const Duration(minutes: 5)),
        ),
      ));
      final high = EnergyPredictor.predict(EnergyPredictionInput(
        now: now,
        manual: EnergyManualOverride(
          level: 99,
          recordedAt: now.subtract(const Duration(minutes: 5)),
        ),
      ));
      expect(low.level, 1);
      expect(high.level, 10);
      expect(low.basis.any((line) => line.contains('clamp')), isTrue);
      expect(high.basis.any((line) => line.contains('clamp')), isTrue);
    });

    test('手工值恰好 2 小时 ⇒ 视为过期（半开区间，采用时 expiresAt 必晚于 now）', () {
      final prediction = EnergyPredictor.predict(EnergyPredictionInput(
        now: now,
        manual: EnergyManualOverride(
          level: 9,
          recordedAt: now.subtract(kEnergyManualWindow),
        ),
      ));
      expect(prediction.level, kEnergyNeutralLevel); // 没有历史 ⇒ 中性 5
      expect(prediction.confidence, 0.0);
      expect(prediction.shouldAutoSet, isFalse);
      expect(prediction.expiresAt, now.add(kEnergyPredictionTtl));
      expect(prediction.basis.any((line) => line.contains('已过期')), isTrue);
      expect(prediction.expiresAt.isAfter(now), isTrue);
    });

    test('手工值时间晚于 now（时钟异常）⇒ 不采用并说明', () {
      final prediction = EnergyPredictor.predict(EnergyPredictionInput(
        now: now,
        manual: EnergyManualOverride(
          level: 9,
          recordedAt: now.add(const Duration(hours: 1)),
        ),
      ));
      expect(prediction.level, kEnergyNeutralLevel);
      expect(prediction.confidence, 0.0);
      expect(prediction.shouldAutoSet, isFalse);
      expect(
        prediction.basis.any((line) => line.contains('手工值时间晚于当前时刻')),
        isTrue,
      );
    });
  });

  group('边界与 clamp', () {
    test('极端疲劳（重负荷 + 超时完成 + 复习失败 + 深夜）⇒ clamp 到 1', () {
      final night =
          DateTime.utc(2026, 11, 1, 23, 30); // utcOffset = 0 ⇒ 本地 23:30
      final completions = <EnergyCompletion>[
        for (var i = 0; i < 6; i += 1)
          completion(
            night.subtract(Duration(minutes: 10 + i * 10)),
            actual: 120,
            estimate: 40,
          ),
      ];
      final reviews = <EnergyReview>[
        review(
          night.subtract(const Duration(minutes: 90)),
          EnergyReviewResult.forgot,
        ),
        review(
          night.subtract(const Duration(minutes: 85)),
          EnergyReviewResult.forgot,
        ),
        review(
          night.subtract(const Duration(minutes: 80)),
          EnergyReviewResult.forgot,
        ),
      ];
      final prediction = EnergyPredictor.predict(EnergyPredictionInput(
        now: night,
        completions: completions,
        reviews: reviews,
      ));
      expect(prediction.level, 1);
      expect(prediction.level, inInclusiveRange(1, 10));
      expect(prediction.basis.any((line) => line.contains('clamp')), isTrue);
    });

    test('样本不足（3 条、1 个本地日）⇒ 给预测但置信不足，不自动设定', () {
      final prediction = EnergyPredictor.predict(EnergyPredictionInput(
        now: now,
        completions: <EnergyCompletion>[
          completion(DateTime.utc(2026, 11, 1, 10, 30),
              actual: 30, estimate: 30),
          completion(DateTime.utc(2026, 11, 1, 11, 0),
              actual: 30, estimate: 30),
          completion(DateTime.utc(2026, 11, 1, 11, 30),
              actual: 30, estimate: 30),
        ],
      ));
      expect(prediction.level, 4); // 近 2 小时 90 分钟 ⇒ 降 1 档
      expect(prediction.confidence, closeTo(0.44, 1e-12));
      expect(prediction.shouldAutoSet, isFalse);
    });

    test('includeInModel=false 的完成记录忽略 actual，用 estimate 折算负荷', () {
      final prediction = EnergyPredictor.predict(EnergyPredictionInput(
        now: now,
        completions: <EnergyCompletion>[
          completion(
            DateTime.utc(2026, 11, 1, 11),
            actual: 500,
            estimate: 90,
            includeInModel: false,
          ),
        ],
      ));
      // actual=500 若被采用会扣满 3 档；改用 estimate=90 ⇒ 只扣 1 档（5 → 4）。
      expect(prediction.level, 4);
      expect(
        prediction.basis.any(
          (line) => line.contains('近 2 小时累计负荷约 90 分钟'),
        ),
        isTrue,
      );
    });

    test('historyDays < 1 ⇒ ArgumentError', () {
      expect(
        () => EnergyPredictor.predict(
          EnergyPredictionInput(now: now, historyDays: 0),
        ),
        throwsArgumentError,
      );
    });
  });

  group('确定性', () {
    test('同一个输入跑两次 ⇒ level/confidence/basis/expiresAt 完全一致', () {
      final first = EnergyPredictor.predict(reasonableInput());
      final second = EnergyPredictor.predict(reasonableInput());
      expect(second.toJson(), first.toJson());
      expect(second.basis, first.basis);
    });

    test('输入顺序颠倒 ⇒ 结果一致（排序把浮点求和顺序钉住）', () {
      final forward = EnergyPredictor.predict(reasonableInput());
      final reversed = EnergyPredictor.predict(EnergyPredictionInput(
        now: now,
        completions: reasonableCompletions().reversed.toList(),
        reviews: reasonableReviews().reversed.toList(),
        utcOffset: const Duration(hours: 8),
      ));
      expect(reversed.toJson(), forward.toJson());
    });
  });

  group('复习结果映射', () {
    test('review_logs 列值 → 结果，FSRS 优先于 correct', () {
      expect(
        EnergyReviewResult.fromLog(ratingFsrs: 1),
        EnergyReviewResult.forgot,
      );
      expect(
        EnergyReviewResult.fromLog(ratingFsrs: 2),
        EnergyReviewResult.hard,
      );
      expect(
        EnergyReviewResult.fromLog(ratingFsrs: 3),
        EnergyReviewResult.good,
      );
      expect(
        EnergyReviewResult.fromLog(ratingFsrs: 4),
        EnergyReviewResult.easy,
      );
      expect(EnergyReviewResult.fromLog(correct: 0), EnergyReviewResult.forgot);
      expect(EnergyReviewResult.fromLog(correct: 1), EnergyReviewResult.good);
      expect(EnergyReviewResult.fromLog(rating: 0), EnergyReviewResult.forgot);
      expect(EnergyReviewResult.fromLog(rating: 1), EnergyReviewResult.hard);
      expect(EnergyReviewResult.fromLog(rating: 2), EnergyReviewResult.good);
      expect(EnergyReviewResult.fromLog(), EnergyReviewResult.unknown);
      expect(
        EnergyReviewResult.fromLog(ratingFsrs: 2, correct: 0),
        EnergyReviewResult.hard,
      );
      expect(EnergyReviewResult.forgot.isFailure, isTrue);
      expect(EnergyReviewResult.good.isFailure, isFalse);
    });
  });

  group('toJson', () {
    test('带未标定标记与稳定键', () {
      final json = EnergyPredictor.predict(reasonableInput()).toJson();
      expect(json['level'], 6);
      expect(json['uncalibrated'], isTrue);
      expect(json['should_auto_set'], isTrue);
      expect(
        json['expires_at'],
        now.add(kEnergyPredictionTtl).millisecondsSinceEpoch,
      );
      expect(json['basis'], isA<List<String>>());
    });
  });
}

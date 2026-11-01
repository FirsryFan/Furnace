/// MindNet 的**精力预测**：从历史日志推断"此刻的精力水平 1..10"。
///
/// ## 为什么是纯逻辑
///
/// 这一层不碰数据库、不碰 Flutter、也不读时钟：调用方把 `completion_logs` /
/// `review_logs` 的行投影成 [EnergyCompletion] / [EnergyReview]，把顶栏手填值
/// 投影成 [EnergyManualOverride]，连同 [EnergyPredictionInput.now] 一起传进来。
/// 同一个输入永远得到同一个输出：[EnergyPredictor.predict] 不调用
/// `DateTime.now`，记录先按固定键排序（浮点求和的顺序也随之固定），
/// 所以边界可以被测试钉住。
///
/// ## 与现有"精力"的关系
///
/// `ThreadStates.energy`（`tables.dart:592`，1..10）与 `RankContext.energy`
/// （`thread_ranker.dart:149`）是**用户手填/确认**的当前值；本文件只给这个值
/// 提供一个可自动维护的来源，不改排序口径。`StudyRhythm` 的 α(τ) 是节律门算
/// 出的注意力可用性，也不是精力条；两者可以不一致。
///
/// ## 输出怎么读
///
/// * [EnergyPrediction.level]：1..10，与 `FurnaceDefaults.energyScaleMin/Max`、
///   `ThreadStates.energy` 同一刻度（`docs/DESIGN_BLUEPRINT.md` 的十档描述）。
/// * [EnergyPrediction.confidence]：0..1，**不是**测量精度，而是"这个推断足以
///   据此行动"的把握；历史推断样本少就低。手工值在窗口内时是 1.0——那是用户
///   自己给出的事实（不是本文件推断出来的），不是"样本很多"。
/// * [EnergyPrediction.basis]：可解释的推导旁白，UI 可逐行展示；最后一行永远是
///   未标定声明。
/// * [EnergyPrediction.shouldAutoSet]：MindNet 能否不经询问把 level 写进
///   `ThreadStates.energy`。手工值仍在窗口内时为 false（那是用户自己的覆盖，
///   不叫自动设定）；无数据、低置信（< [kEnergyAutoSetMinConfidence]）、或可用
///   记录覆盖的本地日数 < [kEnergyAutoSetMinDays] 时也是 false——同一天刷
///   9 条记录不算"有历史"。
/// * [EnergyPrediction.expiresAt]：这条预测何时作废。手工值优先时是手工窗口的
///   终点，否则是"现在 + [kEnergyPredictionTtl]"。
///
/// ## 规则（全部是显式选定的粗映射，不是测量）
///
/// 1. **手工值优先**：`now - recordedAt ∈ [0, 2h)` 时直接采用并 clamp 到
///    1..10，不自动写入；过期则忽略，并在依据里如实说"过期"。取半开区间是为了
///    让被采用的预测 `expiresAt` 严格晚于 `now`（2 小时端点归入"已过期"）。
/// 2. **近 2 小时重负荷降级**：[kEnergyAcuteWindow] 内的完成记录折算分钟数
///    （可建模时用 `actual_minutes`，否则 `estimate_minutes`，都没有用
///    [kEnergyFallbackCompletionMinutes]），每条复习记
///    [kEnergyReviewLoadMinutes] 分钟；每满 [kEnergyAcuteMinutesPerStep] 分钟
///    降 1 档，最多降 [kEnergyAcuteMaxSteps] 档。
/// 3. **休息恢复**：距最近一条记录 ≥ [kEnergyRecoveryGap] → +1 档。
/// 4. **吞吐比**：近 N 天可建模（`includeInModel` 且 actual/estimate 均 > 0）
///    的完成记录，按 [kEnergyThroughputHalfLife] 半衰加权平均
///    `actual/estimate`：≤ [kEnergyThroughputFastRatio] → +1 档，
///    ≥ [kEnergyThroughputSlowRatio] → -1 档（样本数需
///    ≥ [kEnergyThroughputMinSamples]）。
/// 5. **复习失败率**：近 [kEnergyReviewWindow] 内结果已知的复习里，"完全没
///    想起来"（[EnergyReviewResult.forgot]）占比
///    ≥ [kEnergyReviewFailureShare] 且样本 ≥ [kEnergyReviewMinSamples] → -1 档。
/// 6. **昼夜代理**：本地时间 23:00–05:00 → -1 档（没有睡眠数据，这是时间代理）。
/// 7. 中性先验 [kEnergyNeutralLevel]，最终 clamp 到 1..10。
///
/// 置信度用整数百分点累加（避免浮点误差把 100% 变成 0.999…）：每条可用记录
/// [kEnergyConfidencePerRecordPercent]，最近 [kEnergyRecentWindow] 内有记录再加
/// [kEnergyConfidenceRecentBonusPercent]，覆盖 ≥ [kEnergyConfidenceDaySpan] 个
/// 本地日再加 [kEnergyConfidenceDaySpanBonusPercent]，最后 /100 得 0..1。
/// `shouldAutoSet` 还要求覆盖 ≥ [kEnergyAutoSetMinDays] 个本地日：同一天里刷
/// 再多条记录也只是一天的样本。
///
/// ## [未标定]
///
/// 上面每一档阈值、半衰期、分钟换算、恢复窗口都**没有标定来源**：它们是显式
/// 选定的粗映射，集中放在本文件顶部，标定之后只改这一处。本预测与模型诊断
/// （R/S 轨迹）不是同一种陈述，两者不一致不是 bug；UI 必须把
/// [kEnergyPredictionUncalibratedNote] 与依据一起显示，不能把它摆成"测量结果"。
library;

import 'dart:math' as math;

import '../config/furnace_defaults.dart';

/// 历史窗口默认天数（"最近 N 天"的 N）。
const int kEnergyHistoryDays = 7;

/// 中性先验档位。没有证据时返回它，同时把置信度压到 0：**"不知道"不等于
/// "中等精力"**，避免无数据时自动写入一个编出来的值。
///
/// [未标定]：5 只是十档刻度的中点。
const int kEnergyNeutralLevel = 5;

/// 手工值的有效期。与 `FurnaceDefaults.stateStaleAfter` 同一口径：顶栏状态超过
/// 2 小时就算陈旧（`docs/FURNACE_SPEC.md` 1.1.3 的 2h 确认提示），手工精力值
/// 也一样。
const Duration kEnergyManualWindow = FurnaceDefaults.stateStaleAfter;

/// 预测值的有效期：超过它就该重新预测（同样与顶栏的 2 小时陈旧阈值对齐）。
const Duration kEnergyPredictionTtl = FurnaceDefaults.stateStaleAfter;

/// "近 2 小时"负荷窗口的默认长度。
const Duration kEnergyAcuteWindow = Duration(hours: 2);

/// 负荷折算：每满这么多分钟降 1 档。[未标定]
const double kEnergyAcuteMinutesPerStep = 60.0;

/// 近 2 小时负荷最多降几档（防止一段极端记录把预测压穿）。[未标定]
const int kEnergyAcuteMaxSteps = 3;

/// 一条复习记录折算成的负荷分钟数（复习本身很短，但没有会话计时器，只能给一
/// 个粗代理）。[未标定]
const double kEnergyReviewLoadMinutes = 2.0;

/// 完成记录既没有实际分钟也没有预估分钟时的兜底负荷。[未标定]
const double kEnergyFallbackCompletionMinutes = 20.0;

/// 距最近一条记录超过这么久，视为"已经休息过"，+1 档。[未标定]
const Duration kEnergyRecoveryGap = Duration(hours: 8);

/// 吞吐比加权的半衰期：越近的完成记录越能说明"现在"的吞吐。[未标定]
const Duration kEnergyThroughputHalfLife = Duration(hours: 48);

/// 平均实际用时 ≤ 预估用时的这个比例 ⇒ 状态好，+1 档。[未标定]
const double kEnergyThroughputFastRatio = 0.8;

/// 平均实际用时 ≥ 预估用时的这个比例 ⇒ 疲劳，-1 档。[未标定]
const double kEnergyThroughputSlowRatio = 1.5;

/// 吞吐比至少需要几条可建模记录才生效。[未标定]
const int kEnergyThroughputMinSamples = 2;

/// 复习失败率的统计窗口。[未标定]
const Duration kEnergyReviewWindow = Duration(hours: 24);

/// 复习失败率至少需要几条已知结果。[未标定]
const int kEnergyReviewMinSamples = 3;

/// 失败占比达到多少算"最近复习状态差"。[未标定]
const double kEnergyReviewFailureShare = 0.5;

/// 深夜时段的起点（含）。
const int kEnergyNightStartHour = 23;

/// 深夜时段的终点（不含），即 23:00–05:00。
const int kEnergyNightEndHour = 5;

/// 每条可用记录贡献的置信度，单位是百分点。[未标定]
const int kEnergyConfidencePerRecordPercent = 12;

/// 最近 [kEnergyRecentWindow] 内有记录时的置信度加成，单位是百分点。[未标定]
const int kEnergyConfidenceRecentBonusPercent = 8;

/// "最近有记录"的窗口。
const Duration kEnergyRecentWindow = Duration(hours: 24);

/// 历史覆盖天数达到这个数时的置信度加成。[未标定]
const int kEnergyConfidenceDaySpan = 3;

/// 覆盖天数加成，单位是百分点。[未标定]
const int kEnergyConfidenceDaySpanBonusPercent = 8;

/// 允许自动设定的最低置信度。[未标定]
const double kEnergyAutoSetMinConfidence = 0.5;

/// 允许自动设定的最少本地日覆盖数：只有一天的记录不算"有历史"。[未标定]
const int kEnergyAutoSetMinDays = 2;

/// 每条预测依据的最后一行：未标定声明。UI 必须显示它。
const String kEnergyPredictionUncalibratedNote =
    '[未标定] 精力预测由完成/复习日志推导，是代理值而不是精力测量；'
    '阈值、半衰期与分钟换算均无标定来源。';

/// 一条完成记录（`completion_logs` 的纯数据投影）。
///
/// 列口径见 `tables.dart:619-645`：`completed_at`、`actual_minutes`、
/// `estimate_minutes`、`include_in_model`。
class EnergyCompletion {
  const EnergyCompletion({
    required this.completedAt,
    this.actualMinutes,
    this.estimateMinutes,
    this.includeInModel = true,
  });

  /// `completion_logs.completed_at`（这里已经是 `DateTime`）。
  final DateTime completedAt;

  /// `completion_logs.actual_minutes`：完成时刻 - 开始时刻，没有开始/完成
  /// 两个时间点时是 null。
  final int? actualMinutes;

  /// `completion_logs.estimate_minutes`。
  final int? estimateMinutes;

  /// `completion_logs.include_in_model`：这条记录是否允许喂给时长模型。
  /// false（疑似被打断）时本文件不拿它的 `actual_minutes` 做负荷/吞吐，
  /// 改用预估分钟——不是假装它没发生过。
  final bool includeInModel;
}

/// 一条复习记录的结果。
///
/// 映射自 `review_logs` 的既有列（`tables.dart:447-506`）：
///
/// * `rating_fsrs`（1 Again / 2 Hard / 3 Good / 4 Easy，`tables.dart:460`）
///   优先；
/// * 其次 `correct`（0/1，`tables.dart:463`）：0 → [forgot]，1 → [good]；
/// * 再次 v1 `rating`（0 forgot / 1 fuzzy / 2 remembered，`tables.dart:457`）；
/// * 都没有 → [unknown]（不参与失败率，但仍算"发生过一次复习"）。
enum EnergyReviewResult {
  forgot,
  hard,
  good,
  easy,
  unknown;

  /// 从 `review_logs` 的列值映射，见枚举文档。
  static EnergyReviewResult fromLog({
    int? correct,
    int? ratingFsrs,
    int? rating,
  }) {
    if (ratingFsrs == 1) {
      return EnergyReviewResult.forgot;
    }
    if (ratingFsrs == 2) {
      return EnergyReviewResult.hard;
    }
    if (ratingFsrs == 3) {
      return EnergyReviewResult.good;
    }
    if (ratingFsrs == 4) {
      return EnergyReviewResult.easy;
    }
    if (correct == 0) {
      return EnergyReviewResult.forgot;
    }
    if (correct == 1) {
      return EnergyReviewResult.good;
    }
    if (rating == 0) {
      return EnergyReviewResult.forgot;
    }
    if (rating == 1) {
      return EnergyReviewResult.hard;
    }
    if (rating == 2) {
      return EnergyReviewResult.good;
    }
    return EnergyReviewResult.unknown;
  }

  /// 是否算"完全没想起来"，即失败率的分子。
  bool get isFailure => this == EnergyReviewResult.forgot;
}

/// 一条复习记录（`review_logs` 的纯数据投影：时刻 + 结果）。
class EnergyReview {
  const EnergyReview({
    required this.reviewedAt,
    this.result = EnergyReviewResult.unknown,
  });

  /// `review_logs.reviewed_at`（这里已经是 `DateTime`）。
  final DateTime reviewedAt;

  /// 由 `EnergyReviewResult.fromLog` 映射出来的结果。
  final EnergyReviewResult result;
}

/// 顶栏最近一次手填的精力值（`ThreadStates.energy` + `ThreadStates.updatedAt`
/// 的投影）。
class EnergyManualOverride {
  const EnergyManualOverride({required this.level, required this.recordedAt});

  /// 用户手填的精力，语义上 1..10；越界值会被 clamp，并在依据里说明。
  final int level;

  /// 手填时刻（`ThreadStates.updated_at`）。
  final DateTime recordedAt;
}

/// [EnergyPredictor.predict] 的全部输入。
class EnergyPredictionInput {
  const EnergyPredictionInput({
    required this.now,
    this.completions = const <EnergyCompletion>[],
    this.reviews = const <EnergyReview>[],
    this.manual,
    this.utcOffset = Duration.zero,
    this.historyDays = kEnergyHistoryDays,
  });

  /// 当前时刻。显式传入，做纯逻辑与可测边界。
  final DateTime now;

  /// 最近 N 天的完成记录；窗口外的、晚于 [now] 的会被忽略（后者会在依据里说明）。
  final List<EnergyCompletion> completions;

  /// 最近 N 天的复习记录；过滤规则同 [completions]。
  final List<EnergyReview> reviews;

  /// 最近一次手填值；null = 用户没填过（或已被清空）。
  final EnergyManualOverride? manual;

  /// 本地时区偏移（`DateTime.timeZoneOffset` 的写法：东八区 = +8h）。只用于
  /// 两件事：判昼夜代理、把记录归到"本地哪一天"。默认 0 = 按 UTC 读，让测试
  /// 与本机时区无关。
  final Duration utcOffset;

  /// 历史窗口天数，默认 [kEnergyHistoryDays]；必须 ≥ 1。
  final int historyDays;
}

/// 一次精力预测的输出。字段语义见本文件库注释。
class EnergyPrediction {
  const EnergyPrediction({
    required this.level,
    required this.confidence,
    required this.basis,
    required this.shouldAutoSet,
    required this.expiresAt,
  });

  /// 预测的精力水平，保证在 1..10 内。
  final int level;

  /// 0..1，含义见库注释（不是测量精度）。
  final double confidence;

  /// 可解释的推导旁白，确定性顺序；最后一行是
  /// [kEnergyPredictionUncalibratedNote]。
  final List<String> basis;

  /// 是否可以不经询问把 [level] 写成当前精力。
  final bool shouldAutoSet;

  /// 这条预测的作废时刻。
  final DateTime expiresAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'level': level,
        'confidence': confidence,
        'basis': basis,
        'should_auto_set': shouldAutoSet,
        'expires_at': expiresAt.millisecondsSinceEpoch,
        'uncalibrated': true,
      };
}

/// 纯逻辑：把历史记录 + 可选手工值 + 当前时刻，推成一条可解释的
/// [EnergyPrediction]。规则见本文件库注释。
abstract final class EnergyPredictor {
  /// 计算预测。同样的输入永远得到同样的输出；[EnergyPredictionInput.historyDays]
  /// 小于 1 时抛 [ArgumentError]。
  static EnergyPrediction predict(EnergyPredictionInput input) {
    if (input.historyDays < 1) {
      throw ArgumentError.value(
        input.historyDays,
        'historyDays',
        '历史窗口至少 1 天',
      );
    }

    final now = input.now;
    final basis = <String>[];

    // --- 1) 手工值优先 ---------------------------------------------------
    final manual = input.manual;
    if (manual != null) {
      final age = now.difference(manual.recordedAt);
      if (!age.isNegative && age < kEnergyManualWindow) {
        final clamped = manual.level
            .clamp(
                FurnaceDefaults.energyScaleMin, FurnaceDefaults.energyScaleMax)
            .toInt();
        basis.add(
          '手工填写值 ${manual.level}，记录于 ${_describeSpan(age)}前，'
          '仍在 ${_describeSpan(kEnergyManualWindow)}窗口内 → 直接采用',
        );
        if (clamped != manual.level) {
          basis.add('手工值 ${manual.level} 超出 1..10 刻度 → clamp 到 $clamped');
        }
        basis.add(
          '手工值是用户自己给出的事实 → 置信度 1.0；正因是覆盖才不自动设定',
        );
        basis.add(kEnergyPredictionUncalibratedNote);
        return EnergyPrediction(
          level: clamped,
          confidence: 1.0,
          basis: List<String>.unmodifiable(basis),
          shouldAutoSet: false,
          expiresAt: manual.recordedAt.add(kEnergyManualWindow),
        );
      }
      if (age.isNegative) {
        basis.add('手工值时间晚于当前时刻（时钟异常），本次不采用');
      } else {
        basis.add(
          '手工值已过期（记录于 ${_describeSpan(age)}前，'
          '超过 ${_describeSpan(kEnergyManualWindow)}窗口），本次不采用',
        );
      }
    }

    // --- 过滤窗口 ---------------------------------------------------------
    final cutoff = now.subtract(Duration(days: input.historyDays));
    final futureCount =
        input.completions.where((c) => c.completedAt.isAfter(now)).length +
            input.reviews.where((r) => r.reviewedAt.isAfter(now)).length;
    if (futureCount > 0) {
      basis.add('有 $futureCount 条记录时间晚于当前时刻（时钟异常），已忽略');
    }

    final completions = <EnergyCompletion>[
      for (final c in input.completions)
        if (!c.completedAt.isAfter(now) && !c.completedAt.isBefore(cutoff)) c,
    ]..sort(_compareCompletions);
    final reviews = <EnergyReview>[
      for (final r in input.reviews)
        if (!r.reviewedAt.isAfter(now) && !r.reviewedAt.isBefore(cutoff)) r,
    ]..sort(_compareReviews);

    final usableCompletions =
        completions.where(_isUsableCompletion).toList(growable: false);
    final knownReviews = reviews
        .where((r) => r.result != EnergyReviewResult.unknown)
        .toList(growable: false);

    if (usableCompletions.isEmpty && knownReviews.isEmpty) {
      final recordCount = completions.length + reviews.length;
      basis.add(
        recordCount == 0
            ? '近 ${input.historyDays} 天没有完成/复习记录 → 中性 '
                '$kEnergyNeutralLevel 分、置信度 0，不自动设定'
            : '近 ${input.historyDays} 天有 $recordCount 条记录，但没有可用的'
                '时长/结果信号 → 中性 $kEnergyNeutralLevel 分、置信度 0，'
                '不自动设定',
      );
      basis.add(kEnergyPredictionUncalibratedNote);
      return EnergyPrediction(
        level: kEnergyNeutralLevel,
        confidence: 0.0,
        basis: List<String>.unmodifiable(basis),
        shouldAutoSet: false,
        expiresAt: now.add(kEnergyPredictionTtl),
      );
    }

    final localNow = now.toUtc().add(input.utcOffset);
    var level = kEnergyNeutralLevel.toDouble();

    // --- 2) 近 2 小时重负荷 ----------------------------------------------
    final acuteCutoff = now.subtract(kEnergyAcuteWindow);
    var acuteMinutes = 0.0;
    for (final completion in completions) {
      // 窗口是 (now - 2h, now]：正好卡在 2 小时前的那条不算"近 2 小时"。
      if (completion.completedAt.isAfter(acuteCutoff) &&
          !completion.completedAt.isAfter(now)) {
        acuteMinutes += _loadMinutesOf(completion);
      }
    }
    for (final review in reviews) {
      if (review.reviewedAt.isAfter(acuteCutoff) &&
          !review.reviewedAt.isAfter(now)) {
        acuteMinutes += kEnergyReviewLoadMinutes;
      }
    }
    final acuteSteps = (acuteMinutes / kEnergyAcuteMinutesPerStep)
        .floor()
        .clamp(0, kEnergyAcuteMaxSteps)
        .toInt();
    if (acuteSteps > 0) {
      level -= acuteSteps;
      basis.add(
        '近 2 小时累计负荷约 ${acuteMinutes.round()} 分钟'
        '（每满 ${kEnergyAcuteMinutesPerStep.round()} 分钟降 1 档，'
        '上限 $kEnergyAcuteMaxSteps 档）→ 降 $acuteSteps 档',
      );
    }

    // --- 3) 休息恢复 ------------------------------------------------------
    final lastActivityAt = _latestActivity(completions, reviews);
    final recoveryGap = now.difference(lastActivityAt);
    if (recoveryGap >= kEnergyRecoveryGap) {
      level += 1;
      basis.add(
        '距最近一条学习记录约 ${_describeSpan(recoveryGap)}'
        '（≥ ${_describeSpan(kEnergyRecoveryGap)}）→ 视为已休息，升 1 档',
      );
    }

    // --- 4) 吞吐比 --------------------------------------------------------
    var weightedRatioSum = 0.0;
    var weightSum = 0.0;
    var modeledCount = 0;
    for (final completion in completions) {
      final actual = completion.actualMinutes;
      final estimate = completion.estimateMinutes;
      if (!completion.includeInModel ||
          actual == null ||
          actual <= 0 ||
          estimate == null ||
          estimate <= 0) {
        continue;
      }
      final ageMs = now.difference(completion.completedAt).inMilliseconds;
      final weight = math
          .pow(
            0.5,
            ageMs / kEnergyThroughputHalfLife.inMilliseconds,
          )
          .toDouble();
      weightedRatioSum += weight * (actual / estimate);
      weightSum += weight;
      modeledCount += 1;
    }
    if (modeledCount >= kEnergyThroughputMinSamples && weightSum > 0) {
      final ratio = weightedRatioSum / weightSum;
      if (ratio >= kEnergyThroughputSlowRatio) {
        level -= 1;
        basis.add(
          '近 ${input.historyDays} 天 $modeledCount 条可建模完成记录的'
          '实际用时平均是预估的 ${ratio.toStringAsFixed(2)} 倍'
          '（≥ ${kEnergyThroughputSlowRatio.toStringAsFixed(1)}）→ 降 1 档',
        );
      } else if (ratio <= kEnergyThroughputFastRatio) {
        level += 1;
        basis.add(
          '近 ${input.historyDays} 天 $modeledCount 条可建模完成记录的'
          '实际用时平均是预估的 ${ratio.toStringAsFixed(2)} 倍'
          '（≤ ${kEnergyThroughputFastRatio.toStringAsFixed(1)}）→ 升 1 档',
        );
      }
    }

    // --- 5) 复习失败率 ----------------------------------------------------
    final reviewCutoff = now.subtract(kEnergyReviewWindow);
    var recentKnownReviews = 0;
    var failures = 0;
    for (final review in reviews) {
      if (review.result == EnergyReviewResult.unknown ||
          !review.reviewedAt.isAfter(reviewCutoff)) {
        continue;
      }
      recentKnownReviews += 1;
      if (review.result.isFailure) {
        failures += 1;
      }
    }
    if (recentKnownReviews >= kEnergyReviewMinSamples &&
        failures / recentKnownReviews >= kEnergyReviewFailureShare) {
      level -= 1;
      basis.add(
        '最近 ${kEnergyReviewWindow.inHours} 小时 $recentKnownReviews 次复习中'
        '有 $failures 次完全没想起来'
        '（占比 ${(failures * 100 / recentKnownReviews).round()}%，'
        '≥ ${(kEnergyReviewFailureShare * 100).round()}%）→ 降 1 档',
      );
    }

    // --- 6) 昼夜代理 ------------------------------------------------------
    final localHour = localNow.hour;
    if (localHour >= kEnergyNightStartHour || localHour < kEnergyNightEndHour) {
      level -= 1;
      basis.add(
        '本地时间 ${_clockText(localNow)} 属于深夜时段'
        '（${kEnergyNightStartHour.toString().padLeft(2, '0')}:00–'
        '${kEnergyNightEndHour.toString().padLeft(2, '0')}:00）'
        '→ 降 1 档（时间代理，未标定）',
      );
    }

    // --- 7) 最终 clamp + 置信度 -------------------------------------------
    final rawLevel = level.round();
    final clampedLevel = rawLevel
        .clamp(FurnaceDefaults.energyScaleMin, FurnaceDefaults.energyScaleMax)
        .toInt();
    if (rawLevel != clampedLevel) {
      basis.add('预测原始值 $rawLevel 超出 1..10 刻度 → clamp 到 $clampedLevel');
    }

    final evidenceCount = usableCompletions.length + knownReviews.length;
    final daysCovered = _localDaysCovered(
      completions: usableCompletions,
      reviews: knownReviews,
      utcOffset: input.utcOffset,
    );
    final hasRecent = _hasRecordWithin(
      completions: usableCompletions,
      reviews: knownReviews,
      now: now,
      window: kEnergyRecentWindow,
    );
    final confidencePercent =
        (evidenceCount * kEnergyConfidencePerRecordPercent +
                (hasRecent ? kEnergyConfidenceRecentBonusPercent : 0) +
                (daysCovered >= kEnergyConfidenceDaySpan
                    ? kEnergyConfidenceDaySpanBonusPercent
                    : 0))
            .clamp(0, 100);
    final confidence = confidencePercent / 100.0;
    final confidentEnough = confidence >= kEnergyAutoSetMinConfidence;
    final shouldAutoSet =
        confidentEnough && daysCovered >= kEnergyAutoSetMinDays;
    final String autoSetNote;
    if (shouldAutoSet) {
      autoSetNote = ' → 可自动设定';
    } else if (confidentEnough) {
      autoSetNote = ' → 只覆盖 $daysCovered 个本地日（< $kEnergyAutoSetMinDays），不自动设定';
    } else {
      autoSetNote = ' → 置信不足，不自动设定';
    }

    basis.add(
      '依据近 ${input.historyDays} 天内 $evidenceCount 条可用完成/复习记录'
      '（覆盖 $daysCovered 个本地日），置信度 '
      '${(confidence * 100).round()}%$autoSetNote',
    );
    basis.add(kEnergyPredictionUncalibratedNote);

    return EnergyPrediction(
      level: clampedLevel,
      confidence: confidence,
      basis: List<String>.unmodifiable(basis),
      shouldAutoSet: shouldAutoSet,
      expiresAt: now.add(kEnergyPredictionTtl),
    );
  }
}

/// 完成记录的折算负荷分钟：可建模时用实际分钟，否则用预估，都没有用兜底值。
double _loadMinutesOf(EnergyCompletion completion) {
  final actual = completion.actualMinutes;
  if (completion.includeInModel && actual != null && actual > 0) {
    return actual.toDouble();
  }
  final estimate = completion.estimateMinutes;
  if (estimate != null && estimate > 0) {
    return estimate.toDouble();
  }
  return kEnergyFallbackCompletionMinutes;
}

/// 这条完成记录是否带可用的时长信号（置信度口径）。
bool _isUsableCompletion(EnergyCompletion completion) {
  final actual = completion.actualMinutes;
  final estimate = completion.estimateMinutes;
  return (completion.includeInModel && actual != null && actual > 0) ||
      (estimate != null && estimate > 0);
}

/// 排序是确定性的前提：`List.sort` 不稳定，同一时刻的记录必须用后续键定序。
int _compareCompletions(EnergyCompletion a, EnergyCompletion b) {
  final byTime = a.completedAt.compareTo(b.completedAt);
  if (byTime != 0) {
    return byTime;
  }
  final byActual = (a.actualMinutes ?? -1).compareTo(b.actualMinutes ?? -1);
  if (byActual != 0) {
    return byActual;
  }
  final byEstimate =
      (a.estimateMinutes ?? -1).compareTo(b.estimateMinutes ?? -1);
  if (byEstimate != 0) {
    return byEstimate;
  }
  return (a.includeInModel ? 1 : 0).compareTo(b.includeInModel ? 1 : 0);
}

/// 复习记录的确定性定序（时刻相同就用结果枚举序兜底）。
int _compareReviews(EnergyReview a, EnergyReview b) {
  final byTime = a.reviewedAt.compareTo(b.reviewedAt);
  if (byTime != 0) {
    return byTime;
  }
  return a.result.index.compareTo(b.result.index);
}

/// 窗口内最近一条活动的时间。调用前保证两个列表里至少一条记录。
DateTime _latestActivity(
  List<EnergyCompletion> completions,
  List<EnergyReview> reviews,
) {
  DateTime? latest;
  if (completions.isNotEmpty) {
    latest = completions.last.completedAt;
  }
  if (reviews.isNotEmpty) {
    final reviewAt = reviews.last.reviewedAt;
    if (latest == null || reviewAt.isAfter(latest)) {
      latest = reviewAt;
    }
  }
  return latest!;
}

/// 可用记录覆盖了几个"本地日"。
int _localDaysCovered({
  required List<EnergyCompletion> completions,
  required List<EnergyReview> reviews,
  required Duration utcOffset,
}) {
  final days = <String>{};
  for (final completion in completions) {
    days.add(_localDayKey(completion.completedAt, utcOffset));
  }
  for (final review in reviews) {
    days.add(_localDayKey(review.reviewedAt, utcOffset));
  }
  return days.length;
}

/// 最近 [window] 内是否有记录。
bool _hasRecordWithin({
  required List<EnergyCompletion> completions,
  required List<EnergyReview> reviews,
  required DateTime now,
  required Duration window,
}) {
  final cutoff = now.subtract(window);
  for (final completion in completions) {
    if (completion.completedAt.isAfter(cutoff)) {
      return true;
    }
  }
  for (final review in reviews) {
    if (review.reviewedAt.isAfter(cutoff)) {
      return true;
    }
  }
  return false;
}

String _localDayKey(DateTime moment, Duration utcOffset) {
  final local = moment.toUtc().add(utcOffset);
  return '${local.year}-${local.month}-${local.day}';
}

/// `10.5 小时` / `30 分钟` 这类人读的跨度。
String _describeSpan(Duration span) {
  if (span.inMinutes < 60) {
    return '${span.inMinutes} 分钟';
  }
  return '${(span.inMinutes / 60).toStringAsFixed(1)} 小时';
}

String _clockText(DateTime local) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}

/// 学习效果的度量——留存率与校准曲线（milestone ②「记忆效果好」的验收器）。
///
/// 为什么要有这个文件：用户说"链接认知模型和闪存卡，我实际操作发现记忆效果好"。
/// 在模型自己没有度量之前，这句话只能是感觉。这一层把复习历史变成两个可以摆出来看的量：
///
/// 1. **留存率**——按"距上次复习多久"分桶，看每一桶里真的还记得的比例。这是观测，
///    不需要任何预测，因此对**已有**的历史数据立刻可用。
/// 2. **校准**——把模型当时预测的 `R` 与真实结果对起来（Brier / ECE）。它要求预测在
///    判分之前就落库（事后重算不算预测），所以只有带 `predictedR` 的样本参与；
///    没有预测时这一半诚实地空着，而不是假装算过。
///
/// 纯逻辑：没有数据库、没有 Flutter、没有时钟。谁拿样本进来，谁负责样本来源。
library;

import 'dart:math' as math;

import '../srs/dsr_memory.dart';

/// 一次复习算不算"记得"。
///
/// 优先级与数据来源一致（`review_logs` 三代字段并存）：
/// 客观判分 > FSRS 评分 > v1 旧评分。`fuzzy`（1）与 `Hard`（2）都**不算**记得——
/// 校准曲线要的是"能不能取出来"，不是"有没有印象"；把它们算进去会把留存率整体抬高。
bool recalledFromReview({int? rating, int? ratingFsrs, bool? correct}) {
  if (correct != null) return correct;
  if (ratingFsrs != null) return ratingFsrs >= 3;
  if (rating != null) return rating >= 2;
  throw ArgumentError('复核记录里没有任何判分信号，无法判断是否记得');
}

/// 默认的间隔分桶边界（天）。最后一桶无上界。
const List<double> defaultIntervalBucketEdgesDays = [
  0,
  1,
  3,
  7,
  30,
  double.infinity,
];

/// 默认的校准分箱数（预测 `R` 在 `[0, 1]` 上等宽切分）。
const int defaultCalibrationBinCount = 5;

/// 按知识点聚合留存率时的最小样本数。
///
/// 20 条时 `p = 0.5` 的标准误约 0.11（见 [KnowledgePointRetention.standardError]）：
/// 比这更薄的分组，把它当成"最差的知识点"就是把噪声当结论。因此低于它的分组
/// **如实省略**，而不是补 0、也不是借全局留存率冒充——"复习了两次全错"不是
/// "这个知识点在漏"。
const int kMinKnowledgePointRetentionSamples = 20;

/// 孤儿日志（`card_states` 行已不存在，或那条卡没挂知识点）在内部分组时用的键；
/// 不可能与真实 id 相同。
const String _orphanKnowledgePointKey = '\u0000orphan';

/// 一条待度量的复习结果。
class RetentionSample {
  const RetentionSample({
    required this.cardStateId,
    required this.reviewedAtMs,
    required this.recalled,
    this.knowledgePointId,
    this.intervalDays,
    this.predictedR,
  });

  final String cardStateId;
  final String? knowledgePointId;
  final int reviewedAtMs;

  /// 这一次复习是否真的取出来了。
  final bool recalled;

  /// 距上一次复习同一条卡的天数；第一次复习为 `null`（没有"间隔"可言，不进分桶）。
  final double? intervalDays;

  /// 判分**之前**模型给出的 `R`；历史行没有这个值，为 `null`。
  final double? predictedR;

  RetentionSample copyWith({
    double? intervalDays,
    double? predictedR,
    bool? recalled,
  }) {
    return RetentionSample(
      cardStateId: cardStateId,
      knowledgePointId: knowledgePointId,
      reviewedAtMs: reviewedAtMs,
      recalled: recalled ?? this.recalled,
      intervalDays: intervalDays ?? this.intervalDays,
      predictedR: predictedR ?? this.predictedR,
    );
  }

  Map<String, Object?> toJson() => {
        'card_state_id': cardStateId,
        'knowledge_point_id': knowledgePointId,
        'reviewed_at': reviewedAtMs,
        'recalled': recalled,
        'interval_days':
            intervalDays == null ? null : DsrMemory.round6(intervalDays!),
        'predicted_r':
            predictedR == null ? null : DsrMemory.round6(predictedR!),
      };
}

/// 一个间隔桶的留存率。
class RetentionBucket {
  const RetentionBucket({
    required this.loDays,
    required this.hiDays,
    required this.samples,
    required this.recalled,
  });

  final double loDays;
  final double hiDays;
  final int samples;
  final int recalled;

  /// 桶内记得的比例；空桶为 0（调用方靠 [samples] 判断有没有意义）。
  double get retention => samples == 0 ? 0 : recalled / samples;

  Map<String, Object?> toJson() => {
        'lo_days': DsrMemory.round6(loDays),
        'hi_days': hiDays.isFinite ? DsrMemory.round6(hiDays) : null,
        'samples': samples,
        'recalled': recalled,
        'retention': DsrMemory.round6(retention),
      };
}

/// 一个预测区间的校准情况。
class CalibrationBin {
  const CalibrationBin({
    required this.lo,
    required this.hi,
    required this.samples,
    required this.meanPredictedR,
    required this.observed,
  });

  final double lo;
  final double hi;
  final int samples;
  final double meanPredictedR;
  final double observed;

  /// 预测减实际：正数＝过度自信，负数＝低估自己。
  double get gap => meanPredictedR - observed;

  Map<String, Object?> toJson() => {
        'lo': DsrMemory.round6(lo),
        'hi': DsrMemory.round6(hi),
        'samples': samples,
        'mean_predicted_r': DsrMemory.round6(meanPredictedR),
        'observed': DsrMemory.round6(observed),
        'gap': DsrMemory.round6(gap),
      };
}

/// 一个知识点上的留存率。
///
/// [knowledgePointId] 为 `null` 表示**归不到知识点**的复习：两种来源都会落进来——
/// ① `card_states` 行已被删（`retentionSamples()` 用 `LEFT JOIN` 刻意保留这条日志，
/// 它仍然是一次真实的复习）；② 这条卡来自 v1 模板（`getOrCreateCardState` 把
/// `card_states.knowledge_point_id` 留空，模板才是它回到材料的唯一线索）。
class KnowledgePointRetention {
  const KnowledgePointRetention({
    required this.knowledgePointId,
    required this.samples,
    required this.recalled,
  });

  final String? knowledgePointId;
  final int samples;
  final int recalled;

  /// 这个知识点上"记得"的比例；空组为 0（调用方靠 [samples] 判断有没有意义）。
  double get retention => samples == 0 ? 0 : recalled / samples;

  /// 比例的伯努利标准误 `sqrt(p(1−p)/n)`：用来判断"最差"是不是只是样本少。
  double get standardError =>
      samples == 0 ? 0 : math.sqrt(retention * (1 - retention) / samples);

  Map<String, Object?> toJson() => {
        'knowledge_point_id': knowledgePointId,
        'samples': samples,
        'recalled': recalled,
        'retention': DsrMemory.round6(retention),
        'standard_error': DsrMemory.round6(standardError),
      };
}

/// 一组复习历史的完整读数。
class LearningMetrics {
  const LearningMetrics({
    required this.reviewedCount,
    required this.recalledCount,
    required this.buckets,
    required this.bins,
    required this.calibratedCount,
    this.brier,
    this.ece,
  });

  /// 参与留存率统计的复习次数（含没有间隔值的第一次）。
  final int reviewedCount;

  /// 其中"记得"的次数。
  final int recalledCount;

  /// 按间隔分好的桶（含空桶，便于界面稳定地画出来）。
  final List<RetentionBucket> buckets;

  /// 按预测 `R` 分好的箱（含空箱）。
  final List<CalibrationBin> bins;

  /// 带预测值、因而能进校准统计的样本数。
  final int calibratedCount;

  /// 均方误差 `mean((R_pred - 实际)^2)`；没有预测样本时为 `null`。
  final double? brier;

  /// 期望校准误差 `Σ (n_b/N)·|预测均值 - 实际|`；没有预测样本时为 `null`。
  final double? ece;

  static const LearningMetrics empty = LearningMetrics(
    reviewedCount: 0,
    recalledCount: 0,
    buckets: [],
    bins: [],
    calibratedCount: 0,
  );

  bool get isEmpty => reviewedCount == 0;

  /// 总体留存率；没有样本时为 0（调用方看 [isEmpty]）。
  double get retention =>
      reviewedCount == 0 ? 0 : recalledCount / reviewedCount;

  /// 有预测样本、校准数字才有意义。
  bool get hasCalibration => calibratedCount > 0;

  Map<String, Object?> toJson() => {
        'schema': 'mindnet.learning_metrics/1',
        'calibrated': false,
        'reviewed': reviewedCount,
        'recalled': recalledCount,
        'retention': DsrMemory.round6(retention),
        'calibrated_count': calibratedCount,
        'brier': brier == null ? null : DsrMemory.round6(brier!),
        'ece': ece == null ? null : DsrMemory.round6(ece!),
        'buckets': [for (final bucket in buckets) bucket.toJson()],
        'bins': [for (final bin in bins) bin.toJson()],
      };

  /// 从样本算出全部读数。
  ///
  /// 桶与箱**始终完整**（哪怕某桶没有样本）：界面不该因为"这周没复习"就少一行，
  /// 缺数据本身就是要看见的信息。
  static LearningMetrics read({
    required List<RetentionSample> samples,
    List<double> bucketEdges = defaultIntervalBucketEdgesDays,
    int calibrationBinCount = defaultCalibrationBinCount,
  }) {
    if (calibrationBinCount < 1) {
      throw ArgumentError('校准分箱数必须至少为 1，实际 $calibrationBinCount');
    }
    if (bucketEdges.length < 2) {
      throw ArgumentError('间隔分桶至少要两条边界，实际 ${bucketEdges.length}');
    }

    var recalled = 0;
    for (final sample in samples) {
      if (sample.recalled) recalled++;
    }

    final buckets = <RetentionBucket>[];
    for (var i = 0; i + 1 < bucketEdges.length; i++) {
      final lo = bucketEdges[i];
      final hi = bucketEdges[i + 1];
      var bucketSamples = 0;
      var bucketRecalled = 0;
      for (final sample in samples) {
        final days = sample.intervalDays;
        if (days == null) continue;
        if (days >= lo && days < hi) {
          bucketSamples++;
          if (sample.recalled) bucketRecalled++;
        }
      }
      buckets.add(
        RetentionBucket(
          loDays: lo,
          hiDays: hi,
          samples: bucketSamples,
          recalled: bucketRecalled,
        ),
      );
    }

    final width = 1 / calibrationBinCount;
    final predicted = <RetentionSample>[
      for (final sample in samples)
        if (sample.predictedR != null) sample,
    ];

    final bins = <CalibrationBin>[];
    for (var i = 0; i < calibrationBinCount; i++) {
      final lo = i * width;
      // 最后一箱闭合到 1，否则 `R == 1.0` 会掉在箱子外面。
      final hi = i == calibrationBinCount - 1 ? 1.0 : (i + 1) * width;
      var binSamples = 0;
      var binPredicted = 0.0;
      var binRecalled = 0;
      for (final sample in predicted) {
        final r = sample.predictedR!.clamp(0.0, 1.0);
        final inBin = i == calibrationBinCount - 1
            ? (r >= lo && r <= hi)
            : (r >= lo && r < hi);
        if (!inBin) continue;
        binSamples++;
        binPredicted += r;
        if (sample.recalled) binRecalled++;
      }
      bins.add(
        CalibrationBin(
          lo: lo,
          hi: hi,
          samples: binSamples,
          meanPredictedR: binSamples == 0 ? 0 : binPredicted / binSamples,
          observed: binSamples == 0 ? 0 : binRecalled / binSamples,
        ),
      );
    }

    double? brier;
    double? ece;
    if (predicted.isNotEmpty) {
      var squared = 0.0;
      for (final sample in predicted) {
        final r = sample.predictedR!.clamp(0.0, 1.0);
        final actual = sample.recalled ? 1.0 : 0.0;
        squared += (r - actual) * (r - actual);
      }
      brier = squared / predicted.length;

      var weighted = 0.0;
      for (final bin in bins) {
        if (bin.samples == 0) continue;
        weighted += (bin.samples / predicted.length) * bin.gap.abs();
      }
      ece = weighted;
    }

    return LearningMetrics(
      reviewedCount: samples.length,
      recalledCount: recalled,
      buckets: buckets,
      bins: bins,
      calibratedCount: predicted.length,
      brier: brier,
      ece: ece,
    );
  }

  /// 按知识点聚合的留存率，**最差的在前**。
  ///
  /// 只保留样本数 `>= minSamples` 的分组：样本不够的知识点**不会出现**在结果里，
  /// 调用方要如实说"按知识点还看不出结论"，而不是拿一两条样本点名一个知识点。
  /// 排序确定性：留存率升序 → 样本数降序 → 知识点 id 升序（孤儿日志排最后）。
  static List<KnowledgePointRetention> retentionByKnowledgePoint({
    required List<RetentionSample> samples,
    int minSamples = kMinKnowledgePointRetentionSamples,
  }) {
    if (minSamples < 1) {
      throw ArgumentError('最小样本数必须至少为 1，实际 $minSamples');
    }

    final tally = <String, ({int samples, int recalled})>{};
    for (final sample in samples) {
      final key = sample.knowledgePointId ?? _orphanKnowledgePointKey;
      final current = tally[key];
      tally[key] = (
        samples: (current?.samples ?? 0) + 1,
        recalled: (current?.recalled ?? 0) + (sample.recalled ? 1 : 0),
      );
    }

    final out = <KnowledgePointRetention>[
      for (final entry in tally.entries)
        if (entry.value.samples >= minSamples)
          KnowledgePointRetention(
            knowledgePointId:
                entry.key == _orphanKnowledgePointKey ? null : entry.key,
            samples: entry.value.samples,
            recalled: entry.value.recalled,
          ),
    ];
    out.sort((a, b) {
      // 孤儿日志不是知识点，永远排最后：工具摘要按列表头点名"最差的知识点"，
      // 把"卡片已被删除"那一组摆在第一位会读成"这个知识点在漏"。
      final aId = a.knowledgePointId;
      final bId = b.knowledgePointId;
      if (aId == null || bId == null) {
        if (aId == null && bId == null) return 0;
        return aId == null ? 1 : -1;
      }
      final byRetention = a.retention.compareTo(b.retention);
      if (byRetention != 0) return byRetention;
      final bySamples = b.samples.compareTo(a.samples);
      if (bySamples != 0) return bySamples;
      return aId.compareTo(bId);
    });
    return out;
  }
}

/// 给样本补上"距上一次复习同一条卡多少天"。
///
/// 按 `(cardStateId, reviewedAtMs)` 排序后逐条推进：同一条卡的上一条决定这一条的间隔；
/// 时间戳相同时后一条视为间隔 0（同一秒里连点两次是真实会发生的事，不该被丢掉）。
List<RetentionSample> withIntervals(List<RetentionSample> samples) {
  final sorted = [...samples]..sort((a, b) {
      final byCard = a.cardStateId.compareTo(b.cardStateId);
      if (byCard != 0) return byCard;
      return a.reviewedAtMs.compareTo(b.reviewedAtMs);
    });

  final out = <RetentionSample>[];
  String? lastCard;
  int? lastMs;
  for (final sample in sorted) {
    final sameCard = sample.cardStateId == lastCard;
    final days = sameCard && lastMs != null
        ? math.max(0, sample.reviewedAtMs - lastMs) /
            Duration.millisecondsPerDay
        : null;
    out.add(sameCard ? sample.copyWith(intervalDays: days) : sample);
    lastCard = sample.cardStateId;
    lastMs = sample.reviewedAtMs;
  }
  return out;
}

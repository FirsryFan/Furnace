/// 用户层「学习状态」的纯逻辑：把模型读数折成用户能看懂的四件事。
///
/// 任务来源：用户反馈「认知模型/MindNet 的测试入口、评价体系、可视化太复杂」，
/// 要求用户层只显示：档位 S/A/B/C/D/`?`、3 强项 + 3 弱项、今日复习/任务数、
/// 一句趋势；开发者字段默认隐藏。本文件只做**折算**，不读库、不读时钟、不碰
/// Flutter，因此页面、测试与将来的 CLI 能拿到同一份答案（D2）。
///
/// 三条纪律：
///
/// * **证据不足就是 `?`**：档位走 [readAbilityBand]，少于
///   [AbilityBandPolicy.minObservations] 个**有复习记录的知识点**、或区间过宽时，
///   输出 [AbilityBand.unknown]，页面显示 `?`，不拿 0 / 50% 冒充读数。
/// * **强项/弱项只从有观测的知识点里排名**：没有任何复习记录的知识点不进榜，
///   也不补 0；列表没排满 3 个时，页面如实说「证据不足」。
/// * **档位以知识点为观测单位，不以闪存卡为观测单位**（2026-11-15 第二遍清理，
///   task-113）：用户反馈「认知模型进去基本是闪存卡读数」。同一知识点下的多张卡
///   先取平均 R 作为**一个**观测，档位看的是「多少个知识点有复习记录」而不是
///   「多少张卡被复习过」；卡片数只留在开发者读数与序列化里。
///   阈值与证据门槛沿用 `ability_band.dart` 的未标定占位值
///   （[AbilityBandPolicy.mastery]，`calibrated=false`）。
///   页面只显示档位字，不显示均值或区间。
library;

import 'dart:math' as math;

import 'ability_band.dart';
import 'learning_metrics.dart';
import 'preset_prior.dart';

/// 一张卡在用户层能提供的读数。
///
/// 只保留折算需要的东西：属于哪个知识点、模型算出的当前可提取度，以及这张卡
/// 到底有没有复习记录（[hasObservation]）。没有任何写的字段都不进这一层。
class LearningStatusCard {
  const LearningStatusCard({
    required this.knowledgePointId,
    required this.knowledgePointTitle,
    required this.retrievability,
    required this.hasObservation,
  });

  final String knowledgePointId;
  final String knowledgePointTitle;

  /// 模型读出的当前可提取度 `R`（0–1）。
  final double retrievability;

  /// 这张卡有没有属于它自己的复习记录（`lastReviewedAt != null` 或
  /// `repetitions > 0`）。没有观测的卡只是模型默认值，不算证据。
  final bool hasObservation;
}

/// 一条知识点在用户层的证据状态。
///
/// 目前只有「实测」会进强项/弱项榜；保留枚举是为了让页面在不进榜的场合也能
/// 说清「证据不足」，而不是把空列表读成「没有问题」。
enum LearningEvidence {
  /// 至少一张卡有复习记录。
  measured,

  /// 没有任何复习记录（既没有实测，也没有进榜资格）。
  insufficient,
}

/// 强项/弱项榜上的一条。
class LearningStatusItem {
  const LearningStatusItem({
    required this.knowledgePointId,
    required this.knowledgePointTitle,
    required this.meanRetrievability,
    required this.observedCards,
    this.evidence = LearningEvidence.measured,
  });

  final String knowledgePointId;

  /// 知识点标题；可能为空字符串（调用方自己给兜底文案）。
  final String knowledgePointTitle;

  /// 这个知识点下**有复习记录**的卡片的平均 `R`（0–1）。
  final double meanRetrievability;

  /// 参与平均的卡片数（至少 1）。
  final int observedCards;

  final LearningEvidence evidence;

  Map<String, Object?> toJson() => <String, Object?>{
        'knowledge_point_id': knowledgePointId,
        'title': knowledgePointTitle,
        'mean_r': meanRetrievability,
        'observed_cards': observedCards,
        'evidence': evidence.name,
      };
}

/// 用户层学习状态：档位 + 强项/弱项 + 证据计数。
class LearningStatus {
  const LearningStatus({
    required this.band,
    required this.strengths,
    required this.weaknesses,
    required this.knowledgePointCount,
    required this.observedKnowledgePointCount,
    required this.observedCardCount,
    required this.bandMinObservations,
    required this.maxItems,
  });

  /// 档位读数（只取 `band` / `display` / `unknownReason`；均值不往页面传）。
  final AbilityBandReading band;

  /// 相对更强的知识点（按平均 `R` 降序），最多 [maxItems] 个。
  final List<LearningStatusItem> strengths;

  /// 相对更弱的知识点（按平均 `R` 升序），最多 [maxItems] 个；
  /// 至少有两个有观测的知识点才会出现条目（只有一个时无法分强弱）。
  final List<LearningStatusItem> weaknesses;

  /// 读数里出现过的知识点总数（含有观测与没有观测的）。
  final int knowledgePointCount;

  /// 有复习记录的**知识点**数——档位的观测数就是它（不是卡片数）。
  final int observedKnowledgePointCount;

  /// 有复习记录的卡片数。开发者读数与序列化会用到；用户层页面不再把它当
  /// 档位依据（task-113：避免"进去全是闪存卡读数"）。
  final int observedCardCount;

  /// 档位策略要求的最低观测数（照抄 policy，不在页面里写死）。
  final int bandMinObservations;

  /// 榜最多列几个。
  final int maxItems;

  /// 有没有任何复习证据。
  bool get hasEvidence => observedCardCount > 0;

  /// 档位是否真的给出了（`?` 时为 false）。
  bool get hasBand => band.band.isKnown;

  /// 强项是否没排满。
  bool get strengthsIncomplete => strengths.length < maxItems;

  /// 弱项是否没排满。
  bool get weaknessesIncomplete => weaknesses.length < maxItems;

  Map<String, Object?> toJson() => <String, Object?>{
        'band': band.band.name,
        'band_label': band.band.label,
        'band_source': band.source.code,
        'band_unknown_reason': band.unknownReason.code,
        'band_min_observations': bandMinObservations,
        'strengths': <Object?>[for (final item in strengths) item.toJson()],
        'weaknesses': <Object?>[for (final item in weaknesses) item.toJson()],
        'knowledge_points': knowledgePointCount,
        'observed_knowledge_points': observedKnowledgePointCount,
        'observed_cards': observedCardCount,
      };
}

/// 折算用户层学习状态。
///
/// 档位 = **有复习记录的知识点**的平均 `R` 的均值 + 95% 区间（样本标准差换算），
/// 交给 [readAbilityBand] 按 [AbilityBandPolicy.mastery] 落档。观测单位是知识点：
/// 同一知识点下多张卡先取平均，再参与落档；样本数（知识点数）<
/// `minObservations` 或区间宽于 policy 上限时输出 `?`，这是刻意的：一两个知识点
/// 不足以给档位。
///
/// 强项/弱项在**知识点**层排名（同一知识点的多张卡先取平均），只有该知识点
/// 至少有一张有复习记录的卡才进榜。分配规则（确定性）：按平均 `R` 降序排，
/// 有 `n` 个有观测的知识点时
///
/// * `n == 0`：两个榜都空；
/// * `n == 1`：强项 1 个、弱项 0 个（不能把同一个点同时说成强和弱）；
/// * `n >= 2`：强项取前 `min(maxItems, n - 1)` 个，弱项从剩下的里取
///   `min(maxItems, n - 强项数)` 个（弱项按 `R` 升序）。
///
/// 排序并列时按观测卡数降序、再按知识点 id 升序，保证同一输入永远同一输出。
LearningStatus buildLearningStatus({
  required List<LearningStatusCard> cards,
  AbilityBandPolicy bandPolicy = AbilityBandPolicy.mastery,
  PresetPrior? preset,
  int maxItems = 3,
}) {
  if (maxItems < 1) {
    throw ArgumentError.value(maxItems, 'maxItems', '榜上至少要有 1 个位置');
  }

  final observedR = <double>[
    for (final card in cards)
      if (card.hasObservation && card.retrievability.isFinite)
        card.retrievability,
  ];

  final grouped = <String, List<LearningStatusCard>>{};
  for (final card in cards) {
    grouped
        .putIfAbsent(card.knowledgePointId, () => <LearningStatusCard>[])
        .add(card);
  }

  final measured = <LearningStatusItem>[];
  for (final entry in grouped.entries) {
    final observed = <LearningStatusCard>[
      for (final card in entry.value)
        if (card.hasObservation && card.retrievability.isFinite) card,
    ];
    if (observed.isEmpty) continue;
    final mean =
        observed.map((card) => card.retrievability).reduce((a, b) => a + b) /
            observed.length;
    measured.add(
      LearningStatusItem(
        knowledgePointId: entry.key,
        knowledgePointTitle: _titleOf(entry.value),
        meanRetrievability: mean,
        observedCards: observed.length,
      ),
    );
  }

  measured.sort((a, b) {
    final byMean = b.meanRetrievability.compareTo(a.meanRetrievability);
    if (byMean != 0) return byMean;
    final byCards = b.observedCards.compareTo(a.observedCards);
    if (byCards != 0) return byCards;
    return a.knowledgePointId.compareTo(b.knowledgePointId);
  });

  final strengths = <LearningStatusItem>[];
  final weaknesses = <LearningStatusItem>[];
  if (measured.length == 1) {
    strengths.add(measured.first);
  } else if (measured.length >= 2) {
    final strengthCount = math.min(maxItems, measured.length - 1);
    final weaknessCount = math.min(maxItems, measured.length - strengthCount);
    strengths.addAll(measured.take(strengthCount));
    final rest = measured.skip(strengthCount).toList();
    rest.sort((a, b) {
      final byMean = a.meanRetrievability.compareTo(b.meanRetrievability);
      if (byMean != 0) return byMean;
      final byCards = b.observedCards.compareTo(a.observedCards);
      if (byCards != 0) return byCards;
      return a.knowledgePointId.compareTo(b.knowledgePointId);
    });
    weaknesses.addAll(rest.take(weaknessCount));
  }

  return LearningStatus(
    // 档位的观测单位是知识点（每个知识点取有观测卡片的平均 R），不是卡片：
    // 「一张卡复习过 5 次」不等于「5 个知识点有证据」（task-113）。
    band: measured.isEmpty && preset != null
        ? readAbilityBand(
            AbilityBandInput(
              source: AbilitySource.preset,
              nObs: 0,
              mean: preset.effectiveMean,
            ),
            policy: bandPolicy,
          )
        : _bandOf(
            <double>[for (final item in measured) item.meanRetrievability],
            bandPolicy,
          ),
    strengths: List<LearningStatusItem>.unmodifiable(strengths),
    weaknesses: List<LearningStatusItem>.unmodifiable(weaknesses),
    knowledgePointCount: grouped.length,
    observedKnowledgePointCount: measured.length,
    observedCardCount: observedR.length,
    bandMinObservations: bandPolicy.minObservations,
    maxItems: maxItems,
  );
}

/// 档位：观测够 + 区间够窄才出档，否则 `?`（由 [readAbilityBand] 判定）。
AbilityBandReading _bandOf(
  List<double> values,
  AbilityBandPolicy policy,
) {
  if (values.isEmpty) {
    return readAbilityBand(
      const AbilityBandInput(source: AbilitySource.unknown, nObs: 0),
      policy: policy,
    );
  }
  final mean = values.reduce((a, b) => a + b) / values.length;
  final sd = values.length >= 2 ? _sampleStandardDeviation(values, mean) : null;
  return readAbilityBand(
    AbilityBandInput(
      source: AbilitySource.measured,
      nObs: values.length,
      mean: mean,
      sd: sd,
    ),
    policy: policy,
  );
}

/// 样本标准差（分母 n-1）。`n < 2` 时没有样本方差，返回 null。
double? _sampleStandardDeviation(List<double> values, double mean) {
  if (values.length < 2) return null;
  var sum = 0.0;
  for (final value in values) {
    final diff = value - mean;
    sum += diff * diff;
  }
  return math.sqrt(sum / (values.length - 1));
}

String _titleOf(List<LearningStatusCard> cards) {
  for (final card in cards) {
    final title = card.knowledgePointTitle.trim();
    if (title.isNotEmpty) return title;
  }
  return '';
}

/// 「最近一周复习」的一句话趋势素材。
///
/// 只统计 [RetentionSample]（`review_logs` 的观测），不预测、不补算：
/// 时间窗内没有复习记录时 [hasEvidence] 为 false，页面说「证据不足」。
class WeeklyReviewTrend {
  const WeeklyReviewTrend({
    required this.reviewsThisWeek,
    required this.recalledThisWeek,
    required this.reviewsLastWeek,
    this.windowDays = 7,
  });

  /// 时间窗内一次复习都没有的读数。
  static const WeeklyReviewTrend empty = WeeklyReviewTrend(
    reviewsThisWeek: 0,
    recalledThisWeek: 0,
    reviewsLastWeek: 0,
  );

  /// 最近一个窗口内的复习次数。
  final int reviewsThisWeek;

  /// 其中「记得」的次数。
  final int recalledThisWeek;

  /// 前一个窗口内的复习次数（只在页面要对比时用）。
  final int reviewsLastWeek;

  /// 窗口长度（天）。页面文案里的「最近 N 天」由它决定，不写死。
  final int windowDays;

  /// 最近一个窗口里有没有复习记录。
  bool get hasThisWeek => reviewsThisWeek > 0;

  /// 两个窗口里有没有任何复习记录。
  bool get hasEvidence => reviewsThisWeek > 0 || reviewsLastWeek > 0;

  /// 本窗口留存率；没有复习记录时为 null（页面不会显示 0%）。
  double? get retention =>
      reviewsThisWeek == 0 ? null : recalledThisWeek / reviewsThisWeek;

  /// 从复习样本算出两个窗口的计数。
  ///
  /// 时间窗以 [now] 为右端：`[now - windowDays, now]` 是本窗口，
  /// `[now - 2*windowDays, now - windowDays)` 是上一窗口。时间戳晚于 [now]
  /// 的样本被忽略（时钟回拨/未来日志不是这一周的复习）。
  static WeeklyReviewTrend read({
    required Iterable<RetentionSample> samples,
    required DateTime now,
    int windowDays = 7,
  }) {
    if (windowDays < 1) {
      throw ArgumentError.value(windowDays, 'windowDays', '窗口至少 1 天');
    }
    final nowMs = now.millisecondsSinceEpoch;
    final windowMs = windowDays * Duration.millisecondsPerDay;
    final thisStart = nowMs - windowMs;
    final lastStart = thisStart - windowMs;
    var reviewsThisWeek = 0;
    var recalledThisWeek = 0;
    var reviewsLastWeek = 0;
    for (final sample in samples) {
      final at = sample.reviewedAtMs;
      if (at > nowMs) continue;
      if (at >= thisStart) {
        reviewsThisWeek++;
        if (sample.recalled) recalledThisWeek++;
      } else if (at >= lastStart) {
        reviewsLastWeek++;
      }
    }
    return WeeklyReviewTrend(
      reviewsThisWeek: reviewsThisWeek,
      recalledThisWeek: recalledThisWeek,
      reviewsLastWeek: reviewsLastWeek,
      windowDays: windowDays,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'window_days': windowDays,
        'reviews_this_window': reviewsThisWeek,
        'recalled_this_window': recalledThisWeek,
        'reviews_previous_window': reviewsLastWeek,
        'retention': retention,
      };
}

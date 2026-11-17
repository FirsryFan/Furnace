/// 题目「能不能进主题库」的判据（纯逻辑，不碰 DB / Flutter）。
///
/// 用户口径（2026-11-17）：**入库但没有解析/答案的题从主题库隐藏**，改在
/// 「待处理题目」入口里按原因统计；等答案/解析补上再自动回到主题库。真实库
/// 170 题里有 105 题 `answer` 与 `solution` 同时为空（全部来自整卷导入），
/// 混在主题库里既没法练也没法判分。
///
/// 为什么把口径做成 [QuestionCompletenessPolicy] 而不是写死：
///  * 不同入口要的严格度不同（主题库 vs 待处理列表 vs 组卷候选）；
///  * 将来可能要求「必须有答案」或「必须有解析」，不应再改判据代码；
///  * 不能按学科/来源硬编码——判据只看题自身有没有答案/解析/配图。
///
/// 默认 [QuestionCompletenessPolicy.hidePending] 判「待处理」的标准是
/// **答案与解析都为空**；这是本轮数据口径，不是对某科的假设。
library;

import 'question_asset_placeholder.dart';

/// 一道题待处理的原因（可以同时有多条）。
enum QuestionPendingReason {
  /// 没有参考答案。
  missingAnswer,

  /// 没有解析。
  missingSolution,

  /// 题面还引用着 `{{asset:NAME}}`，但库里没有任何题干配图：图没了。
  missingStemMedia,
}

/// 一道题的完整性结论。
class QuestionReadiness {
  const QuestionReadiness({required this.reasons});

  /// 全部通过：可以直接进主题库。
  static const QuestionReadiness ready =
      QuestionReadiness(reasons: <QuestionPendingReason>[]);

  /// 待处理原因；空 = 完整。
  final List<QuestionPendingReason> reasons;

  bool get isReady => reasons.isEmpty;

  bool get isPending => reasons.isNotEmpty;

  bool has(QuestionPendingReason reason) => reasons.contains(reason);

  @override
  String toString() => 'QuestionReadiness(${reasons.map((r) => r.name).join(',')})';
}

/// 判据配置：哪几项缺失算「待处理」。
///
/// 三个开关彼此独立，默认只开 [requireAnswerOrSolution]：
///  * [requireAnswer]：答案为空就算待处理（更严）；
///  * [requireSolution]：解析为空就算待处理（更严）；
///  * [requireAnswerOrSolution]：答案与解析**都**为空才算（默认口径，105 题）；
///  * [requireStemMedia]：题干引用资产占位却没有任何配图才算（配图缺失）。
class QuestionCompletenessPolicy {
  const QuestionCompletenessPolicy({
    this.requireAnswer = false,
    this.requireSolution = false,
    this.requireAnswerOrSolution = true,
    this.requireStemMedia = false,
  });

  /// 主题库默认口径：答案与解析都为空 → 待处理（隐藏）。
  static const QuestionCompletenessPolicy hidePending =
      QuestionCompletenessPolicy();

  /// 完全不筛：任何题都算完整（读表函数的历史行为）。
  static const QuestionCompletenessPolicy includeAll =
      QuestionCompletenessPolicy(requireAnswerOrSolution: false);

  final bool requireAnswer;
  final bool requireSolution;
  final bool requireAnswerOrSolution;
  final bool requireStemMedia;

  /// 这份配置会不会真的筛掉题（全 false 时读表结果与历史一致）。
  bool get filtersAnything =>
      requireAnswer ||
      requireSolution ||
      requireAnswerOrSolution ||
      requireStemMedia;
}

/// 判一道题：缺什么、算不算待处理。
///
/// [stemImageCount] 只用于 [QuestionCompletenessPolicy.requireStemMedia]：题干里有
/// `{{asset:NAME}}` 占位而配图为 0，说明源图从来没落库（`.wmf` 也一样，见
/// `question_asset_placeholder.dart` 的格式说明）。
QuestionReadiness evaluateQuestionReadiness({
  required String? answer,
  required String? solution,
  required String stem,
  required int stemImageCount,
  QuestionCompletenessPolicy policy = QuestionCompletenessPolicy.hidePending,
}) {
  final answerMissing = (answer ?? '').trim().isEmpty;
  final solutionMissing = (solution ?? '').trim().isEmpty;
  final mediaMissing = stemImageCount <= 0 &&
      containsQuestionAssetPlaceholder(stem);
  final reasons = <QuestionPendingReason>[];
  if (policy.requireAnswer && answerMissing) {
    reasons.add(QuestionPendingReason.missingAnswer);
  }
  if (policy.requireSolution && solutionMissing) {
    reasons.add(QuestionPendingReason.missingSolution);
  }
  if (policy.requireAnswerOrSolution && answerMissing && solutionMissing) {
    // 两项都缺时两条原因都记：待处理页按原因统计才有意义（「缺答案/缺解析」
    // 是同一批题的两面，数量可以相等，不合并成一条含糊的「没答案没解析」）。
    reasons
      ..add(QuestionPendingReason.missingAnswer)
      ..add(QuestionPendingReason.missingSolution);
  }
  if (policy.requireStemMedia && mediaMissing) {
    reasons.add(QuestionPendingReason.missingStemMedia);
  }
  if (reasons.isEmpty) {
    return QuestionReadiness.ready;
  }
  return QuestionReadiness(reasons: List<QuestionPendingReason>.unmodifiable(reasons));
}

/// 待处理统计（按题去重；同一道题可以同时缺答案与解析）。
class QuestionPendingStats {
  const QuestionPendingStats({
    required this.total,
    required this.missingAnswer,
    required this.missingSolution,
    required this.missingStemMedia,
    required this.reasonCounts,
  });

  /// 待处理题目数。
  final int total;

  /// 缺答案的题数。
  final int missingAnswer;

  /// 缺解析的题数。
  final int missingSolution;

  /// 配图缺失的题数。
  final int missingStemMedia;

  /// 原因 → 题数（用于页面逐条列出；保持 [QuestionPendingReason] 的声明顺序）。
  final Map<QuestionPendingReason, int> reasonCounts;

  bool get isEmpty => total == 0;

  static const QuestionPendingStats empty = QuestionPendingStats(
    total: 0,
    missingAnswer: 0,
    missingSolution: 0,
    missingStemMedia: 0,
    reasonCounts: <QuestionPendingReason, int>{},
  );
}

/// 从每道题的完整性结论汇总统计。
QuestionPendingStats questionPendingStats(
  Iterable<QuestionReadiness> readiness,
) {
  var total = 0;
  final counts = <QuestionPendingReason, int>{};
  for (final item in readiness) {
    if (item.isPending) total++;
    for (final reason in item.reasons) {
      counts[reason] = (counts[reason] ?? 0) + 1;
    }
  }
  return QuestionPendingStats(
    total: total,
    missingAnswer: counts[QuestionPendingReason.missingAnswer] ?? 0,
    missingSolution: counts[QuestionPendingReason.missingSolution] ?? 0,
    missingStemMedia: counts[QuestionPendingReason.missingStemMedia] ?? 0,
    reasonCounts: Map<QuestionPendingReason, int>.unmodifiable(counts),
  );
}

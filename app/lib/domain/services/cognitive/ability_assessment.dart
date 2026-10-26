/// 能力测评（MVP）的领域层换算：把 4 项本地小测的原始读数换算成 0–100 分。
///
/// 设计来源：`docs/REVIEW_FEEDBACK.md` §8（:241-248）——认知测评要测「能力」而不是
/// 知识点；MVP 4 项小测（反应速度 / 工作记忆 / 模式识别 / 注意稳定性）都是纯本地、
/// 可复现的小测。本文件只做换算：不建表、不读写数据库、不 import Flutter；
/// `ability_scores` 落库与页面由上层接。
///
/// 三条口径：
///
/// * 分数统一夹在 0–100；没有有效读数时返回 0，而不是「默认满分」；
/// * 所有函数确定、无副作用：同一输入永远同一输出，不读时钟、不随机；
/// * 边界按闭区间取：例如反应速度中位反应时 ≤250ms → 100、≥800ms → 0。
library;

/// 反应速度：满分与零分的中位反应时分界（ms）。
const int _reactionBestMillis = 250;
const int _reactionWorstMillis = 800;

/// 工作记忆：零分与满分的最长正确跨度分界。
const int _workingMemoryFloorSpan = 3;
const int _workingMemoryCeilSpan = 9;

/// 模式识别：速度项的满分 / 零分分界（中位用时，ms）与两项权重。
const int _patternFastMillis = 1500;
const int _patternSlowMillis = 6000;
const double _patternAccuracyWeight = 70;
const double _patternSpeedWeight = 30;

/// 能力维度（MVP 4 项小测）。
enum AbilityKey {
  /// 反应速度：随机延迟后目标出现，记录中位反应时（ms）。
  reactionSpeed('reaction_speed'),

  /// 工作记忆：数字 / 空间序列回忆，记录最长正确跨度。
  workingMemory('working_memory'),

  /// 模式识别：数列 / 图形规律 4 选 1，记录正确率与中位用时。
  patternRecognition('pattern_recognition'),

  /// 注意稳定性：go / no-go 持续任务，记录命中、漏报、错报。
  attentionStability('attention_stability');

  const AbilityKey(this.code);

  /// 落库与 JSON 使用的稳定编码（小写蛇形；不随枚举改名而变）。
  final String code;

  /// 由编码找回维度；未知 / 空白编码返回 null（不猜、不抛）。
  ///
  /// 只做两端空白容错，大小写敏感：编码是内部约定，不做模糊匹配。
  static AbilityKey? fromCode(String code) {
    final normalized = code.trim();
    for (final key in AbilityKey.values) {
      if (key.code == normalized) return key;
    }
    return null;
  }
}

/// 一个维度的分数与原始读数。
class AbilityScore {
  /// 构造时校验分数必须落在 0–100。
  const AbilityScore({
    required this.key,
    required this.score,
    this.metrics = const <String, Object?>{},
  }) : assert(score >= 0 && score <= 100, '能力分数必须落在 0–100 之间');

  /// 维度。
  final AbilityKey key;

  /// 0–100 分。
  final double score;

  /// 该分数的原始读数（中位反应时、正确率等），供 `rawMetricsJson` 落库。
  final Map<String, Object?> metrics;
}

/// 反应时的中位数（ms）：空表或没有任何非负样本时返回 0。
///
/// 负数样本视为无效读数直接忽略（例如计时器抖动）；有效样本为偶数个时，
/// 取中间两个的平均值并四舍五入到整数毫秒。
int medianReactionMillis(List<int> samples) {
  final valid = <int>[
    for (final sample in samples)
      if (sample >= 0) sample,
  ]..sort();
  if (valid.isEmpty) return 0;
  final middle = valid.length ~/ 2;
  if (valid.length.isOdd) return valid[middle];
  return ((valid[middle - 1] + valid[middle]) / 2).round();
}

/// 反应速度分数：中位反应时 ≤250ms → 100，≥800ms → 0，中间线性反向。
///
/// 空表、或样本全是负数（没有有效读数）→ 0。
double scoreReactionSpeed(List<int> samplesMillis) {
  final valid = <int>[
    for (final sample in samplesMillis)
      if (sample >= 0) sample,
  ];
  if (valid.isEmpty) return 0;
  final median = medianReactionMillis(valid);
  if (median <= _reactionBestMillis) return 100;
  if (median >= _reactionWorstMillis) return 0;
  const span = _reactionWorstMillis - _reactionBestMillis;
  return _clampScore((_reactionWorstMillis - median) / span * 100);
}

/// 工作记忆分数：最长正确跨度 ≤3 → 0，≥9 → 100，中间线性。
double scoreWorkingMemory(int longestCorrectSpan) {
  if (longestCorrectSpan <= _workingMemoryFloorSpan) return 0;
  if (longestCorrectSpan >= _workingMemoryCeilSpan) return 100;
  const span = _workingMemoryCeilSpan - _workingMemoryFloorSpan;
  return _clampScore(
    (longestCorrectSpan - _workingMemoryFloorSpan) / span * 100,
  );
}

/// 模式识别分数：正确率占 70 分、速度占 30 分。
///
/// 速度项：中位用时 ≤1500ms → 1.0，≥6000ms → 0.0，中间线性；
/// 正确率与速度都先夹到合法区间，再合成并夹到 0–100。total ≤0 → 0。
double scorePatternRecognition({
  required int correct,
  required int total,
  required int medianMillis,
}) {
  if (total <= 0) return 0;
  final accuracy = _clampUnit(correct / total);
  final speed = medianMillis <= _patternFastMillis
      ? 1.0
      : medianMillis >= _patternSlowMillis
          ? 0.0
          : (_patternSlowMillis - medianMillis) /
              (_patternSlowMillis - _patternFastMillis);
  return _clampScore(
    accuracy * _patternAccuracyWeight + speed * _patternSpeedWeight,
  );
}

/// 注意稳定性分数：灵敏度与特异度各占一半。
///
/// 灵敏度 = hits / targets，特异度 = 1 - falseAlarms / nonTargets，两者先夹到
/// 0–1 再取平均 ×100；`misses` 不进入公式（漏报已隐含在 hits / targets 里），
/// 保留参数是为了让调用方把完整读数一并传进来、便于 metrics 与排查。
/// targets ≤0 或 nonTargets ≤0 时无法计算 → 0。
double scoreAttentionStability({
  required int hits,
  required int misses,
  required int falseAlarms,
  required int targets,
  required int nonTargets,
}) {
  if (targets <= 0 || nonTargets <= 0) return 0;
  final sensitivity = _clampUnit(hits / targets);
  final specificity = _clampUnit(1 - falseAlarms / nonTargets);
  return _clampScore((sensitivity + specificity) / 2 * 100);
}

double _clampUnit(double value) => value.clamp(0.0, 1.0).toDouble();

double _clampScore(double value) => value.clamp(0.0, 100.0).toDouble();

/// 由真实自测作答估计题目难度（不是预设难度）。
///
/// 样本不足时返回 `null`，界面显示“样本不足”，绝不拿先验冒充实测。
/// 这是最小的可解释估计：先验难度 + 正确率偏差；不是 IRT/MIRT，不宣称标定。
double? measuredDifficultyFromAttempts({
  required double? priorDifficulty,
  required int attempts,
  required int correct,
  int minSamples = 3,
}) {
  if (attempts < minSamples || attempts <= 0) return null;
  final accuracy = (correct.clamp(0, attempts)) / attempts;
  final prior = priorDifficulty ?? 5.0;
  // 正确率越高 → 实测难度越低；±0.5 正确率每差 0.1 调 0.4 分。
  final adjusted = prior + (0.5 - accuracy) * 4.0;
  return adjusted.clamp(1.0, 10.0);
}

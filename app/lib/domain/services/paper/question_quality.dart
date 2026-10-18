/// 找相似题里的「MindNet 有效性」质量读数：纯逻辑投影，不连数据库、不读 provider。
///
/// 相似题排序（`similar_questions.dart`）本来只有「像不像」四个信号；用户口径
/// 「肯定要融合 MindNet 对相似题进行质量评比」要求在同一批相似题里再比一层
/// 「现在做它值不值」。质量分**不改相似度**，只作为一个可选的第五个分量参与加权。
///
/// ## 读数从哪来
///
/// 输入是 `scheduling/domain_balance.dart` 的 [KnowledgePointReading]（由
/// `scheduling/cognitive_readings.dart` 的 `CognitiveReadingsAdapter` 从
/// `LibraryDiagnosis` / `AssessmentPriorEstimate` 投影出来）：
///
/// * [KnowledgePointReading.inDangerZone] ← `BottleneckType.danger`；
/// * [KnowledgePointReading.inDevelopmentZone] ← `BottleneckType.weak`；
/// * [KnowledgePointReading.priorR0] / [KnowledgePointReading.priorConfidence] ← 测评先验。
///
/// ## 口径
///
/// 与 [DomainBalanceRanker] 内部的 `_effectivenessOf` **同一公式**（那里是私有
/// 函数，这里按同一口径重写；Lead 后续把它提成公共 helper 之后可以删掉这份复制）：
///
/// ```
/// value = tuning.neutral
///       + (inDangerZone ? tuning.dangerBoost : 0)
///       + (inDevelopmentZone ? tuning.developmentBoost : 0)
///       + (priorR0 != null && priorConfidence > 0
///             ? tuning.priorWeight * (1 - clamp(priorR0, 0, 1))
///                 * clamp(priorConfidence, 0, 1)
///             : 0)
/// ```
///
/// 一个候选挂多个知识点时取 **max**（只要有一个现在最该练就值得推荐）；没有
/// 读数 → [kNeutralQuestionQuality]（中性：不惩罚"不知道"）。
///
/// ## 未标定
///
/// [kNeutralQuestionQuality] 与 [EffectivenessTuning] 的四个默认值都**未标定**
/// （与仓库其它认知层一致：显式粗映射，集中一处，标定之后只改一处）。相似题
/// 排序里的质量权重 `SimilarityWeights.quality` 默认也是 `0.0`（未标定前不启用，
/// 保证既有排序逐字节不变）——标定数据回来之前不要改这些默认值。
library;

import '../scheduling/domain_balance.dart';

/// 没有任何认知读数时的中性质量分：不惩罚、也不奖励"不知道"。
const double kNeutralQuestionQuality = 0.5;

/// 把「知识点认知读数」投影成一道候选题的 MindNet 有效性质量分（0..1）。
///
/// [knowledgePointIds] 是参与评比的知识点。找相似题时调用方应传**候选与聚焦题
/// 共用的知识点**（不是候选自己的全部知识点）：相似度已经由共用点 / 同型动作决定，
/// 这一层只回答"这些共用的点里有没有现在最该练的"。跨学科纯动作迁移没有共用点 →
/// 中性，不拿无关的弱点把榜单带偏。
///
/// 空 id、空白 id、读不到的 id 一律跳过；一个读数都没有时返回
/// [kNeutralQuestionQuality]。
double questionQuality({
  required Iterable<String> knowledgePointIds,
  required Map<String, KnowledgePointReading> readings,
  EffectivenessTuning tuning = const EffectivenessTuning(),
}) {
  if (readings.isEmpty) return kNeutralQuestionQuality;
  double? best;
  for (final raw in knowledgePointIds) {
    final id = raw.trim();
    if (id.isEmpty) continue;
    final reading = readings[id];
    if (reading == null) continue;
    final value = effectivenessFromReading(reading, tuning);
    if (best == null || value > best) best = value;
  }
  return best ?? kNeutralQuestionQuality;
}

/// 单个知识点的有效性（与 `DomainBalanceRanker._effectivenessOf` 同一公式）。
///
/// 单独暴露是为了测试与复用；正常调用走 [questionQuality]。
double effectivenessFromReading(
  KnowledgePointReading reading, [
  EffectivenessTuning tuning = const EffectivenessTuning(),
]) {
  var value = tuning.neutral;
  if (reading.inDangerZone) value += tuning.dangerBoost;
  if (reading.inDevelopmentZone) value += tuning.developmentBoost;
  final r0 = reading.priorR0;
  if (r0 != null && reading.priorConfidence > 0) {
    value += tuning.priorWeight *
        (1.0 - r0.clamp(0.0, 1.0)) *
        reading.priorConfidence.clamp(0.0, 1.0);
  }
  return value.clamp(0.0, 1.0);
}

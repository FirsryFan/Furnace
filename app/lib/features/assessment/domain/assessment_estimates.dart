/// 评测板块估计标准化与合并（设计文档 v1.0 §3.5 / §7.2 / §8.3；纯逻辑）。
///
/// 四件事：
///
/// * [standardizeMetric]：把会话级原始指标转成能力 z 值（0 = 个人基线；
///   先验常数是**系统先验，不是人群常模**，见 [kMetricBaselines] 注释）；
/// * [weightedMedian]：加权中位数，[mergeAbilityEstimate] 的合并核心；
/// * [mergeAbilityEstimate]：旧估计 + 新测量 → 新估计（质量标记只上调不确定性，
///   不删除数据；`user_override` 的旧估计不覆盖）；
/// * [deriveParams]：能力 z 值按 `ability_param_mapping` 聚合成认知模型参数。
///
/// 所有函数确定性、不读时钟、不随机、不碰数据库；需要时间的地方由调用方注入。
library;

import 'dart:math' as math;

import 'assessment_models.dart';

/// 一次会话测量在合并前的默认不确定性；质量标记会再加罚（[kQualityFlagUncertaintyPenalty]）。
const double kAbilityMeasurementBaseUncertainty = 0.5;

/// 标准化后能力 z 值的截断边界（±3 个系统先验尺度）。
const double kMetricZLimit = 3.0;

/// 能力 z 值进入参数信号时的饱和尺度：`|z| >= 2` 视作满信号。
const double kAbilitySignalScale = 2.0;

/// 推导参数的不确定性下限 / 上限（§7.2：夹在 [0.15, 0.9]）。
const double kDerivedParamMinUncertainty = 0.15;
const double kDerivedParamMaxUncertainty = 0.9;

/// 加权中位数的一个观测。
class WeightedValue {
  const WeightedValue({required this.value, required this.weight});

  final double value;
  final double weight;
}

/// 一个指标的系统先验基线：`z = (raw - baseline) / scale`（`higherIsBetter` 为假时取反）。
///
/// 基线全部是**系统先验，不是常模**：用于把量纲不同的指标放到同一 z 量纲，
/// 未经真实人群标定；换任务设计时应整表重新标定并升 `mapping_version`。
class MetricBaseline {
  const MetricBaseline({
    required this.baseline,
    required this.scale,
    required this.higherIsBetter,
  });

  /// 中性点：该指标在「个人典型状态」下的先验值。
  final double baseline;

  /// 一个 z 单位对应的原始指标变化量；必须为正。
  final double scale;

  /// 指标越高越好（正确率/跨度）还是越低越好（反应时/代价）。
  final bool higherIsBetter;
}

/// 21 个会话级指标的系统先验基线（设计文档 §3.2）。
///
/// 这些数字是**系统先验，不是常模**：只用于把指标变成同量纲 z 值，
/// 不做个体间比较，也不对外宣称「高于/低于常人」。
const Map<String, MetricBaseline> kMetricBaselines = <String, MetricBaseline>{
  MetricNames.rtMedian:
      MetricBaseline(baseline: 600, scale: 150, higherIsBetter: false),
  MetricNames.rtIqr:
      MetricBaseline(baseline: 180, scale: 80, higherIsBetter: false),
  MetricNames.accuracy:
      MetricBaseline(baseline: 0.75, scale: 0.15, higherIsBetter: true),
  MetricNames.hitRate:
      MetricBaseline(baseline: 0.80, scale: 0.15, higherIsBetter: true),
  MetricNames.falseAlarmRate:
      MetricBaseline(baseline: 0.10, scale: 0.10, higherIsBetter: false),
  MetricNames.dPrime:
      MetricBaseline(baseline: 2.0, scale: 0.8, higherIsBetter: true),
  MetricNames.rtCost:
      MetricBaseline(baseline: 0.20, scale: 0.15, higherIsBetter: false),
  MetricNames.loadSlope:
      MetricBaseline(baseline: 30, scale: 20, higherIsBetter: false),
  MetricNames.stableSpan:
      MetricBaseline(baseline: 5, scale: 1.5, higherIsBetter: true),
  MetricNames.maxSpan:
      MetricBaseline(baseline: 6, scale: 1.5, higherIsBetter: true),
  MetricNames.rtSlope:
      MetricBaseline(baseline: 5, scale: 5, higherIsBetter: false),
  MetricNames.varianceDrift:
      MetricBaseline(baseline: 1.1, scale: 0.3, higherIsBetter: false),
  MetricNames.switchCost:
      MetricBaseline(baseline: 60, scale: 40, higherIsBetter: false),
  MetricNames.conflictCost:
      MetricBaseline(baseline: 40, scale: 30, higherIsBetter: false),
  MetricNames.decisionDrift:
      MetricBaseline(baseline: 1.05, scale: 0.10, higherIsBetter: false),
  MetricNames.repeatRt:
      MetricBaseline(baseline: 600, scale: 150, higherIsBetter: false),
  MetricNames.switchRt:
      MetricBaseline(baseline: 660, scale: 150, higherIsBetter: false),
  MetricNames.congruentRt:
      MetricBaseline(baseline: 600, scale: 150, higherIsBetter: false),
  MetricNames.lapseSlope:
      MetricBaseline(baseline: 0.05, scale: 0.05, higherIsBetter: false),
  MetricNames.fishTrialAccuracy:
      MetricBaseline(baseline: 0.75, scale: 0.15, higherIsBetter: true),
  MetricNames.defaultChoiceRate:
      MetricBaseline(baseline: 0.20, scale: 0.15, higherIsBetter: false),
};

/// 加权中位数：按值升序累计权重，取第一个累计权重 >= 总权重一半的值。
///
/// * 空输入、总权重 <= 0、所有值或权重非有限 → `null`；
/// * 非正权重、非有限值的条目被忽略（不抛异常）；
/// * 恰好一半时取**较小**的观测（例如等权 [1, 2] → 1.0）。
double? weightedMedian(Iterable<WeightedValue> items) {
  final entries = <WeightedValue>[];
  for (final item in items) {
    if (!item.value.isFinite) continue;
    if (!item.weight.isFinite || item.weight <= 0) continue;
    entries.add(item);
  }
  if (entries.isEmpty) return null;
  entries.sort((a, b) {
    final byValue = a.value.compareTo(b.value);
    return byValue != 0 ? byValue : a.weight.compareTo(b.weight);
  });
  var total = 0.0;
  for (final entry in entries) {
    total += entry.weight;
  }
  if (!total.isFinite || total <= 0) return null;
  final half = total / 2;
  var cumulative = 0.0;
  for (final entry in entries) {
    cumulative += entry.weight;
    if (cumulative >= half) return entry.value;
  }
  return entries.last.value;
}

/// 一次会话测量（映射层产出，合并层消费）。
///
/// [value] 是原始指标值，[zScore] 是 [standardizeMetric] 后的能力 z 值；
/// [weight] 是 `task_ability_mapping` 的权重；[qualityFlags] 只上调不确定性，不删数据。
class AbilityMeasurement {
  const AbilityMeasurement({
    required this.abilityId,
    required this.taskId,
    required this.metricName,
    required this.value,
    required this.zScore,
    this.weight = 1.0,
    this.nTrials = 0,
    this.nMeasurements = 1,
    this.uncertainty = kAbilityMeasurementBaseUncertainty,
    this.qualityFlags = const <String>[],
    this.designVersion = kAssessmentDesignVersion,
    this.mappingVersion = kAssessmentMappingVersion,
    this.device = AssessmentDevices.unknown,
    this.measuredAt,
  });

  final String abilityId;
  final String taskId;
  final String metricName;

  /// 原始指标值（与 [metricName] 同量纲）。
  final double value;

  /// 标准化后的能力 z 值（0 = 个人基线）。
  final double zScore;

  /// 映射权重；<= 0 或非有限值的测量不参与合并。
  final double weight;

  /// 参与计算的 trial 数（质量检查用，不直接决定权重）。
  final int nTrials;

  /// 这次测量代表几次测量（通常一次会话 = 1；批量导入可大于 1）。
  final int nMeasurements;

  /// 基础不确定性（未含质量标记惩罚），0–1。
  final double uncertainty;

  final List<String> qualityFlags;
  final String designVersion;
  final String mappingVersion;
  final String device;
  final DateTime? measuredAt;

  /// 能否进入合并：id 非空、权重为正、z 值有限。
  bool get isValid =>
      abilityId.trim().isNotEmpty &&
      weight.isFinite &&
      weight > 0 &&
      zScore.isFinite;

  /// 基础不确定性 + 每个已知质量标记 0.1（去重、夹 0–1）。
  double get uncertaintyWithQualityFlags {
    final flags = <String>{};
    for (final flag in qualityFlags) {
      final normalized = flag.trim();
      if (QualityFlags.all.contains(normalized)) flags.add(normalized);
    }
    return _clamp01(
        uncertainty + kQualityFlagUncertaintyPenalty * flags.length);
  }

  /// 已知质量标记的去重个数（未知标记忽略）；合并时估算值不确定性也按它上调。
  int get qualityFlagCount {
    final flags = <String>{};
    for (final flag in qualityFlags) {
      final normalized = flag.trim();
      if (QualityFlags.all.contains(normalized)) flags.add(normalized);
    }
    return flags.length;
  }
}

/// 把原始指标标准化成能力 z 值；未知指标、非有限输入、非法基线返回 `null`。
///
/// 结果夹在 `[-kMetricZLimit, kMetricZLimit]`，避免单个极端读数压过其它证据。
double? standardizeMetric(String metricName, double rawValue) {
  final baseline = kMetricBaselines[metricName.trim()];
  if (baseline == null) return null;
  if (!rawValue.isFinite) return null;
  if (!baseline.baseline.isFinite || !baseline.scale.isFinite) return null;
  if (baseline.scale <= 0) return null;
  final z = (rawValue - baseline.baseline) / baseline.scale;
  final signed = baseline.higherIsBetter ? z : -z;
  return signed.clamp(-kMetricZLimit, kMetricZLimit).toDouble();
}

/// 合并旧能力估计与新测量（§8.3）。
///
/// 规则（逐条对应设计文档）：
///
/// * 旧估计是 `user_override` → 原样返回，不覆盖；
/// * 旧估计 `stale` 或设计/映射版本不同 → 不参与合并，新测量直接替换；
/// * `w_current = (1 - u_current) * n_current`，`w_new = (1 - u_new) * weight`，
///   合并值 = 两个 (值, 权重) 的加权中位数；
/// * 新不确定性 = `max(0.15, 1 / sqrt(n + 1))`，n = 合并后的测量数；
/// * 质量标记每个 +0.1：既上调 `u_new`（压低新证据权重），也把估算结果的不确定性
///   抬高同等幅度（夹 1.0），不删除任何数据。
AbilityEstimate? mergeAbilityEstimate({
  required AbilityEstimate? current,
  required AbilityMeasurement measurement,
  String source = EstimateSources.assessment,
}) {
  if (current != null && current.isUserOverride) return current;
  if (!measurement.isValid) return current;
  if (current != null &&
      current.abilityId.trim() != measurement.abilityId.trim()) {
    return current;
  }
  final base = _mergeableCurrent(current, measurement);
  final nCurrent =
      base == null || base.nMeasurements < 0 ? 0 : base.nMeasurements;
  final newMeasurements =
      measurement.nMeasurements < 0 ? 0 : measurement.nMeasurements;
  final nTotal = math.max(1, nCurrent + newMeasurements);
  final updatedAt = measurement.measuredAt ?? base?.updatedAt;
  final abilityId = base?.abilityId.trim().isNotEmpty == true
      ? base!.abilityId
      : measurement.abilityId.trim();
  final designVersion = measurement.designVersion;
  final mappingVersion = measurement.mappingVersion;
  final device = measurement.device;
  if (base == null) {
    return AbilityEstimate(
      abilityId: abilityId,
      mean: measurement.zScore,
      uncertainty: _applyQualityPenalty(_finalUncertainty(nTotal), measurement),
      nMeasurements: nTotal,
      source: source,
      designVersion: designVersion,
      mappingVersion: mappingVersion,
      device: device,
      updatedAt: updatedAt,
      contributions: <AbilityContribution>[
        AbilityContribution(
          taskId: measurement.taskId.trim(),
          weight: measurement.weight,
          metric: measurement.metricName.trim(),
        ),
      ],
    );
  }
  final uCurrent = _clamp01(base.uncertainty);
  final uNew = measurement.uncertaintyWithQualityFlags;
  final wCurrent = (1 - uCurrent) * nCurrent;
  final wNew = (1 - uNew) * measurement.weight;
  final mergedMean = weightedMedian(<WeightedValue>[
        WeightedValue(value: base.mean, weight: wCurrent),
        WeightedValue(value: measurement.zScore, weight: wNew),
      ]) ??
      measurement.zScore;
  final contributions = <AbilityContribution>[...base.contributions];
  final key = (measurement.taskId.trim(), measurement.metricName.trim());
  contributions.removeWhere((c) => (c.taskId.trim(), c.metric.trim()) == key);
  contributions.add(
    AbilityContribution(
      taskId: key.$1,
      weight: measurement.weight,
      metric: key.$2,
    ),
  );
  return AbilityEstimate(
    abilityId: base.abilityId,
    mean: mergedMean,
    uncertainty: _applyQualityPenalty(_finalUncertainty(nTotal), measurement),
    nMeasurements: nTotal,
    source: source,
    designVersion: designVersion,
    mappingVersion: mappingVersion,
    personalBaseline: base.personalBaseline,
    device: device,
    updatedAt: updatedAt,
    contributions: List<AbilityContribution>.unmodifiable(contributions),
  );
}

/// 由能力估计与映射表推导认知模型参数（§7.2）。
///
/// * 只处理 `enabled` 且能力估计存在的映射；
/// * `positive`：能力 z 越高参数越大；`negative`：能力 z 越高参数越小（未知方向按 positive）；
/// * `signal = Σ(w * directionSign * clamp(z / kAbilitySignalScale, -1, 1)) / Σw`，
///   `value = clamp(0.5 + 0.5 * signal, 0, 1)`；
/// * `uncertainty = Σ(w * u) / Σw`，夹在 `[kDerivedParamMinUncertainty, kDerivedParamMaxUncertainty]`；
/// * 已有 `user_override` 的参数跳过（不生成新估计，避免覆盖用户设置）；
/// * 输出按 [CognitiveParamIds.all] 排序，未知参数 id 排在后面（字典序）。
List<ParamEstimate> deriveParams({
  required List<AbilityEstimate> abilities,
  required List<AbilityParamMapping> mappings,
  List<ParamEstimate> currentParams = const <ParamEstimate>[],
  DateTime? updatedAt,
}) {
  final abilityById = <String, AbilityEstimate>{};
  for (final ability in abilities) {
    final id = ability.abilityId.trim();
    if (id.isEmpty) continue;
    abilityById[id] = ability;
  }
  final overriddenParams = <String>{};
  for (final param in currentParams) {
    if (!param.isUserOverride) continue;
    overriddenParams.add(param.paramId.trim());
  }
  final grouped = <String, List<AbilityParamMapping>>{};
  for (final mapping in mappings) {
    if (!mapping.enabled) continue;
    final paramId = mapping.paramId.trim();
    if (paramId.isEmpty) continue;
    if (overriddenParams.contains(paramId)) continue;
    if (!mapping.weight.isFinite || mapping.weight <= 0) continue;
    if (!abilityById.containsKey(mapping.abilityId.trim())) continue;
    grouped.putIfAbsent(paramId, () => <AbilityParamMapping>[]).add(mapping);
  }
  final orderedParamIds = <String>[];
  for (final paramId in CognitiveParamIds.all) {
    if (grouped.containsKey(paramId)) orderedParamIds.add(paramId);
  }
  final extraParamIds = grouped.keys
      .where((paramId) => !CognitiveParamIds.all.contains(paramId))
      .toList()
    ..sort();
  orderedParamIds.addAll(extraParamIds);
  final result = <ParamEstimate>[];
  for (final paramId in orderedParamIds) {
    final entries = grouped[paramId]!;
    var signalSum = 0.0;
    var weightSum = 0.0;
    var uncertaintySum = 0.0;
    final derivedFrom = <ParamSourceWeight>[];
    for (final mapping in entries) {
      final ability = abilityById[mapping.abilityId.trim()]!;
      final weight = mapping.weight;
      final direction = mapping.direction.trim().toLowerCase();
      final sign = direction == MappingDirection.negative ? -1.0 : 1.0;
      final mean = ability.mean.isFinite ? ability.mean : 0.0;
      final capped = mean.clamp(-kAbilitySignalScale, kAbilitySignalScale) /
          kAbilitySignalScale;
      signalSum += weight * sign * capped;
      weightSum += weight;
      uncertaintySum += weight * _clamp01(ability.uncertainty);
      derivedFrom.add(
        ParamSourceWeight(abilityId: ability.abilityId, weight: weight),
      );
    }
    if (weightSum <= 0) continue;
    final signal = signalSum / weightSum;
    final value = _clampRange(0.5 + 0.5 * signal, 0.0, 1.0);
    final uncertainty = _clampRange(
      uncertaintySum / weightSum,
      kDerivedParamMinUncertainty,
      kDerivedParamMaxUncertainty,
    );
    result.add(
      ParamEstimate(
        paramId: paramId,
        value: value,
        uncertainty: uncertainty,
        source: EstimateSources.derived,
        derivedFrom: List<ParamSourceWeight>.unmodifiable(derivedFrom),
        updatedAt: updatedAt,
      ),
    );
  }
  return List<ParamEstimate>.unmodifiable(result);
}

/// 合并后的不确定性：`max(0.15, 1 / sqrt(n + 1))`（§8.3）。
/// 估算结果的不确定性再按新测量的质量标记上调（每个已知标记 +0.1，夹 1.0）。
///
/// 与 [AbilityMeasurement.uncertaintyWithQualityFlags] 的区别：那个是「这次证据
/// 有多不可信」（进合并权重），这个是「合并后的估计有多不确定」（给用户看）。
double _applyQualityPenalty(
    double uncertainty, AbilityMeasurement measurement) {
  final count = measurement.qualityFlagCount;
  if (count == 0) return _clamp01(uncertainty);
  return _clamp01(uncertainty + kQualityFlagUncertaintyPenalty * count);
}

double _finalUncertainty(int nMeasurements) {
  final n = nMeasurements < 1 ? 1 : nMeasurements;
  return math.max(kMinEstimateUncertainty, 1 / math.sqrt(n + 1));
}

/// 能参与合并的旧估计：非空、非 user_override、非 stale、版本一致。
AbilityEstimate? _mergeableCurrent(
  AbilityEstimate? current,
  AbilityMeasurement measurement,
) {
  if (current == null) return null;
  if (current.isUserOverride) return null;
  if (current.stale) return null;
  if (current.designVersion != measurement.designVersion) return null;
  if (current.mappingVersion != measurement.mappingVersion) return null;
  return current;
}

double _clamp01(double value) => _clampRange(value, 0.0, 1.0);

double _clampRange(double value, double lower, double upper) {
  if (!value.isFinite) return lower;
  if (value < lower) return lower;
  if (value > upper) return upper;
  return value;
}

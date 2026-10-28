/// 会话指标 → 能力测量映射（设计文档 v1.0 §7.1；纯逻辑）。
///
/// 输入是一次评测会话产出的 [MetricSample]（如 `rt_median`、`d_prime`）与
/// `task_ability_mapping` 表；输出是能进入能力估计合并的 [AbilityMeasurement]。
///
/// 规则：
///
/// * 只处理 `enabled` 且 taskId 匹配的映射；
/// * 指标缺失、指标没有系统先验基线、权重非法、原始值非有限 → 跳过并记录原因，
///   绝不抛异常；
/// * 同一指标名（trim 后）在会话里出现多次时**取第一次**，后续样本不覆盖；
/// * 标准化走 [standardizeMetric]，未知指标不会静默变成 0。
library;

import 'assessment_estimates.dart';
import 'assessment_models.dart';

/// 映射跳过原因常量（`AbilityMappingSkipped.reason` 的取值）。
abstract final class AbilityMappingSkipReasons {
  /// 映射没有对应指标样本。
  static const String missingMetric = 'missing_metric';

  /// 指标样本存在，但不在 [kMetricBaselines] 先验表里。
  static const String unknownMetric = 'unknown_metric';

  /// 映射权重非有限或 <= 0。
  static const String invalidWeight = 'invalid_weight';

  /// 指标原始值为 NaN/±Infinity，无法标准化。
  static const String invalidValue = 'invalid_value';

  /// 映射没有能力 id。
  static const String missingAbility = 'missing_ability';
}

/// 一条被跳过的映射，保留原始值与原因便于排查。
class AbilityMappingSkipped {
  const AbilityMappingSkipped({
    required this.taskId,
    required this.abilityId,
    required this.metricName,
    required this.reason,
  });

  final String taskId;
  final String abilityId;
  final String metricName;

  /// 取值见 [AbilityMappingSkipReasons]。
  final String reason;
}

/// 一次映射的完整结果：能用的测量 + 被跳过的映射。
class AbilityMappingResult {
  const AbilityMappingResult({
    required this.measurements,
    required this.skipped,
  });

  static const AbilityMappingResult empty = AbilityMappingResult(
    measurements: <AbilityMeasurement>[],
    skipped: <AbilityMappingSkipped>[],
  );

  final List<AbilityMeasurement> measurements;
  final List<AbilityMappingSkipped> skipped;

  bool get isEmpty => measurements.isEmpty;
  bool get isNotEmpty => measurements.isNotEmpty;
}

/// 把一次会话的指标映射成能力测量，并保留跳过明细。
AbilityMappingResult mapSessionToAbilityMeasurements({
  required String taskId,
  required List<TaskAbilityMapping> mappings,
  required List<MetricSample> metrics,
  String designVersion = kAssessmentDesignVersion,
  String device = AssessmentDevices.unknown,
  DateTime? measuredAt,
}) {
  final normalizedTaskId = taskId.trim();
  if (normalizedTaskId.isEmpty || mappings.isEmpty) {
    return AbilityMappingResult.empty;
  }
  final samplesByName = <String, MetricSample>{};
  for (final sample in metrics) {
    final name = sample.name.trim();
    if (name.isEmpty) continue;
    samplesByName.putIfAbsent(name, () => sample);
  }
  final measurements = <AbilityMeasurement>[];
  final skipped = <AbilityMappingSkipped>[];
  for (final mapping in mappings) {
    if (!mapping.enabled) continue;
    if (mapping.taskId.trim() != normalizedTaskId) continue;
    final abilityId = mapping.abilityId.trim();
    final metricName = mapping.metricSource.trim();
    void skip(String reason) {
      skipped.add(
        AbilityMappingSkipped(
          taskId: normalizedTaskId,
          abilityId: abilityId,
          metricName: metricName,
          reason: reason,
        ),
      );
    }

    if (abilityId.isEmpty) {
      skip(AbilityMappingSkipReasons.missingAbility);
      continue;
    }
    if (!mapping.weight.isFinite || mapping.weight <= 0) {
      skip(AbilityMappingSkipReasons.invalidWeight);
      continue;
    }
    final sample = samplesByName[metricName];
    if (sample == null) {
      skip(AbilityMappingSkipReasons.missingMetric);
      continue;
    }
    if (!kMetricBaselines.containsKey(metricName)) {
      skip(AbilityMappingSkipReasons.unknownMetric);
      continue;
    }
    final zScore = standardizeMetric(metricName, sample.value);
    if (zScore == null) {
      skip(AbilityMappingSkipReasons.invalidValue);
      continue;
    }
    final mappingVersion = mapping.mappingVersion.trim().isEmpty
        ? kAssessmentMappingVersion
        : mapping.mappingVersion.trim();
    measurements.add(
      AbilityMeasurement(
        abilityId: abilityId,
        taskId: normalizedTaskId,
        metricName: metricName,
        value: sample.value,
        zScore: zScore,
        weight: mapping.weight,
        nTrials: sample.nTrials < 0 ? 0 : sample.nTrials,
        qualityFlags: List<String>.unmodifiable(sample.qualityFlags),
        designVersion: designVersion,
        mappingVersion: mappingVersion,
        device: device,
        measuredAt: measuredAt,
      ),
    );
  }
  return AbilityMappingResult(
    measurements: List<AbilityMeasurement>.unmodifiable(measurements),
    skipped: List<AbilityMappingSkipped>.unmodifiable(skipped),
  );
}

/// 只要测量、不关心跳过明细的便捷入口；`onSkipped` 可逐条接收跳过原因。
List<AbilityMeasurement> abilityMeasurementsForSession({
  required String taskId,
  required List<TaskAbilityMapping> mappings,
  required List<MetricSample> metrics,
  String designVersion = kAssessmentDesignVersion,
  String device = AssessmentDevices.unknown,
  DateTime? measuredAt,
  void Function(AbilityMappingSkipped skipped)? onSkipped,
}) {
  final result = mapSessionToAbilityMeasurements(
    taskId: taskId,
    mappings: mappings,
    metrics: metrics,
    designVersion: designVersion,
    device: device,
    measuredAt: measuredAt,
  );
  if (onSkipped != null) {
    for (final skipped in result.skipped) {
      onSkipped(skipped);
    }
  }
  return result.measurements;
}

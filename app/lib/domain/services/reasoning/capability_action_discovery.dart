/// 从已解析的推理步骤里发现「词表还不认识」的能力动作。
///
/// 背景：模型拆题时会写出内置动作之外的动作名（「配平」「画受力图」）。
/// parseChain 不丢步骤、原样保留 actionType；本文件补的是统计——哪些未知
/// actionType 已经真实出现、出现多少次、涉及多少题、卡点风险有多高，让 UI 能
/// 给出「这些动作值得加进词表」的候选列表。
///
/// 口径（都有测试守着）：
/// 1. 只统计 [CapabilityActionCatalog] 不认识的 actionType：内置与已生效的
///    自定义动作都算「认识」，不会出现在候选里；
/// 2. actionType 去首尾空白后按大小写敏感匹配（与 parseChain / byKey 一致），
///    空白串丢弃；
/// 3. 题数按 questionId 去重，空串不计数也不进样本；
/// 4. stuckRisk 只有非 null 且有限时才参与均值与高危计数，并先夹到 [0, 1]；
///    缺失/非有限值**不插补为 0**——「没测到风险」不等于「风险低」；一个动作
///    一条可用风险都没有时 [CapabilityActionCandidate.averageStuckRisk] 为
///    null；
/// 5. 排序：步数降序 → 题数降序 → actionType 升序（结果稳定、可复现，便于
///    测试与快照）。
///
/// 纯函数、同步、无 IO、不抛异常；不 import Flutter / 数据库 / 网络，也不
/// import reasoning_prompt，避免发现层与提示层耦合（调用方把 ParsedStep
/// 投影成 [CapabilityStepSample]）。
library;

import 'capability_action_overlay.dart';

/// 一条可统计的推理步骤样本。
///
/// 由调用方从 `ParsedChain.steps` 投影出来；[questionId] 由调用方提供
/// （ParsedStep 本身不带题目标识）。
class CapabilityStepSample {
  const CapabilityStepSample({
    required this.actionType,
    required this.questionId,
    this.stuckRisk,
  });

  /// parseChain 原样保留的 actionType（未知动作也保留）。
  final String actionType;

  /// 这一步属于哪道题；空串表示调用方没有题目标识。
  final String questionId;

  /// 该步的卡点风险（约定 0..1）；null 表示没测到。
  final double? stuckRisk;
}

/// 一个「词表还不认识、但已经真实出现」的动作，及出现频次统计。
class CapabilityActionCandidate {
  const CapabilityActionCandidate({
    required this.actionType,
    required this.stepCount,
    required this.questionCount,
    required this.highRiskStepCount,
    required this.averageStuckRisk,
    required this.sampleQuestionIds,
  });

  /// 未知动作的原始 actionType（已去首尾空白，保留原有大小写）。
  final String actionType;

  /// 出现过的步骤总数。
  final int stepCount;

  /// 涉及的不同题目数（按 questionId 去重；空 questionId 不计）。
  final int questionCount;

  /// 风险 >= [CapabilityActionDiscovery.defaultHighRiskThreshold]（或调用方
  /// 传入阈值）的步骤数；只数有可用 stuckRisk 的步骤。
  final int highRiskStepCount;

  /// 有可用 risk 的步骤的平均风险；没有任何可用测量时为 null。
  final double? averageStuckRisk;

  /// 样本题目 id，最多 maxSampleQuestionIds 个，按首次出现顺序。
  final List<String> sampleQuestionIds;

  /// 可直接持久化/导出成 JSON 报告（字段与构造参数一一对应）。
  Map<String, Object?> toJson() => <String, Object?>{
        'actionType': actionType,
        'stepCount': stepCount,
        'questionCount': questionCount,
        'highRiskStepCount': highRiskStepCount,
        'averageStuckRisk': averageStuckRisk,
        'sampleQuestionIds': sampleQuestionIds,
      };

  @override
  String toString() => 'CapabilityActionCandidate(actionType: $actionType, '
      'stepCount: $stepCount, questionCount: $questionCount, '
      'highRiskStepCount: $highRiskStepCount, '
      'averageStuckRisk: $averageStuckRisk)';
}

/// 未知动作发现器。纯静态：无状态、可重复调用。
class CapabilityActionDiscovery {
  const CapabilityActionDiscovery._();

  /// 高危步的默认风险阈值：stuckRisk >= 0.6 记为高危。
  static const double defaultHighRiskThreshold = 0.6;

  /// 每个候选默认保留的样本题目数。
  static const int defaultMaxSampleQuestionIds = 5;

  /// 统计 [samples] 里 [catalog] 不认识的 actionType。
  ///
  /// [catalog] 传 null 表示只用内置词表；要认自定义动作请传
  /// `overlay.catalog`。返回列表按「步数降序 → 题数降序 → actionType 升序」
  /// 排序，且不可变。
  static List<CapabilityActionCandidate> discover({
    required Iterable<CapabilityStepSample> samples,
    CapabilityActionCatalog? catalog,
    double highRiskThreshold = defaultHighRiskThreshold,
    int maxSampleQuestionIds = defaultMaxSampleQuestionIds,
  }) {
    final known = catalog ?? CapabilityActionCatalog.builtIn;
    final threshold = _normalizeThreshold(highRiskThreshold);
    final sampleLimit = maxSampleQuestionIds < 0 ? 0 : maxSampleQuestionIds;
    final accumulators = <String, _Accumulator>{};
    for (final sample in samples) {
      final actionType = sample.actionType.trim();
      if (actionType.isEmpty) {
        continue;
      }
      if (known.byKey(actionType) != null) {
        continue;
      }
      final accumulator = accumulators.putIfAbsent(
        actionType,
        _Accumulator.new,
      );
      accumulator.stepCount += 1;
      final questionId = sample.questionId.trim();
      if (questionId.isNotEmpty) {
        accumulator.questionIds.add(questionId);
      }
      final risk = sample.stuckRisk;
      if (risk != null && risk.isFinite) {
        final normalizedRisk = _clampRisk(risk);
        accumulator.riskSum += normalizedRisk;
        accumulator.riskCount += 1;
        if (normalizedRisk >= threshold) {
          accumulator.highRiskStepCount += 1;
        }
      }
    }
    final candidates = <CapabilityActionCandidate>[
      for (final entry in accumulators.entries)
        CapabilityActionCandidate(
          actionType: entry.key,
          stepCount: entry.value.stepCount,
          questionCount: entry.value.questionIds.length,
          highRiskStepCount: entry.value.highRiskStepCount,
          averageStuckRisk: entry.value.riskCount == 0
              ? null
              : entry.value.riskSum / entry.value.riskCount,
          sampleQuestionIds: List<String>.unmodifiable(
            entry.value.questionIds.take(sampleLimit),
          ),
        ),
    ];
    candidates.sort((left, right) {
      final byStepCount = right.stepCount.compareTo(left.stepCount);
      if (byStepCount != 0) {
        return byStepCount;
      }
      final byQuestionCount = right.questionCount.compareTo(left.questionCount);
      if (byQuestionCount != 0) {
        return byQuestionCount;
      }
      return left.actionType.compareTo(right.actionType);
    });
    return List<CapabilityActionCandidate>.unmodifiable(candidates);
  }

  /// 阈值夹到 [0, 1]；非有限值退回默认阈值（NaN/infinity 不能变成 -inf 边界）。
  static double _normalizeThreshold(double value) {
    if (!value.isFinite) {
      return defaultHighRiskThreshold;
    }
    return _clampRisk(value);
  }

  static double _clampRisk(double value) {
    if (value < 0) {
      return 0.0;
    }
    if (value > 1) {
      return 1.0;
    }
    return value;
  }
}

class _Accumulator {
  int stepCount = 0;
  final Set<String> questionIds = <String>{};
  int highRiskStepCount = 0;
  double riskSum = 0;
  int riskCount = 0;
}

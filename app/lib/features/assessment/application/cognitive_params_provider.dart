/// Thread（ThreadFlow）读取本机认知模型参数的纯逻辑接口（评测板块设计文档 §11 P2）。
///
/// 设计目标：ThreadFlow 只关心「每个认知参数该用哪个值」，不关心它来自真实评测、
/// 推导还是默认先验。因此这里把三类信息拆开：
/// - 原始参数估计（[ParamEstimate]，来自 assessment 板块的落库数据）；
/// - 回退规则（不确定性高于阈值时回退系统默认值，见 [CognitiveParamsProvider] 文档）；
/// - Thread 侧建议（[ThreadWeightSuggestion]，带 `usedDefault` 标记，便于 UI 标注「用默认值」）。
///
/// 本文件是纯 Dart：不 import Flutter、不读时钟、不随机、不碰数据库。
library;

import '../domain/assessment_models.dart';

/// Thread 侧参数不确定性阈值（设计文档 §11）：高于该值即回退默认先验。
const double kThreadParamMaxUncertainty = 0.4;

/// Thread 关心的认知参数 id，顺序与 [CognitiveParamIds.all] 一致。
const List<String> kThreadRelevantParamIds = <String>[
  CognitiveParamIds.taskDurationEstimate,
  CognitiveParamIds.chunkingThreshold,
  CognitiveParamIds.interruptionCost,
  CognitiveParamIds.switchPenalty,
  CognitiveParamIds.highLoadDiscount,
  CognitiveParamIds.similarFatiguePenalty,
  CognitiveParamIds.scheduleIntensityCap,
  CognitiveParamIds.expectedPressure,
  CognitiveParamIds.timeOfDayBias,
];

/// 未在 [kCognitiveParamSpecs] 里登记的参数使用的中性出厂值。
const double _fallbackDefaultValue = 0.5;

final Map<String, CognitiveParamSpec> _specById = <String, CognitiveParamSpec>{
  for (final spec in kCognitiveParamSpecs) spec.id: spec,
};

/// 系统默认先验值：登记过的参数取 spec，未知参数取中性出厂值。
double _defaultValueOf(String paramId) {
  return _specById[paramId]?.defaultValue ?? _fallbackDefaultValue;
}

/// 系统默认先验不确定性：登记过的参数取 spec，未知参数取 [kDefaultAbilityUncertainty]。
double _defaultUncertaintyOf(String paramId) {
  return _specById[paramId]?.defaultUncertainty ?? kDefaultAbilityUncertainty;
}

/// 一条给 Thread 的参数建议。
///
/// [usedDefault] 为 true 表示最终值来自系统默认先验（原始估计缺失、本身就是默认、
/// 或不确定性过高被回退），Thread 侧可以据此降权或标注「暂用默认值」。
class ThreadWeightSuggestion {
  const ThreadWeightSuggestion({
    required this.paramId,
    required this.defaultValue,
    required this.suggestedValue,
    required this.uncertainty,
    required this.source,
    required this.usedDefault,
  });

  final String paramId;
  final double defaultValue;
  final double suggestedValue;
  final double uncertainty;
  final String source;
  final bool usedDefault;

  bool get isUserOverride => source == EstimateSources.userOverride;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'param_id': paramId,
      'default_value': defaultValue,
      'suggested_value': suggestedValue,
      'uncertainty': uncertainty,
      'source': source,
      'used_default': usedDefault,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ThreadWeightSuggestion &&
        other.paramId == paramId &&
        other.defaultValue == defaultValue &&
        other.suggestedValue == suggestedValue &&
        other.uncertainty == uncertainty &&
        other.source == source &&
        other.usedDefault == usedDefault;
  }

  @override
  int get hashCode {
    return Object.hash(
      paramId,
      defaultValue,
      suggestedValue,
      uncertainty,
      source,
      usedDefault,
    );
  }

  @override
  String toString() {
    return 'ThreadWeightSuggestion(paramId: $paramId, defaultValue: $defaultValue, '
        'suggestedValue: $suggestedValue, uncertainty: $uncertainty, '
        'source: $source, usedDefault: $usedDefault)';
  }
}

/// 把「本机参数估计 + 回退规则」包装成 Thread 可消费的只读视图。
///
/// 回退规则（优先级从高到低）：
/// 1. 没有原始估计 → 用 [kCognitiveParamSpecs] 的 defaultValue/defaultUncertainty，
///    来源视为 [EstimateSources.defaultPrior]；
/// 2. 原始来源是 [EstimateSources.defaultPrior] → 原样使用；
/// 3. 原始来源是 [EstimateSources.userOverride] → 永远信任，保留值/不确定性/来源，
///    不受阈值影响；
/// 4. 其余来源（assessment_v1 / derived / 未知来源）：不确定性高于 [maxUncertainty]
///    （含 NaN/inf 这类不可用读数）→ 回退默认；等于或低于阈值 → 保留原始。
class CognitiveParamsProvider {
  /// 直接用给定的估计表创建。
  ///
  /// 原始数据请走 [CognitiveParamsProvider.fromEstimates]，它会做 id 归一化与
  /// 只读包装；这里保留 const 构造是为了让上层能创建常量 provider（如测试替身）。
  const CognitiveParamsProvider({
    required Map<String, ParamEstimate> estimates,
    this.maxUncertainty = kThreadParamMaxUncertainty,
  }) : _estimates = estimates;

  /// 从原始估计列表创建：id 去首尾空白、丢弃空 id、重复 id 后写覆盖先写。
  factory CognitiveParamsProvider.fromEstimates(
    Iterable<ParamEstimate> estimates, {
    double maxUncertainty = kThreadParamMaxUncertainty,
  }) {
    final normalized = <String, ParamEstimate>{};
    for (final estimate in estimates) {
      final id = estimate.paramId.trim();
      if (id.isEmpty) continue;
      normalized[id] = estimate;
    }
    return CognitiveParamsProvider(
      estimates: Map<String, ParamEstimate>.unmodifiable(normalized),
      maxUncertainty: maxUncertainty,
    );
  }

  final Map<String, ParamEstimate> _estimates;

  /// 原始估计表（只读视图，id 已由 [CognitiveParamsProvider.fromEstimates] 归一化）。
  Map<String, ParamEstimate> get estimates {
    return Map<String, ParamEstimate>.unmodifiable(_estimates);
  }

  /// 不确定性阈值：严格高于它才回退默认；等于阈值保留原始。
  final double maxUncertainty;

  /// Thread 侧参数列表。
  ///
  /// [paramIds] 为 null 时返回 [kThreadRelevantParamIds] 全部九项；显式传入时
  /// 已知 id 按 [kThreadRelevantParamIds] 顺序、未知 id 排后并按字典序，
  /// 重复 id 去重、空白 id 丢弃。每项都已套用回退规则。
  Map<String, ParamEstimate> getParamsForThread({Iterable<String>? paramIds}) {
    final ordered = _orderedParamIds(paramIds);
    return Map<String, ParamEstimate>.unmodifiable(<String, ParamEstimate>{
      for (final id in ordered) id: _effectiveEstimate(id),
    });
  }

  /// 单个参数的最终估计（id 会去首尾空白）；未知/缺失 id 返回默认先验。
  ParamEstimate estimateFor(String paramId) {
    return _effectiveEstimate(paramId.trim());
  }

  /// [getParamsForThread] 的建议列表包装，见顶层 [threadWeightSuggestions]。
  List<ThreadWeightSuggestion> suggestions({Iterable<String>? paramIds}) {
    return threadWeightSuggestions(this, paramIds: paramIds);
  }

  List<String> _orderedParamIds(Iterable<String>? paramIds) {
    if (paramIds == null) return List<String>.of(kThreadRelevantParamIds);
    final requested = <String>{};
    for (final raw in paramIds) {
      final id = raw.trim();
      if (id.isEmpty) continue;
      requested.add(id);
    }
    final known = <String>[
      for (final id in kThreadRelevantParamIds)
        if (requested.contains(id)) id,
    ];
    final unknown = <String>[
      for (final id in requested)
        if (!kThreadRelevantParamIds.contains(id)) id,
    ]..sort();
    return <String>[...known, ...unknown];
  }

  ParamEstimate _effectiveEstimate(String id) {
    final fallback = ParamEstimate(
      paramId: id,
      value: _defaultValueOf(id),
      uncertainty: _defaultUncertaintyOf(id),
      source: EstimateSources.defaultPrior,
    );
    final raw = _estimates[id];
    if (raw == null) return fallback;
    if (raw.source == EstimateSources.defaultPrior) return raw;
    if (raw.source == EstimateSources.userOverride) return raw;
    if (!raw.uncertainty.isFinite || raw.uncertainty > maxUncertainty) {
      return fallback;
    }
    return raw;
  }
}

/// 把 provider 的参数表转成 Thread 侧建议列表（[CognitiveParamsProvider.suggestions] 的
/// 顶层包装，便于不持有 provider 的调用方使用）。
///
/// 顺序与 [CognitiveParamsProvider.getParamsForThread] 一致；
/// `usedDefault` = 最终来源是 [EstimateSources.defaultPrior]。
List<ThreadWeightSuggestion> threadWeightSuggestions(
  CognitiveParamsProvider provider, {
  Iterable<String>? paramIds,
}) {
  final params = provider.getParamsForThread(paramIds: paramIds);
  return List<ThreadWeightSuggestion>.unmodifiable(<ThreadWeightSuggestion>[
    for (final entry in params.entries)
      ThreadWeightSuggestion(
        paramId: entry.key,
        defaultValue: _defaultValueOf(entry.key),
        suggestedValue: entry.value.value,
        uncertainty: entry.value.uncertainty,
        source: entry.value.source,
        usedDefault: entry.value.source == EstimateSources.defaultPrior,
      ),
  ]);
}

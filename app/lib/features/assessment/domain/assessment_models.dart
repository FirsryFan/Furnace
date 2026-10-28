/// 用户评测板块的共享领域契约（设计文档 v1.0，2026-10-29）。
///
/// 这个文件是评测板块**唯一的术语与类型来源**：任务注册、运行引擎、指标计算、
/// 估计合并、映射解析、数据层与界面都只 import 它，不各自造一套近似类型。
///
/// 设计文档的三层纪律（写代码前先记住）：
///
/// * 评测数据（trial 级原始记录 + 会话级统计量）→ 能力指标（硬件读数）→
///   认知模型参数（模型内变量，多对多）；四层之间只靠本文件的类型与映射表连接。
/// * 默认值不是常模（`source: default`，`uncertainty: 0.7`）；个体内基线。
/// * 每条估计都带 `uncertainty`；质量标记只上调不确定性，绝不删除数据。
///
/// 本文件纯 Dart：不 import Flutter、不读时钟、不随机、不碰数据库。
library;

/// 任务设计版本。任务设计（刺激、时长、trial 数）一改就必须升版：
/// 旧测量会标 `stale`，不直接参与合并。
const String kAssessmentDesignVersion = '1.0';

/// 映射版本（任务→能力指标、能力指标→认知模型参数的权重表版本）。
const String kAssessmentMappingVersion = '1.0';

/// 系统先验的默认不确定性；数字越小越可信。默认值不是人群常模。
const double kDefaultAbilityUncertainty = 0.7;

/// `decision_fatigue` 暂定（设计文档 §4.3.8 / §5）：默认 0.9，先验证信度。
const double kDecisionFatigueAbilityUncertainty = 0.9;

/// `cross_language_cost` 只由 Stroop 的可选映射产生，默认 0.8。
const double kCrossLanguageCostUncertainty = 0.8;

/// 不确定性下限：重测再多也不归零（`uncertainty = max(0.15, 1/sqrt(n+1))`）。
const double kMinEstimateUncertainty = 0.15;

/// 每个质量标记给新测量的不确定性加 0.1（只加不删）。
const double kQualityFlagUncertaintyPenalty = 0.1;

/// 设备基线：同一套任务在不同设备上的输入延迟不同，不混用。
abstract final class AssessmentDevices {
  static const String windowsMouse = 'windows_mouse';
  static const String androidTouch = 'android_touch';
  static const String unknown = 'unknown';
}

/// 测评任务类型（设计文档 §4.1 的 `task_type`）。
///
/// 运行引擎按类型分派刺激生成器；新增任务只要用已有类型加配置即可，不改引擎。
enum AssessmentTaskType {
  choiceReaction('choice_reaction'),
  goNogo('go_nogo'),
  nBack('n_back'),
  stroop('stroop'),
  switching('switching'),
  fatigue('fatigue'),
  digitSpan('digit_span'),
  decisionFatigue('decision_fatigue');

  const AssessmentTaskType(this.code);

  /// 落库 / JSON 的稳定编码（不随枚举改名而变）。
  final String code;

  /// 由编码找回类型；未知 / 空白返回 null（不猜、不抛）。
  static AssessmentTaskType? fromCode(String code) {
    final normalized = code.trim();
    for (final type in AssessmentTaskType.values) {
      if (type.code == normalized) return type;
    }
    return null;
  }
}

/// 能力指标 id（设计文档 §5）。这些是**硬件读数**，不是知识点掌握度。
abstract final class AbilityIds {
  static const String processingSpeed = 'processing_speed';
  static const String inhibitoryControl = 'inhibitory_control';
  static const String workingMemoryCapacity = 'working_memory_capacity';
  static const String workingMemoryUpdateSpeed = 'working_memory_update_speed';
  static const String distractionResistance = 'distraction_resistance';
  static const String switchCostAbility = 'switch_cost_ability';
  static const String fatigueSlope = 'fatigue_slope';
  static const String stabilityDrift = 'stability_drift';
  static const String decisionFatigue = 'decision_fatigue';
  static const String crossLanguageCost = 'cross_language_cost';

  /// 全部能力指标，顺序即画像页的默认展示顺序。
  static const List<String> all = <String>[
    processingSpeed,
    inhibitoryControl,
    workingMemoryCapacity,
    workingMemoryUpdateSpeed,
    distractionResistance,
    switchCostAbility,
    fatigueSlope,
    stabilityDrift,
    decisionFatigue,
    crossLanguageCost,
  ];
}

/// 一个能力指标的系统先验（来源任务 + 默认不确定性）。
class AbilitySpec {
  const AbilitySpec({
    required this.id,
    required this.defaultUncertainty,
    this.defaultMean = 0,
  });

  final String id;
  final double defaultUncertainty;

  /// 没测过时的中位数先验；0 = 相对个人基线的中性点。
  final double defaultMean;
}

/// 10 个能力指标的定义（顺序稳定，画像页与导出都按它遍历）。
const List<AbilitySpec> kAbilitySpecs = <AbilitySpec>[
  AbilitySpec(
      id: AbilityIds.processingSpeed,
      defaultUncertainty: kDefaultAbilityUncertainty),
  AbilitySpec(
      id: AbilityIds.inhibitoryControl,
      defaultUncertainty: kDefaultAbilityUncertainty),
  AbilitySpec(
      id: AbilityIds.workingMemoryCapacity,
      defaultUncertainty: kDefaultAbilityUncertainty),
  AbilitySpec(
      id: AbilityIds.workingMemoryUpdateSpeed,
      defaultUncertainty: kDefaultAbilityUncertainty),
  AbilitySpec(
      id: AbilityIds.distractionResistance,
      defaultUncertainty: kDefaultAbilityUncertainty),
  AbilitySpec(
      id: AbilityIds.switchCostAbility,
      defaultUncertainty: kDefaultAbilityUncertainty),
  AbilitySpec(
      id: AbilityIds.fatigueSlope,
      defaultUncertainty: kDefaultAbilityUncertainty),
  AbilitySpec(
      id: AbilityIds.stabilityDrift,
      defaultUncertainty: kDefaultAbilityUncertainty),
  AbilitySpec(
      id: AbilityIds.decisionFatigue,
      defaultUncertainty: kDecisionFatigueAbilityUncertainty),
  AbilitySpec(
      id: AbilityIds.crossLanguageCost,
      defaultUncertainty: kCrossLanguageCostUncertainty),
];

/// 认知模型参数 id（设计文档 §6）。这些是**模型内变量**，不是能力读数；
/// 界面上不能把两者混叫「能力」。
abstract final class CognitiveParamIds {
  static const String taskDurationEstimate = 'task_duration_estimate';
  static const String chunkingThreshold = 'chunking_threshold';
  static const String interruptionCost = 'interruption_cost';
  static const String switchPenalty = 'switch_penalty';
  static const String highLoadDiscount = 'high_load_discount';
  static const String similarFatiguePenalty = 'similar_fatigue_penalty';
  static const String scheduleIntensityCap = 'schedule_intensity_cap';
  static const String expectedPressure = 'expected_pressure';
  static const String timeOfDayBias = 'time_of_day_bias';

  static const List<String> all = <String>[
    taskDurationEstimate,
    chunkingThreshold,
    interruptionCost,
    switchPenalty,
    highLoadDiscount,
    similarFatiguePenalty,
    scheduleIntensityCap,
    expectedPressure,
    timeOfDayBias,
  ];
}

/// 一个认知模型参数的系统先验。
class CognitiveParamSpec {
  const CognitiveParamSpec({
    required this.id,
    required this.defaultValue,
    required this.defaultUncertainty,
  });

  final String id;

  /// 默认值：模型侧按自己的量纲读，0.5 是多数参数的「中性」出厂值。
  final double defaultValue;
  final double defaultUncertainty;
}

/// 9 个认知模型参数的定义（顺序稳定）。
const List<CognitiveParamSpec> kCognitiveParamSpecs = <CognitiveParamSpec>[
  CognitiveParamSpec(
      id: CognitiveParamIds.taskDurationEstimate,
      defaultValue: 0.5,
      defaultUncertainty: kDefaultAbilityUncertainty),
  CognitiveParamSpec(
      id: CognitiveParamIds.chunkingThreshold,
      defaultValue: 0.5,
      defaultUncertainty: kDefaultAbilityUncertainty),
  CognitiveParamSpec(
      id: CognitiveParamIds.interruptionCost,
      defaultValue: 0.5,
      defaultUncertainty: kDefaultAbilityUncertainty),
  CognitiveParamSpec(
      id: CognitiveParamIds.switchPenalty,
      defaultValue: 0.5,
      defaultUncertainty: kDefaultAbilityUncertainty),
  CognitiveParamSpec(
      id: CognitiveParamIds.highLoadDiscount,
      defaultValue: 0.5,
      defaultUncertainty: kDefaultAbilityUncertainty),
  CognitiveParamSpec(
      id: CognitiveParamIds.similarFatiguePenalty,
      defaultValue: 0.5,
      defaultUncertainty: kDefaultAbilityUncertainty),
  CognitiveParamSpec(
      id: CognitiveParamIds.scheduleIntensityCap,
      defaultValue: 0.5,
      defaultUncertainty: kDefaultAbilityUncertainty),
  CognitiveParamSpec(
      id: CognitiveParamIds.expectedPressure,
      defaultValue: 0.5,
      defaultUncertainty: kDefaultAbilityUncertainty),
  CognitiveParamSpec(
      id: CognitiveParamIds.timeOfDayBias,
      defaultValue: 0.5,
      defaultUncertainty: kDefaultAbilityUncertainty),
];

/// 统计指标名（设计文档 §3.2）。落 `assessment_metrics.metric_name`。
abstract final class MetricNames {
  static const String rtMedian = 'rt_median';
  static const String rtIqr = 'rt_iqr';
  static const String accuracy = 'accuracy';
  static const String hitRate = 'hit_rate';
  static const String falseAlarmRate = 'false_alarm_rate';
  static const String dPrime = 'd_prime';
  static const String rtCost = 'rt_cost';
  static const String loadSlope = 'load_slope';
  static const String stableSpan = 'stable_span';
  static const String maxSpan = 'max_span';
  static const String rtSlope = 'rt_slope';
  static const String varianceDrift = 'variance_drift';
  static const String switchCost = 'switch_cost';
  static const String conflictCost = 'conflict_cost';
  static const String decisionDrift = 'decision_drift';
  static const String repeatRt = 'repeat_rt';
  static const String switchRt = 'switch_rt';
  static const String congruentRt = 'congruent_rt';
  static const String lapseSlope = 'lapse_slope';
  static const String fishTrialAccuracy = 'fish_trial_accuracy';
  static const String defaultChoiceRate = 'default_choice_rate';
}

/// 数据质量标记（设计文档 §9）。只上调不确定性，不删数据、不判作弊。
abstract final class QualityFlags {
  static const String practiceBlock = 'practice_block';
  static const String backgroundSwitch = 'background_switch';
  static const String tooFast = 'too_fast';
  static const String tooSlow = 'too_slow';
  static const String highLapse = 'high_lapse';
  static const String deviceMismatch = 'device_mismatch';
  static const String incomplete = 'incomplete';
  static const String lowTrialCount = 'low_trial_count';

  static const List<String> all = <String>[
    practiceBlock,
    backgroundSwitch,
    tooFast,
    tooSlow,
    highLapse,
    deviceMismatch,
    incomplete,
    lowTrialCount,
  ];
}

/// 估计来源（设计文档 §3.5）。
abstract final class EstimateSources {
  static const String defaultPrior = 'default';
  static const String assessment = 'assessment_v1';
  static const String derived = 'derived';
  static const String userOverride = 'user_override';
}

/// 映射方向（设计文档 §7.2）。
abstract final class MappingDirection {
  static const String positive = 'positive';
  static const String negative = 'negative';
}

/// 一次 trial 的完整记录（设计文档 §10.1 `assessment_trials`）。
///
/// [stimulus] / [response] 是任务自定义的原始数据（JSON 可编码对象），
/// 指标计算只读 [rtMs] / [correct] / [isPractice] 与质量标记，不解析私有字段。
class TrialResult {
  const TrialResult({
    required this.trialIndex,
    required this.blockIndex,
    this.stimulus = const <String, Object?>{},
    this.response = const <String, Object?>{},
    this.rtMs,
    this.correct,
    this.isPractice = false,
    this.timestamp,
  });

  /// 本会话内从 0 开始的序号（练习 trial 也占号，保持原始顺序可追溯）。
  final int trialIndex;

  /// 块序号（单块任务恒为 0；疲劳块按 60 秒分段）。
  final int blockIndex;

  final Map<String, Object?> stimulus;
  final Map<String, Object?> response;

  /// 反应时（ms）；没反应 / 超时为 null（不是 0 —— 0 会被当成一次极快反应）。
  final int? rtMs;

  /// 是否正确；开放式任务（纯反应时）可为 null。
  final bool? correct;

  final bool isPractice;

  final DateTime? timestamp;

  /// 有效 trial：非练习。所有指标只统计有效 trial。
  bool get isMeasured => !isPractice;
}

/// 会话级统计量（设计文档 §10.1 `assessment_metrics`）。
class MetricSample {
  const MetricSample({
    required this.name,
    required this.value,
    required this.nTrials,
    this.qualityFlags = const <String>[],
  });

  final String name;
  final double value;
  final int nTrials;
  final List<String> qualityFlags;
}

/// 任务定义（设计文档 §4.1 / `assessment_tasks`）。
///
/// [config] 是声明式配置（结构 / 刺激 / 计时 / 反应 / 结构），键约定见
/// `task_registry.dart` 顶部注释；新增任务只加配置，不改引擎。
class AssessmentTaskConfig {
  const AssessmentTaskConfig({
    required this.taskId,
    required this.displayName,
    required this.taskType,
    required this.estimatedDurationSeconds,
    this.designVersion = kAssessmentDesignVersion,
    this.config = const <String, Object?>{},
    this.producedMetrics = const <String>[],
    this.qualityChecks = const <String>[],
    this.enabled = true,
    this.provisional = false,
  });

  final String taskId;
  final String displayName;
  final AssessmentTaskType taskType;
  final int estimatedDurationSeconds;
  final String designVersion;
  final Map<String, Object?> config;
  final List<String> producedMetrics;
  final List<String> qualityChecks;

  /// 用户可选的任务；暂定任务（decision_fatigue）默认关闭。
  final bool enabled;

  /// `provisional: true`（设计文档 §4.3.8）：信度未验证，只当「当天状态」。
  final bool provisional;
}

/// 一条能力估计（设计文档 §5 / `ability_estimates`）。
class AbilityEstimate {
  const AbilityEstimate({
    required this.abilityId,
    required this.mean,
    required this.uncertainty,
    required this.nMeasurements,
    required this.source,
    this.designVersion = kAssessmentDesignVersion,
    this.mappingVersion = kAssessmentMappingVersion,
    this.personalBaseline = const <String, Object?>{},
    this.device = AssessmentDevices.unknown,
    this.updatedAt,
    this.stale = false,
    this.contributions = const <AbilityContribution>[],
  });

  final String abilityId;

  /// 相对个人基线的标准化值（z-score 量纲）：0 = 自己的典型水平。
  final double mean;

  /// 0–1，越小越可信；系统先验是 0.7，重测最低 0.15。
  final double uncertainty;
  final int nMeasurements;

  /// default / assessment_v1 / user_override。
  final String source;
  final String designVersion;
  final String mappingVersion;
  final Map<String, Object?> personalBaseline;
  final String device;
  final DateTime? updatedAt;

  /// 设计版本升级后旧测量标 stale，不直接参与合并。
  final bool stale;
  final List<AbilityContribution> contributions;

  bool get isUserOverride => source == EstimateSources.userOverride;
  bool get isDefault => source == EstimateSources.defaultPrior;
}

/// 一项能力被哪个任务、哪个指标贡献了多少权重。
class AbilityContribution {
  const AbilityContribution({
    required this.taskId,
    required this.weight,
    required this.metric,
  });

  final String taskId;
  final double weight;
  final String metric;
}

/// 一条认知模型参数估计（设计文档 §6 / `cognitive_params`）。
class ParamEstimate {
  const ParamEstimate({
    required this.paramId,
    required this.value,
    required this.uncertainty,
    required this.source,
    this.derivedFrom = const <ParamSourceWeight>[],
    this.updatedAt,
  });

  final String paramId;
  final double value;
  final double uncertainty;

  /// default / derived / user_override。
  final String source;
  final List<ParamSourceWeight> derivedFrom;
  final DateTime? updatedAt;

  bool get isUserOverride => source == EstimateSources.userOverride;
}

/// 参数由哪些能力指标推导、权重多少。
class ParamSourceWeight {
  const ParamSourceWeight({required this.abilityId, required this.weight});

  final String abilityId;
  final double weight;
}

/// 任务 → 能力指标的映射（设计文档 §7.1 / `task_ability_mapping`）。
class TaskAbilityMapping {
  const TaskAbilityMapping({
    required this.taskId,
    required this.abilityId,
    required this.weight,
    required this.metricSource,
    this.enabled = true,
    this.mappingVersion = kAssessmentMappingVersion,
  });

  final String taskId;
  final String abilityId;
  final double weight;

  /// 用哪个会话级指标估计（`MetricNames` 常量）。
  final String metricSource;
  final bool enabled;
  final String mappingVersion;
}

/// 能力指标 → 认知模型参数的映射（设计文档 §7.2 / `ability_param_mapping`）。
class AbilityParamMapping {
  const AbilityParamMapping({
    required this.abilityId,
    required this.paramId,
    required this.weight,
    required this.direction,
    this.enabled = true,
    this.mappingVersion = kAssessmentMappingVersion,
  });

  final String abilityId;
  final String paramId;
  final double weight;

  /// positive / negative（negative：能力越弱，参数越大）。
  final String direction;
  final bool enabled;
  final String mappingVersion;
}

/// 一次已完成 / 中断的测评会话摘要（结果页与历史列表读它）。
class AssessmentSessionSummary {
  const AssessmentSessionSummary({
    required this.sessionId,
    required this.taskId,
    required this.designVersion,
    required this.device,
    required this.startedAt,
    required this.completedAt,
    required this.status,
    this.qualityFlags = const <String>[],
    this.metrics = const <MetricSample>[],
  });

  final String sessionId;
  final String taskId;
  final String designVersion;
  final String device;
  final DateTime startedAt;
  final DateTime? completedAt;

  /// completed / incomplete / aborted。
  final String status;
  final List<String> qualityFlags;
  final List<MetricSample> metrics;
}

/// 数据层契约：界面与运行引擎只依赖这组方法，不直接碰 Drift。
///
/// 实现见 `app/lib/data/repositories/cognitive_profile_repository.dart`。
abstract class AssessmentStore {
  /// 首次打开时写入默认任务与默认映射（幂等）；不覆盖用户改过的映射。
  Future<void> ensureSeeded({DateTime? now});

  /// 可选任务（默认只读 enabled 的）。
  Future<List<AssessmentTaskConfig>> listTasks({bool enabledOnly = true});

  /// 落一次会话 + 全部 trial + 统计量，返回 session id。
  Future<String> recordSession({
    required String taskId,
    required String designVersion,
    required String device,
    required DateTime startedAt,
    required DateTime completedAt,
    required String status,
    required List<TrialResult> trials,
    required List<MetricSample> metrics,
    List<String> qualityFlags = const <String>[],
  });

  Future<List<AbilityEstimate>> readAbilities();
  Future<List<ParamEstimate>> readCognitiveParams();

  /// 写回合并后的估计（能力与参数各一份）；存在即更新，source=user_override 的
  /// 行不在这里被自动覆盖（调用方负责判断）。
  Future<void> writeEstimates({
    List<AbilityEstimate> abilities = const <AbilityEstimate>[],
    List<ParamEstimate> params = const <ParamEstimate>[],
  });

  Future<List<TaskAbilityMapping>> readTaskAbilityMappings(
      {bool enabledOnly = true});
  Future<List<AbilityParamMapping>> readAbilityParamMappings(
      {bool enabledOnly = true});

  /// 最近会话（新→旧）。
  Future<List<AssessmentSessionSummary>> readSessions({int limit = 20});
  Future<AssessmentSessionSummary?> readSession(String sessionId);

  /// 用户手动覆盖一项能力（标 user_override，之后停止自动更新）。
  Future<void> setAbilityUserOverride(
      {required String abilityId, required double mean});

  /// 用户手动覆盖一个认知参数。
  Future<void> setParamUserOverride(
      {required String paramId, required double value});

  /// 撤销一项能力的手动覆盖，**但不丢数值**：`n_measurements > 0` 时 source 回到
  /// `assessment_v1`（下次评测继续自动合并），从未测过则回到 `default`；
  /// mean / uncertainty 保持原样。用户按「恢复自动更新」时调用。
  Future<void> clearAbilityUserOverride({required String abilityId});

  /// 撤销一个认知参数的手动覆盖：由能力推导过的回 `derived`，否则回 `default`；
  /// value / uncertainty 保持原样。
  Future<void> clearParamUserOverride({required String paramId});
}

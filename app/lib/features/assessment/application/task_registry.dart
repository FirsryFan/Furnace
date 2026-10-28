/// 评测板块的任务注册表：10 个任务定义 + 两张默认映射表。
///
/// 依据：设计文档 v1.0 §4.2（任务清单）、§4.3（试次与时长）、§7.1（任务→能力）、
/// §7.2（能力→认知参数）、§5（能力先验与不确定性）。本文件是**数据**，不含逻辑；
/// 新增任务只加 [AssessmentTaskConfig]，引擎与刺激生成器按 taskId / taskType 分派。
///
/// ## config map 键契约（新增任务必须遵守）
///
/// 通用：
/// * `trials`（int）：正式 trial 数；
/// * `practice_trials`（int）：练习 trial 数（标 practice_block 排除）；
/// * `blocks`（int）：块数，单块任务为 1；
/// * `isi_min_ms` / `isi_max_ms`（int）：刺激间空屏时长范围；
/// * `response_window_ms`（int）：反应窗口，超时判错。
///
/// 分类型：
/// * choice 类：`options`（List<String>）：选项码，顺序即 UI 顺序；
/// * go_nogo：`go_ratio`（double，0–1）：Go 试次比例；
/// * n_back：`n`（int）、`match_ratio`（double，0–1）；
/// * stroop：`congruent_ratio` / `conflict_ratio` / `fish_ratio`（double）；
/// * switching：`switch_ratio`（double，0–1）；
/// * digit_span：`start_length`（int）、`lengths`（List<int>）、
///   `failures_to_stop`（int）、`display_ms`（int）、`gap_ms`（int）；
/// * fatigue：`block_seconds`（int）、`trials_per_block`（int）。
///
/// 未在配置里出现的键走 `TaskRunParameters` 的默认值；这些默认值**未标定**，
/// 在真实数据回来之前只当作占位，不要写进对外文案。
///
/// ## 已标定 / 未标定
///
/// * 任务清单、产出指标、能力映射权重与方向：来自设计文档 §4.2 / §7.1 / §7.2；
/// * `estimated_duration_sec`：§4.3 只给试次与时长范围，没有逐任务秒数表，这里按
///   「试次 x (ISI + 反应窗)」推算并取整，**由 §4.3 推算、未标定**；
/// * `quality_checks`：质量标记取了设计文档 §3.2 的通用集合，**未标定**。
library;

import '../domain/assessment_models.dart';

/// 10 个任务的稳定 taskId（落库 / 映射表 / 界面都用它）。
abstract final class AssessmentTaskIds {
  static const String fastSimpleI = 'fast_simple_task_i';
  static const String fastSimpleIi = 'fast_simple_task_ii';
  static const String fastSimpleIii = 'fast_simple_task_iii';
  static const String goNogo = 'go_nogo';
  static const String digitSpanBackward = 'digit_span_backward';
  static const String nBack2 = 'n_back_2';
  static const String stroopCrosslang = 'stroop_crosslang';
  static const String taskSwitching = 'task_switching';
  static const String fatigueBlock = 'fatigue_block';
  static const String decisionFatigue = 'decision_fatigue';

  /// 全部任务 id，顺序即 §4.2 任务清单顺序（疲劳块放最后前一位，会话编排
  /// 负责把它排到整轮最末）。
  static const List<String> all = <String>[
    fastSimpleI,
    fastSimpleIi,
    fastSimpleIii,
    goNogo,
    digitSpanBackward,
    nBack2,
    stroopCrosslang,
    taskSwitching,
    fatigueBlock,
    decisionFatigue,
  ];
}

/// 默认质量检查：所有任务都查「练习块 / 太快 / 不完备」，输入设备敏感的任务
/// 再查设备一致性，其余按任务类型补充（未标定）。
const List<String> _commonQualityChecks = <String>[
  QualityFlags.incomplete,
  QualityFlags.practiceBlock,
  QualityFlags.tooFast,
  QualityFlags.deviceMismatch,
];

/// 设计文档 §4.2 的 10 个默认任务。
const List<AssessmentTaskConfig> kDefaultAssessmentTasks =
    <AssessmentTaskConfig>[
  AssessmentTaskConfig(
    taskId: AssessmentTaskIds.fastSimpleI,
    displayName: '快速分类 I（图形）',
    taskType: AssessmentTaskType.choiceReaction,
    estimatedDurationSeconds: 120,
    config: <String, Object?>{
      'trials': 30,
      'practice_trials': 8,
      'isi_min_ms': 1000,
      'isi_max_ms': 2500,
      'response_window_ms': 1500,
      'options': <String>['circle', 'square'],
    },
    producedMetrics: <String>[
      MetricNames.rtMedian,
      MetricNames.accuracy,
      MetricNames.rtIqr,
    ],
    qualityChecks: _commonQualityChecks,
  ),
  AssessmentTaskConfig(
    taskId: AssessmentTaskIds.fastSimpleIi,
    displayName: '快速分类 II（计算）',
    taskType: AssessmentTaskType.choiceReaction,
    estimatedDurationSeconds: 120,
    config: <String, Object?>{
      'trials': 30,
      'practice_trials': 8,
      'isi_min_ms': 1000,
      'isi_max_ms': 2500,
      'response_window_ms': 1500,
      'options': <String>['yes', 'no'],
    },
    producedMetrics: <String>[
      MetricNames.rtMedian,
      MetricNames.accuracy,
      MetricNames.rtIqr,
    ],
    qualityChecks: _commonQualityChecks,
  ),
  AssessmentTaskConfig(
    taskId: AssessmentTaskIds.fastSimpleIii,
    displayName: '快速匹配（同异判断）',
    taskType: AssessmentTaskType.choiceReaction,
    estimatedDurationSeconds: 120,
    config: <String, Object?>{
      'trials': 30,
      'practice_trials': 8,
      'isi_min_ms': 1000,
      'isi_max_ms': 2500,
      'response_window_ms': 1500,
      'options': <String>['same', 'different'],
    },
    producedMetrics: <String>[
      MetricNames.rtMedian,
      MetricNames.accuracy,
      MetricNames.rtIqr,
    ],
    qualityChecks: _commonQualityChecks,
    // §4.2：可选副本，默认关闭；映射也整体默认关闭。
    enabled: false,
  ),
  AssessmentTaskConfig(
    taskId: AssessmentTaskIds.goNogo,
    displayName: 'Go/No-Go 抑制控制',
    taskType: AssessmentTaskType.goNogo,
    estimatedDurationSeconds: 240,
    config: <String, Object?>{
      'trials': 70,
      'practice_trials': 8,
      'go_ratio': 0.7,
      'response_window_ms': 1500,
    },
    producedMetrics: <String>[
      MetricNames.hitRate,
      MetricNames.falseAlarmRate,
      MetricNames.dPrime,
      MetricNames.rtCost,
    ],
    qualityChecks: <String>[
      ..._commonQualityChecks,
      QualityFlags.lowTrialCount
    ],
  ),
  AssessmentTaskConfig(
    taskId: AssessmentTaskIds.digitSpanBackward,
    displayName: '倒序数字广度',
    taskType: AssessmentTaskType.digitSpan,
    estimatedDurationSeconds: 180,
    config: <String, Object?>{
      'start_length': 3,
      'lengths': <int>[3, 4, 5, 6, 7, 8, 9],
      'failures_to_stop': 2,
    },
    producedMetrics: <String>[
      MetricNames.stableSpan,
      MetricNames.maxSpan,
    ],
    qualityChecks: <String>[
      ..._commonQualityChecks,
      QualityFlags.tooSlow,
      QualityFlags.lowTrialCount,
    ],
  ),
  AssessmentTaskConfig(
    taskId: AssessmentTaskIds.nBack2,
    displayName: '2-back 更新',
    taskType: AssessmentTaskType.nBack,
    estimatedDurationSeconds: 240,
    config: <String, Object?>{
      'n': 2,
      'trials': 60,
      'practice_trials': 8,
      'match_ratio': 0.35,
      'response_window_ms': 1500,
    },
    producedMetrics: <String>[
      MetricNames.accuracy,
      MetricNames.dPrime,
      MetricNames.rtMedian,
    ],
    qualityChecks: <String>[
      ..._commonQualityChecks,
      QualityFlags.highLapse,
      QualityFlags.lowTrialCount,
    ],
  ),
  AssessmentTaskConfig(
    taskId: AssessmentTaskIds.stroopCrosslang,
    displayName: '颜色-语义冲突 Stroop（跨语言）',
    taskType: AssessmentTaskType.stroop,
    estimatedDurationSeconds: 210,
    config: <String, Object?>{
      'trials': 50,
      'practice_trials': 6,
      'congruent_ratio': 0.45,
      'conflict_ratio': 0.30,
      'fish_ratio': 0.25,
      'response_window_ms': 1500,
      'options': <String>['red', 'blue'],
    },
    producedMetrics: <String>[
      MetricNames.conflictCost,
      MetricNames.accuracy,
      MetricNames.congruentRt,
      MetricNames.fishTrialAccuracy,
    ],
    qualityChecks: <String>[..._commonQualityChecks, QualityFlags.tooSlow],
  ),
  AssessmentTaskConfig(
    taskId: AssessmentTaskIds.taskSwitching,
    displayName: '任务切换',
    taskType: AssessmentTaskType.switching,
    estimatedDurationSeconds: 240,
    config: <String, Object?>{
      'trials': 70,
      'practice_trials': 8,
      'switch_ratio': 0.5,
      'response_window_ms': 1500,
    },
    producedMetrics: <String>[
      MetricNames.switchCost,
      MetricNames.repeatRt,
      MetricNames.switchRt,
    ],
    qualityChecks: <String>[..._commonQualityChecks, QualityFlags.tooSlow],
  ),
  AssessmentTaskConfig(
    taskId: AssessmentTaskIds.fatigueBlock,
    displayName: '疲劳块',
    taskType: AssessmentTaskType.fatigue,
    estimatedDurationSeconds: 240,
    config: <String, Object?>{
      'blocks': 3,
      'block_seconds': 60,
      'trials_per_block': 30,
      'practice_trials': 3,
    },
    producedMetrics: <String>[
      MetricNames.rtSlope,
      MetricNames.varianceDrift,
      MetricNames.lapseSlope,
    ],
    qualityChecks: <String>[
      ..._commonQualityChecks,
      QualityFlags.highLapse,
      QualityFlags.lowTrialCount,
    ],
  ),
  AssessmentTaskConfig(
    taskId: AssessmentTaskIds.decisionFatigue,
    displayName: '决策疲劳',
    taskType: AssessmentTaskType.decisionFatigue,
    estimatedDurationSeconds: 180,
    config: <String, Object?>{
      'trials': 75,
      'practice_trials': 5,
    },
    producedMetrics: <String>[
      MetricNames.decisionDrift,
      MetricNames.defaultChoiceRate,
    ],
    qualityChecks: <String>[
      ..._commonQualityChecks,
      QualityFlags.highLapse,
      QualityFlags.tooSlow,
    ],
    // §4.3.8：信度未验证，默认关闭，只当「当天状态」。
    enabled: false,
    provisional: true,
  ),
];

/// §7.1 默认任务→能力映射。
///
/// 源表只有 go_nogo / stroop / fast_simple_task_i 的细目；其余任务按 §4.2 的
/// 「默认映射能力」补成 weight 1.0 + 对应产出主指标。stroop 的两条可选映射与
/// fast_simple_task_iii 默认 enabled=false（§7.1「可选，配置启用」）。
const List<TaskAbilityMapping> kDefaultTaskAbilityMappings =
    <TaskAbilityMapping>[
  TaskAbilityMapping(
    taskId: AssessmentTaskIds.fastSimpleI,
    abilityId: AbilityIds.processingSpeed,
    weight: 1.0,
    metricSource: MetricNames.rtMedian,
  ),
  TaskAbilityMapping(
    taskId: AssessmentTaskIds.fastSimpleIi,
    abilityId: AbilityIds.processingSpeed,
    weight: 1.0,
    metricSource: MetricNames.rtMedian,
  ),
  TaskAbilityMapping(
    taskId: AssessmentTaskIds.fastSimpleIii,
    abilityId: AbilityIds.processingSpeed,
    weight: 1.0,
    metricSource: MetricNames.rtMedian,
    enabled: false,
  ),
  TaskAbilityMapping(
    taskId: AssessmentTaskIds.goNogo,
    abilityId: AbilityIds.inhibitoryControl,
    weight: 1.0,
    metricSource: MetricNames.dPrime,
  ),
  TaskAbilityMapping(
    taskId: AssessmentTaskIds.digitSpanBackward,
    abilityId: AbilityIds.workingMemoryCapacity,
    weight: 1.0,
    metricSource: MetricNames.stableSpan,
  ),
  TaskAbilityMapping(
    taskId: AssessmentTaskIds.nBack2,
    abilityId: AbilityIds.workingMemoryUpdateSpeed,
    weight: 1.0,
    metricSource: MetricNames.dPrime,
  ),
  TaskAbilityMapping(
    taskId: AssessmentTaskIds.stroopCrosslang,
    abilityId: AbilityIds.distractionResistance,
    weight: 0.7,
    metricSource: MetricNames.conflictCost,
  ),
  TaskAbilityMapping(
    taskId: AssessmentTaskIds.stroopCrosslang,
    abilityId: AbilityIds.processingSpeed,
    weight: 0.3,
    metricSource: MetricNames.rtMedian,
    enabled: false,
  ),
  TaskAbilityMapping(
    taskId: AssessmentTaskIds.stroopCrosslang,
    abilityId: AbilityIds.crossLanguageCost,
    weight: 0.2,
    metricSource: MetricNames.congruentRt,
    enabled: false,
  ),
  TaskAbilityMapping(
    taskId: AssessmentTaskIds.taskSwitching,
    abilityId: AbilityIds.switchCostAbility,
    weight: 1.0,
    metricSource: MetricNames.switchCost,
  ),
  TaskAbilityMapping(
    taskId: AssessmentTaskIds.fatigueBlock,
    abilityId: AbilityIds.fatigueSlope,
    weight: 1.0,
    metricSource: MetricNames.rtSlope,
  ),
  TaskAbilityMapping(
    taskId: AssessmentTaskIds.fatigueBlock,
    abilityId: AbilityIds.stabilityDrift,
    weight: 1.0,
    metricSource: MetricNames.varianceDrift,
  ),
  TaskAbilityMapping(
    taskId: AssessmentTaskIds.decisionFatigue,
    abilityId: AbilityIds.decisionFatigue,
    weight: 1.0,
    metricSource: MetricNames.decisionDrift,
    enabled: false,
  ),
];

/// §7.2 默认能力→认知参数映射（direction 一律 positive / negative）。
const List<AbilityParamMapping> kDefaultAbilityParamMappings =
    <AbilityParamMapping>[
  AbilityParamMapping(
    abilityId: AbilityIds.processingSpeed,
    paramId: CognitiveParamIds.taskDurationEstimate,
    weight: 0.7,
    direction: MappingDirection.positive,
  ),
  AbilityParamMapping(
    abilityId: AbilityIds.processingSpeed,
    paramId: CognitiveParamIds.chunkingThreshold,
    weight: 0.3,
    direction: MappingDirection.positive,
  ),
  AbilityParamMapping(
    abilityId: AbilityIds.fatigueSlope,
    paramId: CognitiveParamIds.taskDurationEstimate,
    weight: 0.3,
    direction: MappingDirection.positive,
  ),
  AbilityParamMapping(
    abilityId: AbilityIds.inhibitoryControl,
    paramId: CognitiveParamIds.interruptionCost,
    weight: 0.6,
    direction: MappingDirection.negative,
  ),
  AbilityParamMapping(
    abilityId: AbilityIds.inhibitoryControl,
    paramId: CognitiveParamIds.switchPenalty,
    weight: 0.4,
    direction: MappingDirection.negative,
  ),
  AbilityParamMapping(
    abilityId: AbilityIds.distractionResistance,
    paramId: CognitiveParamIds.interruptionCost,
    weight: 0.4,
    direction: MappingDirection.negative,
  ),
  AbilityParamMapping(
    abilityId: AbilityIds.workingMemoryCapacity,
    paramId: CognitiveParamIds.highLoadDiscount,
    weight: 0.6,
    direction: MappingDirection.negative,
  ),
  AbilityParamMapping(
    abilityId: AbilityIds.workingMemoryUpdateSpeed,
    paramId: CognitiveParamIds.highLoadDiscount,
    weight: 0.4,
    direction: MappingDirection.negative,
  ),
  AbilityParamMapping(
    abilityId: AbilityIds.switchCostAbility,
    paramId: CognitiveParamIds.switchPenalty,
    weight: 0.7,
    direction: MappingDirection.negative,
  ),
  AbilityParamMapping(
    abilityId: AbilityIds.fatigueSlope,
    paramId: CognitiveParamIds.similarFatiguePenalty,
    weight: 0.7,
    direction: MappingDirection.positive,
  ),
  AbilityParamMapping(
    abilityId: AbilityIds.fatigueSlope,
    paramId: CognitiveParamIds.scheduleIntensityCap,
    weight: 0.6,
    direction: MappingDirection.negative,
  ),
  AbilityParamMapping(
    abilityId: AbilityIds.stabilityDrift,
    paramId: CognitiveParamIds.expectedPressure,
    weight: 0.5,
    direction: MappingDirection.positive,
  ),
  AbilityParamMapping(
    abilityId: AbilityIds.decisionFatigue,
    paramId: CognitiveParamIds.timeOfDayBias,
    weight: 0.8,
    direction: MappingDirection.positive,
  ),
];

/// 按 taskId 取默认任务；未知返回 null（不猜、不抛）。
AssessmentTaskConfig? defaultAssessmentTask(String taskId) {
  final normalized = taskId.trim();
  for (final task in kDefaultAssessmentTasks) {
    if (task.taskId == normalized) return task;
  }
  return null;
}

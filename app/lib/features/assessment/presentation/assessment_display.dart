/// 评测板块的显示层纯函数：语言文案映射、数值格式化与计数聚合。
///
/// 这些函数把「数据层的稳定 id」翻译成「用户能读的字」，并且是**纯函数**：
/// 不读数据库、不读时钟、不随机。页面只负责布局，任何一处文案或数字格式的
/// 改动都只发生在这里，四个页面与它们的测试共享同一口径。
///
/// 语言文案全部来自 [AppLocalizations]；本文件不硬编码中文，也不猜未知 id
/// 的语义——未知 id 原样回显，让数据问题看得见。
library;

import '../../../l10n/app_localizations.dart';
import '../domain/assessment_models.dart';

/// 任务名：先按 taskId / taskType 映射到本地化文案，再退回任务自带的
/// [AssessmentTaskConfig.displayName]，最后退回 taskId。
String assessmentTaskName(AppLocalizations l10n, AssessmentTaskConfig task) {
  final byId = _taskNameForId(l10n, task.taskId);
  if (byId != null) return byId;
  final byType = _taskNameForType(l10n, task.taskType);
  if (byType != null) return byType;
  final displayName = task.displayName.trim();
  return displayName.isEmpty ? task.taskId : displayName;
}

/// 只有稳定 taskId、没有任务配置时的任务名（例如结果页的会话摘要）。
///
/// 映射不到就原样回显 taskId：不按类型猜名字（三个快速任务同属 choice_reaction，
/// 猜类型会把它们都显示成同一个名字），也不去数据库反查任务配置。
String assessmentTaskNameById(AppLocalizations l10n, String taskId) {
  return _taskNameForId(l10n, taskId) ?? taskId;
}

String? _taskNameForId(AppLocalizations l10n, String taskId) {
  switch (taskId.trim().toLowerCase()) {
    case 'fast_simple_task_i':
    case 'fast_simple_task_1':
      return l10n.taskFastSimpleTaskI;
    case 'fast_simple_task_ii':
    case 'fast_simple_task_2':
      return l10n.taskFastSimpleTaskIi;
    case 'fast_simple_task_iii':
    case 'fast_simple_task_3':
      return l10n.taskFastSimpleTaskIii;
    case 'go_nogo':
    case 'go_nogo_task':
      return l10n.taskGoNogo;
    case 'digit_span_backward':
    case 'digit_span':
    case 'digit_span_backward_task':
      return l10n.taskDigitSpanBackward;
    case 'n_back_2':
    case 'nback_2':
    case 'n_back':
      return l10n.taskNBack2;
    case 'stroop_crosslang':
    case 'stroop':
      return l10n.taskStroopCrosslang;
    case 'task_switching':
    case 'switching':
      return l10n.taskSwitching;
    case 'fatigue_block':
    case 'fatigue':
      return l10n.taskFatigueBlock;
    case 'decision_fatigue':
      return l10n.taskDecisionFatigue;
  }
  return null;
}

/// 类型兜底：只有「一个类型对应一个已定文案」时才映射；choice_reaction 有
/// 三个变体，不按类型猜名字。
String? _taskNameForType(AppLocalizations l10n, AssessmentTaskType type) {
  switch (type) {
    case AssessmentTaskType.goNogo:
      return l10n.taskGoNogo;
    case AssessmentTaskType.nBack:
      return l10n.taskNBack2;
    case AssessmentTaskType.stroop:
      return l10n.taskStroopCrosslang;
    case AssessmentTaskType.switching:
      return l10n.taskSwitching;
    case AssessmentTaskType.fatigue:
      return l10n.taskFatigueBlock;
    case AssessmentTaskType.digitSpan:
      return l10n.taskDigitSpanBackward;
    case AssessmentTaskType.decisionFatigue:
      return l10n.taskDecisionFatigue;
    case AssessmentTaskType.choiceReaction:
      return null;
  }
}

/// 能力指标名；未知 id 原样回显。
String assessmentAbilityName(AppLocalizations l10n, String abilityId) {
  switch (abilityId) {
    case AbilityIds.processingSpeed:
      return l10n.abilityProcessingSpeed;
    case AbilityIds.inhibitoryControl:
      return l10n.abilityInhibitoryControl;
    case AbilityIds.workingMemoryCapacity:
      return l10n.abilityWorkingMemoryCapacity;
    case AbilityIds.workingMemoryUpdateSpeed:
      return l10n.abilityWorkingMemoryUpdateSpeed;
    case AbilityIds.distractionResistance:
      return l10n.abilityDistractionResistance;
    case AbilityIds.switchCostAbility:
      return l10n.abilitySwitchCostAbility;
    case AbilityIds.fatigueSlope:
      return l10n.abilityFatigueSlope;
    case AbilityIds.stabilityDrift:
      return l10n.abilityStabilityDrift;
    case AbilityIds.decisionFatigue:
      return l10n.abilityDecisionFatigue;
    case AbilityIds.crossLanguageCost:
      return l10n.abilityCrossLanguageCost;
  }
  return abilityId;
}

/// 认知模型参数名；未知 id 原样回显。
String assessmentParamName(AppLocalizations l10n, String paramId) {
  switch (paramId) {
    case CognitiveParamIds.taskDurationEstimate:
      return l10n.paramTaskDurationEstimate;
    case CognitiveParamIds.chunkingThreshold:
      return l10n.paramChunkingThreshold;
    case CognitiveParamIds.interruptionCost:
      return l10n.paramInterruptionCost;
    case CognitiveParamIds.switchPenalty:
      return l10n.paramSwitchPenalty;
    case CognitiveParamIds.highLoadDiscount:
      return l10n.paramHighLoadDiscount;
    case CognitiveParamIds.similarFatiguePenalty:
      return l10n.paramSimilarFatiguePenalty;
    case CognitiveParamIds.scheduleIntensityCap:
      return l10n.paramScheduleIntensityCap;
    case CognitiveParamIds.expectedPressure:
      return l10n.paramExpectedPressure;
    case CognitiveParamIds.timeOfDayBias:
      return l10n.paramTimeOfDayBias;
  }
  return paramId;
}

/// 统计指标名；未知名字原样回显（指标集合比本地化文案宽，例如 max_span）。
String assessmentMetricName(AppLocalizations l10n, String metricName) {
  switch (metricName) {
    case MetricNames.rtMedian:
      return l10n.metricRtMedian;
    case MetricNames.rtIqr:
      return l10n.metricRtIqr;
    case MetricNames.accuracy:
      return l10n.metricAccuracy;
    case MetricNames.hitRate:
      return l10n.metricHitRate;
    case MetricNames.falseAlarmRate:
      return l10n.metricFalseAlarmRate;
    case MetricNames.dPrime:
      return l10n.metricDPrime;
    case MetricNames.rtCost:
      return l10n.metricRtCost;
    case MetricNames.stableSpan:
      return l10n.metricStableSpan;
    case MetricNames.rtSlope:
      return l10n.metricRtSlope;
    case MetricNames.varianceDrift:
      return l10n.metricVarianceDrift;
    case MetricNames.switchCost:
      return l10n.metricSwitchCost;
    case MetricNames.conflictCost:
      return l10n.metricConflictCost;
    case MetricNames.decisionDrift:
      return l10n.metricDecisionDrift;
    case MetricNames.repeatRt:
      return l10n.metricRepeatRt;
    case MetricNames.switchRt:
      return l10n.metricSwitchRt;
    case MetricNames.congruentRt:
      return l10n.metricCongruentRt;
    case MetricNames.lapseSlope:
      return l10n.metricLapseSlope;
    case MetricNames.fishTrialAccuracy:
      return l10n.metricFishTrialAccuracy;
    case MetricNames.defaultChoiceRate:
      return l10n.metricDefaultChoiceRate;
  }
  return metricName;
}

/// 指标值的显示格式：比例用百分比、反应时用毫秒、其余保留两位小数。
///
/// 只做显示；不四舍五入到数据层，也不把单位塞进数据。
String assessmentMetricValueText(String metricName, double value) {
  switch (metricName) {
    case MetricNames.accuracy:
    case MetricNames.hitRate:
    case MetricNames.falseAlarmRate:
    case MetricNames.fishTrialAccuracy:
    case MetricNames.defaultChoiceRate:
      return '${(value * 100).toStringAsFixed(1)}%';
    case MetricNames.rtMedian:
    case MetricNames.rtIqr:
    case MetricNames.rtCost:
    case MetricNames.repeatRt:
    case MetricNames.switchRt:
    case MetricNames.congruentRt:
      return '${value.round()} ms';
    case MetricNames.stableSpan:
    case MetricNames.maxSpan:
      return value.toStringAsFixed(1);
  }
  return value.toStringAsFixed(2);
}

/// 估计值（能力/参数）的显示格式：统一两位小数，避免同页两种精度。
String assessmentEstimateValueText(double value) => value.toStringAsFixed(2);

/// 任务预计时长（秒 → 分钟）；不足一分钟仍显示「约 1 分钟」。
int assessmentTaskDurationMinutes(int estimatedDurationSeconds) {
  if (estimatedDurationSeconds <= 0) return 1;
  final minutes = (estimatedDurationSeconds / 60).round();
  return minutes < 1 ? 1 : minutes;
}

/// 用时时长：mm:ss（超过一小时 h:mm:ss）。负时长按 0 处理。
String assessmentDurationText(Duration duration) {
  final safe = duration.isNegative ? Duration.zero : duration;
  final hours = safe.inHours;
  final minutes = safe.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) return '$hours:$minutes:$seconds';
  return '${safe.inMinutes.toString().padLeft(2, '0')}:$seconds';
}

/// 历史行的时间：本地时区的 yyyy-MM-dd HH:mm。
String assessmentHistoryTimeText(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

/// 估算来源徽标文案。
String assessmentSourceLabel(AppLocalizations l10n, String source) {
  switch (source) {
    case EstimateSources.defaultPrior:
      return l10n.assessmentProfileSourceDefault;
    case EstimateSources.assessment:
      return l10n.assessmentProfileSourceAssessment;
    case EstimateSources.derived:
      return l10n.assessmentProfileSourceDerived;
    case EstimateSources.userOverride:
      return l10n.assessmentProfileSourceOverride;
  }
  return source;
}

/// 质量标记串：空列表显示「无」，否则按原始编码用「·」连接。
///
/// 不翻译标记编码：这些是设计文档里的稳定 id，结果页与档案页要能对照原始数据。
String assessmentQualityFlagsText(AppLocalizations l10n, List<String> flags) {
  if (flags.isEmpty) return l10n.assessmentResultQualityNone;
  return flags.join(' · ');
}

/// 每个任务已完成的测量次数（默认只数 status=completed 的会话）。
Map<String, int> assessmentSessionCountsByTaskId(
  Iterable<AssessmentSessionSummary> sessions, {
  bool completedOnly = true,
}) {
  final counts = <String, int>{};
  for (final session in sessions) {
    if (completedOnly && session.status != 'completed') continue;
    counts[session.taskId] = (counts[session.taskId] ?? 0) + 1;
  }
  return counts;
}

/// 能力估计按 [AbilityIds.all] 的稳定顺序排列；未知 id 排在末尾。
List<AbilityEstimate> assessmentSortedAbilities(
  List<AbilityEstimate> abilities,
) {
  int order(String abilityId) {
    final index = AbilityIds.all.indexOf(abilityId);
    return index < 0 ? AbilityIds.all.length : index;
  }

  final sorted = List<AbilityEstimate>.of(abilities)
    ..sort((a, b) => order(a.abilityId).compareTo(order(b.abilityId)));
  return sorted;
}

/// 参数估计按 [CognitiveParamIds.all] 的稳定顺序排列；未知 id 排在末尾。
List<ParamEstimate> assessmentSortedParams(List<ParamEstimate> params) {
  int order(String paramId) {
    final index = CognitiveParamIds.all.indexOf(paramId);
    return index < 0 ? CognitiveParamIds.all.length : index;
  }

  final sorted = List<ParamEstimate>.of(params)
    ..sort((a, b) => order(a.paramId).compareTo(order(b.paramId)));
  return sorted;
}

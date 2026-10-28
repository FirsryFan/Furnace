/// 评测会话服务：一次测评从「原始 trial」到「能力估计 + 认知参数」的编排。
///
/// 责任链（设计文档 v1.0 §4 / §7 / §8 / §9 / §10.2）：
///
/// 1. 按任务 `produced_metrics` 计算会话级指标（[computeSessionMetrics]）；
/// 2. 评估质量标记（[evaluateQualityFlags]，只上调不确定性，不删数据）；
/// 3. 落库会话 + trial + 指标；
/// 4. 指标 → 能力测量（`abilityMeasurementsForSession`）→ 按 uncertainty 加权
///    中位数合并到能力估计；
/// 5. 能力 → 认知模型参数（`deriveParams`）；
/// 6. 读回能力与参数给结果页。
///
/// 纯编排 + 纯函数指标计算：不 import Flutter，时间与设备由调用方注入，
/// 数据库只通过 [AssessmentStore] 抽象访问（可单测）。
library;

import 'dart:io' show Platform;

import '../domain/assessment_estimates.dart';
import '../domain/assessment_mapping.dart';
import '../domain/assessment_metrics.dart' as measures;
import '../domain/assessment_models.dart';

/// 会话状态（写入 `cog_assessment_sessions.status`，与设计文档 §10.2 一致）。
abstract final class AssessmentSessionStatuses {
  static const String completed = 'completed';
  static const String incomplete = 'incomplete';
  static const String aborted = 'aborted';

  static const List<String> all = <String>[completed, incomplete, aborted];
}

/// 当前运行设备类别（写进会话与能力估计，做设备一致性检查）。
String currentAssessmentDevice() {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    return AssessmentDevices.windowsMouse;
  }
  if (Platform.isAndroid || Platform.isIOS) {
    return AssessmentDevices.androidTouch;
  }
  return AssessmentDevices.unknown;
}

/// 一次已保存会话的完整结果（结果页直接用这几份数据）。
class AssessmentSessionResult {
  const AssessmentSessionResult({
    required this.summary,
    required this.metrics,
    required this.abilities,
    required this.params,
    required this.qualityFlags,
    required this.measurements,
  });

  final AssessmentSessionSummary summary;
  final List<MetricSample> metrics;

  /// 合并后的全部能力估计（10 项，含没测过的先验）。
  final List<AbilityEstimate> abilities;

  /// 推导后的全部认知参数（9 项）。
  final List<ParamEstimate> params;

  final List<String> qualityFlags;

  /// 本次真正参与合并的测量（跳过的指标不在其中）。
  final List<AbilityMeasurement> measurements;

  /// 本次没有贡献任何能力测量（指标缺失 / 映射未启用 / 全被跳过）。
  bool get isEmpty => measurements.isEmpty;
}

/// 会话编排服务；无内部状态，可安全复用。
class AssessmentSessionService {
  const AssessmentSessionService({required AssessmentStore store})
      : _store = store;

  final AssessmentStore _store;

  /// 正常完成一次任务：算指标、落库、合并能力、推导参数，读回结果。
  ///
  /// [trials] 可以包含练习 trial（服务自己按 [TrialResult.isMeasured] 过滤）。
  Future<AssessmentSessionResult> completeSession({
    required AssessmentTaskConfig task,
    required List<TrialResult> trials,
    required DateTime startedAt,
    required DateTime completedAt,
    required String device,
    Set<String> extraQualityFlags = const <String>{},
  }) async {
    final measured =
        trials.where((trial) => trial.isMeasured).toList(growable: false);
    final metricSamples = computeSessionMetrics(task: task, trials: measured);
    final previousSessions = await _store.readSessions(limit: 1);
    final qualityFlags = evaluateQualityFlags(
      task: task,
      trials: measured,
      metricSamples: metricSamples,
      status: AssessmentSessionStatuses.completed,
      device: device,
      previousDevice:
          previousSessions.isEmpty ? null : previousSessions.first.device,
    );
    final effectiveFlags = _mergeQualityFlags(
      base: qualityFlags,
      extra: extraQualityFlags,
    );
    final flaggedMetrics = _withQualityFlags(metricSamples, effectiveFlags);
    final sessionId = await _store.recordSession(
      taskId: task.taskId,
      designVersion: task.designVersion,
      device: device,
      startedAt: startedAt,
      completedAt: completedAt,
      status: AssessmentSessionStatuses.completed,
      trials: trials,
      metrics: flaggedMetrics,
      qualityFlags: effectiveFlags,
    );
    final summary = AssessmentSessionSummary(
      sessionId: sessionId,
      taskId: task.taskId,
      designVersion: task.designVersion,
      device: device,
      startedAt: startedAt,
      completedAt: completedAt,
      status: AssessmentSessionStatuses.completed,
      qualityFlags: effectiveFlags,
      metrics: flaggedMetrics,
    );

    final measurements = await _mergeMeasurements(
      task: task,
      metrics: flaggedMetrics,
      measuredAt: completedAt,
      device: device,
    );
    final abilities = await _mergeAbilities(
      task: task,
      measurements: measurements,
      metrics: metricSamples,
      measuredAt: completedAt,
      device: device,
    );
    final params = await _deriveParams(
      abilities: abilities,
      updatedAt: completedAt,
    );
    return AssessmentSessionResult(
      summary: summary,
      metrics: metricSamples,
      abilities: abilities,
      params: params,
      qualityFlags: effectiveFlags,
      measurements: measurements,
    );
  }

  /// 中途退出：只落会话与已完成 trial，不更新任何估计。
  Future<AssessmentSessionSummary> recordIncompleteSession({
    required AssessmentTaskConfig task,
    required List<TrialResult> trials,
    required DateTime startedAt,
    required DateTime endedAt,
    required String device,
    String status = AssessmentSessionStatuses.aborted,
  }) async {
    final measured =
        trials.where((trial) => trial.isMeasured).toList(growable: false);
    final metricSamples = computeSessionMetrics(task: task, trials: measured);
    final qualityFlags = evaluateQualityFlags(
      task: task,
      trials: measured,
      metricSamples: metricSamples,
      status: status,
      device: device,
    );
    final sessionId = await _store.recordSession(
      taskId: task.taskId,
      designVersion: task.designVersion,
      device: device,
      startedAt: startedAt,
      completedAt: endedAt,
      status: status,
      trials: trials,
      metrics: metricSamples,
      qualityFlags: qualityFlags,
    );
    return AssessmentSessionSummary(
      sessionId: sessionId,
      taskId: task.taskId,
      designVersion: task.designVersion,
      device: device,
      startedAt: startedAt,
      completedAt: endedAt,
      status: status,
      qualityFlags: qualityFlags,
      metrics: metricSamples,
    );
  }

  Future<List<AbilityMeasurement>> _mergeMeasurements({
    required AssessmentTaskConfig task,
    required List<MetricSample> metrics,
    required DateTime measuredAt,
    required String device,
  }) async {
    final mappings = await _store.readTaskAbilityMappings();
    return abilityMeasurementsForSession(
      taskId: task.taskId,
      mappings: mappings,
      metrics: metrics,
      designVersion: task.designVersion,
      device: device,
      measuredAt: measuredAt,
    );
  }

  Future<List<AbilityEstimate>> _mergeAbilities({
    required AssessmentTaskConfig task,
    required List<AbilityMeasurement> measurements,
    required List<MetricSample> metrics,
    required DateTime measuredAt,
    required String device,
  }) async {
    final current = await _store.readAbilities();
    final byId = <String, AbilityEstimate>{
      for (final ability in current) ability.abilityId: ability,
    };
    final updated = <AbilityEstimate>[];
    for (final measurement in measurements) {
      final merged = mergeAbilityEstimate(
        current: byId[measurement.abilityId],
        measurement: measurement,
      );
      if (merged == null) continue;
      byId[merged.abilityId] = merged;
      updated.add(merged);
    }
    if (updated.isNotEmpty) {
      await _store.writeEstimates(abilities: updated);
    }
    final result = byId.values.toList(growable: false)
      ..sort((a, b) => a.abilityId.compareTo(b.abilityId));
    return List<AbilityEstimate>.unmodifiable(result);
  }

  Future<List<ParamEstimate>> _deriveParams({
    required List<AbilityEstimate> abilities,
    required DateTime updatedAt,
  }) async {
    final mappings = await _store.readAbilityParamMappings();
    final currentParams = await _store.readCognitiveParams();
    final derived = deriveParams(
      abilities: abilities,
      mappings: mappings,
      currentParams: currentParams,
      updatedAt: updatedAt,
    );
    if (derived.isNotEmpty) {
      await _store.writeEstimates(params: derived);
    }
    final stored = await _store.readCognitiveParams();
    final byId = <String, ParamEstimate>{
      for (final param in stored) param.paramId: param,
    };
    for (final param in derived) {
      byId[param.paramId] = param;
    }
    final result = byId.values.toList(growable: false)
      ..sort((a, b) => a.paramId.compareTo(b.paramId));
    return List<ParamEstimate>.unmodifiable(result);
  }
}

/// 把调用方补充的质量标记（例如运行页看到的切后台 `background_switch`）并入
/// 会话标记。
///
/// 只接受 [QualityFlags.all] 里已知的标记；输出顺序按 [QualityFlags.all] 稳定。
/// 与 [evaluateQualityFlags] 的区别：那类标记由任务 `quality_checks` 决定是否
/// 产出，而环境级标记（切后台/设备不一致）由调用方给出、不受任务声明限制。
List<String> _mergeQualityFlags({
  required List<String> base,
  required Set<String> extra,
}) {
  final merged = <String>{...base};
  for (final flag in extra) {
    final normalized = flag.trim();
    if (QualityFlags.all.contains(normalized)) {
      merged.add(normalized);
    }
  }
  final ordered = <String>[
    for (final flag in QualityFlags.all)
      if (merged.contains(flag)) flag,
  ];
  return List<String>.unmodifiable(ordered);
}

/// 给会话指标打上会话级质量标记：合并层按 [AbilityMeasurement.qualityFlags]
/// 上调新证据的不确定性（每个已知标记 +0.1），不会删除任何数值。
List<MetricSample> _withQualityFlags(
  List<MetricSample> metrics,
  List<String> flags,
) {
  if (flags.isEmpty) return metrics;
  return List<MetricSample>.unmodifiable(<MetricSample>[
    for (final sample in metrics)
      MetricSample(
        name: sample.name,
        value: sample.value,
        nTrials: sample.nTrials,
        qualityFlags: flags,
      ),
  ]);
}

/// 按任务声明的 `produced_metrics` 计算会话级指标；算不出的指标直接跳过。
///
/// 只统计有效 trial（[TrialResult.isMeasured]）。指标公式见
/// `assessment_metrics.dart`；本文件只补设计文档 §4.2 提到、指标文件还没有
/// 独立函数的几项（repeat_rt / switch_rt / congruent_rt / lapse_slope /
/// max_span / fish_trial_accuracy / default_choice_rate），口径写在各自注释里。
List<MetricSample> computeSessionMetrics({
  required AssessmentTaskConfig task,
  required List<TrialResult> trials,
}) {
  final measured =
      trials.where((trial) => trial.isMeasured).toList(growable: false);
  final samples = <MetricSample>[];
  for (final name in task.producedMetrics) {
    final value = metricValueFor(name, measured);
    if (value == null || !value.isFinite) continue;
    samples.add(
      MetricSample(
        name: name,
        value: value,
        nTrials: measured.length,
      ),
    );
  }
  return List<MetricSample>.unmodifiable(samples);
}

/// 单个指标的计算入口；未知指标、样本不足时返回 null。
double? metricValueFor(String metricName, List<TrialResult> measuredTrials) {
  switch (metricName) {
    case MetricNames.rtMedian:
      return measures.rtMedian(measuredTrials);
    case MetricNames.rtIqr:
      return measures.rtIqr(measuredTrials);
    case MetricNames.accuracy:
      return measures.accuracy(measuredTrials);
    case MetricNames.hitRate:
      return measures.hitRate(measuredTrials, isTarget: _isTargetTrial);
    case MetricNames.falseAlarmRate:
      return measures.falseAlarmRate(measuredTrials, isTarget: _isTargetTrial);
    case MetricNames.dPrime:
      return measures.dPrime(measuredTrials, isTarget: _isTargetTrial);
    case MetricNames.rtCost:
      return measures.rtCost(measuredTrials, isTarget: _isTargetTrial);
    case MetricNames.stableSpan:
      final span = measures.stableSpan(measuredTrials, spanOf: _spanOf);
      return span?.toDouble();
    case MetricNames.maxSpan:
      return _maxSpan(measuredTrials);
    case MetricNames.rtSlope:
      return measures.rtSlope(measuredTrials);
    case MetricNames.varianceDrift:
      return measures.varianceDrift(measuredTrials);
    case MetricNames.switchCost:
      return measures.switchCost(measuredTrials, isSwitchTrial: _isSwitchTrial);
    case MetricNames.conflictCost:
      final stroop = measuredTrials
          .where((trial) => _stroopKind(trial) != null)
          .toList(growable: false);
      return measures.conflictCost(stroop,
          isCongruentTrial: (trial) => _stroopKind(trial) == 'congruent');
    case MetricNames.decisionDrift:
      return measures.decisionDrift(measuredTrials);
    case MetricNames.repeatRt:
      return _medianRt(measuredTrials.where((t) => !_isSwitchTrial(t)));
    case MetricNames.switchRt:
      return _medianRt(measuredTrials.where(_isSwitchTrial));
    case MetricNames.congruentRt:
      return _medianRt(
          measuredTrials.where((trial) => _stroopKind(trial) == 'congruent'));
    case MetricNames.lapseSlope:
      return _lapseSlope(measuredTrials);
    case MetricNames.fishTrialAccuracy:
      return measures.accuracy(
          measuredTrials.where((trial) => _stroopKind(trial) == 'fish'));
    case MetricNames.defaultChoiceRate:
      return _defaultChoiceRate(measuredTrials);
    default:
      return null;
  }
}

/// 会话质量标记（设计文档 §9）：只标记，不删数据；标记由指标权重加罚。
///
/// * `incomplete`：状态不是 completed；
/// * `too_fast`：中位 RT < 100ms；
/// * `too_slow`：中位 RT > 3000ms（绝对阈值占位，真实数据回来前不对外解释）；
/// * `high_lapse`：未作答 trial 占比 > 30%；
/// * `low_trial_count`：有效 trial < 20；
/// * `device_mismatch`：本次设备与上一次同类会话不同；
/// * `practice_block` / `background_switch`：本轮不产出（练习已被指标层排除，
///   后台切屏没有遥测来源），保持沉默而不是误报。
List<String> evaluateQualityFlags({
  required AssessmentTaskConfig task,
  required List<TrialResult> trials,
  required List<MetricSample> metricSamples,
  required String status,
  required String device,
  String? previousDevice,
}) {
  final flags = <String>{};
  void addIfChecked(String flag, bool condition) {
    if (!condition) return;
    if (task.qualityChecks.isNotEmpty && !task.qualityChecks.contains(flag)) {
      return;
    }
    flags.add(flag);
  }

  final measured =
      trials.where((trial) => trial.isMeasured).toList(growable: false);
  final medianRt = measures.rtMedian(measured);
  final unanswered = measured.where((trial) => trial.rtMs == null).length;
  final lapseRate = measured.isEmpty ? 0.0 : unanswered / measured.length;
  addIfChecked(
      QualityFlags.incomplete, status != AssessmentSessionStatuses.completed);
  addIfChecked(QualityFlags.tooFast, medianRt != null && medianRt < 100);
  addIfChecked(QualityFlags.tooSlow, medianRt != null && medianRt > 3000);
  addIfChecked(QualityFlags.highLapse, lapseRate > 0.3);
  addIfChecked(QualityFlags.lowTrialCount, measured.length < 20);
  addIfChecked(
    QualityFlags.deviceMismatch,
    previousDevice != null &&
        previousDevice.isNotEmpty &&
        previousDevice != AssessmentDevices.unknown &&
        device.isNotEmpty &&
        device != AssessmentDevices.unknown &&
        previousDevice != device,
  );
  final ordered = <String>[];
  for (final flag in QualityFlags.all) {
    if (flags.contains(flag)) ordered.add(flag);
  }
  return List<String>.unmodifiable(ordered);
}

/// 目标 trial（go/nogo 的 Go、n-back 的匹配）；其他任务没有目标概念。
bool _isTargetTrial(TrialResult trial) {
  final isTarget = trial.stimulus['is_target'];
  if (isTarget is bool) return isTarget;
  final match = trial.stimulus['match'];
  if (match is bool) return match;
  final shouldTap = trial.stimulus['should_tap'];
  if (shouldTap is bool) return shouldTap;
  return false;
}

bool _isSwitchTrial(TrialResult trial) => trial.stimulus['switched'] == true;

String? _stroopKind(TrialResult trial) {
  final kind = trial.stimulus['kind'];
  return kind is String && kind.isNotEmpty ? kind : null;
}

int? _spanOf(TrialResult trial) {
  final length = trial.stimulus['length'];
  return length is int ? length : null;
}

double? _medianRt(Iterable<TrialResult> trials) {
  final values = <double>[];
  for (final trial in trials) {
    if (!trial.isMeasured) continue;
    final rt = trial.rtMs;
    if (rt == null) continue;
    values.add(rt.toDouble());
  }
  if (values.isEmpty) return null;
  values.sort();
  final middle = values.length ~/ 2;
  if (values.length.isOdd) return values[middle];
  return (values[middle - 1] + values[middle]) / 2;
}

/// 最高跨度：在答对的有效 trial 里取最大 `length`。
double? _maxSpan(List<TrialResult> trials) {
  int? best;
  for (final trial in trials) {
    if (!trial.isMeasured || trial.correct != true) continue;
    final span = _spanOf(trial);
    if (span == null) continue;
    if (best == null || span > best) best = span;
  }
  return best?.toDouble();
}

/// 漏答率随块号的稳健斜率（Theil–Sen）；块数少于 2 返回 null。
double? _lapseSlope(List<TrialResult> trials) {
  final total = <int, int>{};
  final lapses = <int, int>{};
  for (final trial in trials) {
    if (!trial.isMeasured) continue;
    final block = trial.blockIndex;
    total[block] = (total[block] ?? 0) + 1;
    if (trial.rtMs == null) lapses[block] = (lapses[block] ?? 0) + 1;
  }
  final blocks = total.keys.toList()..sort();
  if (blocks.length < 2) return null;
  final rates = <double>[
    for (final block in blocks) (lapses[block] ?? 0) / (total[block] ?? 1),
  ];
  final slopes = <double>[];
  for (var i = 0; i < blocks.length; i++) {
    for (var j = i + 1; j < blocks.length; j++) {
      final dx = blocks[j] - blocks[i];
      if (dx <= 0) continue;
      slopes.add((rates[j] - rates[i]) / dx);
    }
  }
  if (slopes.isEmpty) return null;
  slopes.sort();
  final middle = slopes.length ~/ 2;
  return slopes.length.isOdd
      ? slopes[middle]
      : (slopes[middle - 1] + slopes[middle]) / 2;
}

/// 默认选择率：在二选一任务里选「左边 / 第一个选项」的比例。
///
/// 设计文档 §3.2 只给了 `default_choice_rate` 这个指标名与基线（越低越好：
/// 一直选默认项说明没在读题），没有给公式；这里的口径是**占位**，等真实
/// 数据标定后换成「与上一 trial 同侧」或模型定义的默认项。
double? _defaultChoiceRate(List<TrialResult> trials) {
  var answered = 0;
  var left = 0;
  for (final trial in trials) {
    if (!trial.isMeasured) continue;
    final choice = trial.response['choice'];
    if (choice is! String) continue;
    answered++;
    if (choice == 'left') left++;
  }
  if (answered == 0) return null;
  return left / answered;
}

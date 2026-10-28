/// 评测板块 §3.2 统计指标（纯逻辑，2026-10-29）。
///
/// 口径（设计文档 v1.0 §3.2 / §9）：
///
/// * 只统计有效 trial（[TrialResult.isMeasured]）；练习 block 不进入任何指标。
/// * 样本不足、无可比组、除零一律返回 `null` —— 不编造 0，也不抛异常，
///   调用方据 `null` 跳过该指标（不写 `assessment_metrics` 行）。
/// * 反应时类指标只用 `rtMs != null` 的 trial（超时/未作答不是 0 ms）。
/// * 判别类指标默认从 `stimulus` 的稳定键读条件：`is_target`（go/no-go）、
///   `switch`（切换）、`congruent`（Stroop）、`span`（数字/工作记忆跨度）；
///   任务可用回调覆盖，指标函数不解析其它私有字段。
/// * 分位数用线性插值（位置 `p * (n - 1)`）；[rtIqr] = Q3 - Q1。
/// * 所有函数确定性、不读时钟、不随机，输入列表不被修改。
library;

import 'dart:math' as math;

import 'assessment_models.dart';

/// 反应时中位数（ms）；没有有效的 `rtMs` 时返回 `null`。
double? rtMedian(Iterable<TrialResult> trials) =>
    _quantile(_rtValues(trials), 0.5);

/// 反应时四分位距（Q3 - Q1，ms）；有效 RT 少于 2 个时返回 `null`。
double? rtIqr(Iterable<TrialResult> trials) {
  final values = _rtValues(trials);
  if (values.length < 2) return null;
  final q1 = _quantile(values, 0.25);
  final q3 = _quantile(values, 0.75);
  if (q1 == null || q3 == null) return null;
  return q3 - q1;
}

/// 正确率 = 正确 trial 数 / 有判定结果的 trial 数；没有可判定 trial 时返回 `null`。
double? accuracy(Iterable<TrialResult> trials) {
  var answered = 0;
  var correct = 0;
  for (final trial in trials) {
    if (!trial.isMeasured) continue;
    final isCorrect = trial.correct;
    if (isCorrect == null) continue;
    answered++;
    if (isCorrect) correct++;
  }
  if (answered == 0) return null;
  return correct / answered;
}

/// 命中率 = 目标 trial 中答对的占比；没有目标 trial 时返回 `null`。
double? hitRate(Iterable<TrialResult> trials,
    {bool Function(TrialResult trial)? isTarget}) {
  final counts = _hitCounts(trials, isTarget ?? _defaultIsTarget);
  if (counts.targets == 0) return null;
  return counts.hits / counts.targets;
}

/// 虚报率 = 非目标 trial 中错误「是」的占比；没有非目标 trial 时返回 `null`。
double? falseAlarmRate(Iterable<TrialResult> trials,
    {bool Function(TrialResult trial)? isTarget}) {
  final counts = _falseAlarmCounts(trials, isTarget ?? _defaultIsTarget);
  if (counts.nonTargets == 0) return null;
  return counts.falseAlarms / counts.nonTargets;
}

/// 信号检测论 d′（越高越强）：`z(命中率) - z(虚报率)`。
///
/// 命中/虚报先做 log-linear 校正：`(x + 0.5) / (n + 1)`，避免 0 / 1 的极端比率。
/// 缺目标或非目标 trial 时返回 `null`。
double? dPrime(Iterable<TrialResult> trials,
    {bool Function(TrialResult trial)? isTarget}) {
  final selector = isTarget ?? _defaultIsTarget;
  final hits = _hitCounts(trials, selector);
  final falseAlarms = _falseAlarmCounts(trials, selector);
  return dPrimeFromCounts(
    hits: hits.hits,
    targets: hits.targets,
    falseAlarms: falseAlarms.falseAlarms,
    nonTargets: falseAlarms.nonTargets,
  );
}

/// 由原始计数算 d′；与 [dPrime] 同一套 log-linear 校正。
double? dPrimeFromCounts({
  required int hits,
  required int targets,
  required int falseAlarms,
  required int nonTargets,
}) {
  if (targets <= 0 || nonTargets <= 0) return null;
  final hitRate = logLinearRate(successes: hits, trials: targets);
  final falseAlarmRate =
      logLinearRate(successes: falseAlarms, trials: nonTargets);
  return _inverseNormalCdf(hitRate) - _inverseNormalCdf(falseAlarmRate);
}

/// log-linear 校正后的比率：`(successes + 0.5) / (trials + 1)`。
double logLinearRate({required int successes, required int trials}) {
  final safeSuccesses = successes < 0 ? 0 : successes;
  final safeTrials = trials < 0 ? 0 : trials;
  return (safeSuccesses + 0.5) / (safeTrials + 1);
}

/// go/no-go 反应时代价：`(中位 RT_go - 中位 RT_noGo) / 中位 RT_noGo`。
///
/// 只对两类 trial 都有 RT 的变体有意义；任一类缺样本或 no-go 中位数为 0 时返回 `null`。
double? rtCost(Iterable<TrialResult> trials,
    {bool Function(TrialResult trial)? isTarget}) {
  final selector = isTarget ?? _defaultIsTarget;
  final goRts = <double>[];
  final noGoRts = <double>[];
  for (final trial in trials) {
    if (!trial.isMeasured) continue;
    final rt = trial.rtMs;
    if (rt == null) continue;
    if (selector(trial)) {
      goRts.add(rt.toDouble());
    } else {
      noGoRts.add(rt.toDouble());
    }
  }
  final goMedian = _quantile(goRts, 0.5);
  final noGoMedian = _quantile(noGoRts, 0.5);
  if (goMedian == null || noGoMedian == null || noGoMedian == 0) return null;
  return (goMedian - noGoMedian) / noGoMedian;
}

/// 稳定跨度：同一跨度上连续答对至少 [requiredConsecutive] 次（默认 2 次）的最高跨度。
///
/// 默认从 `stimulus['span']` 读跨度；跨度切换、不可判定 trial 都会打断连续计数。
int? stableSpan(
  Iterable<TrialResult> trials, {
  int requiredConsecutive = 2,
  int? Function(TrialResult trial)? spanOf,
}) {
  final needed = requiredConsecutive < 1 ? 1 : requiredConsecutive;
  final selector = spanOf ?? _defaultSpanOf;
  int? best;
  int? currentSpan;
  var run = 0;
  for (final trial in trials) {
    if (!trial.isMeasured) continue;
    final span = selector(trial);
    final isCorrect = trial.correct;
    if (span == null || isCorrect == null) {
      currentSpan = null;
      run = 0;
      continue;
    }
    if (span != currentSpan) {
      currentSpan = span;
      run = 0;
    }
    if (isCorrect) {
      run++;
      if (run >= needed && (best == null || span > best)) best = span;
    } else {
      run = 0;
    }
  }
  return best;
}

/// 反应时随块号的 Theil–Sen 稳健斜率（ms/块）。
///
/// 先按 `blockIndex` 求每块中位 RT，再对所有块对求斜率、取中位数；块数少于 2 时返回 `null`。
double? rtSlope(Iterable<TrialResult> trials) {
  final byBlock = <int, List<double>>{};
  for (final trial in trials) {
    if (!trial.isMeasured) continue;
    final rt = trial.rtMs;
    if (rt == null) continue;
    byBlock.putIfAbsent(trial.blockIndex, () => <double>[]).add(rt.toDouble());
  }
  if (byBlock.length < 2) return null;
  final blocks = byBlock.keys.toList()..sort();
  final medians = <double>[];
  for (final block in blocks) {
    final median = _quantile(byBlock[block]!, 0.5);
    if (median == null) return null;
    medians.add(median);
  }
  final slopes = <double>[];
  for (var i = 0; i < blocks.length; i++) {
    for (var j = i + 1; j < blocks.length; j++) {
      final dx = blocks[j] - blocks[i];
      if (dx <= 0) continue;
      slopes.add((medians[j] - medians[i]) / dx);
    }
  }
  return _quantile(slopes, 0.5);
}

/// 方差漂移：后段 RT 方差 / 前段 RT 方差（样本方差，按 trial 顺序对半切）。
///
/// 有效 RT 少于 4 个、任一段少于 2 个、前段方差为 0 时返回 `null`。
double? varianceDrift(Iterable<TrialResult> trials) {
  final values = _rtValues(trials);
  if (values.length < 4) return null;
  final middle = values.length ~/ 2;
  final first = values.sublist(0, middle);
  final second = values.sublist(middle);
  if (first.length < 2 || second.length < 2) return null;
  final firstVariance = _sampleVariance(first);
  final secondVariance = _sampleVariance(second);
  if (firstVariance == null || secondVariance == null || firstVariance == 0) {
    return null;
  }
  return secondVariance / firstVariance;
}

/// 切换代价：`中位 RT_switch - 中位 RT_repeat`（ms）。
///
/// 默认从 `stimulus['switch'] == true` 识别切换 trial；任一组缺 RT 时返回 `null`。
double? switchCost(
  Iterable<TrialResult> trials, {
  bool Function(TrialResult trial)? isSwitchTrial,
}) {
  final selector = isSwitchTrial ?? _defaultIsSwitch;
  final switchRts = <double>[];
  final repeatRts = <double>[];
  for (final trial in trials) {
    if (!trial.isMeasured) continue;
    final rt = trial.rtMs;
    if (rt == null) continue;
    if (selector(trial)) {
      switchRts.add(rt.toDouble());
    } else {
      repeatRts.add(rt.toDouble());
    }
  }
  final switchMedian = _quantile(switchRts, 0.5);
  final repeatMedian = _quantile(repeatRts, 0.5);
  if (switchMedian == null || repeatMedian == null) return null;
  return switchMedian - repeatMedian;
}

/// 冲突代价：`中位 RT_incongruent - 中位 RT_congruent`（ms）。
///
/// 默认从 `stimulus['congruent'] == true` 识别一致条件；任一组缺 RT 时返回 `null`。
double? conflictCost(
  Iterable<TrialResult> trials, {
  bool Function(TrialResult trial)? isCongruentTrial,
}) {
  final selector = isCongruentTrial ?? _defaultIsCongruent;
  final congruentRts = <double>[];
  final incongruentRts = <double>[];
  for (final trial in trials) {
    if (!trial.isMeasured) continue;
    final rt = trial.rtMs;
    if (rt == null) continue;
    if (selector(trial)) {
      congruentRts.add(rt.toDouble());
    } else {
      incongruentRts.add(rt.toDouble());
    }
  }
  final congruentMedian = _quantile(congruentRts, 0.5);
  final incongruentMedian = _quantile(incongruentRts, 0.5);
  if (congruentMedian == null || incongruentMedian == null) return null;
  return incongruentMedian - congruentMedian;
}

/// 决策漂移：后段中位 RT / 前段中位 RT（按 trial 顺序对半切）。
///
/// 有效 RT 少于 4 个或前段中位数为 0 时返回 `null`。
double? decisionDrift(Iterable<TrialResult> trials) {
  final values = _rtValues(trials);
  if (values.length < 4) return null;
  final middle = values.length ~/ 2;
  final firstMedian = _quantile(values.sublist(0, middle), 0.5);
  final secondMedian = _quantile(values.sublist(middle), 0.5);
  if (firstMedian == null || secondMedian == null || firstMedian == 0) {
    return null;
  }
  return secondMedian / firstMedian;
}

List<double> _rtValues(Iterable<TrialResult> trials) {
  final values = <double>[];
  for (final trial in trials) {
    if (!trial.isMeasured) continue;
    final rt = trial.rtMs;
    if (rt == null) continue;
    values.add(rt.toDouble());
  }
  return values;
}

double? _quantile(List<double> values, double p) {
  if (values.isEmpty) return null;
  if (values.length == 1) return values.single;
  final sorted = List<double>.of(values)..sort();
  final position = p * (sorted.length - 1);
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) return sorted[lower];
  final fraction = position - lower;
  return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction;
}

double? _sampleVariance(List<double> values) {
  if (values.length < 2) return null;
  var sum = 0.0;
  for (final value in values) {
    sum += value;
  }
  final mean = sum / values.length;
  var squared = 0.0;
  for (final value in values) {
    final delta = value - mean;
    squared += delta * delta;
  }
  return squared / (values.length - 1);
}

({int hits, int targets}) _hitCounts(
  Iterable<TrialResult> trials,
  bool Function(TrialResult trial) selector,
) {
  var hits = 0;
  var targets = 0;
  for (final trial in trials) {
    if (!trial.isMeasured) continue;
    final isCorrect = trial.correct;
    if (isCorrect == null || !selector(trial)) continue;
    targets++;
    if (isCorrect) hits++;
  }
  return (hits: hits, targets: targets);
}

({int falseAlarms, int nonTargets}) _falseAlarmCounts(
  Iterable<TrialResult> trials,
  bool Function(TrialResult trial) selector,
) {
  var falseAlarms = 0;
  var nonTargets = 0;
  for (final trial in trials) {
    if (!trial.isMeasured) continue;
    final isCorrect = trial.correct;
    if (isCorrect == null || selector(trial)) continue;
    nonTargets++;
    if (!isCorrect) falseAlarms++;
  }
  return (falseAlarms: falseAlarms, nonTargets: nonTargets);
}

bool _defaultIsTarget(TrialResult trial) => trial.stimulus['is_target'] == true;

bool _defaultIsSwitch(TrialResult trial) => trial.stimulus['switch'] == true;

bool _defaultIsCongruent(TrialResult trial) =>
    trial.stimulus['congruent'] == true;

int? _defaultSpanOf(TrialResult trial) {
  final value = trial.stimulus['span'];
  if (value is int) return value;
  if (value is num) return value.round();
  return null;
}

/// 标准正态分布逆函数（Acklam 有理近似，误差 < 1.15e-9）。
double _inverseNormalCdf(double p) {
  if (p.isNaN) return double.nan;
  var probability = p;
  if (probability < 1e-12) probability = 1e-12;
  if (probability > 1 - 1e-12) probability = 1 - 1e-12;
  const double pLow = 0.02425;
  const double pHigh = 1 - pLow;
  const double a0 = -3.969683028665376e+01;
  const double a1 = 2.209460984245205e+02;
  const double a2 = -2.759285104469687e+02;
  const double a3 = 1.383577518672690e+02;
  const double a4 = -3.066479806614716e+01;
  const double a5 = 2.506628277459239e+00;
  const double b0 = -5.447609879822406e+01;
  const double b1 = 1.615858368580409e+02;
  const double b2 = -1.556989798598866e+02;
  const double b3 = 6.680131188771972e+01;
  const double b4 = -1.328068155288572e+01;
  const double c0 = -7.784894002430293e-03;
  const double c1 = -3.223964580411365e-01;
  const double c2 = -2.400758277161838e+00;
  const double c3 = -2.549732539343734e+00;
  const double c4 = 4.374664141464968e+00;
  const double c5 = 2.938163982698783e+00;
  const double d0 = 7.784695709041462e-03;
  const double d1 = 3.224671290700398e-01;
  const double d2 = 2.445134137142996e+00;
  const double d3 = 3.754408661907416e+00;
  if (probability < pLow) {
    final q = math.sqrt(-2 * math.log(probability));
    return (((((c0 * q + c1) * q + c2) * q + c3) * q + c4) * q + c5) /
        ((((d0 * q + d1) * q + d2) * q + d3) * q + 1);
  }
  if (probability <= pHigh) {
    final q = probability - 0.5;
    final r = q * q;
    return (((((a0 * r + a1) * r + a2) * r + a3) * r + a4) * r + a5) *
        q /
        (((((b0 * r + b1) * r + b2) * r + b3) * r + b4) * r + 1);
  }
  final q = math.sqrt(-2 * math.log(1 - probability));
  return -(((((c0 * q + c1) * q + c2) * q + c3) * q + c4) * q + c5) /
      ((((d0 * q + d1) * q + d2) * q + d3) * q + 1);
}

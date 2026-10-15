/// 标定协议 v1（本地那一条）：把"模型当时说的 `R`"与"真实结果"对起来，
/// 给出一个**可检验**的偏差量，并且在该拒绝给数的时候明确拒绝。
///
/// 为什么要有这个文件：`learning_metrics.dart` 已经把预测与结果摆到了一起
/// （Brier / ECE / 分箱），但那三个数字只回答"有多不准"，不回答"往哪偏、偏得
/// 算不算真"。而 `docs/ASSESSMENT_DESIGN.md` 一直挂着一句"把 `calibrated` 从 false
/// 变 true（需要标定协议）"——在协议跑过之前，`cognitive_priors.calibrated` 必须
/// 继续是 0（`assessment_repository.dart` 永远不写 1）。这一层就是协议的**估计量**部分：
///
/// - 输入只有一样：复习日志里在判分**之前**落库的 `predicted_r`（v11 起），
///   配上这次复习的真实结果。事后重算的 `R` 不算样本（那已经被 `retentionSamples`
///   的读取口径挡住：老行 NULL，且**不补算**）。
/// - 估计量是二参数 logistic 重标定 `p = σ(a·logit(r) + b)`：`b` 是"系统性过度自信/
///   低估"的全局偏置，`a` 是"预测的离散度够不够"的斜率。用牛顿迭代解，标准误从
///   观测信息矩阵的逆取，不做任何随机初始化（同输入必得同输出）。
/// - 诚实规则写在 [CalibrationReport.read] 里：没有样本、样本太少、结果只有一类
///   （全对或全错，似然没有有限最大值）时**拒绝给系数**，而不是给一个看起来像结论的数。
///   斜率要 n ≥ [kMinSlopeSamplesForTrust] 才值得读。
///
/// 纯逻辑：没有数据库、没有 Flutter、没有时钟。谁拿样本进来，谁负责样本来源。
///
/// 六个 MindNet 实验（`ls` / `W_DAR` / `β_goal` / `kappa_reach` / `T_ign` 等）的协议
/// 在 MindNet 侧（只读：`E:\Document\MindNet\docs\CALIBRATION.md`），本仓库没有那批
/// 实验数据，所以本地协议只覆盖**上面这一条**；口径与边界见 `docs/CALIBRATION.md`。
library;

import 'dart:math' as math;

import '../srs/dsr_memory.dart';
import 'learning_metrics.dart';

/// 拟合至少需要多少条带预测的样本。
///
/// 30 是个刻意保守的门槛：它不来自任何论文，而是"再多一条反例就能把结论翻过来"的
/// 那个规模——在这个规模以下，`b` 会跟着噪声走，报出来就是在骗人。
const int kMinCalibrationSamples = 30;

/// 斜率 `a` 值得读的最低样本量。
///
/// 截距 `b` 在 30 条时已经有意义（它是全局偏差），但 `a` 要区分"预测太极端"与
/// "预测太平"需要更多样本：这里给 200，并且**无论多少样本都算 `a`**（截距的
/// 正确性依赖它），只是不满 200 时标成不可读。
const int kMinSlopeSamplesForTrust = 200;

/// 牛顿迭代的上限；超过就当作没收敛（拒绝给系数）。
const int kMaxNewtonIterations = 100;

/// 每一步最多二分回溯多少次（步长减半）。
const int kMaxBacktrackingSteps = 40;

/// 梯度收敛判据（两个分量都小于它就算到顶了）。
///
/// 用 `1e-7` 而不是更小的数：对数似然在双精度下的平坦区在 `1e-13` 量级，`1e-10`
/// 这种门槛会让迭代在已经到顶之后还在原地打转（步长减到 2⁻⁴⁰ 也无法让似然"更大"），
/// 最后因为"走不动"而误报"没收敛"。`1e-7` 对应的系数精度远好于 6 位小数。
const double kGradientTolerance = 1e-7;

/// 偏置是否"显著"的阈值（双侧 95%）。只用来措辞，不用来决定要不要给数。
const double kCalibrationSignificanceZ = 1.96;

/// `logit` 在 0 / 1 处会发散，所以预测 `R` 先夹到这个范围内。
///
/// 取 `1e-3` 而不是更小的数是有理由的：夹到 `1e-6` 会把 `logit` 推到 ±13.8，
/// 于是"模型说了 0 或 1"的样本在信息矩阵里的权重掉到 1e-12 量级，拟合会因为数值
/// 退化而拒绝整批数据——那等于用实现细节否掉了真实样本。`1e-3` 等于把"完全确定"
/// 读成"99.9% / 0.1%"：记忆预测本来就不该是完全确定的，这个口径既保留样本信息，
/// 又不会把一条 0 变成无穷大。
const double kLogitEpsilon = 1e-3;

/// 系数与标准误的可读上限。
///
/// 数据"几乎可分"时（某一侧的样本全是同一类），最大似然估计不存在——似然沿着某个
/// 方向还能一直变大。数值上它表现为系数与标准误一起冲到几十上百。超过这个量级就
/// 认为没有可读的结论：报一个 `b=27±15000` 比"拒绝给数"坏得多。
const double kMaxUsableCoefficientMagnitude = 10.0;

/// 标准误的可读上限（与 [kMaxUsableCoefficientMagnitude] 同一个量级）。
const double kMaxUsableStdError = 10.0;

/// 标定这条路的五种结局。
///
/// 前四种都是"不算"：失败在这里是一个**正当结论**，不是错误。
enum CalibrationVerdict {
  /// 一条带预测的样本都没有（v11 之前的复习没有这个值，也不补算）。
  noSamples('no_samples', '还没有样本'),

  /// 样本少于 [kMinCalibrationSamples]。
  tooFewSamples('too_few_samples', '样本不足'),

  /// 结果只有一类（全对或全错）：似然没有有限最大值。
  singleClass('single_class', '只有一类结果'),

  /// 牛顿迭代没收敛，或观测信息矩阵退化。
  notConverged('not_converged', '拟合没收敛'),

  /// 有可读的拟合结果。
  ok('ok', '可以看');

  const CalibrationVerdict(this.wireValue, this.labelZh);

  /// 进 JSON / 模型的稳定键。
  final String wireValue;

  /// 给日志与摘要看的中文名。
  final String labelZh;

  static CalibrationVerdict? byKey(String? key) {
    if (key == null) return null;
    for (final verdict in values) {
      if (verdict.wireValue == key) return verdict;
    }
    return null;
  }
}

/// 一次成功的重标定拟合。
class CalibrationFit {
  const CalibrationFit({
    required this.intercept,
    required this.interceptStdError,
    required this.slope,
    required this.slopeStdError,
    required this.logLikelihood,
    required this.iterations,
  });

  /// 全局偏置 `b`：正数＝模型系统性**低估**自己（实际比预测更常记住），
  /// 负数＝系统性过度自信。
  final double intercept;

  /// `b` 的标准误（观测信息矩阵逆的对角线开方）。
  final double interceptStdError;

  /// 斜率 `a`：1 附近＝离散度合适；<1＝预测太平；>1＝预测太极端。
  final double slope;

  /// `a` 的标准误。
  final double slopeStdError;

  /// 收敛点的对数似然。
  final double logLikelihood;

  /// 用掉了几次迭代。
  final int iterations;

  /// `b` 的 z 值；标准误非正时为 0。
  double get biasZ =>
      interceptStdError > 0 ? intercept.abs() / interceptStdError : 0;

  /// `b` 与 0 的差异是否达到双侧 95%。
  bool get biasSignificant => biasZ >= kCalibrationSignificanceZ;

  /// 斜率是否值得读（样本量门槛见 [kMinSlopeSamplesForTrust]）。
  bool slopeUsableIn(int sampleCount) =>
      sampleCount >= kMinSlopeSamplesForTrust;

  Map<String, Object?> toJson() => {
        'intercept': DsrMemory.round6(intercept),
        'intercept_std_error': DsrMemory.round6(interceptStdError),
        'slope': DsrMemory.round6(slope),
        'slope_std_error': DsrMemory.round6(slopeStdError),
        'log_likelihood': DsrMemory.round6(logLikelihood),
        'iterations': iterations,
      };
}

/// 一份校准结论：能不能看、往哪偏、偏得算不算真。
class CalibrationReport {
  const CalibrationReport({
    required this.samples,
    required this.positives,
    required this.meanPredicted,
    required this.observedRate,
    required this.verdict,
    this.fit,
    this.refusalReasonZh,
  });

  /// 带预测值的样本数（不是复习总次数）。
  final int samples;

  /// 其中真的记住了的次数。
  final int positives;

  /// 预测 `R` 的平均值。
  final double meanPredicted;

  /// 实际记住的比例。
  final double observedRate;

  final CalibrationVerdict verdict;

  /// 只有 [verdict] 为 [CalibrationVerdict.ok] 时非空。
  final CalibrationFit? fit;

  /// 不算的原因（中文，直接可展示）。
  final String? refusalReasonZh;

  static const CalibrationReport empty = CalibrationReport(
    samples: 0,
    positives: 0,
    meanPredicted: 0,
    observedRate: 0,
    verdict: CalibrationVerdict.noSamples,
    refusalReasonZh: '还没有带预测的复习样本（v11 之前的复习没有这个值，也不补算）。',
  );

  /// 有可读的拟合结果。
  bool get usable => verdict == CalibrationVerdict.ok && fit != null;

  /// 偏差达到显著（且本来就可读）。
  bool get biasSignificant => usable && fit!.biasSignificant;

  /// 斜率是否可读。
  bool get slopeUsable => usable && fit!.slopeUsableIn(samples);

  /// 实际减预测：正数＝模型低估自己。
  double get observedMinusPredicted => observedRate - meanPredicted;

  /// 一句话结论（中文，含"不算"的那几种）。
  String get summaryZh {
    if (!usable) {
      return '${verdict.labelZh}：${refusalReasonZh ?? '没有可读的标定结论。'}';
    }
    final bias = fit!;
    final direction = bias.intercept >= 0 ? '低估自己' : '过度自信';
    final significance = bias.biasSignificant
        ? '这个偏差是显著的（z=${bias.biasZ.toStringAsFixed(2)}）'
        : '这个偏差还不显著（z=${bias.biasZ.toStringAsFixed(2)}），可以说模型没有系统性偏差';
    return '$samples 条带预测的复习：预测平均 ${DsrMemory.round6(meanPredicted)}、'
        '实际记住 ${DsrMemory.round6(observedRate)}；'
        '偏置 b=${DsrMemory.round6(bias.intercept)}（$direction），$significance。'
        '${slopeUsable ? '斜率 a=${DsrMemory.round6(bias.slope)}。' : '斜率样本不够（<$kMinSlopeSamplesForTrust 条），只看偏置。'}';
  }

  Map<String, Object?> toJson() => {
        'schema': 'mindnet.calibration/1',
        'verdict': verdict.wireValue,
        'verdict_zh': verdict.labelZh,
        'usable': usable,
        'samples': samples,
        'positives': positives,
        'observed_rate': DsrMemory.round6(observedRate),
        'mean_predicted': DsrMemory.round6(meanPredicted),
        'refusal': refusalReasonZh,
        'bias_significant': biasSignificant,
        'slope_usable': slopeUsable,
        'fit': fit?.toJson(),
      };

  /// 从样本算出结论。样本来源见 `retentionSamples()`。
  ///
  /// 顺序即诚实规则的顺序：没有样本 → 样本太少 → 结果只有一类 → 拟合失败 → 报告。
  /// 每一步的拒绝理由都写成人能读懂的中文，因为调用方（读数页、AI 工具）会**原样**
  /// 展示它——"拒绝给数"本身就是这条协议要传达的信息。
  static CalibrationReport read({required List<RetentionSample> samples}) {
    final predicted = <double>[];
    final outcome = <bool>[];
    for (final sample in samples) {
      final r = sample.predictedR;
      if (r == null) continue;
      predicted.add(r.clamp(0.0, 1.0));
      outcome.add(sample.recalled);
    }

    final n = predicted.length;
    if (n == 0) return empty;

    var positives = 0;
    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      sum += predicted[i];
      if (outcome[i]) positives++;
    }
    final meanPredicted = sum / n;
    final observedRate = positives / n;

    if (n < kMinCalibrationSamples) {
      return CalibrationReport(
        samples: n,
        positives: positives,
        meanPredicted: meanPredicted,
        observedRate: observedRate,
        verdict: CalibrationVerdict.tooFewSamples,
        refusalReasonZh:
            '样本只有 $n 条，不足 $kMinCalibrationSamples 条：这个规模下拟合出来的系数会跟着噪声走，所以这里拒绝给数（再攒一些复习就有）。',
      );
    }

    if (positives == 0 || positives == n) {
      final only = positives == n ? '记得' : '忘记';
      final missing = positives == n ? '反例（忘记）' : '正例（记得）';
      return CalibrationReport(
        samples: n,
        positives: positives,
        meanPredicted: meanPredicted,
        observedRate: observedRate,
        verdict: CalibrationVerdict.singleClass,
        refusalReasonZh:
            '$n 条样本全是「$only」，没有一条$missing：似然没有有限最大值（把偏置往任一方向推都能更"解释"数据），所以这里拒绝给数。',
      );
    }

    final xs = <double>[for (final r in predicted) _logit(r)];
    final ys = <double>[for (final o in outcome) o ? 1.0 : 0.0];
    final fit = _newton(xs, ys);
    if (fit == null) {
      return CalibrationReport(
        samples: n,
        positives: positives,
        meanPredicted: meanPredicted,
        observedRate: observedRate,
        verdict: CalibrationVerdict.notConverged,
        refusalReasonZh: '拟合没有收敛（或观测信息矩阵退化：预测值几乎完全一样，海森解不出逆）：'
            '这种情况给不出可信的系数。数据"几乎可分"（某一侧样本几乎全是同一类）时也会这样——'
            '最大似然估计不存在，硬报一个系数就是在骗人。',
      );
    }

    return CalibrationReport(
      samples: n,
      positives: positives,
      meanPredicted: meanPredicted,
      observedRate: observedRate,
      verdict: CalibrationVerdict.ok,
      fit: fit,
    );
  }
}

/// 牛顿迭代解 `p_i = σ(a·x_i + b)`，`x_i` 已经是 logit 空间。
///
/// 解析梯度/海森，最多 [kMaxNewtonIterations] 步；收敛判据是梯度足够小。
/// 海森退化（预测值几乎全等）直接返回 `null`——那种数据本来就不含信息。
///
/// **带回溯的牛顿**：纯牛顿步在"预测集中在两端、样本又混着两类结果"时会来回过冲
/// （中间那一箱的权重压倒两端，步长被放得极大 → a 在 ±几十之间跳），结果是数据明明
/// 有有限的最大似然解，却报"没收敛"。所以每一步都先取牛顿方向，再用二分回溯找第一个
/// 让对数似然真的变大的步长；走不动就当作没收敛（`null`），不硬报系数。
CalibrationFit? _newton(List<double> xs, List<double> ys) {
  var a = 1.0;
  var b = 0.0;
  var logLikelihood = _logLikelihoodOf(xs, ys, a, b);
  if (!logLikelihood.isFinite) return null;

  for (var iteration = 1; iteration <= kMaxNewtonIterations; iteration++) {
    var gradA = 0.0;
    var gradB = 0.0;
    var hessAA = 0.0;
    var hessAB = 0.0;
    var hessBB = 0.0;

    for (var i = 0; i < xs.length; i++) {
      final p = _sigmoid(a * xs[i] + b);
      final weight = p * (1 - p);
      final y = ys[i];
      gradA += xs[i] * (y - p);
      gradB += y - p;
      hessAA += xs[i] * xs[i] * weight;
      hessAB += xs[i] * weight;
      hessBB += weight;
    }

    if (gradA.abs() < kGradientTolerance && gradB.abs() < kGradientTolerance) {
      final det = hessAA * hessBB - hessAB * hessAB;
      if (det <= 1e-12) return null;

      // 完全可分（模型能把每一条样本都分到正确的一侧）＝ 似然没有有限最大值：
      // 继续把 a/b 往那个方向推，似然还会变大。这种数据必须拒绝，否则会返回一个
      // 偏置动辄几十、标准误上万的"拟合结果"，那比不给数更坏。
      var separated = true;
      for (var i = 0; i < xs.length; i++) {
        final p = _sigmoid(a * xs[i] + b);
        if ((p >= 0.5) != (ys[i] >= 0.5)) {
          separated = false;
          break;
        }
      }
      if (separated) return null;

      final seA = math.sqrt(hessBB / det);
      final seB = math.sqrt(hessAA / det);
      if (!seA.isFinite || !seB.isFinite) return null;
      if (a.abs() > kMaxUsableCoefficientMagnitude ||
          b.abs() > kMaxUsableCoefficientMagnitude ||
          seA > kMaxUsableStdError ||
          seB > kMaxUsableStdError) {
        // 数据几乎可分：系数和标准误一起冲上去了，这里没有可读的结论。
        return null;
      }
      return CalibrationFit(
        intercept: b,
        interceptStdError: seB,
        slope: a,
        slopeStdError: seA,
        logLikelihood: logLikelihood,
        iterations: iteration,
      );
    }

    final det = hessAA * hessBB - hessAB * hessAB;
    if (!det.isFinite || det <= 1e-12) return null;
    final stepA = (hessBB * gradA - hessAB * gradB) / det;
    final stepB = (hessAA * gradB - hessAB * gradA) / det;
    if (!stepA.isFinite || !stepB.isFinite) return null;

    var scale = 1.0;
    var accepted = false;
    for (var back = 0; back < kMaxBacktrackingSteps; back++) {
      final candA = a + stepA * scale;
      final candB = b + stepB * scale;
      final candLl = _logLikelihoodOf(xs, ys, candA, candB);
      if (candLl.isFinite && candLl > logLikelihood) {
        a = candA;
        b = candB;
        logLikelihood = candLl;
        accepted = true;
        break;
      }
      scale /= 2;
    }
    // 回溯也找不到一个更好的点：要么已经到边界（可分数据），要么数值上走不动。
    // 两种情况都不该硬报系数。
    if (!accepted) return null;
  }

  return null;
}

/// `Σ y·log p + (1−y)·log(1−p)`，回溯用的目标函数。
double _logLikelihoodOf(List<double> xs, List<double> ys, double a, double b) {
  var total = 0.0;
  for (var i = 0; i < xs.length; i++) {
    final p = _sigmoid(a * xs[i] + b);
    total += ys[i] * _logSafe(p) + (1 - ys[i]) * _logSafe(1 - p);
  }
  return total;
}

double _sigmoid(double z) {
  if (z >= 0) return 1 / (1 + math.exp(-z));
  final e = math.exp(z);
  return e / (1 + e);
}

double _logit(double r) {
  final clamped = r.clamp(kLogitEpsilon, 1 - kLogitEpsilon);
  return math.log(clamped / (1 - clamped));
}

double _logSafe(double p) => math.log(p < 1e-300 ? 1e-300 : p);

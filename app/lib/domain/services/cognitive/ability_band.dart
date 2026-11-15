/// 能力档位：把一条**带不确定度的能力后验**折算成 S/A/B/C/D，证据不足时给 `?`。
///
/// 设计来源：工作区 `FURNACE-DESIGN-REFERENCE-2026-11-15.md` §M-04「SABCD 档位」
/// ——用户可见的是「S/A/B/C/D 模糊档位 + 依据类型」，**不显示伪精确百分比**。
/// 实现口径由用户 2026-11-15 确认：「先按后验 + 不确定度分档；证据不足不给档，
/// 显示 ?」。
///
/// 四条纪律（写死在代码里）：
///
/// * **没有证据不给档**。`source=unknown`、没有均值、样本数不足、或不确定度
///   过宽时，输出 [AbilityBand.unknown]、显示 `?`；不拿 0 / 50% 冒充读数。
/// * **预设不是实测**。`source=preset` 允许映射出档位（它是设计先验），但
///   [AbilityBandReading.source] 仍是 preset，显示串带「（预设）」标记，
///   [AbilityBandReading.isMeasured] 为 false：调用方不得把它当成测量。
/// * **同一后验稳定映射**。纯函数：不读时钟、不随机、不读写数据库、不 import
///   Flutter；同一输入永远同一输出。
/// * **阈值未标定**。[AbilityBandThresholds] 的默认值是显式选定的占位阈值，
///   不是心理测量标准；[AbilityBandPolicy] 全部可配置，标定后只改这里。
///
/// 两个量纲（对应 `ability-matrix` JSON 的两类行，别混用）：
///
/// * `probability`（默认）：0–1 掌握度，对应矩阵 knowledge 行的
///   `mastery.mean` 与 `intervals`；
/// * `logit`：能力 logit，对应矩阵 capability 行的 `mean` 与 `uncertainty`
///   （logit 标准差）。两条轴的默认阈值与证据门槛不同，见
///   [AbilityBandPolicy.mastery] / [AbilityBandPolicy.abilityLogit]。
library;

/// 档位。`unknown` 的显示是 `?`（证据不足，不是最低档）。
enum AbilityBand {
  s('S'),
  a('A'),
  b('B'),
  c('C'),
  d('D'),
  unknown('?');

  const AbilityBand(this.label);

  /// 用户可见的档位字：`S` / `A` / `B` / `C` / `D` / `?`。
  final String label;

  /// 是否是真实档位；`unknown` 不是。
  bool get isKnown => this != AbilityBand.unknown;
}

/// 证据来源类别，和 `ability-matrix` JSON 的 `class` 取值（measured / preset /
/// unknown）对齐。
///
/// 矩阵里更细的 `source`（`assessment_v1`、`self_report`、`default`、
/// `preset_fixed` …）由 [AbilitySource.fromCode] 归到这三类；认不出的编码一律
/// 归 [AbilitySource.unknown]（不猜、不抛）。
enum AbilitySource {
  /// 对学习者的观测（矩阵 `MEASURED_SOURCES`）：实测。
  measured('measured'),

  /// 设计先验 / 出厂默认：**不是**对学习者的测量。
  preset('preset'),

  /// 没有证据，也没有预设。
  unknown('unknown');

  const AbilitySource(this.code);

  /// 稳定编码：`measured` / `preset` / `unknown`。
  final String code;

  bool get isMeasured => this == AbilitySource.measured;

  /// 由矩阵 JSON 的 `class` 或 `source` 编码归类。
  ///
  /// * `measured`、`assessment_v1`、`item_response`、`self_report`、
  ///   `process_feedback` → [measured]；
  /// * `preset`、`preset_or_default`、`preset_fixed`、`default` → [preset]；
  /// * `unknown`、空白、null、认不出的编码 → [unknown]。
  ///
  /// 大小写与两端空白容错；其余不模糊匹配。
  static AbilitySource fromCode(String? code) {
    switch ((code ?? '').trim().toLowerCase()) {
      case 'measured':
      case 'assessment_v1':
      case 'assessment':
      case 'item_response':
      case 'self_report':
      case 'process_feedback':
        return measured;
      case 'preset':
      case 'preset_or_default':
      case 'preset_fixed':
      case 'default':
        return preset;
      default:
        return unknown;
    }
  }
}

/// 档位轴的量纲。
enum AbilityBandScale {
  /// 0–1 掌握度（矩阵 knowledge 行）。
  probability,

  /// 能力 logit（矩阵 capability 行，`uncertainty` 是 logit 标准差）。
  logit,
}

/// 一条后验区间（默认按 95% 口径解释宽度阈值）。
class AbilityInterval {
  const AbilityInterval({required this.lo, required this.hi, this.level = 0.95});

  final double lo;
  final double hi;

  /// 区间可信度（0–1）；矩阵 UI 给的是 95% / 80% 两档，取更宽的那条。
  final double level;

  /// 区间宽度，`hi - lo`（非负）。
  double get width => hi - lo;

  Map<String, Object?> toJson() => <String, Object?>{
        'lo': lo,
        'hi': hi,
        'level': level,
      };
}

/// 一档的阈值。默认值**未校准**，只是显式选定的占位切分。
class AbilityBandThresholds {
  const AbilityBandThresholds({
    required this.scale,
    required this.s,
    required this.a,
    required this.b,
    required this.c,
  });

  final AbilityBandScale scale;

  /// `mean >= s` → S。
  final double s;

  /// `mean >= a` → A。
  final double a;

  /// `mean >= b` → B。
  final double b;

  /// `mean >= c` → C；否则 D。
  final double c;

  /// 0–1 掌握度默认阈值：S ≥0.90、A ≥0.75、B ≥0.60、C ≥0.40、D <0.40。
  ///
  /// 这组数是为了「先跑通分档」而显式选定的**占位值**，不是心理测量标准，
  /// 也没有在本机数据上做过等值/信度标定。
  static const AbilityBandThresholds masteryProbability = AbilityBandThresholds(
    scale: AbilityBandScale.probability,
    s: 0.90,
    a: 0.75,
    b: 0.60,
    c: 0.40,
  );

  /// 能力 logit 默认阈值：S ≥1.5、A ≥0.75、B ≥0、C ≥−0.75、D <−0.75。
  ///
  /// 同样是**未校准占位值**（0 只表示「平均水平」，不是熟练线）。
  static const AbilityBandThresholds abilityLogit = AbilityBandThresholds(
    scale: AbilityBandScale.logit,
    s: 1.5,
    a: 0.75,
    b: 0.0,
    c: -0.75,
  );

  /// 均值落档。边界闭区间：`== s` 就是 S。
  AbilityBand bandFor(double mean) {
    if (mean >= s) return AbilityBand.s;
    if (mean >= a) return AbilityBand.a;
    if (mean >= b) return AbilityBand.b;
    if (mean >= c) return AbilityBand.c;
    return AbilityBand.d;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'scale': scale.name,
        's': s,
        'a': a,
        'b': b,
        'c': c,
      };
}

/// 分档策略：阈值 + 两条「证据不足」门槛。
class AbilityBandPolicy {
  const AbilityBandPolicy({
    this.thresholds = AbilityBandThresholds.masteryProbability,
    this.minObservations = 3,
    this.maxIntervalWidth = 0.60,
    this.calibrated = false,
  });

  final AbilityBandThresholds thresholds;

  /// 实测档的最低观测数；低于它 → `?`。
  final int minObservations;

  /// 后验区间（默认按 95% 解释）的宽度上限；超过它 → `?`。
  final double maxIntervalWidth;

  /// 这组阈值/门槛是否已在真实数据上标定。默认 false（当前就是未标定）。
  final bool calibrated;

  /// 0–1 掌握度（矩阵 knowledge 行）用的默认策略。
  static const AbilityBandPolicy mastery = AbilityBandPolicy();

  /// 能力 logit（矩阵 capability 行）用的默认策略。
  ///
  /// logit 轴上一个 95% 区间宽 3.0 约等于 sd 0.765；观测数门槛同样为 3。
  static const AbilityBandPolicy abilityLogit = AbilityBandPolicy(
    thresholds: AbilityBandThresholds.abilityLogit,
    maxIntervalWidth: 3.0,
  );
}

/// 分档输入：一条后验 + 它的证据强度。
class AbilityBandInput {
  const AbilityBandInput({
    required this.source,
    required this.nObs,
    this.mean,
    this.interval,
    this.sd,
  });

  final AbilitySource source;

  /// 观测数（矩阵 `evidence.n_obs` / capability 的 `n_measurements`）。
  final int nObs;

  /// 后验均值；null = 没有均值（预估置行为就是这种）。
  final double? mean;

  /// 后验区间（有则优先于 [sd]）。
  final AbilityInterval? interval;

  /// 后验标准差（与 [mean] 同量纲）；没有区间时用它换算 95% 宽度。
  final double? sd;

  /// 由矩阵 UI 的 knowledge 行构造。
  ///
  /// 读取 `mastery.class`（优先）/ `mastery.source`、`mastery.mean`、
  /// `mastery.intervals`（UI 投影是 `{"95": [lo, hi]}`，完整矩阵是
  /// `[{"lo", "hi", "level"}]` 列表），以及 `evidence.n_obs`。
  factory AbilityBandInput.fromMatrixKnowledgeRow(
    Map<String, Object?> row,
  ) {
    final mastery = _mapOf(row['mastery']);
    final evidence = _mapOf(row['evidence']);
    return AbilityBandInput(
      source: AbilitySource.fromCode(
        _stringOf(mastery['class']) ?? _stringOf(mastery['source']),
      ),
      nObs: _intOf(evidence['n_obs']),
      mean: _doubleOf(mastery['mean']),
      interval: _intervalOf(mastery['intervals']),
    );
  }

  /// 由矩阵 UI 的 capability 行构造（logit 量纲：`mean` + `uncertainty` sd）。
  factory AbilityBandInput.fromMatrixCapability(Map<String, Object?> row) {
    return AbilityBandInput(
      source: AbilitySource.fromCode(
        _stringOf(row['class']) ?? _stringOf(row['source']),
      ),
      nObs: _intOf(row['n_measurements'] ?? row['n_obs']),
      mean: _doubleOf(row['mean']),
      sd: _doubleOf(row['uncertainty'] ?? row['sd'] ?? row['sd_logit']),
    );
  }
}

/// 为什么没给出档位。`none` 表示给了档位。
enum AbilityUnknownReason {
  none('none'),

  /// 来源本身就是 unknown：没有证据也没有预设。
  sourceUnknown('source_unknown'),

  /// 有来源但没有均值（例如未测量的预设行）。
  noMean('no_mean'),

  /// 观测数低于策略门槛。
  tooFewObservations('too_few_observations'),

  /// 实测行既没有区间也没有标准差，无法判断不确定度。
  missingUncertainty('missing_uncertainty'),

  /// 后验区间宽度超过策略上限。
  uncertainInterval('uncertain_interval');

  const AbilityUnknownReason(this.code);

  final String code;
}

/// 分档读数。
class AbilityBandReading {
  const AbilityBandReading({
    required this.band,
    required this.source,
    required this.unknownReason,
    required this.nObs,
    required this.mean,
    required this.interval,
    required this.thresholds,
    required this.calibrated,
  });

  final AbilityBand band;
  final AbilitySource source;
  final AbilityUnknownReason unknownReason;
  final int nObs;
  final double? mean;

  /// 实际用于宽度判定的区间（调用方给的原样，或由 [sd] 换算的 95% 区间）。
  final AbilityInterval? interval;

  final AbilityBandThresholds thresholds;

  /// 这组阈值/门槛是否已标定（当前默认 false）。
  final bool calibrated;

  /// 是否是一条**实测**档位：来源是 measured 且真的出了档。
  bool get isMeasured => source.isMeasured && band.isKnown;

  /// 是否是一条**预设**档位（设计先验，不是测量）。
  bool get isPreset => source == AbilitySource.preset && band.isKnown;

  /// 用户可见串：`S`…`D` / `?`，预设档追加「（预设）」。
  String get display =>
      '${band.label}${source == AbilitySource.preset ? '（预设）' : ''}';

  /// 序列化。`evidence_class` 与矩阵 JSON 的 `class` 同词表；
  /// `calibrated=false` 提醒下游：档位映射尚未标定。
  Map<String, Object?> toJson() => <String, Object?>{
        'band': band.name,
        'band_label': band.label,
        'source': source.code,
        'evidence_class': source.code,
        'display': display,
        'unknown_reason': unknownReason.code,
        'n_obs': nObs,
        'mean': mean,
        'interval': interval?.toJson(),
        'scale': thresholds.scale.name,
        'thresholds': thresholds.toJson(),
        'calibrated': calibrated,
      };
}

/// 一条后验 → 档位读数。
///
/// 规则顺序（显式，测试覆盖边界）：
///
/// 1. `source=unknown` → `?`（[AbilityUnknownReason.sourceUnknown]）；
/// 2. 没有均值 → `?`（[AbilityUnknownReason.noMean]）；
/// 3. `source=measured`：
///    * `nObs < minObservations` → `?`；
///    * 既没区间也没 sd → `?`（不确定度是必填的）；
///    * 区间宽度 > `maxIntervalWidth` → `?`；
///    * 否则按阈值落档；
/// 4. `source=preset`：有均值就按阈值落档，但带「（预设）」标记；不受实测的
///    样本数 / 区间宽度门槛约束。
///
/// 非法输入（负观测数、NaN、负 sd、lo > hi、阈值不递减…）抛 [ArgumentError]：
/// 这是调用方 bug，不该被静默降级成 `?`。
AbilityBandReading readAbilityBand(
  AbilityBandInput input, {
  AbilityBandPolicy policy = AbilityBandPolicy.mastery,
}) {
  _validateInput(input);
  _validatePolicy(policy);

  final mean = input.mean;
  final thresholds = policy.thresholds;
  final interval = _effectiveInterval(input);

  var band = AbilityBand.unknown;
  var reason = AbilityUnknownReason.none;

  if (input.source == AbilitySource.unknown) {
    reason = AbilityUnknownReason.sourceUnknown;
  } else if (mean == null) {
    reason = AbilityUnknownReason.noMean;
  } else if (input.source.isMeasured) {
    if (input.nObs < policy.minObservations) {
      reason = AbilityUnknownReason.tooFewObservations;
    } else if (interval == null) {
      reason = AbilityUnknownReason.missingUncertainty;
    } else if (interval.width > policy.maxIntervalWidth) {
      reason = AbilityUnknownReason.uncertainInterval;
    } else {
      band = thresholds.bandFor(mean);
    }
  } else {
    // preset：设计先验可以给档，但它永远不是实测档。
    band = thresholds.bandFor(mean);
  }

  return AbilityBandReading(
    band: band,
    source: input.source,
    unknownReason: reason,
    nObs: input.nObs,
    mean: mean,
    interval: interval,
    thresholds: thresholds,
    calibrated: policy.calibrated,
  );
}

const double _z95 = 1.959964;

/// 调用方给了区间就用它（优先 95%）；否则用 sd 换算 95% 正态区间。
AbilityInterval? _effectiveInterval(AbilityBandInput input) {
  final given = input.interval;
  if (given != null) return given;
  final mean = input.mean;
  final sd = input.sd;
  if (mean == null || sd == null) return null;
  return AbilityInterval(
    lo: mean - _z95 * sd,
    hi: mean + _z95 * sd,
  );
}

void _validateInput(AbilityBandInput input) {
  if (input.nObs < 0) {
    throw ArgumentError.value(input.nObs, 'nObs', '观测数不能为负');
  }
  final mean = input.mean;
  if (mean != null && !mean.isFinite) {
    throw ArgumentError.value(mean, 'mean', '均值必须是有限数');
  }
  final sd = input.sd;
  if (sd != null && (!sd.isFinite || sd < 0)) {
    throw ArgumentError.value(sd, 'sd', '标准差必须是有限非负数');
  }
  final interval = input.interval;
  if (interval != null) {
    if (!interval.lo.isFinite || !interval.hi.isFinite) {
      throw ArgumentError.value(interval.toJson(), 'interval', '区间端点必须是有限数');
    }
    if (interval.lo > interval.hi) {
      throw ArgumentError.value(interval.toJson(), 'interval', '区间下界不能大于上界');
    }
    if (!(interval.level > 0 && interval.level < 1)) {
      throw ArgumentError.value(interval.level, 'interval.level', '区间可信度必须在 0–1 之间');
    }
  }
}

void _validatePolicy(AbilityBandPolicy policy) {
  if (policy.minObservations < 1) {
    throw ArgumentError.value(
      policy.minObservations,
      'policy.minObservations',
      '最低观测数必须 ≥1',
    );
  }
  if (!policy.maxIntervalWidth.isFinite || policy.maxIntervalWidth <= 0) {
    throw ArgumentError.value(
      policy.maxIntervalWidth,
      'policy.maxIntervalWidth',
      '区间宽度上限必须是有限正数',
    );
  }
  final thresholds = policy.thresholds;
  final values = <double>[
    thresholds.s,
    thresholds.a,
    thresholds.b,
    thresholds.c,
  ];
  for (final value in values) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'thresholds', '阈值必须是有限数');
    }
  }
  if (!(thresholds.s > thresholds.a &&
      thresholds.a > thresholds.b &&
      thresholds.b > thresholds.c)) {
    throw ArgumentError.value(
      thresholds.toJson(),
      'thresholds',
      '阈值必须严格递减：s > a > b > c',
    );
  }
}

Map<String, Object?> _mapOf(Object? value) {
  if (value is! Map) return const <String, Object?>{};
  return <String, Object?>{
    for (final entry in value.entries) '${entry.key}': entry.value,
  };
}

String? _stringOf(Object? value) => value is String ? value : null;

double? _doubleOf(Object? value) => value is num ? value.toDouble() : null;

int _intOf(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}

/// 读矩阵 knowledge 行的区间：UI 投影是 level→[lo, hi] 映射，完整矩阵是
/// `[{lo, hi, level}]` 列表；取可信度最高（最宽）的那条，没有则 null。
AbilityInterval? _intervalOf(Object? raw) {
  if (raw is List) {
    AbilityInterval? best;
    for (final item in raw) {
      final map = _mapOf(item);
      final lo = _doubleOf(map['lo']);
      final hi = _doubleOf(map['hi']);
      if (lo == null || hi == null) continue;
      final interval = AbilityInterval(
        lo: lo,
        hi: hi,
        level: _doubleOf(map['level']) ?? 0.95,
      );
      if (best == null || interval.level > best.level) best = interval;
    }
    return best;
  }
  final map = _mapOf(raw);
  for (final level in const <String>['95', '80']) {
    final pair = map[level];
    if (pair is! List || pair.length < 2) continue;
    final lo = _doubleOf(pair[0]);
    final hi = _doubleOf(pair[1]);
    if (lo == null || hi == null) continue;
    return AbilityInterval(
      lo: lo,
      hi: hi,
      level: double.parse(level) / 100,
    );
  }
  return null;
}

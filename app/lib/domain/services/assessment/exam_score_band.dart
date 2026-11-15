/// 高考分数档：把「某一科的高考卷面总分」折算成 S+/S/A/B/C/D。
///
/// 用户 2026-11-15 确认的口径（task-63）：
///
/// * 每科满分：数学/英语/语文 150，物理/化学/生物 100；
/// * S+：绝对正确 / 思路绝对清晰的**参考档**，暂定「满分」为数值门槛，可配置；
/// * S/A/B/C/D 按每科阈值分档，边界闭区间（`>=`）；
/// * D = 低于 C；
/// * 越界 / 非法分数直接抛 [ArgumentError]，不静默降级成一档。
///
/// 三条纪律（写死在代码里）：
///
/// * **这是内部评判，不是能力后验**。高考分数档只描述「一次卷面分落在哪档」，
///   不是 `ability-matrix` 的能力测量，也不是对学生能力的预测；两者在本
///   domain 里没有任何耦合。
/// * **不向用户输出预测分数**。对外的 [ExamScoreBandReading.display] 只输出档位
///   字（`S+`/`S`/`A`/`B`/`C`/`D`），不输出分数、百分比或「高考能考多少」的映射；
///   [ExamScoreBandReading.toJson] 默认也不包含原始分数（内部日志需要时显式
///   传 `includeScore: true`）。本文件不接 UI。
/// * **阈值未校准**。[ExamScoreThresholds] 的默认值是用户确认的任务口径，
///   但没有在本机数据上做过标定；[ExamScoreBandPolicy.calibrated] 默认 false，
///   标定后只改 policy，不要把阈值散落到其它层。
///
/// 纯逻辑：不读时钟、不随机、不读写数据库、不 import Flutter；同一输入永远
/// 同一输出。
///
/// 英语/语文作文的临时分**不在本 domain**：这里只接收卷面总分；作文分是内部
/// 临时口径（后续打磨、不写进 UI），由上游评分流程负责，不能在这里反推。
library;

/// 六科，以及每科的高考满分。
enum ExamSubject {
  math('math', '数学', 150),
  english('english', '英语', 150),
  chinese('chinese', '语文', 150),
  physics('physics', '物理', 100),
  chemistry('chemistry', '化学', 100),
  biology('biology', '生物', 100);

  const ExamSubject(this.code, this.labelZh, this.fullScore);

  /// 稳定编码：`math` / `english` / `chinese` / `physics` / `chemistry` / `biology`。
  final String code;

  /// 中文名（日志/报告用，不进 UI 文案体系）。
  final String labelZh;

  /// 该科高考卷面满分。
  final int fullScore;

  /// 由编码找学科；认不出返回 null（不猜）。
  static ExamSubject? tryFromCode(String? code) {
    final normalized = (code ?? '').trim().toLowerCase();
    for (final subject in ExamSubject.values) {
      if (subject.code == normalized) return subject;
    }
    return null;
  }
}

/// 分数档。`S+` 是参考档（默认满分门槛），不是「比 S 更高的一次测量」。
enum ExamScoreBand {
  sPlus('S+'),
  s('S'),
  a('A'),
  b('B'),
  c('C'),
  d('D');

  const ExamScoreBand(this.label);

  /// 用户可见的档位字：`S+` / `S` / `A` / `B` / `C` / `D`。
  final String label;

  /// 是否是 S+ 参考档。
  bool get isReference => this == ExamScoreBand.sPlus;

  /// 是否落在「低于 C」的最低档（D）。
  bool get isBelowC => this == ExamScoreBand.d;
}

/// S+ 的口径。
enum ExamSPlusMode {
  /// 按分数派生：`score >= sPlus` 就是 S+；默认 `sPlus == 该科满分`，
  /// 也可以在阈值里调低（例如 148）。
  derived('derived'),

  /// S+ 只是参考档，不从分数派生：满分落在 S，任何分数都不会得到 S+。
  onlyReference('only_reference');

  const ExamSPlusMode(this.code);

  /// 稳定编码。
  final String code;
}

/// 一科的分档阈值（全部为该科卷面分，单位与满分一致）。
///
/// 边界闭区间：`score == s` 就是 S（不是 A）；`score == c` 就是 C（不是 D）。
class ExamScoreThresholds {
  const ExamScoreThresholds({
    required this.subject,
    required this.sPlus,
    required this.s,
    required this.a,
    required this.b,
    required this.c,
  });

  final ExamSubject subject;

  /// `score >= sPlus` → S+（仅 [ExamSPlusMode.derived] 生效；默认等于满分）。
  final double sPlus;

  /// `score >= s` → S。
  final double s;

  /// `score >= a` → A。
  final double a;

  /// `score >= b` → B。
  final double b;

  /// `score >= c` → C；否则 D。
  final double c;

  /// 该科满分（来自 [ExamSubject.fullScore]）。
  double get fullScore => subject.fullScore.toDouble();

  // 用户确认的每科阈值（task-63）。S+ 暂定满分，但单独给出数值，便于配置。
  static const ExamScoreThresholds math = ExamScoreThresholds(
    subject: ExamSubject.math,
    sPlus: 150,
    s: 145,
    a: 135,
    b: 125,
    c: 110,
  );

  static const ExamScoreThresholds english = ExamScoreThresholds(
    subject: ExamSubject.english,
    sPlus: 150,
    s: 140,
    a: 130,
    b: 120,
    c: 110,
  );

  static const ExamScoreThresholds chinese = ExamScoreThresholds(
    subject: ExamSubject.chinese,
    sPlus: 150,
    s: 130,
    a: 115,
    b: 110,
    c: 100,
  );

  static const ExamScoreThresholds physics = ExamScoreThresholds(
    subject: ExamSubject.physics,
    sPlus: 100,
    s: 96,
    a: 86,
    b: 75,
    c: 60,
  );

  static const ExamScoreThresholds chemistry = ExamScoreThresholds(
    subject: ExamSubject.chemistry,
    sPlus: 100,
    s: 94,
    a: 86,
    b: 75,
    c: 60,
  );

  static const ExamScoreThresholds biology = ExamScoreThresholds(
    subject: ExamSubject.biology,
    sPlus: 100,
    s: 94,
    a: 86,
    b: 75,
    c: 60,
  );

  /// 六科默认阈值的完整表（[ExamScoreBandPolicy.gaokao] 的默认值）。
  static const Map<ExamSubject, ExamScoreThresholds> gaokaoDefaults =
      <ExamSubject, ExamScoreThresholds>{
    ExamSubject.math: math,
    ExamSubject.english: english,
    ExamSubject.chinese: chinese,
    ExamSubject.physics: physics,
    ExamSubject.chemistry: chemistry,
    ExamSubject.biology: biology,
  };

  /// 按阈值落档。`score` 必须已经过调用方校验（在 0…满分之间、有限）。
  ExamScoreBand bandFor(double score, {required ExamSPlusMode sPlusMode}) {
    if (sPlusMode == ExamSPlusMode.derived && score >= sPlus) {
      return ExamScoreBand.sPlus;
    }
    if (score >= s) return ExamScoreBand.s;
    if (score >= a) return ExamScoreBand.a;
    if (score >= b) return ExamScoreBand.b;
    if (score >= c) return ExamScoreBand.c;
    return ExamScoreBand.d;
  }

  /// 序列化（阈值本身；不含任何学生数据）。
  Map<String, Object?> toJson() => <String, Object?>{
        'subject': subject.code,
        'full_score': fullScore,
        's_plus': sPlus,
        's': s,
        'a': a,
        'b': b,
        'c': c,
      };
}

/// 分档策略：六科阈值 + S+ 口径 + 是否已校准。整体可替换。
class ExamScoreBandPolicy {
  const ExamScoreBandPolicy({
    this.thresholds = ExamScoreThresholds.gaokaoDefaults,
    this.sPlusMode = ExamSPlusMode.derived,
    this.calibrated = false,
  });

  /// 学科 → 阈值。默认是用户确认的六科表；替换时需自担「六科齐全」。
  final Map<ExamSubject, ExamScoreThresholds> thresholds;

  /// S+ 口径：默认满分门槛的派生档；[ExamSPlusMode.onlyReference] 时 S+ 仅参考。
  final ExamSPlusMode sPlusMode;

  /// 这组阈值是否已在真实数据上标定。当前默认 false（就是未标定）。
  final bool calibrated;

  /// 用户确认的默认策略：S+ = 满分，六科阈值按 task-63 表。
  static const ExamScoreBandPolicy gaokao = ExamScoreBandPolicy();

  /// 同一套六科阈值，但 S+ 只作参考档：满分落在 S，不输出 S+。
  static const ExamScoreBandPolicy gaokaoReferenceSPlus = ExamScoreBandPolicy(
    sPlusMode: ExamSPlusMode.onlyReference,
  );

  /// 取某科阈值（校验存在 / subject 与键一致 / 数值合法）。
  ExamScoreThresholds thresholdsFor(ExamSubject subject) {
    final value = thresholds[subject];
    if (value == null) {
      throw ArgumentError.value(
        subject.code,
        'thresholds',
        '缺少 ${subject.code} 的阈值配置',
      );
    }
    if (value.subject != subject) {
      throw ArgumentError.value(
        value.toJson(),
        'thresholds',
        '阈值配置的 subject（${value.subject.code}）与键（${subject.code}）不一致',
      );
    }
    _validateThresholds(value);
    return value;
  }

  /// 输入学科 + 分数，返回档位。非法分数抛 [ArgumentError]。
  ExamScoreBand bandFor(ExamSubject subject, num score) {
    final resolved = thresholdsFor(subject);
    final value = _validatedScore(resolved, score);
    return resolved.bandFor(value, sPlusMode: sPlusMode);
  }

  /// 返回替换了单科阈值的新策略（不改原对象）。
  ExamScoreBandPolicy replaceThreshold(ExamScoreThresholds replacement) {
    final merged = <ExamSubject, ExamScoreThresholds>{
      ...thresholds,
      replacement.subject: replacement,
    };
    return ExamScoreBandPolicy(
      thresholds: Map<ExamSubject, ExamScoreThresholds>.unmodifiable(merged),
      sPlusMode: sPlusMode,
      calibrated: calibrated,
    );
  }

  /// 浅拷贝。
  ExamScoreBandPolicy copyWith({
    Map<ExamSubject, ExamScoreThresholds>? thresholds,
    ExamSPlusMode? sPlusMode,
    bool? calibrated,
  }) {
    return ExamScoreBandPolicy(
      thresholds: thresholds ?? this.thresholds,
      sPlusMode: sPlusMode ?? this.sPlusMode,
      calibrated: calibrated ?? this.calibrated,
    );
  }
}

/// 一次分档读数。
class ExamScoreBandReading {
  const ExamScoreBandReading({
    required this.subject,
    required this.score,
    required this.band,
    required this.thresholds,
    required this.sPlusMode,
    required this.calibrated,
  });

  final ExamSubject subject;

  /// 内部使用的卷面分；不要在 UI 上展示（见文件头纪律）。
  final double score;

  final ExamScoreBand band;
  final ExamScoreThresholds thresholds;
  final ExamSPlusMode sPlusMode;

  /// 阈值是否已标定（当前默认 false）。
  final bool calibrated;

  /// 是否是 S+ 参考档。
  bool get isSPlus => band == ExamScoreBand.sPlus;

  /// S+ 是否只是参考口径（[ExamSPlusMode.onlyReference]）。
  bool get isSPlusReferenceOnly =>
      sPlusMode == ExamSPlusMode.onlyReference;

  /// 是否落在最低档 D（低于 C）。
  bool get isBelowC => band == ExamScoreBand.d;

  /// 对外显示串：只有档位字，绝不含分数 / 百分比 / 预测分。
  String get display => band.label;

  /// 序列化。默认**不含**原始分数；内部日志确实需要时才显式
  /// `includeScore: true`。UI 层不得读取 `score`。
  Map<String, Object?> toJson({bool includeScore = false}) => <String, Object?>{
        'subject': subject.code,
        'band': band.name,
        'band_label': band.label,
        's_plus_mode': sPlusMode.code,
        'calibrated': calibrated,
        if (includeScore) 'score': score,
      };
}

/// 输入学科 + 分数，返回完整读数（档位 + 命中的阈值 + S+ 口径）。
///
/// * 非法分数（负数、超满分、NaN、无穷）抛 [ArgumentError]；
/// * 缺阈值 / subject 与键不一致 / 阈值不递减等配置错误同样抛
///   [ArgumentError]：这些是调用方 bug，不能静默降级成某一档。
ExamScoreBandReading readExamScoreBand({
  required ExamSubject subject,
  required num score,
  ExamScoreBandPolicy policy = ExamScoreBandPolicy.gaokao,
}) {
  final resolved = policy.thresholdsFor(subject);
  final value = _validatedScore(resolved, score);
  final band = resolved.bandFor(value, sPlusMode: policy.sPlusMode);
  return ExamScoreBandReading(
    subject: subject,
    score: value,
    band: band,
    thresholds: resolved,
    sPlusMode: policy.sPlusMode,
    calibrated: policy.calibrated,
  );
}

/// 校验一科阈值：有限、严格递减、S+ 不超过满分、C 下界非负。
void _validateThresholds(ExamScoreThresholds thresholds) {
  final values = <double>[
    thresholds.sPlus,
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
  if (!(thresholds.sPlus > thresholds.s &&
      thresholds.s > thresholds.a &&
      thresholds.a > thresholds.b &&
      thresholds.b > thresholds.c)) {
    throw ArgumentError.value(
      thresholds.toJson(),
      'thresholds',
      '阈值必须严格递减：sPlus > s > a > b > c',
    );
  }
  if (thresholds.sPlus > thresholds.fullScore) {
    throw ArgumentError.value(
      thresholds.toJson(),
      'thresholds',
      'S+ 门槛不能高于该科满分 ${thresholds.fullScore}',
    );
  }
  if (thresholds.c < 0) {
    throw ArgumentError.value(
      thresholds.c,
      'thresholds.c',
      'C 的下界不能为负',
    );
  }
}

/// 校验分数：有限、0…满分。越界/非法一律抛 [ArgumentError]。
double _validatedScore(ExamScoreThresholds thresholds, num score) {
  final value = score.toDouble();
  if (!value.isFinite) {
    throw ArgumentError.value(score, 'score', '分数必须是有限数（拒绝 NaN / 无穷）');
  }
  if (value < 0) {
    throw ArgumentError.value(score, 'score', '分数不能为负');
  }
  if (value > thresholds.fullScore) {
    throw ArgumentError.value(
      score,
      'score',
      '分数不能超过该科满分 ${thresholds.fullScore}',
    );
  }
  return value;
}

/// 能力趋势的领域层纯逻辑：把「最近 N 次能力测量」整理成可直接画趋势小图的数据。
///
/// 设计来源：`docs/REVIEW_FEEDBACK.md` §8（能力测评，:241-248）的后续——能力画像页
/// 目前只显示最近一次分数，趋势小图需要「旧 → 新」的序列、方向与归一化坐标。本文件
/// 只整理数据：不读写数据库、不 import Flutter / drift；仓储读数与页面由上层接。
///
/// 口径：
///
/// * 输入顺序不可信：构造时按 `capturedAt` 稳定升序排序（同一时刻保持传入顺序）；
/// * `kAbilityTrendFlatEpsilon` 是「算平」阈值：`|delta| < 2.0` → flat，恰为 2.0 算有方向；
/// * 序列最多保留 `kAbilityTrendMaxPoints` 个点，超出时只留最新的；
/// * 单点时 `delta` 为 0.0（没有变化）、方向 flat；
/// * 归一化坐标都夹到 0–1，方便直接画点；不读时钟、不随机、同一输入永远同一输出。
library;

/// 「算平」的分数差阈值：`|delta| < epsilon` 视为持平。
const double kAbilityTrendFlatEpsilon = 2.0;

/// 趋势最多保留的点数（超出时只保留最新的点）。
const int kAbilityTrendMaxPoints = 30;

/// 趋势方向：变好 / 持平 / 变差。
enum AbilityTrendDirection {
  /// 最新分明显高于最早分（`delta > kAbilityTrendFlatEpsilon`）。
  improving,

  /// 没有变化，或变化幅度小于 `kAbilityTrendFlatEpsilon`。
  flat,

  /// 最新分明显低于最早分（`delta < -kAbilityTrendFlatEpsilon`）。
  declining,
}

/// 一次能力测量在趋势里的一个点。
class AbilityTrendPoint {
  /// 用采集时间与分数构造一个点。
  const AbilityTrendPoint({required this.capturedAt, required this.score});

  /// 采集时间（排序与新旧判定只看这个字段）。
  final DateTime capturedAt;

  /// 该次测量的分数（上层 `ability_scores` 是 0–100；这里原样保存，不校验以免丢数据）。
  final double score;
}

/// 一条能力趋势：`points` 恒为旧 → 新。
class AbilityTrendSeries {
  /// 用任意顺序的点构造；内部按 `capturedAt` 稳定升序排序并做不可变包装。
  AbilityTrendSeries(List<AbilityTrendPoint> points)
      : points = List<AbilityTrendPoint>.unmodifiable(_stableAscending(points));

  /// 从仓储读数（新 → 旧）构造：反转成旧 → 新后只保留最新 `max` 个点。
  factory AbilityTrendSeries.fromNewestFirst(
    List<AbilityTrendPoint> newestFirst, {
    int max = kAbilityTrendMaxPoints,
  }) =>
      AbilityTrendSeries(newestFirst.reversed.toList()).capped(max: max);

  /// 空趋势（没有任何测量）。
  static final AbilityTrendSeries empty =
      AbilityTrendSeries(const <AbilityTrendPoint>[]);

  /// 旧 → 新的点列（不可修改）。
  final List<AbilityTrendPoint> points;

  /// 是否没有点。
  bool get isEmpty => points.isEmpty;

  /// 是否至少有一个点。
  bool get isNotEmpty => points.isNotEmpty;

  /// 点数。
  int get length => points.length;

  /// 最早（最旧）的一个点；空序列为 null。
  AbilityTrendPoint? get earliest => points.isEmpty ? null : points.first;

  /// 最新（最后一个）的一个点；空序列为 null。
  AbilityTrendPoint? get latest => points.isEmpty ? null : points.last;

  /// 最早一次的分数；空序列为 null。
  double? get earliestScore => earliest?.score;

  /// 最近一次的分数；空序列为 null。
  double? get latestScore => latest?.score;

  /// 最新分减最早分；空序列为 null，单点为 0.0。
  double? get delta {
    if (points.isEmpty) return null;
    return points.last.score - points.first.score;
  }

  /// 所有点的平均分；空序列为 null。
  double? get averageScore {
    if (points.isEmpty) return null;
    var sum = 0.0;
    for (final point in points) {
      sum += point.score;
    }
    return sum / points.length;
  }

  /// 最高的一次分数；空序列为 null。
  double? get bestScore {
    if (points.isEmpty) return null;
    var best = points.first.score;
    for (final point in points) {
      if (point.score > best) best = point.score;
    }
    return best;
  }

  /// 最低的一次分数；空序列为 null。
  double? get worstScore {
    if (points.isEmpty) return null;
    var worst = points.first.score;
    for (final point in points) {
      if (point.score < worst) worst = point.score;
    }
    return worst;
  }

  /// 方向：空 / 单点 / 变化小于阈值 → flat；否则按 delta 正负。
  AbilityTrendDirection get direction {
    if (points.length < 2) return AbilityTrendDirection.flat;
    final change = delta!;
    if (change.abs() < kAbilityTrendFlatEpsilon) {
      return AbilityTrendDirection.flat;
    }
    if (change > 0) return AbilityTrendDirection.improving;
    if (change < 0) return AbilityTrendDirection.declining;
    // NaN 等不可比较的差按持平处理，避免误报方向。
    return AbilityTrendDirection.flat;
  }

  /// 最近一次分数换算成 0–1（`latestScore / 100` 夹到 0–1）；空序列为 null。
  double? get progress01 {
    if (points.isEmpty) return null;
    return _clamp01(points.last.score / 100);
  }

  /// 每个分数换算成 0–1，顺序与 `points` 一致。
  List<double> get normalizedScores => List<double>.unmodifiable(
        points.map((point) => _clamp01(point.score / 100)),
      );

  /// 均匀分布的横向位置：单点 [0]；n≥2 时 `i/(n-1)`（首 0、末 1）。
  List<double> get normalizedPositions {
    final count = points.length;
    if (count == 0) return const <double>[];
    if (count == 1) return const <double>[0.0];
    return List<double>.unmodifiable(
      List<double>.generate(count, (index) => index / (count - 1)),
    );
  }

  /// 只保留最后 `max` 个点（即最新的）；`max <= 0` 返回空序列。
  AbilityTrendSeries capped({int max = kAbilityTrendMaxPoints}) {
    if (max <= 0) return empty;
    if (points.length <= max) return this;
    return AbilityTrendSeries(points.sublist(points.length - max));
  }
}

/// 按 `capturedAt` 稳定升序排序：同一时刻保持传入顺序（下标兜底）。
List<AbilityTrendPoint> _stableAscending(List<AbilityTrendPoint> input) {
  final indices = List<int>.generate(input.length, (index) => index);
  indices.sort((a, b) {
    final byTime = input[a].capturedAt.compareTo(input[b].capturedAt);
    if (byTime != 0) return byTime;
    return a.compareTo(b);
  });
  return <AbilityTrendPoint>[for (final index in indices) input[index]];
}

/// 夹到 0–1；NaN 按 0 处理（画图时不能出现 NaN 坐标）。
double _clamp01(double value) {
  if (value.isNaN) return 0.0;
  return value.clamp(0.0, 1.0).toDouble();
}

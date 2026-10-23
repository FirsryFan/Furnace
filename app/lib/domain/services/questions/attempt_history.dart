/// 作答历史的只读派生视图：把落库的多条自测作答行聚合成「做过几次、对几次、
/// 最近一次何时对错」。
///
/// 本文件是纯领域逻辑：不 import Flutter / Drift，不读库、不写库、不产生副作用。
/// 调用方负责按题取数（例如按 questionId 查出该题的所有作答行），再交给
/// [QuestionAttemptHistory.fromEntries] 聚合；这里不会按 questionId 过滤或分组。
library;

/// 一次自测作答的只读快照（领域层不依赖 Drift 行）。
class QuestionAttemptEntry {
  const QuestionAttemptEntry({
    required this.id,
    required this.questionId,
    required this.isCorrect,
    required this.attemptedAt,
  });

  /// 行 id，仅用于同一毫秒内的确定性排序；不要求唯一。
  final String id;

  /// 题目 id。本类只做统计，不按它过滤，也不因出现多题而报错。
  final String questionId;

  /// 这次作答是否判对（原样保留，不做归一化或改写）。
  final bool isCorrect;

  /// 作答时间。排序比较的是绝对时刻，UTC 与本地时间可以混合传入。
  final DateTime attemptedAt;
}

/// 一道题的作答历史（纯派生视图，不落库）。
///
/// 构造时把输入复制一份并按「新→旧」排好：
/// 1. [QuestionAttemptEntry.attemptedAt] 降序（越晚越靠前）；
/// 2. 同一毫秒按 [QuestionAttemptEntry.id] 升序（tie-break，保证确定性）。
///
/// [entries] 是不可修改列表；重复 id 的条目照收，不去重。
class QuestionAttemptHistory {
  /// 私有构造：调用方请用 [QuestionAttemptHistory.fromEntries]。
  QuestionAttemptHistory._(this.entries);

  /// 从落库行构造历史视图；不修改传入的 [entries]，不抛异常。
  factory QuestionAttemptHistory.fromEntries(
    Iterable<QuestionAttemptEntry> entries,
  ) {
    final sorted = entries.toList(growable: false)..sort(_compareNewestFirst);
    return QuestionAttemptHistory._(
      List<QuestionAttemptEntry>.unmodifiable(sorted),
    );
  }

  /// 按「新→旧」排好的作答记录（不可修改）。
  final List<QuestionAttemptEntry> entries;

  /// 没有任何作答记录。
  bool get isEmpty => entries.isEmpty;

  /// 作答总次数（重复 id 的条目分别计数）。
  int get total => entries.length;

  /// 判对的次数。
  int get correct => entries.where((entry) => entry.isCorrect).length;

  /// 判错的次数（[total] - [correct]）。
  int get incorrect => total - correct;

  /// 最新一条作答；没有记录时为 null。
  QuestionAttemptEntry? get latest => isEmpty ? null : entries.first;

  /// 最新一条作答是否判对；没有记录时返回 false（调用方先用 [isEmpty] 判断）。
  bool get latestIsCorrect => latest?.isCorrect ?? false;
}

/// 新→旧：时间降序；同一时刻按 id 升序。
int _compareNewestFirst(QuestionAttemptEntry a, QuestionAttemptEntry b) {
  final byTime = b.attemptedAt.compareTo(a.attemptedAt);
  if (byTime != 0) {
    return byTime;
  }
  return a.id.compareTo(b.id);
}

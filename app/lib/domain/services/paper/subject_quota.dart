/// 组卷的**按学科配额**：每科最多几道、至少几道。
///
/// 为什么单独一个值对象，而不是往 PaperSpec 里平铺两个 Map：配额由「上限」
/// 「下限」两张表组成，两张表都是「学科 key → 整数」；当成一个值传递，
/// PaperSpec 只多一个可选字段，默认 null = 不启用（历史行为逐字节不变）。
///
/// 规则（确定性、可解释）：
/// * 学科键 = PaperCandidate.subjectKey.trim()；两张表的键在解析时同样 trim。
/// * 没在两张表里出现的学科**不限**（不设上限、不设保底）。
/// * 上限 0 = 这个学科一道都不选；下限用于「跨学科组卷时每科至少来一道」。
/// * 同科 min > max 时**保底优先**：上限抬到 min（保底不能被上限抹掉）。
/// * 负值、trim 后为空的学科键、trim 后撞车的重复键 → ArgumentError：
///   这些是配置错误，不能静默当成「不限」。
///
/// 纯逻辑：不读库、不 import Flutter、不 import drift。
library;

/// 一张按学科配额表（PaperSpec 的可选参数；默认不启用）。
class SubjectQuota {
  const SubjectQuota({
    this.maxPerSubject = const {},
    this.minPerSubject = const {},
  });

  /// 学科 key → 最多几道；没出现的学科不限。
  final Map<String, int> maxPerSubject;

  /// 学科 key → 至少几道；没出现的学科不设保底。
  final Map<String, int> minPerSubject;

  /// 两张表都空 = 不启用（与传 null 等价）。
  bool get isEnabled => maxPerSubject.isNotEmpty || minPerSubject.isNotEmpty;

  /// 校验并归一化：trim 学科键、按 key 排序、应用「保底优先于上限」。
  SubjectQuotaResolved resolve() {
    final max = _normalize(maxPerSubject, label: 'maxPerSubject');
    final min = _normalize(minPerSubject, label: 'minPerSubject');
    final keys = <String>{...max.keys, ...min.keys}.toList()..sort();
    final effectiveMax = <String, int>{};
    for (final key in keys) {
      final maximum = max[key];
      final minimum = min[key];
      if (maximum != null && minimum != null && minimum > maximum) {
        effectiveMax[key] = minimum;
      } else if (maximum != null) {
        effectiveMax[key] = maximum;
      }
    }
    return SubjectQuotaResolved(
      maxPerSubject: Map.unmodifiable(effectiveMax),
      minPerSubject: Map.unmodifiable(min),
    );
  }

  static Map<String, int> _normalize(
    Map<String, int> source, {
    required String label,
  }) {
    final result = <String, int>{};
    for (final entry in source.entries) {
      final key = entry.key.trim();
      if (key.isEmpty) {
        throw ArgumentError.value(entry.key, label, '学科键不能为空白');
      }
      if (entry.value < 0) {
        throw ArgumentError.value(entry.value, label, '学科「$key」的配额不能为负数');
      }
      if (result.containsKey(key)) {
        throw ArgumentError.value(entry.key, label, '学科键 trim 后重复（已有「$key」）');
      }
      result[key] = entry.value;
    }
    final sorted = result.keys.toList()..sort();
    return {for (final key in sorted) key: result[key]!};
  }

  @override
  String toString() =>
      'SubjectQuota(maxPerSubject: $maxPerSubject, minPerSubject: $minPerSubject)';
}

/// SubjectQuota.resolve 的结果：已校验、已 trim、已排序、已应用保底优先。
class SubjectQuotaResolved {
  const SubjectQuotaResolved({
    required this.maxPerSubject,
    required this.minPerSubject,
  });

  /// 生效上限（同科 min > max 时已经抬到 min）；没出现的学科不限。
  final Map<String, int> maxPerSubject;

  /// 生效保底；没出现的学科不设保底。
  final Map<String, int> minPerSubject;

  bool get isEnabled => maxPerSubject.isNotEmpty || minPerSubject.isNotEmpty;

  /// 某学科上限；null = 不限。
  int? maxFor(String subjectKey) => maxPerSubject[subjectKey.trim()];

  /// 某学科保底；没配置时返回 0。
  int minFor(String subjectKey) => minPerSubject[subjectKey.trim()] ?? 0;

  /// PaperPlan.toJson 的 subject_quota 回显（键已排序）。
  Map<String, Object?> toJson() => {
        'max_per_subject': maxPerSubject,
        'min_per_subject': minPerSubject,
      };

  @override
  bool operator ==(Object other) =>
      other is SubjectQuotaResolved &&
      _mapEquals(maxPerSubject, other.maxPerSubject) &&
      _mapEquals(minPerSubject, other.minPerSubject);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(
            maxPerSubject.entries.map((e) => Object.hash(e.key, e.value))),
        Object.hashAll(
            minPerSubject.entries.map((e) => Object.hash(e.key, e.value))),
      );

  @override
  String toString() =>
      'SubjectQuotaResolved(maxPerSubject: $maxPerSubject, minPerSubject: $minPerSubject)';
}

bool _mapEquals(Map<String, int> a, Map<String, int> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

/// 一道本来能进卷、却被学科上限挡下的候选（不静默丢题：如实进
/// PaperPlan.quotaBlockedQuestions）。
///
/// 只在「还有空位」的扫描阶段记录：卷子已经凑满之后剩的候选属于「没排上」，
/// 不是「被配额挡下」。
class QuotaBlockedQuestion {
  const QuotaBlockedQuestion({
    required this.questionId,
    required this.subjectKey,
    required this.subjectLimit,
  });

  final String questionId;

  /// 已 trim 的学科键（与 SubjectQuota 的键空间一致）。
  final String subjectKey;

  /// 生效的学科上限（maxPerSubject[subjectKey]）。
  final int subjectLimit;

  Map<String, Object?> toJson() => {
        'question_id': questionId,
        'subject_key': subjectKey,
        'subject_limit': subjectLimit,
      };
}

/// 一个没达到保底的学科（如实报缺口；不自动编题、不静默丢）。
class SubjectQuotaShortfall {
  const SubjectQuotaShortfall({
    required this.subjectKey,
    required this.minimumCount,
    required this.selectedCount,
    required this.availableCount,
  });

  final String subjectKey;

  /// 配置的保底。
  final int minimumCount;

  /// 实际排进卷子的数量。
  final int selectedCount;

  /// 过了过滤、进入打分阶段的候选数量（0 = 题库里这科压根没有可用题）。
  final int availableCount;

  /// 题库里这科一道候选都没有（缺口在「收题」，不是配额问题）。
  bool get isUncovered => availableCount == 0;

  Map<String, Object?> toJson() => {
        'subject_key': subjectKey,
        'minimum_count': minimumCount,
        'selected_count': selectedCount,
        'available_count': availableCount,
        'is_uncovered': isUncovered,
      };
}

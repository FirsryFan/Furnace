/// 组卷的**按领域配额**：每个顶级领域最多几道、至少几道。
///
/// 与 [SubjectQuota]（按 `subjectKey` 配额）是同一层思路的两套键：领域配额按
/// 「顶级标签」分组，回答的是「数学/物理/语文各来几道」；学科配额按题目行上的
/// `subjectKey`。两者都启用时次序见 `PaperComposer.compose` 的文档与
/// `docs/PAPER_COMPOSER_DESIGN.md` §14。
///
/// 配置规则（与 [SubjectQuota] 同口径，确定性、可解释）：
/// * 领域键 = 标签路径的第一段（`顶级/二级/...` 的第一段）；键在解析时 trim。
/// * 没在两张表里出现的领域**不限**（不设上限、不设保底）。
/// * 上限 0 = 这个领域一道都不选；下限用于「每个领域至少来一道」。
/// * 同域 min > max 时**保底优先**：上限抬到 min（保底不能被上限抹掉）。
/// * 负值、trim 后为空的领域键、trim 后撞车的重复键 → ArgumentError：
///   这些是配置错误，不能静默当成「不限」。
///
/// 纯逻辑：不读库、不 import Flutter、不 import drift。
library;

/// 一张按领域配额表（`PaperSpec.domainQuota` 的可选参数；默认不启用）。
class DomainQuota {
  const DomainQuota({
    this.maxPerDomain = const {},
    this.minPerDomain = const {},
  });

  /// 领域键 → 最多几道；没出现的领域不限。
  final Map<String, int> maxPerDomain;

  /// 领域键 → 至少几道；没出现的领域不设保底。
  final Map<String, int> minPerDomain;

  /// 两张表都空 = 不启用（与传 null 等价）。
  bool get isEnabled => maxPerDomain.isNotEmpty || minPerDomain.isNotEmpty;

  /// 校验并归一化：trim 领域键、按 key 排序、应用「保底优先于上限」。
  DomainQuotaResolved resolve() {
    final max = _normalize(maxPerDomain, label: 'maxPerDomain');
    final min = _normalize(minPerDomain, label: 'minPerDomain');
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
    return DomainQuotaResolved(
      maxPerDomain: Map.unmodifiable(effectiveMax),
      minPerDomain: Map.unmodifiable(min),
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
        throw ArgumentError.value(entry.key, label, '领域键不能为空白');
      }
      if (entry.value < 0) {
        throw ArgumentError.value(entry.value, label, '领域「$key」的配额不能为负数');
      }
      if (result.containsKey(key)) {
        throw ArgumentError.value(entry.key, label, '领域键 trim 后重复（已有「$key」）');
      }
      result[key] = entry.value;
    }
    final sorted = result.keys.toList()..sort();
    return {for (final key in sorted) key: result[key]!};
  }

  @override
  String toString() =>
      'DomainQuota(maxPerDomain: $maxPerDomain, minPerDomain: $minPerDomain)';
}

/// [DomainQuota.resolve] 的结果：已校验、已 trim、已排序、已应用保底优先。
class DomainQuotaResolved {
  const DomainQuotaResolved({
    required this.maxPerDomain,
    required this.minPerDomain,
  });

  /// 生效上限（同域 min > max 时已经抬到 min）；没出现的领域不限。
  final Map<String, int> maxPerDomain;

  /// 生效保底；没出现的领域不设保底。
  final Map<String, int> minPerDomain;

  bool get isEnabled => maxPerDomain.isNotEmpty || minPerDomain.isNotEmpty;

  /// 某领域上限；null = 不限。
  int? maxFor(String domain) => maxPerDomain[domain.trim()];

  /// 某领域保底；没配置时返回 0。
  int minFor(String domain) => minPerDomain[domain.trim()] ?? 0;

  /// PaperPlan.toJson 的 domain_quota 回显（键已排序）。
  Map<String, Object?> toJson() => {
        'max_per_domain': maxPerDomain,
        'min_per_domain': minPerDomain,
      };

  @override
  bool operator ==(Object other) =>
      other is DomainQuotaResolved &&
      _mapEquals(maxPerDomain, other.maxPerDomain) &&
      _mapEquals(minPerDomain, other.minPerDomain);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(
            maxPerDomain.entries.map((e) => Object.hash(e.key, e.value))),
        Object.hashAll(
            minPerDomain.entries.map((e) => Object.hash(e.key, e.value))),
      );

  @override
  String toString() =>
      'DomainQuotaResolved(maxPerDomain: $maxPerDomain, minPerDomain: $minPerDomain)';
}

bool _mapEquals(Map<String, int> a, Map<String, int> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

/// 一道题落到哪些领域。
///
/// 口径（确定性）：
/// * 领域来自这道题**挂到的知识点**的标签路径：`knowledgePointTagPaths` 的每个值
///   是一条**完整标签路径**（`Tags.path`，形如 `数学/函数/函数单调性`），取第一段非空
///   内容作为领域键；同一个知识点挂多条路径时可能落到多个领域。
/// * 一道题的领域集合 = 它所有知识点领域的**并集**，排序去重。
/// * **主领域** = 排序后的第一个（字典序），用于上限/保底判定；其余进
///   [additionalDomains]，只在回报（`PaperPlan.byDomain`）里出现、不参与判定。
/// * 没挂知识点、或挂到的知识点没有标签路径 → [primaryDomain] 为 null：
///   题目按「无领域」处理，不进领域配额判定，也不出现在 `byDomain` 里。
class QuestionDomains {
  const QuestionDomains({
    this.primaryDomain,
    this.additionalDomains = const [],
  });

  /// 无领域的题。
  static const QuestionDomains none = QuestionDomains();

  /// 主领域（字典序最小）；null = 没有领域。
  final String? primaryDomain;

  /// 附加领域（排序、去重、不含主领域）；只回报，不参与上限/保底判定。
  final List<String> additionalDomains;

  bool get hasDomain => primaryDomain != null;

  /// 主领域在前、附加领域在后的完整列表（排序、去重）。
  List<String> get allDomains => primaryDomain == null
      ? const <String>[]
      : <String>[primaryDomain!, ...additionalDomains];

  Map<String, Object?> toJson() => {
        'primary_domain': primaryDomain,
        'additional_domains': additionalDomains,
      };

  @override
  bool operator ==(Object other) =>
      other is QuestionDomains &&
      other.primaryDomain == primaryDomain &&
      _listEquals(additionalDomains, other.additionalDomains);

  @override
  int get hashCode => Object.hash(
        primaryDomain,
        Object.hashAll(additionalDomains),
      );

  @override
  String toString() =>
      'QuestionDomains(primaryDomain: $primaryDomain, additionalDomains: $additionalDomains)';
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 标签路径 → 领域键的解析器（纯函数，无状态）。
abstract final class DomainQuotaResolver {
  /// 一条标签路径的领域键：按 `/` 切分后的第一个非空段。
  ///
  /// 例：`数学/函数/函数单调性` → `数学`；` 物理 ` → `物理`；空白路径 → null。
  static String? domainOfTagPath(String tagPath) {
    for (final segment in tagPath.split('/')) {
      final trimmed = segment.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  /// 知识点 id → 排序去重的领域列表。
  ///
  /// 输入是 `PaperComposer.compose` 已有的 `knowledgePointTagPaths`：
  /// 值里的**每个元素是一条完整标签路径**（`question_corpus_reader.dart` 从
  /// `Tags.path` 读出）。已经切好的片段列表不要直接传：每一段都会被当成一条路径。
  /// 键会 trim；空键、没有任何可用领域键的知识点不进结果（等价「没有领域」）。
  static Map<String, List<String>> domainsByKnowledgePoint(
    Map<String, List<String>> knowledgePointTagPaths,
  ) {
    final sets = <String, Set<String>>{};
    for (final entry in knowledgePointTagPaths.entries) {
      final knowledgePointId = entry.key.trim();
      if (knowledgePointId.isEmpty) continue;
      final domains = sets[knowledgePointId] ??= <String>{};
      for (final tagPath in entry.value) {
        final domain = domainOfTagPath(tagPath);
        if (domain != null) domains.add(domain);
      }
    }
    final result = <String, List<String>>{};
    final ids = sets.keys.toList()..sort();
    for (final knowledgePointId in ids) {
      final domains = sets[knowledgePointId]!;
      if (domains.isEmpty) continue;
      final sorted = domains.toList()..sort();
      result[knowledgePointId] = List<String>.unmodifiable(sorted);
    }
    return Map<String, List<String>>.unmodifiable(result);
  }

  /// 一道题（一组知识点）的领域归属。
  ///
  /// [domainsByKnowledgePoint] 来自 [domainsByKnowledgePoint]（已归一化）；
  /// 知识点 id 会 trim、去空白；没有任何领域时返回 [QuestionDomains.none]。
  static QuestionDomains questionDomains(
    Map<String, List<String>> domainsByKnowledgePoint,
    Iterable<String> knowledgePointIds,
  ) {
    final domains = <String>{};
    for (final rawId in knowledgePointIds) {
      final knowledgePointId = rawId.trim();
      if (knowledgePointId.isEmpty) continue;
      final pointDomains = domainsByKnowledgePoint[knowledgePointId];
      if (pointDomains != null) domains.addAll(pointDomains);
    }
    if (domains.isEmpty) return QuestionDomains.none;
    final sorted = domains.toList()..sort();
    return QuestionDomains(
      primaryDomain: sorted.first,
      additionalDomains:
          List<String>.unmodifiable(sorted.skip(1).toList(growable: false)),
    );
  }
}

/// 一道本来能进卷、却被领域上限挡下的候选（不静默丢题：如实进
/// `PaperPlan.quotaBlockedByDomain`）。
///
/// 只在「还有空位」的扫描阶段记录：卷子已经凑满之后剩的候选属于「没排上」，
/// 不是「被配额挡下」。判定用的是候选的**主领域**（见 [QuestionDomains]）。
class DomainQuotaBlockedQuestion {
  const DomainQuotaBlockedQuestion({
    required this.questionId,
    required this.domain,
    required this.domainLimit,
  });

  final String questionId;

  /// 已 trim 的主领域键（与 DomainQuota 的键空间一致）。
  final String domain;

  /// 生效的领域上限（maxPerDomain[domain]）。
  final int domainLimit;

  Map<String, Object?> toJson() => {
        'question_id': questionId,
        'domain': domain,
        'domain_limit': domainLimit,
      };
}

/// 一个没达到保底的领域（如实报缺口；不自动编题、不静默丢）。
///
/// 计数口径：`selectedCount` / `availableCount` 都按候选的**主领域**算，
/// 附加领域不参与保底判定（与上限判定同口径）。
class DomainQuotaShortfall {
  const DomainQuotaShortfall({
    required this.domain,
    required this.minimumCount,
    required this.selectedCount,
    required this.availableCount,
  });

  final String domain;

  /// 配置的保底。
  final int minimumCount;

  /// 实际排进卷子、且主领域是这个领域的题目数量。
  final int selectedCount;

  /// 过了过滤、进入打分阶段、且主领域是这个领域的候选数量
  /// （0 = 题库里这个领域压根没有可用题）。
  final int availableCount;

  /// 题库里这个领域一道候选都没有（缺口在「收题」，不是配额问题）。
  bool get isUncovered => availableCount == 0;

  Map<String, Object?> toJson() => {
        'domain': domain,
        'minimum_count': minimumCount,
        'selected_count': selectedCount,
        'available_count': availableCount,
        'is_uncovered': isUncovered,
      };
}

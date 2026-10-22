/// 题库批量打标签计划（纯逻辑，不读库、不抛异常）。
///
/// 题库页选中 N 道题、勾选若干标签后，需要先算清楚：
/// * 哪些标签路径是词表里认识的（可挂载），哪些不认识（缺失）；
/// * 每个可挂载路径实际要给哪些题新增挂载（已挂的跳过，不重复写）；
/// * 一共要新增多少条挂载、影响多少道题、跳过多少条已有挂载。
///
/// 口径：
/// * `questionIds` / `tagPaths` 都先 trim、去空、去重保序；
/// * `knownTagPaths` trim 后成集合，大小写敏感、路径分隔符原样比较；
/// * 只有同时有题目和标签请求时才计算；任一边为空都返回空计划；
/// * 请求了词表里没有的路径 → `missingTagPaths`（保序），不产生任何挂载；
/// * `existingTagPathsByQuestionId`：题 id → 已挂标签路径集合；不含某道题的
///   键 = 该题没有已挂标签；只对可挂载路径统计跳过数；集合成员按原样精确
///   比较（不做 trim/大小写归一），调用方应传入与词表同形的路径；
/// * 没有「未知题」概念：本层不查库、不判断题是否真实存在，只按传入的题 id
///   出结果，因此结果里没有 unknownQuestionCount 这类字段；
/// * 任何输入都不抛异常。
library;

/// 一次批量打标签的计算结果（构造后不可变）。
class QuestionBulkTagPlan {
  const QuestionBulkTagPlan._({
    required this.usableTagPaths,
    required this.missingTagPaths,
    required this.questionIdsByTagPath,
    required this.linkCount,
    required this.affectedQuestionCount,
    required this.skippedExistingLinkCount,
  });

  /// 空计划：没有缺失路径、没有任何待新增挂载。
  static const QuestionBulkTagPlan empty = QuestionBulkTagPlan._(
    usableTagPaths: <String>[],
    missingTagPaths: <String>[],
    questionIdsByTagPath: <String, List<String>>{},
    linkCount: 0,
    affectedQuestionCount: 0,
    skippedExistingLinkCount: 0,
  );

  /// 词表认识、可以挂载的标签路径（请求顺序、trim、去重）。
  final List<String> usableTagPaths;

  /// 词表里没有的标签路径（请求顺序、trim、去重）。
  final List<String> missingTagPaths;

  /// 可挂载路径 → 待新增挂载的题 id（题 id 按请求顺序）；
  /// 已挂的题已剔除，没有待新增的路径不出现；键顺序 = [usableTagPaths] 顺序。
  final Map<String, List<String>> questionIdsByTagPath;

  /// 待新增的 (题, 路径) 挂载数量。
  final int linkCount;

  /// 至少会新增一个标签的题数（同一道题只算一次）。
  final int affectedQuestionCount;

  /// 因为已经挂过而跳过的 (题, 路径) 对数；只统计可挂载路径。
  final int skippedExistingLinkCount;

  /// 是否没有任何要做的动作：没有缺失路径、也没有待新增挂载。
  ///
  /// 「全部题都已挂过」也算空计划（没有缺失路径），只是
  /// [skippedExistingLinkCount] 会记录跳过的条数。
  bool get isEmpty => missingTagPaths.isEmpty && linkCount == 0;

  /// [isEmpty] 的取反。
  bool get isNotEmpty => !isEmpty;

  /// 是否有词表不认识的标签路径。
  bool get hasMissingTagPaths => missingTagPaths.isNotEmpty;

  /// 请求的标签路径总数（去重后，含缺失）。
  int get requestedTagPathCount =>
      usableTagPaths.length + missingTagPaths.length;

  @override
  String toString() {
    return 'QuestionBulkTagPlan(usable: ${usableTagPaths.length}, '
        'missing: ${missingTagPaths.length}, links: $linkCount, '
        'questions: $affectedQuestionCount, '
        'skipped: $skippedExistingLinkCount)';
  }
}

/// 计算一次批量打标签计划。
///
/// [questionIds] 选中的题 id；[tagPaths] 要打的标签路径；[knownTagPaths] 当前
/// 词表里已知的全部路径；[existingTagPathsByQuestionId] 每道题已挂的路径集合。
///
/// 任一边（题 id 或标签路径）规范化为空时返回 [QuestionBulkTagPlan.empty]。
QuestionBulkTagPlan planQuestionBulkTag({
  required Iterable<String> questionIds,
  required Iterable<String> tagPaths,
  required Iterable<String> knownTagPaths,
  Map<String, Set<String>> existingTagPathsByQuestionId =
      const <String, Set<String>>{},
}) {
  final List<String> ids = _normalizedStrings(questionIds);
  final List<String> requested = _normalizedStrings(tagPaths);
  if (ids.isEmpty || requested.isEmpty) {
    return QuestionBulkTagPlan.empty;
  }

  final Set<String> known = <String>{};
  for (final String raw in knownTagPaths) {
    final String trimmed = raw.trim();
    if (trimmed.isNotEmpty) {
      known.add(trimmed);
    }
  }

  final List<String> usable = <String>[];
  final List<String> missing = <String>[];
  for (final String path in requested) {
    if (known.contains(path)) {
      usable.add(path);
    } else {
      missing.add(path);
    }
  }

  final Map<String, List<String>> byPath = <String, List<String>>{};
  final Set<String> affected = <String>{};
  int skipped = 0;
  for (final String path in usable) {
    final List<String> pending = <String>[];
    for (final String id in ids) {
      final Set<String>? existing = existingTagPathsByQuestionId[id];
      if (existing != null && existing.contains(path)) {
        skipped++;
        continue;
      }
      pending.add(id);
      affected.add(id);
    }
    if (pending.isNotEmpty) {
      byPath[path] = List<String>.unmodifiable(pending);
    }
  }

  int links = 0;
  for (final List<String> pending in byPath.values) {
    links += pending.length;
  }

  return QuestionBulkTagPlan._(
    usableTagPaths: List<String>.unmodifiable(usable),
    missingTagPaths: List<String>.unmodifiable(missing),
    questionIdsByTagPath: Map<String, List<String>>.unmodifiable(byPath),
    linkCount: links,
    affectedQuestionCount: affected.length,
    skippedExistingLinkCount: skipped,
  );
}

/// trim、去空、去重保序。
List<String> _normalizedStrings(Iterable<String> raw) {
  final List<String> result = <String>[];
  final Set<String> seen = <String>{};
  for (final String value in raw) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty || !seen.add(trimmed)) {
      continue;
    }
    result.add(trimmed);
  }
  return result;
}

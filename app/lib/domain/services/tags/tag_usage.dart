import 'dart:collection';

/// 标签用途（schema v37，轮次一百七十六；docs/REVIEW_FEEDBACK.md §10/§11）。
///
/// 一张全局标签树，不同地方只应该看到「属于自己的那部分标签」：
/// 时间表、题库、知识网络、任务、闪卡各自声明可用哪些标签分支。
/// 声明存在标签行上（[TagUsageNode.declaredUsages]），**继承在读取时算**：
/// 一个标签没有声明就看最近一个声明了的祖先；整条链都没声明 = 不限制。
///
/// 纯 Dart、确定性、无 I/O：编码/解码 + 继承解析全部可单测。
enum TagUsage {
  time('time'),
  question('question'),
  knowledge('knowledge'),
  task('task'),
  flashcard('flashcard');

  const TagUsage(this.code);

  /// 落库用的稳定 code（不存中文，也不存枚举序号）。
  final String code;

  /// 认不出的 code 返回 null（容忍旧版本/未来版本写进来的值）。
  static TagUsage? fromCode(String code) {
    for (final usage in TagUsage.values) {
      if (usage.code == code) return usage;
    }
    return null;
  }
}

/// 把一组用途编码成可落库的字符串；空集合 -> null（= 这一级没有声明）。
///
/// 输出顺序固定在枚举声明顺序，同样的集合永远编码成同一串，便于测试与 diff。
String? encodeTagUsageCodes(Iterable<TagUsage> usages) {
  final set = usages.toSet();
  if (set.isEmpty) return null;
  final codes = <String>[
    for (final usage in TagUsage.values)
      if (set.contains(usage)) usage.code,
  ];
  return codes.join(',');
}

/// 解码一列的原始值；null / 空串 / 全是认不出的 code -> null（= 没有声明）。
Set<TagUsage>? decodeTagUsageCodes(String? raw) {
  if (raw == null) return null;
  final decoded = <TagUsage>{};
  for (final part in raw.split(',')) {
    final code = part.trim();
    if (code.isEmpty) continue;
    final usage = TagUsage.fromCode(code);
    if (usage != null) decoded.add(usage);
  }
  return decoded.isEmpty ? null : decoded;
}

/// 解析继承所需的标签快照：id、父 id、**本级**声明的用途。
class TagUsageNode {
  TagUsageNode({
    required this.id,
    this.parentId,
    Set<TagUsage>? declaredUsages,
  }) : declaredUsages = declaredUsages == null
            ? null
            : UnmodifiableSetView(declaredUsages.toSet());

  final String id;
  final String? parentId;

  /// null = 这一级没有声明（用途从祖先继承）。非 null 的空集也按「没有声明」
  /// 处理：它只可能来自手写/坏数据（编码器写空集合时返回 null），
  /// 所以解析层不让它意外截断继承链。
  final Set<TagUsage>? declaredUsages;
}

/// 在一棵标签树快照上解析「这个标签实际有效的用途」。
///
/// 构造后不可变。所有方法对未知 id 安全：返回 null / true（不限制）而不是抛。
class TagUsageResolver {
  TagUsageResolver(Iterable<TagUsageNode> nodes)
      : _nodes = {for (final node in nodes) node.id: node};

  final Map<String, TagUsageNode> _nodes;

  TagUsageNode? nodeOf(String tagId) => _nodes[tagId];

  /// 这一级自己声明的用途；null = 没有声明。
  Set<TagUsage>? declaredFor(String tagId) => _nodes[tagId]?.declaredUsages;

  /// 生效用途：自己或最近一个声明了的祖先；null = 整条链都没声明 = 不限制。
  Set<TagUsage>? effectiveFor(String tagId) {
    final source = effectiveSourceTagId(tagId);
    if (source == null) return null;
    final declared = _nodes[source]?.declaredUsages;
    if (declared == null || declared.isEmpty) return null;
    return declared;
  }

  /// 哪个标签（自己或祖先）提供了生效声明；null = 没声明。UI 可用来标「继承自」。
  String? effectiveSourceTagId(String tagId) {
    final seen = <String>{};
    var current = _nodes[tagId];
    while (current != null) {
      if (!seen.add(current.id)) return null; // 环保护：坏数据不挂 UI
      final declared = current.declaredUsages;
      if (declared != null && declared.isNotEmpty) return current.id;
      final parentId = current.parentId;
      current = parentId == null ? null : _nodes[parentId];
    }
    return null;
  }

  /// 这棵树里是否有任何标签声明了用途（UI 可据此显示「标签还没有设过边界」）。
  bool get hasAnyDeclaration =>
      _nodes.values.any((node) => node.declaredUsages?.isNotEmpty ?? false);

  /// 声明过用途的标签数量（含声明了空集的：它们也算一次明确的清除）。
  int get declaredTagCount =>
      _nodes.values.where((node) => node.declaredUsages != null).length;

  /// 这个标签在某用途下是否可见：整条链都没声明 = 可见（不限制）。
  bool isVisibleFor(String tagId, TagUsage usage) {
    final effective = effectiveFor(tagId);
    if (effective == null) return true;
    return effective.contains(usage);
  }

  /// 某用途下可见的标签 id（继承生效后）。用于选择器过滤。
  Set<String> visibleTagIdsFor(TagUsage usage) => {
        for (final id in _nodes.keys)
          if (isVisibleFor(id, usage)) id,
      };

  /// 过滤一组标签 id（只保留在某用途下可见的），保持原顺序。
  List<String> visibleOf(Iterable<String> tagIds, TagUsage usage) => [
        for (final id in tagIds)
          if (isVisibleFor(id, usage)) id,
      ];
}

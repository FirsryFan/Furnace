/// 标签树装配 + 三口径排序 + 排序偏好编解码（纯 Dart：不依赖 Flutter / drift / dart:io）。
///
/// 输入是 TagRepository 读出的扁平行（id / parentId / name / path / createdAt /
/// description）和 objectCountByTagId 得到的计数；输出是可直接渲染的树：
///
/// - 同层顺序复用 tag_tree_sort.dart 的 sortTagTreeSiblings，不复制排序实现；
/// - 父节点不在输入里的标签当根，按 id 升序记入 orphanIds；
/// - 自环、双节点环、长环都按同一规则断开：环上 id 最小的节点与它父节点的边
///   被切断、该节点当根；环上所有节点按 id 升序记入 cycleIds；
/// - path 一律用祖先 name 以 '/' 拼出（输入的 Tag.path 只作数据保留，歧义时以
///   拼出的路径为准；路径为空时从自身 name 开始）；
/// - countDescendants = true 时节点计数 = 自身 + 子树累计（只沿装配后的树边，
///   被断开的环边不计）；false 时直接用 objectCounts 里的直接计数；
/// - 不修改入参；同输入同输出：返回的列表与映射都是不可变集合，所有顺位都由
///   确定性规则决定。
library;

import 'tag_tree_sort.dart';

/// 装配树需要的一行标签数据（来自 tags 表；Tag.path 由 repository 派生，可为空）。
class TagTreeViewTag {
  const TagTreeViewTag({
    required this.id,
    this.parentId,
    required this.name,
    this.path,
    required this.createdAt,
    this.description,
  });

  /// 标签主键（同 id 重复时只保留第一条，见 buildTagTreeView）。
  final String id;

  /// 父标签 id；null 或空白表示顶层。
  final String? parentId;

  /// 显示名（Tag.name，不含路径）。
  final String name;

  /// 数据库里的派生路径（Tag.path）；装配时不用它，path 由祖先 name 拼出。
  final String? path;

  /// 添加时间，参与「按添加时间」排序。
  final DateTime createdAt;

  /// 备注，可为空。
  final String? description;

  @override
  String toString() =>
      'TagTreeViewTag(id: $id, parentId: $parentId, name: $name)';
}

/// 装配后的一个树节点。
class TagTreeViewNode {
  TagTreeViewNode({
    required this.tagId,
    required this.parentId,
    required this.name,
    required this.path,
    required this.depth,
    required this.objectCount,
    required List<TagTreeViewNode> children,
  }) : children = List<TagTreeViewNode>.unmodifiable(children);

  /// 对应 TagTreeViewTag.id。
  final String tagId;

  /// 装配后的父 id：顶层为 null（孤儿与断环后的根也是 null）。
  final String? parentId;

  /// 显示名。
  final String name;

  /// 由祖先 name 以 '/' 拼出的完整路径（根就是自身 name）。
  final String path;

  /// 层级：根为 0。
  final int depth;

  /// 直接计数或子树累计（取决于 countDescendants）。
  final int objectCount;

  /// 已按排序口径排好的子节点（不可变）。
  final List<TagTreeViewNode> children;

  /// 是否有子节点。
  bool get hasChildren => children.isNotEmpty;

  /// 子节点数量。
  int get childCount => children.length;

  @override
  String toString() =>
      'TagTreeViewNode(tagId: $tagId, depth: $depth, path: $path, '
      'objectCount: $objectCount, children: $childCount)';
}

/// 装配结果：整棵森林 + 索引 + 前序序列 + 异常诊断。
class TagTreeView {
  TagTreeView({
    required List<TagTreeViewNode> roots,
    required Map<String, TagTreeViewNode> byId,
    required List<TagTreeViewNode> preorder,
    required List<String> orphanIds,
    required List<String> cycleIds,
  })  : roots = List<TagTreeViewNode>.unmodifiable(roots),
        byId = Map<String, TagTreeViewNode>.unmodifiable(byId),
        preorder = List<TagTreeViewNode>.unmodifiable(preorder),
        orphanIds = List<String>.unmodifiable(orphanIds),
        cycleIds = List<String>.unmodifiable(cycleIds);

  /// 顶层节点（已按排序口径排序）。
  final List<TagTreeViewNode> roots;

  /// tagId -> 节点。
  final Map<String, TagTreeViewNode> byId;

  /// 先父后子的深度优先序列（同一层已按排序口径排序）。
  final List<TagTreeViewNode> preorder;

  /// 父节点不在输入里的标签 id（按 id 升序）。
  final List<String> orphanIds;

  /// 参与过环的标签 id（按 id 升序；环已被断开，这些节点仍在 byId 里）。
  final List<String> cycleIds;

  /// 没有任何根（空输入）。
  bool get isEmpty => roots.isEmpty;

  /// 节点总数。
  int get totalCount => byId.length;

  @override
  String toString() =>
      'TagTreeView(total: $totalCount, roots: ${roots.length}, '
      'orphans: ${orphanIds.length}, cycles: ${cycleIds.length})';
}

/// 把扁平的标签行装配成树，并按 [mode] 给每一层排序。
///
/// 规则（全部确定性）：
/// - 空 id 的输入行被跳过（其子节点因此成为孤儿根）；同 id 重复时保留第一条；
/// - parentId 为 null / 空白 → 根；父 id 不在输入里 → 根并记入 orphanIds；
/// - 环：环上 id 最小的节点断开父边当根，环上全部 id 记入 cycleIds；
/// - 同层顺序 = sortTagTreeSiblings；countDescendants = true 时该口径的
///   objectCount 用「自身 + 子树累计」，否则用直接计数（objectCounts 缺失按 0）；
/// - 输入里的 Tag.path 不参与装配，path 字段始终由祖先 name 拼出；
/// - 除顶层外每个节点只有一个父，因此装配后必为森林；递归深度等于树深
///   （标签树通常 2-4 层，不做迭代化）。
TagTreeView buildTagTreeView({
  required List<TagTreeViewTag> tags,
  Map<String, int> objectCounts = const <String, int>{},
  TagTreeSortMode mode = TagTreeSortMode.alphabetical,
  bool countDescendants = false,
}) {
  // 1) 规整输入：跳过空 id、同 id 保留第一条；基准顺序按 id 升序，保证
  //    孤儿 / 环的发现顺序与入参顺序无关。
  final tagById = <String, TagTreeViewTag>{};
  for (final tag in tags) {
    if (tag.id.isEmpty || tagById.containsKey(tag.id)) continue;
    tagById[tag.id] = tag;
  }
  final tagIds = tagById.keys.toList()..sort();

  // 2) 解析父边：空白父 = 根；父不在输入 = 孤儿根（先按原始输入判断）。
  final parentOf = <String, String?>{};
  final orphanIds = <String>[];
  for (final id in tagIds) {
    final rawParentId = tagById[id]!.parentId;
    if (rawParentId == null || rawParentId.trim().isEmpty) {
      parentOf[id] = null;
      continue;
    }
    if (!tagById.containsKey(rawParentId)) {
      parentOf[id] = null;
      orphanIds.add(id);
      continue;
    }
    parentOf[id] = rawParentId;
  }

  // 3) 断环：每个节点只有一条父边，所以图是「父指针森林 + 若干环」。
  //    三色遍历找环，环上 id 最小的节点断父边当根。
  final cycleIds = <String>[];
  final color = <String, int>{}; // 0/缺失 = 未访问，1 = 当前路径上，2 = 完成
  for (final start in tagIds) {
    if ((color[start] ?? 0) != 0) continue;
    final walk = <String>[];
    String? current = start;
    while (current != null && (color[current] ?? 0) == 0) {
      color[current] = 1;
      walk.add(current);
      current = parentOf[current];
    }
    if (current != null && color[current] == 1) {
      final cycle = walk.sublist(walk.indexOf(current))..sort();
      parentOf[cycle.first] = null;
      cycleIds.addAll(cycle);
    }
    for (final id in walk) {
      color[id] = 2;
    }
  }
  cycleIds.sort();
  orphanIds.sort();

  // 4) 子节点表 + 直接计数 + 子树累计（此时已无环，一定收敛到根）。
  final childrenOf = <String, List<String>>{};
  final rootIds = <String>[];
  for (final id in tagIds) {
    final parentId = parentOf[id];
    if (parentId == null) {
      rootIds.add(id);
    } else {
      childrenOf.putIfAbsent(parentId, () => <String>[]).add(id);
    }
  }

  final directCounts = <String, int>{
    for (final id in tagIds) id: objectCounts[id] ?? 0,
  };
  final subtreeCounts = <String, int>{...directCounts};
  final visitOrder = <String>[];
  final pending = <String>[...rootIds];
  while (pending.isNotEmpty) {
    final id = pending.removeLast();
    visitOrder.add(id);
    final children = childrenOf[id];
    if (children != null) {
      pending.addAll(children);
    }
  }
  for (final id in visitOrder.reversed) {
    final parentId = parentOf[id];
    if (parentId == null) continue;
    subtreeCounts[parentId] = subtreeCounts[parentId]! + subtreeCounts[id]!;
  }

  int countFor(String id) =>
      countDescendants ? subtreeCounts[id]! : directCounts[id]!;

  // 5) 同层排序：完全复用 tag_tree_sort.dart 的全序比较，不复制实现。
  List<String> sortLevel(List<String> ids) {
    if (ids.isEmpty) return const <String>[];
    final entries = <TagTreeSortEntry>[
      for (final id in ids)
        TagTreeSortEntry(
          id: id,
          name: tagById[id]!.name,
          createdAt: tagById[id]!.createdAt,
          objectCount: countFor(id),
        ),
    ];
    return sortTagTreeSiblings(entries, mode)
        .map((entry) => entry.id)
        .toList(growable: false);
  }

  final sortedRootIds = sortLevel(rootIds);
  final sortedChildren = <String, List<String>>{
    for (final entry in childrenOf.entries) entry.key: sortLevel(entry.value),
  };

  // 6) 自顶向下组装节点（父边已无环，path/depth 由祖先链路得出）。
  final byId = <String, TagTreeViewNode>{};
  TagTreeViewNode buildNode(String id, String? parentPath, int depth) {
    final tag = tagById[id]!;
    final path = parentPath == null ? tag.name : '$parentPath/${tag.name}';
    final childIds = sortedChildren[id] ?? const <String>[];
    final children = <TagTreeViewNode>[
      for (final childId in childIds) buildNode(childId, path, depth + 1),
    ];
    final node = TagTreeViewNode(
      tagId: id,
      parentId: parentOf[id],
      name: tag.name,
      path: path,
      depth: depth,
      objectCount: countFor(id),
      children: children,
    );
    byId[id] = node;
    return node;
  }

  final roots = <TagTreeViewNode>[
    for (final id in sortedRootIds) buildNode(id, null, 0),
  ];

  // 7) 前序：父在子之前的深度优先序（同层已排序）。
  final preorder = <TagTreeViewNode>[];
  final preorderStack = <TagTreeViewNode>[...roots.reversed];
  while (preorderStack.isNotEmpty) {
    final node = preorderStack.removeLast();
    preorder.add(node);
    for (var index = node.children.length - 1; index >= 0; index--) {
      preorderStack.add(node.children[index]);
    }
  }

  return TagTreeView(
    roots: roots,
    byId: byId,
    preorder: preorder,
    orphanIds: orphanIds,
    cycleIds: cycleIds,
  );
}

/// 从持久化字符串还原排序口径：null / 空白 / 认不出 → 字典序；
/// 容忍两端空白与大小写（复用 TagTreeSortMode.byCode 的归一化）。
TagTreeSortMode tagTreeSortModeFromStorage(String? raw) {
  if (raw == null) return TagTreeSortMode.alphabetical;
  return TagTreeSortMode.byCode(raw) ?? TagTreeSortMode.alphabetical;
}

/// 排序口径 → 持久化字符串（稳定 snake_case 编码，可直接进 preferences / DB）。
String tagTreeSortModeToStorage(TagTreeSortMode mode) => mode.code;

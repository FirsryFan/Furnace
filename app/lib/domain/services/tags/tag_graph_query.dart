/// 标签图（Thinking DAG 式布局）的可见性与搜索纯逻辑。
///
/// 这里只回答三个问题，不碰 Flutter / drift / l10n：
///  * 哪些节点当前应该出现在图上（折叠状态 + 搜索过滤）；
///  * 一次搜索命中了哪些标签；
///  * 命中标签要显示时，需要连带显示哪些祖先/后代。
///
/// 约定：
///  * 入参不会被修改，返回值都是新的不可变集合；
///  * 所有顺序都沿 [TagTreeView.preorder]（同层已按用户选的排序口径排好），
///    因此同一份输入永远得到同一顺序，测试可以逐项钉住；
///  * 折叠按 id 记忆：集合里出现未知 id 不影响输出（被忽略）；
///  * 搜索大小写不敏感，只对 `name` / `path` 做子串匹配（不引入模糊匹配）；
///  * 搜索模式下忽略折叠（命中路径必须展开），由 [onlyIds] 收窄可见集合。
library;

import 'tag_tree_view.dart';

/// 搜索命中的标签 id，按树的前序顺序返回。
///
/// 口径：
///  * query 先 trim，空串 = 不搜索，返回空列表；
///  * 不打分、不做模糊匹配：name 或由祖先 name 拼出的 path 包含 query 就算命中
///    （大小写不敏感），所以搜「语」能命中「文化课/语文」；
///  * 返回顺序是前序不是命中强度，UI 不需要另排一次。
List<String> tagGraphSearchMatchIds(TagTreeView tree, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) {
    return const <String>[];
  }
  return List<String>.unmodifiable(<String>[
    for (final node in tree.preorder)
      if (node.name.toLowerCase().contains(needle) ||
          node.path.toLowerCase().contains(needle))
        node.tagId,
  ]);
}

/// [ids] 的全部祖先 id（不含自身，按发现顺序无所谓；根没有祖先）。
///
/// 未知 id 被忽略；父指针坏掉（父不在 `byId` 里）时停在最后能走到的节点，
/// 不会因为坏数据抛异常（与 `buildTagTreeView` 的防环/防孤儿一致）。
Set<String> tagGraphAncestorIds(TagTreeView tree, Iterable<String> ids) {
  final ancestors = <String>{};
  for (final id in ids) {
    var node = tree.byId[id];
    final guard = <String>{id};
    while (node != null) {
      final parentId = node.parentId;
      if (parentId == null) {
        break;
      }
      if (!guard.add(parentId)) {
        break;
      }
      ancestors.add(parentId);
      node = tree.byId[parentId];
    }
  }
  return Set<String>.unmodifiable(ancestors);
}

/// 搜索生效时要画出来的节点：命中节点 + 它们的祖先 + 命中节点的全部后代。
///
/// 为什么连带后代：命中一个分支根时，用户想看的是整个分支，而不是一条孤零零
/// 的路径；为什么连带祖先：图要从根连到命中的节点，否则看不出它挂在哪。
/// 结果是「命中节点子树的连通闭包」——同一份命中集合，页面与测试共用同一口径。
Set<String> tagGraphSearchVisibleIds(
  TagTreeView tree,
  Iterable<String> matchIds,
) {
  final visible = <String>{};
  for (final id in matchIds) {
    final node = tree.byId[id];
    if (node == null || !visible.add(id)) {
      continue;
    }
    // 祖先路径：从命中节点一路画到根。
    var current = node;
    var guard = <String>{id};
    while (current.parentId != null) {
      final parentId = current.parentId!;
      if (!guard.add(parentId)) {
        break;
      }
      final parent = tree.byId[parentId];
      if (parent == null) {
        break;
      }
      visible.add(parent.tagId);
      current = parent;
    }
    // 后代：命中分支整棵张开（折叠状态在搜索期间被忽略）。
    final stack = <TagTreeViewNode>[...node.children];
    guard = <String>{id};
    while (stack.isNotEmpty) {
      final child = stack.removeLast();
      if (!guard.add(child.tagId)) {
        continue;
      }
      visible.add(child.tagId);
      stack.addAll(child.children);
    }
  }
  return Set<String>.unmodifiable(visible);
}

/// 当前应该画出来的节点，前序顺序（父在子前，同层保持树里的排序）。
///
/// [collapsedIds]：被用户折叠的标签 id；命中的节点本身仍显示，但不再递归子层。
/// [onlyIds]：非空时只保留这个集合里的节点（搜索模式），并且**忽略折叠**——
/// 搜索的目标就是把命中路径摊开。闭包口径见 [tagGraphSearchVisibleIds]。
List<TagTreeViewNode> tagGraphVisibleNodes(
  TagTreeView tree, {
  Set<String> collapsedIds = const <String>{},
  Set<String>? onlyIds,
}) {
  final visible = <TagTreeViewNode>[];
  void visit(TagTreeViewNode node) {
    final included = onlyIds == null || onlyIds.contains(node.tagId);
    if (included) {
      visible.add(node);
    }
    // 折叠只在「整棵树」模式下生效；搜索模式下用 onlyIds 收窄，并继续往下走，
    // 让任意子集（包括缺祖先的闭包）都能得到自己的前序序列。
    if (onlyIds == null && collapsedIds.contains(node.tagId)) {
      return;
    }
    for (final child in node.children) {
      visit(child);
    }
  }

  for (final root in tree.roots) {
    visit(root);
  }
  return List<TagTreeViewNode>.unmodifiable(visible);
}

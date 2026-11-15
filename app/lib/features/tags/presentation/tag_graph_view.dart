/// 标签图的 Widget 层：画布（节点 + 父子连线）、节点卡片、节点设置浮窗。
///
/// 这里不做任何数据查询/写库：位置来自 [layoutTagGraph]，节点内容/回调由
/// tag_tree_page 注入。拆出来是为了让画布与浮窗能被单独渲染、单独测，
/// 页面文件只留状态与动作。
library;

import 'package:flutter/material.dart';

import '../../../domain/services/tags/tag_tree_view.dart';
import '../../../l10n/app_localizations.dart';
import 'tag_graph_layout.dart';

/// 节点设置浮窗里每一行的键（测试按 key 点，不依赖中文文案）。
const Key tagNodeSettingsKnowledgeKey = Key('tag-node-settings-knowledge');
const Key tagNodeSettingsAddChildKey = Key('tag-node-settings-add-child');
const Key tagNodeSettingsRenameKey = Key('tag-node-settings-rename');
const Key tagNodeSettingsMoveKey = Key('tag-node-settings-move');
const Key tagNodeSettingsUsageKey = Key('tag-node-settings-usage');
const Key tagNodeSettingsDeleteKey = Key('tag-node-settings-delete');

/// 画布：先用 painter 画全部连线，再把节点卡片按矩形叠在上面。
///
/// 连线在节点下面，所以点节点不会被线挡住；节点的命中/点击完全由页面给的
/// [buildNode] 决定。
class TagGraphCanvas extends StatelessWidget {
  const TagGraphCanvas({
    super.key,
    required this.layout,
    required this.highlightedIds,
    required this.nodeBuilder,
  });

  /// 已经算好的节点位置与连线。
  final TagGraphLayout layout;

  /// 搜索命中的节点 id：两端都在集合里的连线用强调色画，其余用弱色。
  final Set<String> highlightedIds;

  /// 每个可见节点对应的 Widget（页面负责选中/折叠/菜单等交互）。
  final Widget Function(BuildContext context, TagGraphNodePlacement placement)
      nodeBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: layout.size.width,
      height: layout.size.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: TagGraphEdgePainter(
                edges: layout.edges,
                baseColor: theme.colorScheme.outlineVariant,
                highlightColor: theme.colorScheme.primary,
                highlightedIds: highlightedIds,
              ),
            ),
          ),
          for (final placement in layout.nodes)
            Positioned.fromRect(
              rect: placement.rect,
              child: nodeBuilder(context, placement),
            ),
        ],
      ),
    );
  }
}

/// 画父子连线：父右中点 → 层间中线 → 子左中点，正交折线。
class TagGraphEdgePainter extends CustomPainter {
  const TagGraphEdgePainter({
    required this.edges,
    required this.baseColor,
    required this.highlightColor,
    required this.highlightedIds,
  });

  final List<TagGraphEdge> edges;
  final Color baseColor;
  final Color highlightColor;
  final Set<String> highlightedIds;

  @override
  void paint(Canvas canvas, Size size) {
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = baseColor;
    final highlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..color = highlightColor;

    for (final edge in edges) {
      final highlighted = highlightedIds.contains(edge.parentId) &&
          highlightedIds.contains(edge.childId);
      final path = Path()
        ..moveTo(edge.from.dx, edge.from.dy)
        ..lineTo(edge.midX, edge.from.dy)
        ..lineTo(edge.midX, edge.to.dy)
        ..lineTo(edge.to.dx, edge.to.dy);
      canvas.drawPath(path, highlighted ? highlightPaint : basePaint);
    }
  }

  @override
  bool shouldRepaint(TagGraphEdgePainter oldDelegate) =>
      oldDelegate.edges != edges ||
      oldDelegate.highlightedIds != highlightedIds ||
      oldDelegate.baseColor != baseColor ||
      oldDelegate.highlightColor != highlightColor;
}

/// 图上的一个标签节点卡片。
///
/// 交互分工（用户 2026-11-15 补充要求）：**点节点 = 打开设置浮窗**；
/// 折叠/展开只走节点上的箭头按钮，两者不混在同一个手势里。
class TagGraphNodeCard extends StatelessWidget {
  const TagGraphNodeCard({
    super.key,
    required this.node,
    required this.collapsed,
    required this.showObjectCount,
    required this.selectionMode,
    required this.selected,
    required this.matched,
    required this.declaredUsageLabels,
    required this.onTap,
    required this.onToggle,
    required this.onSelectToggle,
    required this.onLongPress,
  });

  final TagTreeViewNode node;

  /// 这一支是否被折叠（默认全展开，所以存的是「折叠」而不是「展开」）。
  final bool collapsed;

  /// 只有「按内容量」排序时才显示内容量角标（与旧列表行为一致）。
  final bool showObjectCount;

  final bool selectionMode;
  final bool selected;

  /// 当前搜索是否命中这个节点（命中用强调色描边/底色）。
  final bool matched;

  /// 这一级自己声明的用途名（空 = 没有声明，不显示徽标）。
  final List<String> declaredUsageLabels;

  /// 单击：多选模式下勾选，否则打开节点设置浮窗。
  final VoidCallback onTap;

  /// 折叠/展开箭头（仅当有子节点时显示）。
  final VoidCallback onToggle;

  /// 多选模式下的勾选框。
  final VoidCallback onSelectToggle;

  /// 长按/右键：与单击一致，打开设置浮窗（不做另一套菜单）。
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasChildren = node.hasChildren;
    final expanded = !collapsed;

    final Color background;
    final Color borderColor;
    final Color foreground;
    if (selected) {
      background = scheme.primaryContainer;
      borderColor = scheme.primary;
      foreground = scheme.onPrimaryContainer;
    } else if (matched) {
      background = scheme.secondaryContainer;
      borderColor = scheme.secondary;
      foreground = scheme.onSecondaryContainer;
    } else {
      background = scheme.surfaceContainerHigh;
      borderColor = scheme.outlineVariant;
      foreground = scheme.onSurface;
    }

    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: borderColor,
          width: selected || matched ? 1.6 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        onSecondaryTap: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            children: [
              if (selectionMode)
                SizedBox(
                  key: ValueKey<String>('tag-graph-select-${node.tagId}'),
                  width: 40,
                  height: 40,
                  child: Checkbox(
                    value: selected,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (_) => onSelectToggle(),
                  ),
                ),
              if (hasChildren)
                SizedBox(
                  width: 28,
                  height: 28,
                  child: IconButton(
                    key: ValueKey<String>('tag-graph-toggle-${node.tagId}'),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    tooltip: expanded ? l10n.tagsCollapse : l10n.tagsExpand,
                    icon: Icon(
                      expanded
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                    ),
                    onPressed: onToggle,
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(Icons.sell_outlined, size: 16, color: foreground),
                ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  node.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
              ),
              if (hasChildren && collapsed)
                Tooltip(
                  message: l10n.tagsCollapsedHidden(node.childCount),
                  child: Container(
                    key: ValueKey<String>('tag-graph-collapsed-${node.tagId}'),
                    margin: const EdgeInsets.only(left: 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.account_tree_outlined,
                          size: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${node.childCount}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (!selectionMode && declaredUsageLabels.isNotEmpty)
                Tooltip(
                  key: ValueKey<String>('tag-usage-badge-${node.tagId}'),
                  message: declaredUsageLabels.join('、'),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 2, right: 2),
                    child: Icon(
                      Icons.rule,
                      size: 16,
                      color: scheme.primary,
                    ),
                  ),
                ),
              if (showObjectCount)
                TagObjectCountBadge(
                  key: ValueKey<String>('tag-object-count-${node.tagId}'),
                  count: node.objectCount,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 内容量角标（与旧标签树的形状一致，键也沿用 `tag-object-count-*`）。
class TagObjectCountBadge extends StatelessWidget {
  const TagObjectCountBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

/// 节点设置浮窗：居中卡片 + 默认 modal barrier（背景变暗）。
///
/// 用户 2026-11-15 补充：这里放这个标签自己的动作（关联内容/新建子标签/
/// 重命名/移动/用途边界/删除）；折叠/展开仍留在节点卡的箭头上，不放进浮窗。
class TagNodeSettingsDialog extends StatelessWidget {
  const TagNodeSettingsDialog({
    super.key,
    required this.label,
    required this.declaredUsageText,
    required this.onOpenKnowledgeEntry,
    required this.onAddChild,
    required this.onRename,
    required this.onMove,
    required this.onUsage,
    required this.onDelete,
  });

  /// 标签显示名（path 优先，与页面 `_labelOf` 一致）。
  final String label;

  /// 本级声明的用途描述；空串 = 没有声明（显示继承提示）。
  final String declaredUsageText;

  final VoidCallback onOpenKnowledgeEntry;
  final VoidCallback onAddChild;
  final VoidCallback onRename;
  final VoidCallback onMove;
  final VoidCallback onUsage;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    void runThenClose(VoidCallback action) {
      Navigator.of(context).pop();
      action();
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
                child: Row(
                  children: [
                    Icon(Icons.sell_outlined, color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.tagsNodeSettings,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.commonClose,
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 8),
              ListTile(
                key: tagNodeSettingsKnowledgeKey,
                leading: const Icon(Icons.sell_outlined),
                title: Text(l10n.tagsKnowledgeEntry),
                onTap: () => runThenClose(onOpenKnowledgeEntry),
              ),
              ListTile(
                key: tagNodeSettingsAddChildKey,
                leading: const Icon(Icons.add),
                title: Text(l10n.tagsAddChild),
                onTap: () => runThenClose(onAddChild),
              ),
              ListTile(
                key: tagNodeSettingsRenameKey,
                leading: const Icon(Icons.drive_file_rename_outline),
                title: Text(l10n.tagsRename),
                onTap: () => runThenClose(onRename),
              ),
              ListTile(
                key: tagNodeSettingsMoveKey,
                leading: const Icon(Icons.drive_file_move_outline),
                title: Text(l10n.commonMove),
                onTap: () => runThenClose(onMove),
              ),
              ListTile(
                key: tagNodeSettingsUsageKey,
                leading: const Icon(Icons.rule),
                title: Text(l10n.tagUsageEntryTitle),
                subtitle: Text(
                  declaredUsageText.isEmpty
                      ? l10n.tagUsageInheritHint
                      : declaredUsageText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => runThenClose(onUsage),
              ),
              const Divider(height: 8),
              ListTile(
                key: tagNodeSettingsDeleteKey,
                leading: Icon(Icons.delete_outline, color: scheme.error),
                title: Text(
                  l10n.commonDelete,
                  style: TextStyle(color: scheme.error),
                ),
                onTap: () => runThenClose(onDelete),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  l10n.tagsNodeSettingsHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

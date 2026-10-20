import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/database/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/tags/tag_tree_sort.dart';
import '../../../domain/services/tags/tag_tree_view.dart';
import '../../../l10n/app_localizations.dart';

/// All tags, flat. The tree is assembled in memory so a rename or move only
/// needs one refresh.
final allTagsProvider = FutureProvider<List<Tag>>((ref) {
  ref.watchDatabaseRevision();
  return ref.watch(tagRepositoryProvider).getAllTags();
});

/// How many objects hang directly on each tag. The tree needs this twice: the
/// "by object count" ordering and the count badge.
///
/// It is a separate provider so the tree can render from [allTagsProvider]
/// before the counts arrive - a missing count simply means 0, it never blocks
/// the tree or turns the page into a spinner.
final tagObjectCountsProvider = FutureProvider<Map<String, int>>((ref) {
  ref.watchDatabaseRevision();
  return ref.watch(tagRepositoryProvider).objectCountByTagId();
});

/// The sort mode picked in the app bar.
///
/// Session-scoped on purpose: this round does not write preferences (and does
/// not touch the l10n files). [tagTreeSortModeToStorage] is the stable value
/// ready for that wiring later; a restart falls back to alphabetical.
final tagTreeSortModeProvider =
    StateProvider<TagTreeSortMode>((ref) => TagTreeSortMode.alphabetical);

/// The authoritative display/query path of a tag.
String _labelOf(Tag tag) =>
    tag.path == null || tag.path!.isEmpty ? tag.name : tag.path!;

/// The tag tree (blueprint 2.8; user annotation 9).
///
/// Mindnet is no longer a separate module: the tree of tags IS the map. This
/// page is therefore the single place to grow the hierarchy that Thread's goal
/// matching and filtering depend on.
class TagTreePage extends ConsumerStatefulWidget {
  const TagTreePage({super.key});

  @override
  ConsumerState<TagTreePage> createState() => _TagTreePageState();
}

class _TagTreePageState extends ConsumerState<TagTreePage> {
  final _expanded = <String>{};

  /// Maps the flat drift rows to the pure-logic tree builder: assembly, the
  /// three ordering modes and the parent/child edges all live in
  /// domain/services/tags/tag_tree_view.dart. This page only keeps the
  /// expansion state (keyed by tag id) and renders the result.
  TagTreeView _treeOf(
    List<Tag> tags,
    Map<String, int> objectCounts,
    TagTreeSortMode mode,
  ) =>
      buildTagTreeView(
        tags: <TagTreeViewTag>[
          for (final tag in tags)
            TagTreeViewTag(
              id: tag.id,
              parentId: tag.parentId,
              name: tag.name,
              path: tag.path,
              createdAt: DateTime.fromMillisecondsSinceEpoch(tag.createdAt),
              description: tag.description,
            ),
        ],
        objectCounts: objectCounts,
        mode: mode,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tagsAsync = ref.watch(allTagsProvider);
    final mode = ref.watch(tagTreeSortModeProvider);
    // Counts loading must not hold the tree back: until they land every tag
    // simply shows 0, and the page rebuilds by itself when they arrive.
    final objectCounts =
        ref.watch(tagObjectCountsProvider).valueOrNull ?? const <String, int>{};

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navTags),
        actions: [
          // Mode names come straight from the domain enum for now: the l10n
          // files are being edited by another member this round, so wiring
          // these three labels into AppLocalizations is a follow-up.
          PopupMenuButton<TagTreeSortMode>(
            tooltip: '排序',
            icon: const Icon(Icons.sort),
            initialValue: mode,
            onSelected: (next) =>
                ref.read(tagTreeSortModeProvider.notifier).state = next,
            itemBuilder: (context) => <PopupMenuEntry<TagTreeSortMode>>[
              for (final option in TagTreeSortMode.values)
                CheckedPopupMenuItem<TagTreeSortMode>(
                  value: option,
                  checked: option == mode,
                  child: Text(option.labelZh),
                ),
            ],
          ),
          IconButton(
            tooltip: l10n.tagsNewTop,
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: () => _addTag(context, parent: null),
          ),
        ],
      ),
      body: tagsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('$error')),
        data: (tags) {
          if (tags.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.account_tree_outlined,
                      size: 44, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 12),
                  Text(l10n.tagsEmpty),
                  const SizedBox(height: 12),
                  IconButton.filled(
                    tooltip: l10n.commonAdd,
                    icon: const Icon(Icons.add),
                    onPressed: () => _addTag(context, parent: null),
                  ),
                ],
              ),
            );
          }
          final tree = _treeOf(tags, objectCounts, mode);
          final tagsById = <String, Tag>{
            for (final tag in tags) tag.id: tag,
          };
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              for (final root in tree.roots)
                ..._renderNode(
                  context,
                  root,
                  tagsById: tagsById,
                  showObjectCount: mode == TagTreeSortMode.byObjectCount,
                ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _renderNode(
    BuildContext context,
    TagTreeViewNode node, {
    required Map<String, Tag> tagsById,
    required bool showObjectCount,
  }) {
    final tag = tagsById[node.tagId]!;
    final hasChildren = node.hasChildren;
    final isExpanded = _expanded.contains(node.tagId);
    final widgets = <Widget>[
      _TagTile(
        node: node,
        tag: tag,
        hasChildren: hasChildren,
        expanded: isExpanded,
        showObjectCount: showObjectCount,
        onToggle: () => setState(() {
          if (isExpanded) {
            _expanded.remove(node.tagId);
          } else {
            _expanded.add(node.tagId);
          }
        }),
        onAddChild: () => _addTag(context, parent: tag),
        onRename: () => _renameTag(context, tag),
        onDelete: () => _deleteTag(context, tag),
      ),
    ];
    if (hasChildren && isExpanded) {
      for (final child in node.children) {
        widgets.addAll(_renderNode(
          context,
          child,
          tagsById: tagsById,
          showObjectCount: showObjectCount,
        ));
      }
    }
    return widgets;
  }

  Future<void> _addTag(BuildContext context, {required Tag? parent}) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(parent == null
            ? l10n.tagsNewTop
            : l10n.tagsNewChild(_labelOf(parent))),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          // Enter confirms, like every other dialog in the app.
          onSubmitted: (_) => Navigator.of(context).pop(true),
          decoration: InputDecoration(
            labelText: l10n.commonName,
            helperText: l10n.tagsNameHint,
            helperMaxLines: 2,
          ),
        ),
        actions: [
          IconButton(
            tooltip: l10n.commonCancel,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          IconButton.filled(
            tooltip: l10n.commonSave,
            icon: const Icon(Icons.check),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (saved != true) {
      return;
    }
    final name = controller.text.trim();
    if (name.isEmpty) {
      return;
    }
    await ref.read(tagRepositoryProvider).createTag(
          name: name,
          parentId: parent?.id,
        );
    if (parent != null) {
      _expanded.add(parent.id);
    }
    ref.invalidate(allTagsProvider);
  }

  Future<void> _renameTag(BuildContext context, Tag tag) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: tag.name);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.tagsRename),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Navigator.of(context).pop(true),
          decoration: InputDecoration(labelText: l10n.commonName),
        ),
        actions: [
          IconButton(
            tooltip: l10n.commonCancel,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          IconButton.filled(
            tooltip: l10n.commonSave,
            icon: const Icon(Icons.check),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (saved != true) {
      return;
    }
    final name = controller.text.trim();
    if (name.isEmpty) {
      return;
    }
    await ref.read(tagRepositoryProvider).renameTag(tag.id, name);
    ref.invalidate(allTagsProvider);
  }

  Future<void> _deleteTag(BuildContext context, Tag tag) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.tagsDeleteTitle(_labelOf(tag))),
        content: Text(l10n.tagsDeleteBody),
        actions: [
          IconButton(
            tooltip: l10n.commonCancel,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          IconButton.filled(
            tooltip: l10n.commonDelete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await ref.read(tagRepositoryProvider).deleteTag(tag.id);
    ref.invalidate(allTagsProvider);
  }
}

class _TagTile extends StatelessWidget {
  const _TagTile({
    required this.node,
    required this.tag,
    required this.hasChildren,
    required this.expanded,
    required this.showObjectCount,
    required this.onToggle,
    required this.onAddChild,
    required this.onRename,
    required this.onDelete,
  });

  final TagTreeViewNode node;

  /// The drift row behind [node], used by the add/rename/delete dialogs
  /// (they predate the pure-logic tree and still take a `Tag`).
  final Tag tag;
  final bool hasChildren;
  final bool expanded;
  final bool showObjectCount;
  final VoidCallback onToggle;
  final VoidCallback onAddChild;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    // Right-click (desktop) / long-press (touch) opens the menu right on the
    // row. The three-dot button stays only as a touch affordance, because a
    // menu that is always visible is exactly what the user pushed back on.
    return GestureDetector(
      onSecondaryTap: () => _showMenu(context),
      onLongPress: () => _showMenu(context),
      child: ListTile(
        contentPadding: EdgeInsets.only(left: 12 + node.depth * 18.0, right: 4),
        leading: hasChildren
            ? IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: expanded ? l10n.tagsCollapse : l10n.tagsExpand,
                icon: Icon(expanded
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_right),
                onPressed: onToggle,
              )
            : Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(Icons.sell_outlined,
                    size: 16, color: theme.colorScheme.outline),
              ),
        title: Text(node.name, style: theme.textTheme.bodyLarge),
        subtitle: _PathCrumbs(
          segments: node.path.split('/').where((s) => s.isNotEmpty).toList(),
        ),
        onTap: hasChildren ? onToggle : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showObjectCount)
              _ObjectCountBadge(
                key: ValueKey<String>('tag-object-count-${node.tagId}'),
                count: node.objectCount,
              ),
            PopupMenuButton<String>(
              tooltip: l10n.commonEdit,
              icon: const Icon(Icons.more_vert),
              onSelected: _handle,
              itemBuilder: (context) => _menuItems(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showMenu(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(
          box != null ? box.localToGlobal(Offset.zero).dx + 40 : 100,
          box != null ? box.localToGlobal(Offset.zero).dy + 20 : 100,
          1,
          1,
        ),
        Offset.zero & (overlay?.size ?? const Size(400, 400)),
      ),
      items: _menuItems(context),
    );
    if (value != null) {
      _handle(value);
    }
  }

  List<PopupMenuEntry<String>> _menuItems(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return [
      PopupMenuItem(
        value: 'add',
        child: Row(
          children: [
            const Icon(Icons.add, size: 18),
            const SizedBox(width: 10),
            Text(l10n.tagsAddChild),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'rename',
        child: Row(
          children: [
            const Icon(Icons.drive_file_rename_outline, size: 18),
            const SizedBox(width: 10),
            Text(l10n.tagsRename),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'delete',
        child: Row(
          children: [
            const Icon(Icons.delete_outline, size: 18),
            const SizedBox(width: 10),
            Text(l10n.commonDelete),
          ],
        ),
      ),
    ];
  }

  void _handle(String value) {
    switch (value) {
      case 'add':
        onAddChild();
      case 'rename':
        onRename();
      case 'delete':
        onDelete();
    }
  }
}

/// How much content hangs on one tag, shown only while sorting by content
/// count (in the other modes the row stays as quiet as before).
class _ObjectCountBadge extends StatelessWidget {
  const _ObjectCountBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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

/// Shows the path as tappable breadcrumbs: the leaf is already in the title,
/// so the crumbs reveal the ancestors for precise querying.
class _PathCrumbs extends StatelessWidget {
  const _PathCrumbs({required this.segments});

  final List<String> segments;

  @override
  Widget build(BuildContext context) {
    if (segments.length <= 1) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        segments.join(' › '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

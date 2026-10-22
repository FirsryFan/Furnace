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

/// The sort mode picked in the app bar, persisted in `local_settings`
/// (schema v29).
///
/// The first build reads the stored [TagTreeSortMode.code] and translates it
/// with [tagTreeSortModeFromStorage] (NULL or an unknown code reads as 字典序);
/// every switch writes the code back without waiting for the write. A failed
/// write only logs: an unsaved preference must never block the tree, and the
/// in-memory choice stays in effect for the session.
final tagTreeSortModeProvider =
    AsyncNotifierProvider<TagTreeSortModeController, TagTreeSortMode>(
  TagTreeSortModeController.new,
);

/// Reads the stored tag-tree sort mode and persists every change.
class TagTreeSortModeController extends AsyncNotifier<TagTreeSortMode> {
  @override
  Future<TagTreeSortMode> build() async {
    final String? raw =
        await ref.watch(settingsRepositoryProvider).getTagTreeSortMode();
    return tagTreeSortModeFromStorage(raw);
  }

  /// Switches the tree immediately, then persists the choice.
  Future<void> select(TagTreeSortMode mode) async {
    state = AsyncData<TagTreeSortMode>(mode);
    try {
      await ref
          .read(settingsRepositoryProvider)
          .updateTagTreeSortMode(tagTreeSortModeToStorage(mode));
    } catch (error) {
      // Losing the preference is annoying, not fatal: keep the session choice.
      debugPrint('Failed to persist tag tree sort mode: $error');
    }
  }
}

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

  /// 多选模式：进入后每行左侧出现勾选框，底部出现批量操作条。
  bool _selectionMode = false;
  final _selected = <String>{};

  /// 批量删除/移动执行期间为 true：操作条与各入口一律禁用，避免重入。
  bool _batchBusy = false;

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
    final modeAsync = ref.watch(tagTreeSortModeProvider);
    // Never paint the tree under a guessed order: until the stored mode lands
    // one spinner beats showing 字典序 and jumping to the real order.
    final mode = modeAsync.valueOrNull ?? TagTreeSortMode.alphabetical;
    // Counts loading must not hold the tree back: until they land every tag
    // simply shows 0, and the page rebuilds by itself when they arrive.
    final objectCounts =
        ref.watch(tagObjectCountsProvider).valueOrNull ?? const <String, int>{};

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navTags),
        actions: _selectionMode
            ? [
                IconButton(
                  tooltip: l10n.commonClose,
                  icon: const Icon(Icons.close),
                  onPressed: _batchBusy ? null : _exitSelectionMode,
                ),
              ]
            : [
                // Mode names still come straight from the domain enum: only the
                // button tooltip is localized this round.
                PopupMenuButton<TagTreeSortMode>(
                  tooltip: l10n.tagsSort,
                  icon: const Icon(Icons.sort),
                  initialValue: mode,
                  onSelected: (next) =>
                      ref.read(tagTreeSortModeProvider.notifier).select(next),
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
                // 多选入口（task-119）
                IconButton(
                  tooltip: l10n.tagsSelectMode,
                  icon: const Icon(Icons.checklist_outlined),
                  onPressed: _enterSelectionMode,
                ),
              ],
      ),
      bottomNavigationBar: _selectionMode
          ? _buildSelectionBar(
              context,
              tagsAsync.valueOrNull ?? const <Tag>[],
            )
          : null,
      body: modeAsync.isLoading
          ? const Center(child: CircularProgressIndicator())
          : tagsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(child: Text('$error')),
              data: (tags) {
                if (tags.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.account_tree_outlined,
                            size: 44,
                            color: Theme.of(context).colorScheme.outline),
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
        selectionMode: _selectionMode,
        selected: _selected.contains(node.tagId),
        onSelectToggle: () => _toggleSelected(node.tagId),
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

  // --- 多选批量操作（task-119）-------------------------------------------
  //
  // 用户反馈：逐个点开菜单、移动、再退出太繁琐。多选后底部一条操作栏就能
  // 批量删除/移动。选择只存在页面状态里，退出多选即清空；删除/移动成功后
  // 同样清空（被删的 id 不能留在集合里，否则下一次批量操作会指向不存在的行）。

  void _enterSelectionMode() {
    if (_batchBusy) {
      return;
    }
    setState(() {
      _selectionMode = true;
      _selected.clear();
    });
  }

  void _exitSelectionMode() {
    if (_batchBusy) {
      return;
    }
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  void _toggleSelected(String tagId) {
    if (_batchBusy) {
      return;
    }
    setState(() {
      if (!_selected.remove(tagId)) {
        _selected.add(tagId);
      }
    });
  }

  void _toggleSelectAll(List<Tag> tags) {
    if (_batchBusy) {
      return;
    }
    setState(() {
      if (tags.isNotEmpty && _selected.length == tags.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(tags.map((tag) => tag.id));
      }
    });
  }

  /// 底部批量操作条。只要处于多选就显示（即使 0 项）——否则「全选」按钮
  /// 永远出不来；删除/移动在 0 项时禁用。
  Widget _buildSelectionBar(BuildContext context, List<Tag> tags) {
    final l10n = AppLocalizations.of(context);
    final allSelected = tags.isNotEmpty && _selected.length == tags.length;
    final theme = Theme.of(context);
    return BottomAppBar(
      child: Row(
        children: [
          Text(
            _batchBusy
                ? l10n.tagsBatchBusy
                : l10n.tagsSelectedCount(_selected.length),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: tags.isEmpty || _batchBusy
                ? null
                : () => _toggleSelectAll(tags),
            child: Text(
              allSelected ? l10n.tagsClearSelection : l10n.tagsSelectAll,
            ),
          ),
          const Spacer(),
          FilledButton.tonal(
            onPressed: _selected.isEmpty || _batchBusy
                ? null
                : () => _batchMove(context),
            child: Text(l10n.tagsBatchMove),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _selected.isEmpty || _batchBusy
                ? null
                : () => _batchDelete(context),
            child: Text(l10n.tagsBatchDelete),
          ),
        ],
      ),
    );
  }

  Future<void> _batchDelete(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final tags = ref.read(allTagsProvider).valueOrNull ?? const <Tag>[];
    final byId = <String, Tag>{for (final tag in tags) tag.id: tag};
    final ids = _selected.toList()..sort();
    final preview = <String>[
      for (final id in ids.take(5)) byId[id] == null ? id : _labelOf(byId[id]!),
    ].join('、');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.tagsBatchDeleteTitle(ids.length)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.tagsBatchDeletePreview(preview, ids.length)),
            const SizedBox(height: 12),
            Text(l10n.tagsDeleteBody),
          ],
        ),
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
    final repository = ref.read(tagRepositoryProvider);
    var success = 0;
    final failures = <String>[];
    setState(() => _batchBusy = true);
    try {
      for (final id in ids) {
        try {
          await repository.deleteTag(id);
          success++;
        } catch (error) {
          failures.add('${byId[id] == null ? id : _labelOf(byId[id]!)}：$error');
        }
      }
    } finally {
      if (mounted) {
        setState(() => _batchBusy = false);
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _selected.clear();
      _selectionMode = false;
    });
    ref.invalidate(allTagsProvider);
    ref.invalidate(tagObjectCountsProvider);
    if (!context.mounted) {
      return;
    }
    _showBatchResult(
      context,
      action: l10n.commonDelete,
      success: success,
      failures: failures,
    );
  }

  Future<void> _batchMove(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final tags = ref.read(allTagsProvider).valueOrNull ?? const <Tag>[];
    final byId = <String, Tag>{for (final tag in tags) tag.id: tag};
    final ids = _selected.toList()..sort();

    // 目标父节点不能是被选标签自身或它的后代，否则 moveTag 会按环拒绝。
    final excluded = <String>{...ids};
    final childrenByParent = <String, List<String>>{};
    for (final tag in tags) {
      final parentId = tag.parentId;
      if (parentId != null) {
        (childrenByParent[parentId] ??= <String>[]).add(tag.id);
      }
    }
    final queue = <String>[...ids];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      for (final childId in childrenByParent[current] ?? const <String>[]) {
        if (excluded.add(childId)) {
          queue.add(childId);
        }
      }
    }
    final candidates = <Tag>[
      for (final tag in tags)
        if (!excluded.contains(tag.id)) tag,
    ]..sort((a, b) => _labelOf(a).compareTo(_labelOf(b)));

    final target = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.tagsMoveDialogTitle),
        content: SizedBox(
          width: 460,
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.vertical_align_top),
                title: Text(l10n.tagsMoveToRoot),
                onTap: () => Navigator.of(context).pop(''),
              ),
              for (final tag in candidates)
                ListTile(
                  title: Text(_labelOf(tag)),
                  onTap: () => Navigator.of(context).pop(tag.id),
                ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: l10n.commonCancel,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
    if (target == null) {
      return;
    }
    final newParentId = target.isEmpty ? null : target;
    final repository = ref.read(tagRepositoryProvider);
    var success = 0;
    final failures = <String>[];
    setState(() => _batchBusy = true);
    try {
      for (final id in ids) {
        try {
          await repository.moveTag(id, newParentId);
          success++;
        } catch (error) {
          failures.add('${byId[id] == null ? id : _labelOf(byId[id]!)}：$error');
        }
      }
    } finally {
      if (mounted) {
        setState(() => _batchBusy = false);
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _selected.clear();
      _selectionMode = false;
    });
    ref.invalidate(allTagsProvider);
    ref.invalidate(tagObjectCountsProvider);
    if (!context.mounted) {
      return;
    }
    _showBatchResult(
      context,
      action: l10n.commonMove,
      success: success,
      failures: failures,
    );
  }

  void _showBatchResult(
    BuildContext context, {
    required String action,
    required int success,
    required List<String> failures,
  }) {
    final l10n = AppLocalizations.of(context);
    final message = failures.isEmpty
        ? l10n.tagsBatchResultDone(action, success)
        : l10n.tagsBatchResultMixed(
            success,
            failures.length,
            failures.take(3).join('；'),
          );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 5)),
    );
  }
}

class _TagTile extends StatelessWidget {
  const _TagTile({
    required this.node,
    required this.tag,
    required this.hasChildren,
    required this.expanded,
    required this.showObjectCount,
    required this.selectionMode,
    required this.selected,
    required this.onSelectToggle,
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

  /// 多选模式下行首出现勾选框；点击整行 = 勾选/取消（展开仍走箭头）。
  final bool selectionMode;
  final bool selected;
  final VoidCallback onSelectToggle;
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
      // 多选时不弹单标签菜单：整行点击已经用于勾选。
      onSecondaryTap: selectionMode ? null : () => _showMenu(context),
      onLongPress: selectionMode ? null : () => _showMenu(context),
      child: ListTile(
        contentPadding: EdgeInsets.only(left: 12 + node.depth * 18.0, right: 4),
        leading: selectionMode
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: selected,
                    visualDensity: VisualDensity.compact,
                    onChanged: (_) => onSelectToggle(),
                  ),
                  if (hasChildren)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: expanded ? l10n.tagsCollapse : l10n.tagsExpand,
                      icon: Icon(expanded
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right),
                      onPressed: onToggle,
                    )
                  else
                    const SizedBox(width: 40),
                ],
              )
            : hasChildren
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
        onTap: selectionMode ? onSelectToggle : (hasChildren ? onToggle : null),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showObjectCount)
              _ObjectCountBadge(
                key: ValueKey<String>('tag-object-count-${node.tagId}'),
                count: node.objectCount,
              ),
            if (!selectionMode)
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

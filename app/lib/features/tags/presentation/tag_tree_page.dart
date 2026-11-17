import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/database/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/tags/tag_graph_query.dart';
import '../../../domain/services/tags/tag_tree_expansion.dart';
import '../../../domain/services/tags/tag_tree_sort.dart';
import '../../../domain/services/tags/tag_tree_view.dart';
import '../../../domain/services/tags/tag_usage.dart';
import '../../../l10n/app_localizations.dart';
import '../application/tag_usage_providers.dart';
import 'tag_graph_layout.dart';
import 'tag_graph_view.dart';
import 'tag_knowledge_entry_page.dart';

/// All tags, flat. The tree is assembled in memory so a rename or move only
/// needs one refresh.
final allTagsProvider = FutureProvider<List<Tag>>((ref) {
  ref.watchDatabaseRevision();
  return ref.watch(tagRepositoryProvider).getAllTags();
});

/// How many objects hang directly on each tag. The tree needs this twice: the
/// "by object count" ordering and the count badge.
///
/// It is a separate provider so the graph can render from [allTagsProvider]
/// before the counts arrive - a missing count simply means 0, it never blocks
/// the graph or turns the page into a spinner.
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

/// 标签树的展开状态（v48，2026-11-17 用户要求）：**展开**的标签 id 集合。
///
/// 空集合 = 默认全折叠。第一帧先读 [SettingsRepository.getTagTreeExpandedIds]
/// 再渲染（与 [tagTreeSortModeProvider] 同一个「不拿猜测的顺序画树」原则），
/// NULL / 坏 JSON 由 [tagTreeExpandedIdsFromStorage] 宽容翻成空集合 = 全折叠。
///
/// 用户每点一次折叠箭头、「全部打开」、「全部折叠」，以及新建/移动后需要露出
/// 新节点时都立即写回，不等写完成；写失败只记日志——保存不了的偏好不能挡住
/// 标签页，内存状态保持本次会话有效。
///
/// 搜索自动展开**不经过这里**：它只是渲染期的过滤（`tagGraphVisibleNodes`
/// 的 `onlyIds`，搜索期间忽略折叠），所以搜索结束会自然回到用户自己的状态，
/// 不会把临时展开写进库（用户 2026-11-17 明确要求）。
final tagTreeExpandedIdsProvider =
    AsyncNotifierProvider<TagTreeExpandedIdsController, Set<String>>(
  TagTreeExpandedIdsController.new,
);

/// 读持久化的展开集合并写回每一次变化。
class TagTreeExpandedIdsController extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    final String? raw =
        await ref.watch(settingsRepositoryProvider).getTagTreeExpandedIds();
    return tagTreeExpandedIdsFromStorage(raw);
  }

  /// 立即应用 [next]，然后把最终状态持久化。
  Future<void> save(Set<String> next) async {
    final snapshot = Set<String>.unmodifiable(next);
    state = AsyncData<Set<String>>(snapshot);
    try {
      await ref
          .read(settingsRepositoryProvider)
          .updateTagTreeExpandedIds(tagTreeExpandedIdsToStorage(snapshot));
    } catch (error) {
      // Losing the preference is annoying, not fatal: keep the session state.
      debugPrint('Failed to persist tag tree expansion state: $error');
    }
  }
}

/// The authoritative display/query path of a tag.
String _labelOf(Tag tag) =>
    tag.path == null || tag.path!.isEmpty ? tag.name : tag.path!;

/// 用途的中文名。只给 UI 用，所以留在 presentation，不塞进 domain 枚举。
String _tagUsageLabel(AppLocalizations l10n, TagUsage usage) => switch (usage) {
      TagUsage.time => l10n.tagUsageTime,
      TagUsage.question => l10n.tagUsageQuestion,
      TagUsage.knowledge => l10n.tagUsageKnowledge,
      TagUsage.task => l10n.tagUsageTask,
      TagUsage.flashcard => l10n.tagUsageFlashcard,
    };

/// The tag tree (blueprint 2.8; user annotation 9).
///
/// Mindnet is no longer a separate module: the tree of tags IS the map. This
/// page is therefore the single place to grow the hierarchy that Thread's goal
/// matching and filtering depend on.
///
/// 2026-11-15（用户反馈）：页面不再是一条条列表，而是 Thinking DAG 式的标签图：
///  * 节点 + 父子连线，根在左、分支向右分层展开（[layoutTagGraph]）；
///  * 有子节点的节点带折叠/展开箭头，折叠只藏后代与它们的连线；
///  * 搜索自动展开命中路径（[tagGraphSearchVisibleIds]）；
///  * **单击节点 = 打开节点设置浮窗**（居中卡片 + 变暗背景），折叠箭头仍只
///    管折叠；多选/排序/批量操作保留。
///
/// 2026-11-17（用户要求）：标签页默认**完全折叠**（所有有子节点的节点收起），
/// AppBar 提供「全部打开 / 全部折叠」；展开/折叠状态按标签 id 存进
/// `local_settings.tag_tree_expanded_ids`（[tagTreeExpandedIdsProvider]），
/// 跨页面、跨重启都恢复用户上次结束时的状态。搜索的临时展开不写库。
class TagTreePage extends ConsumerStatefulWidget {
  const TagTreePage({super.key});

  @override
  ConsumerState<TagTreePage> createState() => _TagTreePageState();
}

class _TagTreePageState extends ConsumerState<TagTreePage> {
  /// 多选模式：进入后每个节点出现勾选框，底部出现批量操作条。
  bool _selectionMode = false;
  final _selected = <String>{};

  /// 批量删除/移动执行期间为 true：操作条与各入口一律禁用，避免重入。
  bool _batchBusy = false;

  /// 搜索词（原样保存，匹配时再 trim/小写）；空串 = 不搜索。
  String _query = '';
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
    // 用途解析器（v37）：节点徽标和「用途边界」对话框都读它。加载中或读失败
    // 时退回空快照——任何标签都不声明用途，只是不显示徽标，图照常可用。
    final usageResolver = ref.watch(tagUsageResolverProvider).valueOrNull ??
        TagUsageResolver(const <TagUsageNode>[]);
    // 展开状态（v48）：先读持久化状态再画树。读失败时 valueOrNull 为空，
    // 树按出厂默认全折叠渲染而不是卡在加载圈（与排序偏好的降级一致）。
    final expandedAsync = ref.watch(tagTreeExpandedIdsProvider);
    final expandedIds = expandedAsync.valueOrNull ?? const <String>{};
    // 加载完成前按钮禁用：否则「全部打开」会拿空标签表覆盖还没读出来的状态。
    final canChangeExpansion =
        expandedAsync.hasValue && tagsAsync.hasValue && !_selectionMode;

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
                // 折叠状态（v48）：默认全折叠，一键全部打开 / 全部折叠。
                IconButton(
                  key: const ValueKey<String>('tag-tree-expand-all'),
                  tooltip: l10n.tagsExpandAll,
                  icon: const Icon(Icons.unfold_more),
                  onPressed: canChangeExpansion ? _expandAll : null,
                ),
                IconButton(
                  key: const ValueKey<String>('tag-tree-collapse-all'),
                  tooltip: l10n.tagsCollapseAll,
                  icon: const Icon(Icons.unfold_less),
                  onPressed: canChangeExpansion ? _collapseAll : null,
                ),
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
      body: modeAsync.isLoading || expandedAsync.isLoading
          ? const Center(child: CircularProgressIndicator())
          : tagsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(child: Text('$error')),
              data: (tags) {
                if (tags.isEmpty) {
                  return _buildEmptyState(context);
                }
                final tree = _treeOf(tags, objectCounts, mode);
                return _buildGraphArea(
                  context,
                  tree: tree,
                  tags: tags,
                  usageResolver: usageResolver,
                  mode: mode,
                  expandedIds: expandedIds,
                );
              },
            ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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

  /// 搜索框 + 图本体。搜索没有命中时只显示空态，不画一张空图。
  ///
  /// [expandedIds] 是持久化读出来的「展开」集合；本方法把它翻成渲染用的
  /// 「折叠」集合（有子节点且不在展开集合里 = 折叠），只为复用
  /// [tagGraphVisibleNodes] 与节点卡片的既有口径。搜索时 `onlyIds` 让
  /// [tagGraphVisibleNodes] 忽略折叠、自动摊开命中路径，且**不修改**
  /// [expandedIds]——搜索结束自然回到用户状态。
  Widget _buildGraphArea(
    BuildContext context, {
    required TagTreeView tree,
    required List<Tag> tags,
    required TagUsageResolver usageResolver,
    required TagTreeSortMode mode,
    required Set<String> expandedIds,
  }) {
    final l10n = AppLocalizations.of(context);
    final query = _query.trim();
    final searchActive = query.isNotEmpty;
    final matchIds =
        searchActive ? tagGraphSearchMatchIds(tree, query) : const <String>[];
    final matchedIds = matchIds.toSet();
    final onlyIds =
        searchActive ? tagGraphSearchVisibleIds(tree, matchIds) : null;

    if (searchActive && matchIds.isEmpty) {
      return Column(
        children: [
          _buildSearchBar(context, matchCount: 0),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.search_off,
                    size: 40,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 10),
                  Text(l10n.tagsSearchEmpty),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final collapsedIds = _collapsedIdsOf(tree, expandedIds);
    final visible = tagGraphVisibleNodes(
      tree,
      collapsedIds: collapsedIds,
      onlyIds: onlyIds,
    );
    final layout = layoutTagGraph(visible);
    final highlightedIds =
        searchActive ? (onlyIds ?? const <String>{}) : const <String>{};

    Widget buildNode(
      BuildContext nodeContext,
      TagGraphNodePlacement placement,
    ) {
      final node = placement.node;
      final tag = tags.firstWhere((candidate) => candidate.id == node.tagId);
      final declaredUsages =
          usageResolver.declaredFor(node.tagId) ?? const <TagUsage>{};
      return TagGraphNodeCard(
        key: ValueKey<String>('tag-graph-node-${node.tagId}'),
        node: node,
        collapsed: collapsedIds.contains(node.tagId),
        showObjectCount: mode == TagTreeSortMode.byObjectCount,
        selectionMode: _selectionMode,
        selected: _selected.contains(node.tagId),
        matched: matchedIds.contains(node.tagId),
        declaredUsageLabels: <String>[
          for (final usage in declaredUsages) _tagUsageLabel(l10n, usage),
        ],
        onTap: _selectionMode
            ? () => _toggleSelected(node.tagId)
            : () => _showNodeSettings(nodeContext, tag),
        onToggle: () => _toggleCollapsed(expandedIds, node.tagId),
        onSelectToggle: () => _toggleSelected(node.tagId),
        onLongPress: _selectionMode
            ? () {}
            : () => _showNodeSettings(nodeContext, tag),
      );
    }

    return Column(
      children: [
        _buildSearchBar(context, matchCount: matchIds.length),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final canvas = TagGraphCanvas(
                layout: layout,
                highlightedIds: highlightedIds,
                nodeBuilder: buildNode,
              );
              if (!layout.fitsWidth(constraints.maxWidth)) {
                // 图比一屏宽：不塞横向滚动条，改成可拖动/缩放（仍不出现
                // Axis.horizontal 的滚动容器）。
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      child: Text(
                        l10n.tagsGraphPanHint,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                    ),
                    Expanded(
                      child: InteractiveViewer(
                        constrained: false,
                        minScale: 0.35,
                        maxScale: 2.5,
                        boundaryMargin: const EdgeInsets.all(120),
                        child: canvas,
                      ),
                    ),
                  ],
                );
              }
              return SingleChildScrollView(
                key: const ValueKey<String>('tag-graph-scroll'),
                padding: const EdgeInsets.only(bottom: 24),
                child: SizedBox(
                  width: constraints.maxWidth,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: canvas,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar(BuildContext context, {required int matchCount}) {
    final l10n = AppLocalizations.of(context);
    final query = _query.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: TextField(
        key: const ValueKey<String>('tag-graph-search'),
        controller: _searchController,
        onChanged: (value) => setState(() => _query = value),
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search),
          hintText: l10n.tagsSearchHint,
          helperText: query.isEmpty || matchCount == 0
              ? null
              : l10n.tagsSearchCount(matchCount),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: l10n.tagsClearSearch,
                  icon: const Icon(Icons.close),
                  onPressed: _clearSearch,
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  // --- 展开/折叠状态（v48）-------------------------------------------------
  //
  // 页面自己不再存「折叠集合」：状态的唯一来源是 [tagTreeExpandedIdsProvider]
  // 里的「展开」集合，渲染时再翻成折叠集合（[_collapsedIdsOf]）。这样搜索、
  // 排序、刷新标签表都不会各存一份互相打架的状态；每次修改都立刻写库，失败
  // 只记日志（由 controller 负责）。

  /// 渲染用的折叠集合：有子节点、但不在展开集合里的标签。
  Set<String> _collapsedIdsOf(TagTreeView tree, Set<String> expandedIds) {
    final collapsed = <String>{};
    for (final node in tree.preorder) {
      if (node.children.isNotEmpty && !expandedIds.contains(node.tagId)) {
        collapsed.add(node.tagId);
      }
    }
    return collapsed;
  }

  Set<String> _expandedIdsNow() =>
      ref.read(tagTreeExpandedIdsProvider).valueOrNull ?? const <String>{};

  /// 折叠箭头的唯一入口：翻转一个标签的展开状态并立即持久化。
  void _toggleCollapsed(Set<String> expandedIds, String tagId) {
    final next = <String>{...expandedIds};
    if (!next.remove(tagId)) {
      next.add(tagId);
    }
    ref.read(tagTreeExpandedIdsProvider.notifier).save(next);
  }

  /// AppBar「全部打开」：所有标签都记成展开。把叶子也记进去是故意的——叶子
  /// 以后长出子标签时，用户刚表达过的「全开」仍然成立。
  void _expandAll() {
    final tags = ref.read(allTagsProvider).valueOrNull ?? const <Tag>[];
    ref.read(tagTreeExpandedIdsProvider.notifier).save(
      <String>{for (final tag in tags) tag.id},
    );
  }

  /// AppBar「全部折叠」：清空展开集合（空集合就是出厂默认）。
  void _collapseAll() {
    ref.read(tagTreeExpandedIdsProvider.notifier).save(const <String>{});
  }

  /// 新建子标签 / 移动完成后必须让结果可见：把节点记成展开。
  void _expandTag(String tagId) {
    final current = _expandedIdsNow();
    if (current.contains(tagId)) {
      return;
    }
    ref
        .read(tagTreeExpandedIdsProvider.notifier)
        .save(<String>{...current, tagId});
  }

  /// 删掉标签后把它从展开集合里清掉，避免集合里积累已不存在的 id。
  void _forgetExpandedTags(Iterable<String> tagIds) {
    final current = _expandedIdsNow();
    final next = <String>{...current}..removeAll(tagIds);
    if (next.length == current.length) {
      return;
    }
    ref.read(tagTreeExpandedIdsProvider.notifier).save(next);
  }

  /// 节点设置浮窗（用户 2026-11-15 补充要求）：单击节点打开，居中卡片 +
  /// modal barrier；折叠箭头不经过这里。
  void _showNodeSettings(BuildContext context, Tag tag) {
    final l10n = AppLocalizations.of(context);
    final resolver = ref.read(tagUsageResolverProvider).valueOrNull ??
        TagUsageResolver(const <TagUsageNode>[]);
    final declared = resolver.declaredFor(tag.id) ?? const <TagUsage>{};
    showDialog<void>(
      context: context,
      builder: (_) => TagNodeSettingsDialog(
        label: _labelOf(tag),
        declaredUsageText: declared.isEmpty
            ? ''
            : <String>[
                for (final usage in declared) _tagUsageLabel(l10n, usage),
              ].join('、'),
        onOpenKnowledgeEntry: () => _openKnowledgeEntry(context, tag),
        onAddChild: () => _addTag(context, parent: tag),
        onRename: () => _renameTag(context, tag),
        onMove: () => _moveTag(context, tag),
        onUsage: () => _editTagUsages(context, tag),
        onDelete: () => _deleteTag(context, tag),
      ),
    );
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
      // 新子节点必须看得见：把父节点记成展开，而不是悄悄加一个隐藏节点。
      _expandTag(parent.id);
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
    _forgetExpandedTags(<String>[tag.id]);
    _selected.remove(tag.id);
    ref.invalidate(allTagsProvider);
    ref.invalidate(tagObjectCountsProvider);
  }

  /// 单标签移动（节点设置浮窗新增；旧列表只有批量移动）。
  ///
  /// 目标列表与批量移动同口径：排除自己与全部后代，避免把标签挂进自己的
  /// 子树里（仓库 moveTag 会按环拒绝，这里先挡掉不给用户点）。
  Future<void> _moveTag(BuildContext context, Tag tag) async {
    final l10n = AppLocalizations.of(context);
    final tags = ref.read(allTagsProvider).valueOrNull ?? const <Tag>[];
    final excluded = _excludedIds(tags, <String>{tag.id});
    final candidates = <Tag>[
      for (final candidate in tags)
        if (!excluded.contains(candidate.id)) candidate,
    ]..sort((a, b) => _labelOf(a).compareTo(_labelOf(b)));

    final target = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.tagsMoveSingleTitle(_labelOf(tag))),
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
              for (final candidate in candidates)
                ListTile(
                  title: Text(_labelOf(candidate)),
                  onTap: () => Navigator.of(context).pop(candidate.id),
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
    try {
      await ref.read(tagRepositoryProvider).moveTag(tag.id, newParentId);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
      return;
    }
    if (!mounted) {
      return;
    }
    if (newParentId != null) {
      // 移动结果要看得见：展开新父节点。
      _expandTag(newParentId);
    }
    ref.invalidate(allTagsProvider);
    ref.invalidate(tagObjectCountsProvider);
  }

  /// 标签作为知识入口（B8）：打开这个标签挂着的题 / 卡 / 任务。
  ///
  /// 只传 id 与显示名：页面自己按 `TagKnowledgeIndex` 只读查询，标签在打开
  /// 之前被删掉时页面会如实说「已不存在」，这里不做存在性猜测。
  void _openKnowledgeEntry(BuildContext context, Tag tag) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TagKnowledgeEntryPage(
          tagId: tag.id,
          tagLabel: _labelOf(tag),
        ),
      ),
    );
  }

  /// 「用途边界」对话框（v37；docs/REVIEW_FEEDBACK.md §10/§11）。
  ///
  /// 勾选框初值是**本级声明**（不是继承来的生效值）：全不勾 = 这一级不声明，
  /// 继续继承祖先；保存空集合会把 usage_codes 写回 NULL。
  Future<void> _editTagUsages(BuildContext context, Tag tag) async {
    final l10n = AppLocalizations.of(context);
    final resolver = ref.read(tagUsageResolverProvider).valueOrNull ??
        TagUsageResolver(const <TagUsageNode>[]);
    final selected = <TagUsage>{...?resolver.declaredFor(tag.id)};
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l10n.tagUsageDialogTitle),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.tagUsageInheritHint,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    l10n.tagUsageEntrySubtitle(resolver.declaredTagCount),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  for (final usage in TagUsage.values)
                    CheckboxListTile(
                      key: ValueKey<String>('tag-usage-check-${usage.code}'),
                      value: selected.contains(usage),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(_tagUsageLabel(l10n, usage)),
                      onChanged: (checked) => setState(() {
                        if (checked ?? false) {
                          selected.add(usage);
                        } else {
                          selected.remove(usage);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.commonSave),
            ),
          ],
        ),
      ),
    );
    if (saved != true) {
      return;
    }
    try {
      await setTagUsages(ref, tag.id, selected);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
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

  /// [ids] 自身 + 全部后代（防环：每个子节点只入队一次）。
  Set<String> _excludedIds(List<Tag> tags, Iterable<String> ids) {
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
    return excluded;
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
    final deletedIds = <String>[];
    setState(() => _batchBusy = true);
    try {
      for (final id in ids) {
        try {
          await repository.deleteTag(id);
          success++;
          deletedIds.add(id);
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
    _forgetExpandedTags(deletedIds);
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
    final excluded = _excludedIds(tags, ids);
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
    if (newParentId != null) {
      _expandTag(newParentId);
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

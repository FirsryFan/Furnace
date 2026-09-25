import 'package:flutter/material.dart';
import 'package:furnace/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database.dart';
import '../../../data/repositories/repository_providers.dart';

final mindMapsProvider = FutureProvider<List<MindMap>>((ref) {
  return ref.watch(mindMapRepositoryProvider).getMindMaps();
});

final selectedMapIdProvider = StateProvider<String?>((ref) => null);

final mindNodesProvider =
    FutureProvider.family<List<MindNode>, String>((ref, mapId) {
  return ref.watch(mindMapRepositoryProvider).getNodesForMap(mapId);
});

/// Mind Map module: basic map list + node tree.
class MindMapPage extends ConsumerWidget {
  const MindMapPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final mapsAsync = ref.watch(mindMapsProvider);
    final selectedMapId = ref.watch(selectedMapIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navMindMap),
        actions: [
          IconButton(
            tooltip: l10n.mindMapNewMap,
            icon: const Icon(Icons.add),
            onPressed: () => _createMap(context, ref),
          ),
        ],
      ),
      body: mapsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('$error')),
        data: (maps) {
          if (maps.isEmpty) {
            return Center(
              child: FilledButton.icon(
                onPressed: () => _createMap(context, ref),
                icon: const Icon(Icons.add),
                label: Text(l10n.mindMapNewMap),
              ),
            );
          }

          final selectedMap = maps.firstWhere(
            (m) => m.id == selectedMapId,
            orElse: () => maps.first,
          );

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 240,
                child: ListView(
                  children: [
                    for (final map in maps)
                      ListTile(
                        selected: map.id == selectedMap.id,
                        title: Text(map.title),
                        onTap: () {
                          ref.read(selectedMapIdProvider.notifier).state =
                              map.id;
                        },
                      ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _MapNodesView(
                  mapId: selectedMap.id,
                  mapTitle: selectedMap.title,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createMap(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.mindMapNewMap),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.commonName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) {
      return;
    }
    await ref.read(mindMapRepositoryProvider).createMindMap(name);
    ref.invalidate(mindMapsProvider);
  }
}

class _MapNodesView extends ConsumerWidget {
  const _MapNodesView({required this.mapId, required this.mapTitle});

  final String mapId;
  final String mapTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nodesAsync = ref.watch(mindNodesProvider(mapId));

    return Scaffold(
      appBar: AppBar(
        title: Text(mapTitle),
        actions: [
          IconButton(
            tooltip: l10n.mindMapAddNode,
            icon: const Icon(Icons.add),
            onPressed: () => _addNode(context, ref, parentId: null),
          ),
        ],
      ),
      body: nodesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('$error')),
        data: (nodes) {
          if (nodes.isEmpty) {
            return Center(
              child: FilledButton.icon(
                onPressed: () => _addNode(context, ref, parentId: null),
                icon: const Icon(Icons.add),
                label: Text(l10n.mindMapAddNode),
              ),
            );
          }
          final rootNodes = nodes.where((n) => n.parentId == null).toList();
          return ListView(
            children: [
              for (final node in rootNodes)
                _NodeTile(
                  node: node,
                  allNodes: nodes,
                  onAddChild: (parentId) =>
                      _addNode(context, ref, parentId: parentId),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addNode(
    BuildContext context,
    WidgetRef ref, {
    required String? parentId,
  }) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.mindMapAddNode),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.commonTitle),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    if (text == null || text.isEmpty) {
      return;
    }
    await ref
        .read(mindMapRepositoryProvider)
        .addNode(mapId: mapId, parentId: parentId, text: text);
    ref.invalidate(mindNodesProvider(mapId));
  }
}

class _NodeTile extends ConsumerWidget {
  const _NodeTile({
    required this.node,
    required this.allNodes,
    required this.onAddChild,
  });

  final MindNode node;
  final List<MindNode> allNodes;
  final ValueChanged<String?> onAddChild;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final children = allNodes.where((n) => n.parentId == node.id).toList();
    final siblings = allNodes
        .where((n) => n.parentId == node.parentId)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final siblingIndex = siblings.indexWhere((n) => n.id == node.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          dense: true,
          leading: node.isTag
              ? const Icon(Icons.sell_outlined)
              : const Icon(Icons.circle_outlined),
          title: Text(node.nodeText),
          subtitle: (node.notes == null || node.notes!.isEmpty)
              ? null
              : Text(node.notes!),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (siblingIndex > 0)
                IconButton(
                  tooltip: l10n.mindMapMoveUp,
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: () => _moveNode(context, ref, up: true),
                ),
              if (siblingIndex >= 0 && siblingIndex < siblings.length - 1)
                IconButton(
                  tooltip: l10n.mindMapMoveDown,
                  icon: const Icon(Icons.arrow_downward),
                  onPressed: () => _moveNode(context, ref, up: false),
                ),
              if (children.isNotEmpty)
                IconButton(
                  icon: Icon(
                    node.collapsed
                        ? Icons.expand_more
                        : Icons.expand_less,
                  ),
                  onPressed: () => _toggleCollapsed(context, ref),
                ),
              IconButton(
                tooltip: l10n.mindMapPromoteTag,
                icon: const Icon(Icons.sell_outlined),
                onPressed: node.isTag
                    ? null
                    : () => _promoteToTag(context, ref),
              ),
              IconButton(
                tooltip: l10n.mindMapPromoteTask,
                icon: const Icon(Icons.checklist_outlined),
                onPressed: () => _promoteToTask(context, ref),
              ),
              IconButton(
                tooltip: l10n.mindMapAddNode,
                icon: const Icon(Icons.add),
                onPressed: () => onAddChild(node.id),
              ),
              IconButton(
                tooltip: l10n.mindMapEditNotes,
                icon: const Icon(Icons.notes),
                onPressed: () => _editNotes(context, ref),
              ),
              IconButton(
                tooltip: l10n.mindMapRenameNode,
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _renameNode(context, ref),
              ),
              IconButton(
                tooltip: l10n.commonDelete,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteNode(context, ref),
              ),
            ],
          ),
        ),
        if (!node.collapsed)
          for (final child in children)
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: _NodeTile(
                node: child,
                allNodes: allNodes,
                onAddChild: onAddChild,
              ),
            ),
      ],
    );
  }

  Future<void> _moveNode(
    BuildContext context,
    WidgetRef ref, {
    required bool up,
  }) async {
    await ref
        .read(mindMapRepositoryProvider)
        .moveNode(node.id, up: up);
    ref.invalidate(mindNodesProvider(node.mapId));
  }

  Future<void> _toggleCollapsed(BuildContext context, WidgetRef ref) async {
    await ref
        .read(mindMapRepositoryProvider)
        .updateNode(node.id, collapsed: !node.collapsed);
    ref.invalidate(mindNodesProvider(node.mapId));
  }

  Future<void> _promoteToTask(BuildContext context, WidgetRef ref) async {
    final task = await ref
        .read(taskRepositoryProvider)
        .createTask(title: node.nodeText);
    if (node.isTag && node.tagId != null) {
      await ref.read(tagRepositoryProvider).addTagToObject(
            tagId: node.tagId!,
            objectType: 'task',
            objectId: task.id,
          );
    }
    if (context.mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${node.nodeText} → ${l10n.mindMapPromoteTask}')),
      );
    }
  }

  Future<void> _promoteToTag(BuildContext context, WidgetRef ref) async {
    final tag = await ref
        .read(tagRepositoryProvider)
        .createTag(name: node.nodeText, sourceNodeId: node.id);
    await ref
        .read(mindMapRepositoryProvider)
        .updateNode(node.id, isTag: true, tagId: tag.id);
    ref.invalidate(mindNodesProvider(node.mapId));
  }

  Future<void> _editNotes(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: node.notes ?? '');
    final notes = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.mindMapEditNotes),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          decoration: InputDecoration(labelText: l10n.commonContent),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    if (notes == null) {
      return;
    }
    await ref
        .read(mindMapRepositoryProvider)
        .updateNode(
          node.id,
          notes: notes.isEmpty ? null : notes,
          clearNotes: notes.isEmpty,
        );
    ref.invalidate(mindNodesProvider(node.mapId));
  }

  Future<void> _renameNode(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: node.nodeText);
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.mindMapRenameNode),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.commonTitle),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    if (text == null || text.isEmpty) {
      return;
    }
    await ref.read(mindMapRepositoryProvider).updateNode(node.id, text: text);
    ref.invalidate(mindNodesProvider(node.mapId));
  }

  Future<void> _deleteNode(BuildContext context, WidgetRef ref) async {
    await ref.read(mindMapRepositoryProvider).deleteNode(node.id);
    ref.invalidate(mindNodesProvider(node.mapId));
  }
}

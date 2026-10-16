import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/knowledge_edge_repository.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../l10n/app_localizations.dart';
import 'knowledge_edge_page.dart';

/// 一个知识点自己的线索边（出边 + 入边），摆在知识点详情里。
///
/// [externalId] 是 `knowledge_points.external_id`。为 null 时（手写的知识点从来没进过图）
/// **不说"它没有边"**，而是说清楚"它不在图里" —— 两句话看着像，意思完全不同：
/// 前者是"图里查过、确实没有"，后者是"根本查不到它"。
///
/// 从这里还能**手写**一条边（`origin: 'manual'`）与删掉手写的边：材料确认那条路负责
/// "材料里写的连接"，这一段负责"用户自己看出来的连接"。删只放行手写的 ——
/// 材料边删了，材料里写了什么就和库里对不上了。
class KnowledgePointEdgesSection extends ConsumerWidget {
  const KnowledgePointEdgesSection({required this.externalId, super.key});

  final String? externalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final id = externalId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(
              Icons.hub_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(l10n.knowledgeEdges, style: theme.textTheme.titleMedium),
          ],
        ),
        if (id == null)
          _Note(text: l10n.knowledgePointEdgesNotInGraph)
        else
          ref.watch(knowledgePointEdgesProvider(id)).when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                error: (error, stack) => _Note(text: '$error'),
                data: (edges) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (edges.isEmpty)
                      _Note(text: l10n.knowledgePointEdgesEmpty)
                    else
                      for (final edge in edges)
                        _EdgeRow(
                          edge: edge,
                          pointId: id,
                          // 只有手写边能从这里删：材料边要回材料那一步。
                          onDelete: edge.origin == 'manual'
                              ? () => _delete(context, ref, id, edge)
                              : null,
                        ),
                    TextButton.icon(
                      onPressed: () => _add(context, ref, id),
                      icon: const Icon(Icons.add, size: 16),
                      label: Text(l10n.knowledgeEdgeAdd),
                    ),
                  ],
                ),
              ),
      ],
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref, String pointId) async {
    final message = await showDialog<String>(
      context: context,
      builder: (_) => _AddEdgeDialog(pointId: pointId),
    );
    if (message == null || !context.mounted) {
      return;
    }
    _refresh(ref, pointId);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    String pointId,
    KnowledgeEdgeView edge,
  ) async {
    final l10n = AppLocalizations.of(context);
    final label = '${knowledgeEdgeEndpointLabel(edge.fromTitle, edge.fromId)}'
        ' → '
        '${knowledgeEdgeEndpointLabel(edge.toTitle, edge.toId)}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.knowledgeEdgeDeleteConfirm),
        content: Text(label),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    final outcome = await ref
        .read(knowledgeEdgeRepositoryProvider)
        .deleteManualEdge(edge.id);
    if (!context.mounted) {
      return;
    }
    _refresh(ref, pointId);
    final message = switch (outcome) {
      ManualEdgeDeleteOutcome.deleted => l10n.knowledgeEdgeDeleted,
      ManualEdgeDeleteOutcome.notFound => l10n.knowledgeEdgeNotFound,
      ManualEdgeDeleteOutcome.notManual => l10n.knowledgeEdgeNotManual,
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// 写完自己这一处重读：这一段刚动过那张表，不等数据库 revision 兜一圈
  /// （revision 是给"别的页面写的"用的）。
  void _refresh(WidgetRef ref, String pointId) {
    ref.invalidate(knowledgePointEdgesProvider(pointId));
    ref.invalidate(knowledgeEdgeEndpointsProvider);
    ref.invalidate(knowledgeEdgesProvider);
  }
}

/// 手写一条边：选方向（它指向 / 指向它）和另一端，两端都必须在图里。
class _AddEdgeDialog extends ConsumerStatefulWidget {
  const _AddEdgeDialog({required this.pointId});

  final String pointId;

  @override
  ConsumerState<_AddEdgeDialog> createState() => _AddEdgeDialogState();
}

class _AddEdgeDialogState extends ConsumerState<_AddEdgeDialog> {
  String _direction = 'out';
  String? _other;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final endpoints = ref.watch(knowledgeEdgeEndpointsProvider);

    return AlertDialog(
      title: Text(l10n.knowledgeEdgeAddTitle),
      content: SizedBox(
        width: 420,
        child: endpoints.when(
          loading: () => const SizedBox(
            height: 60,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (error, stack) => Text('$error'),
          data: (points) {
            final others = <KnowledgeEdgeEndpoint>[
              for (final point in points)
                if (point.externalId != widget.pointId) point,
            ];
            if (others.isEmpty) {
              return Text(l10n.knowledgeEdgeNoOtherPoints);
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RadioGroup<String>(
                  groupValue: _direction,
                  onChanged: (value) => setState(() => _direction = value!),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RadioListTile<String>(
                        value: 'out',
                        title: Text(l10n.knowledgeEdgeDirectionOutgoing),
                      ),
                      RadioListTile<String>(
                        value: 'in',
                        title: Text(l10n.knowledgeEdgeDirectionIncoming),
                      ),
                    ],
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _other,
                  decoration:
                      InputDecoration(labelText: l10n.knowledgeEdgePickOther),
                  items: <DropdownMenuItem<String>>[
                    for (final point in others)
                      DropdownMenuItem<String>(
                        value: point.externalId,
                        child: Text(point.title),
                      ),
                  ],
                  onChanged: (value) => setState(() => _other = value),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _other == null ? null : _submit,
          child: Text(l10n.commonConfirm),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final other = _other!;
    final fromId = _direction == 'out' ? widget.pointId : other;
    final toId = _direction == 'out' ? other : widget.pointId;

    final result = await ref
        .read(knowledgeEdgeRepositoryProvider)
        .createManualEdge(fromId: fromId, toId: toId);
    if (!mounted) {
      return;
    }
    final message = switch (result.outcome) {
      ManualEdgeOutcome.created => l10n.knowledgeEdgeCreated,
      ManualEdgeOutcome.alreadyExists => l10n.knowledgeEdgeAlreadyExists(
          knowledgeEdgeOriginLabel(
            l10n,
            result.existingOrigin ?? 'material',
          ),
        ),
      ManualEdgeOutcome.unknownEndpoint => l10n.knowledgeEdgeEndpointMissing,
      ManualEdgeOutcome.samePoint => l10n.knowledgeEdgeSamePoint,
    };
    Navigator.pop(context, message);
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 6, 0, 6),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 一条边，站在这个知识点的角度说方向：出边写"它指向谁"，入边写"谁指向它"。
class _EdgeRow extends StatelessWidget {
  const _EdgeRow({
    required this.edge,
    required this.pointId,
    this.onDelete,
  });

  final KnowledgeEdgeView edge;
  final String pointId;

  /// 非空时才显示删除：只有手写边给得起这个回调（材料边要回材料那一步）。
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final outgoing = edge.fromId == pointId;
    final other = outgoing
        ? knowledgeEdgeEndpointLabel(edge.toTitle, edge.toId)
        : knowledgeEdgeEndpointLabel(edge.fromTitle, edge.fromId);

    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 2, 0, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            outgoing ? Icons.arrow_forward : Icons.arrow_back,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  outgoing
                      ? l10n.knowledgePointEdgesOutgoing(other)
                      : l10n.knowledgePointEdgesIncoming(other),
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  knowledgeEdgeOriginLabel(l10n, edge.origin),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (onDelete != null)
            IconButton(
              tooltip: l10n.knowledgeEdgeDeleteTooltip,
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}

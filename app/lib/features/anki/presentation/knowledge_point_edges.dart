import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/knowledge_edge_repository.dart';
import '../../../l10n/app_localizations.dart';
import 'knowledge_edge_page.dart';

/// 一个知识点自己的线索边（出边 + 入边），摆在知识点详情里。
///
/// [externalId] 是 `knowledge_points.external_id`。为 null 时（手写的知识点从来没进过图）
/// **不说"它没有边"**，而是说清楚"它不在图里" —— 两句话看着像，意思完全不同：
/// 前者是"图里查过、确实没有"，后者是"根本查不到它"。
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
                data: (edges) => edges.isEmpty
                    ? _Note(text: l10n.knowledgePointEdgesEmpty)
                    : Column(
                        children: [
                          for (final edge in edges)
                            _EdgeRow(edge: edge, pointId: id),
                        ],
                      ),
              ),
      ],
    );
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
  const _EdgeRow({required this.edge, required this.pointId});

  final KnowledgeEdgeView edge;
  final String pointId;

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
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/repositories/knowledge_edge_repository.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../l10n/app_localizations.dart';

/// 全部线索边（新的在前）。写完就重读：边的写者在别处（材料确认、或是手写那一段），
/// 所以这一页要靠数据库 revision 自己醒过来。
final knowledgeEdgesProvider = FutureProvider<List<KnowledgeEdgeView>>((ref) {
  ref.watchDatabaseRevision();
  return ref.watch(knowledgeEdgeRepositoryProvider).all();
});

/// 某个知识点自己的线索边（出边 + 入边）。键是 `knowledge_points.external_id`。
final knowledgePointEdgesProvider =
    FutureProvider.family<List<KnowledgeEdgeView>, String>((ref, externalId) {
  ref.watchDatabaseRevision();
  return ref.watch(knowledgeEdgeRepositoryProvider).forPoint(externalId);
});

/// 图里的端点（有 `external_id` 的知识点）：手写边那个选择框的候选。
final knowledgeEdgeEndpointsProvider =
    FutureProvider<List<KnowledgeEdgeEndpoint>>((ref) {
  ref.watchDatabaseRevision();
  return ref.watch(knowledgeEdgeRepositoryProvider).graphPoints();
});

/// 端点的显示名：库里有点就用标题，没有就照实显示 id（不编一个名字）。
String knowledgeEdgeEndpointLabel(String? title, String id) => title ?? id;

/// `origin` 是人话，认不出来的关系名照实显示（不硬塞进"材料"那一类）。
String knowledgeEdgeOriginLabel(AppLocalizations l10n, String origin) =>
    switch (origin) {
      'contains' => l10n.knowledgeEdgesOriginContains,
      'produce' => l10n.knowledgeEdgesOriginProduce,
      'topic' => l10n.knowledgeEdgesOriginTopic,
      'manual' => l10n.knowledgeEdgesOriginManual,
      'material' => l10n.knowledgeEdgesOriginMaterial,
      _ => origin,
    };

/// 线索边的只读清单（`knowledge_edges`；`docs/MINDNET_ROADMAP.md` §2-C ④）。
///
/// 轮次六十八让连接**能落库**，这一页让它们**能被看见** —— 一张只有写者、
/// 没有任何读者的表，等于把"资料进图"这件事藏进库里。这一页只读：
/// 不建边、不删边、不改 `ls`；它只把库里的事实（含未标定与缺端）照说。
class KnowledgeEdgePage extends ConsumerWidget {
  const KnowledgeEdgePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final edgesAsync = ref.watch(knowledgeEdgesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.knowledgeEdges),
        actions: [
          IconButton(
            tooltip: l10n.commonRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(knowledgeEdgesProvider),
          ),
        ],
      ),
      body: edgesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('$error')),
        data: (edges) {
          if (edges.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.knowledgeEdgesEmpty,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              _Header(count: edges.length, note: l10n.knowledgeEdgesIntro),
              for (final edge in edges) _EdgeTile(edge: edge),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.count, required this.note});

  final int count;
  final String note;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hub_outlined,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                l10n.knowledgeEdgesCount(count),
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            note,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _EdgeTile extends StatelessWidget {
  const _EdgeTile({required this.edge});

  final KnowledgeEdgeView edge;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final parts = <String>[
      knowledgeEdgeOriginLabel(l10n, edge.origin),
      if (edge.source != null && edge.source!.isNotEmpty) edge.source!,
      if (edge.ls != null)
        edge.lsCalibrated
            ? l10n.knowledgeEdgesLsCalibrated(edge.ls!.toStringAsFixed(2))
            : l10n.knowledgeEdgesLs(edge.ls!.toStringAsFixed(2))
      else
        l10n.knowledgeEdgesNoLs,
      if (edge.hasMissingEndpoint) l10n.knowledgeEdgesMissingEnd,
    ];

    return ListTile(
      dense: true,
      leading: Icon(
        Icons.arrow_forward,
        size: 18,
        color: theme.colorScheme.primary,
      ),
      title: Text(
        '${knowledgeEdgeEndpointLabel(edge.fromTitle, edge.fromId)} → '
        '${knowledgeEdgeEndpointLabel(edge.toTitle, edge.toId)}',
      ),
      subtitle: Text(parts.join(' · ')),
    );
  }
}

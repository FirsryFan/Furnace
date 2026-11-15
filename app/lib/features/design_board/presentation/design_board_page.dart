import 'package:flutter/material.dart';

import '../data/design_board_repository.dart';
import '../domain/design_board.dart';
import 'content_sample_page.dart';
import 'sample_badges.dart';

/// Read-only "design & content board" page.
///
/// Shows the design reference library trimmed to 47 entries, grouped by the
/// five-level taxonomy (L1 / L2-A / L2-B / L2-C / L3). Each entry exposes the
/// name, type, status, one-sentence user verdict, and an expandable mechanism
/// summary. All data comes from the bundled local asset; the page performs no
/// writes, starts no network request and touches no database table.
///
/// The labels are Chinese on purpose: the content is lifted verbatim from the
/// Chinese design reference library, so translating the chrome alone would mix
/// two languages. (`GaokaoLibraryPage` sets the same precedent.)
class DesignBoardPage extends StatefulWidget {
  const DesignBoardPage({
    super.key,
    this.source = const AssetDesignBoardSource(),
  });

  /// Injectable so widget tests do not depend on the Flutter asset bundle.
  final DesignBoardSource source;

  @override
  State<DesignBoardPage> createState() => _DesignBoardPageState();
}

class _DesignBoardPageState extends State<DesignBoardPage> {
  late Future<DesignBoardData> _data;

  @override
  void initState() {
    super.initState();
    _data = widget.source.load();
  }

  void _reload() {
    setState(() {
      _data = widget.source.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设计与内容板块')),
      body: FutureBuilder<DesignBoardData>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorView(
              message: '${snapshot.error}',
              onRetry: _reload,
            );
          }
          return _BoardView(data: snapshot.data!);
        },
      ),
    );
  }
}

class _BoardView extends StatelessWidget {
  const _BoardView({required this.data});

  final DesignBoardData data;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      _HeaderCard(data: data),
      for (final sample in data.realContentSamples) ...[
        const SizedBox(height: 12),
        _OptionalCard(
          title: sample.title,
          card: sample,
          unfinishedReason: null,
          onOpen: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => ContentSamplePage(sample: sample),
            ),
          ),
        ),
      ],
      const SizedBox(height: 12),
      _OptionalCard(
        title: '能力矩阵示例（L2-A）',
        card: data.abilityMatrix,
        unfinishedReason: data.unfinished['abilityMatrix'],
      ),
      const SizedBox(height: 8),
      _OptionalCard(
        title: '内容 schema 示例（L2-B）',
        card: data.contentSchema,
        unfinishedReason: data.unfinished['contentSchema'],
      ),
    ];

    for (final layer in data.layers) {
      final entries = data.entriesOf(layer.id);
      children.add(_LayerHeader(layer: layer, count: entries.length));
      for (final entry in entries) {
        children.add(_EntryCard(entry: entry));
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: children,
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.data});

  final DesignBoardData data;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final counts = data.statusCounts;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.menu_book_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'FURNACE 设计与内容参考库（只读）',
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '来源：${data.sourceDocument} · 本地 JSON asset（不联网、不写库）',
              style: text.bodySmall,
            ),
            if (data.sourceNote.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(data.sourceNote, style: text.bodySmall),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _CountChip(label: '${data.entryCount} 条'),
                _CountChip(label: '${data.layers.length} 层'),
                for (final status in DesignBoardData.statusOrder)
                  _CountChip(label: '$status ${counts[status] ?? 0}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders a read-only example card, or an explicit "数据未完成" placeholder.
///
/// Cards flagged `expandable` (the real-content sample) keep their warning
/// flags visible and hide the longer details behind a tap, so a reviewer sees
/// "答案来自 Source / DAG 未独立审核 / private_study_only" without scrolling
/// into a wall of text.
class _OptionalCard extends StatelessWidget {
  const _OptionalCard({
    required this.title,
    required this.card,
    required this.unfinishedReason,
    this.onOpen,
  });

  final String title;
  final DesignBoardCard? card;
  final String? unfinishedReason;

  /// When set (real content samples), shows an "打开完整内容" button that opens
  /// [ContentSamplePage].
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final card = this.card;
    if (card == null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.hourglass_empty),
          title: Text(title),
          subtitle: Text(unfinishedReason ?? '数据未完成'),
          trailing: const SampleStatusChip(status: '数据未完成'),
        ),
      );
    }
    final cardTitle = card.title.isEmpty ? title : card.title;
    if (card.expandable) {
      return Card(
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          title: Row(
            children: [
              Expanded(child: Text(cardTitle, style: text.titleSmall)),
              if (card.statusLabel.isNotEmpty)
                SampleStatusChip(status: card.statusLabel),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final chip in card.chips) SampleFlagChip(label: chip),
                  ],
                ),
                if (onOpen != null) ...[
                  const SizedBox(height: 2),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: Key('open-sample-${card.id}'),
                      onPressed: onOpen,
                      icon: const Icon(Icons.article_outlined, size: 18),
                      label: const Text('打开完整内容'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          children: [
            for (final line in card.lines)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('• $line', style: text.bodySmall),
              ),
          ],
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(cardTitle, style: text.titleSmall),
                ),
                if (card.statusLabel.isNotEmpty)
                  SampleStatusChip(status: card.statusLabel),
              ],
            ),
            if (card.subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(card.subtitle, style: text.bodySmall),
            ],
            if (card.chips.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final chip in card.chips) _CountChip(label: chip),
                ],
              ),
            ],
            for (final line in card.lines) ...[
              const SizedBox(height: 6),
              Text('• $line', style: text.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _LayerHeader extends StatelessWidget {
  const _LayerHeader({required this.layer, required this.count});

  final DesignLayer layer;
  final int count;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  layer.label,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _CountChip(label: '$count 条'),
            ],
          ),
          const SizedBox(height: 2),
          Text(layer.description, style: text.bodySmall),
        ],
      ),
    );
  }
}

/// One entry: collapsed = name / type / status / one-sentence user verdict;
/// expanded = mechanism summary, reference status, evidence and source.
class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry});

  final DesignEntry entry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: Key('design-entry-${entry.id}'),
        tilePadding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Row(
          children: [
            Expanded(child: Text(entry.name, style: text.titleSmall)),
            const SizedBox(width: 8),
            SampleStatusChip(status: entry.status),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 2,
                children: [
                  Text(
                    entry.id,
                    style: text.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text('类型 ${entry.layer}', style: text.labelSmall),
                  if (entry.userVerdict.isNotEmpty)
                    Text('用户判定 ${entry.userVerdict}', style: text.labelSmall),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '用户评价：${entry.userEval}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall,
              ),
            ],
          ),
        ),
        children: [
          if (entry.summary.isNotEmpty)
            _DetailField(label: '机制摘要', value: entry.summary),
          if (entry.mechanism.isNotEmpty)
            _DetailField(label: '机制明细', value: entry.mechanism),
          _DetailField(label: '状态原文', value: entry.statusRaw),
          _DetailField(label: '证据等级', value: entry.evidence),
          if (entry.paper.isNotEmpty)
            _DetailField(label: '论文 / 来源', value: entry.paper),
        ],
      ),
    );
  }
}

class _DetailField extends StatelessWidget {
  const _DetailField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: theme.textTheme.labelSmall),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 8),
            Text('本地数据读取失败', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(message, textAlign: TextAlign.center, style: text.bodySmall),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

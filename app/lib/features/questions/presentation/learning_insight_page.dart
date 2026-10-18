/// 学习洞察页：把解题链里的能力动作、卡点热区与下一步建议摊开。
///
/// 口径全部在 [learningInsightDataProvider]（链洞察 + 学习建议 + 能力词表 +
/// 知识点中文名已经拼好），本文件只做展示：
/// * 建议按 provider 已排好的顺序渲染，页面不重排、不改优先级；
/// * 平均风险为 null 时显示「未读数」，不插补 0；
/// * 词表外动作单独成块，不静默忽略；空输入显示「还没有解题链」，不虚构读数。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/reasoning/learning_advice.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/presentation/capability_vocabulary_page.dart';
import '../application/learning_insight_provider.dart';

/// 学习洞察页的根 key。
const Key learningInsightPageKey = Key('learning-insight-page');

/// 下拉刷新容器。
const Key learningInsightRefreshKey = Key('learning-insight-refresh');

/// 顶部刷新按钮。
const Key learningInsightRefreshButtonKey =
    Key('learning-insight-refresh-button');

/// 建议卡的 key（同类建议可能有多张，用动作类型区分）。
Key learningInsightAdviceCardKey(LearningInsightAdviceCard card) =>
    ValueKey<String>(
      'learning-insight-advice-${card.kind.name}-${card.actionType ?? ''}',
    );

/// 动作分布行的 key。
Key learningInsightActionRowKey(String actionType) =>
    ValueKey<String>('learning-insight-action-$actionType');

/// 卡点热区行的 key。
Key learningInsightStuckRowKey(String knowledgePointId) =>
    ValueKey<String>('learning-insight-stuck-$knowledgePointId');

/// 动作 × 知识点交叉行的 key。
Key learningInsightCrossRowKey(String actionType, String knowledgePointId) =>
    ValueKey<String>('learning-insight-cross-$actionType-$knowledgePointId');

/// 词表外动作块。
const Key learningInsightUnknownSectionKey =
    Key('learning-insight-unknown-section');

/// 词表退回内置的提示条。
const Key learningInsightFallbackBannerKey =
    Key('learning-insight-fallback-banner');

/// 空态卡片。
const Key learningInsightEmptyKey = Key('learning-insight-empty');

/// 错误态卡片。
const Key learningInsightErrorKey = Key('learning-insight-error');

/// 建议种类 -> 图标（不新造文案，先用图标区分）。
IconData learningInsightAdviceIcon(LearningAdviceKind kind) => switch (kind) {
      LearningAdviceKind.practiceAction => Icons.fitness_center,
      LearningAdviceKind.collectChains => Icons.link,
      LearningAdviceKind.reviewVocabulary => Icons.account_tree_outlined,
      LearningAdviceKind.keepGoing => Icons.check_circle_outline,
      LearningAdviceKind.noData => Icons.info_outline,
    };

/// 建议种类 -> 强调色。
Color learningInsightAdviceColor(ThemeData theme, LearningAdviceKind kind) =>
    switch (kind) {
      LearningAdviceKind.practiceAction => theme.colorScheme.primary,
      LearningAdviceKind.collectChains => theme.colorScheme.secondary,
      LearningAdviceKind.reviewVocabulary => Colors.orange.shade800,
      LearningAdviceKind.keepGoing => Colors.green.shade700,
      LearningAdviceKind.noData => theme.colorScheme.outline,
    };

/// 平均风险文案：null = 没有风险读数（不是 0），页面显示「未读数」。
String learningInsightRiskText(
  AppLocalizations l10n,
  double? averageStuckRisk,
) {
  if (averageStuckRisk == null) {
    return l10n.learningInsightRiskUnread;
  }
  return l10n.learningInsightRiskAverage(
    '${(averageStuckRisk * 100).round()}%',
  );
}

/// 动作三态文案：自定义优先于「内置」，都认不出才是未知。
String learningInsightActionStateText(
  AppLocalizations l10n,
  LearningInsightActionRow row,
) {
  if (row.custom) {
    return l10n.learningInsightActionCustom;
  }
  if (row.known) {
    return l10n.learningInsightActionBuiltIn;
  }
  return l10n.learningInsightActionUnknown;
}

/// 最近出现时间；没有时间戳返回 null（界面不显示这一项）。
String? learningInsightLastSeenText(
  AppLocalizations l10n,
  DateTime? lastSeenAt,
) {
  if (lastSeenAt == null) {
    return null;
  }
  final local = lastSeenAt.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return l10n.learningInsightLastSeen(
    '${local.year}-${two(local.month)}-${two(local.day)} '
    '${two(local.hour)}:${two(local.minute)}',
  );
}

/// 词表退回提示是否显示（provider 读自定义词表失败时置 true）。
bool learningInsightShowsFallback(LearningInsightData data) =>
    data.vocabOverlayFallback;

/// 空态：没有任何链读数，且建议只有 noData。
bool learningInsightShowsEmpty(LearningInsightData data) {
  if (data.hasActivity) {
    return false;
  }
  return data.adviceCards.every(
    (card) => card.kind == LearningAdviceKind.noData,
  );
}

/// 学习洞察页。
class LearningInsightPage extends ConsumerWidget {
  const LearningInsightPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      key: learningInsightPageKey,
      appBar: AppBar(
        title: Text(l10n.learningInsightTitle),
        actions: [
          IconButton(
            key: learningInsightRefreshButtonKey,
            tooltip: l10n.learningInsightRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(learningInsightDataProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        key: learningInsightRefreshKey,
        onRefresh: () async {
          ref.invalidate(learningInsightDataProvider);
          await ref.read(learningInsightDataProvider.future);
        },
        child: ref.watch(learningInsightDataProvider).when(
              loading: () => ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 240),
                  Center(child: CircularProgressIndicator()),
                ],
              ),
              error: (error, stackTrace) => _InsightErrorView(
                l10n: l10n,
                error: error,
                onRetry: () => ref.invalidate(learningInsightDataProvider),
              ),
              data: (data) => _InsightBody(data: data, l10n: l10n),
            ),
      ),
    );
  }
}

class _InsightBody extends StatelessWidget {
  const _InsightBody({required this.data, required this.l10n});

  final LearningInsightData data;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final empty = learningInsightShowsEmpty(data);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (learningInsightShowsFallback(data)) _FallbackBanner(l10n: l10n),
        if (empty)
          _EmptyCard(l10n: l10n)
        else ...[
          _SummaryLine(data: data, l10n: l10n),
          _AdviceSection(data: data, l10n: l10n),
          _ActionSection(data: data, l10n: l10n),
          if (data.unknownRows.isNotEmpty)
            _UnknownSection(data: data, l10n: l10n),
          if (data.neverUsedActions.isNotEmpty)
            _NeverUsedSection(data: data, l10n: l10n),
          if (data.stuckRows.isNotEmpty) _StuckSection(data: data, l10n: l10n),
          if (data.actionKnowledgeRows.isNotEmpty)
            _CrossSection(data: data, l10n: l10n),
        ],
      ],
    );
  }
}

class _InsightErrorView extends StatelessWidget {
  const _InsightErrorView({
    required this.l10n,
    required this.error,
    required this.onRetry,
  });

  final AppLocalizations l10n;
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          key: learningInsightErrorKey,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.learningInsightLoadFailed('$error'),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: Text(l10n.learningInsightRetry),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.data, required this.l10n});

  final LearningInsightData data;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        l10n.learningInsightSummary(
          data.insights.chainCount,
          data.insights.stepCount,
          data.insights.questionCount,
        ),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _AdviceSection extends StatelessWidget {
  const _AdviceSection({required this.data, required this.l10n});

  final LearningInsightData data;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SectionCard(
      icon: Icons.tips_and_updates_outlined,
      title: l10n.learningInsightAdviceSection,
      child: data.adviceCards.isEmpty
          ? Text(
              l10n.learningInsightAdviceEmpty,
              style: theme.textTheme.bodyMedium,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final card in data.adviceCards)
                  _AdviceCard(card: card, l10n: l10n),
              ],
            ),
    );
  }
}

class _ActionSection extends StatelessWidget {
  const _ActionSection({required this.data, required this.l10n});

  final LearningInsightData data;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SectionCard(
      icon: Icons.insights_outlined,
      title: l10n.learningInsightActionSection,
      child: data.actionRows.isEmpty
          ? Text(
              l10n.learningInsightActionEmpty,
              style: theme.textTheme.bodyMedium,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final row in data.actionRows)
                  _ActionRow(row: row, l10n: l10n),
              ],
            ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _AdviceCard extends StatelessWidget {
  const _AdviceCard({required this.card, required this.l10n});

  final LearningInsightAdviceCard card;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = learningInsightAdviceColor(theme, card.kind);
    final metrics = <String>[
      if (card.actionLabelZh != null && card.actionLabelZh!.trim().isNotEmpty)
        l10n.learningInsightAdviceAction(card.actionLabelZh!),
      if (card.questionCount != null)
        l10n.learningInsightAdviceQuestions(card.questionCount!),
      if (card.stepCount != null)
        l10n.learningInsightAdviceSteps(card.stepCount!),
      if (card.highRiskStepCount != null && card.highRiskStepCount! > 0)
        l10n.learningInsightAdviceHighRisk(card.highRiskStepCount!),
    ];
    return Container(
      key: learningInsightAdviceCardKey(card),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                learningInsightAdviceIcon(card.kind),
                size: 18,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(card.titleZh, style: theme.textTheme.titleSmall),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(card.detailZh, style: theme.textTheme.bodyMedium),
          if (metrics.isNotEmpty || card.knowledgePointTitles.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final metric in metrics) _MetricChip(text: metric),
                for (final title in card.knowledgePointTitles)
                  _MetricChip(text: title, emphasized: true),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.row, required this.l10n});

  final LearningInsightActionRow row;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastSeen = learningInsightLastSeenText(l10n, row.lastSeenAt);
    final tail = <String>[
      learningInsightRiskText(l10n, row.averageStuckRisk),
      if (lastSeen != null) lastSeen,
    ];
    return Padding(
      key: learningInsightActionRowKey(row.actionType),
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.labelZh,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _MetricChip(
                text: learningInsightActionStateText(l10n, row),
                emphasized: row.custom,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            l10n.learningInsightActionCounts(
              row.stepCount,
              row.questionCount,
              row.highRiskStepCount,
            ),
            style: theme.textTheme.bodySmall,
          ),
          Text(
            tail.join(' · '),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _UnknownSection extends StatelessWidget {
  const _UnknownSection({required this.data, required this.l10n});

  final LearningInsightData data;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: learningInsightUnknownSectionKey,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.help_outline,
                  size: 18,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.learningInsightUnknownSection(data.unknownRows.length),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              l10n.learningInsightUnknownHint,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            for (final row in data.unknownRows)
              Text('- ${row.labelZh}', style: theme.textTheme.bodyMedium),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const CapabilityVocabularyPage(),
                  ),
                ),
                icon: const Icon(Icons.account_tree_outlined, size: 18),
                label: Text(l10n.learningInsightOpenVocabulary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NeverUsedSection extends StatelessWidget {
  const _NeverUsedSection({required this.data, required this.l10n});

  final LearningInsightData data;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SectionCard(
      icon: Icons.checklist_rtl,
      title: l10n.learningInsightNeverUsedSection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.learningInsightNeverUsedHint,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final action in data.neverUsedActions)
                _MetricChip(text: action.labelZh),
            ],
          ),
        ],
      ),
    );
  }
}

class _StuckSection extends StatelessWidget {
  const _StuckSection({required this.data, required this.l10n});

  final LearningInsightData data;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SectionCard(
      icon: Icons.local_fire_department_outlined,
      title: l10n.learningInsightStuckSection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in data.stuckRows)
            Padding(
              key: learningInsightStuckRowKey(row.knowledgePointId),
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.titleZh, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(
                    l10n.learningInsightStuckCounts(
                      row.highRiskStepCount,
                      row.questionCount,
                      row.chainCount,
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CrossSection extends StatelessWidget {
  const _CrossSection({required this.data, required this.l10n});

  final LearningInsightData data;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SectionCard(
      icon: Icons.hub_outlined,
      title: l10n.learningInsightCrossSection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in data.actionKnowledgeRows)
            Padding(
              key: learningInsightCrossRowKey(
                row.actionType,
                row.knowledgePointId,
              ),
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${row.actionLabelZh} → ${row.knowledgePointTitleZh}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.learningInsightStuckCounts(
                      row.highRiskStepCount,
                      row.questionCount,
                      row.chainCount,
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FallbackBanner extends StatelessWidget {
  const _FallbackBanner({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: learningInsightFallbackBannerKey,
      margin: const EdgeInsets.only(bottom: 12),
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: theme.colorScheme.onTertiaryContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.learningInsightOverlayFallback,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onTertiaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: learningInsightEmptyKey,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insights_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.learningInsightEmptyTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.learningInsightEmptyBody,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.text, this.emphasized = false});

  final String text;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: emphasized
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color:
              emphasized ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

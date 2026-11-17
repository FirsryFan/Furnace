/// 「待处理题目」页：把**已入库但不完整**的题从主题库单拎出来。
///
/// 用户口径（2026-11-17）：入库但没有答案/解析的题不能在主题库混着，要另设入口
/// 并统计数量/原因；补上后自动回到主题库。这一页只读：列待处理题、给出原因
/// （缺答案 / 缺解析 / 缺配图），点开进详情页去补，不在这里改数据。
///
/// 数据源是 [questionPendingLibraryProvider]（与主题库同一个读表函数
/// `readQuestionLibrary`，只是判据反过来：`pendingOnly: true`），统计来自
/// [questionPendingStatsProvider]；判据在
/// `domain/services/questions/question_readiness.dart`，不按学科硬编码。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/reasoning/capability_action.dart';
import '../../../l10n/app_localizations.dart';
import '../application/question_library_provider.dart';
import 'question_detail_page.dart';

/// 待处理页根部 key（测试定位）。
const Key questionPendingPageKey = Key('question-pending-page');

/// 待处理页「按原因统计」卡片 key。
const Key questionPendingStatsKey = Key('question-pending-stats');

/// 待处理列表行按题 id 生成 key：`question-pending-row-<questionId>`。
String questionPendingRowKeyFor(String questionId) =>
    'question-pending-row-$questionId';

/// 题库页「待处理」入口的 key。
const Key questionBankPendingEntryKey = Key('question-bank-pending-entry');

class QuestionPendingPage extends ConsumerWidget {
  const QuestionPendingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final snapshotAsync = ref.watch(questionPendingLibraryProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.questionPendingTitle)),
      body: snapshotAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.questionBankFailed('$error'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (snapshot) => snapshot.isEmpty
            ? _EmptyPendingView(l10n: l10n)
            : _PendingList(l10n: l10n, snapshot: snapshot),
      ),
    );
  }
}

class _EmptyPendingView extends StatelessWidget {
  const _EmptyPendingView({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.task_alt,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(l10n.questionPendingEmpty, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              l10n.questionPendingEmptyHint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingList extends ConsumerWidget {
  const _PendingList({required this.l10n, required this.snapshot});

  final AppLocalizations l10n;
  final QuestionLibrarySnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final stats = ref.watch(questionPendingStatsProvider).valueOrNull ??
        questionPendingStats(
          <QuestionReadiness>[
            for (final entry in snapshot.entries) entry.readiness,
          ],
        );
    final entries = snapshot.entries;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 988),
        child: ListView(
          key: questionPendingPageKey,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: <Widget>[
            Text(l10n.questionPendingIntro, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Card(
              key: questionPendingStatsKey,
              elevation: 0,
              color: theme.colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l10n.questionPendingSummary(stats.total),
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: <Widget>[
                        if (stats.missingAnswer > 0)
                          _ReasonChip(
                            label: l10n.questionPendingReasonAnswer(
                              stats.missingAnswer,
                            ),
                          ),
                        if (stats.missingSolution > 0)
                          _ReasonChip(
                            label: l10n.questionPendingReasonSolution(
                              stats.missingSolution,
                            ),
                          ),
                        if (stats.missingStemMedia > 0)
                          _ReasonChip(
                            label: l10n.questionPendingReasonMedia(
                              stats.missingStemMedia,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final entry in entries)
              _PendingRow(
                entry: entry,
                subjectKey: entry.subjectKey,
                onOpen: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) =>
                        QuestionDetailPage(questionId: entry.questionId),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReasonChip extends StatelessWidget {
  const _ReasonChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  const _PendingRow({
    required this.entry,
    required this.subjectKey,
    required this.onOpen,
  });

  final QuestionLibraryEntry entry;
  final String subjectKey;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final reasons = <String>[
      if (entry.readiness.has(QuestionPendingReason.missingAnswer))
        l10n.practiceRecommendationReasonMissingAnswer,
      if (entry.readiness.has(QuestionPendingReason.missingSolution))
        l10n.practiceRecommendationReasonMissingSolution,
      if (entry.readiness.has(QuestionPendingReason.missingStemMedia))
        l10n.questionPendingReasonMediaLabel,
    ];
    final subject = subjectKey.trim().isEmpty
        ? l10n.questionPaperSubjectNone
        : (CapabilityAction.subjectLabelsZh[subjectKey.trim()] ?? subjectKey);
    final preview = entry.stemPreview;

    return Card(
      key: ValueKey<String>(questionPendingRowKeyFor(entry.questionId)),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    entry.serialLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  Text(
                    subject,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (preview.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: <Widget>[
                  for (final reason in reasons)
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        reason,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

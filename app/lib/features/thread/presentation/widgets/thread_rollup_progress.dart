/// 父容器子任务汇总的只读展示（Thread，2026-11-15）。
///
/// 数据来自 `features/thread/application/thread_rollup_projection.dart` 的
/// [ThreadRollup]（纯函数结果，不查库、不写库）。这里只有两个壳：
///
///  * [ThreadRollupProgressLine]：列表里容器行上的一行摘要（`子任务 3/10 · 30%`）；
///  * [ThreadRollupCard]：事件属性页里的详情卡（汇总状态 / 分状态计数 / 合计估时 /
///    进度条），并明确写出"只读汇总"——显示它不会写回父容器状态。
///
/// 不在这里推导任何状态或百分比：全部由 domain 算好，UI 不出现第二套规则，也就
/// 不会出现"列表说 30%、详情说 3/10"这种两处各算一遍的分歧。
library;

import 'package:flutter/material.dart';

import '../../../../domain/services/thread/thread_rollup.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../tasks/presentation/widgets/task_status_actions.dart';

/// 容器行上的一行汇总：`子任务 3/10 · 30% · 卡住 1 · 跳过 2`。
///
/// 空汇总（没有子节点）渲染成零高度：没东西可汇总时不该多一条空行。
class ThreadRollupProgressLine extends StatelessWidget {
  const ThreadRollupProgressLine({super.key, required this.rollup});

  final ThreadRollup rollup;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final counts = rollup.counts;
    if (rollup.isEmpty) {
      return const SizedBox.shrink();
    }
    final parts = <String>[
      '${l10n.threadRollupSubtasks} '
          '${l10n.threadRollupDoneOf(counts.done, counts.total)}',
      if (rollup.percent != null) l10n.threadRollupPercent(rollup.percent!),
      if (counts.blocked > 0) l10n.threadRollupBlocked(counts.blocked),
      if (counts.skipped > 0) l10n.threadRollupSkipped(counts.skipped),
    ];
    return Row(
      children: [
        Icon(
          Icons.account_tree_outlined,
          size: 13,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            parts.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// 事件属性页里的「子任务汇总（只读）」卡片。
///
/// 显示：汇总状态、分状态计数、合计估时（未知时明说未知）、进度条 + 百分比、
/// 一句"只读汇总"的说明。没有子任务时渲染成零高度。
class ThreadRollupCard extends StatelessWidget {
  const ThreadRollupCard({super.key, required this.rollup});

  final ThreadRollup rollup;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (rollup.isEmpty) {
      return const SizedBox.shrink();
    }
    final counts = rollup.counts;
    final status = rollup.status;
    final estimate = rollup.estimateMinutes;
    return Card(
      key: const Key('thread-rollup-card'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_tree_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.threadRollupSection,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (status != null)
              Row(
                children: [
                  Text(
                    l10n.threadRollupStatus,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    taskStatusLabelOf(l10n, status),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 6),
            Text(
              l10n.threadRollupCountsLine(
                counts.todo,
                counts.doing,
                counts.done,
                counts.blocked,
                counts.skipped,
              ),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              estimate != null
                  ? l10n.threadRollupEstimate(estimate)
                  : l10n.threadRollupEstimateUnknown,
              style: theme.textTheme.bodySmall,
            ),
            if (rollup.fraction != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: rollup.fraction,
                        minHeight: 6,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.threadRollupPercent(rollup.percent ?? 0),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Text(
              l10n.threadRollupReadOnly,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

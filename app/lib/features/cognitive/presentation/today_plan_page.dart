/// 今日清单页：把 `TodayPlanner` 排好的清单摆到用户面前。
///
/// 这一页只做三件事：给一行「未标定」的说明、逐条排版（做什么 / 买到多少 /
/// 为什么排这里）、如实报「清单外还有几件」。所有价格与次序都来自
/// `TodayPlan`，页面**不重算任何数字**（`today_plan.dart` 是唯一来源），也
/// 不认识 `dueAt` / `stability` / `difficulty`（记忆层的字段是服务层的事）。
///
/// 它是只读的：没有任何写库路径。候选题的价格要模型给
/// （`plan_today` / `evaluate_problem_fit`），这一页只列到期的卡，末尾一行
/// 明说这件事，免得用户以为「没有练习」等于「没有值得做的题」。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/scheduling/today_plan.dart';
import '../../../l10n/app_localizations.dart';
import '../application/today_plan_reader.dart';

class TodayPlanPage extends ConsumerWidget {
  const TodayPlanPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.todayPlanTitle),
        actions: [
          IconButton(
            // 清单跟着 `dataRevision` 走，所以正常不需要手动刷；这个按钮是
            // 「我刚刚在别处改过、页面还没反应过来」时的一条明路。
            tooltip: l10n.commonRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(todayPlanProvider),
          ),
        ],
      ),
      body: ref.watch(todayPlanProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.todayPlanFailed('$error'),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            data: (plan) => _TodayPlanBody(plan: plan),
          ),
    );
  }
}

class _TodayPlanBody extends StatelessWidget {
  const _TodayPlanBody({required this.plan});

  final TodayPlan plan;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // 先说清楚这不是测量：顺序可以照做，数字不要当刻度。
        Text(l10n.todayPlanUncalibrated, style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        if (plan.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n.todayPlanEmpty),
            ),
          )
        else ...[
          Text(
            l10n.todayPlanCount(plan.actions.length),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final action in plan.actions) TodayActionCard(action: action),
          if (plan.omitted > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.todayPlanOmitted(plan.omitted),
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
        const SizedBox(height: 16),
        Text(l10n.todayPlanPracticeHint, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// 清单里的一条。公开类：别的入口（将来的首页卡片）可以复用同一张。
class TodayActionCard extends StatelessWidget {
  const TodayActionCard({super.key, required this.action});

  final TodayAction action;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Chip(label: _kindLabel(l10n), theme: theme),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    action.title,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            if (action.priced) ...[
              const SizedBox(height: 6),
              Text(_priceLine(l10n), style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 4),
            Text(action.why, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  String _kindLabel(AppLocalizations l10n) =>
      action.kind == TodayActionKind.review
          ? l10n.todayPlanKindReview
          : l10n.todayPlanKindPractice;

  /// 没有价格的行**不画价格行**：`TodayPlanner` 已经决定「零增益不是价格」，
  /// 页面照着做，不在这里补一个 0.0（补了就等于替它撒了一个谎）。
  String _priceLine(AppLocalizations l10n) {
    final metric = action.metric == TodayMetric.reachability
        ? l10n.todayPlanMetricReachability
        : l10n.todayPlanMetricRetention;
    return l10n.todayPlanPrice(
      metric,
      action.value!.toStringAsFixed(3),
      action.cost!.toStringAsFixed(1),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.theme});

  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall
            ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
      ),
    );
  }
}

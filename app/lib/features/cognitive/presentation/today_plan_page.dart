/// 今日清单页：把 `TodayPlanner` 排好的清单摆到用户面前。
///
/// 这一页只做三件事：给一行「未标定」的说明、逐条排版（做什么 / 买到多少 /
/// 为什么排这里）、如实报「清单外还有几件」。所有价格与次序都来自
/// `TodayPlan`，页面**不重算任何数字**（`today_plan.dart` 是唯一来源），也
/// 不认识 `dueAt` / `stability` / `difficulty`（记忆层的字段是服务层的事）。
///
/// 顶部「今天做什么」来自推理层的 `DailyStudyPlan`（`daily_study_plan.dart`），
/// 与下面的复习侧清单是两个独立口径：它按优先级排步骤，页面同样只排版、
/// 不重排、不重算，也不把两份计划合并成一份。
///
/// 它是只读的：没有任何写库路径。候选题的价格要模型给
/// （`plan_today` / `evaluate_problem_fit`），这一页只列到期的卡，末尾一行
/// 明说这件事，免得用户以为「没有练习」等于「没有值得做的题」。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/reasoning/daily_study_plan.dart';
import '../../../domain/services/scheduling/today_plan.dart';
import '../../../l10n/app_localizations.dart';
import '../application/daily_study_plan_reader.dart';
import '../application/today_plan_reader.dart';

/// 「今天做什么」区块的稳定 key：测试与将来的首页卡片共用同一套定位点。
const Key todayStudyPlanSectionKey = Key('today-study-plan');
const Key todayStudyPlanErrorKey = Key('today-study-plan-error');
const Key todayStudyPlanRetryKey = Key('today-study-plan-retry');

/// 第 [index] 步的 key（顺序即 `DailyStudyPlan.steps` 的顺序，页面不重排）。
Key todayStudyPlanStepKey(int index) =>
    ValueKey<String>('today-study-plan-step-$index');

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
            onPressed: () {
              // 两个区块各自独立取数：刷新必须同时失效，否则会出现
              // 「一个更新了、另一个还停在旧读数」的半新半旧页面。
              ref.invalidate(todayPlanProvider);
              ref.invalidate(dailyStudyPlanProvider);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // 推理层的「今天做什么」放页顶：它按优先级给今天的步骤；下面的旧
          // 清单是复习侧的计划，两者各自加载、各自失败，不合并口径。
          const _DailyStudyPlanSection(),
          const SizedBox(height: 16),
          ref.watch(todayPlanProvider).when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l10n.todayPlanFailed('$error'),
                    textAlign: TextAlign.center,
                  ),
                ),
                data: (plan) => _TodayPlanBody(plan: plan),
              ),
        ],
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

    // 外层已经是 ListView：这里换成 Column，让「今天做什么」区块留在页顶，
    // 旧清单的内容照旧往下排（不为新数据把旧清单重新排一遍）。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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

/// 推理层「今天做什么」区块：只照抄 `DailyStudyPlan`（步骤标题 / 理由 / 分钟 /
/// 总分钟 / 跳过条数），不重排、不重算、不虚构。没有依据时数据层自己会给一条
/// `noData` 步骤，这里照常展示，不另造一句空态把它压掉。
class _DailyStudyPlanSection extends ConsumerWidget {
  const _DailyStudyPlanSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final plan = ref.watch(dailyStudyPlanProvider);
    final value = plan.valueOrNull;

    return Column(
      key: todayStudyPlanSectionKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.today_outlined,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.todayStudyPlanTitle,
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (value != null)
              Text(
                l10n.todayStudyPlanTotal(value.totalMinutes),
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
        if (value != null && value.skippedStepCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.todayStudyPlanSkipped(value.skippedStepCount),
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 8),
        plan.when(
          loading: () => Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.todayStudyPlanLoading,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          error: (error, _) => _DailyStudyPlanError(
            message: l10n.todayStudyPlanFailed('$error'),
            onRetry: () => ref.invalidate(dailyStudyPlanProvider),
          ),
          data: (data) => _DailyStudyPlanContent(plan: data),
        ),
      ],
    );
  }
}

class _DailyStudyPlanContent extends StatelessWidget {
  const _DailyStudyPlanContent({required this.plan});

  final DailyStudyPlan plan;

  @override
  Widget build(BuildContext context) {
    // 数据层最差也会给一条 keepGoing / noData；空列表只是防御性兜底。
    if (plan.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < plan.steps.length; index++)
          _DailyStudyStepCard(index: index, step: plan.steps[index]),
      ],
    );
  }
}

class _DailyStudyStepCard extends StatelessWidget {
  const _DailyStudyStepCard({required this.index, required this.step});

  final int index;
  final DailyPlanStep step;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Card(
      key: todayStudyPlanStepKey(index),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(step.titleZh, style: theme.textTheme.titleSmall),
                ),
                const SizedBox(width: 8),
                // 分钟数照抄数据层；0 分钟也照写，不替它改口径。
                Text(
                  l10n.todayStudyPlanStepMinutes(step.estimatedMinutes),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(step.detailZh, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _DailyStudyPlanError extends StatelessWidget {
  const _DailyStudyPlanError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Card(
      key: todayStudyPlanErrorKey,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: todayStudyPlanRetryKey,
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.todayStudyPlanRetry),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

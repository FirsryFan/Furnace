import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/assessment_models.dart';
import 'assessment_display.dart';

/// 结果页「已保存」横幅。
const Key assessmentResultSavedKey = Key('assessment-result-saved');

/// 结果页统计指标区。
const Key assessmentResultMetricsKey = Key('assessment-result-metrics');

/// 结果页能力估计区。
const Key assessmentResultAbilitiesKey = Key('assessment-result-abilities');

/// 结果页质量标记区。
const Key assessmentResultQualityKey = Key('assessment-result-quality');

/// 结果页完成按钮。
const Key assessmentResultDoneKey = Key('assessment-result-done');

/// 单条统计指标行；[metricName] 是指标的稳定 id（例如 rt_median）。
Key assessmentResultMetricRowKey(String metricName) =>
    ValueKey<String>('assessment-result-metric-$metricName');

/// 单条能力估计行；[abilityId] 是能力的稳定 id（例如 processing_speed）。
Key assessmentResultAbilityRowKey(String abilityId) =>
    ValueKey<String>('assessment-result-ability-$abilityId');

/// 一次评测结束后的结果页。
///
/// 只消费纯数据：会话摘要、本次产出的统计指标、更新后的能力估计与质量标记。
/// 页面不读数据库、不调用服务、不猜测结果是否已保存——调用方（run 页）负责
/// 在保存成功后把 [AssessmentSessionSummary] 传进来。
///
/// 之所以收模型而不是收 `AssessmentSessionResult`，是为了让结果页与引擎解耦：
/// 结果页可以单测，run 页重构也不会连带改这里。
class AssessmentResultPage extends StatelessWidget {
  const AssessmentResultPage({
    super.key,
    required this.summary,
    required this.metrics,
    required this.abilities,
    required this.params,
    required this.qualityFlags,
    this.onDone,
  });

  final AssessmentSessionSummary summary;
  final List<MetricSample> metrics;
  final List<AbilityEstimate> abilities;
  final List<ParamEstimate> params;
  final List<String> qualityFlags;

  /// 点「完成」后的动作；缺省关闭当前路由。
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final completedAt = summary.completedAt;
    final durationText = completedAt == null
        ? null
        : assessmentDurationText(completedAt.difference(summary.startedAt));
    final sortedAbilities = assessmentSortedAbilities(abilities);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.assessmentResultPageTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SavedBanner(
            durationText: durationText,
            taskName: assessmentTaskNameById(l10n, summary.taskId),
          ),
          if (metrics.isNotEmpty)
            _ResultSection(
              key: assessmentResultMetricsKey,
              title: l10n.assessmentResultMetricsTitle,
              children: [
                for (final metric in metrics)
                  Padding(
                    key: assessmentResultMetricRowKey(metric.name),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            assessmentMetricName(l10n, metric.name),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          assessmentMetricValueText(metric.name, metric.value),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          if (sortedAbilities.isNotEmpty)
            _ResultSection(
              key: assessmentResultAbilitiesKey,
              title: l10n.assessmentResultAbilityTitle,
              children: [
                for (final ability in sortedAbilities)
                  Padding(
                    key: assessmentResultAbilityRowKey(ability.abilityId),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                assessmentAbilityName(l10n, ability.abilityId),
                                style: theme.textTheme.bodyMedium,
                              ),
                              if (ability.stale)
                                Text(
                                  l10n.assessmentProfileStale,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              assessmentEstimateValueText(ability.mean),
                              style: theme.textTheme.bodyMedium,
                            ),
                            Text(
                              assessmentSourceLabel(l10n, ability.source),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          _ResultSection(
            key: assessmentResultQualityKey,
            title: l10n.assessmentResultQualityTitle,
            children: [
              Text(
                assessmentQualityFlagsText(l10n, qualityFlags),
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: assessmentResultDoneKey,
            onPressed: onDone ?? () => Navigator.of(context).pop(),
            child: Text(l10n.assessmentResultDone),
          ),
        ],
      ),
    );
  }
}

class _SavedBanner extends StatelessWidget {
  const _SavedBanner({required this.durationText, required this.taskName});

  final String? durationText;
  final String taskName;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      key: assessmentResultSavedKey,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_outline,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.assessmentResultSaved,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  taskName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                if (durationText != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    l10n.assessmentResultDuration(durationText!),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultSection extends StatelessWidget {
  const _ResultSection({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

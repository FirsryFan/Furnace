import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../application/assessment_providers.dart';
import '../domain/assessment_models.dart';
import 'assessment_display.dart';
import 'assessment_profile_page.dart';
import 'assessment_run_page.dart';

/// 评测中心页：任务清单 + 认知档案入口。
///
/// 任务与读数都来自 provider；页面只负责展示、启动与返回后刷新。
const Key assessmentCenterProfileEntryKey =
    Key('assessment-center-profile-entry');
const Key assessmentCenterProfileSummaryKey =
    Key('assessment-center-profile-summary');
const Key assessmentCenterNoMeasurementsKey =
    Key('assessment-center-no-measurements');
const Key assessmentCenterTasksKey = Key('assessment-center-tasks');
const Key assessmentCenterRetryKey = Key('assessment-center-retry');

Key assessmentCenterTaskCardKey(String taskId) =>
    ValueKey<String>('assessment-center-task-$taskId');

Key assessmentCenterStartButtonKey(String taskId) =>
    ValueKey<String>('assessment-center-start-$taskId');

/// 启动一次评测的方式：默认 push 运行页。
///
/// 抽成 provider 是为了让 widget test 能注入替身（不真的跑完整评测，也能
/// 模拟「打不开任务」的失败分支）。
typedef AssessmentTaskStarter = Future<void> Function(
    BuildContext context, AssessmentTaskConfig task);

final assessmentStartTaskProvider = Provider<AssessmentTaskStarter>((ref) {
  return (context, task) => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => AssessmentRunPage(task: task),
        ),
      );
});

class AssessmentCenterPage extends ConsumerWidget {
  const AssessmentCenterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tasks = ref.watch(assessmentTasksProvider);
    final profile = ref.watch(assessmentProfileProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.assessmentCenterTitle)),
      body: tasks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _CenterFailure(
          error: error,
          onRetry: () {
            ref.invalidate(assessmentTasksProvider);
            ref.invalidate(assessmentProfileProvider);
          },
        ),
        data: (configs) {
          final enabled = [
            for (final config in configs)
              if (config.enabled) config,
          ];
          final sessions = profile.valueOrNull?.sessions ??
              const <AssessmentSessionSummary>[];
          final counts = assessmentSessionCountsByTaskId(sessions);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Text(
                l10n.assessmentCenterIntro,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              _ProfileEntryCard(profile: profile),
              const SizedBox(height: 24),
              Text(
                l10n.assessmentCenterTasksTitle,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Column(
                key: assessmentCenterTasksKey,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final task in enabled)
                    _TaskCard(
                      task: task,
                      measuredCount: counts[task.taskId] ?? 0,
                      onStart: () => _startTask(context, ref, task),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

Future<void> _startTask(
  BuildContext context,
  WidgetRef ref,
  AssessmentTaskConfig task,
) async {
  final l10n = AppLocalizations.of(context);
  try {
    await ref.read(assessmentStartTaskProvider)(context, task);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.assessmentCenterStartFailed('$error'))),
    );
    return;
  }
  if (!context.mounted) return;
  // 一次评测会写会话与新的估计，回来后两块读数都要重读。
  ref.invalidate(assessmentTasksProvider);
  ref.invalidate(assessmentProfileProvider);
}

class _CenterFailure extends StatelessWidget {
  const _CenterFailure({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 32,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.assessmentCenterLoadFailed('$error'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              key: assessmentCenterRetryKey,
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l10n.commonRefresh),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileEntryCard extends StatelessWidget {
  const _ProfileEntryCard({required this.profile});

  final AsyncValue<AssessmentProfileSnapshot> profile;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      key: assessmentCenterProfileEntryKey,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const AssessmentProfilePage(),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.insights_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.assessmentCenterProfileTitle,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 20),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                l10n.assessmentCenterProfileHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              profile.when(
                loading: () => const SizedBox(
                  height: 14,
                  child: LinearProgressIndicator(),
                ),
                error: (error, _) => Text(
                  l10n.assessmentProfileLoadFailed('$error'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                data: (snapshot) => snapshot.sessions.isEmpty
                    ? Text(
                        l10n.assessmentCenterNoMeasurements,
                        key: assessmentCenterNoMeasurementsKey,
                        style: theme.textTheme.bodyMedium,
                      )
                    : Text(
                        l10n.assessmentCenterMeasuredCount(
                          snapshot.sessions.length,
                        ),
                        key: assessmentCenterProfileSummaryKey,
                        style: theme.textTheme.bodyMedium,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.measuredCount,
    required this.onStart,
  });

  final AssessmentTaskConfig task;
  final int measuredCount;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      key: assessmentCenterTaskCardKey(task.taskId),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    assessmentTaskName(l10n, task),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (task.provisional) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      l10n.assessmentCenterProvisional,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.assessmentCenterDurationMinutes(
                assessmentTaskDurationMinutes(task.estimatedDurationSeconds),
              ),
              style: theme.textTheme.bodySmall,
            ),
            Text(
              l10n.assessmentCenterMeasuredCount(measuredCount),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: assessmentCenterStartButtonKey(task.taskId),
                onPressed: onStart,
                child: Text(
                  measuredCount > 0
                      ? l10n.assessmentCenterRedo
                      : l10n.assessmentCenterStart,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

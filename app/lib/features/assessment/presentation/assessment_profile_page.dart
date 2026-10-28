import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../application/assessment_providers.dart';
import '../domain/assessment_models.dart';
import 'assessment_cog_profile_export.dart';
import 'assessment_display.dart';

/// 认知档案页：能力估计、认知模型参数、最近测量。
///
/// 只消费 [assessmentProfileProvider]，不在页面里重算估计；手动覆盖与恢复自动
/// 直接落到 [AssessmentStore]，随后 invalidate provider 重新读库。
const Key assessmentProfileRetryKey = Key('assessment-profile-retry');
const Key assessmentProfileAbilitiesKey = Key('assessment-profile-abilities');
const Key assessmentProfileParamsKey = Key('assessment-profile-params');
const Key assessmentProfileHistoryKey = Key('assessment-profile-history');
const Key assessmentProfileHistoryEmptyKey =
    Key('assessment-profile-history-empty');

/// 导出 `.cogprofile` 的按钮 key（widget test 与无障碍定位用）。
const Key assessmentProfileExportKey = Key('assessment-profile-export');

Key assessmentProfileAbilityRowKey(String abilityId) =>
    ValueKey<String>('assessment-profile-ability-$abilityId');

Key assessmentProfileAbilityOverrideKey(String abilityId) =>
    ValueKey<String>('assessment-profile-ability-override-$abilityId');

Key assessmentProfileAbilityClearKey(String abilityId) =>
    ValueKey<String>('assessment-profile-ability-clear-$abilityId');

Key assessmentProfileParamRowKey(String paramId) =>
    ValueKey<String>('assessment-profile-param-$paramId');

Key assessmentProfileParamOverrideKey(String paramId) =>
    ValueKey<String>('assessment-profile-param-override-$paramId');

Key assessmentProfileParamClearKey(String paramId) =>
    ValueKey<String>('assessment-profile-param-clear-$paramId');

Key assessmentProfileHistoryRowKey(String sessionId) =>
    ValueKey<String>('assessment-profile-history-$sessionId');

class AssessmentProfilePage extends ConsumerWidget {
  const AssessmentProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(assessmentProfileProvider);
    final snapshot = profile.valueOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.assessmentProfileTitle),
        actions: [
          IconButton(
            key: assessmentProfileExportKey,
            tooltip: l10n.assessmentProfileExport,
            icon: const Icon(Icons.ios_share),
            onPressed: snapshot == null
                ? null
                : () => _exportCogProfile(
                      context: context,
                      l10n: l10n,
                      snapshot: snapshot,
                      saver: ref.read(cogProfileFileSaverProvider),
                    ),
          ),
        ],
      ),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ProfileFailure(
          error: error,
          onRetry: () => ref.invalidate(assessmentProfileProvider),
        ),
        data: (snapshot) => _ProfileBody(snapshot: snapshot),
      ),
    );
  }
}

/// 导出当前档案：生成字节 → 弹「另存为」→ 按结果提示。
///
/// * 用户取消（saver 返回 null）不提示；
/// * 成功提示文件名，失败提示原始错误；
/// * 两次 await 之后都检查 mounted，避免页面退出后还弹 SnackBar。
Future<void> _exportCogProfile({
  required BuildContext context,
  required AppLocalizations l10n,
  required AssessmentProfileSnapshot snapshot,
  required CogProfileFileSaver saver,
}) async {
  final exportedAt = DateTime.now();
  final fileName = cogProfileFileName(exportedAt);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await buildCogProfileBytes(
      abilities: snapshot.abilities,
      cognitiveParams: snapshot.params,
      exportedAt: exportedAt,
    );
    final uri = await saver(fileName: fileName, bytes: bytes);
    if (uri == null || !context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.assessmentProfileExportSuccess(fileName)),
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.assessmentProfileExportFailed('$error')),
      ),
    );
  }
}

class _ProfileFailure extends StatelessWidget {
  const _ProfileFailure({required this.error, required this.onRetry});

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
              l10n.assessmentProfileLoadFailed('$error'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              key: assessmentProfileRetryKey,
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

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.snapshot});

  final AssessmentProfileSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final abilities = assessmentSortedAbilities(snapshot.abilities);
    final params = assessmentSortedParams(snapshot.params);
    final sessions = snapshot.sessions;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text(
          l10n.assessmentProfileIntro,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        _SectionHeader(title: l10n.assessmentProfileAbilitiesTitle),
        if (abilities.isEmpty)
          Text(l10n.assessmentCenterNoMeasurements)
        else
          Column(
            key: assessmentProfileAbilitiesKey,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final estimate in abilities)
                _AbilityTile(estimate: estimate),
            ],
          ),
        const SizedBox(height: 24),
        _SectionHeader(title: l10n.assessmentProfileParamsTitle),
        if (params.isEmpty)
          Text(l10n.assessmentCenterNoMeasurements)
        else
          Column(
            key: assessmentProfileParamsKey,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final estimate in params) _ParamTile(estimate: estimate),
            ],
          ),
        const SizedBox(height: 24),
        _SectionHeader(title: l10n.assessmentProfileHistoryTitle),
        if (sessions.isEmpty)
          Text(
            l10n.assessmentProfileHistoryEmpty,
            key: assessmentProfileHistoryEmptyKey,
            style: theme.textTheme.bodyMedium,
          )
        else
          Column(
            key: assessmentProfileHistoryKey,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final session in sessions) _HistoryRow(session: session),
            ],
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _AbilityTile extends ConsumerWidget {
  const _AbilityTile({required this.estimate});

  final AbilityEstimate estimate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return _EstimateTile(
      key: assessmentProfileAbilityRowKey(estimate.abilityId),
      title: assessmentAbilityName(l10n, estimate.abilityId),
      valueText: assessmentEstimateValueText(estimate.mean),
      uncertaintyText: l10n.assessmentProfileUncertaintyRow(
        assessmentEstimateValueText(estimate.uncertainty),
      ),
      measurementsText:
          l10n.assessmentProfileMeasurementsCount(estimate.nMeasurements),
      sourceText: assessmentSourceLabel(l10n, estimate.source),
      stale: estimate.stale,
      isUserOverride: estimate.isUserOverride,
      overrideKey: assessmentProfileAbilityOverrideKey(estimate.abilityId),
      clearKey: assessmentProfileAbilityClearKey(estimate.abilityId),
      onOverride: () => _showAbilityOverrideDialog(context, ref, estimate),
      onClear: () => _clearAbilityOverride(context, ref, estimate),
    );
  }
}

class _ParamTile extends ConsumerWidget {
  const _ParamTile({required this.estimate});

  final ParamEstimate estimate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return _EstimateTile(
      key: assessmentProfileParamRowKey(estimate.paramId),
      title: assessmentParamName(l10n, estimate.paramId),
      valueText: assessmentEstimateValueText(estimate.value),
      uncertaintyText: l10n.assessmentProfileUncertaintyRow(
        assessmentEstimateValueText(estimate.uncertainty),
      ),
      measurementsText: null,
      sourceText: assessmentSourceLabel(l10n, estimate.source),
      stale: false,
      isUserOverride: estimate.isUserOverride,
      overrideKey: assessmentProfileParamOverrideKey(estimate.paramId),
      clearKey: assessmentProfileParamClearKey(estimate.paramId),
      onOverride: () => _showParamOverrideDialog(context, ref, estimate),
      onClear: () => _clearParamOverride(context, ref, estimate),
    );
  }
}

class _EstimateTile extends StatelessWidget {
  const _EstimateTile({
    super.key,
    required this.title,
    required this.valueText,
    required this.uncertaintyText,
    required this.measurementsText,
    required this.sourceText,
    required this.stale,
    required this.isUserOverride,
    required this.overrideKey,
    required this.clearKey,
    required this.onOverride,
    required this.onClear,
  });

  final String title;
  final String valueText;
  final String uncertaintyText;
  final String? measurementsText;
  final String sourceText;
  final bool stale;
  final bool isUserOverride;
  final Key overrideKey;
  final Key clearKey;
  final VoidCallback onOverride;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: theme.textTheme.titleSmall),
              ),
              const SizedBox(width: 8),
              Text(
                valueText,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(uncertaintyText, style: theme.textTheme.bodySmall),
          if (measurementsText != null)
            Text(measurementsText!, style: theme.textTheme.bodySmall),
          Row(
            children: [
              Text(sourceText, style: muted),
              if (stale) ...[
                const SizedBox(width: 8),
                Text(
                  l10n.assessmentProfileStale,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                key: overrideKey,
                onPressed: onOverride,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: Text(l10n.assessmentProfileOverrideAction),
              ),
              if (isUserOverride)
                TextButton.icon(
                  key: clearKey,
                  onPressed: onClear,
                  icon: const Icon(Icons.restart_alt, size: 16),
                  label: Text(l10n.assessmentProfileClearOverride),
                ),
            ],
          ),
          Divider(
            height: 12,
            color: theme.colorScheme.outlineVariant,
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.session});

  final AssessmentSessionSummary session;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final timeText = assessmentHistoryTimeText(
      session.completedAt ?? session.startedAt,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        l10n.assessmentProfileHistoryRow(
          assessmentTaskNameById(l10n, session.taskId),
          timeText,
          session.status,
        ),
        key: assessmentProfileHistoryRowKey(session.sessionId),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

Future<void> _showAbilityOverrideDialog(
  BuildContext context,
  WidgetRef ref,
  AbilityEstimate estimate,
) async {
  final l10n = AppLocalizations.of(context);
  final value = await showDialog<double>(
    context: context,
    builder: (_) => _EstimateOverrideDialog(
      title: l10n.assessmentProfileOverrideTitle(
        assessmentAbilityName(l10n, estimate.abilityId),
      ),
      hint: l10n.assessmentProfileOverrideHint,
      initialValue: estimate.mean,
      minValue: -5,
      maxValue: 5,
      invalidMessage: l10n.assessmentProfileOverrideInvalidZScore,
      cancelLabel: l10n.commonCancel,
      saveLabel: l10n.commonSave,
    ),
  );
  if (value == null) return;
  try {
    await ref
        .read(assessmentStoreProvider)
        .setAbilityUserOverride(abilityId: estimate.abilityId, mean: value);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.assessmentRunSaveFailed('$error'))),
    );
    return;
  }
  ref.invalidate(assessmentProfileProvider);
}

Future<void> _showParamOverrideDialog(
  BuildContext context,
  WidgetRef ref,
  ParamEstimate estimate,
) async {
  final l10n = AppLocalizations.of(context);
  final value = await showDialog<double>(
    context: context,
    builder: (_) => _EstimateOverrideDialog(
      title: l10n.assessmentProfileOverrideTitle(
        assessmentParamName(l10n, estimate.paramId),
      ),
      hint: l10n.assessmentProfileOverrideHint,
      initialValue: estimate.value,
      minValue: 0,
      maxValue: 1,
      invalidMessage: l10n.assessmentProfileOverrideInvalid,
      cancelLabel: l10n.commonCancel,
      saveLabel: l10n.commonSave,
    ),
  );
  if (value == null) return;
  try {
    await ref
        .read(assessmentStoreProvider)
        .setParamUserOverride(paramId: estimate.paramId, value: value);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.assessmentRunSaveFailed('$error'))),
    );
    return;
  }
  ref.invalidate(assessmentProfileProvider);
}

Future<void> _clearAbilityOverride(
  BuildContext context,
  WidgetRef ref,
  AbilityEstimate estimate,
) async {
  final l10n = AppLocalizations.of(context);
  try {
    await ref
        .read(assessmentStoreProvider)
        .clearAbilityUserOverride(abilityId: estimate.abilityId);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.assessmentRunSaveFailed('$error'))),
    );
    return;
  }
  ref.invalidate(assessmentProfileProvider);
}

Future<void> _clearParamOverride(
  BuildContext context,
  WidgetRef ref,
  ParamEstimate estimate,
) async {
  final l10n = AppLocalizations.of(context);
  try {
    await ref
        .read(assessmentStoreProvider)
        .clearParamUserOverride(paramId: estimate.paramId);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.assessmentRunSaveFailed('$error'))),
    );
    return;
  }
  ref.invalidate(assessmentProfileProvider);
}

/// 手动覆盖对话框：自己持有 controller，避免路由退场时 TextField 还在读已释放的
/// controller（历史 bug：对话框返回后立刻 dispose controller 会崩）。
class _EstimateOverrideDialog extends StatefulWidget {
  const _EstimateOverrideDialog({
    required this.title,
    required this.hint,
    required this.initialValue,
    required this.minValue,
    required this.maxValue,
    required this.invalidMessage,
    required this.cancelLabel,
    required this.saveLabel,
  });

  final String title;
  final String hint;
  final double initialValue;
  final double minValue;
  final double maxValue;
  final String invalidMessage;
  final String cancelLabel;
  final String saveLabel;

  @override
  State<_EstimateOverrideDialog> createState() =>
      _EstimateOverrideDialogState();
}

class _EstimateOverrideDialogState extends State<_EstimateOverrideDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialValue.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = double.tryParse(_controller.text.trim());
    if (parsed == null ||
        !parsed.isFinite ||
        parsed < widget.minValue ||
        parsed > widget.maxValue) {
      setState(() => _errorText = widget.invalidMessage);
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.hint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.numberWithOptions(
              decimal: true,
              signed: widget.minValue < 0,
            ),
            decoration: InputDecoration(
              errorText: _errorText,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.saveLabel),
        ),
      ],
    );
  }
}

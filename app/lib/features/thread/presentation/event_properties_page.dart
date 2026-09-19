import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/database/database.dart';
import '../../../../data/repositories/repository_providers.dart';
import '../../../../domain/services/scheduling/thread_ranker.dart';
import '../../../../l10n/app_localizations.dart';
import '../../settings/presentation/usage_doc_page.dart';
import '../application/thread_rank_service.dart';
import 'widgets/energy_bar.dart';

/// The event property page (blueprint 2.4; user annotations 6 and 13).
///
/// This is where explainability lives. The list shows nothing but the facts;
/// here the user sees and edits every parameter, and EVERY editable parameter
/// card carries a one-line explanation of what it means in real life.
/// The algorithm section shows the raw components this event scored plus the
/// weights, and the weights are editable (they are global).
class EventPropertiesPage extends ConsumerStatefulWidget {
  const EventPropertiesPage({super.key, required this.taskId});

  final String taskId;

  @override
  ConsumerState<EventPropertiesPage> createState() =>
      _EventPropertiesPageState();
}

class _EventPropertiesPageState extends ConsumerState<EventPropertiesPage> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _estimate;
  int? _energy;
  DateTime? _expectedAt;
  DateTime? _deadline;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController();
    _description = TextEditingController();
    _estimate = TextEditingController();
    _load();
  }

  Future<void> _load() async {
    final task = await ref.read(taskRepositoryProvider).getTaskById(
          widget.taskId,
        );
    if (!mounted || task == null) {
      return;
    }
    setState(() {
      _title.text = task.title;
      _description.text = task.description ?? '';
      _estimate.text = task.estimateMinutes?.toString() ?? '';
      _energy = task.energyRequired;
      _expectedAt = task.expectedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(task.expectedAt!);
      _deadline = task.dueAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(task.dueAt!);
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _estimate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final repo = ref.read(taskRepositoryProvider);
    final minutes = int.tryParse(_estimate.text.trim());
    await repo.updateTask(
      widget.taskId,
      title: _title.text.trim().isEmpty ? null : _title.text.trim(),
      description: _description.text,
      estimateMinutes: minutes,
      clearExpectedAt: _expectedAt == null,
      expectedAt: _expectedAt?.millisecondsSinceEpoch,
      clearDueAt: _deadline == null,
      dueAt: _deadline?.millisecondsSinceEpoch,
      clearEnergyRequired: _energy == null,
      energyRequired: _energy,
    );
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _pick(DateTime? current, ValueChanged<DateTime?> apply) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (date == null || !mounted) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current ?? now),
    );
    if (time == null) {
      return;
    }
    apply(DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final feed = ref.watch(threadFeedProvider).valueOrNull;
    final ranked = feed?.ranked.all
        .where((r) => r.event.id == widget.taskId)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.commonEdit),
        actions: [
          IconButton(
            tooltip: l10n.commonSave,
            icon: const Icon(Icons.check),
            onPressed: _loaded ? _save : null,
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
              children: [
                _ParameterCard(
                  icon: Icons.title,
                  label: l10n.commonTitle,
                  child: TextField(
                    controller: _title,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                _ParameterCard(
                  icon: Icons.notes,
                  label: l10n.commonDescription,
                  child: TextField(
                    controller: _description,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                _ParameterCard(
                  icon: Icons.timer_outlined,
                  label: l10n.tasksEstimateMinutes,
                  child: TextField(
                    controller: _estimate,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    // Enter saves, like every other dialog in the app.
                    onSubmitted: (_) => _save(),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                _ParameterCard(
                  icon: Icons.schedule,
                  label: l10n.tasksExpectedAt,
                  trailing: _clearButton(() => setState(() => _expectedAt = null),
                      enabled: _expectedAt != null),
                  child: _MomentField(
                    value: _expectedAt,
                    onPick: () => _pick(
                      _expectedAt,
                      (value) => setState(() => _expectedAt = value),
                    ),
                  ),
                ),
                _ParameterCard(
                  icon: Icons.event,
                  label: l10n.tasksDueAt,
                  trailing: _clearButton(() => setState(() => _deadline = null),
                      enabled: _deadline != null),
                  child: _MomentField(
                    value: _deadline,
                    onPick: () => _pick(
                      _deadline,
                      (value) => setState(() => _deadline = value),
                    ),
                  ),
                ),
                _ParameterCard(
                  icon: Icons.bolt,
                  label: l10n.threadEnergy,
                  trailing: _clearButton(() => setState(() => _energy = null),
                      enabled: _energy != null),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: EnergyBar(
                      energy: _energy,
                      onChanged: (value) => setState(() => _energy = value),
                    ),
                  ),
                ),
                _AlgorithmSection(ranked: ranked?.isEmpty == false ? ranked!.first : null),
              ],
            ),
    );
  }

  Widget? _clearButton(VoidCallback onClear, {required bool enabled}) {
    if (!enabled) {
      return null;
    }
    return IconButton(
      tooltip: AppLocalizations.of(context).commonClear,
      icon: const Icon(Icons.backspace_outlined, size: 18),
      onPressed: onClear,
    );
  }
}

class _MomentField extends StatelessWidget {
  const _MomentField({required this.value, required this.onPick});

  final DateTime? value;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: onPick,
        icon: const Icon(Icons.edit_calendar, size: 18),
        label: Text(value == null ? l10n.commonAdd : _format(value!)),
      ),
    );
  }

  static String _format(DateTime moment) {
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${moment.year}-${two(moment.month)}-${two(moment.day)} '
        '${two(moment.hour)}:${two(moment.minute)}';
  }
}

/// One editable parameter. The explanation lives in Settings -> Usage guide
/// (user feedback item 1), so this page stays a control surface, not a manual.
class _ParameterCard extends StatelessWidget {
  const _ParameterCard({
    required this.icon,
    required this.label,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label, style: theme.textTheme.titleSmall),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

/// The algorithm section: every raw component this event scored, plus the
/// weights. Nothing about the sorting is hidden (blueprint P5/P6).
class _AlgorithmSection extends ConsumerWidget {
  const _AlgorithmSection({required this.ranked});

  final RankedEvent? ranked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final result = ranked;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.functions,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l10n.propAlgorithm,
                      style: theme.textTheme.titleSmall),
                ),
                IconButton(
                  tooltip: l10n.settingsUsageDoc,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.help_outline, size: 18),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => const UsageDocPage(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (result == null)
              Text(l10n.propAlgorithmNoData,
                  style: theme.textTheme.bodySmall)
            else ...[
              _ScoreMeter(
                label: l10n.propUrgency,
                value: result.score.urgency,
                weight: result.score.weights.urgency,
                contribution: result.score.urgencyContribution,
              ),
              _ScoreMeter(
                label: l10n.propGoalMatch,
                value: result.score.goalMatch,
                weight: result.score.weights.goal,
                contribution: result.score.goalContribution,
              ),
              _ScoreMeter(
                label: l10n.propFit,
                value: result.score.fit,
                weight: result.score.weights.fit,
                contribution: result.score.fitContribution,
              ),
              _ScoreMeter(
                label: l10n.propExpectedPressure,
                value: result.score.expectedPressure,
                weight: result.score.weights.expected,
                contribution: result.score.expectedContribution,
              ),
              _ScoreMeter(
                label: l10n.propFatigue,
                value: result.score.fatiguePenalty,
                weight: result.score.weights.fatigue,
                contribution: result.score.fatigueContribution,
                penalizes: true,
              ),
              const Divider(height: 24),
              Row(
                children: [
                  Text(l10n.propTotal, style: theme.textTheme.titleSmall),
                  const Spacer(),
                  Text(
                    result.score.total.toStringAsFixed(3),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (result.insufficient || result.overdue) ...[
                const SizedBox(height: 8),
                Text(
                  result.overdue
                      ? l10n.propFlagOverdue
                      : l10n.propFlagInsufficient,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ] else if (result.expectedNear) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.propFlagExpectedNear,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.amber.shade800,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  const Spacer(),
                  IconButton(
                    tooltip: l10n.propResetWeights,
                    icon: const Icon(Icons.restart_alt),
                    onPressed: () async {
                      await ref.read(threadRankRepositoryProvider).resetWeights();
                      ref.invalidate(currentWeightsProvider);
                      await ref.read(threadFeedProvider.notifier).sort();
                    },
                  ),
                  IconButton(
                    tooltip: l10n.propWeights,
                    icon: const Icon(Icons.tune),
                    onPressed: () => showWeightsEditor(context, ref),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScoreMeter extends StatelessWidget {
  const _ScoreMeter({
    required this.label,
    required this.value,
    required this.weight,
    required this.contribution,
    this.penalizes = false,
  });

  final String label;
  final double value;
  final double weight;
  final double contribution;
  final bool penalizes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
              Text(
                '${value.toStringAsFixed(2)} × ${weight.toStringAsFixed(2)} = '
                '${contribution >= 0 ? '+' : ''}${contribution.toStringAsFixed(3)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              minHeight: 6,
              color: penalizes
                  ? theme.colorScheme.outline
                  : theme.colorScheme.primary,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

/// Weight editor: the same numbers the engine uses, editable by the user.
Future<void> showWeightsEditor(BuildContext context, WidgetRef ref) async {
  final weights = await ref.read(threadRankRepositoryProvider).getWeights();
  if (!context.mounted) {
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (context) => _WeightsDialog(initial: weights),
  );
  await ref.read(threadFeedProvider.notifier).sort();
}

class _WeightsDialog extends ConsumerStatefulWidget {
  const _WeightsDialog({required this.initial});

  final RankWeights initial;

  @override
  ConsumerState<_WeightsDialog> createState() => _WeightsDialogState();
}

class _WeightsDialogState extends ConsumerState<_WeightsDialog> {
  late double _urgency = widget.initial.urgency;
  late double _goal = widget.initial.goal;
  late double _fit = widget.initial.fit;
  late double _fatigue = widget.initial.fatigue;
  late double _expected = widget.initial.expected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.propWeights),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _weightSlider(l10n.propUrgency, _urgency,
                (v) => setState(() => _urgency = v)),
            _weightSlider(l10n.propGoalMatch, _goal,
                (v) => setState(() => _goal = v)),
            _weightSlider(l10n.propFit, _fit, (v) => setState(() => _fit = v)),
            _weightSlider(l10n.propExpectedPressure, _expected,
                (v) => setState(() => _expected = v)),
            _weightSlider(l10n.propFatigue, _fatigue,
                (v) => setState(() => _fatigue = v)),
            const SizedBox(height: 8),
            Text(l10n.propWeightsHint, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      actions: [
        IconButton(
          tooltip: l10n.commonCancel,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        IconButton.filled(
          tooltip: l10n.commonSave,
          icon: const Icon(Icons.check),
          onPressed: () async {
            await ref.read(threadRankRepositoryProvider).updateWeights(
                  urgency: _urgency,
                  goal: _goal,
                  fit: _fit,
                  fatigue: _fatigue,
                  expected: _expected,
                );
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          },
        ),
      ],
    );
  }

  Widget _weightSlider(String label, double value, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 96, child: Text(label)),
        Expanded(
          child: Slider(
            value: value,
            min: 0,
            max: 1,
            divisions: 20,
            label: value.toStringAsFixed(2),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(value.toStringAsFixed(2), textAlign: TextAlign.end),
        ),
      ],
    );
  }
}

/// Convenience used by the list: opens the property page for [task].
Future<void> openEventProperties(BuildContext context, Task task) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => EventPropertiesPage(taskId: task.id),
    ),
  );
}

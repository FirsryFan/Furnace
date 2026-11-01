import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/repository_providers.dart';
import '../../../../domain/services/cognitive/study_rhythm.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/energy_prediction_provider.dart';
import '../../application/study_rhythm_reader.dart';
import '../../application/thread_rank_service.dart';
import 'energy_bar.dart';

/// Thread status bar (blueprint 2.2; user annotations 2, 3, 4, 8, 10).
///
/// - Collapsible: on phones it folds down to a very narrow strip.
/// - The goal is NOT shown in full: only a title (ellipsized) next to a target
///   icon that opens the full editor.
/// - Energy is a red-to-green chip button carrying only the number.
/// - Sorting is a single icon button; every button here is an icon button.
class ThreadStatusBar extends ConsumerStatefulWidget {
  const ThreadStatusBar({super.key, required this.onOpenProperties});

  /// Opens the property page of the event currently in focus, if any.
  final VoidCallback? onOpenProperties;

  @override
  ConsumerState<ThreadStatusBar> createState() => _ThreadStatusBarState();
}

class _ThreadStatusBarState extends ConsumerState<ThreadStatusBar> {
  bool _collapsed = false;
  bool _loadedCollapsed = false;
  bool _sorting = false;

  @override
  void initState() {
    super.initState();
    _loadCollapsed();
  }

  Future<void> _loadCollapsed() async {
    final collapsed =
        await ref.read(threadRankRepositoryProvider).isHeaderCollapsed();
    if (!mounted) {
      return;
    }
    setState(() {
      _collapsed = collapsed;
      _loadedCollapsed = true;
    });
  }

  Future<void> _toggleCollapsed() async {
    final next = !_collapsed;
    setState(() => _collapsed = next);
    await ref.read(threadRankRepositoryProvider).setHeaderCollapsed(next);
  }

  /// Shared sort flow: confirm a >2h-stale status bar first, then sort
  /// (user annotation 10: confirming sorts immediately).
  Future<void> _sort() async {
    if (_sorting) {
      return;
    }
    setState(() => _sorting = true);
    try {
      final notifier = ref.read(threadFeedProvider.notifier);
      final stale = await notifier.isStateStale();
      if (!mounted) {
        return;
      }
      if (stale) {
        final proceed = await _confirmStale();
        if (proceed != true) {
          return;
        }
        // Confirming refreshes the stamp so the prompt does not nag again.
        await ref
            .read(threadStateRepositoryProvider)
            .updateState(updatedAt: DateTime.now());
      }
      await notifier.sort();
    } finally {
      if (mounted) {
        setState(() => _sorting = false);
      }
    }
  }

  Future<bool?> _confirmStale() {
    final l10n = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.threadStaleTitle),
        content: Text(l10n.threadStaleBody),
        actions: [
          IconButton(
            tooltip: l10n.commonCancel,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          IconButton.filled(
            tooltip: l10n.commonConfirm,
            icon: const Icon(Icons.check),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
  }

  /// "Use prediction": the user explicitly accepts the MindNet value, so it is
  /// written exactly like a hand-filled one (energy + updated_at, stamped by the
  /// repository). The prediction then reports the manual window - which is why
  /// the "手动" badge replaces the button afterwards.
  Future<void> _usePrediction(int level) async {
    await ref.read(threadStateRepositoryProvider).updateState(energy: level);
    ref.invalidate(threadStateProvider);
    ref.invalidate(energyPredictionProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(threadStateProvider);
    final energyPrediction = ref.watch(energyPredictionProvider);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: _collapsed ? 4 : 10,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (!_collapsed) ...[
                  _GoalButton(
                    goalText: state.valueOrNull?.goalText,
                    onChanged: (text) async {
                      await ref
                          .read(threadStateRepositoryProvider)
                          .updateState(goalText: text, clearGoal: text.isEmpty);
                      ref.invalidate(threadStateProvider);
                    },
                  ),
                  const SizedBox(width: 8),
                ],
                EnergyBar(
                  energy: state.valueOrNull?.energy,
                  compact: _collapsed,
                  onChanged: (value) async {
                    await ref
                        .read(threadStateRepositoryProvider)
                        .updateState(energy: value);
                    ref.invalidate(threadStateProvider);
                    // The prediction's "manual" badge is derived from the same
                    // row; refresh it even where no write hook is installed.
                    ref.invalidate(energyPredictionProvider);
                  },
                ),
                const Spacer(),
                IconButton(
                  tooltip: _collapsed ? l10n.threadExpand : l10n.threadCollapse,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    _collapsed ? Icons.unfold_more : Icons.unfold_less,
                  ),
                  onPressed: _loadedCollapsed ? _toggleCollapsed : null,
                ),
                IconButton(
                  tooltip: l10n.commonEdit,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.tune),
                  onPressed: widget.onOpenProperties,
                ),
                if (_sorting)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton.filled(
                    tooltip: l10n.threadSort,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.refresh),
                    onPressed: _sort,
                  ),
              ],
            ),
            // Collapsed, the strip is a single row by design: the reading is the
            // first thing to go (the prediction line goes with it).
            if (!_collapsed) ...[
              _EnergyPredictionHint(
                snapshot: energyPrediction.valueOrNull,
                onUsePrediction: _usePrediction,
              ),
              const _AttentionHint(),
            ],
          ],
        ),
      ),
    );
  }
}

/// The attention-availability reading plus its advice (roadmap §3 row 4).
///
/// Derived, not measured: [StudyRhythm] turns the app's own study log into
/// "minutes into the current sitting" and asks the same uncalibrated
/// `rhythm.gate` parameter the engine uses. So the widget prints the number and
/// the advice together, says the parameter is uncalibrated in the tooltip, and
/// vanishes when the user turns the switch off (no query, no number).
class _AttentionHint extends ConsumerWidget {
  const _AttentionHint();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final snapshot = ref.watch(studyRhythmProvider).valueOrNull;
    // While loading (or while the switch is off) show nothing: a placeholder
    // that flickers into a number would read as if the number had changed.
    if (snapshot == null || !snapshot.enabled) {
      return const SizedBox.shrink();
    }

    final reading = snapshot.reading;
    if (reading == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Icon(
              Icons.hourglass_empty,
              size: 16,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                l10n.threadRhythmEmpty,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final advice = switch (reading.advice) {
      StudyAdvice.hard => l10n.threadRhythmAdviceHard,
      StudyAdvice.moderate => l10n.threadRhythmAdviceModerate,
      StudyAdvice.rest => l10n.threadRhythmAdviceRest,
      StudyAdvice.none => l10n.threadRhythmEmpty,
    };
    final text = l10n.threadRhythmReading(
      reading.vigilancePercent,
      reading.minutesOnRounded,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Tooltip(
            message: l10n.threadRhythmUncalibrated,
            child: Icon(
              Icons.timelapse,
              size: 16,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '$text · $advice',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          IconButton(
            tooltip: l10n.threadRhythmHide,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.visibility_off, size: 18),
            onPressed: () async {
              await ref
                  .read(settingsRepositoryProvider)
                  .updateRhythmHintsEnabled(false);
              ref.invalidate(studyRhythmProvider);
              ref.invalidate(rhythmHintsEnabledProvider);
            },
          ),
        ],
      ),
    );
  }
}

/// The MindNet energy-prediction line under the energy chip (D13).
///
/// Shows the predicted level and its confidence, explains where it came from in
/// the tooltip (the predictor's own basis lines plus the uncalibrated note - the
/// number must not read as a measurement), and offers "use prediction". When the
/// status-bar value is the user's own recent hand-filled one, a "manual" badge
/// replaces that button: writing the prediction back would be a no-op by
/// definition, and the value on screen is already the user's own.
class _EnergyPredictionHint extends StatelessWidget {
  const _EnergyPredictionHint({
    required this.snapshot,
    required this.onUsePrediction,
  });

  /// Null while loading: nothing is drawn, so the bar never flickers between the
  /// old and the new number.
  final EnergyPredictionSnapshot? snapshot;

  /// Writes [EnergyPrediction.level] as the status-bar energy.
  final ValueChanged<int> onUsePrediction;

  @override
  Widget build(BuildContext context) {
    final snapshot = this.snapshot;
    if (snapshot == null) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final prediction = snapshot.prediction;
    final manual = snapshot.manualOverrideActive;
    final confidence = '${(prediction.confidence * 100).round()}%';

    return Padding(
      key: const Key('threadEnergyPredictionRow'),
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Tooltip(
            message: '${l10n.threadEnergyPredictedNote}\n\n'
                '${prediction.basis.join('\n')}',
            child: Icon(
              Icons.auto_awesome,
              size: 16,
              color: manual
                  ? theme.colorScheme.outline
                  : theme.colorScheme.tertiary,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              l10n.threadEnergyPredicted(prediction.level, confidence),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (manual) ...[
            const SizedBox(width: 6),
            Container(
              key: const Key('threadEnergyManualBadge'),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                l10n.threadEnergyManualBadge,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ] else if (prediction.confidence > 0)
            TextButton(
              key: const Key('threadEnergyUsePrediction'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => onUsePrediction(prediction.level),
              child: Text(l10n.threadEnergyUsePrediction),
            ),
        ],
      ),
    );
  }
}

/// The goal is shown as a title only; tapping opens the full editor, because
/// a long goal never fits in the status bar (user annotation 2).
class _GoalButton extends StatelessWidget {
  const _GoalButton({required this.goalText, required this.onChanged});

  final String? goalText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final text = goalText;
    final hasGoal = text != null && text.trim().isNotEmpty;

    return Tooltip(
      message: hasGoal ? text : l10n.threadGoalEmpty,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () =>
            showGoalEditor(context, initial: text, onChanged: onChanged),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.my_location,
                  size: 18,
                  color: hasGoal
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    hasGoal ? text : l10n.threadGoalEmpty,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: hasGoal
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full goal editor opened from the status bar title.
Future<String?> showGoalEditor(
  BuildContext context, {
  required String? initial,
  required ValueChanged<String> onChanged,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _GoalDialog(initial: initial, onChanged: onChanged),
  );
}

class _GoalDialog extends StatefulWidget {
  const _GoalDialog({required this.initial, required this.onChanged});

  final String? initial;
  final ValueChanged<String> onChanged;

  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.my_location),
          const SizedBox(width: 8),
          Expanded(child: Text(l10n.threadGoal)),
        ],
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 1,
        maxLines: 3,
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
      actions: [
        IconButton(
          tooltip: l10n.commonCancel,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        IconButton(
          tooltip: l10n.commonClear,
          icon: const Icon(Icons.backspace_outlined),
          onPressed: () {
            widget.onChanged('');
            Navigator.of(context).pop('');
          },
        ),
        IconButton.filled(
          tooltip: l10n.commonSave,
          icon: const Icon(Icons.check),
          onPressed: () {
            final text = _controller.text.trim();
            widget.onChanged(text);
            Navigator.of(context).pop(text);
          },
        ),
      ],
    );
  }
}

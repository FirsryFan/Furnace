import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/repository_providers.dart';
import '../../../../l10n/app_localizations.dart';
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(threadStateProvider);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: _collapsed ? 4 : 10,
        ),
        child: Row(
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
              },
            ),
            const Spacer(),
            IconButton(
              tooltip: _collapsed ? l10n.threadExpand : l10n.threadCollapse,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                _collapsed
                    ? Icons.unfold_more
                    : Icons.unfold_less,
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
        onTap: () => showGoalEditor(context, initial: text, onChanged: onChanged),
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

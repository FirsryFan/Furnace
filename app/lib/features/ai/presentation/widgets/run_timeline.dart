import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/agent_loop.dart';

/// Key of the timeline container (present only while the turn has steps).
const Key runTimelineKey = Key('ai-run-timeline');

/// Key of the one-line summary shown when the timeline is collapsed.
const Key runTimelineSummaryKey = Key('ai-run-timeline-summary');

/// Key of the expand/collapse header.
const Key runTimelineHeaderKey = Key('ai-run-timeline-header');

/// Key of one step row, addressed by [AgentStep.id].
Key runTimelineStepKey(int id) => Key('ai-run-timeline-step-$id');

/// The turn's live timeline: one row per model round / tool call.
///
/// Why this exists (user 2026-10-27): the chat used to show a single growing
/// answer block, so a long tool-heavy turn looked frozen - the only sign of
/// life was the thin progress bar. This panel draws every step as it starts,
/// in the order the loop runs them:
///
///  * a model round (thinking / writing),
///  * a tool call (which one, with the argument summary),
///  * the approval pause (a proposed call waiting for the user),
///  * the outcome (done / failed / cancelled) with its summary.
///
/// The elapsed readout of the running row ticks once a second; a finished row
/// shows its measured duration. Rows are ordered by when they started and are
/// updated in place, because [AgentTurnState.steps] replaces the step object
/// rather than appending a new one for every event.
///
/// The panel is expanded while the turn is live and folds into a one-line
/// summary ("本轮 N 步") once it ends, so a finished chat does not stay full of
/// transient furniture. A tap toggles it; the next turn starts expanded again.
class RunTimeline extends StatefulWidget {
  const RunTimeline({
    super.key,
    required this.state,
    required this.l10n,
    this.now,
  });

  final AgentTurnState state;

  final AppLocalizations l10n;

  /// Clock used for the running row's elapsed readout. Injectable so a widget
  /// test can advance it without waiting in real time.
  final DateTime Function()? now;

  @override
  State<RunTimeline> createState() => _RunTimelineState();
}

class _RunTimelineState extends State<RunTimeline> {
  Timer? _ticker;

  /// Whether the user overrode the automatic expansion for the current turn.
  ///
  /// Null means "follow the turn": expanded while it runs, folded after. A tap
  /// sets it, and the next turn clears it - otherwise one fold would stick for
  /// the rest of the conversation.
  bool? _manualExpanded;

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  bool get _live => widget.state.generating || widget.state.hasPending;

  bool get _hasRunningStep => widget.state.steps.any((step) => step.isRunning);

  bool get _expanded => _manualExpanded ?? _live;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant RunTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasLive = oldWidget.state.generating || oldWidget.state.hasPending;
    if (!wasLive && _live) {
      // A new turn starts: forget the previous override, so the fresh
      // timeline opens by itself.
      _manualExpanded = null;
    }
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Runs a one-second ticker only while a row is actually counting.
  void _syncTicker() {
    final needsTicker = _expanded && _hasRunningStep;
    if (needsTicker && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {});
        }
      });
    } else if (!needsTicker) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _toggle() {
    setState(() {
      _manualExpanded = !_expanded;
    });
    _syncTicker();
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.state.steps;
    if (steps.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final l10n = widget.l10n;
    final expanded = _expanded;
    final writing = widget.state.streamingText.isNotEmpty;

    return Container(
      key: runTimelineKey,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: runTimelineHeaderKey,
            borderRadius: BorderRadius.circular(8),
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(
                    expanded ? Icons.timeline : Icons.checklist,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      expanded
                          ? l10n.aiStepsTitle
                          : l10n.aiStepsSummary(steps.length),
                      key: expanded ? null : runTimelineSummaryKey,
                      style: theme.textTheme.labelLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (expanded)
                    Text(
                      l10n.aiStepsSummary(steps.length),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            for (final step in steps)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _StepRow(
                  key: runTimelineStepKey(step.id),
                  step: step,
                  l10n: l10n,
                  now: _now(),
                  writing: writing,
                ),
              ),
        ],
      ),
    );
  }
}

/// One timeline row: status glyph, what is happening, and how long it took.
class _StepRow extends StatelessWidget {
  const _StepRow({
    super.key,
    required this.step,
    required this.l10n,
    required this.now,
    required this.writing,
  });

  final AgentStep step;
  final AppLocalizations l10n;
  final DateTime now;

  /// Whether the current model round has started producing answer text. Read
  /// off [AgentTurnState.streamingText]: no characters yet means the model is
  /// still reasoning, which is the phase worth telling apart from "writing".
  final bool writing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.textTheme.bodyMedium;
    final secondary = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    final title = switch (step.kind) {
      AgentStepKind.model => step.isRunning
          ? '${l10n.aiStepRound(step.round)} · '
              '${writing ? l10n.aiStepAnswering : l10n.aiStepThinking}'
          : l10n.aiStepRound(step.round),
      AgentStepKind.tool => l10n.aiStepCalling(step.toolName ?? step.title),
    };

    final detail = step.detail.trim().isEmpty
        ? (step.summary?.trim() ?? '')
        : step.detail.trim();
    final summary = step.summary?.trim() ?? '';
    final showSummary = summary.isNotEmpty && summary != detail;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: _statusGlyph(theme),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: primary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (detail.isNotEmpty)
                Text(
                  detail,
                  style: secondary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              if (showSummary)
                Text(
                  summary,
                  style: secondary?.copyWith(fontStyle: FontStyle.italic),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _trailing(step),
          style: theme.textTheme.labelSmall?.copyWith(
            color: step.isWaiting
                ? theme.colorScheme.tertiary
                : theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }

  String _trailing(AgentStep step) {
    switch (step.status) {
      case AgentStepStatus.waiting:
        return l10n.aiStepWaiting;
      case AgentStepStatus.failed:
        return l10n.aiStepFailed;
      case AgentStepStatus.cancelled:
        return l10n.aiStepCancelled;
      case AgentStepStatus.running:
        return l10n.aiStepElapsed(
          '${now.difference(step.startedAt).inSeconds}',
        );
      case AgentStepStatus.done:
        final elapsed = step.elapsed;
        return elapsed == null
            ? l10n.aiStepDone
            : l10n.aiStepElapsed('${elapsed.inSeconds}');
    }
  }

  Widget _statusGlyph(ThemeData theme) {
    switch (step.status) {
      case AgentStepStatus.running:
        return const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case AgentStepStatus.waiting:
        return Icon(
          Icons.hourglass_top,
          size: 15,
          color: theme.colorScheme.tertiary,
        );
      case AgentStepStatus.failed:
        return Icon(Icons.error, size: 15, color: theme.colorScheme.error);
      case AgentStepStatus.cancelled:
        return Icon(Icons.cancel, size: 15, color: theme.colorScheme.outline);
      case AgentStepStatus.done:
        return step.ok == false
            ? Icon(Icons.error, size: 15, color: theme.colorScheme.error)
            : Icon(
                Icons.check_circle,
                size: 15,
                color: theme.colorScheme.primary,
              );
    }
  }
}

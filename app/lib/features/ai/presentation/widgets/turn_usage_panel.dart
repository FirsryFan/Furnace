import 'dart:async';

import 'package:flutter/material.dart';
import 'package:furnace/l10n/app_localizations.dart';

import '../../domain/agent_loop.dart';

/// What the turn/usage panel should show right now.
///
/// Split from [TurnUsage] because the panel has to answer a second question -
/// "is this the turn that is running, or the last one that finished?" - and the
/// usage itself must not carry presentation state.
class TurnUsageView {
  const TurnUsageView({this.usage, this.generating = false});

  /// The turn to describe, or `null` when nothing has been measured yet.
  final TurnUsage? usage;

  /// A round is in flight, so the rate is a live estimate rather than a frozen
  /// measurement.
  final bool generating;

  /// Whether there is anything to draw. An untouched turn is hidden rather than
  /// shown as six zeros.
  bool get hasData => usage != null && !usage!.isEmpty;

  /// Nothing measured yet.
  static const TurnUsageView empty = TurnUsageView();
}

/// Keeps "what the running turn used" and "what the last finished turn used".
///
/// The loop resets its usage when a new user message starts, so a panel reading
/// [AgentLoop.state] directly would blank out at exactly the moment the user
/// sends the next message. Remembering the last finished turn here is what lets
/// the panel keep showing a summary, and it keeps the page free of bookkeeping.
///
/// A [ValueNotifier] rather than a Riverpod provider: it is a pure view of one
/// loop's state stream, it owns no services, and nothing else in the app needs
/// to read it.
class TurnUsageNotifier extends ValueNotifier<TurnUsageView> {
  TurnUsageNotifier({
    Stream<AgentTurnState>? states,
    AgentTurnState initial = const AgentTurnState(),
  }) : super(TurnUsageView.empty) {
    attach(states: states, initial: initial);
  }

  /// Follows the loop the page is bound to.
  factory TurnUsageNotifier.forLoop(AgentLoop? loop) => TurnUsageNotifier(
        states: loop?.states,
        initial: loop?.state ?? const AgentTurnState(),
      );

  StreamSubscription<AgentTurnState>? _subscription;
  TurnUsage? _lastCompleted;

  /// Follows [states] from now on, replacing any previous subscription, and
  /// starts from [initial] - the state the loop is already in. Called when the
  /// page binds to a different conversation, whose loop is a different object
  /// with its own turn.
  ///
  /// Takes a stream rather than an [AgentLoop] so the bookkeeping can be tested
  /// without a database, a provider or a socket.
  void attach({
    Stream<AgentTurnState>? states,
    AgentTurnState initial = const AgentTurnState(),
  }) {
    _subscription?.cancel();
    _lastCompleted = null;
    // Seeded first, and unconditionally: the state the loop is already in counts
    // even when the notifier is handed no stream (a caller that only wants to
    // render one known state), and a page attached to a conversation whose turn
    // already ran must show that turn rather than wait for the next event.
    value = TurnUsageView.empty;
    _onState(initial);
    _subscription = states?.listen(_onState);
  }

  void _onState(AgentTurnState state) {
    final usage = state.usage;
    if (usage.isEmpty) {
      // A fresh user message: the loop has nothing measured for the new turn
      // yet, so the previous one stays on screen. It is shown as finished
      // rather than live, because it is not the turn being generated.
      value = TurnUsageView(usage: _lastCompleted);
      return;
    }
    if (state.generating || state.hasPending) {
      value = TurnUsageView(usage: usage, generating: state.generating);
      return;
    }
    _lastCompleted = usage;
    value = TurnUsageView(usage: usage);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

/// The turn/usage panel: rounds, tool calls, tokens, rate, cache hits and
/// context occupancy for one turn.
///
/// Six figures, each of which is either measured or a dash - never a plausible
/// number standing in for a missing one. Collapsible, and collapsed it still
/// shows the two figures a user glances at (rounds and rate) in its subtitle,
/// so folding it away hides detail rather than information.
class TurnUsagePanel extends StatelessWidget {
  const TurnUsagePanel({super.key, required this.view});

  final TurnUsageView view;

  /// Stable keys for the six value rows. The UI test reads the figures through
  /// these instead of by label text, so a translation cannot break it.
  static const Key roundsKey = ValueKey('turn-usage-rounds');
  static const Key stepsKey = ValueKey('turn-usage-steps');
  static const Key totalTokensKey = ValueKey('turn-usage-total-tokens');
  static const Key rateKey = ValueKey('turn-usage-tokens-per-second');
  static const Key cacheKey = ValueKey('turn-usage-cache-hit');
  static const Key contextKey = ValueKey('turn-usage-context');

  @override
  Widget build(BuildContext context) {
    final usage = view.usage;
    if (usage == null || usage.isEmpty) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dash = l10n.aiUsageUnavailable;

    final rate =
        view.generating ? usage.liveTokensPerSecond : usage.tokensPerSecond;
    // The live figure is marked as an estimate at the point of display, not in
    // a footnote: while a round is streaming the provider has not reported a
    // token count yet, and the number on screen is derived from characters.
    final rateText = rate == null
        ? dash
        : view.generating
            ? '≈${rate.toStringAsFixed(1)}'
            : rate.toStringAsFixed(1);

    final cacheRatio = usage.cacheHitRatio;
    final contextRatio = usage.contextUsageRatio;

    final stepNotes = <String>[
      if (usage.toolCallsPending > 0)
        l10n.aiUsagePending(usage.toolCallsPending),
      if (usage.toolCallsRejected > 0)
        l10n.aiUsageRejected(usage.toolCallsRejected),
    ];

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: ExpansionTile(
        // All six figures stay visible without a tap - that is the point of the
        // strip - but they are laid out as a wrap of compact chips rather than
        // six stacked label/value/note rows: the rows made the panel tall enough
        // to push the conversation column past the bottom of a short window (a
        // 600px-tall surface, a landscape phone). The note, which is where
        // "this is an estimate" lives, moved into the chip's tooltip.
        initiallyExpanded: true,
        leading: Icon(Icons.speed_outlined, color: theme.colorScheme.primary),
        title: Text(
          view.generating ? l10n.aiUsageCurrent : l10n.aiUsageLast,
          style: theme.textTheme.titleSmall,
        ),
        subtitle: Text(
          '${l10n.aiUsageRounds} ${usage.rounds} / ${usage.maxRounds}'
          ' · ${l10n.aiUsageTokensPerSecond} $rateText',
          style: theme.textTheme.bodySmall,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          _figure(
            context,
            key: roundsKey,
            label: l10n.aiUsageRounds,
            value: '${usage.rounds} / ${usage.maxRounds}',
          ),
          _figure(
            context,
            key: stepsKey,
            label: l10n.aiUsageSteps,
            value: '${usage.toolCallsExecuted}',
            note: stepNotes.isEmpty ? null : stepNotes.join(' · '),
          ),
          _figure(
            context,
            key: totalTokensKey,
            label: l10n.aiUsageTotalTokens,
            value: usage.hasUsage ? '${usage.totalTokens}' : dash,
            note: usage.hasUsage
                ? l10n.aiUsagePromptCompletion(
                    usage.promptTokens,
                    usage.completionTokens,
                  )
                : l10n.aiUsageNoUsage,
          ),
          _figure(
            context,
            key: rateKey,
            label: l10n.aiUsageTokensPerSecond,
            value: rateText,
            note: view.generating ? l10n.aiUsageLiveEstimate : null,
          ),
          _figure(
            context,
            key: cacheKey,
            label: l10n.aiUsageCacheHit,
            value: cacheRatio == null ? dash : _percent(cacheRatio),
            note: cacheRatio == null
                ? l10n.aiUsageCacheAbsent
                : (usage.cacheAccountingIsPartial
                    ? l10n.aiUsageCachePartial
                    : null),
          ),
          _figure(
            context,
            key: contextKey,
            label: l10n.aiUsageContext,
            value: contextRatio == null ? dash : _percent(contextRatio),
            note: contextRatio == null
                ? null
                : l10n.aiUsageContextEstimate(usage.contextWindowTokens),
          ),
        ],
      ),
    );
  }

  /// One figure: a label, a value and an optional one-line explanation of how
  /// the value was obtained. The explanation is where "estimate" lives, so the
  /// number itself never has to carry a caveat it would then have to drop.
  Widget _figure(
    BuildContext context, {
    required Key key,
    required String label,
    required String value,
    String? note,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, key: key, style: theme.textTheme.bodyMedium),
                if (note != null)
                  Text(
                    note,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: theme.colorScheme.outline,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _percent(double ratio) =>
      '${(ratio * 100).toStringAsFixed(1)}%';
}

/// The panel bound to a loop's live state, ready to drop into a page.
///
/// The page supplies the notifier (it owns the loop and its lifetime); this
/// widget only listens and draws.
class TurnUsageSection extends StatelessWidget {
  const TurnUsageSection({super.key, required this.notifier});

  final TurnUsageNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TurnUsageView>(
      valueListenable: notifier,
      builder: (context, view, _) => TurnUsagePanel(view: view),
    );
  }
}

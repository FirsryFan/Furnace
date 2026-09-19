import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/srs/fsrs_scheduler.dart';
import '../../../l10n/app_localizations.dart';
import '../application/review_service.dart';

/// Practice screen (blueprint 4.3; user annotations 17, 18, 19).
///
/// Kept deliberately plain so the user can reach flow: one blank per question,
/// no statistics, no boost badges. Everything analytical lives in the separate
/// insight screen.
class ReviewPage extends ConsumerStatefulWidget {
  const ReviewPage({super.key});

  @override
  ConsumerState<ReviewPage> createState() => _ReviewPageState();
}

/// What happened to the answer just submitted.
class _Feedback {
  const _Feedback({
    required this.correct,
    required this.expected,
    required this.submitted,
  });

  final bool correct;
  final String expected;
  final String submitted;
}

class _ReviewPageState extends ConsumerState<ReviewPage> {
  final _answer = TextEditingController();
  final _scroll = ScrollController();

  List<ReviewItem> _queue = const [];
  int _index = 0;
  bool _loading = true;
  bool _submitting = false;
  _Feedback? _feedback;
  DateTime? _shownAt;
  ReviewOutcome? _outcome;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _answer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final queue = await ref.read(reviewServiceProvider).buildQueue();
    if (!mounted) {
      return;
    }
    setState(() {
      _queue = queue;
      _index = 0;
      _feedback = null;
      _outcome = null;
      _answer.clear();
      _shownAt = DateTime.now();
      _loading = false;
    });
  }

  ReviewItem? get _current =>
      _index >= 0 && _index < _queue.length ? _queue[_index] : null;

  Future<void> _submit() async {
    final item = _current;
    if (item == null || _submitting) {
      return;
    }
    final submitted = _answer.text.trim();
    // Strict grading: exact characters, no normalisation (annotation 18).
    final correct = ReviewService.strictMatch(item.answer, submitted);
    setState(() {
      _submitting = true;
      _feedback = _Feedback(
        correct: correct,
        expected: item.answer,
        submitted: submitted,
      );
    });
    final outcome = await ref.read(reviewServiceProvider).grade(
          item: item,
          correct: correct,
          // The rating index is refined by the self-assessment buttons when
          // the answer was right; a wrong answer is always Again.
          rating: FsrsRating.good,
          submitted: submitted,
          responseSeconds: _shownAt == null
              ? null
              : DateTime.now().difference(_shownAt!).inSeconds,
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _submitting = false;
      _outcome = outcome;
    });
  }

  Future<void> _reveal() async {
    final item = _current;
    if (item == null) {
      return;
    }
    setState(() {
      _feedback = _Feedback(
        correct: false,
        expected: item.answer,
        submitted: '',
      );
      _outcome = null;
    });
  }

  /// Records the self-assessment and moves on.
  Future<void> _rate(FsrsRating rating) async {
    final item = _current;
    if (item == null) {
      return;
    }
    final outcome = _outcome;
    if (outcome != null && outcome.correct && rating != FsrsRating.again) {
      // Re-grade only to adjust the interval for the chosen grade.
      await ref.read(reviewServiceProvider).grade(
            item: item,
            correct: true,
            rating: rating,
            responseSeconds: _shownAt == null
                ? null
                : DateTime.now().difference(_shownAt!).inSeconds,
          );
    }
    await ref.read(reviewServiceProvider).consumeBoost(item.knowledgePointId);
    if (!mounted) {
      return;
    }
    setState(() {
      _index++;
      _feedback = null;
      _outcome = null;
      _answer.clear();
      _shownAt = DateTime.now();
    });
    if (_scroll.hasClients) {
      _scroll.jumpTo(0);
    }
  }

  Future<void> _generateTask() async {
    final item = _current;
    if (item == null) {
      return;
    }
    await ref.read(reviewServiceProvider).createEventFromItem(item);
    if (!mounted) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${l10n.knowledgeTaskCreated}: ${item.title}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_queue.isEmpty) {
      return _EmptyState(onReload: _load);
    }
    final item = _current;
    if (item == null) {
      return _FinishedState(onReload: _load);
    }

    final forcedCount = _queue.where((i) => i.cardState.forced == 1).length;
    return Column(
      children: [
        _ProgressHeader(
          remaining: _queue.length - _index,
          total: _queue.length,
          active: forcedCount,
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 16),
                SelectableText(
                  item.question,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        height: 1.75,
                      ),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _answer,
                  autofocus: true,
                  enabled: _feedback == null,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    if (_feedback == null) {
                      _submit();
                    }
                  },
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: l10n.ankiYourAnswer,
                    suffixIcon: _feedback == null
                        ? IconButton(
                            tooltip: l10n.ankiSubmit,
                            icon: const Icon(Icons.check),
                            onPressed: _submit,
                          )
                        : null,
                  ),
                ),
                if (_feedback != null) ...[
                  const SizedBox(height: 20),
                  _FeedbackCard(feedback: _feedback!, outcome: _outcome),
                ],
              ],
            ),
          ),
        ),
        _BottomBar(
          feedback: _feedback,
          submitting: _submitting,
          onReveal: _reveal,
          onRate: _rate,
          onGenerateTask: _generateTask,
        ),
      ],
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({
    required this.remaining,
    required this.total,
    required this.active,
  });

  final int remaining;
  final int total;
  final int active;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final done = total - remaining;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        children: [
          Row(
            children: [
              Text(l10n.knowledgeRemaining(remaining),
                  style: theme.textTheme.bodyMedium),
              const Spacer(),
              if (active > 0)
                Row(
                  children: [
                    Icon(Icons.replay,
                        size: 16, color: theme.colorScheme.error),
                    const SizedBox(width: 4),
                    Text(
                      l10n.knowledgeActiveCount(active),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 4,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.feedback, required this.outcome});

  final _Feedback feedback;
  final ReviewOutcome? outcome;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final correct = feedback.correct;
    final color = correct ? Colors.green.shade700 : theme.colorScheme.error;

    return Card(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(correct ? Icons.check_circle : Icons.cancel, color: color),
                const SizedBox(width: 8),
                Text(
                  correct ? l10n.ankiCorrect : l10n.ankiWrong,
                  style: theme.textTheme.titleMedium?.copyWith(color: color),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('${l10n.ankiAnswer}: ${feedback.expected}'),
            if (!correct && feedback.submitted.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('${l10n.ankiYourAnswer}: ${feedback.submitted}'),
            ],
            if (outcome != null) ...[
              const SizedBox(height: 10),
              Text(
                outcome!.stillForced
                    ? l10n.knowledgeWillRepeat
                    : l10n.knowledgeNextIn(outcome!.scheduledDays),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (outcome!.boosted.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  l10n.knowledgeBoosted(
                    outcome!.boosted.length,
                    outcome!.boosted.first.factor.toStringAsFixed(1),
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.feedback,
    required this.submitting,
    required this.onReveal,
    required this.onRate,
    required this.onGenerateTask,
  });

  final _Feedback? feedback;
  final bool submitting;
  final VoidCallback onReveal;
  final ValueChanged<FsrsRating> onRate;
  final VoidCallback onGenerateTask;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: feedback == null
            ? Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    tooltip: l10n.ankiShowAnswer,
                    icon: const Icon(Icons.visibility),
                    onPressed: onReveal,
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    tooltip: l10n.ankiForgot,
                    icon: const Icon(Icons.replay),
                    color: Theme.of(context).colorScheme.error,
                    onPressed: submitting
                        ? null
                        : () => onRate(FsrsRating.again),
                  ),
                  IconButton(
                    tooltip: l10n.ankiFuzzy,
                    icon: const Icon(Icons.trending_flat),
                    onPressed:
                        submitting ? null : () => onRate(FsrsRating.hard),
                  ),
                  IconButton.filled(
                    tooltip: l10n.ankiRemembered,
                    icon: const Icon(Icons.check),
                    onPressed:
                        submitting ? null : () => onRate(FsrsRating.good),
                  ),
                  IconButton(
                    tooltip: l10n.knowledgeCreateTask,
                    icon: const Icon(Icons.add_task),
                    onPressed: onGenerateTask,
                  ),
                ],
              ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onReload});

  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline,
              size: 44, color: Colors.green.shade600),
          const SizedBox(height: 12),
          Text(l10n.ankiNoDueCards),
          const SizedBox(height: 12),
          IconButton(
            tooltip: l10n.commonRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: onReload,
          ),
        ],
      ),
    );
  }
}

class _FinishedState extends StatelessWidget {
  const _FinishedState({required this.onReload});

  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.emoji_events_outlined,
              size: 48, color: Colors.amber.shade700),
          const SizedBox(height: 12),
          Text(l10n.knowledgeSessionDone),
          const SizedBox(height: 12),
          IconButton.filled(
            tooltip: l10n.commonRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: onReload,
          ),
        ],
      ),
    );
  }
}

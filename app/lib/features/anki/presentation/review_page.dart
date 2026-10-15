import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/srs/dsr_card_state.dart';
import '../../../domain/services/srs/fsrs_scheduler.dart';
import '../../../l10n/app_localizations.dart';
// The tierB verdict shown on a card is read from the very reading the 认知模型
// page renders (`zoneByKnowledgePoint`), not re-derived here: the page and this
// screen must not disagree about one zone. This import also brings the zone
// words it re-exports (`zoneLabel`), so there is one vocabulary as well.
import '../../cognitive/presentation/cognitive_model_page.dart';
import '../application/judge_mode_preference.dart';
import '../application/review_advisory.dart';
import '../application/review_service.dart';

/// Practice screen (blueprint 4.3; user annotations 17, 18, 19).
///
/// Kept deliberately plain so the user can reach flow: one blank per question,
/// no statistics, no boost badges. Everything analytical lives in the separate
/// insight screen.
///
/// Three things the screen owes the user beyond showing the question:
///  * **A judging mode reachable while answering** (strict / lenient / self),
///    instead of strict comparison being the only way through.
///  * **The hint, but only when asked for** (`CardTemplate.hint` used to be
///    stored and edited and then never shown). Revealing it is not an answer, so
///    it writes nothing to the review log.
///  * **Every card type the app stores** ([ReviewItemKind]): a blank is typed, a
///    single-choice card is picked, an essay is judged by the user.
class ReviewPage extends ConsumerStatefulWidget {
  const ReviewPage({super.key});

  @override
  ConsumerState<ReviewPage> createState() => _ReviewPageState();
}

/// The three ways an answer can be judged from the practice screen.
///
/// [JudgeMode] is the engine's vocabulary; [AnswerMode] adds the strict/lenient
/// split of its `auto`, because "self" is not a strictness and "strict" is not a
/// judge. The same enum is the persisted preference's UI arm
/// (`JudgeModePreference.answerMode`), so the control and the setting cannot
/// drift into two different vocabularies.

/// What the screen knows about the answer just submitted.
class _Feedback {
  const _Feedback({
    required this.expected,
    required this.submitted,
    this.correct,
    this.awaitingSolution = false,
  });

  /// Null while the user still has to judge it: the self path shows the expected
  /// answer and waits for the rating buttons, and only that press is a graded
  /// event.
  final bool? correct;

  final String expected;
  final String submitted;

  /// True while a failed recall still needs its one missing detail: did the user
  /// read the answer and find it recognisable? The review log is deliberately
  /// not written before this is answered - the two answers are two different
  /// model events (see [_ReviewPageState._beginWrong]).
  final bool awaitingSolution;

  bool get awaitingSelfJudge => correct == null;
}

/// A failed recall that is waiting for "did you read the answer?".
///
/// Holds everything `grade` needs so the write can happen once, after the
/// question is answered.
class _PendingWrong {
  const _PendingWrong({
    required this.item,
    required this.submitted,
    required this.judgeMode,
    required this.selfJudged,
  });

  final ReviewItem item;
  final String submitted;
  final JudgeMode judgeMode;

  /// True when the user's own 忘记 press started this, which decides whether the
  /// screen advances itself afterwards (as the self path does) or waits for the
  /// next-card press (as the auto path does).
  final bool selfJudged;
}

class _ReviewPageState extends ConsumerState<ReviewPage> {
  final _answer = TextEditingController();
  final _scroll = ScrollController();

  List<ReviewItem> _queue = const [];
  int _index = 0;
  bool _loading = true;
  bool _submitting = false;
  _Feedback? _feedback;
  AnswerMode _mode = AnswerMode.strict;
  String? _selectedOption;
  DateTime? _shownAt;
  ReviewOutcome? _outcome;
  _PendingWrong? _pendingWrong;

  @override
  void initState() {
    super.initState();
    _load();
    // Cards can appear from outside this screen (the AI tool layer, a package
    // import, the manage tab). They must reach the queue without a restart -
    // but never in the middle of an answer, which would throw the user's
    // position away, so the reload only happens on an untouched queue.
    _revisionSubscription = ref.listenManual(dataRevisionProvider, (_, __) {
      if (_loading || _feedback != null || _outcome != null || _index != 0) {
        return;
      }
      _load();
    });
  }

  late final ProviderSubscription<int> _revisionSubscription;

  @override
  void dispose() {
    _revisionSubscription.close();
    _answer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // The persisted default judging mode decides what the control starts as: a
    // user who chose 宽松 asked for recall rather than dictation, and a user who
    // chose 自判 asked to judge every answer themselves. It is only the starting
    // point - the per-answer control still wins for the card in front of them -
    // and with nothing configured it resolves to 严格, which is the behaviour
    // this screen had before the preference existed.
    final initialMode = ref.initialAnswerMode;
    setState(() {
      _loading = true;
      _mode = initialMode;
    });
    // Today's per-group plan is read once per queue build, not watched: an
    // allowance that changed under the user's fingers would rebuild the queue
    // and throw their position away. With nothing configured this returns an
    // empty load, and `buildQueue` then draws exactly as it did before the plan
    // existed.
    final plan = await ref.read(reviewPlanRepositoryProvider).loadDay();
    if (!mounted) {
      return;
    }
    final queue = await ref.read(reviewServiceProvider).buildQueue(plan: plan);
    if (!mounted) {
      return;
    }
    setState(() {
      _queue = queue;
      _index = 0;
      _feedback = null;
      _outcome = null;
      _answer.clear();
      _selectedOption = null;
      _shownAt = DateTime.now();
      _loading = false;
      _pendingWrong = null;
    });
  }

  ReviewItem? get _current =>
      _index >= 0 && _index < _queue.length ? _queue[_index] : null;

  /// The mode this item is actually judged in.
  ///
  /// An essay has no comparable answer - the app never decides whether prose is
  /// right - so it is always self-judged, whatever the control says.
  AnswerMode _effectiveMode(ReviewItem item) =>
      item.kind == ReviewItemKind.essay ? AnswerMode.self : _mode;

  int? _elapsedSeconds() =>
      _shownAt == null ? null : DateTime.now().difference(_shownAt!).inSeconds;

  /// Decides the answer, or hands it to the user when only the user can.
  Future<void> _submit() async {
    final item = _current;
    if (item == null || _submitting) {
      return;
    }
    if (_effectiveMode(item) == AnswerMode.self) {
      _revealAnswer(item);
      return;
    }
    final selected = item.kind == ReviewItemKind.mcq ? _selectedOption : null;
    final submitted = item.kind == ReviewItemKind.mcq
        ? (selected ?? '')
        : _answer.text.trim();
    final bool? correct;
    if (item.kind == ReviewItemKind.mcq) {
      correct = ReviewService.mcqMatch(
        options: item.options,
        answer: item.answer,
        selected: selected,
      );
    } else {
      correct = _mode == AnswerMode.strict
          ? ReviewService.strictMatch(item.answer, submitted)
          : ReviewService.lenientMatch(item.answer, submitted);
    }
    if (correct == null) {
      // A choice card whose stored answer names no option cannot be judged by
      // the app; the user judges it rather than the app guessing.
      _revealAnswer(item);
      return;
    }
    if (!correct) {
      _beginWrong(
        item: item,
        submitted: submitted,
        judgeMode: JudgeMode.auto,
        selfJudged: false,
      );
      return;
    }
    await _record(
      item: item,
      correct: true,
      submitted: submitted,
      judgeMode: JudgeMode.auto,
    );
  }

  /// Parks one failed recall until the user says whether they read the answer.
  ///
  /// MindNet distinguishes the two (`docs/IO_PROTOCOL.md` §2.3): a bare miss is
  /// a `lapse`, which cuts stability, while a miss followed by reading the
  /// solution is `retrieval_failure_feedback`, a learning event whose gain grows
  /// with `closeness`. That is the whole reason this press is asked for - and
  /// why the log is written *afterwards*: the model's two columns are computed
  /// from the event, so patching the row later would mean applying one review
  /// twice.
  void _beginWrong({
    required ReviewItem item,
    required String submitted,
    required JudgeMode judgeMode,
    required bool selfJudged,
  }) {
    setState(() {
      _pendingWrong = _PendingWrong(
        item: item,
        submitted: submitted,
        judgeMode: judgeMode,
        selfJudged: selfJudged,
      );
      _feedback = _Feedback(
        correct: false,
        expected: item.answer,
        submitted: submitted,
        awaitingSolution: true,
      );
      _outcome = null;
    });
  }

  /// Records the failed recall together with the user's answer to the solution
  /// question, then behaves like the path that asked it.
  ///
  /// [reviewedSolution] false sends the documented default `closeness` (0.5)
  /// along with it; true sends the near-miss anchor (0.6). Both numbers come
  /// from `DsrCardState`, not from this screen, because they are points on the
  /// model's scale rather than UI choices.
  Future<void> _resolveWrong({required bool reviewedSolution}) async {
    final pending = _pendingWrong;
    if (pending == null || _submitting) {
      return;
    }
    setState(() => _pendingWrong = null);
    await _record(
      item: pending.item,
      correct: false,
      submitted: pending.submitted,
      judgeMode: pending.judgeMode,
      reviewedSolution: reviewedSolution,
      closeness: reviewedSolution
          ? DsrCardState.closenessNearMiss
          : DsrCardState.closenessDefault,
    );
    if (!mounted || !pending.selfJudged) {
      return;
    }
    await ref
        .read(reviewServiceProvider)
        .consumeBoost(pending.item.knowledgePointId);
    if (!mounted) {
      return;
    }
    _advance();
  }

  /// Shows the expected answer and waits for the rating buttons.
  ///
  /// Reached by choosing 自判, by pressing 显示答案, and by an essay or an
  /// unjudgeable choice card. Nothing is recorded yet: in this path the user's
  /// own verdict is the graded event.
  void _revealAnswer(ReviewItem item) {
    setState(() {
      _feedback = _Feedback(
        expected: item.answer,
        submitted: _answer.text.trim(),
      );
      _outcome = null;
    });
  }

  /// Writes the one review log this answer gets.
  ///
  /// One log per answer is the contract: the log's `correct`, `judge_mode` and
  /// `format` all come from a single call, so re-grading to pick a different
  /// interval can never double-count a review. The same holds for the v9
  /// failure-feedback pair ([reviewedSolution] / [closeness]): they are part of
  /// this one call, which is why a failed recall waits for its answer instead of
  /// being logged first and amended.
  Future<void> _record({
    required ReviewItem item,
    required bool correct,
    required String submitted,
    required JudgeMode judgeMode,
    FsrsRating? rating,
    bool reviewedSolution = false,
    double closeness = DsrCardState.closenessDefault,
  }) async {
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
          // A wrong answer is always Again (the engine forces it as well); a
          // right one takes the grade the user picked, or Good when the app
          // judged it.
          rating: rating ?? (correct ? FsrsRating.good : FsrsRating.again),
          submitted: submitted,
          judgeMode: judgeMode,
          reviewedSolution: reviewedSolution,
          closeness: closeness,
          responseSeconds: _elapsedSeconds(),
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _submitting = false;
      _outcome = outcome;
    });
  }

  /// Records the self-assessment and moves on.
  ///
  /// This press is the graded event of the self path: 忘记 means wrong and
  /// anything else means right, which is why the log's `judge_mode` is `self`.
  /// 忘记 goes through the solution question like every other failed recall, so
  /// the self and auto paths cannot record the same event differently.
  Future<void> _rate(FsrsRating rating) async {
    final item = _current;
    if (item == null || _submitting) {
      return;
    }
    if (rating == FsrsRating.again) {
      _beginWrong(
        item: item,
        submitted: _answer.text.trim(),
        judgeMode: JudgeMode.self,
        selfJudged: true,
      );
      return;
    }
    await _record(
      item: item,
      correct: true,
      submitted: _answer.text.trim(),
      judgeMode: JudgeMode.self,
      rating: rating,
    );
    if (!mounted) {
      return;
    }
    await ref.read(reviewServiceProvider).consumeBoost(item.knowledgePointId);
    if (!mounted) {
      return;
    }
    _advance();
  }

  /// Records an **exposure**: the user read the answer instead of testing
  /// himself (MindNet's `exposure`, "读了但没测").
  ///
  /// Nothing is graded here, so nothing is scheduled either: the card keeps its
  /// due date and comes back exactly when it would have. That is the point - a
  /// reading is not evidence of recall, and the model is told precisely that
  /// (`DsrEventType.reread`: a tenth-sized stability gain, no `R0` lift). The
  /// write itself is [ReviewService.recordExposure]; this method only reports it
  /// and moves on.
  Future<void> _expose() async {
    final item = _current;
    if (item == null || _submitting || _feedback == null) {
      return;
    }
    setState(() => _submitting = true);
    await ref.read(reviewServiceProvider).recordExposure(item: item);
    if (!mounted) {
      return;
    }
    setState(() => _submitting = false);
    // The press raises a question the screen must answer: "读了算不算复习一次?"
    // - it does not, and the log stays empty.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).ankiExposureRecorded),
      ),
    );
    _advance();
  }

  void _advance() {
    setState(() {
      _index++;
      _feedback = null;
      _outcome = null;
      _pendingWrong = null;
      _answer.clear();
      _selectedOption = null;
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
    final hint = item.hint;
    // What the fast layer said about this card's knowledge point, as the 认知模型
    // page reports it. Only a real complaint becomes a chip: `healthy` ("ran,
    // nothing wrong") and `unavailable` ("nothing was diagnosed") are both
    // "nothing to report on this card", and a chip on every card would train the
    // user to stop reading it. The page is where the two are told apart.
    final zone = ref
        .watch(cognitiveReadingsProvider)
        .valueOrNull
        ?.zoneByKnowledgePoint[item.knowledgePointId];
    final diagnosedZone = zone == null ||
            zone == ReviewZone.unavailable ||
            zone == ReviewZone.healthy
        ? null
        : zone;
    final correctIndex = item.kind == ReviewItemKind.mcq
        ? ReviewService.correctOptionIndex(
            options: item.options,
            answer: item.answer,
          )
        : null;
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
                if (diagnosedZone != null) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _ZoneChip(
                      text: l10n.reviewZoneChip(zoneLabel(l10n, diagnosedZone)),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SelectableText(
                  item.question,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        height: 1.75,
                      ),
                ),
                // Never auto-revealed: the hint is there for the user who is
                // stuck, not for the user who has not tried yet. The key makes
                // every card start with its hint hidden again.
                if (hint != null && hint.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ReviewHintReveal(
                    key: ValueKey('hint-${item.unitKey}'),
                    hint: hint,
                  ),
                ],
                const SizedBox(height: 12),
                AnswerModeSelector(
                  // The effective mode, so an essay shows 自判 even while the
                  // control itself is disabled.
                  mode: _effectiveMode(item),
                  autoEnabled: item.kind != ReviewItemKind.essay,
                  onChanged: _feedback == null
                      ? (mode) => setState(() {
                            // An essay is self-judged whatever the control says,
                            // so tapping 自判 on one must not decide the mode of
                            // the next card.
                            if (item.kind != ReviewItemKind.essay) {
                              _mode = mode;
                            }
                          })
                      : null,
                ),
                const SizedBox(height: 16),
                if (item.kind == ReviewItemKind.mcq) ...[
                  for (var i = 0; i < item.options.length; i++)
                    _OptionButton(
                      label: item.options[i],
                      selected: _selectedOption == item.options[i],
                      isCorrect: _feedback == null ? null : correctIndex == i,
                      onTap: _feedback == null
                          ? () => setState(
                                () => _selectedOption = item.options[i],
                              )
                          : null,
                    ),
                  const SizedBox(height: 4),
                  FilledButton.icon(
                    onPressed: _feedback == null &&
                            _selectedOption != null &&
                            !_submitting
                        ? _submit
                        : null,
                    icon: const Icon(Icons.check),
                    label: Text(l10n.ankiSubmit),
                  ),
                ] else
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
                  _FeedbackCard(
                    feedback: _feedback!,
                    outcome: _outcome,
                    // The question is asked only while it is still unanswered:
                    // once the review is written there is nothing left to tell
                    // the model, and the card's buttons must not reappear.
                    onResolveSolution: _feedback!.awaitingSolution
                        ? (reviewedSolution) => _resolveWrong(
                              reviewedSolution: reviewedSolution,
                            )
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ),
        _BottomBar(
          feedback: _feedback,
          submitting: _submitting,
          onReveal: () {
            final current = _current;
            if (current != null) {
              _revealAnswer(current);
            }
          },
          onRate: _rate,
          onExpose: _expose,
          // Pressing "next" before the solution question is answered would skip
          // the write of an answer that has not been recorded yet, so the
          // button is disabled until then.
          onNext: _feedback?.awaitingSolution == true ? null : _advance,
          onGenerateTask: _generateTask,
        ),
      ],
    );
  }
}

/// The fast layer's one-word verdict about the card on screen.
///
/// Small on purpose: it is context, not a task, and it must never look like
/// something to act on (nothing here is a control - the review flow's only
/// decisions are the answer and the rating).
class _ZoneChip extends StatelessWidget {
  const _ZoneChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: scheme.onSecondaryContainer),
      ),
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
  const _FeedbackCard({
    required this.feedback,
    required this.outcome,
    this.onResolveSolution,
  });

  final _Feedback feedback;
  final ReviewOutcome? outcome;

  /// Non-null only while a failed recall still needs its one missing detail.
  /// The value is "did you read the answer and still recognise it?".
  final ValueChanged<bool>? onResolveSolution;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final correct = feedback.correct;
    final color = correct == null
        ? theme.colorScheme.primary
        : correct
            ? Colors.green.shade700
            : theme.colorScheme.error;

    return Card(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  correct == null
                      ? Icons.help_outline
                      : correct
                          ? Icons.check_circle
                          : Icons.cancel,
                  color: color,
                ),
                const SizedBox(width: 8),
                Text(
                  correct == null
                      ? l10n.ankiJudgeYourself
                      : correct
                          ? l10n.ankiCorrect
                          : l10n.ankiWrong,
                  style: theme.textTheme.titleMedium?.copyWith(color: color),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('${l10n.ankiAnswer}: ${feedback.expected}'),
            // The user's own answer is withheld only when the app already said
            // it was right.
            if (correct != true && feedback.submitted.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('${l10n.ankiYourAnswer}: ${feedback.submitted}'),
            ],
            // Asked once, before the write, and only for a failed recall: the
            // two answers are two different model events. The explanation is
            // part of the question on purpose - without it "差点想起来" reads
            // like "I passed", and it is not.
            if (onResolveSolution != null) ...[
              const SizedBox(height: 14),
              Text(
                l10n.ankiAfterAnswerPrompt,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: () => onResolveSolution!(true),
                    child: Text(l10n.ankiNearMiss),
                  ),
                  OutlinedButton(
                    onPressed: () => onResolveSolution!(false),
                    child: Text(l10n.ankiStillForgot),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                l10n.ankiAfterAnswerHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
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

/// The judging mode for this answer: strict auto, lenient auto, or self.
///
/// Sits directly above the answer area rather than behind a menu: the complaint
/// was that strict comparison was the only way to answer, so the way out has to
/// be visible while answering.
class AnswerModeSelector extends StatelessWidget {
  const AnswerModeSelector({
    required this.mode,
    required this.autoEnabled,
    required this.onChanged,
  });

  final AnswerMode mode;

  /// False for an essay, which the app never compares.
  final bool autoEnabled;

  /// Null once an answer has been submitted: the mode is per-answer, not a
  /// setting to fiddle with after the fact.
  final ValueChanged<AnswerMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<AnswerMode>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(
            value: AnswerMode.strict,
            enabled: autoEnabled,
            label: Text(l10n.ankiJudgeStrict),
            tooltip: l10n.ankiJudgeStrictHint,
          ),
          ButtonSegment(
            value: AnswerMode.lenient,
            enabled: autoEnabled,
            label: Text(l10n.ankiJudgeLenient),
            tooltip: l10n.ankiJudgeLenientHint,
          ),
          ButtonSegment(
            value: AnswerMode.self,
            label: Text(l10n.ankiJudgeSelf),
            tooltip: l10n.ankiJudgeSelfHint,
          ),
        ],
        selected: {mode},
        onSelectionChanged: onChanged == null
            ? null
            : (selection) => onChanged!(selection.first),
      ),
    );
  }
}

/// One choice of a single-choice card.
class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.label,
    required this.selected,
    required this.isCorrect,
    required this.onTap,
  });

  final String label;
  final bool selected;

  /// Whether this is the card's correct option; null while the answer is open,
  /// so the choice is not given away before submitting.
  final bool? isCorrect;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = isCorrect == true
        ? Colors.green.withValues(alpha: 0.16)
        : (isCorrect == false && selected)
            ? theme.colorScheme.error.withValues(alpha: 0.14)
            : selected
                ? theme.colorScheme.primary.withValues(alpha: 0.14)
                : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          backgroundColor: background,
          // The highlight has to survive the button being disabled after the
          // answer, which is exactly when it matters.
          disabledBackgroundColor: background,
          minimumSize: const Size.fromHeight(44),
        ),
        child: Text(label),
      ),
    );
  }
}

/// The author's hint, hidden until the user asks for it.
///
/// User-triggered by design, and deliberately outside the graded flow: revealing
/// it is not an answer, so it never reaches the review log - the log records how
/// the answer was judged, not that the user needed help.
class ReviewHintReveal extends StatefulWidget {
  const ReviewHintReveal({super.key, required this.hint});

  final String hint;

  @override
  State<ReviewHintReveal> createState() => _ReviewHintRevealState();
}

class _ReviewHintRevealState extends State<ReviewHintReveal> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!_revealed) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _revealed = true),
          icon: const Icon(Icons.lightbulb_outline, size: 18),
          label: Text(l10n.ankiHint),
        ),
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      color: Colors.amber.withValues(alpha: 0.14),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lightbulb_outline,
                size: 18, color: Colors.amber.shade800),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.hint)),
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
    required this.onExpose,
    this.onNext,
    required this.onGenerateTask,
  });

  final _Feedback? feedback;
  final bool submitting;
  final VoidCallback onReveal;
  final ValueChanged<FsrsRating> onRate;

  /// "我读过，没测自己" - the exposure button, shown next to the rating buttons
  /// because that is the moment it describes: the answer is on screen and the
  /// user is choosing what to tell the model. Unlike [onRate] it is not a grade
  /// and writes no review log; the card keeps its due date.
  final VoidCallback onExpose;

  /// Null while the review is not written yet (a failed recall still waiting for
  /// the solution question): there would be nothing to advance from.
  final VoidCallback? onNext;

  final VoidCallback onGenerateTask;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final awaitingJudge = feedback?.awaitingSelfJudge ?? false;
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
                  if (awaitingJudge) ...[
                    IconButton(
                      tooltip: l10n.ankiForgot,
                      icon: const Icon(Icons.replay),
                      color: Theme.of(context).colorScheme.error,
                      onPressed:
                          submitting ? null : () => onRate(FsrsRating.again),
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
                    // The honest third answer to "how well did you know it?":
                    // "I did not test myself, I just read it". It is not a
                    // grade, so it is not in the grade group's styling - a
                    // plain IconButton, and the model hears `reread`.
                    IconButton(
                      tooltip: l10n.ankiExposureTooltip,
                      icon: const Icon(Icons.chrome_reader_mode),
                      onPressed: submitting ? null : onExpose,
                    ),
                  ] else
                    // The answer is already recorded and judged: one press moves
                    // on, and nothing is written a second time. Disabled while
                    // the solution question is still open (onNext is null then).
                    IconButton.filled(
                      tooltip: l10n.ankiNextCard,
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: submitting ? null : onNext,
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

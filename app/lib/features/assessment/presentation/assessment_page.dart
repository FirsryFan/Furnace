/// The assessment surface: one short measurement that gives the cognitive model
/// a starting point about *this* user (M1c of `docs/ASSESSMENT_DESIGN.md` §7).
///
/// Four steps, in this order and for these reasons:
///
/// 1. **Scope.** A measurement is only as good as the population it averages
///    over, so the user names the area first (a tag, children included). The
///    scope is stored as tag **ids**, never paths: `TagRepository` rewrites the
///    paths of every descendant on rename, so a stored path eventually points at
///    a different group.
/// 2. **Self-report.** Milestone ① starts with self-report and lets objective
///    checks take over later. Each rating is a JOL, and a skipped point is left
///    *absent* rather than written as 0 - "I don't know" is not "I know nothing",
///    and the prior layer averages what it is given.
/// 3. **Recall check.** Three knowledge points: the two ends and the middle of
///    the scope. Deterministic on purpose - a random pick would make two rounds
///    incomparable, and picking "the weakest cards" would quietly turn the
///    instrument into another card drill, which is exactly what the user said
///    this must not be (`不建议从卡片出题`). The prompt is the knowledge point,
///    never a card front.
/// 4. **Reading.** What the round produced: steps written, priors recomputed,
///    mean starting R0 and mean confidence - with the uncalibrated disclaimer
///    the design doc requires (§2) rendered here, not in a tooltip.
///
/// This page *writes* (unlike the reading page, which is select-only), so the
/// widget test's job is the mirror image: drive the flow and then check the
/// rows, not just the pixels.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database_provider.dart';
import '../../../data/database/database.dart';
import '../../../data/repositories/assessment_repository.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/cognitive/assessment_prior.dart';
import '../../../l10n/app_localizations.dart';

/// Every tag, in tree order (the scope picker).
///
/// Sorted by `path` and falling back to name: a tag whose `path` is NULL is a
/// legacy row, and it must still be selectable.
final assessmentTagsProvider = FutureProvider<List<Tag>>((ref) async {
  final tags = await ref.watch(tagRepositoryProvider).getAllTags();
  return [...tags]..sort((a, b) {
      final byPath = (a.path ?? a.name).compareTo(b.path ?? b.name);
      return byPath != 0 ? byPath : a.id.compareTo(b.id);
    });
});

/// The knowledge points a scope covers.
///
/// The family key is the selected tag ids, comma-joined and sorted, because
/// provider families compare by `==` and a `List` would never compare equal.
final assessmentScopeProvider = FutureProvider.autoDispose
    .family<AssessmentScope, String>((ref, key) async {
  final selected = <String>{
    for (final id in key.split(','))
      if (id.isNotEmpty) id,
  };
  if (selected.isEmpty) {
    return AssessmentScope.empty;
  }
  final tags = await ref.watch(assessmentTagsProvider.future);

  // Descendants come from `parentId`, not from `path` prefixes: `path` is
  // nullable on legacy rows, and a scope that silently drops a subtree would
  // average a population the user did not choose.
  final inScope = <String>{...selected};
  var grew = true;
  while (grew) {
    grew = false;
    for (final tag in tags) {
      final parent = tag.parentId;
      if (parent != null && inScope.contains(parent) && inScope.add(tag.id)) {
        grew = true;
      }
    }
  }

  final db = ref.watch(appDatabaseProvider);
  // `object_type` is the indexed-looking half of the link table and the only
  // condition this select needs; the tag side is filtered here rather than with
  // a second expression so this file stays free of a drift import (Flutter and
  // drift both export `Column`, and hiding it to fetch a handful of rows is a
  // worse trade than one `where` on an in-memory set).
  final links = await (db.select(db.objectTags)
        ..where((t) => t.objectType.equals('knowledge_point')))
      .get();
  final ids = <String>{
    for (final link in links)
      if (inScope.contains(link.tagId)) link.objectId,
  };
  if (ids.isEmpty) {
    return AssessmentScope.empty;
  }
  final rows = await (db.select(db.knowledgePoints)
        ..where((t) => t.id.isIn(ids.toList())))
      .get();
  // Sorted here rather than in SQL so this file needs no drift import.
  rows.sort((a, b) {
    final byTitle = a.title.compareTo(b.title);
    return byTitle != 0 ? byTitle : a.id.compareTo(b.id);
  });
  return AssessmentScope(knowledgePoints: rows);
});

/// What a scope resolved to.
@immutable
class AssessmentScope {
  const AssessmentScope({required this.knowledgePoints});

  static const AssessmentScope empty =
      AssessmentScope(knowledgePoints: <KnowledgePoint>[]);

  final List<KnowledgePoint> knowledgePoints;

  bool get isEmpty => knowledgePoints.isEmpty;
}

/// The three recall prompts: the two ends and the middle of the scope, in the
/// order the scope provider sorted them (by title), so the same scope always
/// asks the same three questions.
///
/// Top-level rather than a private method so the rule itself is testable
/// without driving the UI: "which three" is a design decision, not plumbing.
List<KnowledgePoint> recallPicks(List<KnowledgePoint> knowledgePoints) {
  if (knowledgePoints.length <= 3) {
    return knowledgePoints;
  }
  return [
    knowledgePoints.first,
    knowledgePoints[knowledgePoints.length ~/ 2],
    knowledgePoints.last,
  ];
}

/// The page. A plain [StatefulWidget]-style flow: the four steps are local
/// state, and nothing is written until the last step (so backing out of step 2
/// leaves no half-session behind).
class AssessmentPage extends ConsumerStatefulWidget {
  const AssessmentPage({super.key});

  @override
  ConsumerState<AssessmentPage> createState() => _AssessmentPageState();
}

class _AssessmentPageState extends ConsumerState<AssessmentPage> {
  static const int _lastStep = 3;

  int _step = 0;
  final Set<String> _tagIds = <String>{};
  final Map<String, int> _selfRatings = <String, int>{};
  final Map<String, String> _recallAnswers = <String, String>{};
  final Map<String, int> _recallRatings = <String, int>{};

  bool _busy = false;
  String? _error;
  int? _stepsWritten;
  int? _pointsWritten;
  double? _meanR0;
  double? _meanConfidence;

  String get _scopeKey {
    final ids = _tagIds.toList()..sort();
    return ids.join(',');
  }

  void _next() {
    setState(() {
      _error = null;
      _step = (_step + 1).clamp(0, _lastStep);
    });
  }

  void _back() {
    setState(() {
      _error = null;
      _step = (_step - 1).clamp(0, _lastStep);
    });
  }

  Future<void> _finish(AssessmentScope scope) async {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(assessmentRepositoryProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final sessionId = await repo.startSession(
        scopeTagIds: _tagIds.toList()..sort(),
      );
      var steps = 0;
      for (final kp in scope.knowledgePoints) {
        final rating = _selfRatings[kp.id];
        if (rating == null) {
          continue;
        }
        await repo.addStep(
          sessionId: sessionId,
          stepKind: AssessmentRepository.selfReportStep,
          knowledgePointId: kp.id,
          prompt: kp.title,
          selfRating: rating,
        );
        steps++;
      }
      for (final kp in recallPicks(scope.knowledgePoints)) {
        final answer = (_recallAnswers[kp.id] ?? '').trim();
        final rating = _recallRatings[kp.id];
        if (rating == null && answer.isEmpty) {
          continue;
        }
        await repo.addStep(
          sessionId: sessionId,
          stepKind: AssessmentRepository.recallStep,
          knowledgePointId: kp.id,
          prompt: kp.title,
          answer: answer.isEmpty ? null : answer,
          selfRating: rating,
        );
        steps++;
      }
      await repo.finishSession(sessionId);
      final reading = await repo.rebuildPriors();
      final inScope = <String>{
        for (final kp in scope.knowledgePoints) kp.id,
      };
      final estimates = [
        for (final estimate in reading.estimates)
          if (inScope.contains(estimate.knowledgePointId)) estimate,
      ];
      if (!mounted) {
        return;
      }
      setState(() {
        _stepsWritten = steps;
        _pointsWritten = estimates.length;
        _meanR0 = _mean(estimates.map((e) => e.r0));
        _meanConfidence = _mean(estimates.map((e) => e.confidence));
        _step = _lastStep;
        _busy = false;
        if (steps == 0) {
          _error = l10n.assessmentNoEvidence;
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  static double? _mean(Iterable<double> values) {
    if (values.isEmpty) {
      return null;
    }
    var sum = 0.0;
    var count = 0;
    for (final value in values) {
      sum += value;
      count++;
    }
    return sum / count;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tags = ref.watch(assessmentTagsProvider);
    final scope = ref.watch(assessmentScopeProvider(_scopeKey));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.assessmentTitle)),
      body: Column(
        children: [
          _StepBar(l10n: l10n, current: _step),
          const Divider(height: 1),
          Expanded(
            child: tags.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _ErrorBox(text: '$error'),
              data: (allTags) => scope.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _ErrorBox(text: '$error'),
                data: (data) => _stepBody(l10n, allTags, data),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _ErrorBox(text: _error!),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child:
                  _navigation(l10n, scope.valueOrNull ?? AssessmentScope.empty),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navigation(AppLocalizations l10n, AssessmentScope scope) {
    final canAdvance = switch (_step) {
      0 => !scope.isEmpty,
      // Step 1 can be passed through without a single rating on purpose: the
      // user is allowed to look at the questions and leave, and "I rated
      // nothing" has to stay representable (it becomes an empty round, which
      // [AssessmentRepository.rebuildPriors] reads as "no evidence" rather than
      // as zeros).
      1 => true,
      _ => true,
    };
    return Row(
      children: [
        if (_step > 0 && _step < _lastStep)
          TextButton(
            onPressed: _busy ? null : _back,
            child: Text(l10n.assessmentBack),
          ),
        const Spacer(),
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(8),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (_step < _lastStep)
          FilledButton(
            onPressed: !canAdvance ? null : _next,
            child: Text(l10n.assessmentNext),
          )
        else if (_stepsWritten == null)
          FilledButton(
            onPressed: () => _finish(scope),
            child: Text(l10n.assessmentFinish),
          ),
      ],
    );
  }

  Widget _stepBody(
    AppLocalizations l10n,
    List<Tag> allTags,
    AssessmentScope scope,
  ) {
    switch (_step) {
      case 0:
        return _scopeStep(l10n, allTags, scope);
      case 1:
        return _selfStep(l10n, scope);
      case 2:
        return _recallStep(l10n, scope);
      default:
        return _resultStep(l10n, scope);
    }
  }

  Widget _scopeStep(
    AppLocalizations l10n,
    List<Tag> allTags,
    AssessmentScope scope,
  ) {
    if (allTags.isEmpty) {
      return _Hint(text: l10n.assessmentScopeEmpty);
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _Hint(text: l10n.assessmentIntro),
        const SizedBox(height: 12),
        _Hint(text: l10n.assessmentScopeHint),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final tag in allTags)
              FilterChip(
                label: Text(tag.name),
                selected: _tagIds.contains(tag.id),
                onSelected: (selected) => setState(() {
                  if (selected) {
                    _tagIds.add(tag.id);
                  } else {
                    _tagIds.remove(tag.id);
                  }
                  // The rating maps are keyed by knowledge point, so a scope
                  // change cannot silently carry a rating into a point that is
                  // no longer part of the measurement.
                  _selfRatings.removeWhere(
                    (id, _) => !scope.knowledgePoints.any((kp) => kp.id == id),
                  );
                }),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          scope.isEmpty
              ? l10n.assessmentScopeEmpty
              : l10n.assessmentScopeCount(scope.knowledgePoints.length),
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ],
    );
  }

  Widget _selfStep(AppLocalizations l10n, AssessmentScope scope) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _Hint(text: l10n.assessmentSelfHint),
        const SizedBox(height: 4),
        Text(
          l10n.assessmentSelfAnswered(
            _selfRatings.length,
            scope.knowledgePoints.length,
          ),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        for (final kp in scope.knowledgePoints)
          _RatingRow(
            keyPrefix: 'self-${kp.id}',
            title: kp.title,
            value: _selfRatings[kp.id],
            onChanged: (value) => setState(() {
              if (value == null) {
                _selfRatings.remove(kp.id);
              } else {
                _selfRatings[kp.id] = value;
              }
            }),
          ),
      ],
    );
  }

  Widget _recallStep(AppLocalizations l10n, AssessmentScope scope) {
    final picks = recallPicks(scope.knowledgePoints);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _Hint(text: l10n.assessmentRecallHint),
        const SizedBox(height: 8),
        for (final kp in picks) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kp.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: ValueKey('recall-answer-${kp.id}'),
                    decoration: InputDecoration(
                      labelText: l10n.assessmentRecallAnswer,
                      border: const OutlineInputBorder(),
                    ),
                    maxLines: 3,
                    onChanged: (value) => setState(() {
                      _recallAnswers[kp.id] = value;
                    }),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.assessmentRecallRating,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  _RatingChips(
                    keyPrefix: 'recall-${kp.id}',
                    value: _recallRatings[kp.id],
                    onChanged: (value) => setState(() {
                      if (value == null) {
                        _recallRatings.remove(kp.id);
                      } else {
                        _recallRatings[kp.id] = value;
                      }
                    }),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ],
    );
  }

  Widget _resultStep(AppLocalizations l10n, AssessmentScope scope) {
    final steps = _stepsWritten;
    final points = _pointsWritten;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          l10n.assessmentResultTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (steps == null)
          _Hint(text: l10n.assessmentResultPending)
        else if (steps == 0)
          _Hint(text: l10n.assessmentNoEvidence)
        else ...[
          Text(l10n.assessmentResultBody(steps, points ?? 0)),
          if (_meanR0 != null)
            Text(l10n.assessmentResultR0(_meanR0!.toStringAsFixed(3))),
          if (_meanConfidence != null)
            Text(
              l10n.assessmentResultConfidence(
                _meanConfidence!.toStringAsFixed(3),
              ),
            ),
          const SizedBox(height: 12),
          _Hint(text: l10n.assessmentResultUncalibrated),
        ],
      ],
    );
  }
}

/// The four step names, with the current one marked. Deliberately not a
/// `Stepper`: this page has no free navigation between steps (a measurement is
/// taken in order), and a Stepper would offer one.
class _StepBar extends StatelessWidget {
  const _StepBar({required this.l10n, required this.current});

  final AppLocalizations l10n;
  final int current;

  @override
  Widget build(BuildContext context) {
    final labels = [
      l10n.assessmentStepScope,
      l10n.assessmentStepSelf,
      l10n.assessmentStepRecall,
      l10n.assessmentStepResult,
    ];
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (var i = 0; i < labels.length; i++)
            Text(
              labels[i],
              style: TextStyle(
                color: i == current ? scheme.primary : scheme.onSurfaceVariant,
                fontWeight: i == current ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
        ],
      ),
    );
  }
}

/// One knowledge point's 0–5 self-report, with "skip" as an explicit choice.
class _RatingRow extends StatelessWidget {
  const _RatingRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.keyPrefix,
  });

  final String title;
  final int? value;
  final ValueChanged<int?> onChanged;
  final String? keyPrefix;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            _RatingChips(
              keyPrefix: keyPrefix,
              value: value,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

/// Six chips: 0–5, plus "unset". Re-tapping the selected chip clears it, which
/// is how "I'd rather not say" stays distinguishable from "0".
///
/// [keyPrefix] exists for tests: two rating rows on one screen would otherwise
/// both offer a chip labelled `4`, and picking "the second 4" is not a test.
class _RatingChips extends StatelessWidget {
  const _RatingChips({
    required this.value,
    required this.onChanged,
    this.keyPrefix,
  });

  final int? value;
  final ValueChanged<int?> onChanged;
  final String? keyPrefix;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      children: [
        for (var rating = AssessmentRepository.minSelfRating;
            rating <= AssessmentRepository.maxSelfRating;
            rating++)
          ChoiceChip(
            key: keyPrefix == null
                ? null
                : ValueKey<String>('$keyPrefix-$rating'),
            label: Text('$rating'),
            selected: value == rating,
            onSelected: (selected) => onChanged(selected ? rating : null),
          ),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(color: scheme.onErrorContainer),
      ),
    );
  }
}

/// Re-exported so the reading page (and tests) can name the reading type
/// without importing the prior layer as well.
typedef AssessmentReading = AssessmentPriorReading;

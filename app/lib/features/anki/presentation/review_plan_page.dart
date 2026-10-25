import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/database/database.dart';
import '../../../data/repositories/review_plan_repository.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/srs/review_retention.dart';
import '../../../l10n/app_localizations.dart';
import '../application/card_type_preference.dart';
import '../application/judge_mode_preference.dart';
import '../application/review_retention_provider.dart';

/// Every configured card group, in tag-path order.
///
/// Watches the database revision so the list refreshes after a plan is saved
/// from anywhere - the plan UI itself, but also a tag rename (which changes the
/// path this list is ordered and labelled by).
final reviewGroupPlansProvider = FutureProvider<List<CardGroupPlan>>((ref) {
  ref.watchDatabaseRevision();
  return ref.watch(reviewPlanRepositoryProvider).groupPlans();
});

/// Today's plan versus today's actual.
///
/// Recomputed whenever the database changes, because the "already done today"
/// half of it comes from `review_logs`: answering a card invalidates this
/// provider, which is what keeps the numbers on screen honest while the user is
/// working through the plan.
final reviewDayLoadProvider = FutureProvider<ReviewDayLoad>((ref) {
  ref.watchDatabaseRevision();
  ref.watch(reviewGroupPlansProvider);
  return ref.watch(reviewPlanRepositoryProvider).loadDay();
});

/// How many cards belong to no card group at all.
///
/// A card group is a tag, so "no tag" means "no group", which means no daily
/// target can reach the card. Old databases can have hundreds of those; before
/// this was surfaced the plan screen just looked empty and the cards were
/// silently out of scope.
final ungroupedKnowledgePointsProvider = FutureProvider<int>((ref) {
  ref.watchDatabaseRevision();
  return ref.watch(tagRepositoryProvider).countKnowledgePointsWithoutTags();
});

/// One group's line: how much is due, how much was done, what is left, and what
/// happens when each allowance runs out.
class CardGroupPlanCard extends ConsumerWidget {
  const CardGroupPlanCard({super.key, required this.group});

  final ReviewGroupLoad group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final plan = group.plan;
    final newRemaining = group.newRemaining;
    final reviewRemaining = group.remainingReviews;
    final newReached = newRemaining <= 0;
    final reviewReached = reviewRemaining == 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    plan.tagPath,
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: l10n.reviewPlanEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () => showCardGroupPlanEditor(
                    context: context,
                    ref: ref,
                    tagId: plan.tagId,
                    tagPath: plan.tagPath,
                    plan: plan,
                  ),
                ),
                IconButton(
                  tooltip: l10n.reviewPlanClear,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => ref
                      .read(reviewPlanRepositoryProvider)
                      .clearGroupPlan(plan.tagId),
                ),
              ],
            ),
            Text(
              l10n.reviewPlanTarget(
                  plan.newCardsPerDay, plan.reviewCardsPerDay),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.reviewPlanDoneToday(group.alreadyDoneToday),
              style: theme.textTheme.bodyMedium,
            ),
            Text(
              l10n.reviewPlanNewRemaining(newRemaining),
              style: theme.textTheme.bodyMedium,
            ),
            Text(
              reviewRemaining == null
                  ? l10n.reviewPlanReviewsUnlimited
                  : l10n.reviewPlanRemaining(reviewRemaining),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            if (newReached)
              _PlanHint(
                icon: Icons.pause_circle_outline,
                color: theme.colorScheme.error,
                text: l10n.reviewPlanNewCardsStopped,
              )
            else if (reviewReached)
              _PlanHint(
                icon: Icons.pause_circle_outline,
                color: theme.colorScheme.error,
                text: l10n.reviewPlanReviewsStopped,
              )
            else
              _PlanHint(
                icon: Icons.play_circle_outline,
                color: theme.colorScheme.primary,
                text: l10n.reviewPlanNewCardsNormal,
              ),
          ],
        ),
      ),
    );
  }
}

/// One line of "what happens now" under a group's counters.
class _PlanHint extends StatelessWidget {
  const _PlanHint({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: color == theme.colorScheme.primary
                  ? theme.colorScheme.onSurfaceVariant
                  : color,
            ),
          ),
        ),
      ],
    );
  }
}

/// Creates or edits one group's daily target.
///
/// Takes the group's tag id and display path rather than a `Tag` row: the caller
/// has the id either way, and the tag's *path* is what the dialog shows - a tag
/// that was renamed between the list read and this call would otherwise show a
/// stale label.
Future<void> showCardGroupPlanEditor({
  required BuildContext context,
  required WidgetRef ref,
  required String tagId,
  required String tagPath,
  CardGroupPlan? plan,
}) async {
  final l10n = AppLocalizations.of(context);
  final newController = TextEditingController(
    text: plan?.newCardsPerDay.toString() ?? '',
  );
  final reviewController = TextEditingController(
    text: plan?.reviewCardsPerDay.toString() ?? '',
  );
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.reviewPlanGroupTitle(tagPath)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.reviewPlanGroupBody,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: newController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.reviewPlanNewCardsPerDay,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: reviewController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.reviewPlanReviewCardsPerDay,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.reviewPlanZeroIsUnlimited,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.commonSave),
        ),
      ],
    ),
  );
  if (saved != true) {
    return;
  }
  // Empty means 0, which for reviews is "no limit" (see
  // `CardGroupPlan.isReviewCapped`) - the same as leaving the field blank on a
  // brand-new group.
  await ref.read(reviewPlanRepositoryProvider).setGroupPlan(
        tagId: tagId,
        newCardsPerDay: int.tryParse(newController.text.trim()) ?? 0,
        reviewCardsPerDay: int.tryParse(reviewController.text.trim()) ?? 0,
      );
  ref.invalidate(reviewGroupPlansProvider);
}

/// The compact 复习偏好 block: the two persisted preferences the user asked for
/// ("题型方式的喜好"), together in one card.
///
/// Kept a shared widget rather than written twice: the same two choices belong on
/// the review-plan surface and in the dialog the Knowledge module opens, and a
/// second copy would be the place where one of them gets forgotten.
class ReviewPreferencesCard extends ConsumerWidget {
  const ReviewPreferencesCard({super.key, this.showHeading = true});

  /// Whether to render the card's own title. False when the host already has a
  /// heading for it (the preferences dialog).
  final bool showHeading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final mode = ref.judgeModePreference;
    final cardType = ref.watch(cardTypePreferenceProvider);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHeading) ...[
              Row(
                children: [
                  Icon(Icons.tune, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(l10n.reviewPreferences,
                      style: theme.textTheme.titleSmall),
                ],
              ),
              const SizedBox(height: 10),
            ],
            Text(l10n.ankiJudgePreference, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            SegmentedButton<JudgeModePreference>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: JudgeModePreference.strict,
                  label: Text(l10n.ankiJudgeStrict),
                  tooltip: l10n.ankiJudgeStrictHint,
                ),
                ButtonSegment(
                  value: JudgeModePreference.lenient,
                  label: Text(l10n.ankiJudgeLenient),
                  tooltip: l10n.ankiJudgeLenientHint,
                ),
                ButtonSegment(
                  value: JudgeModePreference.self,
                  label: Text(l10n.ankiJudgeSelf),
                  tooltip: l10n.ankiJudgeSelfHint,
                ),
              ],
              selected: {mode},
              onSelectionChanged: (selection) => ref
                  .read(judgeModePreferenceProvider.notifier)
                  .select(selection.first),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.ankiJudgePreferenceDetail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(l10n.ankiTypePreference, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final option in CardTypePreference.values)
                  ChoiceChip(
                    label: Text(reviewPreferenceLabel(l10n, option)),
                    selected: option == cardType,
                    onSelected: (selected) {
                      if (selected) {
                        ref
                            .read(cardTypePreferenceProvider.notifier)
                            .select(option);
                      }
                    },
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.ankiTypePreferenceDetail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(l10n.reviewIntervalTitle, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            ref.watch(reviewRetentionProvider).when(
                  data: (spacing) => SegmentedButton<ReviewSpacing>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: ReviewSpacing.longer,
                        label: Text(l10n.reviewIntervalLonger),
                      ),
                      ButtonSegment(
                        value: ReviewSpacing.standard,
                        label: Text(l10n.reviewIntervalStandard),
                      ),
                      ButtonSegment(
                        value: ReviewSpacing.shorter,
                        label: Text(l10n.reviewIntervalShorter),
                      ),
                    ],
                    selected: {spacing},
                    onSelectionChanged: (selection) {
                      selectReviewSpacing(ref, selection.first);
                    },
                  ),
                  // The stored value is one short read; the flash lasts a frame on
                  // a warm DB. A spinner would flash harder than the gap it covers.
                  loading: () => const SizedBox(height: 40),
                  error: (error, _) => Text(
                    '$error',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.reviewIntervalHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the shared 复习偏好 block from wherever the user is.
///
/// A dialog rather than a navigation push on purpose: it is opened from the
/// review screen's app bar, and pushing a route there would throw away the
/// practice screen's state (its loaded queue and the position in it) for a
/// two-tap change.
Future<void> showReviewPreferencesDialog(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.reviewPreferences),
      content: const SingleChildScrollView(
        child: ReviewPreferencesCard(showHeading: false),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonClose),
        ),
      ],
    ),
  );
}

/// The user-facing name of a generation preference.
///
/// Public because the manage page's own menu shows the same list; one mapping
/// means the two surfaces cannot name the same preference differently.
String reviewPreferenceLabel(
  AppLocalizations l10n,
  CardTypePreference preference,
) =>
    switch (preference) {
      CardTypePreference.mixed => l10n.ankiTypePreferenceMixed,
      CardTypePreference.mcq => l10n.ankiTypeMcq,
      CardTypePreference.fillBlank => l10n.ankiTypeFillBlank,
      CardTypePreference.fillBlankLenient =>
        l10n.ankiTypePreferenceFillBlankLenient,
      CardTypePreference.essay => l10n.ankiTypeEssay,
    };

/// The "these cards are in no card group" notice.
///
/// Every daily target is set per card group, and a card group is a tag, so a
/// card with no tag cannot be reached by any target - it is not "unlimited", it
/// is out of scope. Cards created before the grouping existed are exactly like
/// that, which is why this says so instead of leaving them invisible.
class _UngroupedCardsCard extends ConsumerWidget {
  const _UngroupedCardsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final count = ref.watch(ungroupedKnowledgePointsProvider).valueOrNull ?? 0;
    if (count == 0) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.label_off_outlined,
                  size: 18,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.reviewPlanUngroupedTitle(count),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              l10n.reviewPlanUngroupedBody,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              icon: const Icon(Icons.label_outline, size: 18),
              label: Text(l10n.reviewPlanUngroupedAction),
              onPressed: () => _tagUngroupedCards(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}

/// Every tag, ordered the way the pickers show them.
Future<List<Tag>> _sortedTags(WidgetRef ref) async {
  final tags = await ref.read(tagRepositoryProvider).getAllTags();
  tags.sort((a, b) => (a.path ?? a.name).compareTo(b.path ?? b.name));
  return tags;
}

String _tagLabel(Tag tag) => tag.path ?? tag.name;

/// Lets the user pick one of [tags]; null when they back out.
Future<Tag?> _pickTag(
  BuildContext context,
  List<Tag> tags, {
  required String title,
}) {
  return showDialog<Tag>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(title),
      children: [
        for (final tag in tags)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, tag),
            child: Text(_tagLabel(tag)),
          ),
      ],
    ),
  );
}

/// Gives every card that has no tag the same tag, then opens that group's
/// daily-target editor.
///
/// Tagging is only half the job: a group with no target is still unlimited, and
/// the user came here to set "how many cards a day". So the editor opens right
/// away, and backing out of it is fine - the grouping has already happened.
Future<void> _tagUngroupedCards(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final tags = await _sortedTags(ref);
  if (!context.mounted) {
    return;
  }
  if (tags.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.reviewPlanNoTags)),
    );
    return;
  }
  final chosen = await _pickTag(context, tags, title: l10n.reviewPlanPickGroup);
  if (chosen == null || !context.mounted) {
    return;
  }
  final count = await ref
      .read(tagRepositoryProvider)
      .tagKnowledgePointsWithoutTags(chosen.id);
  ref.invalidate(ungroupedKnowledgePointsProvider);
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(l10n.reviewPlanUngroupedDone(count, _tagLabel(chosen))),
    ),
  );
  final plans = await ref.read(reviewGroupPlansProvider.future);
  if (!context.mounted) {
    return;
  }
  final existing = plans.where((p) => p.tagId == chosen.id).firstOrNull;
  await showCardGroupPlanEditor(
    context: context,
    ref: ref,
    tagId: chosen.id,
    tagPath: _tagLabel(chosen),
    plan: existing,
  );
}

/// The review-plan surface: 复习偏好 + the per-group daily plan (plan vs actual).
///
/// Both halves of the user's request live on one screen because they answer one
/// question - "how much am I doing today, and how should it be asked?" - and
/// because the practice screen itself is deliberately free of any planning
/// furniture.
class ReviewPlanPage extends ConsumerWidget {
  const ReviewPlanPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final plansAsync = ref.watch(reviewGroupPlansProvider);
    final loadAsync = ref.watch(reviewDayLoadProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.reviewPlanTitle),
        actions: [
          IconButton(
            tooltip: l10n.reviewPlanAdd,
            icon: const Icon(Icons.add),
            onPressed: () => _pickGroup(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const ReviewPreferencesCard(),
          const _UngroupedCardsCard(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Text(
                  l10n.reviewPlanToday,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                IconButton(
                  tooltip: l10n.commonRefresh,
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: () {
                    ref.invalidate(reviewGroupPlansProvider);
                    ref.invalidate(reviewDayLoadProvider);
                  },
                ),
              ],
            ),
          ),
          plansAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
            error: (error, stack) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('$error'),
            ),
            data: (plans) {
              if (plans.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.reviewPlanEmpty),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        icon: const Icon(Icons.add),
                        label: Text(l10n.reviewPlanAdd),
                        onPressed: () => _pickGroup(context, ref),
                      ),
                    ],
                  ),
                );
              }
              return loadAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: LinearProgressIndicator(),
                ),
                error: (error, stack) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('$error'),
                ),
                data: (load) => Column(
                  children: [
                    for (final group in load.groups)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: CardGroupPlanCard(group: group),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Asks which tag the new plan is for.
  ///
  /// Every tag is offered, including the ones that already have a plan: picking
  /// an existing group edits it rather than creating a second, conflicting
  /// target, because `setGroupPlan` upserts on the tag.
  Future<void> _pickGroup(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final tags = await _sortedTags(ref);
    if (!context.mounted) {
      return;
    }
    if (tags.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.reviewPlanNoTags)),
      );
      return;
    }
    final chosen =
        await _pickTag(context, tags, title: l10n.reviewPlanPickGroup);
    if (chosen == null || !context.mounted) {
      return;
    }
    final plans = await ref.read(reviewGroupPlansProvider.future);
    final existing = plans.where((p) => p.tagId == chosen.id).firstOrNull;
    if (!context.mounted) {
      return;
    }
    await showCardGroupPlanEditor(
      context: context,
      ref: ref,
      tagId: chosen.id,
      tagPath: _tagLabel(chosen),
      plan: existing,
    );
  }
}

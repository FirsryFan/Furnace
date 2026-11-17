import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/scheduling/thread_ranker.dart';
import '../../../l10n/app_localizations.dart';
import '../../thread/application/thread_rank_service.dart';

/// Settings -> Usage guide.
///
/// Written for the student using the app, not for the developer who built it:
/// what the three printed booklets are for, one line per module, where the
/// numbers come from, and the few details that change how a day goes.
///
/// Internal vocabulary stays out of this page on purpose. Words like "subtree",
/// "capability profile" and "raw readings under developer info" told the reader
/// nothing about their own studying; the plain-language versions live in the l10n
/// strings, and the developer-only material already has its own page
/// (Settings -> Developer).
///
/// Layout is grouped so the page can be skimmed: booklets -> modules -> numbers
/// -> day-to-day details -> ordering. The ranking entry keeps the labels and the
/// live numbers; this page explains them once.
class UsageDocPage extends ConsumerWidget {
  const UsageDocPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsUsageDoc)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: [
          // 1. The printed booklets: the first thing a new user meets.
          _SectionHeader(title: l10n.docSectionStart),
          _DocEntry(
            icon: Icons.menu_book_outlined,
            title: l10n.docBooksTitle,
            body: l10n.docBooksBody,
          ),

          // 2. One line per module, so "what is this tab" has a one-line answer.
          _SectionHeader(title: l10n.docSectionModules),
          _DocEntry(
            icon: Icons.today_outlined,
            title: l10n.docModuleTodayTitle,
            body: l10n.docModuleTodayBody,
          ),
          _DocEntry(
            icon: Icons.insights_outlined,
            title: l10n.docModuleStatusTitle,
            body: l10n.docModuleStatusBody,
          ),
          _DocEntry(
            icon: Icons.fact_check_outlined,
            title: l10n.docModuleAssessmentTitle,
            body: l10n.docModuleAssessmentBody,
          ),
          _DocEntry(
            icon: Icons.library_books_outlined,
            title: l10n.docModuleLibraryTitle,
            body: l10n.docModuleLibraryBody,
          ),
          _DocEntry(
            icon: Icons.account_tree_outlined,
            title: l10n.docModuleTagsTitle,
            body: l10n.docModuleTagsBody,
          ),
          _DocEntry(
            icon: Icons.quiz_outlined,
            title: l10n.docModuleBankTitle,
            body: l10n.docModuleBankBody,
          ),

          // 3. The three words that decide how much a number is worth.
          _SectionHeader(title: l10n.docSectionNumbers),
          _DocEntry(
            icon: Icons.percent,
            title: l10n.docNumbersTitle,
            body: l10n.docNumbersBody,
          ),

          // 4. Day-to-day behaviour worth knowing before it surprises you.
          _SectionHeader(title: l10n.docSectionDetails),
          _DocEntry(
            icon: Icons.smart_toy_outlined,
            title: l10n.docAiTitle,
            body: l10n.docAiBody,
          ),
          _DocEntry(
            icon: Icons.school_outlined,
            title: l10n.docReviewTitle,
            body: l10n.docReviewBody,
          ),
          _DocEntry(
            icon: Icons.photo_library_outlined,
            title: l10n.docMaterialTitle,
            body: l10n.docMaterialBody,
          ),

          // 5. Ordering: the total, the weights and the colours.
          _SectionHeader(title: l10n.docSectionSorting),
          _DocEntry(
            icon: Icons.functions,
            title: l10n.docFormulaTitle,
            body: l10n.docFormulaBody,
          ),
          _LiveDefaultsCard(),
          _DocEntry(
            icon: Icons.local_fire_department,
            title: l10n.propUrgency,
            body: l10n.propUrgencyHint,
          ),
          _DocEntry(
            icon: Icons.my_location,
            title: l10n.propGoalMatch,
            body: l10n.propGoalMatchHint,
          ),
          _DocEntry(
            icon: Icons.bolt,
            title: l10n.propFit,
            body: l10n.propFitHint,
          ),
          _DocEntry(
            icon: Icons.schedule,
            title: l10n.propExpectedPressure,
            body: l10n.propExpectedPressureHint,
          ),
          _DocEntry(
            icon: Icons.bedtime_outlined,
            title: l10n.propFatigue,
            body: l10n.propFatigueHint,
          ),
          _DocEntry(
            icon: Icons.tune,
            title: l10n.propWeights,
            body: l10n.propWeightsHint,
          ),
          _DocEntry(
            icon: Icons.flag_outlined,
            title: l10n.docStatusTitle,
            body: l10n.docStatusBody,
          ),
        ],
      ),
    );
  }
}

/// One group heading in the guide ("Start here", "What each part does").
///
/// The page used to be one flat list of cards; a long list with no landmarks is
/// hard to skim, which was the "can't follow it" half of the user feedback.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DocEntry extends StatelessWidget {
  const _DocEntry({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
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
                  child: Text(title, style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows the shipped defaults next to the user's current values, so a changed
/// weight is visible at a glance.
class _LiveDefaultsCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final weightsAsync = ref.watch(currentWeightsProvider);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.straighten,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l10n.docCurrentWeights,
                      style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 10),
            weightsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, stack) => Text('$error'),
              data: (weights) {
                const defaults = RankWeights();
                return Column(
                  children: [
                    _WeightRow(
                      label: l10n.propUrgency,
                      current: weights.urgency,
                      shipped: defaults.urgency,
                    ),
                    _WeightRow(
                      label: l10n.propGoalMatch,
                      current: weights.goal,
                      shipped: defaults.goal,
                    ),
                    _WeightRow(
                      label: l10n.propFit,
                      current: weights.fit,
                      shipped: defaults.fit,
                    ),
                    _WeightRow(
                      label: l10n.propExpectedPressure,
                      current: weights.expected,
                      shipped: defaults.expected,
                    ),
                    _WeightRow(
                      label: l10n.propFatigue,
                      current: weights.fatigue,
                      shipped: defaults.fatigue,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.docWeightsNormalized,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _WeightRow extends StatelessWidget {
  const _WeightRow({
    required this.label,
    required this.current,
    required this.shipped,
  });

  final String label;
  final double current;
  final double shipped;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final changed = (current - shipped).abs() > 1e-9;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(
            current.toStringAsFixed(2),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: changed ? theme.colorScheme.primary : null,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Text(
              '(${shipped.toStringAsFixed(2)})',
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

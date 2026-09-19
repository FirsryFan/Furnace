import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/scheduling/thread_ranker.dart';
import '../../../l10n/app_localizations.dart';
import '../../thread/application/thread_rank_service.dart';

/// Settings -> Usage documentation (user feedback item 1).
///
/// Every ranking parameter is explained in ONE place instead of being
/// duplicated inside the event property page. The property page keeps the
/// labels and the live numbers; the "why" lives here.
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
          _DocEntry(
            icon: Icons.functions,
            title: l10n.docFormulaTitle,
            body: l10n.docFormulaBody,
          ),
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
          _LiveDefaultsCard(),
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

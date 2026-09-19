import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database.dart';
import '../../../data/repositories/diffusion_log_repository.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../l10n/app_localizations.dart';

/// Which local day the insight screen shows.
final insightDayProvider = StateProvider<DateTime>((ref) => DateTime.now());

/// The day's study ledger (blueprint 4.4; user annotation 19).
///
/// This is deliberately a SEPARATE screen from practice: the practice screen
/// stays clean for flow, and "what did I get wrong today" lives here.
final insightSummaryProvider =
    FutureProvider.family<DiffusionDaySummary, DateTime>((ref, day) {
  return ref.watch(diffusionLogRepositoryProvider).summarizeDay(day);
});

class KnowledgeInsightPage extends ConsumerWidget {
  const KnowledgeInsightPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final day = ref.watch(insightDayProvider);
    final summaryAsync = ref.watch(insightSummaryProvider(day));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.knowledgeInsight),
        actions: [
          IconButton(
            tooltip: l10n.commonRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(insightSummaryProvider(day)),
          ),
        ],
      ),
      body: summaryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('$error')),
        data: (summary) {
          if (summary.isEmpty) {
            return Center(child: Text(l10n.knowledgeInsightEmpty));
          }
          final wrong = summary.entries.where((e) => e.kind == 'wrong').toList();
          final boosts = summary.entries.where((e) => e.kind == 'boost').toList();

          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              _DayHeader(summary: summary),
              if (wrong.isNotEmpty) ...[
                _SectionHeader(
                  icon: Icons.close,
                  color: Theme.of(context).colorScheme.error,
                  title: l10n.knowledgeInsightWrong,
                ),
                for (final entry in wrong) _LedgerTile(entry: entry),
              ],
              if (boosts.isNotEmpty) ...[
                _SectionHeader(
                  icon: Icons.local_fire_department,
                  color: Colors.deepOrange,
                  title: l10n.knowledgeInsightBoost,
                ),
                for (final entry in boosts) _LedgerTile(entry: entry),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _DayHeader extends ConsumerWidget {
  const _DayHeader({required this.summary});

  final DiffusionDaySummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Icon(Icons.today, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(summary.dayKey, style: theme.textTheme.titleSmall),
          const Spacer(),
          _Counter(
            icon: Icons.close,
            value: summary.wrongCount,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 12),
          _Counter(
            icon: Icons.local_fire_department,
            value: summary.boostCount,
            color: Colors.deepOrange,
          ),
        ],
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({
    required this.icon,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text('$value', style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.color,
    required this.title,
  });

  final IconData icon;
  final Color color;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _LedgerTile extends StatelessWidget {
  const _LedgerTile({required this.entry});

  final DiffusionLog entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final subtitleParts = <String>[
      if (entry.detail != null && entry.detail!.isNotEmpty) entry.detail!,
      if (entry.distance != null)
        l10n.knowledgeInsightDistance(entry.distance!),
      if (entry.factor != null)
        l10n.knowledgeInsightFactor(entry.factor!.toStringAsFixed(1)),
    ];

    return ListTile(
      dense: true,
      leading: Icon(
        entry.kind == 'wrong' ? Icons.cancel_outlined : Icons.arrow_upward,
        color: entry.kind == 'wrong'
            ? theme.colorScheme.error
            : Colors.deepOrange,
      ),
      title: Text(entry.ownerTitle ?? entry.knowledgePointTitle ?? '-'),
      subtitle: subtitleParts.isEmpty ? null : Text(subtitleParts.join(' · ')),
    );
  }
}

/// The cognitive model's read-only observation surface: the "认知模型" page and
/// the one place a *reading* is assembled.
///
/// Three jobs live here:
///
/// * **the reading.** [assembleCognitiveReadings] turns stored rows into the
///   numbers a human should see. It calls exactly two things - the injected
///   [CognitiveModel] and `ReviewAdvisory` - and invents no arithmetic of its
///   own: no curve, no comparator, no band rule. That is what keeps this page,
///   the review queue and the command-line probe from disagreeing (D2: one
///   source of truth per number).
/// * **the page.** Read-only by construction: it lists knowledge points, card
///   states and boost entries (all `select`s) and writes nothing. The two
///   disclaimers the user must see - advisor mode and the uncalibrated weights -
///   are rendered above the list rather than hidden in a tooltip.
/// * **the probe's view model.** The same `toJson()` shapes are what
///   `tool/mindnet_probe.dart` prints, so "what the CLI says" and "what the page
///   says" are the same claim, computed the same way. The CLI owns the database
///   side of that handshake (copy, read-only open, integrity witnesses) and the
///   host entry (`test/tool/mindnet_probe_report_test.dart`) owns the Flutter
///   runtime the model seam needs; this file owns the meaning.
///
/// What this file deliberately does **not** do:
///
/// * it does not run the tierB fast layer, so [ReviewZone.unavailable] is the
///   honest zone for every card here (the review queue passes no diagnosis map
///   either - §9.5). `unavailable` explicitly does *not* mean "no problem"
///   ([ReviewZone.healthy]); the page says so in words.
/// * it does not touch `dueAt`, `stability` or `difficulty`: FSRS owns those
///   (D1). The model influences the queue order and nothing else.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/database/app_database_provider.dart';
import '../../../data/database/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/cognitive/cognitive_model.dart';
import '../../../domain/services/cognitive/fast_diagnosis.dart'
    show BottleneckType;
import '../../../domain/services/srs/fsrs_scheduler.dart';
import '../../../l10n/app_localizations.dart';
import '../../anki/application/review_advisory.dart';

/// One card as the observation surface sees it: the stored row plus what it
/// belongs to. `isNew` is the review flow's own flag (D4), not a second
/// definition derived from the row.
class CognitiveObservedUnit {
  const CognitiveObservedUnit({
    required this.row,
    required this.knowledgePointTitle,
    required this.tagCount,
    required this.isNew,
  });

  /// Reads one unit back from the probe's JSON handshake.
  ///
  /// The map is the CLI's read-only export of a `card_states` row plus the two
  /// facts the model seam cannot see by itself (the title, the tag count). It is
  /// parsed here - next to [CardState] - so the shape has one owner.
  factory CognitiveObservedUnit.fromJson(Map<String, Object?> json) {
    final row = (json['row'] as Map?)?.cast<String, Object?>() ?? const {};
    return CognitiveObservedUnit(
      row: CardState(
        id: _jsonString(row['id']) ?? '',
        cardTemplateId: _jsonString(row['cardTemplateId']),
        dueAt: _jsonInt(row['dueAt']),
        intervalDays: _jsonDouble(row['intervalDays']) ?? 0,
        ease: _jsonDouble(row['ease']) ?? 2.5,
        repetitions: _jsonInt(row['repetitions']) ?? 0,
        lapses: _jsonInt(row['lapses']) ?? 0,
        state: _jsonString(row['state']) ?? 'new',
        lastReviewedAt: _jsonInt(row['lastReviewedAt']),
        createdAt: _jsonInt(row['createdAt']) ?? 0,
        updatedAt: _jsonInt(row['updatedAt']) ?? 0,
        knowledgePointId: _jsonString(row['knowledgePointId']),
        unitKey: _jsonString(row['unitKey']),
        stability: _jsonDouble(row['stability']),
        difficulty: _jsonDouble(row['difficulty']),
        encodingStrength: _jsonDouble(row['encodingStrength']),
        savings: _jsonDouble(row['savings']),
        forced: _jsonInt(row['forced']) ?? 0,
        forcedStreak: _jsonInt(row['forcedStreak']) ?? 0,
      ),
      knowledgePointTitle: _jsonString(json['knowledgePointTitle']) ?? '',
      tagCount: _jsonInt(json['tagCount']) ?? 0,
      isNew: json['isNew'] == true,
    );
  }

  final CardState row;
  final String knowledgePointTitle;
  final int tagCount;
  final bool isNew;

  /// The only value that identifies exactly one unit: `unitKey` can repeat
  /// across knowledge points (`'essay'` is the fallback for unblankable
  /// content), so every lookup is keyed by this.
  String get cardStateId => row.id;

  String get knowledgePointId => row.knowledgePointId ?? '';

  Map<String, Object?> toJson() => {
        'knowledgePointTitle': knowledgePointTitle,
        'tagCount': tagCount,
        'isNew': isNew,
        'row': {
          'id': row.id,
          'cardTemplateId': row.cardTemplateId,
          'dueAt': row.dueAt,
          'intervalDays': row.intervalDays,
          'ease': row.ease,
          'repetitions': row.repetitions,
          'lapses': row.lapses,
          'state': row.state,
          'lastReviewedAt': row.lastReviewedAt,
          'createdAt': row.createdAt,
          'updatedAt': row.updatedAt,
          'knowledgePointId': row.knowledgePointId,
          'unitKey': row.unitKey,
          'stability': row.stability,
          'difficulty': row.difficulty,
          'encodingStrength': row.encodingStrength,
          'savings': row.savings,
          'forced': row.forced,
          'forcedStreak': row.forcedStreak,
        },
      };
}

/// Everything the page reads before any model call: the units and the (explicitly
/// heuristic) diffusion boosts.
class CognitiveObservationInputs {
  const CognitiveObservationInputs({
    required this.units,
    this.boostFactorByKnowledgePoint = const {},
  });

  factory CognitiveObservationInputs.fromJson(Map<String, Object?> json) {
    final units = (json['units'] as List?) ?? const [];
    final boosts =
        (json['boostFactorByKnowledgePoint'] as Map?)?.cast<String, Object?>() ??
            const {};
    return CognitiveObservationInputs(
      units: [
        for (final unit in units)
          CognitiveObservedUnit.fromJson((unit as Map).cast<String, Object?>()),
      ],
      boostFactorByKnowledgePoint: {
        for (final entry in boosts.entries)
          if (_jsonDouble(entry.value) case final factor?) entry.key: factor,
      },
    );
  }

  final List<CognitiveObservedUnit> units;

  /// `DiffusionBoost` factors, keyed the way the review flow keys them (D5: a
  /// heuristic, not a model quantity - it selects a band, never a score).
  final Map<String, double> boostFactorByKnowledgePoint;

  Map<String, Object?> toJson() => {
        'units': [for (final unit in units) unit.toJson()],
        'boostFactorByKnowledgePoint': boostFactorByKnowledgePoint,
      };
}

/// One card's reading, in presentation order.
class CognitiveCardReading {
  const CognitiveCardReading({
    required this.cardStateId,
    required this.knowledgePointId,
    required this.knowledgePointTitle,
    required this.unitKey,
    required this.rank,
    required this.r,
    required this.gain,
    required this.r0,
    required this.sigma,
    required this.band,
    required this.zone,
    required this.isNew,
    required this.scoreUsedForOrdering,
    required this.boostFactor,
    required this.tagCount,
    required this.dueAt,
    required this.lastReviewedAt,
    required this.intervalDays,
    required this.suggestedIntervalDays,
    required this.repetitions,
    required this.lapses,
    required this.stability,
    required this.difficulty,
    required this.forced,
    required this.forcedStreak,
  });

  final String cardStateId;
  final String knowledgePointId;
  final String knowledgePointTitle;
  final String? unitKey;

  /// Position in `ReviewAdvisory`'s ranked queue (the order the review screen
  /// would use). `-1` only for a row the advisor did not rank.
  final int rank;

  /// `R0 * Psi(t/S)`: how well the card is known *now*.
  final double r;

  /// The model's claim about reviewing now ([CognitiveModel.expectedGain]).
  /// Meaningful for [ReviewBand.model] only - [scoreUsedForOrdering] says which.
  final double gain;

  /// The model-owned columns, read through the interface.
  final double r0;
  final double sigma;

  final ReviewBand band;
  final ReviewZone zone;

  /// The review flow's "never shown before" flag (D4).
  final bool isNew;

  /// True when this card's band is [ReviewBand.model], i.e. when [gain] is what
  /// decided its position.
  final bool scoreUsedForOrdering;

  /// The `DiffusionBoost` factor that put this card in [ReviewBand.boosted].
  /// `1.0` means not boosted.
  final double boostFactor;

  final int tagCount;
  final int? dueAt;
  final int? lastReviewedAt;

  /// What FSRS currently stores for this card.
  final double intervalDays;

  /// What FSRS would schedule if the card were answered "记得" now. **Not a
  /// model quantity**: the model has no interval-output API on purpose (D1),
  /// and this number is here so the page can show what "reviewing now" means on
  /// the authority that owns `dueAt`.
  final int suggestedIntervalDays;

  final int repetitions;
  final int lapses;
  final double? stability;
  final double? difficulty;
  final int forced;
  final int forcedStreak;

  Map<String, Object?> toJson() => {
        'cardStateId': cardStateId,
        'knowledgePointId': knowledgePointId,
        'knowledgePointTitle': knowledgePointTitle,
        'unitKey': unitKey,
        'rank': rank,
        'r': r,
        'gain': gain,
        'r0': r0,
        'sigma': sigma,
        'band': band.name,
        'zone': zone.name,
        'isNew': isNew,
        'scoreUsedForOrdering': scoreUsedForOrdering,
        'boostFactor': boostFactor,
        'tagCount': tagCount,
        'dueAt': dueAt,
        'lastReviewedAt': lastReviewedAt,
        'intervalDays': intervalDays,
        'suggestedIntervalDays': suggestedIntervalDays,
        'repetitions': repetitions,
        'lapses': lapses,
        'stability': stability,
        'difficulty': difficulty,
        'forced': forced,
        'forcedStreak': forcedStreak,
      };
}

/// The whole reading: per-card rows plus the advisor's own maps, unrenamed.
class CognitiveReadings {
  const CognitiveReadings({
    required this.modelId,
    required this.nowHours,
    required this.nowUtc,
    required this.cards,
    required this.bandByCardStateId,
    required this.scoreByCardStateId,
    required this.zoneByKnowledgePoint,
  });

  final String modelId;

  /// The model's clock (hours since the Unix epoch, §6.1) - not a duration.
  final double nowHours;
  final DateTime nowUtc;
  final List<CognitiveCardReading> cards;

  /// `ReviewAdvisory`'s maps, keyed by **card state id** (never `unitKey`:
  /// `'essay'` repeats across knowledge points).
  final Map<String, ReviewBand> bandByCardStateId;
  final Map<String, double> scoreByCardStateId;
  final Map<String, ReviewZone> zoneByKnowledgePoint;

  int get cardCount => cards.length;
  int get newCount => cards.where((card) => card.isNew).length;

  /// Mean R over the observed cards, or null when there is nothing to average.
  double? get meanR => cards.isEmpty
      ? null
      : cards.map((card) => card.r).reduce((a, b) => a + b) / cards.length;

  double? get minR => cards.isEmpty
      ? null
      : cards.map((card) => card.r).reduce((a, b) => a < b ? a : b);

  double? get meanGain => cards.isEmpty
      ? null
      : cards.map((card) => card.gain).reduce((a, b) => a + b) / cards.length;

  Map<ReviewBand, int> get bandCounts {
    final counts = <ReviewBand, int>{for (final band in ReviewBand.values) band: 0};
    for (final card in cards) {
      counts[card.band] = (counts[card.band] ?? 0) + 1;
    }
    return counts;
  }

  Map<ReviewZone, int> get zoneCounts {
    final counts = <ReviewZone, int>{for (final zone in ReviewZone.values) zone: 0};
    for (final card in cards) {
      counts[card.zone] = (counts[card.zone] ?? 0) + 1;
    }
    return counts;
  }

  Map<String, Object?> toJson() => {
        'schema': 'mindnet.readings/1',
        'modelId': modelId,
        'nowHours': nowHours,
        'nowUtc': nowUtc.toUtc().toIso8601String(),
        'summary': {
          'cards': cardCount,
          'newCards': newCount,
          'seenCards': cardCount - newCount,
          'meanR': meanR,
          'minR': minR,
          'meanGain': meanGain,
          'bandCounts': {
            for (final entry in bandCounts.entries) entry.key.name: entry.value,
          },
          'zoneCounts': {
            for (final entry in zoneCounts.entries) entry.key.name: entry.value,
          },
        },
        'cards': [for (final card in cards) card.toJson()],
        'bandByCardStateId': {
          for (final entry in bandByCardStateId.entries) entry.key: entry.value.name,
        },
        'scoreByCardStateId': scoreByCardStateId,
        'zoneByKnowledgePoint': {
          for (final entry in zoneByKnowledgePoint.entries) entry.key: entry.value.name,
        },
      };
}

/// Assembles the reading. **Pure**: rows in, numbers out - no database, no
/// clock, no IO, so the page, the probe host and a test all get the same answer
/// from the same inputs.
///
/// The only model call is through [CognitiveModel]; the banding and the zone
/// vocabulary are `ReviewAdvisory`'s (§9.5), and `starts`/`targets`-style
/// product rules stay where they belong (the review flow passes none here: this
/// page observes, it does not plan).
CognitiveReadings assembleCognitiveReadings({
  required List<CognitiveObservedUnit> units,
  required CognitiveModel model,
  required DateTime now,
  Map<String, double> boostFactorByKnowledgePoint = const {},
  Map<String, BottleneckType>? diagnosisByKnowledgePoint,
}) {
  final candidates = <ReviewCandidate>[
    for (final unit in units)
      ReviewCandidate(
        knowledgePointId: unit.knowledgePointId,
        row: unit.row,
        isNew: unit.isNew,
      ),
  ];
  final ordering = ReviewAdvisory.order(
    candidates: candidates,
    model: model,
    nowHours: modelHoursOf(now),
    boostFactorByKnowledgePoint: boostFactorByKnowledgePoint,
    diagnosisByKnowledgePoint: diagnosisByKnowledgePoint,
  );

  final unitByCandidate = Map<ReviewCandidate, CognitiveObservedUnit>.identity();
  for (var i = 0; i < candidates.length; i++) {
    unitByCandidate[candidates[i]] = units[i];
  }
  final rankByCardStateId = <String, int>{};
  for (var i = 0; i < ordering.ranked.length; i++) {
    rankByCardStateId[ordering.ranked[i].cardStateId] = i;
  }

  final cards = <CognitiveCardReading>[];
  for (final candidate in ordering.ranked) {
    final unit = unitByCandidate[candidate];
    if (unit == null) {
      // The advisor ranked something this call did not hand over (only possible
      // for a model implementation that invents candidates). Skip instead of
      // inventing a row for it.
      continue;
    }
    final row = unit.row;
    final reading = model.modelReadingOf(row, nowHours: modelHoursOf(now));
    final band = ordering.bandByCardStateId[candidate.cardStateId] ??
        ReviewBand.unseen;
    // The advisor only scores the model band (D4); every other row still gets
    // the model's answer to "what would reviewing this be worth", flagged as
    // not-deciding by `scoreUsedForOrdering`.
    final gain = ordering.scoreByCardStateId[candidate.cardStateId] ??
        model.expectedGain(row, nowHours: modelHoursOf(now));
    cards.add(CognitiveCardReading(
      cardStateId: candidate.cardStateId,
      knowledgePointId: unit.knowledgePointId,
      knowledgePointTitle: unit.knowledgePointTitle,
      unitKey: row.unitKey,
      rank: rankByCardStateId[candidate.cardStateId] ?? -1,
      r: reading.r,
      gain: gain,
      r0: reading.r0,
      sigma: reading.sigma,
      band: band,
      zone: ordering.zoneByKnowledgePoint[unit.knowledgePointId] ??
          ReviewZone.unavailable,
      isNew: unit.isNew,
      scoreUsedForOrdering: band == ReviewBand.model,
      boostFactor:
          boostFactorByKnowledgePoint[unit.knowledgePointId] ?? 1.0,
      tagCount: unit.tagCount,
      dueAt: row.dueAt,
      lastReviewedAt: row.lastReviewedAt,
      intervalDays: row.intervalDays,
      suggestedIntervalDays: _suggestedIntervalDays(row, now),
      repetitions: row.repetitions,
      lapses: row.lapses,
      stability: row.stability,
      difficulty: row.difficulty,
      forced: row.forced,
      forcedStreak: row.forcedStreak,
    ));
  }

  return CognitiveReadings(
    modelId: model.id,
    nowHours: modelHoursOf(now),
    nowUtc: now.toUtc(),
    cards: cards,
    bandByCardStateId: ordering.bandByCardStateId,
    scoreByCardStateId: ordering.scoreByCardStateId,
    zoneByKnowledgePoint: ordering.zoneByKnowledgePoint,
  );
}

/// [CognitiveReadings] from the probe's JSON handshake. The Flutter runtime is
/// the only place the model seam compiles, so this is the function the host
/// entry calls; the CLI never sees a `CardState`.
CognitiveReadings readingsFromUnitsJson(
  Map<String, Object?> json, {
  required DateTime now,
  CognitiveModel model = const MindNetCognitiveModel(),
}) {
  final inputs = CognitiveObservationInputs.fromJson(json);
  return assembleCognitiveReadings(
    units: inputs.units,
    model: model,
    now: now,
    boostFactorByKnowledgePoint: inputs.boostFactorByKnowledgePoint,
  );
}

/// The FSRS interval a "记得" answer now would produce.
///
/// Kept in this file next to the reading because it is *FSRS's* number, not the
/// model's: the model deliberately exposes no interval (D1), so the observation
/// surface must not invent one and call it a model output.
int _suggestedIntervalDays(CardState row, DateTime now) {
  final memory = row.stability == null
      ? null
      : FsrsMemory(
          stability: row.stability!,
          difficulty: row.difficulty ?? HeuristicCognitiveModel.fallbackDifficulty,
        );
  final lastReview = row.lastReviewedAt == null
      ? now
      : DateTime.fromMillisecondsSinceEpoch(row.lastReviewedAt!);
  return FsrsScheduler.schedule(
    memory: memory,
    lastReview: lastReview,
    now: now,
    rating: FsrsRating.good,
  ).scheduledDays;
}

/// One database read, all `select`s. Overridden in tests with fixture inputs so
/// the page can be driven without a database.
///
/// `autoDispose`: this reads every card state, so it must not stay alive (and
/// re-read on every write) once the page is closed.
final cognitiveObservationInputsProvider = FutureProvider.autoDispose<
    CognitiveObservationInputs>((ref) async {
  ref.watchDatabaseRevision();
  final db = ref.watch(appDatabaseProvider);

  final points = await db.select(db.knowledgePoints).get();
  final titles = {for (final point in points) point.id: point.title};

  // Tag counts for knowledge points. Plain `select` + counting in Dart: this is
  // the read-only observation surface, so it stays on the simplest drift calls
  // the rest of the app uses.
  final tagRows = await db.select(db.objectTags).get();
  final tagCounts = <String, int>{};
  for (final row in tagRows) {
    if (row.objectType != 'knowledge_point') {
      continue;
    }
    tagCounts[row.objectId] = (tagCounts[row.objectId] ?? 0) + 1;
  }

  final states = await db.select(db.cardStates).get();
  final boosts = await db.select(db.boostEntries).get();

  // A card state is only a card when its flashcard still exists, and the two
  // shapes resolve that link differently: a template-backed state names the
  // flashcard through its template, while a presentation unit
  // (`cloze:…` / `essay:…`) names it directly. Rows that resolve to nothing are
  // debris from a deletion performed before the cascade was complete - they are
  // counted separately ([orphanCardStateCountProvider]) instead of being drawn
  // as cards with no name, which is exactly how they were noticed.
  final templates = await db.select(db.cardTemplates).get();
  final flashcardOfTemplate = {
    for (final template in templates) template.id: template.knowledgePointId,
  };

  final live = <(CardState, String)>[];
  for (final state in states) {
    final templateId = state.cardTemplateId;
    final flashcardId = state.knowledgePointId ??
        (templateId == null ? null : flashcardOfTemplate[templateId]);
    if (flashcardId == null || !titles.containsKey(flashcardId)) {
      continue;
    }
    live.add((state, flashcardId));
  }

  return CognitiveObservationInputs(
    units: [
      for (final (state, flashcardId) in live)
        CognitiveObservedUnit(
          row: state,
          knowledgePointTitle: titles[flashcardId]!,
          tagCount: tagCounts[flashcardId] ?? 0,
          isNew: state.repetitions == 0,
        ),
    ],
    boostFactorByKnowledgePoint: {
      for (final boost in boosts)
        if (titles.containsKey(boost.knowledgePointId))
          boost.knowledgePointId: boost.factor,
    },
  );
});

/// How many card states belong to a flashcard that no longer exists.
///
/// The page shows this number (and offers to delete them) instead of listing
/// them as cards: they cannot be reviewed, so the only honest thing to do with
/// them is say so and let the user clear them.
final orphanCardStateCountProvider =
    FutureProvider.autoDispose<int>((ref) async {
  ref.watchDatabaseRevision();
  return ref.watch(ankiRepositoryProvider).countOrphanCardStates();
});

/// The reading the page shows: the injected model's numbers, the advisor's
/// bands, nothing else.
final cognitiveReadingsProvider =
    FutureProvider.autoDispose<CognitiveReadings>((ref) async {
  final inputs = await ref.watch(cognitiveObservationInputsProvider.future);
  final model = ref.watch(cognitiveModelProvider);
  return assembleCognitiveReadings(
    units: inputs.units,
    model: model,
    now: DateTime.now(),
    boostFactorByKnowledgePoint: inputs.boostFactorByKnowledgePoint,
  );
});

/// The read-only "认知模型" page. Read-only means: every access is a `select`,
/// and the two sentences at the top are part of the deliverable, not decoration.
class CognitiveModelPage extends ConsumerWidget {
  const CognitiveModelPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final readings = ref.watch(cognitiveReadingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.cognitiveModelTitle)),
      body: readings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorNote(l10n: l10n, error: error),
        data: (data) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _Notes(l10n: l10n),
            const SizedBox(height: 8),
            const _OrphanRepairBanner(),
            _Summary(l10n: l10n, readings: data),
            const SizedBox(height: 8),
            if (data.cards.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.cognitiveEmpty,
                  textAlign: TextAlign.center,
                ),
              )
            else
              for (final card in data.cards)
                _CardTile(l10n: l10n, card: card),
          ],
        ),
      ),
    );
  }
}

/// The repair path for card states whose flashcard is already gone.
///
/// Those rows were written by an older, incomplete cascade; they can never be
/// reviewed, so the page reports how many there are and offers to remove them
/// instead of drawing them as nameless cards. The action is explicit on
/// purpose: a silent cleanup on load would be a data change behind the user's
/// back, on a page that otherwise promises to be read-only.
class _OrphanRepairBanner extends ConsumerWidget {
  const _OrphanRepairBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final count = ref.watch(orphanCardStateCountProvider).valueOrNull ?? 0;
    if (count == 0) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final onContainer = theme.colorScheme.onErrorContainer;
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cleaning_services_outlined, color: onContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.cognitiveOrphanTitle(count),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: onContainer),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              l10n.cognitiveOrphanDetail,
              style: theme.textTheme.bodySmall?.copyWith(color: onContainer),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  final removed = await ref
                      .read(ankiRepositoryProvider)
                      .purgeOrphanKnowledgeRows();
                  ref.invalidate(orphanCardStateCountProvider);
                  ref.invalidate(cognitiveObservationInputsProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.cognitiveOrphanDone(removed)),
                      ),
                    );
                  }
                },
                child: Text(l10n.cognitiveOrphanAction(count)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the numbers are *allowed* to mean. Rendered above the list on purpose:
/// a user who reads only the first screen must not conclude that the model
/// schedules reviews or that its weights are calibrated.
class _Notes extends StatelessWidget {
  const _Notes({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _NoteRow(
              icon: Icons.insights_outlined,
              title: l10n.cognitiveAdvisorMode,
              detail: l10n.cognitiveAdvisorModeDetail,
              emphasis: theme.colorScheme.primary,
            ),
            const SizedBox(height: 8),
            _NoteRow(
              icon: Icons.warning_amber_outlined,
              title: l10n.cognitiveUncalibratedWeights,
              detail: l10n.cognitiveUncalibratedWeightsDetail,
              emphasis: theme.colorScheme.error,
            ),
            const SizedBox(height: 8),
            _NoteRow(
              icon: Icons.lock_outline,
              title: l10n.cognitiveReadOnlyNote,
              detail: l10n.cognitiveZoneNote,
              emphasis: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.emphasis,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Color emphasis;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: emphasis),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: emphasis),
              ),
              Text(detail, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.l10n, required this.readings});

  final AppLocalizations l10n;
  final CognitiveReadings readings;

  @override
  Widget build(BuildContext context) {
    final meanR = readings.meanR;
    final bands = [
      for (final band in ReviewBand.values)
        if ((readings.bandCounts[band] ?? 0) > 0)
          '${bandLabel(l10n, band)} ${readings.bandCounts[band]}',
    ].join(' · ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.cognitiveSummary(readings.cardCount, readings.modelId),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(l10n.cognitiveSummaryBands(bands)),
            Text(l10n.cognitiveReadAt(readings.nowUtc.toLocal().toString())),
            Text(
              l10n.cognitiveSummaryNumbers(
                readings.newCount,
                meanR == null ? '—' : meanR.toStringAsFixed(3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardTile extends StatelessWidget {
  const _CardTile({required this.l10n, required this.card});

  final AppLocalizations l10n;
  final CognitiveCardReading card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = card.knowledgePointTitle.isEmpty
        ? card.cardStateId
        : card.knowledgePointTitle;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _Chip(
                  text: card.isNew
                      ? l10n.cognitiveNewCard
                      : l10n.cognitiveSeenCard,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.cognitiveCardId(card.cardStateId),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _Chip(
                  text: l10n.cognitiveRetrievability(
                    card.r.toStringAsFixed(3),
                  ),
                ),
                _Chip(text: l10n.cognitiveGain(card.gain.toStringAsFixed(3))),
                _Chip(text: l10n.cognitiveEncoding(card.r0.toStringAsFixed(2))),
                _Chip(
                  text: l10n.cognitiveSavings(card.sigma.toStringAsFixed(2)),
                ),
                _Chip(text: l10n.cognitiveTags(card.tagCount)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${l10n.cognitiveColumnBand}: ${bandLabel(l10n, card.band)}'
              '${card.band == ReviewBand.boosted ? ' ×${card.boostFactor.toStringAsFixed(1)}' : ''}',
              style: theme.textTheme.bodyMedium,
            ),
            Text(
              '${l10n.cognitiveColumnZone}: ${zoneLabel(l10n, card.zone)}',
              style: theme.textTheme.bodyMedium,
            ),
            Text(
              '${l10n.cognitiveColumnSchedule}: '
              '${_scheduleText(l10n, card)}',
              style: theme.textTheme.bodyMedium,
            ),
            if (!card.scoreUsedForOrdering && !card.isNew)
              Text(
                l10n.cognitiveGainNotUsed,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            if (card.isNew)
              Text(
                l10n.cognitiveNewCardNotOrdered,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }

  String _scheduleText(AppLocalizations l10n, CognitiveCardReading card) {
    final due = card.dueAt == null
        ? l10n.cognitiveNoSchedule
        : DateTime.fromMillisecondsSinceEpoch(card.dueAt!)
            .toLocal()
            .toString();
    return '${l10n.cognitiveDue(due)} · '
        '${l10n.cognitiveInterval(card.intervalDays.toStringAsFixed(1))} · '
        '${l10n.cognitiveSuggestedInterval(card.suggestedIntervalDays)}';
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.l10n, required this.error});

  final AppLocalizations l10n;
  final Object error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(l10n.cognitiveErrorTitle),
          const SizedBox(height: 8),
          Text('$error', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Band vocabulary, exhaustive on purpose: a fifth band in `ReviewAdvisory`
/// stops compiling here instead of silently rendering nothing.
String bandLabel(AppLocalizations l10n, ReviewBand band) => switch (band) {
      ReviewBand.forced => l10n.cognitiveBandForced,
      ReviewBand.boosted => l10n.cognitiveBandBoosted,
      ReviewBand.model => l10n.cognitiveBandModel,
      ReviewBand.unseen => l10n.cognitiveBandUnseen,
    };

/// Zone vocabulary, exhaustive on purpose (all nine `ReviewZone` values are
/// named, including [ReviewZone.unavailable] and [ReviewZone.healthy]).
String zoneLabel(AppLocalizations l10n, ReviewZone zone) => switch (zone) {
      ReviewZone.proximal => l10n.cognitiveZoneProximal,
      ReviewZone.empty => l10n.cognitiveZoneEmpty,
      ReviewZone.deadEnd => l10n.cognitiveZoneDeadEnd,
      ReviewZone.slow => l10n.cognitiveZoneSlow,
      ReviewZone.overload => l10n.cognitiveZoneOverload,
      ReviewZone.offGoal => l10n.cognitiveZoneOffGoal,
      ReviewZone.danger => l10n.cognitiveZoneDanger,
      ReviewZone.healthy => l10n.cognitiveZoneHealthy,
      ReviewZone.unavailable => l10n.cognitiveZoneUnavailable,
    };

String? _jsonString(Object? value) => value == null ? null : value as String;

int? _jsonInt(Object? value) => switch (value) {
      null => null,
      final int value => value,
      final num value => value.toInt(),
      final String value => int.tryParse(value),
      _ => null,
    };

double? _jsonDouble(Object? value) => switch (value) {
      null => null,
      final num value => value.toDouble(),
      final String value => double.tryParse(value),
      _ => null,
    };

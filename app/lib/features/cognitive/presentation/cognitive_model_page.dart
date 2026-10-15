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
/// * it does not reimplement the tierB fast layer: it asks
///   [LibraryDiagnosisRunner] for one run and hands the result to the advisor.
///   `null` (the run did not happen) and an empty map (it happened and found
///   nothing) must stay distinguishable - the first is
///   [ReviewZone.unavailable], the second [ReviewZone.healthy], and
///   `unavailable` explicitly does *not* mean "no problem". The review queue
///   still passes no diagnosis map (§9.5), so its zones stay `unavailable`.
/// * it does not touch `dueAt`, `stability` or `difficulty`: FSRS owns those
///   (D1). The model influences the queue order and nothing else.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/database/app_database_provider.dart';
import '../../../data/database/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/cognitive/assessment_prior.dart';
import '../../../domain/services/cognitive/cognitive_model.dart';
import '../../../domain/services/cognitive/fast_diagnosis.dart'
    show BottleneckType;
import '../../../domain/services/cognitive/library_diagnosis.dart';
import '../../../domain/services/cognitive/learning_metrics.dart';
import '../../../domain/services/cognitive/metacognition.dart';
import '../../../domain/services/srs/fsrs_scheduler.dart';
import '../../../l10n/app_localizations.dart';
import '../../anki/application/review_advisory.dart';
import '../../assessment/presentation/assessment_page.dart';
import '../../cognitive/application/library_diagnosis_reader.dart';
import 'zone_labels.dart';

// The band/zone words are re-exported so every existing importer of this page
// (`cognitive_model_page_test.dart` calls `zoneLabel`) keeps resolving them,
// while the review screen can import them without pulling in this whole page.
export 'zone_labels.dart';

// 观察层的读表 + 诊断跑动搬到了 `cognitive/application/library_diagnosis_reader.dart`
// （Q13）：页面、AI 工具、CLI 探针共用同一份读法，不再各写一遍。两个观察类型与
// 那个 start 上限仍从这里 re-export，既有 importer（页面测试、探针）不用改。
export '../../cognitive/application/library_diagnosis_reader.dart'
    show
        CognitiveObservationInputs,
        CognitiveObservedUnit,
        cognitiveStartNodeLimit;

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
    this.prior,
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

  /// The measurement prior for this card's knowledge point, when one exists
  /// (M1d). It is a *starting point*, not an observation: see [r0FromPrior].
  final AssessmentPriorEstimate? prior;

  /// Whether this card has any review history of its own. `repetitions` and
  /// `lastReviewedAt` are checked together because a row can be forced or
  /// re-imported and end up with one but not the other.
  bool get hasObservation => lastReviewedAt != null || repetitions > 0;

  /// True when the starting point shown for this card is the measurement prior
  /// instead of the model's own `r0`.
  ///
  /// A prior only speaks until the first real review: after that, the card's own
  /// history is the better evidence, and quietly letting the prior outrank it
  /// would be the "先验≠观测" mistake the design doc forbids (§8).
  bool get r0FromPrior => prior != null && !hasObservation;

  /// The value the page shows as this card's starting point.
  double get displayedR0 => r0FromPrior ? prior!.r0 : r0;

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
        'prior': prior?.toJson(),
        'r0FromPrior': r0FromPrior,
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
    this.fastLayerRan = false,
    this.metacognition = MetacognitionReading.empty,
    this.priorByKnowledgePoint = const {},
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

  /// Whether the tierB fast layer actually ran for this reading. False means
  /// every zone is [ReviewZone.unavailable] *because nothing was diagnosed* (no
  /// tag graph, or nothing to diffuse from) - not because the cards are healthy.
  final bool fastLayerRan;

  /// The metacognition layer's read, when the tierB run produced one. Empty
  /// (the default) means "not judged this run" - it is *not* a claim that
  /// nothing is in danger, which is why the page draws the section only when
  /// [fastLayerRan] is true.
  final MetacognitionReading metacognition;

  /// The measurement priors (M1d), keyed by knowledge point id. A prior is kept
  /// whole here - not folded into `r0` - because the page has to say *which*
  /// starting points are still guesses from a measurement rather than numbers
  /// that came out of the user's own reviews (§8: 先验≠观测).
  final Map<String, AssessmentPriorEstimate> priorByKnowledgePoint;

  /// Cards whose displayed starting point is a measurement prior.
  int get priorCount => cards.where((card) => card.r0FromPrior).length;

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
    final counts = <ReviewBand, int>{
      for (final band in ReviewBand.values) band: 0
    };
    for (final card in cards) {
      counts[card.band] = (counts[card.band] ?? 0) + 1;
    }
    return counts;
  }

  Map<ReviewZone, int> get zoneCounts {
    final counts = <ReviewZone, int>{
      for (final zone in ReviewZone.values) zone: 0
    };
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
        'fastLayerRan': fastLayerRan,
        'metacognition': metacognition.toJson(),
        'priorByKnowledgePoint': {
          for (final entry in priorByKnowledgePoint.entries)
            entry.key: entry.value.toJson(),
        },
        'priorCount': priorCount,
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
          for (final entry in bandByCardStateId.entries)
            entry.key: entry.value.name,
        },
        'scoreByCardStateId': scoreByCardStateId,
        'zoneByKnowledgePoint': {
          for (final entry in zoneByKnowledgePoint.entries)
            entry.key: entry.value.name,
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
///
/// [diagnosisByKnowledgePoint] is the tierB run's output
/// (`LibraryDiagnosisRunner`). Its `null` case is meaningful and must stay
/// distinguishable from an empty map: `null` = nothing was diagnosed
/// ([ReviewZone.unavailable]), empty = the layer ran and found nothing to
/// complain about ([ReviewZone.healthy]). [fastLayerRan] carries that fact into
/// the reading so the page can say which one happened.
CognitiveReadings assembleCognitiveReadings({
  required List<CognitiveObservedUnit> units,
  required CognitiveModel model,
  required DateTime now,
  Map<String, double> boostFactorByKnowledgePoint = const {},
  Map<String, BottleneckType>? diagnosisByKnowledgePoint,
  bool fastLayerRan = false,
  MetacognitionReading metacognition = MetacognitionReading.empty,
  Map<String, AssessmentPriorEstimate> priorByKnowledgePoint = const {},
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

  final unitByCandidate =
      Map<ReviewCandidate, CognitiveObservedUnit>.identity();
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
    final band =
        ordering.bandByCardStateId[candidate.cardStateId] ?? ReviewBand.unseen;
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
      boostFactor: boostFactorByKnowledgePoint[unit.knowledgePointId] ?? 1.0,
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
      prior: priorByKnowledgePoint[unit.knowledgePointId],
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
    fastLayerRan: fastLayerRan,
    metacognition: metacognition,
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
          difficulty:
              row.difficulty ?? HeuristicCognitiveModel.fallbackDifficulty,
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
final cognitiveObservationInputsProvider =
    FutureProvider.autoDispose<CognitiveObservationInputs>((ref) async {
  ref.watchDatabaseRevision();
  // 读表本体在 `cognitive/application/library_diagnosis_reader.dart`（Q13）：
  // 页面与 AI 工具读同一份，没有第二份"活卡判定"。
  return readCognitiveObservationInputs(ref.watch(appDatabaseProvider));
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

/// The measurement priors for the knowledge points currently on screen (M1d).
///
/// Kept apart from the reading so the reading stays a pure function of its
/// inputs and this is the only thing that touches the assessment tables: the
/// page's other numbers all come from `select`s on the model's own columns.
final cognitivePriorsProvider =
    FutureProvider.autoDispose<Map<String, AssessmentPriorEstimate>>(
        (ref) async {
  ref.watchDatabaseRevision();
  final inputs = await ref.watch(cognitiveObservationInputsProvider.future);
  return ref.watch(assessmentRepositoryProvider).priorEstimatesFor(
        inputs.units.map((unit) => unit.knowledgePointId),
      );
});

/// The learning-effect reading (M6): retention by interval plus whatever
/// calibration the predicted-`R` history supports.
///
/// Deliberately **not** derived from the fast layer or from the priors: it is a
/// `select` over `review_logs` only. That is what makes it an *external* check
/// on the model - if the numbers here were assembled from the model's own
/// reading, the curve would always agree with itself.
final learningMetricsProvider =
    FutureProvider.autoDispose<LearningMetrics>((ref) async {
  ref.watchDatabaseRevision();
  final samples = await ref.watch(ankiRepositoryProvider).retentionSamples();
  return LearningMetrics.read(samples: samples);
});

/// 知识点 id → 它直挂的标签 id（Q8）。
///
/// 这一层存在是因为**两套 id 不是一回事**：知识点是 `kp-…`，标签是 `tag-…`，
/// 而认知快层的图节点是标签（`cognitive_graph.dart` 的 `CognitiveTag.fromTag`
/// 直接取 `row.id`）。页面手里的是知识点，runner 要的是图节点，所以读一次
/// `object_tags` 交给 [KnowledgePointTagBridge] 翻译。
///
/// 以前没有这一层：页面把知识点 id 直接当图节点 id 传进去，`starts`/`targets`/
/// `rowsByKnowledgePoint` 在真实数据上全被丢掉，界面永远显示"这轮没诊断"
/// （实测与解释见 `docs/THREADFLOW_TWO_SEGMENT.md` §8.3）。
final knowledgePointTagIdsProvider =
    FutureProvider.autoDispose<Map<String, List<String>>>((ref) async {
  ref.watchDatabaseRevision();
  return readKnowledgePointTagIds(ref.watch(appDatabaseProvider));
});

/// The reading the page shows: the injected model's numbers, the advisor's
/// bands, the fast layer's zones - nothing else.
final cognitiveReadingsProvider =
    FutureProvider.autoDispose<CognitiveReadings>((ref) async {
  final inputs = await ref.watch(cognitiveObservationInputsProvider.future);
  final model = ref.watch(cognitiveModelProvider);
  final diagnosis = await ref.watch(cognitiveLibraryDiagnosisProvider.future);
  final priors = await ref.watch(cognitivePriorsProvider.future);
  return assembleCognitiveReadings(
    units: inputs.units,
    model: model,
    now: DateTime.now(),
    boostFactorByKnowledgePoint: inputs.boostFactorByKnowledgePoint,
    // `null` (not `{}`) when the layer did not run: the advisor turns that into
    // "unavailable", which is the honest zone for "nothing was diagnosed".
    //
    // The verdicts are keyed by knowledge point already: the runner translates
    // the graph's tag-keyed nodes back into the caller's key space (Q8), so every
    // consumer downstream (`review_advisory`, the review page, the AI tool) can
    // keep looking up by knowledge point.
    diagnosisByKnowledgePoint:
        diagnosis.fastLayerRan ? diagnosis.byKnowledgePoint : null,
    fastLayerRan: diagnosis.fastLayerRan,
    metacognition: diagnosis.metacognition,
    priorByKnowledgePoint: priors,
  );
});

/// How many recently reviewed knowledge points seed the diffusion ("what the
/// user is holding in mind right now", §6.3). A product rule, not a calibrated
/// number: the model cannot tell us this, so the page states it here.
const int cognitiveStartNodeLimit = 5;

/// The tierB run behind the zone column: the tag tree plus one representative
/// card row per knowledge point, diffused once from the most recently reviewed
/// points toward today's due set.
///
/// Two product rules are visible here on purpose (Furnace has no goal entity):
///
/// * `starts` = the [cognitiveStartNodeLimit] most recently reviewed points.
/// * `targets` = the points with something due now (or a forced card) - "what
///   this session is trying to push". Nodes outside that set can therefore be
///   reported as `off_goal` / `dead_end`, which is what those verdicts mean.
///
/// `danger` can appear here: it is the metacognition layer's verdict on a
/// tagged point that has a representative card row and is not one of `starts` -
/// `LibraryDiagnosisRunner._readMetacognition` derives the belief/reality gap
/// from the stored rows, it does not need a belief table. A point with no card
/// row (or no finite reading) is skipped there, so "absent" means "no data",
/// not "healthy".
final cognitiveLibraryDiagnosisProvider =
    FutureProvider.autoDispose<LibraryDiagnosis>((ref) async {
  ref.watchDatabaseRevision();
  // 读表 + 跑 runner 都在 `cognitive/application/library_diagnosis_reader.dart`
  // （Q13）：页面与 AI 工具的 `compose_paper` 调同一份函数，页面说"危险"的点，
  // 组卷读数里也是危险（D2）。这里的 inputs 复用页面已经 watch 的那一份，
  // 所以这次改造没有让同一屏多读一遍表。
  return readLibraryDiagnosis(
    ref.watch(appDatabaseProvider),
    model: ref.watch(cognitiveModelProvider),
    inputs: await ref.watch(cognitiveObservationInputsProvider.future),
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
            _AssessmentEntry(l10n: l10n),
            const SizedBox(height: 8),
            _Notes(
              l10n: l10n,
              fastLayerRan: data.fastLayerRan,
              priorCount: data.priorCount,
            ),
            const SizedBox(height: 8),
            const _OrphanRepairBanner(),
            _Summary(l10n: l10n, readings: data),
            if (data.fastLayerRan)
              _Metacognition(l10n: l10n, reading: data.metacognition),
            const _LearningMetricsSection(),
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
              for (final card in data.cards) _CardTile(l10n: l10n, card: card),
          ],
        ),
      ),
    );
  }
}

/// The way out of "every number here is a default": one short measurement.
///
/// It sits above the notes because the page's own disclaimers are about what
/// the model does *not* know yet, and this is the only action that changes that
/// - a user who reads "weights are uncalibrated" and has nowhere to go learns
/// nothing. The page stays select-only: the write happens on the assessment
/// page, behind an explicit tap.
class _AssessmentEntry extends StatelessWidget {
  const _AssessmentEntry({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.assessmentTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AssessmentPage(),
                ),
              ),
              icon: const Icon(Icons.assignment_outlined),
              label: Text(l10n.assessmentEntryAction),
            ),
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
  const _Notes({
    required this.l10n,
    required this.fastLayerRan,
    required this.priorCount,
  });

  final AppLocalizations l10n;

  /// Whether the tierB run happened. The note says which, because the page now
  /// runs it - a "the page never diagnoses" sentence would be a lie.
  final bool fastLayerRan;

  /// How many cards are currently showing a measurement prior as their starting
  /// point (M1d). Zero is a fact worth stating: it tells the user the numbers on
  /// this page are all defaults or observations, and the measurement page is one
  /// tap away.
  final int priorCount;

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
            const SizedBox(height: 8),
            _NoteRow(
              icon: Icons.travel_explore_outlined,
              title: l10n.cognitiveFastLayerNote,
              detail: fastLayerRan
                  ? l10n.cognitiveFastLayerRanDetail
                  : l10n.cognitiveFastLayerNotRunDetail,
              emphasis: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            _NoteRow(
              icon: Icons.psychology_outlined,
              title: l10n.cognitiveZoneDanger,
              detail: l10n.cognitiveDangerNote,
              emphasis: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            _NoteRow(
              icon: Icons.assignment_turned_in_outlined,
              title: l10n.cognitivePriorNote,
              detail: priorCount > 0
                  ? l10n.cognitivePriorCount(priorCount)
                  : l10n.cognitivePriorNone,
              emphasis: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// The metacognition layer's read, shown as named lists rather than a chart.
///
/// This is the only block on the page that puts two different quantities side by
/// side - what the model believes (belief) against what the cards can actually
/// do (retrievability) - so a single number would hide the point. The names and
/// the gap threshold come from [MetacognitionReading]; this widget rounds
/// nothing and decides nothing.
///
/// It renders only when the tierB run happened, because danger and
/// underestimation are statements *about a run*: without one there is nothing to
/// compare, and drawing the empty list would read as "no problem".
class _Metacognition extends StatelessWidget {
  const _Metacognition({required this.l10n, required this.reading});

  final AppLocalizations l10n;
  final MetacognitionReading reading;

  /// ' · ' rather than a locale comma: the same separator reads correctly in
  /// both languages, so this widget does not have to branch on locale.
  static String _names(List<MetacognitionRow> rows) =>
      [for (final row in rows) row.name].join(' · ');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.psychology_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.cognitiveMetacognitionTitle,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(l10n.cognitiveMetacognitionDetail, style: subtle),
              const SizedBox(height: 8),
              if (!reading.hasRows)
                Text(l10n.cognitiveMetacognitionNoRows, style: subtle)
              else ...[
                Text(
                  l10n.cognitiveMetacognitionCalibration(
                    reading.calibration.toStringAsFixed(3),
                  ),
                  style: subtle,
                ),
                if (reading.danger.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    l10n.cognitiveMetacognitionDanger(_names(reading.danger)),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                if (reading.anxiety.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    l10n.cognitiveMetacognitionAnxiety(_names(reading.anxiety)),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                ],
                if (reading.danger.isEmpty && reading.anxiety.isEmpty) ...[
                  const SizedBox(height: 6),
                  Text(l10n.cognitiveMetacognitionLevel, style: subtle),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "学得到底怎么样"——M6 的留存率与校准度。
///
/// 这一块是整页唯一一个**不看成模型自己的读数**的卡片：数字全部来自复习日志，
/// 所以它是模型的考官，而不是模型的自我介绍。校准那一半在没有带预测的复习时
/// 明说没有，而不是画一条由假设拼出来的曲线。
class _LearningMetricsSection extends ConsumerWidget {
  const _LearningMetricsSection();

  static String _days(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);

  static String _range(RetentionBucket bucket) => bucket.hiDays.isFinite
      ? '${_days(bucket.loDays)}–${_days(bucket.hiDays)}'
      : '${_days(bucket.loDays)}+';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final subtle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final metrics = ref.watch(learningMetricsProvider);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.insights_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.learningMetricsTitle,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(l10n.learningMetricsDetail, style: subtle),
              const SizedBox(height: 8),
              if (metrics.isLoading)
                const SizedBox(
                  height: 16,
                  child: Center(
                    child: SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (metrics.hasError)
                Text(l10n.learningMetricsUnavailable, style: subtle)
              else
                ..._body(l10n, theme, subtle, metrics.requireValue),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(
    AppLocalizations l10n,
    ThemeData theme,
    TextStyle? subtle,
    LearningMetrics data,
  ) {
    if (data.isEmpty) {
      return [Text(l10n.learningMetricsEmpty, style: subtle)];
    }

    final retained = (data.retention * 100).round();
    final shown = [
      for (final b in data.buckets)
        if (b.samples > 0) b
    ];
    return [
      Text(
        l10n.learningMetricsOverall(data.reviewedCount, retained),
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: 6),
      if (shown.isEmpty)
        Text(l10n.learningMetricsNoBuckets, style: subtle)
      else
        for (final bucket in shown)
          Text(
            l10n.learningMetricsBucket(
              _range(bucket),
              bucket.samples,
              (bucket.retention * 100).round(),
            ),
            style: subtle,
          ),
      const SizedBox(height: 6),
      // 有预测样本才谈校准；否则这句话就是"这一版之前根本没记过预测"，
      // 与"模型很准"（brier 0）必须能被区分开。
      Text(
        data.hasCalibration
            ? l10n.learningMetricsCalibration(
                data.brier!.toStringAsFixed(3),
                data.ece!.toStringAsFixed(3),
              )
            : l10n.learningMetricsNoCalibration,
        style: subtle,
      ),
    ];
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
                _Chip(
                  text: card.r0FromPrior
                      ? l10n.cognitiveEncodingPrior(
                          card.displayedR0.toStringAsFixed(2),
                        )
                      : l10n.cognitiveEncoding(
                          card.displayedR0.toStringAsFixed(2)),
                ),
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
        : DateTime.fromMillisecondsSinceEpoch(card.dueAt!).toLocal().toString();
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

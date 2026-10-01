/// The review queue's advisor: turns "which cards exist" into "which order to
/// show them in, and what the model thinks of each".
///
/// Three things live here and nowhere else:
///
/// * **the bands.** The queue is shown in four groups -
///   `forced -> boosted -> model -> unseen`. The model band leads the unseen
///   band on purpose: the whole value of wiring the model in is "review what
///   you are about to forget first", and a new card has no history for the
///   model to judge (decision D4), so letting new cards sit in front of the
///   model's ranking would dilute exactly the effect that justifies the
///   integration.
/// * **the zone vocabulary.** [ReviewZone] is the *coarse* app-facing answer to
///   "development zone or dead end". The *fine* vocabulary is the fast layer's
///   `BottleneckType`; this file only translates, it never invents a diagnosis
///   (MINDNET_CONTRACT §6.3).
/// * **the band labels.** [ReviewOrdering.bandByCardStateId] is what a
///   read-only view shows the user as the *reason* an item sits where it does.
///
/// What deliberately does **not** live here:
///
/// * **the model band's ordering rule.** That is
///   [CognitiveModel.orderAdvisory]'s, a total order with its own tests; a
///   second comparator here would be a second source of truth for the same
///   decision.
/// * **where a forced card is placed inside the queue.** That is
///   `ReviewService._interleave`'s rule (annotation 17: a wrong blank returns
///   a few cards later). This file labels forced items; it does not move them.
/// * **any write.** Nothing here touches a repository. The model's two columns
///   are written by `AnkiRepository.updateModelState`, and `FsrsScheduler` /
///   FSRS keep `stability` / `difficulty` / `dueAt` (D1/D2).
///
/// ## Why every lookup is keyed by the card state id
///
/// The queue has no globally unique "unit key": a knowledge point whose content
/// yields no blank gets the fallback unit key `'essay'`
/// (`ReviewService._itemFor`), so two such points produce two rows that share a
/// unit key. Content-derived cloze keys can repeat across points for the same
/// reason. `card_states.id` is the only value that identifies exactly one queue
/// entry, so the band and score maps are keyed by it.
library;

import '../../../data/database/database.dart';
import '../../../domain/services/cognitive/cognitive_model.dart';
import '../../../domain/services/cognitive/fast_diagnosis.dart'
    show BottleneckType;

/// Which part of the queue an item came from.
enum ReviewBand {
  /// Bound by a wrong answer: must reappear today. Placement is the caller's.
  forced,

  /// Lifted by `DiffusionBoost` because a related item went wrong.
  ///
  /// **A heuristic, not a model quantity** (D5, §6.5): the factors are
  /// `1.8 / 1.3` with no calibration source, so they are kept as their own band
  /// rather than blended into the model's score.
  boosted,

  /// Ordered by the cognitive model (gain, then the model's own tie-breaks).
  model,

  /// Never shown before - the band called "new" in decision D4.
  ///
  /// The model is not consulted: with no history there is nothing for it to
  /// judge. Spelled `unseen` because `new` is a Dart keyword and cannot be an
  /// enum constant.
  unseen,
}

/// Development zone, dead end, or "nobody asked the diagnosis layer".
///
/// One value per `BottleneckType` (no lossy collapse: `off_goal` and `danger`
/// are distinct verdicts with distinct advice, and folding `danger` into
/// "development zone" would tell the user the opposite of what the model said),
/// plus [unavailable] for when no diagnosis was produced at all.
enum ReviewZone {
  /// The fast layer's `weak`: it almost came back. This is the development
  /// zone - work the student can do right now.
  proximal,

  /// The fast layer's `empty`: nothing reaches it, or what reaches it is too
  /// weak to ignite. A **dead end in the sense of "no way in"**.
  ///
  /// This is **not** the same value as [unavailable]: `empty` means the
  /// diagnosis ran and concluded there is no entry; `unavailable` means no
  /// diagnosis exists. Mixing them would let "the model is not wired up here"
  /// read as "the student cannot do this" - the exact misreading 用途1's
  /// "all empty => out of syllabus / dead end" rule must avoid.
  empty,

  /// The fast layer's `dead_end`: it can be thought of, but nothing follows.
  deadEnd,

  /// The fast layer's `slow`: it lights up, but only after too many rounds.
  slow,

  /// The fast layer's `overload`: the knowledge is there and was outcompeted by
  /// capacity - a different problem from a knowledge gap.
  overload,

  /// The fast layer's `off_goal`: it lit up but cannot reach any target.
  offGoal,

  /// The fast layer's `danger`: confidently wrong - high subjective ease, low
  /// actual retrievability. Never folded into [proximal].
  danger,

  /// **The diagnosis layer ran and found no bottleneck for this knowledge
  /// point.** A node with no verdict lit up, is on target, and has somewhere to
  /// go.
  ///
  /// Distinct from [unavailable] on purpose - "we looked and it is fine" is not
  /// "nobody looked" - and distinct from [empty], which is a *complaint*.
  healthy,

  /// **No diagnosis was produced at all** (the fast layer is off, or the caller
  /// did not run it). This says nothing about the student.
  unavailable,
}

/// One candidate unit as the advisor sees it.
class ReviewCandidate {
  const ReviewCandidate({
    required this.knowledgePointId,
    required this.row,
    required this.isNew,
  });

  /// The knowledge point this unit belongs to (one point can own several
  /// units, so every tie-break ends on [cardStateId] instead).
  final String knowledgePointId;

  /// The stored `card_states` row. Passed in, never fetched: this file stays a
  /// pure function so it can be tested with a closed database.
  final CardState row;

  /// "This blank has never been shown before", passed through from the review
  /// item. It is the caller's existing flag rather than a second definition
  /// derived from the row - D4 is about what the user has seen.
  final bool isNew;

  /// The row id: the only value that identifies exactly one queue entry.
  String get cardStateId => row.id;
}

/// The advisor's whole output.
class ReviewOrdering {
  const ReviewOrdering({
    required this.ranked,
    required this.bandByCardStateId,
    required this.zoneByKnowledgePoint,
    required this.scoreByCardStateId,
  });

  /// The queue in presentation order: `forced -> boosted -> model -> unseen`.
  ///
  /// Forced items are listed for the caller to place (see the library doc);
  /// everything else is already in final order.
  final List<ReviewCandidate> ranked;

  /// The band of every candidate, keyed by [ReviewCandidate.cardStateId] - the
  /// label a read-only view shows as "why is this here".
  final Map<String, ReviewBand> bandByCardStateId;

  /// The zone of every knowledge point that had a candidate here. Absent
  /// knowledge points simply have no entry.
  final Map<String, ReviewZone> zoneByKnowledgePoint;

  /// The model's score (`CognitiveModel.expectedGain`) for **model-band items
  /// only**, keyed by [ReviewCandidate.cardStateId]. New cards have no score on
  /// purpose (D4), and forced/boosted items are in their band for reasons the
  /// model did not decide.
  final Map<String, double> scoreByCardStateId;
}

/// The advisor. Pure: no database, no clock, no IO, no mutation of the input.
abstract final class ReviewAdvisory {
  /// Partitions [candidates] into bands and orders each band.
  ///
  /// * `boostFactorByKnowledgePoint` - the existing `DiffusionBoost` factors,
  ///   keyed the way the review flow already keys them. `> 1.0` means boosted
  ///   (D5). Values `<= 1.0` or missing mean "not boosted".
  /// * `diagnosisByKnowledgePoint` - the fast layer's verdict per knowledge
  ///   point, and the only place the two "nothing to report" cases are told
  ///   apart:
  ///   * **`null` means the diagnosis layer did not run** - every zone becomes
  ///     [ReviewZone.unavailable], which says nothing about the student;
  ///   * a **knowledge point missing from a non-null map** is
  ///     [ReviewZone.healthy]: the layer ran and produced no verdict for that
  ///     node, which is what the fast layer reports for a node that lit up, is
  ///     on target and has somewhere to go.
  ///
  ///   Collapsing those two would let "the model is not wired up here" read as
  ///   "this student is fine" (or, before, as "this student is stuck").
  /// * `targetKpIds` - **a product rule, not a model quantity** (no calibration
  ///   source exists for it): the caller's plan named these knowledge points,
  ///   so they lead. Passed through to [CognitiveModel.orderAdvisory]
  ///   unchanged; an empty set disables it. The review queue passes `const {}`.
  static ReviewOrdering order({
    required List<ReviewCandidate> candidates,
    required CognitiveModel model,
    required double nowHours,
    Map<String, double> boostFactorByKnowledgePoint = const {},
    Map<String, BottleneckType>? diagnosisByKnowledgePoint,
    Set<String> targetKpIds = const {},
  }) {
    final forced = <ReviewCandidate>[];
    final boosted = <ReviewCandidate>[];
    final modelBand = <ReviewCandidate>[];
    final unseen = <ReviewCandidate>[];

    for (final candidate in candidates) {
      if (candidate.row.forced == 1) {
        // Forced wins over everything else: it is bound by a wrong answer and
        // has to come back today whatever the model thinks.
        forced.add(candidate);
      } else if ((boostFactorByKnowledgePoint[candidate.knowledgePointId] ??
              1.0) >
          1.0) {
        boosted.add(candidate);
      } else if (candidate.isNew) {
        // Checked before the model band: a card with no history is not scored
        // (D4).
        unseen.add(candidate);
      } else {
        modelBand.add(candidate);
      }
    }

    // Boosted: factor descending, then deterministic. Not delegated to the
    // model - this band exists for a reason the model did not decide (D5).
    boosted.sort((a, b) {
      final factorA = boostFactorByKnowledgePoint[a.knowledgePointId] ?? 1.0;
      final factorB = boostFactorByKnowledgePoint[b.knowledgePointId] ?? 1.0;
      final byFactor = factorB.compareTo(factorA);
      if (byFactor != 0) {
        return byFactor;
      }
      final byKnowledgePoint = a.knowledgePointId.compareTo(b.knowledgePointId);
      if (byKnowledgePoint != 0) {
        return byKnowledgePoint;
      }
      return a.cardStateId.compareTo(b.cardStateId);
    });

    // Model band: the model's own total order, reached only through the seam.
    // Candidates are handed over as `AdvisorCandidate`s and matched back by
    // object identity, so a caller that passes the same row twice cannot have
    // its items merged by an id lookup.
    final handedOver = <AdvisorCandidate>[
      for (final candidate in modelBand)
        AdvisorCandidate(
          knowledgePointId: candidate.knowledgePointId,
          row: candidate.row,
        ),
    ];
    final back = Map<AdvisorCandidate, ReviewCandidate>.identity();
    for (var i = 0; i < handedOver.length; i++) {
      back[handedOver[i]] = modelBand[i];
    }
    final orderedModelBand = <ReviewCandidate>[
      for (final ordered in model.orderAdvisory(
        handedOver,
        nowHours: nowHours,
        targetKpIds: targetKpIds,
      ))
        back[ordered]!,
    ];

    // Unseen: deterministic, and deliberately *without* a model call. A brand
    // new card has no schedule, so `dueAt ?? 0` is a formality here that only
    // keeps the (rare) scheduled-without-history row from making the order
    // depend on input order - it is not the "overdue wins" rule of the model
    // band, which is `orderAdvisory`'s `null`-sorts-last convention.
    final sortedUnseen = [...unseen]..sort((a, b) {
        final byDueAt = (a.row.dueAt ?? 0).compareTo(b.row.dueAt ?? 0);
        if (byDueAt != 0) {
          return byDueAt;
        }
        final byKnowledgePoint =
            a.knowledgePointId.compareTo(b.knowledgePointId);
        if (byKnowledgePoint != 0) {
          return byKnowledgePoint;
        }
        return a.cardStateId.compareTo(b.cardStateId);
      });

    // Forced items keep the caller's order: their *placement* is
    // `_interleave`'s rule and depends on this order, so sorting here would
    // silently change which card comes back first.
    final ranked = <ReviewCandidate>[
      ...forced,
      ...boosted,
      ...orderedModelBand,
      ...sortedUnseen,
    ];

    final bandByCardStateId = <String, ReviewBand>{
      for (final candidate in forced)
        candidate.cardStateId: ReviewBand.forced,
      for (final candidate in boosted)
        candidate.cardStateId: ReviewBand.boosted,
      for (final candidate in orderedModelBand)
        candidate.cardStateId: ReviewBand.model,
      for (final candidate in sortedUnseen)
        candidate.cardStateId: ReviewBand.unseen,
    };

    final diagnosis = diagnosisByKnowledgePoint;
    final zoneByKnowledgePoint = <String, ReviewZone>{
      for (final candidate in ranked)
        candidate.knowledgePointId: diagnosis == null
            ? ReviewZone.unavailable
            : _zoneOf(diagnosis[candidate.knowledgePointId]),
    };

    return ReviewOrdering(
      ranked: ranked,
      bandByCardStateId: bandByCardStateId,
      zoneByKnowledgePoint: zoneByKnowledgePoint,
      scoreByCardStateId: {
        for (final candidate in orderedModelBand)
          candidate.cardStateId: model.expectedGain(
            candidate.row,
            nowHours: nowHours,
          ),
      },
    );
  }

  /// The fast layer's verdict for one knowledge point, or
  /// [ReviewZone.healthy] when the layer ran and produced no verdict.
  ///
  /// Only reached with a non-null diagnosis map: "no verdict" is a result
  /// ("nothing to report"), whereas "no diagnosis map" is [ReviewZone.unavailable].
  static ReviewZone _zoneOf(BottleneckType? type) =>
      type == null ? ReviewZone.healthy : zoneOf(type);

  /// Translates one verdict. **Exhaustive on purpose**: if the fast layer ever
  /// grows an eighth diagnosis, this switch stops compiling instead of silently
  /// reporting the old set. (Dart has no "unknown enum value" case to fall
  /// back on, so the compiler is the only guard available.)
  static ReviewZone zoneOf(BottleneckType type) => switch (type) {
        BottleneckType.weak => ReviewZone.proximal,
        BottleneckType.empty => ReviewZone.empty,
        BottleneckType.deadEnd => ReviewZone.deadEnd,
        BottleneckType.slow => ReviewZone.slow,
        BottleneckType.overload => ReviewZone.overload,
        BottleneckType.offGoal => ReviewZone.offGoal,
        BottleneckType.danger => ReviewZone.danger,
      };
}

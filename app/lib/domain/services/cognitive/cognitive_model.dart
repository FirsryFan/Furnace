/// The replaceable seam between Furnace's review flow and the cognitive model.
///
/// Furnace promised MindNet an abstract `CognitiveModel` so that adopting the
/// model cannot block either side (`docs/MINDNET_CONTRACT.md` §5), and the
/// review flow was written before the model existed. This file is that seam:
///
/// * **every reader goes through the interface.** The review ordering and the
///   question-quality evaluation are allowed to call [CognitiveModel] and
///   nothing else of the model; if they reach for `DsrMemory` directly there is
///   no longer a swappable implementation, only a convention.
/// * **read-only advisement.** Everything here derives numbers from a stored
///   row plus a moment in time and writes nothing. FSRS stays the authority on
///   `dueAt` and the model advises on ordering (decision D1); the *zone*
///   vocabulary ("发展区 / 死角 / 不可用") deliberately lives one layer up, in
///   the adapter that consumes the fast layer's bottleneck types, so this seam
///   never holds a second copy of it. The model owns exactly two columns
///   - `encoding_strength` / `savings` - which are written by a narrow
///   repository update that touches nothing else; the review flow deliberately
///   does **not** persist a review through `DsrCardState.write`, because that
///   companion also carries `stability` / `difficulty` / `dueAt`, and those
///   belong to FSRS (D2: one column, one writer).
/// * **no second copy of the algorithm.** Implementations delegate to the
///   tierA port. Re-deriving the curve here would create a second source of
///   truth for the same numbers, which is exactly what D2 forbids.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database.dart';
import '../srs/dsr_card_state.dart';
import '../srs/dsr_memory.dart';
import '../srs/fsrs_scheduler.dart';

/// What the rest of the app may ask the cognitive model.
///
/// The surface is small and read-only:
///
/// * two numbers per card - [retrievabilityOf] ("how well is it known right
///   now") and [expectedGain] ("what would reviewing it now be worth"), which
///   is the model's actual claim and the reason its ordering differs from "due
///   date ascending";
/// * [orderAdvisory], the same two numbers turned into a queue order;
/// * [modelReadingOf] / [modelStateAfterReview] for the model-owned columns
///   (`encoding_strength` / `savings`), so the write itself can stay a single
///   narrow database update outside this interface (D2).
abstract interface class CognitiveModel {
  /// Stable identifier of the implementation, for logs and for saying **where
  /// a number came from** in a read-only view. Never a user-facing string.
  String get id;

  /// The retrievability of [row] at [nowHours], in `[0, 1]`.
  ///
  /// [nowHours] is the model's clock - hours since the Unix epoch, `u` in
  /// MindNet - not a duration. Use [modelHoursOf] to convert a wall clock
  /// rather than dividing by 24 somewhere (§6.1's unit trap).
  double retrievabilityOf(CardState row, {required double nowHours});

  /// The multiplicative stability gain of one successful review of [row] at
  /// [nowHours]. Always `>= 1`; larger means reviewing now is worth more.
  ///
  /// [closeness] is forwarded to tierA unchanged. A successful review's gain
  /// does **not** depend on it: the model weights *how* the answer was produced
  /// (reread / retrieval / failure-feedback), not how close it was, and the
  /// grade only moves later gains (§6.2's semantic trap). The parameter exists
  /// because tierA's signature carries it and because the event that does use
  /// it must not be silently dropped if this seam ever grows an event argument.
  double expectedGain(
    CardState row, {
    required double nowHours,
    double closeness = 0.5,
  });

  /// Orders [candidates] the way the model says they should be reviewed.
  ///
  /// This is the advisor's whole output (D1: it advises; FSRS still owns
  /// `dueAt`). Every sort key is explicit - nothing here relies on
  /// `List.sort` being stable:
  ///
  /// 1. **candidates in [targetKpIds] lead.** This is a **product-layer rule,
  ///    not a model quantity, and it has no calibration source.** MindNet's own
  ///    goal bias is `β_goal·γ(distance)` inside the fast layer - a mechanism
  ///    tierA does not have - so inventing a `β` here would be fabricating an
  ///    uncalibrated parameter, which §6.7 explicitly refuses to do. So the
  ///    goal is honoured as a *tier* (the caller's plan asked for exactly those
  ///    knowledge points), the gain still decides inside each tier, and passing
  ///    `const {}` disables it entirely.
  /// 2. **score descending**, the score being [expectedGain] - a card you have
  ///    almost forgotten is worth more than one you still know.
  /// 3. **`dueAt` ascending**, so among equal scores the more overdue card goes
  ///    first. A row with no schedule (`dueAt == null`) sorts after every
  ///    scheduled row: it is the new/unscheduled case (D4 keeps those out of
  ///    this list), and treating "no date" as 1970 would silently promote it.
  /// 4. **knowledge point id ascending**, then **card state id ascending** -
  ///    one knowledge point can own several unit rows, so this is what makes
  ///    the order total rather than merely almost deterministic.
  ///
  /// Pure: no database, no clock, no IO. Same candidates (in any input order),
  /// same [nowHours], same [targetKpIds] - same sequence out.
  List<AdvisorCandidate> orderAdvisory(
    List<AdvisorCandidate> candidates, {
    required double nowHours,
    Set<String> targetKpIds = const {},
  });

  /// The model-owned columns of [row], plus the retrievability they imply.
  ///
  /// * `r0` is `encoding_strength` (MindNet's `R0`, the encoding ceiling).
  ///   **A NULL column is not 0**: on a row that carries FSRS memory it reads
  ///   as `1.0`, because "no recorded ceiling" means "no ceiling" - which is
  ///   also exactly what makes the model's curve identical to FSRS's.
  /// * `sigma` is `savings` (MindNet's `Σ`, the savings effect). A NULL column
  ///   reads as `0.8`, the model's documented default.
  /// * `r` is the derived retrievability `R0 * Psi(t / S)`. It is never stored,
  ///   so it cannot drift from the row it was derived from.
  ///
  /// One nuance worth knowing before writing anything back: a row with **no
  /// memory at all** (both `stability` and `difficulty` NULL) is a brand new
  /// card, and tierA starts it from its own defaults (`R0 = 0.8`, and a `Σ`
  /// equal to it) rather than from the 1.0/0.8 above. That branch belongs to
  /// `DsrCardState.read` and is pinned by its tests; this method reports what
  /// the model actually uses, which is the whole point of a reading interface.
  ///
  /// Both clock traps are tierA's and are inherited here: `nowHours` is
  /// **hours since the Unix epoch** (use [modelHoursOf]), and a row with no
  /// `lastReviewedAt` is treated as learned at **hour 0**, not "now" - reading
  /// it as brand new would keep `dt = 0` forever and compute nothing.
  ({double r0, double sigma, double r}) modelReadingOf(
    CardState row, {
    required double nowHours,
  });

  /// The values the model would put in `encoding_strength` / `savings` after
  /// one review - computed, **not written**.
  ///
  /// This is the pair a narrow `updateModelState(id, {encodingStrength,
  /// savings})` needs: the model owns exactly these two columns (D2), and one
  /// review event produces exactly these two numbers. `stability`,
  /// `difficulty` and `dueAt` stay FSRS's.
  ///
  /// [rating] is the review UI's 1..4 (`1` is a lapse), mapped to the model's
  /// event vocabulary by `DsrCardState.eventFor` so the two cannot drift
  /// apart. Nothing is persisted here and [row] is not mutated - the caller
  /// owns the write.
  ({double r0, double sigma}) modelStateAfterReview(
    CardState row, {
    required int rating,
    required double nowHours,
    bool reread = false,
    double closeness = 0.5,
  });
}

/// One review candidate as the advisor sees it: the stored card row plus the
/// knowledge point it belongs to.
///
/// **No zone here, on purpose.** The diagnosis vocabulary belongs to the
/// adapter layer that consumes the fast layer's bottleneck types (t3's
/// `review_advisory.dart`, whose `ReviewZone` is the app-facing answer with its
/// own explicit `unavailable`); a second "发展区/死角" enum on this side would
/// be a duplicate vocabulary and a reviewer's blocker. This seam stays a pair
/// of numbers per card plus the ordering they imply.
class AdvisorCandidate {
  const AdvisorCandidate({
    required this.knowledgePointId,
    required this.row,
  });

  /// The knowledge point this unit row belongs to (one point can own several
  /// unit rows, which is why [CognitiveModel.orderAdvisory] keeps breaking ties
  /// on the row id).
  final String knowledgePointId;

  /// The stored `card_states` row. Passed in, never fetched: the advisor must
  /// stay callable from a pure test with a closed database.
  final CardState row;

  /// The row id, spelled out for callers that order or log by it.
  String get cardStateId => row.id;
}

/// The one implementation of [CognitiveModel.orderAdvisory]'s rule.
///
/// Private and shared: the rule is a property of the model *interface*, not of
/// an implementation - the two implementations differ only in the two numbers
/// it reads. It is reachable only as `model.orderAdvisory(...)`, so there is no
/// second place a caller could pick a different ordering.
///
/// On the comparator: the keys in the interface doc make it a total order for
/// distinct rows, so no tie-break depends on the sort's stability. Two
/// candidates carrying the *same* row id are indistinguishable here and their
/// relative order is unobservable.
List<AdvisorCandidate> _orderAdvisory(
  CognitiveModel model,
  List<AdvisorCandidate> candidates, {
  required double nowHours,
  Set<String> targetKpIds = const {},
}) {
  final scored = <({AdvisorCandidate candidate, double gain, int dueAt, bool isTarget})>[
    for (final candidate in candidates)
      (
        candidate: candidate,
        gain: model.expectedGain(candidate.row, nowHours: nowHours),
        dueAt: candidate.row.dueAt ?? _unscheduledDueAt,
        isTarget: targetKpIds.contains(candidate.knowledgePointId),
      ),
  ]..sort((a, b) {
      if (a.isTarget != b.isTarget) {
        return a.isTarget ? -1 : 1;
      }
      final byScore = b.gain.compareTo(a.gain);
      if (byScore != 0) {
        return byScore;
      }
      final byDueAt = a.dueAt.compareTo(b.dueAt);
      if (byDueAt != 0) {
        return byDueAt;
      }
      final byKnowledgePoint =
          a.candidate.knowledgePointId.compareTo(b.candidate.knowledgePointId);
      if (byKnowledgePoint != 0) {
        return byKnowledgePoint;
      }
      return a.candidate.row.id.compareTo(b.candidate.row.id);
    });

  return [for (final entry in scored) entry.candidate];
}

/// Stand-in `dueAt` for a row that has none: larger than any epoch
/// millisecond, so "no schedule" sorts after every real due time instead of
/// being read as "overdue since 1970".
const int _unscheduledDueAt = 1 << 62;

/// Converts a wall clock into the model's clock: hours since the Unix epoch.
///
/// There is exactly one conversion in the system between "days stored in
/// `card_states`" and "hours the model works in", and §6.1 singles it out as
/// the easiest silent mistake: the curve constants are identical in both
/// systems, so a stray `* 24` does not crash - it just quietly schedules the
/// wrong interval. Call this instead of converting at each call site.
double modelHoursOf(DateTime moment) =>
    moment.millisecondsSinceEpoch / Duration.millisecondsPerHour;

/// The model-backed implementation: the tierA port, read-only.
///
/// It adds no arithmetic of its own - every call lands in `DsrCardState`, which
/// reads the same `card_states` row the review flow reads, so the model and the
/// scheduler can never disagree about a card (D2: one row, one memory state).
class MindNetCognitiveModel implements CognitiveModel {
  const MindNetCognitiveModel({this.params = const DsrParams()});

  /// MindNet's constants, passed rather than hard-coded at call sites (§6.6:
  /// default parameter values are the one thing allowed to change between
  /// MindNet versions), so a caller can drive the model from a vector's
  /// published numbers. The defaults are the snapshot's values; the tierA
  /// conformance test pins `gamma` (through `c`), `kappa`, `beta` and `eta`
  /// against the vectors' `A01` entry.
  final DsrParams params;

  @override
  String get id => 'mindnet-tierA';

  @override
  double retrievabilityOf(CardState row, {required double nowHours}) =>
      DsrCardState.retrievabilityOf(row, nowHours: nowHours, params: params);

  @override
  double expectedGain(
    CardState row, {
    required double nowHours,
    double closeness = 0.5,
  }) =>
      DsrCardState.expectedGain(
        row,
        nowHours: nowHours,
        closeness: closeness,
        params: params,
      );

  @override
  List<AdvisorCandidate> orderAdvisory(
    List<AdvisorCandidate> candidates, {
    required double nowHours,
    Set<String> targetKpIds = const {},
  }) =>
      _orderAdvisory(this, candidates,
          nowHours: nowHours, targetKpIds: targetKpIds);

  @override
  ({double r0, double sigma, double r}) modelReadingOf(
    CardState row, {
    required double nowHours,
  }) {
    // One read of the row, then the model's own curve - the same two calls the
    // review flow's writing path makes, so the reading cannot drift from it.
    final state = DsrCardState.read(row, params: params, nowHours: nowHours);
    return (
      r0: state.r0,
      sigma: state.sigma,
      r: DsrMemory.retrievability(state, nowHours, params).r,
    );
  }

  @override
  ({double r0, double sigma}) modelStateAfterReview(
    CardState row, {
    required int rating,
    required double nowHours,
    bool reread = false,
    double closeness = 0.5,
  }) {
    // The event grammar is `DsrCardState.eventFor`'s, not this file's: a rating
    // is mapped in one place so the review flow and the advisor cannot disagree
    // about what "困难" means. The event is applied to a local copy, which is
    // why these two numbers are by construction the ones `DsrCardState.write`
    // would store for the pair - and why nothing is written here.
    final state = DsrCardState.read(row, params: params, nowHours: nowHours);
    DsrMemory.applyReview(
      state,
      nowHours,
      DsrCardState.eventFor(
        rating: rating,
        reread: reread,
        closeness: closeness,
      ),
      params,
    );
    return (r0: state.r0, sigma: state.sigma);
  }
}

/// The placeholder used when the cognitive model must not be consulted (§5).
///
/// It is **not** the model and must never be presented as one: it is the FSRS
/// curve Furnace already had, read at the same moments, with FSRS's own
/// next-stability as the gain. Two things follow, and both are deliberate:
///
/// * it agrees with the model exactly where the model has no ceiling
///   (`R0 = 1`), because then both curves are the same function (§6.1/§8.1) -
///   which is what the boundary test pins;
/// * it disagrees wherever `R0 < 1`, and it has no `Sigma`, no event types and
///   no difficulty consequence, because those are the model's, not FSRS's.
///
/// The point of keeping it is that "the model is unavailable" has to have a
/// defined behaviour that is not silence.
class HeuristicCognitiveModel implements CognitiveModel {
  const HeuristicCognitiveModel({
    this.parameters = const FsrsParameters(),
    this.rating = FsrsRating.good,
  });

  final FsrsParameters parameters;

  /// The grade the hypothetical review is scored at. `good` is FSRS's own
  /// neutral grade and the one the review UI's "记得" maps to.
  final FsrsRating rating;

  /// A row with stability but no difficulty: the same neutral value
  /// `review_service.dart` passes to `FsrsScheduler` in the same situation.
  static const double fallbackDifficulty = 5.0;

  @override
  String get id => 'heuristic-fsrs';

  @override
  double retrievabilityOf(CardState row, {required double nowHours}) {
    final stability = row.stability;
    if (stability == null || stability <= 0) {
      // No FSRS memory yet: nothing has had time to decay. (The model-backed
      // implementation answers differently here: `DsrCardState.read` treats a
      // never-reviewed card as learned at the epoch, so its retrievability has
      // already decayed. That reading is tierA's documented behaviour with its
      // own test; a placeholder has no business imitating a quirk.)
      return 1.0;
    }
    return FsrsScheduler.forgettingCurve(
      w: FsrsScheduler.normalizeWeights(parameters.w),
      elapsedDays: _elapsedDays(row, nowHours),
      stability: stability,
    );
  }

  @override
  double expectedGain(
    CardState row, {
    required double nowHours,
    double closeness = 0.5,
  }) {
    final stability = row.stability;
    if (stability == null || stability <= 0) {
      // A card with no memory has no stability to multiply. It is not "worth
      // zero": the advisor simply has nothing to say, and new cards are kept in
      // their own group precisely so this number never decides their order
      // (decision D4).
      return 1.0;
    }
    final w = FsrsScheduler.normalizeWeights(parameters.w);
    final r = retrievabilityOf(row, nowHours: nowHours);
    return FsrsScheduler.nextRecallStability(
          w,
          row.difficulty ?? fallbackDifficulty,
          stability,
          r,
          rating,
        ) /
        stability;
  }

  @override
  List<AdvisorCandidate> orderAdvisory(
    List<AdvisorCandidate> candidates, {
    required double nowHours,
    Set<String> targetKpIds = const {},
  }) =>
      _orderAdvisory(this, candidates,
          nowHours: nowHours, targetKpIds: targetKpIds);

  /// The stored columns, read literally (D2: NULL is not 0), plus the FSRS
  /// curve's retrievability.
  ///
  /// ```text
  /// encoding_strength NULL -> 1.0   (no recorded ceiling means no ceiling)
  /// savings           NULL -> 0.8   (the model's documented default)
  /// ```
  ///
  /// A stored 0.0 is returned as 0.0: that is data, not absence. And this
  /// implementation keeps no `Σ` at all, so [modelReadingOf] reports what the
  /// row says rather than a number it maintains.
  @override
  ({double r0, double sigma, double r}) modelReadingOf(
    CardState row, {
    required double nowHours,
  }) =>
      (
        r0: row.encodingStrength ?? 1.0,
        sigma: row.savings ?? 0.8,
        r: retrievabilityOf(row, nowHours: nowHours),
      );

  /// The heuristic maintains no model state, so a review changes neither
  /// column: the stored values come back unchanged.
  ///
  /// That is the honest answer rather than a fabricated gain - and it means a
  /// narrow write of these two values is a no-op, not a corruption, if the app
  /// runs without the model.
  @override
  ({double r0, double sigma}) modelStateAfterReview(
    CardState row, {
    required int rating,
    required double nowHours,
    bool reread = false,
    double closeness = 0.5,
  }) =>
      (
        r0: row.encodingStrength ?? 1.0,
        sigma: row.savings ?? 0.8,
      );

  /// Days since the card's last review, sharing `DsrCardState`'s convention
  /// that "no review recorded" means **the epoch**, not "now" - otherwise the
  /// two implementations would disagree about when decay started, and the
  /// substitution of "now" would keep `dt = 0` forever.
  double _elapsedDays(CardState row, double nowHours) {
    final lastReviewHours =
        (row.lastReviewedAt ?? 0) / Duration.millisecondsPerHour;
    final elapsedHours = nowHours - lastReviewHours;
    return elapsedHours <= 0 ? 0 : elapsedHours / DsrCardState.hoursPerDay;
  }
}

/// The one place the app decides which model it runs.
///
/// Swapping the implementation - back to the heuristic, or to a future
/// MindNet-side process - is a provider override rather than an edit at every
/// call site:
///
/// ```dart
/// ProviderScope(
///   overrides: [
///     cognitiveModelProvider.overrideWithValue(const HeuristicCognitiveModel()),
///   ],
///   child: const FurnaceApp(),
/// )
/// ```
final cognitiveModelProvider = Provider<CognitiveModel>((ref) {
  return const MindNetCognitiveModel();
});

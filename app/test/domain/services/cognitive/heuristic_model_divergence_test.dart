import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/cognitive/cognitive_model.dart';
import 'package:furnace/domain/services/srs/fsrs_scheduler.dart';

/// Pins a **known divergence** between the two `CognitiveModel`
/// implementations, so that swapping them cannot silently change how the same
/// stored row reads.
///
/// The row in question carries `encoding_strength = 0` (a *legal* stored value,
/// a different fact from NULL) plus a normal FSRS memory:
///
/// * `MindNetCognitiveModel` reads the column as the encoding ceiling
///   (`r0 = encodingStrength ?? 1.0` in `DsrCardState.read`), so `R0 = 0` and
///   `R = 0 * Psi(t/S) = 0`.
/// * `HeuristicCognitiveModel` answers from FSRS's own curve and never reads
///   that column, so its answer is whatever the curve says - at `t = S` that is
///   the 0.9 fixed point MINDNET_CONTRACT §8.1 records.
///
/// This is **not** a bug and nothing in the model is to be "fixed": D6 requires
/// the port to stay bit-for-bit with the JS, and the JS reads `ms > 0 ? ms :
/// 0.8` at initialization and `R0 = encodingStrength ?? 1.0` on a stored row -
/// so `0` really does mean "no ceiling at all". The app's own write path cannot
/// produce it either: `updateModelState` treats `null` as "leave the column
/// alone" (it cannot clear a column back to NULL) and the model never computes
/// `r0 = 0` (a lapse does not touch `R0`, a success only raises it:
/// `dsr_memory.dart` L470-479 and L484-486). Such a value therefore implies an
/// external write or dirty migration data - which is exactly why the divergence
/// is pinned and read-only rather than guarded.
///
/// ## Why the assertions below are invariants, not the numbers 0.9 / 0.537
///
/// The FSRS curve's output is a *function of the clock and of `S`*, so
/// `expect(heuristic, 0.9)` would be a magic number that turns red the moment
/// anyone changes `nowHours` or `stability` - and then gets "fixed" by editing
/// the expected value, at which point the test proves nothing. The contract is
/// therefore stated as: **the heuristic is invariant under a change of
/// `encodingStrength`, and the model is not.** The measured values are recorded
/// in comments, cross-checked against the reviewer's t32 measurements:
///
/// ```
/// encoding_strength = 0     : model r0 = 0.0, r = 0.0 | heuristic r = 0.9
/// encoding_strength = NULL  : model r0 = 1.0, r = 0.9 | heuristic r = 0.9
/// stability+difficulty NULL : model r0 = 0.8, r = 0.537059510243242
/// ```
void main() {
  const mindnet = MindNetCognitiveModel();
  const heuristic = HeuristicCognitiveModel();

  /// The reviewer's fixed clock: `nowHours = 240`. With `S = 10 days` and no
  /// recorded review (`lastReviewedAt == null`, which tierA reads as "learned at
  /// the epoch", hour 0), the elapsed time is exactly `t = S`.
  const nowHours = 240.0;
  const stabilityDays = 10.0;

  CardState rowWithMemory({required double? encodingStrength}) => CardState(
        id: 'cs-divergence',
        knowledgePointId: 'kp-divergence',
        unitKey: 'essay',
        intervalDays: stabilityDays,
        ease: 2.5,
        repetitions: 3,
        lapses: 0,
        state: 'review',
        // NULL on purpose: the epoch convention, and a row the model has never
        // written to.
        lastReviewedAt: null,
        createdAt: 1,
        updatedAt: 1,
        stability: stabilityDays,
        difficulty: 5,
        encodingStrength: encodingStrength,
        // NULL savings, exactly as in the t32 measurement.
        savings: null,
        forced: 0,
        forcedStreak: 0,
      );

  CardState rowWithoutMemory() => const CardState(
        id: 'cs-no-memory',
        knowledgePointId: 'kp-no-memory',
        unitKey: 'essay',
        intervalDays: 0,
        ease: 2.5,
        repetitions: 0,
        lapses: 0,
        state: 'new',
        lastReviewedAt: null,
        createdAt: 1,
        updatedAt: 1,
        stability: null,
        difficulty: null,
        encodingStrength: null,
        savings: null,
        forced: 0,
        forcedStreak: 0,
      );

  double heuristicR(CardState row) =>
      heuristic.retrievabilityOf(row, nowHours: nowHours);

  double mindnetR(CardState row) =>
      mindnet.retrievabilityOf(row, nowHours: nowHours);

  group('the same row reads differently depending on the implementation', () {
    test('the model reads encoding_strength as the ceiling (1.0 -> 0.0)',
        () {
      final unset = rowWithMemory(encodingStrength: null);
      final zeroed = rowWithMemory(encodingStrength: 0);

      // NULL means "no recorded ceiling", i.e. no ceiling at all.
      expect(mindnet.modelReadingOf(unset, nowHours: nowHours).r0, 1.0);
      // 0 is a stored value, not "unset" - and it is read literally, so the
      // ceiling is 0 and every retrievability derived from it collapses.
      expect(mindnet.modelReadingOf(zeroed, nowHours: nowHours).r0, 0.0);
      expect(mindnetR(unset) > 0, isTrue);
      expect(mindnetR(zeroed), 0.0);
    });

    test('the heuristic never reads it: same answer for NULL and for 0', () {
      final unset = rowWithMemory(encodingStrength: null);
      final zeroed = rowWithMemory(encodingStrength: 0);

      expect(heuristicR(zeroed), closeTo(heuristicR(unset), 1e-15),
          reason: 'encoding_strength must not reach the FSRS-based read');
    });

    test('so switching implementations changes the reading of that row', () {
      final zeroed = rowWithMemory(encodingStrength: 0);

      final viaHeuristic = heuristicR(zeroed);
      final viaMindNet = mindnetR(zeroed);

      // The whole finding, with no magic number in it: the heuristic keeps
      // answering from the curve while the model answers 0. Measured at this
      // clock: 0.9 vs 0.0, i.e. the choice of implementation is worth ~90
      // percentage points on this row.
      expect(viaMindNet, 0.0);
      expect(viaHeuristic > viaMindNet, isTrue);
      expect(viaHeuristic, closeTo(heuristicR(rowWithMemory(encodingStrength: 1.0)), 1e-15));
    });

    test('the curve point above is the documented t = S identity', () {
      // Why 0.9 shows up: FSRS's curve returns exactly 0.9 at t = S regardless
      // of R0 (§8.1). Computed through the same API the heuristic uses, so this
      // is a property of the curve - not a hard-coded expectation.
      final w = FsrsScheduler.normalizeWeights(const FsrsParameters().w);
      final atStability = FsrsScheduler.forgettingCurve(
        w: w,
        elapsedDays: stabilityDays,
        stability: stabilityDays,
      );

      expect(atStability, closeTo(0.9, 1e-9));
      expect(heuristicR(rowWithMemory(encodingStrength: null)),
          closeTo(atStability, 1e-12),
          reason: 'with R0 = 1 the two curves are the same function (§6.1)');
    });

    test('a row with no memory at all starts from the model defaults', () {
      final fresh = rowWithoutMemory();

      // R0 defaults to 0.8 in tierA's initial branch (not 1.0, not 0): the
      // third row of the t32 table.
      expect(mindnet.modelReadingOf(fresh, nowHours: nowHours).r0, 0.8);
      final r = mindnetR(fresh);
      expect(r > 0 && r < 1, isTrue,
          reason: 'measured 0.537059510243242 at nowHours = 240');
    });
  });
}

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/cognitive/cognitive_graph.dart';
import 'package:furnace/domain/services/cognitive/cognitive_model.dart';
import 'package:furnace/domain/services/srs/dsr_card_state.dart';
import 'package:furnace/domain/services/srs/dsr_memory.dart';
import 'package:furnace/domain/services/srs/fsrs_scheduler.dart';

/// Tests for the `CognitiveModel` seam.
///
/// Two things are being defended here, and neither is arithmetic of its own:
///
/// 1. **the seam is swappable** - the app resolves one provider, and swapping
///    the implementation needs no call-site edit;
/// 2. **the boundary is where the model and the existing FSRS curve must agree**
///    - at `R0 = 1` both are the same function, and both give `R = 0.9` at
///    `t = S` (contract §6.1 and §8.1: `decayFactor` *is* `curveC`, so only the
///    day/hour unit converts). The test uses the shipped FSRS constants rather
///    than re-deriving them, so it would catch a drift in either side.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  /// Seeds a real `card_states` row, so the model is always reading a row the
  /// review flow could read - not a hand-made object.
  ///
  /// [kpId] / [stateId] default to the single-card fixture the earlier tests
  /// use; the advisory tests need several rows, and one knowledge point can own
  /// more than one unit row, so both are parameters.
  Future<CardState> seedCard({
    String kpId = 'kp1',
    String stateId = 'cs1',
    double? stability,
    double? difficulty,
    double? encodingStrength,
    double? savings,
    int? lastReviewedAt,
    int? dueAt,
    int repetitions = 0,
  }) async {
    await db.into(db.knowledgePoints).insert(
          KnowledgePointsCompanion.insert(
            id: kpId,
            title: '动量守恒',
            content: '动量守恒定律',
            createdAt: 1,
            updatedAt: 1,
          ),
          mode: InsertMode.insertOrIgnore,
        );
    await db.into(db.cardTemplates).insert(
          CardTemplatesCompanion.insert(
            id: 'ct-$stateId',
            knowledgePointId: kpId,
            type: 'basic',
            question: '动量守恒的条件是什么？',
            answer: '合外力为零',
            createdAt: 1,
            updatedAt: 1,
          ),
          mode: InsertMode.insertOrIgnore,
        );
    await db.into(db.cardStates).insert(
          CardStatesCompanion.insert(
            id: stateId,
            cardTemplateId: Value('ct-$stateId'),
            knowledgePointId: Value(kpId),
            stability: Value(stability),
            difficulty: Value(difficulty),
            encodingStrength: Value(encodingStrength),
            savings: Value(savings),
            lastReviewedAt: Value(lastReviewedAt),
            dueAt: Value(dueAt),
            repetitions: Value(repetitions),
            createdAt: 1,
            updatedAt: 1,
          ),
        );
    return (await (db.select(db.cardStates)..where((t) => t.id.equals(stateId)))
        .getSingle());
  }

  /// Hours-since-epoch of a whole hour, so `nowHours` stays exact.
  int hours(int h) => h * Duration.millisecondsPerHour;

  group('the seam', () {
    test('the app runs the model-backed implementation by default', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final model = container.read(cognitiveModelProvider);
      expect(model, isA<MindNetCognitiveModel>());
      expect(model.id, 'mindnet-tierA');
    });

    test('the implementation is swapped by an override, not by call sites',
        () {
      final container = ProviderContainer(
        overrides: [
          cognitiveModelProvider
              .overrideWithValue(const HeuristicCognitiveModel()),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(cognitiveModelProvider).id, 'heuristic-fsrs');
    });

    test('both implementations satisfy the interface', () {
      expect(const MindNetCognitiveModel(), isA<CognitiveModel>());
      expect(const HeuristicCognitiveModel(), isA<CognitiveModel>());
    });
  });

  group('the clock', () {
    test('modelHoursOf is hours since the epoch, not days', () {
      expect(modelHoursOf(DateTime.fromMillisecondsSinceEpoch(0)), 0);
      expect(modelHoursOf(DateTime.fromMillisecondsSinceEpoch(3600000)), 1.0);
      expect(
          modelHoursOf(DateTime.fromMillisecondsSinceEpoch(86400000)), 24.0);
    });
  });

  group('R0 = 1 is the boundary where the model is the FSRS curve', () {
    test('both give 0.9 at t = S, and so does the shipped FSRS constant',
        () async {
      const stabilityDays = 10.0;
      const lastReviewHour = 10;
      const nowHours = lastReviewHour + stabilityDays * 24; // t = S exactly

      // The FSRS side, from the existing scheduler's own constants (w[20] is
      // the decay): no re-derivation here on purpose.
      const fsrs = FsrsParameters();
      final w = FsrsScheduler.normalizeWeights(fsrs.w);
      expect(
        FsrsScheduler.forgettingCurve(
            w: w, elapsedDays: stabilityDays, stability: stabilityDays),
        0.9,
        reason: 'the curve returns exactly 0.9 at t = S by construction',
      );

      final row = await seedCard(
        stability: stabilityDays,
        difficulty: 5,
        lastReviewedAt: hours(lastReviewHour),
      );
      expect(DsrCardState.read(row, nowHours: nowHours.toDouble()).r0, 1.0,
          reason: 'no recorded ceiling means R0 = 1, which is the case the '
              'contract says makes the two curves identical');

      final now = nowHours.toDouble();
      final modelR =
          const MindNetCognitiveModel().retrievabilityOf(row, nowHours: now);
      expect(modelR, closeTo(0.9, 1e-12));
      expect(DsrMemory.round6(modelR), 0.9,
          reason: 'and it is 0.9 under the published 6-decimal convention too');

      expect(
          const HeuristicCognitiveModel()
              .retrievabilityOf(row, nowHours: now),
          0.9);
    });

    test('with a ceiling below 1 the two part company, as 8.1 predicts',
        () async {
      const stabilityDays = 10.0;
      const lastReviewHour = 10;
      final now = (lastReviewHour + stabilityDays * 24).toDouble();

      final row = await seedCard(
        stability: stabilityDays,
        difficulty: 5,
        encodingStrength: 0.5,
        lastReviewedAt: hours(lastReviewHour),
      );

      final modelR =
          const MindNetCognitiveModel().retrievabilityOf(row, nowHours: now);
      expect(modelR, closeTo(0.45, 1e-12),
          reason: 'R = R0 * Psi(t/S) = 0.5 * 0.9 at t = S');
      // The FSRS curve is absolute: it has no ceiling to apply, so the
      // heuristic reads the same card as twice as retrievable. This is the
      // "not just a x24 conversion" gap from contract 8.1, pinned.
      expect(const HeuristicCognitiveModel().retrievabilityOf(row, nowHours: now),
          0.9);
    });
  });

  group('the model adds no arithmetic of its own', () {
    test('it delegates to tierA, value for value', () async {
      final row = await seedCard(
        stability: 10,
        difficulty: 6,
        encodingStrength: 0.8,
        savings: 0.4,
        lastReviewedAt: hours(5),
      );
      const now = 300.0;
      const model = MindNetCognitiveModel();

      expect(model.retrievabilityOf(row, nowHours: now),
          DsrCardState.retrievabilityOf(row, nowHours: now));
      expect(
        model.expectedGain(row, nowHours: now),
        DsrCardState.expectedGain(row, nowHours: now),
      );
    });

    test('the params object is what drives the model, not a hidden default',
        () async {
      final row = await seedCard(
        stability: 10,
        difficulty: 5,
        lastReviewedAt: hours(5),
      );
      const now = 300.0;
      final shipped = const MindNetCognitiveModel()
          .retrievabilityOf(row, nowHours: now);
      final slowerDecay = const MindNetCognitiveModel(
        params: DsrParams(gamma: 0.05),
      ).retrievabilityOf(row, nowHours: now);

      expect(slowerDecay, greaterThan(shipped),
          reason: 'a smaller gamma forgets more slowly; the constants are '
              'injected rather than baked into the call site (6.6)');
    });
  });

  group('what the two numbers mean for ordering', () {
    test('a forgotten card gains more than a fresh one, both ways', () async {
      final row = await seedCard(
        stability: 10,
        difficulty: 5,
        encodingStrength: 1,
        lastReviewedAt: hours(10),
      );
      const model = MindNetCognitiveModel();
      const heuristic = HeuristicCognitiveModel();

      const overdue = 10 + 10 * 24 * 3.0;
      const fresh = 10 + 1.0;

      expect(model.expectedGain(row, nowHours: overdue),
          greaterThan(model.expectedGain(row, nowHours: fresh)));
      expect(heuristic.expectedGain(row, nowHours: overdue),
          greaterThan(heuristic.expectedGain(row, nowHours: fresh)));
      expect(model.expectedGain(row, nowHours: overdue), greaterThanOrEqualTo(1));
    });

    test('closeness does not move a successful review\'s gain', () async {
      // Pinned so nobody "fixes" it into a fudge factor: in the model the
      // *type* of the review decides the immediate gain, and closeness only
      // matters for retrieval-failure-feedback (6.2).
      final row = await seedCard(
        stability: 10,
        difficulty: 5,
        lastReviewedAt: hours(5),
      );
      const model = MindNetCognitiveModel();
      expect(model.expectedGain(row, nowHours: 300, closeness: 0.1),
          model.expectedGain(row, nowHours: 300, closeness: 0.9));
    });

    test('the heuristic has nothing to say about a card with no memory',
        () async {
      // No stability yet: FSRS has no memory for it. The heuristic says so
      // (R = 1, gain = 1) instead of inventing a decay; new cards are kept in
      // their own group so this number never decides their order (D4).
      final row = await seedCard();
      const heuristic = HeuristicCognitiveModel();
      expect(heuristic.retrievabilityOf(row, nowHours: 100000), 1.0);
      expect(heuristic.expectedGain(row, nowHours: 100000), 1.0);
    });

    test('the heuristic uses the FSRS curve on real FSRS inputs', () async {
      final row = await seedCard(
        stability: 20,
        difficulty: 5,
        lastReviewedAt: hours(10),
      );
      const heuristic = HeuristicCognitiveModel();
      final w = FsrsScheduler.normalizeWeights(const FsrsParameters().w);

      expect(
        heuristic.retrievabilityOf(row, nowHours: 10 + 5 * 24.0),
        FsrsScheduler.forgettingCurve(w: w, elapsedDays: 5, stability: 20),
      );
    });
  });

  group('the advisory order', () {
    const model = MindNetCognitiveModel();

    /// The knowledge-point ids in the order the advisor put them.
    List<String> orderOf(List<AdvisorCandidate> ordered) =>
        [for (final candidate in ordered) candidate.knowledgePointId];

    test('is a pure function: same candidates in, same order out', () async {
      final a = await seedCard(
        kpId: 'kp-a',
        stateId: 'cs-a',
        stability: 10,
        difficulty: 5,
        lastReviewedAt: hours(5),
        dueAt: 1000,
      );
      final b = await seedCard(
        kpId: 'kp-b',
        stateId: 'cs-b',
        stability: 2,
        difficulty: 5,
        lastReviewedAt: hours(5),
        dueAt: 500,
      );
      final c = await seedCard(
        kpId: 'kp-c',
        stateId: 'cs-c',
        stability: 40,
        difficulty: 5,
        lastReviewedAt: hours(5),
        dueAt: 2000,
      );

      List<AdvisorCandidate> candidates(List<CardState> rows) => [
            for (final row in rows)
              AdvisorCandidate(
                knowledgePointId: row.knowledgePointId!,
                row: row,
              ),
          ];

      final first = model.orderAdvisory(candidates([a, b, c]), nowHours: 300);
      final second = model.orderAdvisory(candidates([a, b, c]), nowHours: 300);
      final shuffled =
          model.orderAdvisory(candidates([c, a, b]), nowHours: 300);

      expect(orderOf(second), orderOf(first));
      expect(orderOf(shuffled), orderOf(first),
          reason: 'the result is a function of the candidate set, not of the '
              'order the caller happened to collect them in');
    });

    test('runs with the database closed', () async {
      // The strongest available proof that ordering touches no storage: the
      // rows are read into memory, the database is closed, and ordering still
      // works. A repository call anywhere in the path would fail here.
      final isolated = AppDatabase.forTesting(NativeDatabase.memory());
      await isolated.into(isolated.knowledgePoints).insert(
            KnowledgePointsCompanion.insert(
              id: 'kp-iso',
              title: 't',
              content: 'c',
              createdAt: 1,
              updatedAt: 1,
            ),
          );
      await isolated.into(isolated.cardTemplates).insert(
            CardTemplatesCompanion.insert(
              id: 'ct-iso',
              knowledgePointId: 'kp-iso',
              type: 'basic',
              question: 'q',
              answer: 'a',
              createdAt: 1,
              updatedAt: 1,
            ),
          );
      await isolated.into(isolated.cardStates).insert(
            CardStatesCompanion.insert(
              id: 'cs-iso',
              cardTemplateId: const Value('ct-iso'),
              knowledgePointId: const Value('kp-iso'),
              stability: const Value(10),
              difficulty: const Value(5),
              lastReviewedAt: Value(hours(5)),
              createdAt: 1,
              updatedAt: 1,
            ),
          );
      final row = await (isolated.select(isolated.cardStates)
            ..where((t) => t.id.equals('cs-iso')))
          .getSingle();
      await isolated.close();

      final ordered = model.orderAdvisory(
        [AdvisorCandidate(knowledgePointId: 'kp-iso', row: row)],
        nowHours: 300,
      );
      expect(ordered.single.row.id, 'cs-iso');
    });

    test('the higher gain leads, and the most overdue among equals', () async {
      // Same stability, same clock, different due dates -> identical gains, so
      // this is exactly the dueAt tie-break.
      final later = await seedCard(
        kpId: 'kp-1',
        stateId: 'cs-later',
        stability: 10,
        difficulty: 5,
        lastReviewedAt: hours(5),
        dueAt: 900,
      );
      final sooner = await seedCard(
        kpId: 'kp-1',
        stateId: 'cs-sooner',
        stability: 10,
        difficulty: 5,
        lastReviewedAt: hours(5),
        dueAt: 100,
      );

      final ordered = model.orderAdvisory(
        [
          AdvisorCandidate(knowledgePointId: 'kp-1', row: later),
          AdvisorCandidate(knowledgePointId: 'kp-1', row: sooner),
        ],
        nowHours: 300,
      );
      expect([for (final c in ordered) c.row.id], ['cs-sooner', 'cs-later']);
    });

    test('ties fall through dueAt, then knowledge point id, then row id',
        () async {
      // All three rows are identical to the model (same memory, same clock,
      // same due date), so only the explicit tie-break keys can decide the
      // order.
      final b = await seedCard(
        kpId: 'kp-b',
        stateId: 'cs-b',
        stability: 10,
        difficulty: 5,
        lastReviewedAt: hours(5),
        dueAt: 700,
      );
      final a2 = await seedCard(
        kpId: 'kp-a',
        stateId: 'cs-z',
        stability: 10,
        difficulty: 5,
        lastReviewedAt: hours(5),
        dueAt: 700,
      );
      final a1 = await seedCard(
        kpId: 'kp-a',
        stateId: 'cs-a',
        stability: 10,
        difficulty: 5,
        lastReviewedAt: hours(5),
        dueAt: 700,
      );

      final ordered = model.orderAdvisory(
        [
          AdvisorCandidate(knowledgePointId: 'kp-b', row: b),
          AdvisorCandidate(knowledgePointId: 'kp-a', row: a2),
          AdvisorCandidate(knowledgePointId: 'kp-a', row: a1),
        ],
        nowHours: 300,
      );
      expect([for (final c in ordered) c.row.id], ['cs-a', 'cs-z', 'cs-b'],
          reason: 'kp-a before kp-b by knowledge point id, and inside kp-a the '
              'row id decides - the reason the order is total');
    });

    test('a row with no schedule sorts after scheduled rows it ties with',
        () async {
      final scheduled = await seedCard(
        kpId: 'kp-1',
        stateId: 'cs-scheduled',
        stability: 10,
        difficulty: 5,
        lastReviewedAt: hours(5),
        dueAt: 2000000000000,
      );
      final unscheduled = await seedCard(
        kpId: 'kp-1',
        stateId: 'cs-unscheduled',
        stability: 10,
        difficulty: 5,
        lastReviewedAt: hours(5),
      );
      expect(unscheduled.dueAt, isNull);

      final ordered = model.orderAdvisory(
        [
          AdvisorCandidate(knowledgePointId: 'kp-1', row: unscheduled),
          AdvisorCandidate(knowledgePointId: 'kp-1', row: scheduled),
        ],
        nowHours: 300,
      );
      expect(
          [for (final c in ordered) c.row.id], ['cs-scheduled', 'cs-unscheduled'],
          reason: '"no due date" is the unscheduled case, not "overdue since '
              '1970"; D4 keeps new cards out of this list anyway');
    });

    test('targets lead, and an empty target set is the plain score order',
        () async {
      final overdue = await seedCard(
        kpId: 'kp-overdue',
        stateId: 'cs-overdue',
        stability: 2,
        difficulty: 5,
        lastReviewedAt: hours(5),
        dueAt: 100,
      );
      final fresh = await seedCard(
        kpId: 'kp-fresh',
        stateId: 'cs-fresh',
        stability: 60,
        difficulty: 5,
        lastReviewedAt: hours(5),
        dueAt: 100,
      );

      List<AdvisorCandidate> candidates() => [
            AdvisorCandidate(knowledgePointId: 'kp-overdue', row: overdue),
            AdvisorCandidate(knowledgePointId: 'kp-fresh', row: fresh),
          ];

      expect(
        orderOf(model.orderAdvisory(candidates(), nowHours: 300)),
        ['kp-overdue', 'kp-fresh'],
        reason: 'the model says reviewing the almost forgotten card is worth '
            'more',
      );
      expect(
        orderOf(model.orderAdvisory(
          candidates(),
          nowHours: 300,
          targetKpIds: const {'kp-fresh'},
        )),
        ['kp-fresh', 'kp-overdue'],
        reason: 'the plan asked for kp-fresh, so it leads its tier; the gain '
            'still decides inside a tier and the tie-break chain is unchanged. '
            'This is a product-layer rule, not a model quantity: MindNet\'s own '
            'goal bias is beta_goal*gamma(distance) inside the fast layer, which '
            'tierA does not have, so a weak target beating a strong non-target '
            'is the tier and never a calibrated bonus',
      );
    });

    test('a candidate carries no zone vocabulary of its own', () async {
      // The zone enum was withdrawn from this seam (队长 C 项撤回): the
      // vocabulary belongs to the adapter that consumes tierB's bottleneck
      // types, so there is exactly one of them in the app. What stays here is
      // the pair of numbers and the order - and an advisor that never throws
      // for a card the fast layer has nothing to say about.
      final row = await seedCard(
        stability: 10,
        difficulty: 5,
        lastReviewedAt: hours(5),
      );
      final ordered = model.orderAdvisory(
        [AdvisorCandidate(knowledgePointId: 'kp1', row: row)],
        nowHours: 300,
      );
      expect(ordered.single.cardStateId, 'cs1');
      expect(ordered.single.knowledgePointId, 'kp1');
    });

    test('the heuristic orders the same way without blowing up', () async {
      final row = await seedCard(
        stability: 10,
        difficulty: 5,
        lastReviewedAt: hours(5),
      );
      const heuristic = HeuristicCognitiveModel();
      final ordered = heuristic.orderAdvisory(
        [AdvisorCandidate(knowledgePointId: 'kp1', row: row)],
        nowHours: 300,
        targetKpIds: const {'kp1'},
      );
      expect(ordered.single.knowledgePointId, 'kp1');
    });

    test('an empty list is fine', () {
      expect(model.orderAdvisory(const [], nowHours: 0), isEmpty);
    });
  });

  group('the model-owned columns', () {
    const model = MindNetCognitiveModel();

    test('NULL reads as 1.0 / 0.8 when the row has FSRS memory', () async {
      final row = await seedCard(
        stability: 10,
        difficulty: 5,
        lastReviewedAt: hours(5),
      );
      final reading = model.modelReadingOf(row, nowHours: 300);
      expect(reading.r0, 1.0,
          reason: 'no recorded ceiling means no ceiling - and it is never 0, '
              'which would be "nothing is retrievable at all"');
      expect(reading.sigma, 0.8,
          reason: 'the model default, again not 0');
    });

    test('stored columns are read back, and a stored 0.0 is data', () async {
      final row = await seedCard(
        stability: 10,
        difficulty: 5,
        encodingStrength: 0.5,
        savings: 0.0,
        lastReviewedAt: hours(5),
      );
      final reading = model.modelReadingOf(row, nowHours: 300);
      expect(reading.r0, 0.5);
      expect(reading.sigma, 0.0);
    });

    test('a brand-new row starts from tierA\'s own defaults', () async {
      // Pinned so the 1.0/0.8 branch above is not over-generalised: with no
      // memory at all, `DsrCardState.read` initialises the state (R0 = 0.8,
      // and Sigma equal to it). That is tierA's documented behaviour, and this
      // interface reports what the model actually uses.
      final row = await seedCard();
      final reading = model.modelReadingOf(row, nowHours: 100);
      expect(reading.r0, 0.8);
      expect(reading.sigma, 0.8);
    });

    test('r is the same number retrievabilityOf returns', () async {
      final row = await seedCard(
        stability: 10,
        difficulty: 5,
        encodingStrength: 0.9,
        savings: 0.3,
        lastReviewedAt: hours(5),
      );
      expect(model.modelReadingOf(row, nowHours: 300).r,
          model.retrievabilityOf(row, nowHours: 300));
    });

    test('the reading inherits the epoch convention', () async {
      // `lastReviewedAt` NULL means "learned at hour 0", not "learned now": if
      // it meant "now", dt would be 0 for ever and the model would compute
      // nothing at all.
      final row = await seedCard(stability: 5, difficulty: 5);
      expect(model.modelReadingOf(row, nowHours: 100000).r, lessThan(0.9));
    });

    test('a successful review raises R0 and the savings', () async {
      final row = await seedCard(
        stability: 10,
        difficulty: 5,
        encodingStrength: 0.8,
        lastReviewedAt: hours(5),
      );
      final before = model.modelReadingOf(row, nowHours: 300);
      final after =
          model.modelStateAfterReview(row, rating: 3, nowHours: 300);
      expect(after.r0, greaterThan(before.r0),
          reason: 'R0 grows towards its ceiling (0.8 -> 0.81); at 1.0 it is '
              'already capped, which is why this seeds a lower ceiling');
      expect(after.sigma, greaterThan(before.sigma));
    });

    test('a lapse keeps R0 and still grows the savings', () async {
      final row = await seedCard(
        stability: 40,
        difficulty: 5,
        encodingStrength: 0.8,
        lastReviewedAt: hours(5),
      );
      final before = model.modelReadingOf(row, nowHours: 300);
      final after = model.modelStateAfterReview(row, rating: 1, nowHours: 300);
      expect(after.r0, before.r0,
          reason: 'R0 only grows on a successful retrieval');
      expect(after.sigma, greaterThan(before.sigma),
          reason: 'the effort was real, so the savings effect grows even on a '
              'lapse');
    });

    test('the computed pair is exactly what the tierA write path stores',
        () async {
      final row = await seedCard(
        stability: 10,
        difficulty: 5,
        savings: 0.4,
        lastReviewedAt: hours(5),
      );
      final mine = model.modelStateAfterReview(row, rating: 3, nowHours: 300);
      final written = DsrCardState.applyReview(
        row,
        rating: 3,
        nowHours: 300,
        targetRetention: 0.9,
      ).update;

      expect(mine.r0, written.encodingStrength.value);
      expect(mine.sigma, written.savings.value,
          reason: 'the advisor computes the same two numbers the write path '
              'would store, so a narrow write of them cannot disagree with '
              'tierA');
    });

    test('computing the pair writes nothing', () async {
      final row = await seedCard(
        stability: 10,
        difficulty: 5,
        lastReviewedAt: hours(5),
      );
      model.modelStateAfterReview(row, rating: 3, nowHours: 300);
      final stored =
          await (db.select(db.cardStates)..where((t) => t.id.equals('cs1')))
              .getSingle();
      expect(stored.stability, 10);
      expect(stored.encodingStrength, isNull,
          reason: 'the caller owns the write (D2: one narrow update outside '
              'this interface)');
      expect(stored.lastReviewedAt, hours(5));
    });

    test('the heuristic keeps no model state, so a write is a no-op', () async {
      final row = await seedCard(
        stability: 10,
        difficulty: 5,
        encodingStrength: 0.6,
        savings: 0.2,
        lastReviewedAt: hours(5),
      );
      const heuristic = HeuristicCognitiveModel();
      final reading = heuristic.modelReadingOf(row, nowHours: 300);
      expect(reading.r0, 0.6);
      expect(reading.sigma, 0.2);
      expect(reading.r,
          heuristic.retrievabilityOf(row, nowHours: 300));

      final after =
          heuristic.modelStateAfterReview(row, rating: 4, nowHours: 300);
      expect(after.r0, 0.6);
      expect(after.sigma, 0.2,
          reason: 'the placeholder has no R0/Sigma dynamics; writing these '
              'values back leaves the row as it was instead of fabricating '
              'progress');
    });

    test('the heuristic reads NULL columns as 1.0 / 0.8, never 0', () async {
      final row = await seedCard(
        stability: 10,
        difficulty: 5,
        lastReviewedAt: hours(5),
      );
      final reading =
          const HeuristicCognitiveModel().modelReadingOf(row, nowHours: 300);
      expect(reading.r0, 1.0);
      expect(reading.sigma, 0.8);
    });
  });

  group('the projection and the review flow agree on R0', () {
    const model = MindNetCognitiveModel();

    test('a NULL ceiling with a known stability reaches the graph as 1.0',
        () async {
      // The A2 acceptance. One card, two paths:
      //  (1) the review flow's own reading of the row: D2 says a known
      //      stability plus a NULL `encoding_strength` is R0 = 1.0;
      //  (2) the graph the app projects for MindNet, which reads a node's `ms`
      //      as its initial R0 (mechanisms/memory.dsr.js:90), and falls back to
      //      0.8 on its own when the key is missing (src/model.js:50).
      // If (2) were omitted or defaulted, the same card would carry two
      // different encoding ceilings - this test fails on that divergence.
      final row = await seedCard(
        stability: 10,
        difficulty: 5,
        lastReviewedAt: hours(5),
      );
      expect(row.encodingStrength, isNull,
          reason: 'the fixture has to be the ambiguous row for this to mean '
              'anything');
      expect(DsrCardState.read(row, nowHours: 300).r0, 1.0);

      final ms = model.modelReadingOf(row, nowHours: 300).r0;
      final graph = CognitiveGraph.fromTags(
        tags: const [CognitiveTag(id: 'kp1', name: '动量守恒', path: '动量守恒')],
        ms: {'kp1': ms},
      );

      expect(graph.nodesWithoutMs, isEmpty);
      final emitted = (graph.toJson()['nodes']! as List).single
          as Map<String, Object?>;
      expect(emitted['ms'], 1.0,
          reason: 'not absent (which MindNet would read as 0.8) and not 0.8');
      expect(emitted['ms'], DsrCardState.read(row, nowHours: 300).r0,
          reason: 'the two paths must produce the same ceiling for the same '
              'card (D2)');
    });

    test('the same row with no ms says so instead of claiming 0.8', () async {
      final row = await seedCard(
        stability: 10,
        difficulty: 5,
        lastReviewedAt: hours(5),
      );
      expect(model.modelReadingOf(row, nowHours: 300).r0, 1.0,
          reason: 'the reading is available - the graph below simply was not '
              'given it, and says so instead of guessing');

      final graph = CognitiveGraph.fromTags(
        tags: const [CognitiveTag(id: 'kp1', name: '动量守恒', path: '动量守恒')],
        ms: const {},
      );

      expect(graph.nodeById('kp1')!.ms, isNull);
      expect(graph.nodesWithoutMs, ['kp1'],
          reason: 'the gap is reported, so MindNet\'s own 0.8 substitution '
              'cannot be mistaken for a number Furnace computed');
    });

    test('a stored ceiling reaches the graph unchanged', () async {
      final row = await seedCard(
        stability: 10,
        difficulty: 5,
        encodingStrength: 0.4,
        lastReviewedAt: hours(5),
      );
      final ms = model.modelReadingOf(row, nowHours: 300).r0;
      expect(ms, 0.4);
      final graph = CognitiveGraph.fromTags(
        tags: const [CognitiveTag(id: 'kp1', name: '动量守恒', path: '动量守恒')],
        ms: {'kp1': ms},
      );
      expect((graph.toJson()['nodes']! as List).single,
          containsPair('ms', 0.4));
    });

    test('one card reads 1.0 on all three paths: row, reading, projected node',
        () async {
      // The A2 acceptance in one place, and it fails if any path diverges:
      //  (1) the review flow's reading of the row - D2 says a known stability
      //      with a NULL encoding_strength is R0 = 1.0;
      //  (2) the model's own reading interface, which must agree;
      //  (3) the node the graph actually carries, which must hold that same
      //      number - 0.8 would mean MindNet's own default leaked in
      //      (src/model.js:50) and absence would let it do so at runtime.
      final row = await seedCard(
        stability: 10,
        difficulty: 5,
        lastReviewedAt: hours(5),
      );
      expect(row.encodingStrength, isNull);

      final fromRow = DsrCardState.read(row, nowHours: 300).r0;
      final fromReading = model.modelReadingOf(row, nowHours: 300).r0;
      final graph = CognitiveGraph.fromTags(
        tags: const [CognitiveTag(id: 'kp1', name: '动量守恒', path: '动量守恒')],
        ms: {'kp1': fromReading},
      );
      final onNode = graph.nodeById('kp1')!.ms;

      expect(fromRow, 1.0);
      expect(fromReading, fromRow,
          reason: 'the reading interface may not disagree with the row');
      expect(onNode, fromRow,
          reason: 'the projected node carries the same ceiling, not MindNet\'s '
              'unmeasured 0.8 and not nothing');
      expect(graph.nodesWithoutMs, isEmpty);
      expect((graph.toJson()['nodes']! as List).single,
          containsPair('ms', 1.0));
    });
  });
}

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/srs/dsr_card_state.dart';
import 'package:furnace/domain/services/srs/dsr_memory.dart';

/// The integration claim being tested: adopting the cognitive model adds **no**
/// second source of truth. One card has one memory state, stored in the columns
/// that already existed, and both the legacy review flow and the model read and
/// write that same row.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  /// Inserts a knowledge point + template + card state so a real row exists.
  Future<CardState> seedCard({
    double? stability,
    double? difficulty,
    double? encodingStrength,
    double? savings,
    int? lastReviewedAt,
    int repetitions = 0,
  }) async {
    await db.into(db.knowledgePoints).insert(
          KnowledgePointsCompanion.insert(
            id: 'kp1',
            title: '动量守恒',
            content: '动量守恒定律',
            createdAt: 1,
            updatedAt: 1,
          ),
        );
    await db.into(db.cardTemplates).insert(
          CardTemplatesCompanion.insert(
            id: 'ct1',
            knowledgePointId: 'kp1',
            type: 'basic',
            question: '动量守恒的条件是什么？',
            answer: '合外力为零',
            createdAt: 1,
            updatedAt: 1,
          ),
        );
    await db.into(db.cardStates).insert(
          CardStatesCompanion.insert(
            id: 'cs1',
            cardTemplateId: const Value('ct1'),
            knowledgePointId: const Value('kp1'),
            stability: Value(stability),
            difficulty: Value(difficulty),
            encodingStrength: Value(encodingStrength),
            savings: Value(savings),
            lastReviewedAt: Value(lastReviewedAt),
            repetitions: Value(repetitions),
            createdAt: 1,
            updatedAt: 1,
          ),
        );
    return (await (db.select(db.cardStates)..where((t) => t.id.equals('cs1')))
        .getSingle());
  }

  group('reading a stored row', () {
    test('a brand-new row starts from the model defaults', () async {
      final row = await seedCard();
      final state = DsrCardState.read(row, nowHours: 100);
      // R0 defaults to 0.8 and S to legacy_k * R0 (24 * 0.8 = 19.2 hours).
      expect(state.r0, 0.8);
      expect(state.s, closeTo(19.2, 1e-9));
      expect(state.d, 5.1618);
      expect(state.lastReview, 0,
          reason: 'a card with no review recorded is treated as learned at the '
              'epoch, matching MindNet\'s `|| now` with now defaulting to 0');
    });

    test('days are converted to hours at exactly one place', () async {
      // The contract calls this out as the easiest silent mistake: the curve
      // constants are identical in both systems, only the unit differs.
      final row = await seedCard(stability: 2, difficulty: 5);
      final state = DsrCardState.read(row, nowHours: 0);
      expect(state.s, 2 * DsrCardState.hoursPerDay);
    });

    test('existing FSRS values become the model\'s starting point', () async {
      // An item with history must not be treated as brand new just because the
      // cognitive model has not seen it yet - that would make the two systems
      // disagree on the very first read.
      final row = await seedCard(stability: 10, difficulty: 6, repetitions: 4);
      final state = DsrCardState.read(row, nowHours: 0);
      expect(state.s, 240);
      expect(state.d, 6);
      expect(state.n, 4);
      expect(state.r0, 1.0,
          reason: 'no recorded ceiling means "no ceiling", which makes the two '
              'curves identical (both give R = 0.9 at t = S)');
    });

    test('a stored ceiling is respected, not overwritten', () async {
      final row = await seedCard(
        stability: 19.2,
        difficulty: 5.1618,
        encodingStrength: 0.8,
        savings: 0.9,
      );
      final state = DsrCardState.read(row, nowHours: 0);
      expect(state.r0, 0.8);
      expect(state.sigma, 0.9);
    });

    test('lifetime lapses are not turned into decayed evidence', () async {
      // `lapses` is a count of everything ever forgotten; the model's F is
      // *decayed* evidence. Deriving one from the other would be inventing
      // history, so the model starts with no evidence and rebuilds it.
      final row = await seedCard(stability: 5, difficulty: 5);
      final state = DsrCardState.read(row, nowHours: 0);
      expect(state.f, 0);
      expect(state.lastFail, isNull);
    });
  });

  group('round trip', () {
    test('write then read preserves the model state', () async {
      final row = await seedCard(stability: 10, difficulty: 6, savings: 0.4);
      const nowHours = 500.0;
      final before = DsrCardState.read(row, nowHours: nowHours);

      final update = DsrCardState.write(
        before,
        nowHours: nowHours,
        targetRetention: 0.9,
      );
      await (db.update(db.cardStates)..where((t) => t.id.equals('cs1')))
          .write(update);
      final reloaded =
          await (db.select(db.cardStates)..where((t) => t.id.equals('cs1')))
              .getSingle();

      final after = DsrCardState.read(reloaded, nowHours: nowHours);
      // Stability survives a day<->hour round trip to within rounding.
      expect(after.s, closeTo(before.s, 1e-6));
      expect(after.d, closeTo(before.d, 1e-9));
      expect(after.r0, closeTo(before.r0, 1e-9));
      expect(after.sigma, closeTo(before.sigma, 1e-9));
    });

    test('writing leaves the row internally consistent', () async {
      // The legacy columns must agree with the model's, or the review flow and
      // the model would describe different schedules for the same card.
      final row = await seedCard(stability: 10, difficulty: 5);
      const nowHours = 0.0;
      const nowMillis = 1700000000000;
      final state = DsrCardState.read(row, nowHours: nowHours);
      final update = DsrCardState.write(
        state,
        nowHours: nowHours,
        targetRetention: 0.9,
        nowMillis: nowMillis,
      );
      await (db.update(db.cardStates)..where((t) => t.id.equals('cs1')))
          .write(update);
      final stored =
          await (db.select(db.cardStates)..where((t) => t.id.equals('cs1')))
              .getSingle();

      // intervalDays must be the same schedule the model computed.
      final expectedHours = DsrMemory.scheduleInterval(state, nowHours, 0.9);
      expect(stored.intervalDays, closeTo(expectedHours / 24, 1e-9));
      expect(stored.dueAt, nowMillis + (expectedHours * 3600000).round());
      expect(stored.lastReviewedAt, nowMillis);
    });

    test('an unreachable retention target schedules for right now', () async {
      // A target above R0 can never be reached by the curve. Scheduling it into
      // the past would make the card vanish; due-now is the honest answer.
      final row = await seedCard(
        stability: 20,
        difficulty: 5,
        encodingStrength: 0.5,
      );
      const nowMillis = 1700000000000;
      final state = DsrCardState.read(row, nowHours: 0);
      final update = DsrCardState.write(
        state,
        nowHours: 0,
        targetRetention: 0.9,
        nowMillis: nowMillis,
      );
      await (db.update(db.cardStates)..where((t) => t.id.equals('cs1')))
          .write(update);
      final stored =
          await (db.select(db.cardStates)..where((t) => t.id.equals('cs1')))
              .getSingle();
      expect(stored.dueAt, nowMillis);
      expect(stored.intervalDays, 0);
    });
  });

  group('applying a review through the row', () {
    test('a successful review lengthens the interval and raises R0', () async {
      final row = await seedCard(stability: 10, difficulty: 5);
      final result = DsrCardState.applyReview(
        row,
        rating: 3,
        // Deliberately NOT `t = S`: at exactly t = S the item sits at R = 0.9,
        // where `round8` in the stability term flattens a ~1.1x gain to 1.0.
        // Reviewing an item right on its due boundary is a real no-op, so the
        // test uses a clearly overdue item instead.
        nowHours: 300,
        targetRetention: 0.9,
      );
      expect(result.outcome.kind, 'review');
      expect(result.update.stability.present, isTrue);
      expect(result.update.stability.value,
          greaterThan(row.stability ?? 0));
      expect(result.update.encodingStrength.value,
          greaterThan(1.0 - 1e-9));
    });

    test('reviewing exactly at the due moment is a near no-op', () async {
      // The flip side of the comment above, pinned so nobody "fixes" it later:
      // the model is not supposed to reward reviewing on time with a big jump.
      final row = await seedCard(stability: 10, difficulty: 5);
      final atDue = DsrCardState.applyReview(
        row,
        rating: 3,
        nowHours: 240,
        targetRetention: 0.9,
      );
      final overdue = DsrCardState.applyReview(
        row,
        rating: 3,
        nowHours: 300,
        targetRetention: 0.9,
      );
      final atDueStability = atDue.update.stability.value!;
      final overdueStability = overdue.update.stability.value!;
      expect(atDueStability, lessThan(overdueStability));
    });

    test('rating 1 is a lapse, not a slow success', () async {
      final row = await seedCard(stability: 40, difficulty: 5);
      final result = DsrCardState.applyReview(
        row,
        rating: 1,
        nowHours: 240,
        targetRetention: 0.9,
      );
      expect(result.outcome.kind, 'lapse');
      expect(result.outcome.sInc, isNull);
      expect(result.update.stability.value, lessThan(row.stability!));
    });

    test('the update is a pure function of the row and the event', () async {
      // Same input, same output - no hidden clock, no accumulated state. This
      // is what makes the model testable and reproducible, and it is why the
      // conformance vectors can exist at all.
      final row = await seedCard(stability: 10, difficulty: 5);
      CardStatesCompanion? first;
      CardStatesCompanion? second;
      for (var i = 0; i < 2; i++) {
        final result = DsrCardState.applyReview(
          row,
          rating: 3,
          nowHours: 240,
          targetRetention: 0.9,
          nowMillis: 1700000000000,
        );
        if (i == 0) {
          first = result.update;
        } else {
          second = result.update;
        }
      }
      expect(second!.stability.value, first!.stability.value);
      expect(second.dueAt.value, first.dueAt.value);
      expect(second.encodingStrength.value, first.encodingStrength.value);
    });

    test('retrievability and expected gain are derived, never stored', () async {
      // `lastReviewedAt` matters: with no review time the model treats the item
      // as learned at hour 0, so the elapsed window is `nowHours` itself.
      // Seeding the review moment is what makes the decay measurable.
      final row = await seedCard(
        stability: 19.2,
        difficulty: 5.1618,
        encodingStrength: 1,
        lastReviewedAt: (10 * Duration.millisecondsPerHour).round(),
      );
      // 10 hours after the review, with S = 19.2h, the item is barely touched.
      final justAfter = DsrCardState.retrievabilityOf(row, nowHours: 10);
      expect(justAfter, closeTo(1.0, 1e-6));
      final later = DsrCardState.retrievabilityOf(row, nowHours: 100);
      expect(later, lessThan(justAfter));
      // A forgotten item gains more from a review than a fresh one.
      final gainForgetting = DsrCardState.expectedGain(row, nowHours: 400);
      final gainFresh = DsrCardState.expectedGain(row, nowHours: 11);
      expect(gainForgetting, greaterThan(gainFresh));
    });

    test('a never-reviewed card is treated as learned at the epoch', () async {
      // Counter-intuitive but deliberate, and pinned so it is not "fixed":
      // MindNet initialises `lastReview = node.last_review_time || now` with
      // `now` defaulting to 0, so a card with no review recorded has been
      // decaying since hour 0. Reading it as "brand new, R = 1" instead would
      // make `dt = 0` forever and the model would compute nothing.
      final row = await seedCard(stability: 5, difficulty: 5);
      final forgotten = DsrCardState.retrievabilityOf(row, nowHours: 100000);
      // Decayed a long way, and specifically *below* what a recently reviewed
      // card gives - the reviewed case is covered by the tests that seed
      // `lastReviewedAt`, so this one only pins the epoch reading.
      expect(forgotten, lessThan(0.9),
          reason: 'a card never reviewed is treated as learned at hour 0, so it '
              'has decayed by hour 100000 rather than reading as brand new');
    });
  });

  group('rating vocabulary', () {
    test('the mapping is explicit for every rating', () {
      expect(DsrCardState.eventFor(rating: 1).type, DsrEventType.lapse);
      expect(DsrCardState.eventFor(rating: 2).type,
          DsrEventType.retrievalSuccess);
      expect(DsrCardState.eventFor(rating: 2).grade, 2);
      expect(DsrCardState.eventFor(rating: 4).grade, 4);
      // Out-of-range input is clamped rather than rejected: a rating is UI
      // input, and losing a review because of a stray 0 would be worse.
      expect(DsrCardState.eventFor(rating: 0).type, DsrEventType.lapse);
      expect(DsrCardState.eventFor(rating: 9).grade, 4);
    });

    test('rereading is a different event from retrieving', () {
      // The model weights them differently, which is the extract-practice
      // effect; collapsing them would throw that away.
      expect(DsrCardState.eventFor(rating: 3, reread: true).type,
          DsrEventType.reread);
    });
  });
}

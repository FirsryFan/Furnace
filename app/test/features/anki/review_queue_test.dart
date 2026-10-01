import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/diffusion_log_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/domain/services/cognitive/cognitive_model.dart';
import 'package:furnace/domain/services/srs/dsr_card_state.dart';
import 'package:furnace/domain/services/srs/fsrs_scheduler.dart';
import 'package:furnace/features/anki/application/review_service.dart';

/// The review flow as it is now wired to the cognitive model (D1/D2/D4/D5/D6):
/// bands decide the order, the model band is the model's own total order, the
/// FSRS columns keep exactly one writer, and an unseen card is never given a
/// history it does not have.
void main() {
  late AppDatabase db;
  late AnkiRepository anki;
  late ReviewService service;

  /// A fixed clock: every assertion below compares stored values against a
  /// recomputation with the same `now`, so nothing depends on wall time.
  final moment = DateTime.fromMillisecondsSinceEpoch(1700000000000);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    anki = AnkiRepository(db);
    service = ReviewService(
      ankiRepository: anki,
      tagRepository: TagRepository(db),
      taskRepository: TaskRepository(db),
      diffusionLogRepository: DiffusionLogRepository(db),
      random: Random(7),
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<KnowledgePoint> knowledgePoint(String title) =>
      anki.createKnowledgePoint(
        title: title,
        content: '$title在系统不受外力时守恒。',
      );

  Future<CardState?> rowFor(String knowledgePointId) async {
    final states = await anki.unitStatesForKnowledgePoint(knowledgePointId);
    return states.isEmpty ? null : states.first;
  }

  /// Gives the knowledge point's unit a review history, i.e. moves it out of
  /// the unseen band.
  Future<void> giveHistory(
    String knowledgePointId, {
    int repetitions = 4,
    double stability = 6,
    double difficulty = 5,
    int? forced,
    double? encodingStrength,
    double? savings,
  }) async {
    final row = (await rowFor(knowledgePointId))!;
    await anki.updateUnitCardState(
      row.id,
      repetitions: repetitions,
      stability: stability,
      difficulty: difficulty,
      dueAt: moment.subtract(const Duration(days: 4)).millisecondsSinceEpoch,
      lastReviewedAt:
          moment.subtract(const Duration(days: 6)).millisecondsSinceEpoch,
      forced: forced,
      forcedStreak: forced == 1 ? 1 : null,
    );
    if (encodingStrength != null || savings != null) {
      await anki.updateModelState(
        row.id,
        encodingStrength: encodingStrength,
        savings: savings,
      );
    }
  }

  group('queue bands', () {
    test('model band first, unseen last, and a forced unit keeps its slot',
        () async {
      final a = await knowledgePoint('动量');
      final b = await knowledgePoint('冲量');
      final c = await knowledgePoint('动能');
      final d = await knowledgePoint('功');

      // First pass creates one unit row per knowledge point, all unseen.
      await service.buildQueue(now: moment);
      await giveHistory(a.id);
      await giveHistory(b.id);
      await giveHistory(d.id, forced: 1);

      final queue = await service.buildQueue(now: moment);
      final ids = [for (final item in queue) item.knowledgePointId];

      expect(ids, hasLength(4));
      // D4: the unseen card is never scored, and it sits behind the model band.
      expect(ids.indexOf(c.id), greaterThan(ids.indexOf(a.id)));
      expect(ids.indexOf(c.id), greaterThan(ids.indexOf(b.id)));
      // The forced unit's *position* is annotation 17's rule, not the band
      // order: it ends up appended because the rest of the queue is shorter
      // than one relearn gap.
      expect(ids.last, d.id);
      expect(queue.last.cardState.forced, 1);
    });

    test('the model band is orderAdvisory itself, not a second comparator',
        () async {
      final ids = <String>[];
      for (final title in ['甲', '乙', '丙']) {
        ids.add((await knowledgePoint(title)).id);
      }
      await service.buildQueue(now: moment);
      // Three different histories, so gain order cannot coincide with dueAt
      // order by accident.
      await giveHistory(ids[0], stability: 4, difficulty: 4);
      await giveHistory(ids[1], stability: 60, difficulty: 6);
      await giveHistory(ids[2], stability: 15, difficulty: 5);

      final queue = await service.buildQueue(now: moment);
      final modelBand = [
        for (final item in queue)
          if (!item.isNew && item.cardState.forced != 1) item,
      ];

      final direct = const MindNetCognitiveModel().orderAdvisory(
        [
          for (final item in modelBand)
            AdvisorCandidate(
              knowledgePointId: item.knowledgePointId,
              row: item.cardState,
            ),
        ],
        nowHours: modelHoursOf(moment),
      );

      expect([for (final i in modelBand) i.cardState.id],
          [for (final c in direct) c.row.id],
          reason: 'the band order must be exactly what the model returns');
    });
  });

  group('grade', () {
    test('FSRS keeps stability/difficulty/dueAt; the model writes two columns',
        () async {
      final a = await knowledgePoint('动量');
      await service.buildQueue(now: moment);
      await giveHistory(a.id, repetitions: 3, stability: 20, difficulty: 5.5);

      final item = (await service.buildQueue(now: moment)).single;
      final before = (await rowFor(a.id))!;
      expect(before.encodingStrength, equals(null));

      final outcome = await service.grade(
        item: item,
        correct: true,
        rating: FsrsRating.good,
        now: moment,
      );

      // Independent FSRS recomputation: the stored schedule must be FSRS's.
      final expected = FsrsScheduler.schedule(
        memory: FsrsMemory(
          stability: before.stability!,
          difficulty: before.difficulty!,
        ),
        lastReview: DateTime.fromMillisecondsSinceEpoch(before.lastReviewedAt!),
        now: moment,
        rating: FsrsRating.good,
      );

      final after = (await rowFor(a.id))!;
      expect(after.stability, closeTo(expected.memory.stability, 1e-9));
      expect(after.difficulty, closeTo(expected.memory.difficulty, 1e-9));
      expect(after.dueAt, expected.dueAt.millisecondsSinceEpoch);
      expect(after.intervalDays, closeTo(expected.scheduledDays.toDouble(), 1e-9));
      expect(outcome.nextDueAt, expected.dueAt);

      // …and the model wrote its own two columns, once, from the seam.
      final viaSeam = const MindNetCognitiveModel().modelStateAfterReview(
        before,
        rating: FsrsRating.good.value,
        nowHours: modelHoursOf(moment),
      );
      expect(after.encodingStrength, closeTo(viaSeam.r0, 1e-9));
      expect(after.savings, closeTo(viaSeam.sigma, 1e-9));
      expect(after.lastReviewedAt, moment.millisecondsSinceEpoch);
      expect(after.repetitions, before.repetitions + 1);
    });

    test('an unseen card gets no fabricated history', () async {
      final c = await knowledgePoint('动能');
      final queue = await service.buildQueue(now: moment);
      expect(queue.single.isNew, isTrue);

      final row = (await rowFor(c.id))!;
      expect(row.repetitions, 0);
      expect(row.lastReviewedAt, equals(null));
      expect(row.stability, equals(null));
      expect(row.difficulty, equals(null));
      // The model has not judged it either: no score is written for an item it
      // was never asked about (D4).
      expect(row.encodingStrength, equals(null));
      expect(row.savings, equals(null));
      expect(row.dueAt, equals(null));
    });

    test('D6: a lapse never moves R0 - tierA pinned, no guard added', () async {
      final a = await knowledgePoint('动量');
      await service.buildQueue(now: moment);
      await giveHistory(
        a.id,
        repetitions: 2,
        stability: 15,
        difficulty: 6,
        encodingStrength: 0.3,
        savings: 0.3,
      );

      final item = (await service.buildQueue(now: moment)).single;
      final before = (await rowFor(a.id))!;

      await service.grade(
        item: item,
        correct: false,
        rating: FsrsRating.good,
        now: moment,
      );

      final after = (await rowFor(a.id))!;

      // The pinned, deliberately **unguarded** behaviour (dsr_memory.dart's
      // lapse branch, L470-479): a lapse takes stability apart and records the
      // failure, but it does not touch the encoding ceiling - only a
      // *successful* retrieval raises R0 (`r0 <- min(1, r0 + c_R0*(1-r0))`,
      // L484-486). The counter-intuitive consequence is that an item the user
      // keeps failing keeps a low ceiling forever, and D6 keeps it that way
      // bit-for-bit with the JS instead of adding a guard.
      expect(after.encodingStrength, closeTo(before.encodingStrength!, 1e-12));
      expect(after.encodingStrength, closeTo(0.3, 1e-12));
      expect(after.stability! < before.stability!, isTrue,
          reason: 'a lapse does collapse stability');
      expect(after.savings! >= before.savings!, isTrue,
          reason: 'the savings effect is kept across a lapse');

      // …and the two stored numbers are exactly what tierA itself would write,
      // to the last bit: the narrow write is not a second implementation.
      final viaTierA = DsrCardState.applyReview(
        before,
        rating: FsrsRating.again.value,
        nowHours: modelHoursOf(moment),
        targetRetention: 0.9,
      ).update;
      expect(after.encodingStrength,
          closeTo(viaTierA.encodingStrength.value!, 1e-12));
      expect(after.savings, closeTo(viaTierA.savings.value!, 1e-12));
    });

    test('a model that throws never blocks the review (D1 fallback)', () async {
      final a = await knowledgePoint('动量');
      await service.buildQueue(now: moment);
      await giveHistory(a.id, repetitions: 2, stability: 10, difficulty: 5);

      final failing = ReviewService(
        ankiRepository: anki,
        tagRepository: TagRepository(db),
        taskRepository: TaskRepository(db),
        diffusionLogRepository: DiffusionLogRepository(db),
        random: Random(7),
        cognitiveModel: const _ThrowingModel(),
      );

      final item = (await failing.buildQueue(now: moment)).single;
      final before = (await rowFor(a.id))!;

      await failing.grade(
        item: item,
        correct: true,
        rating: FsrsRating.good,
        now: moment,
      );

      final after = (await rowFor(a.id))!;
      // The review itself went through: FSRS's columns moved.
      expect(after.repetitions, before.repetitions + 1);
      expect(after.lastReviewedAt, moment.millisecondsSinceEpoch);
      expect(after.stability, isNot(equals(before.stability)));
      // …and the advisor's two columns were simply left as they were, because
      // advisement is not allowed to fail a review (D1).
      expect(after.encodingStrength, equals(null));
      expect(after.savings, equals(null));
    });
  });
}

/// A model that answers everything except the write-path question, which it
/// refuses: the review flow must survive that (D1).
class _ThrowingModel implements CognitiveModel {
  const _ThrowingModel();

  static const CognitiveModel _inner = MindNetCognitiveModel();

  @override
  String get id => 'throwing';

  @override
  double retrievabilityOf(CardState row, {required double nowHours}) =>
      _inner.retrievabilityOf(row, nowHours: nowHours);

  @override
  double expectedGain(
    CardState row, {
    required double nowHours,
    double closeness = 0.5,
  }) =>
      _inner.expectedGain(row, nowHours: nowHours, closeness: closeness);

  @override
  List<AdvisorCandidate> orderAdvisory(
    List<AdvisorCandidate> candidates, {
    required double nowHours,
    Set<String> targetKpIds = const {},
  }) =>
      _inner.orderAdvisory(
        candidates,
        nowHours: nowHours,
        targetKpIds: targetKpIds,
      );

  @override
  ({double r0, double sigma, double r}) modelReadingOf(
    CardState row, {
    required double nowHours,
  }) =>
      _inner.modelReadingOf(row, nowHours: nowHours);

  @override
  ({double r0, double sigma}) modelStateAfterReview(
    CardState row, {
    required int rating,
    required double nowHours,
    bool reread = false,
    double closeness = 0.5,
  }) {
    throw StateError('advisor unavailable');
  }
}

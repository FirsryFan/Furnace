import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/cognitive/cognitive_model.dart';
import 'package:furnace/domain/services/cognitive/fast_diagnosis.dart'
    show BottleneckType;
import 'package:furnace/features/anki/application/review_advisory.dart';

/// `ReviewAdvisory` is a pure function, so none of these tests open a database:
/// rows are constructed directly and the model is the real tierA-backed
/// implementation (or a spy around it).
void main() {
  const model = MindNetCognitiveModel();
  const nowHours = 1000.0;

  CardState rowOf({
    required String id,
    String unitKey = 'u',
    String knowledgePointId = 'kp',
    int? dueAt,
    int repetitions = 5,
    int forced = 0,
    double? stability = 20,
    int? lastReviewedAt = 1000,
  }) =>
      CardState(
        id: id,
        unitKey: unitKey,
        knowledgePointId: knowledgePointId,
        dueAt: dueAt,
        intervalDays: 5,
        ease: 2.5,
        repetitions: repetitions,
        lapses: 0,
        state: 'review',
        lastReviewedAt: lastReviewedAt,
        createdAt: 1,
        updatedAt: 2,
        stability: stability,
        difficulty: 5,
        encodingStrength: 1.0,
        savings: 0.8,
        forced: forced,
        forcedStreak: 0,
      );

  ReviewCandidate candidate({
    required String id,
    String knowledgePointId = 'kp',
    int? dueAt,
    int repetitions = 5,
    int forced = 0,
    bool isNew = false,
    double? stability = 20,
    int? lastReviewedAt = 1000,
    String unitKey = 'u',
  }) =>
      ReviewCandidate(
        knowledgePointId: knowledgePointId,
        row: rowOf(
          id: id,
          unitKey: unitKey,
          knowledgePointId: knowledgePointId,
          dueAt: dueAt,
          repetitions: repetitions,
          forced: forced,
          stability: stability,
          lastReviewedAt: lastReviewedAt,
        ),
        isNew: isNew,
      );

  List<String> idsOf(List<ReviewCandidate> items) =>
      [for (final item in items) item.row.id];

  group('bands', () {
    test('partitions into forced -> boosted -> model -> unseen, and labels',
        () {
      final forced = candidate(id: 'f1', forced: 1);
      final boosted = candidate(
        id: 'b1',
        knowledgePointId: 'kp-b',
        dueAt: 900,
      );
      final modelItem = candidate(
        id: 'm1',
        knowledgePointId: 'kp-m',
        dueAt: 500,
      );
      final unseen = candidate(
        id: 'n1',
        knowledgePointId: 'kp-n',
        dueAt: null,
        repetitions: 0,
        stability: null,
        lastReviewedAt: null,
        isNew: true,
      );

      final ordering = ReviewAdvisory.order(
        candidates: [unseen, modelItem, forced, boosted],
        model: model,
        nowHours: nowHours,
        boostFactorByKnowledgePoint: const {'kp-b': 1.8},
      );

      expect(idsOf(ordering.ranked), ['f1', 'b1', 'm1', 'n1']);
      expect(ordering.bandByCardStateId, {
        'f1': ReviewBand.forced,
        'b1': ReviewBand.boosted,
        'm1': ReviewBand.model,
        'n1': ReviewBand.unseen,
      });
    });

    test('forced wins even when the item is also boosted and brand new', () {
      final both = candidate(
        id: 'f1',
        knowledgePointId: 'kp-b',
        forced: 1,
        repetitions: 0,
        isNew: true,
      );

      final ordering = ReviewAdvisory.order(
        candidates: [both],
        model: model,
        nowHours: nowHours,
        boostFactorByKnowledgePoint: const {'kp-b': 1.8},
      );

      expect(ordering.bandByCardStateId['f1'], ReviewBand.forced);
    });

    test('keeps forced items in the caller order (placement is not mine)', () {
      final first = candidate(id: 'f2', knowledgePointId: 'kp-z', forced: 1);
      final second = candidate(id: 'f1', knowledgePointId: 'kp-a', forced: 1);

      final ordering = ReviewAdvisory.order(
        candidates: [first, second],
        model: model,
        nowHours: nowHours,
      );

      // Sorted by id these would swap; the interleave rule depends on the
      // caller's order, so it is preserved verbatim.
      expect(idsOf(ordering.ranked), ['f2', 'f1']);
    });

    test('two knowledge points sharing the essay fallback key stay distinct',
        () {
      // `ReviewService._itemFor` gives every point with nothing blankable the
      // unit key 'essay', so the key cannot identify a queue entry.
      final first = candidate(
        id: 'essay-a',
        knowledgePointId: 'kp-a',
        unitKey: 'essay',
      );
      final second = candidate(
        id: 'essay-b',
        knowledgePointId: 'kp-b',
        unitKey: 'essay',
      );

      final ordering = ReviewAdvisory.order(
        candidates: [first, second],
        model: model,
        nowHours: nowHours,
      );

      expect(ordering.bandByCardStateId, hasLength(2));
      expect(ordering.bandByCardStateId['essay-a'], ReviewBand.model);
      expect(ordering.bandByCardStateId['essay-b'], ReviewBand.model);
      expect(ordering.scoreByCardStateId, hasLength(2));
    });
  });

  group('model band delegation', () {
    test('model band order equals a direct orderAdvisory call (targets passed)',
        () {
      final items = [
        candidate(
          id: 'm1',
          knowledgePointId: 'kp-1',
          dueAt: 400,
          stability: 5,
          lastReviewedAt: 2000,
        ),
        candidate(
          id: 'm2',
          knowledgePointId: 'kp-2',
          dueAt: 300,
          stability: 40,
          lastReviewedAt: 900,
        ),
        candidate(
          id: 'm3',
          knowledgePointId: 'kp-3',
          dueAt: null,
          stability: 20,
          lastReviewedAt: 1500,
        ),
      ];

      final ordering = ReviewAdvisory.order(
        candidates: items,
        model: model,
        nowHours: nowHours,
        targetKpIds: const {'kp-3'},
      );

      final expected = model.orderAdvisory(
        [
          for (final item in items)
            AdvisorCandidate(
              knowledgePointId: item.knowledgePointId,
              row: item.row,
            ),
        ],
        nowHours: nowHours,
        targetKpIds: const {'kp-3'},
      );

      expect(idsOf(ordering.ranked), [for (final e in expected) e.row.id]);
    });

    test('asks the model once, and never about forced/boosted/unseen items',
        () {
      final spy = _SpyModel(model);
      final ordering = ReviewAdvisory.order(
        candidates: [
          candidate(id: 'f1', knowledgePointId: 'kp-f', forced: 1),
          candidate(id: 'b1', knowledgePointId: 'kp-b'),
          candidate(id: 'm1', knowledgePointId: 'kp-m'),
          candidate(
            id: 'n1',
            knowledgePointId: 'kp-n',
            repetitions: 0,
            stability: null,
            lastReviewedAt: null,
            isNew: true,
          ),
        ],
        model: spy,
        nowHours: nowHours,
        boostFactorByKnowledgePoint: const {'kp-b': 1.3},
      );

      expect(spy.advisories, 1);
      expect(spy.scoredRowIds.toSet(), {'m1'});
      expect(
        ordering.scoreByCardStateId.keys,
        ['m1'],
        reason: 'only the model band carries a model score (D4)',
      );
    });
  });

  group('boosted band', () {
    test('sorts by factor descending, ties by knowledge point then row id', () {
      final low = candidate(id: 'b-low', knowledgePointId: 'kp-1');
      final high = candidate(id: 'b-high', knowledgePointId: 'kp-2');
      final tieB = candidate(id: 'b-tie-b', knowledgePointId: 'kp-9');
      final tieA = candidate(id: 'b-tie-a', knowledgePointId: 'kp-9');

      final ordering = ReviewAdvisory.order(
        candidates: [low, high, tieB, tieA],
        model: model,
        nowHours: nowHours,
        boostFactorByKnowledgePoint: const {
          'kp-1': 1.3,
          'kp-2': 1.8,
          'kp-9': 1.3,
        },
      );

      // factor 1.8 leads; inside the 1.3 group the knowledge point decides
      // first ('kp-1' < 'kp-9'), then the row id.
      expect(idsOf(ordering.ranked), ['b-high', 'b-low', 'b-tie-a', 'b-tie-b']);
    });
  });

  group('unseen band', () {
    test('orders by dueAt (null first), then point, then row id, no score', () {
      final unscheduledB = candidate(
        id: 'n-b',
        knowledgePointId: 'kp-b',
        dueAt: null,
        repetitions: 0,
        stability: null,
        lastReviewedAt: null,
        isNew: true,
      );
      final unscheduledA = candidate(
        id: 'n-a',
        knowledgePointId: 'kp-a',
        dueAt: null,
        repetitions: 0,
        stability: null,
        lastReviewedAt: null,
        isNew: true,
      );
      final scheduled = candidate(
        id: 'n-c',
        knowledgePointId: 'kp-c',
        dueAt: 500,
        repetitions: 0,
        stability: null,
        lastReviewedAt: null,
        isNew: true,
      );

      final ordering = ReviewAdvisory.order(
        candidates: [unscheduledB, scheduled, unscheduledA],
        model: model,
        nowHours: nowHours,
      );

      expect(idsOf(ordering.ranked), ['n-a', 'n-b', 'n-c']);
      expect(ordering.scoreByCardStateId, isEmpty);
      expect(ordering.bandByCardStateId.values.toSet(), {ReviewBand.unseen});
    });
  });

  group('zones', () {
    test('no diagnosis layer => every point unavailable, order still fixed',
        () {
      final items = [
        candidate(id: 'm1', knowledgePointId: 'kp-1'),
        candidate(id: 'm2', knowledgePointId: 'kp-2'),
      ];

      final first = ReviewAdvisory.order(
        candidates: items,
        model: model,
        nowHours: nowHours,
        diagnosisByKnowledgePoint: null,
      );
      final second = ReviewAdvisory.order(
        candidates: items,
        model: model,
        nowHours: nowHours,
        diagnosisByKnowledgePoint: null,
      );

      expect(first.zoneByKnowledgePoint.values.toSet(),
          {ReviewZone.unavailable});
      expect(idsOf(first.ranked), idsOf(second.ranked));
    });

    test('translates all seven verdicts one to one', () {
      const translations = <BottleneckType, ReviewZone>{
        BottleneckType.weak: ReviewZone.proximal,
        BottleneckType.empty: ReviewZone.empty,
        BottleneckType.deadEnd: ReviewZone.deadEnd,
        BottleneckType.slow: ReviewZone.slow,
        BottleneckType.overload: ReviewZone.overload,
        BottleneckType.offGoal: ReviewZone.offGoal,
        BottleneckType.danger: ReviewZone.danger,
      };

      for (final entry in translations.entries) {
        expect(ReviewAdvisory.zoneOf(entry.key), entry.value,
            reason: '${entry.key.id} must map to its own zone');
      }
    });

    test('empty, healthy and unavailable are three different things', () {
      expect(ReviewZone.values, hasLength(9),
          reason: 'seven verdicts + healthy + unavailable');
      final items = [
        candidate(id: 'm1', knowledgePointId: 'kp-empty'),
        candidate(id: 'm2', knowledgePointId: 'kp-danger'),
        candidate(id: 'm3', knowledgePointId: 'kp-verdictless'),
        candidate(id: 'm4', knowledgePointId: 'kp-notasked'),
      ];

      final ran = ReviewAdvisory.order(
        candidates: items.sublist(0, 3),
        model: model,
        nowHours: nowHours,
        diagnosisByKnowledgePoint: const {
          'kp-empty': BottleneckType.empty,
          'kp-danger': BottleneckType.danger,
        },
      );

      expect(ran.zoneByKnowledgePoint['kp-empty'], ReviewZone.empty);
      expect(ran.zoneByKnowledgePoint['kp-empty'],
          isNot(ReviewZone.unavailable));
      expect(ran.zoneByKnowledgePoint['kp-danger'], ReviewZone.danger);
      expect(ran.zoneByKnowledgePoint['kp-danger'],
          isNot(ReviewZone.proximal));
      // The layer ran and produced no verdict for this node: it lit up, is on
      // target and has a way out. That is `healthy`, not `unavailable`.
      expect(ran.zoneByKnowledgePoint['kp-verdictless'], ReviewZone.healthy);
      expect(ran.zoneByKnowledgePoint['kp-verdictless'],
          isNot(ReviewZone.unavailable));

      // Without a diagnosis run, the same knowledge point is "nobody looked".
      final notRun = ReviewAdvisory.order(
        candidates: items.sublist(3),
        model: model,
        nowHours: nowHours,
        diagnosisByKnowledgePoint: null,
      );
      expect(notRun.zoneByKnowledgePoint['kp-notasked'],
          ReviewZone.unavailable);
      expect(notRun.zoneByKnowledgePoint['kp-notasked'],
          isNot(ReviewZone.healthy));
    });
  });

  group('purity', () {
    test('does not mutate its input and repeats identically', () {
      final items = [
        candidate(id: 'm2', knowledgePointId: 'kp-2'),
        candidate(id: 'm1', knowledgePointId: 'kp-1'),
        candidate(
          id: 'n1',
          knowledgePointId: 'kp-3',
          repetitions: 0,
          stability: null,
          lastReviewedAt: null,
          isNew: true,
        ),
      ];
      final inputOrderBefore = idsOf(items);

      final first = ReviewAdvisory.order(
        candidates: items,
        model: model,
        nowHours: nowHours,
      );
      final second = ReviewAdvisory.order(
        candidates: items,
        model: model,
        nowHours: nowHours,
      );

      expect(idsOf(items), inputOrderBefore, reason: 'input list untouched');
      expect(idsOf(first.ranked), idsOf(second.ranked));
      expect(
        [for (final item in first.ranked) item],
        [for (final item in second.ranked) item],
        reason: 'same instances, and the same sequence',
      );
    });
  });
}

/// Counts what the advisor asks the model, so "the model is not consulted for
/// new cards" is measured rather than asserted in a comment.
class _SpyModel implements CognitiveModel {
  _SpyModel(this._inner);

  final CognitiveModel _inner;
  int advisories = 0;
  final List<String> scoredRowIds = <String>[];

  @override
  String get id => 'spy(${_inner.id})';

  @override
  double retrievabilityOf(CardState row, {required double nowHours}) =>
      _inner.retrievabilityOf(row, nowHours: nowHours);

  @override
  double expectedGain(
    CardState row, {
    required double nowHours,
    double closeness = 0.5,
  }) {
    scoredRowIds.add(row.id);
    return _inner.expectedGain(row, nowHours: nowHours, closeness: closeness);
  }

  @override
  List<AdvisorCandidate> orderAdvisory(
    List<AdvisorCandidate> candidates, {
    required double nowHours,
    Set<String> targetKpIds = const {},
  }) {
    advisories++;
    return _inner.orderAdvisory(
      candidates,
      nowHours: nowHours,
      targetKpIds: targetKpIds,
    );
  }

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
  }) =>
      _inner.modelStateAfterReview(
        row,
        rating: rating,
        nowHours: nowHours,
        reread: reread,
        closeness: closeness,
      );
}

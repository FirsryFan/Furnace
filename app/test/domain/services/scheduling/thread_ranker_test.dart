import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/config/furnace_defaults.dart';
import 'package:furnace/domain/services/scheduling/thread_ranker.dart';
import 'package:furnace/domain/services/scheduling/time_window_engine.dart';

void main() {
  final now = DateTime(2026, 9, 7, 20); // Monday evening

  group('hard constraint (spec 1.1.3)', () {
    test('event that cannot fit before deadline is red-listed', () {
      final tooBig = RankEvent(
        id: 'e1',
        title: '写论文',
        estimateMinutes: 120,
        dueAt: now.add(const Duration(hours: 1)),
      );
      final fits = RankEvent(
        id: 'e2',
        title: '读课文',
        estimateMinutes: 20,
        dueAt: now.add(const Duration(hours: 1)),
      );
      final output = ThreadRanker.rank(
        events: [tooBig, fits],
        context: RankContext(now: now),
      );
      expect(output.insufficient.map((e) => e.event.id), contains('e1'));
      expect(output.ready.map((e) => e.event.id), contains('e2'));
      final red = output.insufficient.single;
      expect(red.neededMinutes, 120);
      expect(red.availableMinutes, 60);
    });

    test('busy blocks shrink available minutes (deadline window)', () {
      final event = RankEvent(
        id: 'e',
        title: 't',
        estimateMinutes: 31,
        // now 20:00, deadline 21:00 with 20:10-20:40 busy -> available 30.
        dueAt: now.add(const Duration(minutes: 60)),
      );
      final output = ThreadRanker.rank(
        events: [event],
        context: RankContext(
          now: now,
          blocks: [
            ScheduleBlock(
              id: 'busy',
              title: 'busy',
              startAt: now.add(const Duration(minutes: 10)),
              endAt: now.add(const Duration(minutes: 40)),
              available: false,
            ),
          ],
        ),
      );
      final red = output.insufficient.single;
      expect(red.availableMinutes, 30); // 60 - 30 busy
    });
  });

  group('weighted ordering (spec 1.1.3)', () {
    test('nearer deadline ranks higher (urgency 0.4)', () {
      final near = RankEvent(
        id: 'near',
        title: 'a',
        dueAt: now.add(const Duration(hours: 1)),
      );
      final far = RankEvent(
        id: 'far',
        title: 'b',
        dueAt: now.add(const Duration(hours: 48)),
      );
      final output = ThreadRanker.rank(
        events: [far, near],
        context: RankContext(now: now),
      );
      expect(output.ready.first.event.id, 'near');
      // urgency = 0.5^(60/240) for a 1-hour deadline (half-life 4 h).
      expect(output.ready.first.score.urgency, closeTo(0.8408964, 1e-4));
    });

    test('goal path boosts matching tag (goal match 0.3)', () {
      final matching = RankEvent(
        id: 'm',
        title: 'm',
        dueAt: now.add(const Duration(days: 1)),
        tagPaths: const ['文化课/数学/函数'],
      );
      final other = RankEvent(
        id: 'o',
        title: 'o',
        dueAt: now.add(const Duration(days: 1)),
        tagPaths: const ['文化课/语文/作文'],
      );
      final output = ThreadRanker.rank(
        events: [other, matching],
        context: RankContext(
          now: now,
          goal: const RankGoal(path: '文化课/数学'),
        ),
      );
      expect(output.ready.first.event.id, 'm');
      expect(output.ready.first.score.goalMatch, 1.0);
      // Partial credit: 文化课/语文/作文 shares the ancestor 文化课 (1 of 2
      // goal segments).
      expect(output.ready.last.score.goalMatch, closeTo(0.5, 1e-9));
    });

    test('energy fit prefers matching effort (fit 0.2)', () {
      final easy = RankEvent(
        id: 'easy',
        title: 'e',
        energyRequired: 2,
        dueAt: now.add(const Duration(days: 1)),
      );
      final heavy = RankEvent(
        id: 'heavy',
        title: 'h',
        energyRequired: 9,
        dueAt: now.add(const Duration(days: 1)),
      );
      final output = ThreadRanker.rank(
        events: [heavy, easy],
        context: RankContext(now: now, energy: 9),
      );
      expect(output.ready.first.event.id, 'heavy');
      // No estimate -> the window side has no data and is dropped from the
      // average, so fit equals the energy fit exactly (9 vs 9 = 1.0). It used
      // to be averaged with an invented neutral 0.5, which silently halved
      // every score of an event without an estimate.
      expect(output.ready.first.score.energyFit, 1.0);
      expect(output.ready.first.score.windowFit, isNull);
      expect(output.ready.first.score.fit, closeTo(1.0, 1e-9));
      expect(output.ready.last.score.energyFit, lessThan(0.5));

      // A missing energy level is "no data", not "half match".
      final noEnergy = ThreadRanker.rank(
        events: [heavy],
        context: RankContext(now: now),
      );
      expect(noEnergy.ready.single.score.energyFit, isNull);
      expect(noEnergy.ready.single.score.fit,
          FurnaceDefaults.fitMissingEstimateScore);
    });

    test('weights are normalized so the total cannot exceed 1', () {
      // The five shipped defaults add up to 1.05 - the ranker divides by the
      // sum, so a perfect event still scores at most 1.0.
      const raw = RankWeights();
      expect(raw.sum, closeTo(1.05, 1e-9));
      expect(raw.normalized().sum, closeTo(1.0, 1e-9));

      final perfect = RankEvent(
        id: 'perfect',
        title: 'p',
        estimateMinutes: 30,
        energyRequired: 5,
        dueAt: now.add(const Duration(minutes: 5)),
        tagPaths: const ['数学'],
      );
      final output = ThreadRanker.rank(
        events: [perfect],
        context: RankContext(
          now: now,
          energy: 5,
          goal: const RankGoal(text: '数学'),
        ),
      );
      final score = output.all.single.score;
      expect(score.urgency, 1.0);
      expect(score.goalMatch, 1.0);
      expect(score.fit, 1.0);
      expect(score.fatiguePenalty, 0.0);
      expect(score.expectedPressure, 0.0);
      // Total = (0.4 + 0.3 + 0.2) / 1.05 - the weights are rescaled, so the
      // achievable maximum with no fatigue and no expected pressure is the
      // share of the three positive components.
      expect(score.total, lessThanOrEqualTo(1.0 + 1e-9));
      expect(score.total, closeTo(0.9 / 1.05, 1e-9));
    });

    test('fatigue penalizes same-class completions within an hour', () {
      final lateNight = now.subtract(const Duration(minutes: 10));
      final reading = RankEvent(
        id: 'reading',
        title: '阅读',
        dueAt: now.add(const Duration(days: 1)),
        tagPaths: const ['阅读'],
      );
      final mathTask = RankEvent(
        id: 'math',
        title: '数学',
        dueAt: now.add(const Duration(days: 1)),
        tagPaths: const ['数学'],
      );
      final output = ThreadRanker.rank(
        events: [reading, mathTask],
        context: RankContext(
          now: now,
          completions: [
            RankCompletion(
              completedAt: lateNight,
              tagPaths: const ['阅读'],
            ),
          ],
        ),
      );
      final readingRanked =
          output.ready.firstWhere((e) => e.event.id == 'reading').score;
      final mathRanked =
          output.ready.firstWhere((e) => e.event.id == 'math').score;
      expect(readingRanked.fatiguePenalty, greaterThan(0.0));
      expect(mathRanked.fatiguePenalty, 0.0);
      // decay = 1 - 10/60 = 5/6; overlap 1; raw 5/6; norm /2 = 5/12.
      expect(readingRanked.fatiguePenalty, closeTo(5 / 12, 1e-9));
    });

    test('old completions outside the window do not penalize', () {
      final reading = RankEvent(
        id: 'reading',
        title: '阅读',
        dueAt: now.add(const Duration(days: 1)),
        tagPaths: const ['阅读'],
      );
      final output = ThreadRanker.rank(
        events: [reading],
        context: RankContext(
          now: now,
          completions: [
            RankCompletion(
              completedAt:
                  now.subtract(const Duration(minutes: 90)),
              tagPaths: const ['阅读'],
            ),
          ],
        ),
      );
      expect(output.ready.single.score.fatiguePenalty, 0.0);
    });
  });

  group('score decomposition', () {
    test('weights match spec formula', () {
      const score = RankScore(
        urgency: 1,
        goalMatch: 0.5,
        fit: 0.5,
        fatiguePenalty: 0.5,
        total: 0,
      );
      final recomputed = score.urgency * score.weights.urgency +
          score.goalMatch * score.weights.goal +
          score.fit * score.weights.fit -
          score.fatiguePenalty * score.weights.fatigue;
      expect(recomputed, closeTo(0.4 + 0.15 + 0.1 - 0.05, 1e-9));
      expect(FurnaceDefaults.wUrgency + FurnaceDefaults.wGoal +
          FurnaceDefaults.wFit + FurnaceDefaults.wFatigue,
          closeTo(1.0, 1e-9));
    });

    test('every component is exposed with its contribution', () {
      final event = RankEvent(
        id: 'e',
        title: 't',
        estimateMinutes: 30,
        energyRequired: 5,
        dueAt: now.add(const Duration(days: 1)),
        tagPaths: const ['数学'],
      );
      final output = ThreadRanker.rank(
        events: [event],
        context: RankContext(
          now: now,
          energy: 5,
          goal: const RankGoal(text: '数学'),
        ),
      );
      final score = output.ready.single.score;
      expect(score.urgencyContribution,
          closeTo(score.urgency * score.weights.urgency, 1e-12));
      expect(score.goalContribution,
          closeTo(score.goalMatch * score.weights.goal, 1e-12));
      expect(score.fitContribution,
          closeTo(score.fit * score.weights.fit, 1e-12));
      expect(score.fatigueContribution,
          closeTo(-score.fatiguePenalty * score.weights.fatigue, 1e-12));
      // Sub-components of fit are exposed for the property page.
      expect(score.energyFit, 1.0);
      expect(score.windowFit, isNotNull);
      // Weight map is inspectable/editable from the UI.
      expect(score.weights.toMap().keys,
          containsAll(<String>['urgency', 'goal', 'fit', 'fatigue', 'expected']));
    });

    test('custom weights change the ordering (parameters are editable)', () {
      final urgent = RankEvent(
        id: 'urgent',
        title: 'urgent',
        dueAt: now.add(const Duration(hours: 1)),
      );
      final goalMatched = RankEvent(
        id: 'goal',
        title: 'goal',
        dueAt: now.add(const Duration(days: 3)),
        tagPaths: const ['数学'],
      );
      final events = [urgent, goalMatched];
      final goal = const RankGoal(text: '数学');

      final weightOnGoal = ThreadRanker.rank(
        events: events,
        context: RankContext(
          now: now,
          goal: goal,
          weights: const RankWeights(urgency: 0.0, goal: 1.0, fit: 0, fatigue: 0),
        ),
      );
      expect(weightOnGoal.ready.first.event.id, 'goal');

      final weightOnUrgency = ThreadRanker.rank(
        events: events,
        context: RankContext(
          now: now,
          goal: goal,
          weights: const RankWeights(urgency: 1.0, goal: 0.0, fit: 0, fatigue: 0),
        ),
      );
      expect(weightOnUrgency.ready.first.event.id, 'urgent');
    });
  });

  group('deadline-only red constraint (user annotation 16)', () {
    test('expected time near/past is YELLOW, never red', () {
      final event = RankEvent(
        id: 'yellow',
        title: 'yellow',
        estimateMinutes: 30,
        expectedAt: now.subtract(const Duration(minutes: 5)),
        // No deadline at all: nothing can make this red.
      );
      final output = ThreadRanker.rank(
        events: [event],
        context: RankContext(now: now),
      );
      expect(output.insufficient, isEmpty);
      expect(output.overdue, isEmpty);
      final ranked = output.ready.single;
      expect(ranked.expectedNear, isTrue);
      expect(ranked.score.expectedPressure, 1.0);
      expect(ranked.score.expectedContribution, greaterThan(0));
    });

    test('expected time far away is not flagged', () {
      final event = RankEvent(
        id: 'far',
        title: 'far',
        expectedAt: now.add(const Duration(hours: 5)),
      );
      final output = ThreadRanker.rank(
        events: [event],
        context: RankContext(now: now),
      );
      expect(output.ready.single.expectedNear, isFalse);
      expect(output.ready.single.score.expectedPressure, 0.0);
    });

    test('long-forgotten expectation fades back to zero', () {
      final event = RankEvent(
        id: 'stale',
        title: 'stale',
        expectedAt: now.subtract(Duration(
            minutes: FurnaceDefaults.expectedNearWindowMinutes + 400)),
      );
      final output = ThreadRanker.rank(
        events: [event],
        context: RankContext(now: now),
      );
      expect(output.ready.single.score.expectedPressure, 0.0);
    });

    test('passed deadline goes to the overdue bucket, not insufficient', () {
      final event = RankEvent(
        id: 'late',
        title: 'late',
        estimateMinutes: 30,
        dueAt: now.subtract(const Duration(hours: 2)),
      );
      final output = ThreadRanker.rank(
        events: [event],
        context: RankContext(now: now),
      );
      expect(output.overdue.single.event.id, 'late');
      expect(output.overdue.single.overdue, isTrue);
      expect(output.insufficient, isEmpty);
      expect(output.ready, isEmpty);
    });

    test('yellow boost can lift an event above an equal peer', () {
      final yellow = RankEvent(
        id: 'yellow',
        title: 'yellow',
        estimateMinutes: 30,
        expectedAt: now.add(const Duration(minutes: 5)),
      );
      final plain = RankEvent(
        id: 'plain',
        title: 'plain',
        estimateMinutes: 30,
      );
      final output = ThreadRanker.rank(
        events: [plain, yellow],
        context: RankContext(
          now: now,
          weights: const RankWeights(
              urgency: 0, goal: 0, fit: 0, fatigue: 0, expected: 1),
        ),
      );
      expect(output.ready.first.event.id, 'yellow');
      expect(output.ready.first.score.total, greaterThan(0));
      expect(output.ready.last.score.total, 0);
    });
  });
}

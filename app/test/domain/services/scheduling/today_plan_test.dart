import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/cognitive/problem_evaluator.dart';
import 'package:furnace/domain/services/scheduling/today_plan.dart';

/// The plan is a pure function of its inputs - rows and an already-evaluated
/// problem report - so these tests need no database and no clock.
void main() {
  /// Unix-epoch hours, the model's clock (contract §6.1).
  const nowHours = 1000.0;
  const hourMs = 3600000;

  CardState cardOf({
    required String id,
    String? knowledgePointId,
    double? stability = 1,
    double? encodingStrength = 1.0,
    double? lastReviewedHours = 1000,
    int? dueAt = 995000,
    String? unitKey = 'u',
  }) =>
      CardState(
        id: id,
        knowledgePointId: knowledgePointId,
        unitKey: unitKey,
        dueAt: dueAt,
        intervalDays: 1,
        ease: 2.5,
        repetitions: 3,
        lapses: 0,
        state: 'review',
        lastReviewedAt:
            lastReviewedHours == null ? null : (lastReviewedHours * hourMs).round(),
        createdAt: 1,
        updatedAt: 2,
        stability: stability,
        difficulty: 5,
        encodingStrength: encodingStrength,
        savings: 0.8,
        forced: 0,
        forcedStreak: 0,
      );

  ProblemEvaluation pricedProblem(
    String id, {
    required double value,
    String? metric = 'reachability',
    String instruction = 'add_in_edges',
    List<String> kps = const ['kp-1'],
  }) =>
      ProblemEvaluation(
        problemId: id,
        stem: '题干 $id',
        verdict: ProblemVerdict.highValue,
        rankKey: 1.0,
        reason: '值得现在做',
        knowledgePointIds: kps,
        judgedKnowledgePointIds: kps,
        diagnosisByKnowledgePoint: const {},
        counterfactualValue: value,
        counterfactualMetric: metric,
        counterfactualInstruction: instruction,
        counterfactualWhy: '开一条线索',
      );

  ProblemEvaluation unpricedProblem(String id, {String reason = '没有读数'}) =>
      ProblemEvaluation(
        problemId: id,
        stem: '题干 $id',
        verdict: ProblemVerdict.zpd,
        rankKey: 0.6,
        reason: reason,
        knowledgePointIds: const ['kp-1'],
        judgedKnowledgePointIds: const [],
        diagnosisByKnowledgePoint: const {},
      );

  ProblemEvaluationReport reportOf(List<ProblemEvaluation> evaluations) =>
      ProblemEvaluationReport(
        evaluations: evaluations,
        fastLayerRan: true,
        nodesWithoutMs: const <String>[],
      );

  TodayPlan planOf({
    List<CardState> cards = const [],
    List<ProblemEvaluation> problems = const [],
    Map<String, String> names = const {},
    int maxActions = TodayPlanner.kTodayPlanDefaultMaxActions,
  }) =>
      TodayPlanner.build(
        cards: cards,
        problems: reportOf(problems),
        nowHours: nowHours,
        knowledgePointNames: names,
        maxActions: maxActions,
      );

  test('an empty day is an empty plan, and it says the numbers are uncalibrated',
      () {
    final plan = planOf();
    expect(plan.isEmpty, isTrue);
    expect(plan.considered, 0);
    expect(plan.omitted, 0);
    expect(plan.mixesMetrics, isFalse);
    expect(TodayPlan.uncalibrated, isTrue);
    expect(plan.toJson()['uncalibrated'], isTrue);
    expect(plan.toJson()['actions'], isEmpty);
  });

  test('a card you are about to forget is priced in retention gain', () {
    // Reviewed 24 h ago with a 1-day stability: one review buys real retention.
    final card = cardOf(
      id: 'cs-a',
      knowledgePointId: 'kp-physics',
      lastReviewedHours: 976,
    );
    final plan = planOf(
      cards: [card],
      names: const {'kp-physics': '动量守恒'},
    );

    final action = plan.actions.single;
    expect(action.kind, TodayActionKind.review);
    expect(action.id, 'cs-a');
    expect(action.title, '动量守恒');
    expect(action.knowledgePointId, 'kp-physics');
    expect(action.metric, TodayMetric.retention);
    expect(action.priced, isTrue);
    expect(action.gain, greaterThan(0));
    expect(action.cost, TodayPlanner.kTodayPlanCostReview);
    expect(action.value, closeTo(action.gain! / action.cost!, 1e-12));
    expect(action.why, contains('复习这张卡'));
    expect(action.why, contains('多留下'));
    expect(action.dueAtMs, 995000);
  });

  test('a card at its ceiling buys nothing, so it carries no price at all', () {
    // R = R0 = 1.0 and a stability gain of exactly 1: `after == before`.
    final card = cardOf(id: 'cs-ceiling', lastReviewedHours: 1000);
    final plan = planOf(cards: [card], names: const {});

    final action = plan.actions.single;
    expect(action.kind, TodayActionKind.review);
    // Falls back to the unit key when the knowledge point has no name.
    expect(action.title, 'u');
    expect(action.priced, isFalse);
    expect(action.metric, isNull);
    expect(action.value, isNull);
    expect(action.gain, isNull);
    expect(action.why, contains('买不到明天的留存'));
    expect(action.toJson().containsKey('metric'), isFalse);
  });

  test('the gain is ΔR at the horizon, and it is exactly zero at the ceiling',
      () {
    final forgettable = TodayPlanner.retentionGainOf(
      cardOf(id: 'cs-a', lastReviewedHours: 976),
      nowHours: nowHours,
    );
    expect(forgettable.before, lessThan(1.0));
    expect(forgettable.after, greaterThan(forgettable.before));
    expect(forgettable.gain,
        closeTo(forgettable.after - forgettable.before, 1e-12));

    final ceiling = TodayPlanner.retentionGainOf(
      cardOf(id: 'cs-b', lastReviewedHours: 1000),
      nowHours: nowHours,
    );
    // R0 = 1.0, S = legacy_k × R0 = 24 h, t/S = 24/24 = 1 ⇒ both are psi(1) = 0.9
    // exactly (the Q31 measurement, now stated as a test).
    expect(ceiling.before, closeTo(0.9, 1e-12));
    expect(ceiling.after, closeTo(0.9, 1e-12));
    expect(ceiling.gain, 0.0);
  });

  test('a priced problem keeps its metric, and V is gain per unit cost', () {
    final plan = planOf(problems: [
      pricedProblem('p-reach', value: 0.4, metric: 'reachability'),
      pricedProblem(
        'p-retain',
        value: 0.6,
        metric: 'retention',
        instruction: 'strengthen_impression',
      ),
    ]);

    final first = plan.actions.first;
    expect(first.kind, TodayActionKind.practice);
    expect(first.id, 'p-retain');
    expect(first.metric, TodayMetric.retention);
    expect(first.cost, TodayPlanner.kTodayPlanCostReview);
    expect(first.gain, closeTo(0.6, 1e-12));
    expect(first.why, contains('strengthen_impression'));
    expect(first.why, contains('V=0.600'));
    expect(first.title, '题干 p-retain');

    final second = plan.actions[1];
    expect(second.id, 'p-reach');
    expect(second.metric, TodayMetric.reachability);
    expect(second.cost, TodayPlanner.kTodayPlanCostLink);
    expect(second.gain, closeTo(0.4 * TodayPlanner.kTodayPlanCostLink, 1e-12));

    expect(plan.mixesMetrics, isTrue);
  });

  test('a problem with no positive price is a reason, not a price of zero', () {
    final plan = planOf(problems: [
      pricedProblem('p-paid', value: 0.3),
      unpricedProblem('p-free', reason: '这些闪存卡已被另一道更全的题覆盖，重复练习'),
    ]);

    expect(plan.actions.first.id, 'p-paid');
    final free = plan.actions.last;
    expect(free.id, 'p-free');
    expect(free.priced, isFalse);
    expect(free.metric, isNull);
    expect(free.why, '这些闪存卡已被另一道更全的题覆盖，重复练习');
    expect(plan.considered, 2);
  });

  test('priced work leads; unpriced work follows by kind, then due date', () {
    final plan = planOf(
      cards: [
        cardOf(id: 'cs-ceiling-late', lastReviewedHours: 1000, dueAt: 999000),
        cardOf(
          id: 'cs-ceiling-early',
          lastReviewedHours: 1000,
          dueAt: 990000,
        ),
        cardOf(id: 'cs-ceiling-unscheduled', lastReviewedHours: 1000, dueAt: null),
        cardOf(id: 'cs-priced', lastReviewedHours: 976, dueAt: 980000),
      ],
      problems: [
        unpricedProblem('p-free'),
        pricedProblem('p-small', value: 0.1),
      ],
      maxActions: 10,
    );

    expect(plan.actions.map((a) => a.id).toList(), [
      'cs-priced', // priced: the retention gain is positive
      'p-small', // priced: V = 0.1
      'cs-ceiling-early', // unpriced reviews, due date ascending
      'cs-ceiling-late',
      'cs-ceiling-unscheduled', // no date sorts last
      'p-free', // unpriced practices come after unpriced reviews
    ]);
    expect(plan.considered, 6);
    expect(plan.omitted, 0);
  });

  test('the cap keeps the top of the list and reports what it dropped', () {
    final plan = planOf(
      problems: [
        pricedProblem('p-1', value: 0.5),
        pricedProblem('p-2', value: 0.4),
        pricedProblem('p-3', value: 0.3),
        pricedProblem('p-4', value: 0.2),
      ],
      maxActions: 2,
    );

    expect(plan.actions.map((a) => a.id).toList(), ['p-1', 'p-2']);
    expect(plan.considered, 4);
    expect(plan.omitted, 2);
  });

  test('the plan is a function of its inputs, not of their order', () {
    final a = cardOf(id: 'cs-a', lastReviewedHours: 976);
    final b = cardOf(id: 'cs-b', lastReviewedHours: 1000, dueAt: 990000);
    final p1 = pricedProblem('p-1', value: 0.2);
    final p2 = pricedProblem('p-2', value: 0.2);

    final forward = planOf(cards: [a, b], problems: [p1, p2], maxActions: 10);
    final backward = planOf(cards: [b, a], problems: [p2, p1], maxActions: 10);

    expect(
      forward.actions.map((x) => x.id).toList(),
      backward.actions.map((x) => x.id).toList(),
    );
    final ids = forward.actions.map((x) => x.id).toList();
    // Equal prices (p-1 / p-2) fall back to the id, so the order is total.
    expect(ids.indexOf('p-1'), lessThan(ids.indexOf('p-2')));
    // The ceiling card never carries a price, so it is last.
    expect(ids.last, 'cs-b');
    expect(forward.toJson()['considered'], 4);
  });
}

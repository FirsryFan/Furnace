import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/reasoning/capability_action.dart';
import 'package:furnace/domain/services/reasoning/reasoning_prompt.dart';
import 'package:furnace/domain/services/reasoning/stuck_point_evaluator.dart';
import 'package:furnace/domain/services/srs/dsr_memory.dart';

/// 卡点评估的两条纪律（`docs/REASONING_LAYER_DESIGN.md` §5）：
///
///  * 模型先验和**这个学生**的状态读数分别是什么，必须能分开看；
///  * 没有状态数据就是没有，不能被读成「他记得很好」。
void main() {
  ParsedStep step({
    required int index,
    String actionType = 'first_principles',
    double stuckRisk = 0.5,
    List<String> hints = const <String>[],
  }) =>
      ParsedStep(
        index: index,
        goal: '第 $index 步要达成的小目标',
        actionType: actionType,
        action: CapabilityAction.byKey(actionType),
        justification: '为什么成立',
        checkMethod: '',
        stuckRisk: stuckRisk,
        knowledgeHints: hints,
      );

  /// 一个可控的记忆状态：`s` 是稳定度（小时），`d` 是难度（1..10）。
  DsrState state({
    double r0 = 1.0,
    double s = 24,
    double d = 5,
    double lastReview = 0,
  }) =>
      DsrState(
        r0: r0,
        s: s,
        sigma: 0.8,
        d: d,
        lastReview: lastReview,
        initializedAt: 0,
      );

  test('有状态证据时按等权融合，并标记证据存在', () {
    final reading = state(d: 8);
    const modelRisk = 0.4;
    final report = StuckPointEvaluator.evaluate(
      steps: [step(index: 1, stuckRisk: modelRisk, hints: ['二次函数最值'])],
      statesByKnowledgePoint: {'二次函数最值': reading},
      nowHours: 0,
    );

    final only = report.steps.single;
    final expectedStateRisk = StuckPointEvaluator.stateRiskOf(
      reading,
      nowHours: 0,
    );
    expect(only.hasStateEvidence, isTrue);
    expect(only.matchedKnowledgePoints, ['二次函数最值']);
    expect(only.unmatchedHints, isEmpty);
    expect(only.stateRisk, closeTo(expectedStateRisk, 1e-9));
    expect(
      only.fusedRisk,
      closeTo(
        StuckPointEvaluator.modelWeight * modelRisk +
            (1 - StuckPointEvaluator.modelWeight) * expectedStateRisk,
        1e-9,
      ),
    );
    expect(report.evidenceCoverage, 1.0);
  });

  test('没有状态数据时退回模型先验，且不冒充有证据', () {
    final report = StuckPointEvaluator.evaluate(
      steps: [step(index: 1, stuckRisk: 0.42, hints: ['没入过库的知识点'])],
      statesByKnowledgePoint: const <String, DsrState>{},
      nowHours: 0,
    );

    final only = report.steps.single;
    expect(only.hasStateEvidence, isFalse);
    expect(only.stateRisk, isNull);
    expect(only.fusedRisk, closeTo(0.42, 1e-9));
    expect(only.matchedKnowledgePoints, isEmpty);
    expect(only.unmatchedHints, ['没入过库的知识点']);
    expect(report.unmatchedHints, ['没入过库的知识点']);
    expect(report.evidenceCoverage, 0);
    expect(only.suggestion, contains('暂无你的状态数据'));
  });

  test('忘光了 + 高难度 → 高卡点，建议先补这一步', () {
    // lastReview = 0 而 nowHours 很晚，稳定度又低：R 已经很低。
    final forgotten = state(s: 1, d: 10, lastReview: 0);
    final report = StuckPointEvaluator.evaluate(
      steps: [step(index: 1, stuckRisk: 0.9, hints: ['导数单调性'])],
      statesByKnowledgePoint: {'导数单调性': forgotten},
      nowHours: 5000,
    );

    final only = report.steps.single;
    expect(only.stateRisk, greaterThan(0.8));
    expect(
      only.fusedRisk,
      greaterThanOrEqualTo(StuckPointEvaluator.highRiskThreshold),
    );
    expect(only.isHighRisk, isTrue);
    expect(only.suggestion, startsWith('先停下补这一步'));
    expect(only.suggestion, contains('状态读数'));
    expect(report.mostLikely?.index, 1);

    // 同一个遗忘状态会把模型的低先验往上拉：这正是融合存在的意义。
    final lowPrior = StuckPointEvaluator.evaluate(
      steps: [step(index: 1, stuckRisk: 0.2, hints: ['导数单调性'])],
      statesByKnowledgePoint: {'导数单调性': forgotten},
      nowHours: 5000,
    );
    expect(lowPrior.steps.single.fusedRisk, greaterThan(0.2));
    expect(lowPrior.steps.single.fusedRisk, lessThan(only.fusedRisk));
  });

  test('刚复习过 + 低难度 + 模型低风险 → 可以快过', () {
    final fresh = state(s: 240, d: 1, lastReview: 100);
    final report = StuckPointEvaluator.evaluate(
      steps: [step(index: 1, stuckRisk: 0.1, hints: ['集合运算'])],
      statesByKnowledgePoint: {'集合运算': fresh},
      nowHours: 100,
    );

    final only = report.steps.single;
    expect(only.stateRisk, lessThan(0.1));
    expect(only.fusedRisk, lessThan(StuckPointEvaluator.mediumRiskThreshold));
    expect(only.suggestion, startsWith('这一步可以快过'));
  });

  test('同一 R 下难度越高风险越大', () {
    final easy = StuckPointEvaluator.stateRiskOf(
      state(d: 1),
      nowHours: 200,
    );
    final hard = StuckPointEvaluator.stateRiskOf(
      state(d: 10),
      nowHours: 200,
    );
    expect(hard, greaterThan(easy));
  });

  test('提示词两侧空白被 trim 后仍能匹配同一状态', () {
    final report = StuckPointEvaluator.evaluate(
      steps: [
        step(index: 1, hints: ['  二次函数最值  ']),
      ],
      statesByKnowledgePoint: {'二次函数最值': state()},
      nowHours: 0,
    );

    expect(report.steps.single.matchedKnowledgePoints, ['二次函数最值']);
    expect(report.unmatchedHints, isEmpty);
  });

  test('步骤按步号升序返回，mostLikely 平手取更靠前的一步', () {
    final report = StuckPointEvaluator.evaluate(
      steps: [
        step(index: 3, stuckRisk: 0.5),
        step(index: 1, stuckRisk: 0.5),
        step(index: 2, stuckRisk: 0.2),
      ],
      statesByKnowledgePoint: const <String, DsrState>{},
      nowHours: 0,
    );

    expect(report.steps.map((s) => s.index).toList(), [1, 2, 3]);
    expect(report.mostLikely?.index, 1);
    expect(report.byRisk.map((s) => s.index).toList(), [1, 3, 2]);
    expect(report.byRisk.first.fusedRisk, greaterThan(report.byRisk.last.fusedRisk));
  });

  test('全链风险与证据覆盖率按步统计', () {
    final report = StuckPointEvaluator.evaluate(
      steps: [
        step(index: 1, stuckRisk: 0.9, hints: ['已知点']),
        step(index: 2, stuckRisk: 0.1, hints: ['未知点']),
      ],
      statesByKnowledgePoint: <String, DsrState>{
        '已知点': state(),
      },
      nowHours: 0,
    );

    expect(report.steps, hasLength(2));
    expect(report.evidenceCoverage, closeTo(0.5, 1e-9));
    expect(report.overallRisk, report.steps.map((s) => s.fusedRisk).reduce((a, b) => a > b ? a : b));
    expect(report.unmatchedHints, ['未知点']);
    expect(report.toJson()['mostLikelyIndex'], isNotNull);
  });

  test('空链不炸：风险 0、没有最可能卡点', () {
    final report = StuckPointEvaluator.evaluate(
      steps: const <ParsedStep>[],
      statesByKnowledgePoint: const <String, DsrState>{},
      nowHours: 0,
    );

    expect(report.isEmpty, isTrue);
    expect(report.mostLikely, isNull);
    expect(report.overallRisk, 0);
    expect(report.evidenceCoverage, 0);
  });
}

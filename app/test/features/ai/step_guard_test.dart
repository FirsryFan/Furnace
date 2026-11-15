import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/agent_budget.dart';
import 'package:furnace/features/ai/domain/agent_run.dart';
import 'package:furnace/features/ai/domain/step_guard.dart';

/// StepGuard 的判定（STUDENT-MODE-AND-AGENT-LOOP-DESIGN §7.2）：
/// 周期、重复动作、状态指纹/无进展、预算、answer reserve。
///
/// 每个用例只锁一条规则，并且给其它规则「不成立」的输入（指纹各不同、动作各
/// 不同），这样失败时能立刻看出是哪条规则误报。
void main() {
  AgentRunState makeRun({
    int steps = 0,
    AgentPhase phase = AgentPhase.solve,
    int? reasoningTokens,
    int completionTokens = 0,
  }) {
    return AgentRunState(
      id: 'run-1',
      conversationId: 'conv-1',
      presetId: 'student_solver',
      mode: AgentMode.student,
      startedAt: 0,
      phase: phase,
      steps: steps,
      reasoningTokens: reasoningTokens,
      completionTokens: completionTokens,
    );
  }

  group('预算', () {
    test('步数用完 -> stop(maxSteps)', () {
      final guard = StepGuard(budget: RunBudget.chat);
      final decision = guard.check(
        run: makeRun(steps: RunBudget.chat.maxSteps),
        actionKey: 'start',
        stateFingerprint: 'fp-1',
        nowMs: 1000,
      );
      expect(decision.action, StepGuardAction.stop);
      expect(decision.reason, StopReason.maxSteps);
      expect(decision.message, isNotNull);
    });

    test('reasoning 到 70% -> forceAnswer(reasoningBudget)', () {
      final guard = StepGuard(budget: RunBudget.student);
      // 20000 * 0.7 = 14000，正好到阈值。
      final decision = guard.check(
        run: makeRun(reasoningTokens: 14000),
        actionKey: 'think',
        stateFingerprint: 'fp-1',
        nowMs: 1000,
      );
      expect(decision.action, StepGuardAction.forceAnswer);
      expect(decision.reason, StopReason.reasoningBudget);
    });

    test('reasoning 未到阈值 -> proceed', () {
      final guard = StepGuard(budget: RunBudget.student);
      final decision = guard.check(
        run: makeRun(reasoningTokens: 13999),
        actionKey: 'think',
        stateFingerprint: 'fp-1',
        nowMs: 1000,
      );
      expect(decision.action, StepGuardAction.proceed);
      expect(decision.reason, isNull);
    });

    test('answer reserve 见底 -> stop(answerReserve)', () {
      final guard = StepGuard(budget: RunBudget.student);
      // 23000 - 20001 = 2999 < 3000 reserve。
      final decision = guard.check(
        run: makeRun(completionTokens: 20001),
        actionKey: 'think',
        stateFingerprint: 'fp-1',
        nowMs: 1000,
      );
      expect(decision.action, StepGuardAction.stop);
      expect(decision.reason, StopReason.answerReserve);
    });

    test('RunBudget.student 的数字就是设计文档里的 20k + 3k / 1 repair', () {
      expect(RunBudget.student.maxReasoningTokens, 20000);
      expect(RunBudget.student.answerReserveTokens, 3000);
      expect(RunBudget.student.maxRepair, 1);
      expect(RunBudget.student.maxVerifierCalls, 1);
      expect(RunBudget.student.forceAnswerAtReasoningTokens, 14000);
      expect(RunBudget.chat.forceAnswerAtReasoningTokens, isNull);
    });
  });

  group('重复动作', () {
    test('同一 actionKey 在窗口里出现三次 -> forceAnswer(repeatedAction)', () {
      final guard = StepGuard(budget: RunBudget.chat);
      final run = makeRun();

      StepGuardDecision check(int step) => guard.check(
            run: run,
            actionKey: 'tool:search:abc',
            // 指纹各不相同：不是「无进展」，只是同一个动作反复做。
            stateFingerprint: 'fp-$step',
            nowMs: 1000 + step,
          );

      expect(check(1).action, StepGuardAction.proceed);
      expect(check(2).action, StepGuardAction.proceed);
      final third = check(3);
      expect(third.action, StepGuardAction.forceAnswer);
      expect(third.reason, StopReason.repeatedAction);
    });
  });

  group('周期', () {
    final cycle = ['A', 'B', 'C', 'A', 'B', 'C'];

    test('ABCABC -> forceAnswer(cycleDetected)', () {
      final guard = StepGuard(budget: RunBudget.chat);
      final run = makeRun();
      StepGuardDecision? decision;
      for (var index = 0; index < cycle.length; index++) {
        decision = guard.check(
          run: run,
          actionKey: cycle[index],
          stateFingerprint: 'fp-$index',
          nowMs: 1000 + index,
        );
      }
      expect(decision!.action, StepGuardAction.forceAnswer);
      expect(decision.reason, StopReason.cycleDetected);
    });

    test('验证阶段出现周期且有 repair 预算 -> repair', () {
      final guard = StepGuard(budget: RunBudget.student);
      final run = makeRun(phase: AgentPhase.verify);
      StepGuardDecision? decision;
      for (var index = 0; index < cycle.length; index++) {
        decision = guard.check(
          run: run,
          actionKey: cycle[index],
          stateFingerprint: 'fp-$index',
          nowMs: 1000 + index,
          repairsUsed: 0,
        );
      }
      expect(decision!.action, StepGuardAction.repair);
      expect(decision.reason, StopReason.cycleDetected);
    });

    test('验证阶段出现周期但 repair 已用尽 -> forceAnswer', () {
      final guard = StepGuard(budget: RunBudget.student);
      final run = makeRun(phase: AgentPhase.verify);
      StepGuardDecision? decision;
      for (var index = 0; index < cycle.length; index++) {
        decision = guard.check(
          run: run,
          actionKey: cycle[index],
          stateFingerprint: 'fp-$index',
          nowMs: 1000 + index,
          repairsUsed: 1,
        );
      }
      expect(decision!.action, StepGuardAction.forceAnswer);
      expect(decision.reason, StopReason.cycleDetected);
    });
  });

  group('状态指纹 / 无进展', () {
    test('指纹连续三步不变 -> forceAnswer(noProgress)', () {
      final guard = StepGuard(budget: RunBudget.chat);
      final run = makeRun();

      StepGuardDecision check(String action, int step) => guard.check(
            run: run,
            actionKey: action,
            stateFingerprint: 'same-fp',
            nowMs: 1000 + step,
          );

      expect(check('A', 1).action, StepGuardAction.proceed);
      expect(check('B', 2).action, StepGuardAction.proceed);
      final third = check('C', 3);
      expect(third.action, StepGuardAction.forceAnswer);
      expect(third.reason, StopReason.noProgress);
    });

    test('指纹变了就重新计数', () {
      final guard = StepGuard(budget: RunBudget.chat);
      final run = makeRun();

      expect(
        guard
            .check(
              run: run,
              actionKey: 'A',
              stateFingerprint: 'fp-1',
              nowMs: 1000,
            )
            .isProceed,
        isTrue,
      );
      expect(
        guard
            .check(
              run: run,
              actionKey: 'B',
              stateFingerprint: 'fp-1',
              nowMs: 1001,
            )
            .isProceed,
        isTrue,
      );
      // 状态推进了：连续计数被重置，这一步不能判无进展。
      expect(
        guard
            .check(
              run: run,
              actionKey: 'C',
              stateFingerprint: 'fp-2',
              nowMs: 1002,
            )
            .isProceed,
        isTrue,
      );
      expect(guard.sameFingerprintStreak, 1);
    });

    test('reset 清空历史', () {
      final guard = StepGuard(budget: RunBudget.chat);
      guard.check(
        run: makeRun(),
        actionKey: 'A',
        stateFingerprint: 'fp-1',
        nowMs: 1000,
      );
      expect(guard.recentActions, isNotEmpty);
      guard.reset();
      expect(guard.recentActions, isEmpty);
      expect(guard.recentFingerprints, isEmpty);
    });
  });

  group('actionKey / fingerprint 的稳定性', () {
    test('参数键顺序不影响动作键', () {
      final first = AgentActionKey.ofTool('question', {'b': 2, 'a': 1});
      final second = AgentActionKey.ofTool('question', {'a': 1, 'b': 2});
      expect(first, second);
      expect(
        AgentActionKey.ofTool('question', {'a': 1, 'b': 3}),
        isNot(first),
      );
    });

    test('模型步骤按 kind + phase 区分', () {
      final solve = AgentActionKey.ofStep(AgentStepKind.model,
          phase: AgentPhase.solve);
      final answer = AgentActionKey.ofStep(AgentStepKind.model,
          phase: AgentPhase.answer);
      expect(solve, isNot(answer));
      expect(
        AgentActionKey.ofStep(AgentStepKind.model, phase: AgentPhase.solve),
        solve,
      );
    });

    test('状态映射的指纹与键顺序无关，与值有关', () {
      final a = AgentStateFingerprint.of({'x': 1, 'y': 'done'});
      final b = AgentStateFingerprint.of({'y': 'done', 'x': 1});
      final c = AgentStateFingerprint.of({'y': 'open', 'x': 1});
      expect(a, b);
      expect(a, isNot(c));
      expect(a, hasLength(8));
    });

    test('空 actionKey / 空指纹是调用方错误', () {
      final guard = StepGuard(budget: RunBudget.chat);
      expect(
        () => guard.check(
          run: makeRun(),
          actionKey: '',
          stateFingerprint: 'fp',
          nowMs: 1000,
        ),
        throwsArgumentError,
      );
      expect(
        () => guard.check(
          run: makeRun(),
          actionKey: 'A',
          stateFingerprint: '   ',
          nowMs: 1000,
        ),
        throwsArgumentError,
      );
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/agent_run.dart';
import 'package:furnace/features/ai/domain/claim.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart';
import 'package:furnace/features/ai/domain/process_auditor.dart';
import 'package:furnace/features/ai/domain/student_answer_sheet.dart';
import 'package:furnace/features/ai/domain/student_run.dart';
import 'package:furnace/features/ai/domain/student_shadow_verification.dart';
import 'package:furnace/features/ai/domain/verification_pipeline.dart';
import 'package:furnace/features/ai/domain/verifier.dart';
import 'package:furnace/features/ai/infrastructure/fake_model_adapter.dart';

/// Task-32：StudentRun 的 **shadow** 预检接线。
///
/// 锁住的契约：
///  * 默认 null 时旧行为不变（结果字段为 null、不跑 shadow）；
///  * run 结束跑确定性 precheck：clean 才产生 CheckerHandoff（但**不交给**
///    Checker、checkerRounds = 0）；invalid/unknown/解析失败只产生
///    SolverClarificationRequest，不产生 handoff；
///  * 交付原样：stage / verdict / verified / answer / repair 次数 / 验证调用次数
///    与 step/DB 落库都和没有 shadow 时一致；
///  * shadow 抛错被隔离（只记 shadowVerificationError），不改变 run 结论。
void main() {
  const question = 'Q15 斜面与物块。（1）求 F；（2）求 m_2/m_1 的所有可能值；'
      '（3）求 E 的范围（单位 J）';
  const cleanAnswer = '（1）F=m_1 g \\tan\\theta；（2）m_2/m_1\\leq 1 或 7；'
      '（3）17/2\\leq E\\leq 12 J';
  const cleanProcess = '整理：E 的范围用区间表示，端点 17/2 与 12 都要保留。';
  const cleanReasoning = '设物块质量 m_1，斜面倾角 \\theta，重力加速度 g。\n\n'
      '由向心力公式得 F=m_1 g \\tan\\theta。\n\n'
      '当 m_2/m_1=7 时，静摩擦达到临界。\n\n'
      '所以 m_2/m_1\\leq 1 或 7。\n\n'
      '由动能定理得 17/2\\leq E\\leq 12，单位 J。';

  List<ModelEvent> answerTurn(
    String answer, {
    String reasoning = '',
    String process = cleanProcess,
  }) =>
      [
        if (reasoning.isNotEmpty) ModelReasoningDelta(reasoning),
        ModelTextDelta('【题型】解答题\n【答案】$answer\n【过程】$process'),
        const ModelTurnDone(
          finishReason: 'stop',
          promptTokens: 100,
          completionTokens: 50,
        ),
      ];

  List<ModelEvent> emptyTurn({String reasoning = ''}) => [
        if (reasoning.isNotEmpty) ModelReasoningDelta(reasoning),
        const ModelTurnDone(finishReason: 'stop'),
      ];

  StudentRun buildRun({
    required ModelAdapter reason,
    ModelAdapter? answer,
    ModelAdapter? repair,
    Verifier? verifier,
    StudentProcessAuditSource? auditor,
    StudentShadowVerification? shadow,
    StudentRunRecorder? recorder,
  }) {
    return StudentRun(
      reasonAdapter: reason,
      answerAdapter: answer,
      repairAdapter: repair,
      verifier: verifier,
      processAuditor: auditor,
      recorder: recorder,
      shadowVerifier: shadow,
      now: () => 1000,
    );
  }

  Future<StudentRunResult> execute(StudentRun run) => run.execute(
        runId: 'run-1',
        conversationId: 'conv-1',
        question: question,
        startedAt: 1000,
      );

  Claim sampleClaim() => Claim(
        id: 'claim-abc',
        kind: ClaimKind.equation,
        canonical: 'm_2/m_1=7',
        statement: '当 m_2/m_1=7 时临界',
        status: ClaimStatus.proposed,
        createdAtMs: 0,
      );

  group('默认 null：旧行为不变', () {
    test('没注入 shadow：结果字段为 null，交付照旧', () async {
      final run = buildRun(
        reason: FakeModelAdapter([
          answerTurn(cleanAnswer, reasoning: cleanReasoning),
        ]),
        verifier: _ScriptedVerifier([Verification.pass()]),
        auditor: _RecordingAuditor(),
      );

      final result = await execute(run);

      expect(result.shadowVerification, isNull);
      expect(result.shadowVerificationError, isNull);
      expect(result.stage, StudentRunStage.finalized);
      expect(result.verdict, Verdict.pass);
      expect(result.verified, isTrue);
    });

    test('注入 shadow 不改变交付、repair、验证次数与落库', () async {
      Future<(StudentRunResult, _RecordingRecorder, FakeModelAdapter)> runOnce(
        StudentShadowVerification? shadow,
      ) async {
        final reason = FakeModelAdapter([
          answerTurn(cleanAnswer, reasoning: cleanReasoning),
        ]);
        final recorder = _RecordingRecorder();
        final result = await execute(buildRun(
          reason: reason,
          verifier: _ScriptedVerifier([Verification.pass()]),
          auditor: _RecordingAuditor(claims: [sampleClaim()]),
          shadow: shadow,
          recorder: recorder,
        ));
        return (result, recorder, reason);
      }

      final (baseline, baselineRecorder, baselineReason) = await runOnce(null);
      final (shadowed, shadowedRecorder, shadowedReason) = await runOnce(
        const DeterministicShadowVerification(),
      );

      // 交付字段逐项相同。
      expect(shadowed.stage, baseline.stage);
      expect(shadowed.stages, baseline.stages);
      expect(shadowed.verdict, baseline.verdict);
      expect(shadowed.verified, baseline.verified);
      expect(shadowed.unverified, baseline.unverified);
      expect(shadowed.answerSheet.result, baseline.answerSheet.result);
      expect(shadowed.answerSheet.process, baseline.answerSheet.process);
      expect(shadowed.repairCount, baseline.repairCount);
      expect(shadowed.verifierCalls, baseline.verifierCalls);
      expect(shadowed.run.status, baseline.run.status);
      expect(shadowed.run.stopReason, baseline.run.stopReason);
      expect(shadowed.run.verifierVerdict, baseline.run.verifierVerdict);
      expect(shadowed.error, baseline.error);
      // 模型调用次数完全相同（shadow 零模型调用）。
      expect(shadowedReason.requests, hasLength(baselineReason.requests.length));
      expect(shadowedReason.requests, hasLength(1));
      // 落库同样是 run / steps / process / content，shadow 不额外写任何行。
      expect(shadowedRecorder.runs, hasLength(baselineRecorder.runs.length));
      expect(
        shadowedRecorder.steps.map((step) => step.kind),
        baselineRecorder.steps.map((step) => step.kind),
      );
      expect(shadowedRecorder.steps, hasLength(3));
      expect(shadowedRecorder.processAudits,
          hasLength(baselineRecorder.processAudits.length));
      expect(shadowedRecorder.contentVerifications,
          hasLength(baselineRecorder.contentVerifications.length));
      expect(shadowedRecorder.claimsSaves,
          hasLength(baselineRecorder.claimsSaves.length));
      // 两种 run 的 stage 路径都是 solve -> audit -> verify -> finalize。
      expect(shadowed.stages, [
        StudentRunStage.solving,
        StudentRunStage.auditing,
        StudentRunStage.verifying,
        StudentRunStage.finalized,
      ]);
    });

    test('failed run（没有答案）：shadow 不改变失败终态，也不产生 handoff', () async {
      final result = await execute(buildRun(
        reason: FakeModelAdapter([emptyTurn()]),
        answer: FakeModelAdapter([emptyTurn()]),
        shadow: const DeterministicShadowVerification(),
      ));

      expect(result.stage, StudentRunStage.failed);
      expect(result.answered, isFalse);
      expect(result.verdict, Verdict.unknown);
      expect(result.run.status, AgentRunStatus.failed);
      // 没有可交付答案时，shadow 允许记录 invalid/unknown，但绝无 handoff。
      expect(result.shadowVerification?.handoff, isNull);
    });
  });

  group('clean：产生 CheckerHandoff，但不交给 Checker', () {
    test('clean 预检 -> awaitingChecker + handoff，交付原样', () async {
      final recorder = _RecordingRecorder();
      final result = await execute(buildRun(
        reason: FakeModelAdapter([
          answerTurn(cleanAnswer, reasoning: cleanReasoning),
        ]),
        verifier: _ScriptedVerifier([Verification.pass()]),
        auditor: _RecordingAuditor(claims: [sampleClaim()]),
        shadow: const DeterministicShadowVerification(),
        recorder: recorder,
      ));

      final shadow = result.shadowVerification;
      expect(shadow, isNotNull);
      expect(shadow!.status, VerificationPipelineStatus.awaitingChecker);
      expect(shadow.isTerminal, isFalse);
      expect(shadow.deliveryStatus, isNull);
      // shadow 只跑 precheck：没有 checker 报告，也不生成 delivery。
      expect(shadow.checkerRounds, 0);
      expect(shadow.delivery, isNull);

      final handoff = shadow.handoff;
      expect(handoff, isNotNull);
      expect(handoff!.frozenAnswer, result.answerSheet.result);
      expect(handoff.frozenAnswer, cleanAnswer);
      expect(handoff.sourceRunId, 'run-1');
      expect(handoff.sourceTraceRef, 'student_run:run-1/reasoning');
      expect(handoff.processedSteps, isNotEmpty);
      expect(handoff.claims.single.canonical, 'm_2/m_1=7');
      expect(handoff.verifyContentHash(), isTrue);

      // 交付没有被 shadow 改写。
      expect(result.stage, StudentRunStage.finalized);
      expect(result.verdict, Verdict.pass);
      expect(result.verified, isTrue);
      expect(result.answerSheet.result, cleanAnswer);
      // 落库仍是旧路径的 3 条 step（model + process audit + content verify）。
      expect(recorder.steps.map((step) => step.kind), [
        AgentStepKind.model,
        AgentStepKind.verify,
        AgentStepKind.verify,
      ]);
    });

    test('shadow 实现结构上不接模型、不接 Checker（零调用）', () {
      final source = File(
        'lib/features/ai/domain/student_shadow_verification.dart',
      ).readAsStringSync();
      // 不 import 模型 adapter / infrastructure，也没有模型回合调用入口。
      expect(source.contains("import 'model_adapter.dart'"), isFalse);
      expect(source.contains("import '../infrastructure/"), isFalse);
      expect(source.contains('runTurn('), isFalse);
      // handoff 只经由 VerificationPipeline.screen 构造，shadow 不自己建。
      expect(source.contains('CheckerHandoff.fromPrecheck('), isFalse);
    });
  });

  group('invalid / unknown：不产生 handoff，只回 solver', () {
    Future<StudentRunResult> runWith({
      required List<ModelEvent> turn,
      required DeterministicShadowVerification shadow,
    }) {
      return execute(buildRun(
        reason: FakeModelAdapter([turn]),
        verifier: _ScriptedVerifier([Verification.pass()]),
        shadow: shadow,
      ));
    }

    test('invalid（缺小问答案）-> solverRevisionRequired + clarification', () async {
      final result = await runWith(
        turn: answerTurn(
          '（1）F=m_1 g \\tan\\theta；（3）17/2\\leq E\\leq 12 J',
          reasoning: cleanReasoning,
        ),
        shadow: const DeterministicShadowVerification(),
      );

      final shadow = result.shadowVerification;
      expect(shadow, isNotNull);
      expect(shadow!.status, VerificationPipelineStatus.solverRevisionRequired);
      expect(shadow.handoff, isNull);
      expect(shadow.clarification, isNotNull);
      expect(shadow.clarification!.questions, isNotEmpty);
      expect(shadow.delivery, isNull);
      // 交付原样（内容验证 pass，shadow invalid 不改 verdict）。
      expect(result.stage, StudentRunStage.finalized);
      expect(result.verdict, Verdict.pass);
      expect(result.verified, isTrue);
    });

    test('unknown（trace 解析失败）-> solverClarificationRequired，无 handoff',
        () async {
      final result = await runWith(
        turn: answerTurn('某答案', process: ''),
        shadow: const DeterministicShadowVerification(),
      );

      final shadow = result.shadowVerification;
      expect(shadow, isNotNull);
      expect(
          shadow!.status, VerificationPipelineStatus.solverClarificationRequired);
      expect(shadow.handoff, isNull);
      expect(shadow.clarification, isNotNull);
      expect(shadow.clarification!.reason, contains('无法解析'));
      expect(result.stage, StudentRunStage.finalized);
      expect(result.verdict, Verdict.pass);
      expect(result.answerSheet.result, '某答案');
    });

    test('unknown（抽不到 claim）-> 不生成 handoff', () async {
      final result = await runWith(
        turn: answerTurn(
          '（1）1；（2）2；（3）3',
          reasoning: '先读题。\n\n再想想。',
          process: '',
        ),
        shadow: const DeterministicShadowVerification(),
      );

      final shadow = result.shadowVerification;
      expect(shadow, isNotNull);
      expect(
          shadow!.status, VerificationPipelineStatus.solverClarificationRequired);
      expect(shadow.handoff, isNull);
      expect(shadow.clarification, isNotNull);
      expect(result.stage, StudentRunStage.finalized);
      expect(result.verdict, Verdict.pass);
      expect(result.answerSheet.result, contains('（1）1'));
    });
  });

  group('fake 注入与异常隔离', () {
    test('shadow 拿到 run 的最终 reasoning/answer/claims，且只调用一次', () async {
      final recorder = _RecordingShadowVerification();
      final result = await execute(buildRun(
        reason: FakeModelAdapter([
          answerTurn(cleanAnswer, reasoning: 'SECRET-COT $cleanReasoning'),
        ]),
        verifier: _ScriptedVerifier([Verification.pass()]),
        auditor: _RecordingAuditor(claims: [sampleClaim()]),
        shadow: recorder,
      ));

      expect(recorder.calls, hasLength(1));
      final call = recorder.calls.single;
      expect(call.runId, 'run-1');
      expect(call.question, question);
      expect(call.frozenAnswer, result.answerSheet.result);
      expect(call.frozenAnswer, cleanAnswer);
      expect(call.rawReasoning, contains('SECRET-COT'));
      expect(call.processText, result.answerSheet.process);
      expect(call.claims.single.canonical, 'm_2/m_1=7');
      // 结果透传，交付仍原样。
      expect(result.shadowVerification, isNotNull);
      expect(
          result.shadowVerification!.status,
          VerificationPipelineStatus
              .awaitingChecker);
    });

    test('shadow 抛错被隔离：不改变 stage/verdict/answer，只记录错误', () async {
      final result = await execute(buildRun(
        reason: FakeModelAdapter([
          answerTurn(cleanAnswer, reasoning: cleanReasoning),
        ]),
        verifier: _ScriptedVerifier([Verification.pass()]),
        auditor: _RecordingAuditor(),
        shadow: _ThrowingShadowVerification(),
      ));

      expect(result.shadowVerification, isNull);
      expect(result.shadowVerificationError, contains('shadow exploded'));
      // 交付字段与没有 shadow 时相同：错误不写进 run 的 error。
      expect(result.stage, StudentRunStage.finalized);
      expect(result.verdict, Verdict.pass);
      expect(result.verified, isTrue);
      expect(result.answerSheet.result, cleanAnswer);
      expect(result.error, isNull);
      expect(result.run.status, AgentRunStatus.answered);
    });
  });
}

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _ShadowCall {
  const _ShadowCall({
    required this.runId,
    required this.question,
    required this.frozenAnswer,
    required this.rawReasoning,
    required this.processText,
    required this.claims,
  });

  final String runId;
  final String question;
  final String frozenAnswer;
  final String rawReasoning;
  final String processText;
  final List<Claim> claims;
}

class _RecordingShadowVerification implements StudentShadowVerification {
  final List<_ShadowCall> calls = [];
  final StudentShadowVerification _delegate = const DeterministicShadowVerification();

  @override
  VerificationPipelineResult verify({
    required String runId,
    required String question,
    required String frozenAnswer,
    required String rawReasoning,
    required String processText,
    List<Claim> claims = const <Claim>[],
  }) {
    calls.add(_ShadowCall(
      runId: runId,
      question: question,
      frozenAnswer: frozenAnswer,
      rawReasoning: rawReasoning,
      processText: processText,
      claims: claims,
    ));
    return _delegate.verify(
      runId: runId,
      question: question,
      frozenAnswer: frozenAnswer,
      rawReasoning: rawReasoning,
      processText: processText,
      claims: claims,
    );
  }
}

class _ThrowingShadowVerification implements StudentShadowVerification {
  @override
  VerificationPipelineResult verify({
    required String runId,
    required String question,
    required String frozenAnswer,
    required String rawReasoning,
    required String processText,
    List<Claim> claims = const <Claim>[],
  }) {
    throw StateError('shadow exploded');
  }
}

class _ScriptedVerifier implements Verifier {
  _ScriptedVerifier(this._results);

  final List<Verification> _results;
  final List<Verification> calls = [];
  int _index = 0;

  @override
  String get id => 'scripted_verifier';

  @override
  VerifierKind get kind => VerifierKind.content;

  @override
  Future<Verification> verify({
    required String question,
    required StudentAnswerSheet answer,
    List<ChatImagePart> images = const [],
    required ClaimSummary claims,
  }) async {
    final result =
        _results[_index < _results.length ? _index : _results.length - 1];
    _index += 1;
    calls.add(result);
    return result;
  }
}

class _ClaimsSave {
  const _ClaimsSave(this.runId, this.claims);

  final String runId;
  final List<Claim> claims;
}

class _RecordingAuditor implements StudentProcessAuditSource {
  _RecordingAuditor({List<Claim> claims = const <Claim>[]})
      : _claims = claims;

  final List<Claim> _claims;

  @override
  Future<StudentProcessAuditResult> audit({
    required String reasoning,
    String? previousReasoning,
    List<String> actionSequence = const [],
    String? stateFingerprint,
    String? previousStateFingerprint,
  }) async {
    return StudentProcessAuditResult(
      report: ProcessReport.clean,
      claimSummary: ClaimSummary(claims: _claims),
      claims: _claims,
    );
  }
}

class _RecordingRecorder implements StudentRunRecorder {
  final List<AgentRunState> runs = [];
  final List<AgentStep> steps = [];
  final List<ProcessReport> processAudits = [];
  final List<Verification> contentVerifications = [];
  final List<_ClaimsSave> claimsSaves = [];

  @override
  Future<void> saveRun(AgentRunState run) async {
    runs.add(run);
  }

  @override
  Future<void> appendStep(AgentStep step) async {
    steps.add(step);
  }

  @override
  Future<String> saveProcessAudit({
    required String runId,
    required ProcessReport report,
  }) async {
    processAudits.add(report);
    return 'verify-process-${processAudits.length}';
  }

  @override
  Future<String> saveContentVerification({
    required String runId,
    required String verifierId,
    required Verification verification,
  }) async {
    contentVerifications.add(verification);
    return 'verify-content-${contentVerifications.length}';
  }

  @override
  Future<void> saveClaims({
    required String runId,
    required List<Claim> claims,
  }) async {
    claimsSaves.add(_ClaimsSave(runId, claims));
  }
}

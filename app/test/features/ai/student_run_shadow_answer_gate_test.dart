import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/answer_gate.dart';
import 'package:furnace/features/ai/domain/agent_run.dart';
import 'package:furnace/features/ai/domain/checkpoint.dart';
import 'package:furnace/features/ai/domain/claim.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart';
import 'package:furnace/features/ai/domain/process_auditor.dart';
import 'package:furnace/features/ai/domain/student_answer_sheet.dart';
import 'package:furnace/features/ai/domain/student_run.dart';
import 'package:furnace/features/ai/domain/verifier.dart';
import 'package:furnace/features/ai/infrastructure/fake_model_adapter.dart';

/// Task-41：StudentRun 的 **shadow AnswerGate** 接线。
///
/// 锁住的契约：
///  * 默认 null 时旧行为不变（字段 null、不跑 gate）；
///  * 注入 `DeterministicAnswerGate` 后，run 结束时对最终答案卡跑一次确定性
///    锚点检查，结果记录 checked/skipped/issues/verdict 到
///    `StudentRunResult.shadowAnswerGate`；
///  * 交付原样：stage / verdict / verified / answer / repair / 验证次数 / 落库
///    都与没有 gate 时一致；gate 的 fail/unknown 不会改答案、不触发 repair；
///  * pass / fail / unknown / 跳过与缺失检查点 / Q15 教师 checkpoint 样例
///    （样例仅在本测试里，不进生产）。
void main() {
  const question = 'Q15 斜面与物块。（1）求 F；（2）求 m_2/m_1 的所有可能值；'
      '（3）求 E 的范围（单位 J）';
  const cleanAnswer = '（1）F=m_1 g \\tan\\theta；（2）m_2/m_1\\leq 1 或 7；'
      '（3）17/2\\leq E\\leq 12 J';
  const cleanProcess = '由牛顿第二定律得必要步骤。';

  List<ModelEvent> answerTurn(String answer) => [
        ModelTextDelta('【题型】解答题\n【答案】$answer\n【过程】$cleanProcess'),
        const ModelTurnDone(
          finishReason: 'stop',
          promptTokens: 100,
          completionTokens: 50,
        ),
      ];

  StudentRun buildRun({
    required ModelAdapter reason,
    DeterministicAnswerGate? answerGate,
    Verifier? verifier,
    StudentRunRecorder? recorder,
    StudentProcessAuditSource? auditor,
  }) {
    return StudentRun(
      reasonAdapter: reason,
      answerGate: answerGate,
      verifier: verifier,
      recorder: recorder,
      processAuditor: auditor ?? _RecordingAuditor(),
      now: () => 1000,
    );
  }

  Future<StudentRunResult> execute(StudentRun run) => run.execute(
        runId: 'run-1',
        conversationId: 'conv-1',
        question: question,
        startedAt: 1000,
      );

  Checkpoint required(
    String id,
    String label,
    List<String> acceptable, {
    CheckpointConstraintKind kind = CheckpointConstraintKind.symbolic,
  }) =>
      Checkpoint(
        id: id,
        label: label,
        kind: CheckpointKind.relation,
        scope: CheckpointScope.required,
        constraints: [
          CheckpointConstraint(
            kind: kind,
            acceptable: acceptable,
            description: label,
          ),
        ],
      );

  DeterministicAnswerGate gateWith(List<Checkpoint> checkpoints) =>
      DeterministicAnswerGate(
        checkpoints: CheckpointSet(checkpoints: checkpoints),
      );

  group('默认 null：旧行为不变', () {
    test('没注入 gate：结果字段为 null，交付照旧', () async {
      final result = await execute(buildRun(
        reason: FakeModelAdapter([answerTurn(cleanAnswer)]),
        verifier: _ScriptedVerifier([Verification.pass()]),
      ));

      expect(result.shadowAnswerGate, isNull);
      expect(result.shadowAnswerGateError, isNull);
      expect(result.stage, StudentRunStage.finalized);
      expect(result.verdict, Verdict.pass);
      expect(result.verified, isTrue);
    });

    test('注入 gate 不改变交付、repair、验证次数与落库（与无 gate 对比）',
        () async {
      final gate = gateWith([
        required('q15-branch-a', 'm2/m1 轨道支', ['m2m1<=1']),
        required('q15-branch-b', 'm2/m1 的 7 分支', ['或7']),
      ]);

      Future<(StudentRunResult, _RecordingRecorder, FakeModelAdapter)> runOnce(
        DeterministicAnswerGate? answerGate,
      ) async {
        final reason = FakeModelAdapter([answerTurn(cleanAnswer)]);
        final recorder = _RecordingRecorder();
        final result = await execute(buildRun(
          reason: reason,
          answerGate: answerGate,
          verifier: _ScriptedVerifier([Verification.pass()]),
          recorder: recorder,
        ));
        return (result, recorder, reason);
      }

      final (baseline, baselineRecorder, baselineReason) = await runOnce(null);
      final (gated, gatedRecorder, gatedReason) = await runOnce(gate);

      expect(gated.stage, baseline.stage);
      expect(gated.stages, baseline.stages);
      expect(gated.verdict, baseline.verdict);
      expect(gated.verified, baseline.verified);
      expect(gated.unverified, baseline.unverified);
      expect(gated.answerSheet.result, baseline.answerSheet.result);
      expect(gated.answerSheet.process, baseline.answerSheet.process);
      expect(gated.repairCount, baseline.repairCount);
      expect(gated.verifierCalls, baseline.verifierCalls);
      expect(gated.run.status, baseline.run.status);
      expect(gated.run.stopReason, baseline.run.stopReason);
      expect(gated.error, baseline.error);
      // gate 零模型调用；没有额外 DB 行。
      expect(gatedReason.requests, hasLength(baselineReason.requests.length));
      expect(gatedReason.requests, hasLength(1));
      expect(gatedRecorder.runs, hasLength(baselineRecorder.runs.length));
      expect(
        gatedRecorder.steps.map((step) => step.kind),
        baselineRecorder.steps.map((step) => step.kind),
      );
      expect(gatedRecorder.steps, hasLength(3));
      expect(gatedRecorder.processAudits,
          hasLength(baselineRecorder.processAudits.length));
      expect(gatedRecorder.contentVerifications,
          hasLength(baselineRecorder.contentVerifications.length));
      expect(gatedRecorder.claimsSaves,
          hasLength(baselineRecorder.claimsSaves.length));
    });
  });

  group('pass', () {
    test('required 锚点全部满足 -> pass，checked 计数正确，交付不变', () async {
      final gate = gateWith([
        required('q15-force', 'F 的表达式', ['m1gtantheta']),
        required('q15-branch-a', 'm2/m1 轨道支', ['m2m1<=1']),
        required('q15-branch-b', 'm2/m1 的 7 分支', ['或7']),
        required(
          'q15-energy',
          'E 的区间',
          ['172', '12'],
          kind: CheckpointConstraintKind.interval,
        ),
      ]);
      final result = await execute(buildRun(
        reason: FakeModelAdapter([answerTurn(cleanAnswer)]),
        answerGate: gate,
        verifier: _ScriptedVerifier([Verification.pass()]),
      ));

      final gateResult = result.shadowAnswerGate;
      expect(gateResult, isNotNull);
      expect(gateResult!.verdict, Verdict.pass);
      expect(gateResult.issues, isEmpty);
      expect(gateResult.checkedCheckpoints, 4);
      expect(gateResult.skippedCheckpoints, 0);
      expect(gateResult.passed, isTrue);
      // 交付不变。
      expect(result.stage, StudentRunStage.finalized);
      expect(result.verdict, Verdict.pass);
      expect(result.verified, isTrue);
      expect(result.answerSheet.result, cleanAnswer);
    });
  });

  group('fail', () {
    test('required 锚点缺失 -> fail，issues 非空，但交付不变', () async {
      final gate = gateWith([
        required('q15-branch-a', 'm2/m1 轨道支', ['m2m1<=1']),
        // 答案里没有 13：确定为缺失。
        required(
          'q15-energy-max',
          'E 的上界',
          ['13'],
          kind: CheckpointConstraintKind.numeric,
        ),
      ]);
      final result = await execute(buildRun(
        reason: FakeModelAdapter([answerTurn(cleanAnswer)]),
        answerGate: gate,
        verifier: _ScriptedVerifier([Verification.pass()]),
      ));

      final gateResult = result.shadowAnswerGate;
      expect(gateResult, isNotNull);
      expect(gateResult!.verdict, Verdict.fail);
      expect(gateResult.issues, isNotEmpty);
      expect(gateResult.issues.single, contains('E 的上界'));
      expect(gateResult.checkedCheckpoints, 2);
      // shadow fail 不改交付：内容验证 pass 仍然是 pass。
      expect(result.stage, StudentRunStage.finalized);
      expect(result.verdict, Verdict.pass);
      expect(result.verified, isTrue);
      expect(result.answerSheet.result, cleanAnswer);
      expect(result.repairCount, 0);
    });
  });

  group('unknown / 跳过检查点', () {
    test('ifUsed 无法判断 -> unknown，不冒充 pass', () async {
      final gate = gateWith([
        const Checkpoint(
          id: 'q15-critical',
          label: '临界速度',
          kind: CheckpointKind.quantity,
          scope: CheckpointScope.ifUsed,
          constraints: [
            CheckpointConstraint(
              kind: CheckpointConstraintKind.symbolic,
              acceptable: ['vc2=gr'],
            ),
          ],
        ),
      ]);
      final result = await execute(buildRun(
        reason: FakeModelAdapter([answerTurn(cleanAnswer)]),
        answerGate: gate,
        verifier: _ScriptedVerifier([Verification.pass()]),
      ));

      final gateResult = result.shadowAnswerGate;
      expect(gateResult, isNotNull);
      expect(gateResult!.verdict, Verdict.unknown);
      expect(gateResult.skippedCheckpoints, 1);
      expect(gateResult.issues, isEmpty);
      expect(result.stage, StudentRunStage.finalized);
      expect(result.verdict, Verdict.pass);
    });

    test('ifReferenced 未出现 -> 跳过且 pass', () async {
      final gate = gateWith([
        const Checkpoint(
          id: 'q15-vc',
          label: '临界速度',
          kind: CheckpointKind.quantity,
          scope: CheckpointScope.ifReferenced,
          constraints: [
            CheckpointConstraint(
              kind: CheckpointConstraintKind.symbolic,
              acceptable: ['vc2=gr'],
            ),
          ],
        ),
      ]);
      final result = await execute(buildRun(
        reason: FakeModelAdapter([answerTurn(cleanAnswer)]),
        answerGate: gate,
        verifier: _ScriptedVerifier([Verification.pass()]),
      ));

      final gateResult = result.shadowAnswerGate;
      expect(gateResult, isNotNull);
      expect(gateResult!.verdict, Verdict.pass);
      expect(gateResult.skippedCheckpoints, 1);
      expect(gateResult.checkedCheckpoints, 0);
      expect(result.answerSheet.result, cleanAnswer);
    });
  });

  group('Q15 教师 checkpoint 样例（仅测试，不进生产）', () {
    CheckpointSet q15TeacherRubric() => CheckpointSet(
          checkpoints: [
            required('q15-force', 'F 的表达式', ['m1gtantheta']),
            const Checkpoint(
              id: 'q15-branches',
              label: 'm2/m1 两个分支',
              kind: CheckpointKind.relation,
              scope: CheckpointScope.required,
              constraints: [
                CheckpointConstraint(
                  kind: CheckpointConstraintKind.symbolic,
                  acceptable: ['m2m1<=1'],
                ),
                CheckpointConstraint(
                  kind: CheckpointConstraintKind.symbolic,
                  acceptable: ['或7'],
                ),
              ],
            ),
            required(
              'q15-energy',
              'E 的区间',
              ['172', '12'],
              kind: CheckpointConstraintKind.interval,
            ),
            const Checkpoint(
              id: 'q15-domain',
              label: '定义域',
              kind: CheckpointKind.domain,
              scope: CheckpointScope.ifReferenced,
              constraints: [
                CheckpointConstraint(
                  kind: CheckpointConstraintKind.domain,
                  acceptable: ['m2m1>0'],
                ),
              ],
            ),
          ],
        );

    test('完整答案 -> pass（checked 3 / skipped 1），交付不变', () async {
      final result = await execute(buildRun(
        reason: FakeModelAdapter([answerTurn(cleanAnswer)]),
        answerGate: DeterministicAnswerGate(checkpoints: q15TeacherRubric()),
        verifier: _ScriptedVerifier([Verification.pass()]),
      ));

      final gateResult = result.shadowAnswerGate;
      expect(gateResult, isNotNull);
      expect(gateResult!.verdict, Verdict.pass, reason: '${gateResult.issues}');
      expect(gateResult.checkedCheckpoints, 3);
      expect(gateResult.skippedCheckpoints, 1);
      expect(gateResult.issues, isEmpty);
      expect(result.stage, StudentRunStage.finalized);
      expect(result.verdict, Verdict.pass);
      expect(result.verified, isTrue);
      expect(result.answerSheet.result, cleanAnswer);
    });

    test('缺第（3）问 -> fail，且交付不变', () async {
      const incomplete = '（1）F=m_1 g \\tan\\theta；'
          '（2）m_2/m_1\\leq 1 或 7';
      final result = await execute(buildRun(
        reason: FakeModelAdapter([answerTurn(incomplete)]),
        answerGate: DeterministicAnswerGate(checkpoints: q15TeacherRubric()),
        verifier: _ScriptedVerifier([Verification.pass()]),
      ));

      final gateResult = result.shadowAnswerGate;
      expect(gateResult, isNotNull);
      expect(gateResult!.verdict, Verdict.fail);
      expect(gateResult.issues, isNotEmpty);
      expect(gateResult.issues.single, contains('E 的区间'));
      expect(result.stage, StudentRunStage.finalized);
      expect(result.verdict, Verdict.pass, reason: 'shadow fail 不改内容验证结论');
      expect(result.answerSheet.result, incomplete);
    });
  });

  group('异常隔离', () {
    test('gate 抛错 -> 只记录错误，交付不变', () async {
      final result = await execute(buildRun(
        reason: FakeModelAdapter([answerTurn(cleanAnswer)]),
        answerGate: _ThrowingGate(),
        verifier: _ScriptedVerifier([Verification.pass()]),
      ));

      expect(result.shadowAnswerGate, isNull);
      expect(result.shadowAnswerGateError, contains('gate exploded'));
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

class _ThrowingGate extends DeterministicAnswerGate {
  _ThrowingGate()
      : super(checkpoints: const CheckpointSet(checkpoints: <Checkpoint>[]));

  @override
  AnswerGateResult check(StudentAnswerSheet answer) {
    throw StateError('gate exploded');
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
  @override
  Future<StudentProcessAuditResult> audit({
    required String reasoning,
    String? previousReasoning,
    List<String> actionSequence = const [],
    String? stateFingerprint,
    String? previousStateFingerprint,
  }) async {
    return const StudentProcessAuditResult(
      report: ProcessReport.clean,
      claimSummary: ClaimSummary.empty(),
      claims: <Claim>[],
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

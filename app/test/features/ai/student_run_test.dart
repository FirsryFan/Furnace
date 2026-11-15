import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/agent_budget.dart';
import 'package:furnace/features/ai/domain/agent_run.dart';
import 'package:furnace/features/ai/domain/claim.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart';
import 'package:furnace/features/ai/domain/process_auditor.dart';
import 'package:furnace/features/ai/domain/step_guard.dart';
import 'package:furnace/features/ai/domain/student_answer_sheet.dart';
import 'package:furnace/features/ai/domain/student_composition.dart';
import 'package:furnace/features/ai/domain/student_run.dart';
import 'package:furnace/features/ai/domain/verifier.dart';
import 'package:furnace/features/ai/infrastructure/fake_model_adapter.dart';

/// 学生状态机（设计文档 §3.2 / §8）：solve → answer → process audit →
/// content verify → repair(≤1) → finalize。
///
/// 全部用 fake adapter / fake verifier / fake process auditor 驱动，不跑真实
/// API。要锁住的路径：pass / fail→repair→pass / fail→repair→fail / unknown /
/// error / 无答案 / StepGuard 停止；以及三种边界——过程审计读 CoT、内容验证
/// 只拿摘要、主 agent 结构上不可达。
void main() {
  const question = '求物块与斜面间的动摩擦因数';

  List<ModelEvent> answerTurn(String result, {String reasoning = ''}) => [
        if (reasoning.isNotEmpty) ModelReasoningDelta(reasoning),
        ModelTextDelta(
          '【题型】解答题\n【答案】$result\n【过程】由牛顿第二定律得必要步骤。',
        ),
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
    StudentRunRecorder? recorder,
    StepGuard? stepGuard,
    StudentComposition composition = StudentComposition.standard,
  }) {
    return StudentRun(
      reasonAdapter: reason,
      answerAdapter: answer,
      repairAdapter: repair,
      verifier: verifier,
      processAuditor: auditor,
      recorder: recorder,
      stepGuard: stepGuard,
      composition: composition,
      now: () => 1000,
    );
  }

  Future<StudentRunResult> execute(StudentRun run) => run.execute(
        runId: 'run-1',
        conversationId: 'conv-1',
        question: question,
        startedAt: 1000,
      );

  group('状态机路径', () {
    test('pass：solve -> audit -> verify -> finalized，无 repair', () async {
      final reason = FakeModelAdapter([
        answerTurn('μ=0.5', reasoning: 'SENTINEL-REASONING'),
      ]);
      final verifier = _ScriptedVerifier([Verification.pass()]);
      final auditor = _RecordingAuditor();
      final recorder = _RecordingRecorder();
      final run = buildRun(
        reason: reason,
        verifier: verifier,
        auditor: auditor,
        recorder: recorder,
      );

      final result = await execute(run);

      expect(result.stages, [
        StudentRunStage.solving,
        StudentRunStage.auditing,
        StudentRunStage.verifying,
        StudentRunStage.finalized,
      ]);
      expect(result.stage, StudentRunStage.finalized);
      expect(result.verdict, Verdict.pass);
      expect(result.verified, isTrue);
      expect(result.unverified, isFalse);
      expect(result.repairCount, 0);
      expect(result.verifierCalls, 1);
      expect(result.answerSheet.result, contains('μ=0.5'));

      // run 终态与设计 §8 的持久化字段。
      expect(result.run.status, AgentRunStatus.answered);
      expect(result.run.phase, AgentPhase.present);
      expect(result.run.presetId, 'student_solver');
      expect(result.run.mode, AgentMode.student);
      expect(result.run.stopReason, isNull);
      expect(result.run.verifierVerdict, 'pass');
      expect(result.run.steps, 1, reason: '只有 solve 是一次模型步');
      expect(result.run.promptTokens, 100);
      expect(result.run.completionTokens, 50);
      expect(result.run.processReportJson, isNotNull);
      // 答案卡 JSON 只有结构化字段，没有 raw。
      final stored = jsonDecode(result.run.answerSheetJson!) as Map;
      expect(stored['result'], contains('μ=0.5'));
      expect(stored.containsKey('raw'), isFalse);

      // 落库：run + 步骤（model / process / content）+ 两类验证。
      expect(recorder.runs, isNotEmpty);
      expect(recorder.steps.map((step) => step.kind), [
        AgentStepKind.model,
        AgentStepKind.verify,
        AgentStepKind.verify,
      ]);
      expect(recorder.steps.first.phase, AgentPhase.solve);
      expect(recorder.processAudits, hasLength(1));
      expect(recorder.contentVerifications, hasLength(1));
      expect(recorder.contentVerifications.single.verdict, Verdict.pass);
    });

    test('fail -> repair(1) -> 复验 pass', () async {
      final reason = FakeModelAdapter([answerTurn('第一版答案')]);
      final repair = FakeModelAdapter([answerTurn('修正后答案')]);
      final verifier = _ScriptedVerifier([
        Verification.fail(
          failureType: FailureType.missingAnswer,
          issues: const ['第 (2) 问没有答案'],
        ),
        Verification.pass(),
      ]);
      final auditor = _RecordingAuditor();
      final run = buildRun(
        reason: reason,
        repair: repair,
        verifier: verifier,
        auditor: auditor,
      );

      final result = await execute(run);

      expect(result.stages, [
        StudentRunStage.solving,
        StudentRunStage.auditing,
        StudentRunStage.verifying,
        StudentRunStage.repairing,
        StudentRunStage.auditing,
        StudentRunStage.verifying,
        StudentRunStage.finalized,
      ]);
      expect(result.repairCount, 1);
      expect(result.verifierCalls, 2);
      expect(result.verdict, Verdict.pass);
      expect(result.run.status, AgentRunStatus.answered);
      expect(result.answerSheet.result, contains('修正后答案'));

      // 恰好一次 repair 模型调用。
      expect(repair.requests, hasLength(1));
      // repair 之后的复验看到了新的答案卡。
      expect(verifier.calls, hasLength(2));
      expect(verifier.calls.last.answer.result, contains('修正后答案'));
      // repair 后重跑过程审计：第二次带上了上一段 reasoning。
      expect(auditor.reasonings, hasLength(2));
      expect(auditor.previousReasonings.last, isNotNull);
    });

    test('fail -> repair(1) -> 复验仍 fail：停在未验证，不无限重写', () async {
      final repair = FakeModelAdapter([answerTurn('第二版答案')]);
      final verifier = _ScriptedVerifier([
        Verification.fail(failureType: FailureType.inconsistentProcess),
        Verification.fail(failureType: FailureType.inconsistentProcess),
      ]);
      final run = buildRun(
        reason: FakeModelAdapter([answerTurn('第一版答案')]),
        repair: repair,
        verifier: verifier,
      );

      final result = await execute(run);

      expect(result.stage, StudentRunStage.finalizedUnverified);
      expect(result.verdict, Verdict.fail);
      expect(result.repairCount, 1);
      expect(result.verifierCalls, 2);
      expect(repair.requests, hasLength(1));
      // 答案卡仍然保留（设计 §3.2：最终答案即使 unverified 也保留）。
      expect(result.answerSheet.result, contains('第二版答案'));
      expect(result.run.status, AgentRunStatus.stopped);
      expect(result.run.stopReason, StopReason.verifierFailed);
      expect(result.run.verifierVerdict, 'fail');
    });

    test('unknown：直接以未验证收尾，不触发 repair', () async {
      final repair = FakeModelAdapter([answerTurn('不应被调用')]);
      final verifier = _ScriptedVerifier([
        Verification.unknown(failureType: FailureType.other, issues: const ['信息不足']),
      ]);
      final run = buildRun(
        reason: FakeModelAdapter([answerTurn('答案')]),
        repair: repair,
        verifier: verifier,
      );

      final result = await execute(run);

      expect(result.stage, StudentRunStage.finalizedUnverified);
      expect(result.verdict, Verdict.unknown);
      expect(result.unverified, isTrue);
      expect(result.repairCount, 0);
      expect(result.verifierCalls, 1);
      expect(repair.requests, isEmpty);
      expect(result.run.status, AgentRunStatus.answered);
      expect(result.run.verifierVerdict, 'unknown');
    });

    test('error：验证器自身出错也按未验证收尾，不是 pass', () async {
      final repair = FakeModelAdapter([answerTurn('不应被调用')]);
      final run = buildRun(
        reason: FakeModelAdapter([answerTurn('答案')]),
        repair: repair,
        verifier: _ThrowingVerifier(),
      );

      final result = await execute(run);

      expect(result.stage, StudentRunStage.finalizedUnverified);
      expect(result.verdict, Verdict.error);
      expect(result.verification!.failureType, FailureType.verifierError);
      expect(result.repairCount, 0);
      expect(repair.requests, isEmpty);
      expect(result.run.verifierVerdict, 'error');
      expect(result.verified, isFalse);
    });
  });

  group('answer 阶段', () {
    test('solve 没写答案时用 answer adapter 续写答题卡', () async {
      final reason = FakeModelAdapter([
        emptyTurn(reasoning: '推导草稿'),
      ]);
      final answer = FakeModelAdapter([answerTurn('最终答案')]);
      final verifier = _ScriptedVerifier([Verification.pass()]);
      final run = buildRun(
        reason: reason,
        answer: answer,
        verifier: verifier,
      );

      final result = await execute(run);

      expect(result.stages.first, StudentRunStage.solving);
      expect(result.stages, contains(StudentRunStage.answering));
      expect(result.stage, StudentRunStage.finalized);
      expect(answer.requests, hasLength(1));
      // 誊写回合是 3k reserve 的独立 prompt，且带上了草稿。
      expect(
        answer.requests.single.messages.first.content,
        StudentComposition.standard.answerScribePrompt,
      );
      expect(
        answer.requests.single.messages.map((message) => message.role),
        contains('assistant'),
      );
      expect(result.answerSheet.result, contains('最终答案'));
      // raw CoT 拼上了两个回合。
      expect(result.reasoning, contains('推导草稿'));
    });

    test('solve 与 answer 都没有答案：failed，不验证', () async {
      final verifier = _ScriptedVerifier([Verification.pass()]);
      final run = buildRun(
        reason: FakeModelAdapter([emptyTurn()]),
        answer: FakeModelAdapter([emptyTurn()]),
        verifier: verifier,
      );

      final result = await execute(run);

      expect(result.stage, StudentRunStage.failed);
      expect(result.answered, isFalse);
      expect(result.run.status, AgentRunStatus.failed);
      expect(result.run.stopReason, StopReason.solveFailed);
      expect(verifier.calls, isEmpty);
      expect(result.verifierCalls, 0);
    });

    test('solve 因 finish=length 截断时转 answer 阶段', () async {
      final reason = FakeModelAdapter([
        [
          const ModelTextDelta('【答案】半截'),
          const ModelTurnDone(finishReason: 'length'),
        ],
      ]);
      final answer = FakeModelAdapter([answerTurn('完整答案')]);
      final run = buildRun(
        reason: reason,
        answer: answer,
        verifier: _ScriptedVerifier([Verification.pass()]),
      );

      final result = await execute(run);

      expect(result.stage, StudentRunStage.finalized);
      expect(answer.requests, hasLength(1));
      expect(result.answerSheet.result, contains('完整答案'));
    });
  });

  group('StepGuard 介入', () {
    test('预算在 solve 后就用尽时停止，不再调用验证', () async {
      final verifier = _ScriptedVerifier([Verification.pass()]);
      final run = buildRun(
        reason: FakeModelAdapter([answerTurn('答案')]),
        verifier: verifier,
        stepGuard: StepGuard(
          budget: const RunBudget(maxSteps: 1, maxCompletionTokens: 1000),
        ),
      );

      final result = await execute(run);

      expect(result.stage, StudentRunStage.finalizedUnverified);
      expect(result.run.status, AgentRunStatus.stopped);
      expect(result.run.stopReason, StopReason.maxSteps);
      expect(verifier.calls, isEmpty);
      expect(result.verifierCalls, 0);
      // 已经拿到的答案不丢。
      expect(result.answerSheet.result, contains('答案'));
    });
  });

  // ---------------------------------------------------------------------------
  // 过程 blocker 门控（设计文档 §7.4 / §8）
  // ---------------------------------------------------------------------------
  StudentComposition noRepairComposition() => StudentComposition(
        systemPrompt: StudentComposition.standard.systemPrompt,
        answerScribePrompt: StudentComposition.standard.answerScribePrompt,
        repairPrompt: StudentComposition.standard.repairPrompt,
        budget: StudentComposition.standard.budget.copyWith(maxRepair: 0),
      );

  ProcessReport loopReport() => const ProcessReport(
        loopDetected: true,
        stagnation: false,
        repeatedClaimCount: 0,
        selfDoubtCount: 0,
        flags: ['repeated_sentence'],
        extractedClaims: [],
      );

  ProcessReport stagnationReport() => const ProcessReport(
        loopDetected: false,
        stagnation: true,
        repeatedClaimCount: 0,
        selfDoubtCount: 0,
        flags: ['no_new_content_in_tail'],
        extractedClaims: [],
      );

  ProcessReport selfDoubtReport() => const ProcessReport(
        loopDetected: false,
        stagnation: false,
        repeatedClaimCount: 0,
        selfDoubtCount: 4,
        flags: ['self_doubt'],
        extractedClaims: [],
      );

  group('过程 blocker 门控', () {
    test('内容 pass + 过程 loop：先 repair 一次，复验 pass 后 finalized', () async {
      final repair = FakeModelAdapter([answerTurn('修正后答案')]);
      final verifier = _ScriptedVerifier([
        Verification.pass(),
        Verification.pass(),
      ]);
      final auditor = _RecordingAuditor(
        reports: [loopReport(), ProcessReport.clean],
      );
      final run = buildRun(
        reason: FakeModelAdapter([answerTurn('第一版答案')]),
        repair: repair,
        verifier: verifier,
        auditor: auditor,
      );

      final result = await execute(run);

      expect(result.stages, [
        StudentRunStage.solving,
        StudentRunStage.auditing,
        StudentRunStage.verifying,
        StudentRunStage.repairing,
        StudentRunStage.auditing,
        StudentRunStage.verifying,
        StudentRunStage.finalized,
      ]);
      expect(result.stage, StudentRunStage.finalized);
      expect(result.verdict, Verdict.pass);
      expect(result.verified, isTrue);
      expect(result.repairCount, 1);
      expect(result.verifierCalls, 2);
      expect(repair.requests, hasLength(1));
      // 过程 blocker 被一次 repair 清掉后，stop_reason 不写。
      expect(result.run.stopReason, isNull);
    });

    test('内容 pass + 过程 loop 且 repair 预算用尽：不能 finalized', () async {
      final repair = FakeModelAdapter([answerTurn('不应被调用')]);
      final verifier = _ScriptedVerifier([Verification.pass()]);
      final run = buildRun(
        reason: FakeModelAdapter([answerTurn('答案')]),
        repair: repair,
        verifier: verifier,
        auditor: _RecordingAuditor(reports: [loopReport()]),
        composition: noRepairComposition(),
      );

      final result = await execute(run);

      expect(result.stage, StudentRunStage.finalizedUnverified);
      expect(result.verdict, Verdict.pass, reason: '内容本身是通过的');
      expect(result.verified, isFalse, reason: '过程 blocker 不能静默 pass');
      expect(result.unverified, isTrue);
      expect(result.repairCount, 0);
      expect(result.verifierCalls, 1);
      expect(repair.requests, isEmpty);
      // 结论、stop_reason 与落库状态都要反映过程 blocker。
      expect(result.run.status, AgentRunStatus.stopped);
      expect(result.run.stopReason, StopReason.processLoop);
      expect(result.run.verifierVerdict, 'pass');
      // 答案卡保留（设计 §3.2：即使未验证也保留）。
      expect(result.answerSheet.result, contains('答案'));
    });

    test('过程 stagnation 也按 process_loop 处理', () async {
      final verifier = _ScriptedVerifier([Verification.pass()]);
      final run = buildRun(
        reason: FakeModelAdapter([answerTurn('答案')]),
        verifier: verifier,
        auditor: _RecordingAuditor(reports: [stagnationReport()]),
        composition: noRepairComposition(),
      );

      final result = await execute(run);

      expect(result.stage, StudentRunStage.finalizedUnverified);
      expect(result.run.stopReason, StopReason.processLoop);
      expect(result.run.status, AgentRunStatus.stopped);
    });

    test('高密度自我怀疑：stop_reason 记为 process_self_doubt', () async {
      final verifier = _ScriptedVerifier([Verification.pass()]);
      final run = buildRun(
        reason: FakeModelAdapter([answerTurn('答案')]),
        verifier: verifier,
        auditor: _RecordingAuditor(reports: [selfDoubtReport()]),
        composition: noRepairComposition(),
      );

      final result = await execute(run);

      expect(result.stage, StudentRunStage.finalizedUnverified);
      expect(result.verdict, Verdict.pass);
      expect(result.verified, isFalse);
      expect(result.run.stopReason, StopReason.processSelfDoubt);
      expect(result.run.status, AgentRunStatus.stopped);
      // 落库的 run 状态可以直接还原成稳定 id。
      expect(StopReason.fromId(result.run.stopReason!.id),
          StopReason.processSelfDoubt);
    });

    test('过程 blocker 最多 repair 一次，不无限重写', () async {
      final repair = FakeModelAdapter([
        answerTurn('第二版答案'),
        answerTurn('第三版答案（不应被调用）'),
      ]);
      final verifier = _ScriptedVerifier([
        Verification.pass(),
        Verification.pass(),
      ]);
      final run = buildRun(
        reason: FakeModelAdapter([answerTurn('第一版答案')]),
        repair: repair,
        verifier: verifier,
        // 两次审计都判 loop：repair 之后仍然打转。
        auditor: _RecordingAuditor(reports: [loopReport(), loopReport()]),
      );

      final result = await execute(run);

      expect(result.stage, StudentRunStage.finalizedUnverified);
      expect(result.repairCount, 1);
      expect(result.verifierCalls, 2);
      expect(repair.requests, hasLength(1), reason: '一次为限');
      expect(result.run.stopReason, StopReason.processLoop);
      expect(result.answerSheet.result, contains('第二版答案'));
    });
  });

  group('Claim 落库', () {
    test('run 结束把过程审计抽到的 claim 交给 recorder.saveClaims', () async {
      final claim = Claim(
        id: 'claim-abc123',
        kind: ClaimKind.equation,
        canonical: 'μ=0.5',
        statement: '所以 μ=0.5',
        status: ClaimStatus.proposed,
        createdAtMs: 0,
      );
      final recorder = _RecordingRecorder();
      final run = buildRun(
        reason: FakeModelAdapter([answerTurn('μ=0.5', reasoning: '所以 μ=0.5')]),
        verifier: _ScriptedVerifier([Verification.pass()]),
        auditor: _RecordingAuditor(claims: [claim]),
        recorder: recorder,
      );

      await execute(run);

      expect(recorder.claimsSaves, hasLength(1));
      expect(recorder.claimsSaves.single.runId, 'run-1');
      expect(
        recorder.claimsSaves.single.claims.map((claim) => claim.canonical),
        ['μ=0.5'],
      );
      // claim 是过程证据，不影响 run 的 pass 结论。
      expect(recorder.contentVerifications.single.verdict, Verdict.pass);
    });

    test('没有 claim 时不写空批次', () async {
      final recorder = _RecordingRecorder();
      final run = buildRun(
        reason: FakeModelAdapter([answerTurn('答案')]),
        verifier: _ScriptedVerifier([Verification.pass()]),
        auditor: _RecordingAuditor(),
        recorder: recorder,
      );

      await execute(run);

      expect(recorder.claimsSaves, isEmpty);
    });
  });

  group('输入边界', () {
    test('solve 的 system prompt 是 composition 的 prompt，且不带工具', () async {
      final reason = FakeModelAdapter([answerTurn('答案')]);
      final run = buildRun(
        reason: reason,
        verifier: _ScriptedVerifier([Verification.pass()]),
      );

      await execute(run);

      final request = reason.requests.single;
      expect(request.tools, isEmpty);
      expect(request.messages.first.role, 'system');
      expect(
        request.messages.first.content,
        StudentComposition.standard.systemPrompt,
      );
      expect(request.messages.last.content, question);
    });

    test('内容验证只收到 claim 摘要，结构上拿不到 reasoning', () async {
      final verifier = _ScriptedVerifier([Verification.pass()]);
      final auditor = _RecordingAuditor(
        claimSummary: ClaimSummary(claims: [
          Claim(
            id: 'claim-a',
            kind: ClaimKind.given,
            canonical: 'm=2',
            statement: '已知质量 m=2',
            status: ClaimStatus.given,
            createdAtMs: 0,
          ),
        ]),
      );
      final run = buildRun(
        reason: FakeModelAdapter([answerTurn('答案', reasoning: 'SECRET-COT')]),
        verifier: verifier,
        auditor: auditor,
      );

      await execute(run);

      // 过程审计读到了 CoT。
      expect(auditor.reasonings.single, contains('SECRET-COT'));
      // 内容验证拿到的是摘要，不是 CoT。
      expect(verifier.calls.single.claims.claims, hasLength(1));
      expect(
        verifier.calls.single.claims.toPromptText(),
        contains('已知质量 m=2'),
      );
    });

    test('学生状态机结构上不 import 主 agent loop / 工具注册表', () {
      final source = File('lib/features/ai/domain/student_run.dart')
          .readAsStringSync();
      expect(source.contains("import 'agent_loop.dart'"), isFalse);
      expect(source.contains("import 'tool_registry.dart'"), isFalse);
      expect(source.contains('sendUserMessage('), isFalse);
    });
  });
}

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _ScriptedVerifier implements Verifier {
  _ScriptedVerifier(this._results);

  final List<Verification> _results;
  final List<_VerifierCall> calls = [];
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
    calls.add(_VerifierCall(
      question: question,
      answer: answer,
      images: images,
      claims: claims,
    ));
    final result = _results[_index < _results.length ? _index : _results.length - 1];
    _index += 1;
    return result;
  }
}

class _VerifierCall {
  const _VerifierCall({
    required this.question,
    required this.answer,
    required this.images,
    required this.claims,
  });

  final String question;
  final StudentAnswerSheet answer;
  final List<ChatImagePart> images;
  final ClaimSummary claims;
}

class _ThrowingVerifier implements Verifier {
  @override
  String get id => 'throwing_verifier';

  @override
  VerifierKind get kind => VerifierKind.content;

  @override
  Future<Verification> verify({
    required String question,
    required StudentAnswerSheet answer,
    List<ChatImagePart> images = const [],
    required ClaimSummary claims,
  }) async {
    throw StateError('verifier exploded');
  }
}

class _RecordingAuditor implements StudentProcessAuditSource {
  _RecordingAuditor({
    this.claimSummary = const ClaimSummary.empty(),
    List<ProcessReport>? reports,
    List<Claim> claims = const <Claim>[],
  })  : _reports = reports,
        _claims = claims;

  final ClaimSummary claimSummary;
  final List<ProcessReport>? _reports;
  final List<Claim> _claims;
  final List<String> reasonings = [];
  final List<String?> previousReasonings = [];
  int _index = 0;

  @override
  Future<StudentProcessAuditResult> audit({
    required String reasoning,
    String? previousReasoning,
    List<String> actionSequence = const [],
    String? stateFingerprint,
    String? previousStateFingerprint,
  }) async {
    reasonings.add(reasoning);
    previousReasonings.add(previousReasoning);
    final reports = _reports;
    final report = reports == null || reports.isEmpty
        ? ProcessReport.clean
        : reports[_index < reports.length ? _index : reports.length - 1];
    _index += 1;
    return StudentProcessAuditResult(
      report: report,
      claimSummary: claimSummary,
      claims: _claims,
    );
  }
}

class _ClaimsSave {
  const _ClaimsSave(this.runId, this.claims);

  final String runId;
  final List<Claim> claims;
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

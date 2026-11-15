import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/features/ai/application/student_mode_controller.dart';
import 'package:furnace/features/ai/domain/claim.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart';
import 'package:furnace/features/ai/domain/process_auditor.dart';
import 'package:furnace/features/ai/domain/student_answer_sheet.dart';
import 'package:furnace/features/ai/domain/student_composition.dart';
import 'package:furnace/features/ai/domain/student_run.dart';
import 'package:furnace/features/ai/domain/student_shadow_verification.dart';
import 'package:furnace/features/ai/domain/student_solver.dart';
import 'package:furnace/features/ai/domain/verification_pipeline.dart';
import 'package:furnace/features/ai/domain/verifier.dart';
import 'package:furnace/features/ai/infrastructure/agent_run_store.dart';
import 'package:furnace/features/ai/infrastructure/experience_store.dart';
import 'package:furnace/features/ai/infrastructure/fake_model_adapter.dart';
import 'package:furnace/features/ai/infrastructure/student_trace_store.dart';

/// The direct student-mode path, at the level below the UI.
///
/// The important properties are that it calls [StudentSolver] itself (with the
/// attached picture and no tool list), writes the local trace, and has no
/// dependency through which the main agent loop could be reached. The last one
/// is checked structurally as well as by construction: a regression that
/// re-introduces the loop into this file would otherwise be invisible here.
void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('furnace-student-mode-');
  });

  tearDown(() async {
    if (temp.existsSync()) {
      await temp.delete(recursive: true);
    }
  });

  StudentModeController buildController(FakeModelAdapter adapter) {
    return StudentModeController(
      solver: StudentSolver(reasonAdapter: adapter),
      traceStore: StudentTraceStore(supportDirectory: () async => temp),
    );
  }

  group('StudentModeController', () {
    test('calls the solver directly with the question and the image', () async {
      final adapter = FakeModelAdapter([
        [
          const ModelReasoningDelta('推导过程'),
          const ModelTextDelta('a=g sinθ'),
          const ModelTurnDone(
            finishReason: 'stop',
            promptTokens: 100,
            completionTokens: 20,
          ),
        ],
      ]);
      final controller = buildController(adapter)
        ..setImages([
          const ChatImagePart(mime: 'image/png', base64: 'aW1n'),
        ]);

      final outcome = await controller.solve(question: '  求加速度  ');

      expect(outcome.ok, isTrue);
      expect(outcome.question, '求加速度');
      expect(outcome.result.answer, 'a=g sinθ');
      expect(outcome.result.reasoning, '推导过程');
      expect(outcome.result.attempts, 1);
      expect(outcome.result.promptTokens, 100);
      expect(outcome.result.completionTokens, 20);
      expect(outcome.imageCount, 1);

      // The solver was called once, with no tools, and the current message's
      // image travelled in the user message itself.
      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.tools, isEmpty);
      final request = adapter.requests.single.messages;
      expect(request.first.role, 'system');
      expect(request.last.role, 'user');
      expect(request.last.content, '求加速度');
      expect(request.last.images, hasLength(1));
      expect(request.last.images.single.base64, 'aW1n');
      expect(request.last.images.single.mime, 'image/png');
    });

    test('writes a local trace that contains the raw reasoning', () async {
      final adapter = FakeModelAdapter([
        [
          const ModelReasoningDelta('原始思维链'),
          const ModelTextDelta('2'),
          const ModelTurnDone(finishReason: 'stop'),
        ],
      ]);
      final controller = buildController(adapter);

      final outcome = await controller.solve(question: '1+1=?');

      expect(outcome.tracePath, isNotNull);
      expect(outcome.traceError, isNull);
      expect(outcome.tracePath, contains('student_solver_traces'));
      final trace = File(outcome.tracePath!);
      expect(await trace.exists(), isTrue);
      final decoded =
          jsonDecode(await trace.readAsString()) as Map<String, Object?>;
      expect(decoded['schema'], 'furnace.student_solver_trace/1');
      expect(decoded['question'], '1+1=?');
      expect(decoded['answer'], '2');
      expect(decoded['reasoning'], '原始思维链');
      expect(decoded['phase'], 'answered');
      // The answer-sheet structure is part of the trace, not just the raw text.
      final sheet = decoded['answer_sheet']! as Map<String, Object?>;
      expect(sheet['kind'], 'solution');
      expect(sheet['result'], '2');
      expect(sheet['structured'], isFalse);
    });

    test('returns the structured answer sheet, not just free text', () async {
      final adapter = FakeModelAdapter([
        [
          const ModelTextDelta(
            '【题型】解答题\n'
            '【答案】(1) g sinθ；(2) m2/m1≤1 或 m2/m1=7\n'
            '【过程】由牛顿第二定律得 a=g sinθ，再用动量守恒分情况讨论。',
          ),
          const ModelTurnDone(finishReason: 'stop'),
        ],
      ]);
      final controller = buildController(adapter);

      final outcome = await controller.solve(question: '题目');

      expect(outcome.ok, isTrue);
      final sheet = outcome.answerSheet;
      expect(sheet.kind, StudentQuestionKind.solution);
      expect(sheet.result, contains('g sinθ'));
      expect(sheet.process, contains('动量守恒'));
      expect(sheet.structured, isTrue);
      expect(sheet.raw, outcome.result.answer);
      expect(outcome.answerSheet.toPlainText(), contains('【题型】解答题'));
    });

    test('a choice answer carries the option letters', () async {
      final adapter = FakeModelAdapter([
        [
          const ModelTextDelta('【题型】选择题\n【答案】B'),
          const ModelTurnDone(finishReason: 'stop'),
        ],
      ]);
      final controller = buildController(adapter);

      final outcome = await controller.solve(question: '选择题');

      expect(outcome.answerSheet.kind, StudentQuestionKind.choice);
      expect(outcome.answerSheet.choice, 'B');
      expect(outcome.answerSheet.result, 'B');
    });

    test('accepts a photographed question with no typed text', () async {
      final adapter = FakeModelAdapter([
        [
          const ModelTextDelta('(1) g sinθ'),
          const ModelTurnDone(finishReason: 'stop'),
        ],
      ]);
      final controller = buildController(adapter)
        ..setImages([
          const ChatImagePart(mime: 'image/png', base64: 'aW1n'),
        ]);

      final outcome = await controller.solve(question: '');

      expect(outcome.ok, isTrue);
      expect(outcome.imageCount, 1);
      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.messages.last.images, hasLength(1));
    });

    test('reports a model failure without throwing, trace included', () async {
      final adapter = FakeModelAdapter([
        [const ModelFailure('network down')],
      ]);
      final controller = buildController(adapter);

      final outcome = await controller.solve(question: '题目');

      expect(outcome.ok, isFalse);
      expect(outcome.result.answer, isEmpty);
      expect(outcome.result.error, isNotNull);
      expect(outcome.tracePath, isNotNull);
      expect(await File(outcome.tracePath!).exists(), isTrue);
    });

    test('keeps the answer when the trace cannot be written', () async {
      final adapter = FakeModelAdapter([
        [
          const ModelTextDelta('answer'),
          const ModelTurnDone(finishReason: 'stop'),
        ],
      ]);
      final controller = StudentModeController(
        solver: StudentSolver(reasonAdapter: adapter),
        traceStore: StudentTraceStore(
          supportDirectory: () async =>
              throw const FileSystemException('trace dir unavailable'),
        ),
      );

      final outcome = await controller.solve(question: '题目');

      expect(outcome.ok, isTrue);
      expect(outcome.result.answer, 'answer');
      expect(outcome.tracePath, isNull);
      expect(outcome.traceError, isNotNull);
    });

    test('rejects a solve with neither text nor image', () async {
      final adapter = FakeModelAdapter([
        const <ModelEvent>[],
      ]);
      final controller = buildController(adapter);

      expect(
        () => controller.solve(question: '   '),
        throwsA(isA<ArgumentError>()),
      );
      expect(adapter.requests, isEmpty);
    });

    test('has no path to the main agent loop', () {
      // Structural guard: the direct entry point must not import or reference
      // AgentLoop / sendUserMessage / the tool registry. Comment text is
      // excluded by checking code-ish strings only.
      final source = File(
        'lib/features/ai/application/student_mode_controller.dart',
      ).readAsStringSync();
      expect(source.contains("import '../domain/agent_loop.dart'"), isFalse,
          reason: 'the direct path must not import the main agent loop');
      expect(source.contains('AgentLoop'), isFalse,
          reason: 'the direct path must not hold or call the main agent loop');
      expect(source.contains('sendUserMessage'), isFalse,
          reason: 'the direct path must never send a user message');
      expect(source.contains('ToolRegistry'), isFalse,
          reason: 'the direct path must not go through the tool registry');
      expect(source.contains('SolveQuestionAsStudentTool'), isFalse,
          reason: 'the direct path must not be the compatibility tool');
    });
  });

  group('runStudent (StudentRun state machine)', () {
    /// solve 回合：写出一份结构化答案卡。
    List<ModelEvent> solveTurn() => [
          const ModelTextDelta(
            '【题型】解答题\n【答案】μ=0.5\n【过程】由牛顿第二定律得必要步骤。',
          ),
          const ModelTurnDone(
            finishReason: 'stop',
            promptTokens: 100,
            completionTokens: 40,
          ),
        ];

    /// 内容验证回合：独立模型调用返回 pass。
    List<ModelEvent> verifierPassTurn() => [
          const ModelTextDelta('{"verdict":"pass","issues":[],"confidence":0.9}'),
          const ModelTurnDone(finishReason: 'stop', completionTokens: 10),
        ];

    test('runs solve -> audit -> verify -> finalize and writes a trace',
        () async {
      final adapter = FakeModelAdapter([solveTurn(), verifierPassTurn()]);
      final controller = buildController(adapter);

      final outcome = await controller.runStudent(
        question: '求动摩擦因数',
        conversationId: 'conv-1',
      );

      expect(outcome.usedStudentRun, isTrue);
      expect(outcome.ok, isTrue);
      expect(outcome.verified, isTrue);
      expect(outcome.answerSheet.result, contains('μ=0.5'));
      expect(outcome.studentRun!.stages, [
        StudentRunStage.solving,
        StudentRunStage.auditing,
        StudentRunStage.verifying,
        StudentRunStage.finalized,
      ]);
      // 两个回合都没有工具：一个 solve、一个独立内容验证。
      expect(adapter.requests, hasLength(2));
      expect(adapter.requests.every((request) => request.tools.isEmpty), isTrue);
      expect(
        adapter.requests.first.messages.first.content,
        StudentComposition.standard.systemPrompt,
      );

      // 本地 trace 仍然写，且带上原始 reasoning（内容验证看不到它）。
      expect(outcome.tracePath, isNotNull);
      expect(outcome.traceError, isNull);
      final trace = File(outcome.tracePath!);
      expect(await trace.exists(), isTrue);
      final decoded =
          jsonDecode(await trace.readAsString()) as Map<String, Object?>;
      expect(decoded['schema'], 'furnace.student_solver_trace/1');
      expect(decoded['answer_sheet'], isA<Map<String, Object?>>());
    });

    test('the legacy solve() path still calls the solver directly once',
        () async {
      final adapter = FakeModelAdapter([
        [
          const ModelTextDelta('旧路径答案'),
          const ModelTurnDone(finishReason: 'stop'),
        ],
      ]);
      final controller = buildController(adapter);

      final outcome = await controller.solve(question: '题目');

      expect(outcome.usedStudentRun, isFalse);
      expect(outcome.studentRun, isNull);
      expect(outcome.result.answer, '旧路径答案');
      expect(adapter.requests, hasLength(1),
          reason: 'the legacy path does no separate verification turn');
    });

    test('rejects runStudent with neither text nor image', () async {
      final adapter = FakeModelAdapter([const <ModelEvent>[]]);
      final controller = buildController(adapter);

      expect(
        () => controller.runStudent(question: '   ', conversationId: 'conv-1'),
        throwsA(isA<ArgumentError>()),
      );
      expect(adapter.requests, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Shadow 预检（task-32/33）：生产学生模式默认启用，但不参与交付。
  // ---------------------------------------------------------------------------
  group('runStudent shadow 预检（生产默认启用）', () {
    const shadowQuestion = 'Q15 斜面与物块。（1）求 F；（2）求 m_2/m_1 的所有可能值；'
        '（3）求 E 的范围（单位 J）';
    const cleanAnswer = '（1）F=m_1 g \\tan\\theta；（2）m_2/m_1\\leq 1 或 7；'
        '（3）17/2\\leq E\\leq 12 J';
    const cleanProcess = '整理：E 的范围用区间表示，端点 17/2 与 12 都要保留。';
    const cleanReasoning = '设物块质量 m_1，斜面倾角 \\theta，重力加速度 g。\n\n'
        '由向心力公式得 F=m_1 g \\tan\\theta。\n\n'
        '当 m_2/m_1=7 时，静摩擦达到临界。\n\n'
        '所以 m_2/m_1\\leq 1 或 7。\n\n'
        '由动能定理得 17/2\\leq E\\leq 12，单位 J。';

    List<ModelEvent> cleanSolveTurn() => [
          const ModelReasoningDelta(cleanReasoning),
          const ModelTextDelta(
            '【题型】解答题\n【答案】$cleanAnswer\n【过程】$cleanProcess',
          ),
          const ModelTurnDone(
            finishReason: 'stop',
            promptTokens: 100,
            completionTokens: 40,
          ),
        ];

    /// 不带 process、也不带 reasoning 的答案：确定性 trace 解析失败。
    List<ModelEvent> parseFailureTurn() => [
          const ModelTextDelta('【题型】解答题\n【答案】某答案'),
          const ModelTurnDone(finishReason: 'stop', completionTokens: 10),
        ];

    List<ModelEvent> verifierPassTurn() => [
          const ModelTextDelta(
            '{"verdict":"pass","issues":[],"confidence":0.9}',
          ),
          const ModelTurnDone(finishReason: 'stop', completionTokens: 10),
        ];

    Claim shadowClaim() => Claim(
          id: 'claim-shadow',
          kind: ClaimKind.equation,
          canonical: 'μ=0.5',
          statement: '所以 μ=0.5',
          status: ClaimStatus.proposed,
          createdAtMs: 0,
        );

    /// 固定过程审计：shadow 测试只关心 precheck 输入，不需要真实审计启发式
    /// 在这段 fixture 上误判 loop（那会触发 repair，改变输入的答案卡）。
    StudentProcessAuditSource Function() cleanAuditor() =>
        () => _FixedAuditor(claims: [shadowClaim()]);

    /// 生产默认构造：不传 shadowVerifier，走 controller 的默认接线。
    StudentModeController buildDefault(FakeModelAdapter adapter) {
      return StudentModeController(
        solver: StudentSolver(reasonAdapter: adapter),
        traceStore: StudentTraceStore(supportDirectory: () async => temp),
        processAuditorFactory: cleanAuditor(),
      );
    }

    /// 关闭 shadow 的旧基线（用于逐项对比交付）。
    StudentModeController buildNoShadow(FakeModelAdapter adapter) {
      return StudentModeController(
        solver: StudentSolver(reasonAdapter: adapter),
        traceStore: StudentTraceStore(supportDirectory: () async => temp),
        processAuditorFactory: cleanAuditor(),
        shadowVerifier: null,
      );
    }

    test('默认构造真实 run 会跑 precheck，且交付与关闭 shadow 时逐项一致',
        () async {
      final shadowAdapter = FakeModelAdapter([cleanSolveTurn(), verifierPassTurn()]);
      final baselineAdapter =
          FakeModelAdapter([cleanSolveTurn(), verifierPassTurn()]);

      final withShadow = await buildDefault(shadowAdapter).runStudent(
        question: shadowQuestion,
        conversationId: 'conv-1',
      );
      final withoutShadow = await buildNoShadow(baselineAdapter).runStudent(
        question: shadowQuestion,
        conversationId: 'conv-1',
      );

      // 默认路径确实跑了 shadow（clean -> 有 handoff）。
      final shadow = withShadow.studentRun!.shadowVerification;
      expect(shadow, isNotNull);
      expect(shadow!.status, VerificationPipelineStatus.awaitingChecker);
      expect(shadow.handoff, isNotNull);
      expect(shadow.checkerRounds, 0, reason: 'shadow 不调用 Checker');
      expect(withShadow.studentRun!.shadowVerificationError, isNull);
      // handoff 里是这次 run 的冻结答案。
      expect(shadow.handoff!.frozenAnswer, withShadow.answerSheet.result);
      expect(shadow.handoff!.frozenAnswer, cleanAnswer);
      expect(shadow.handoff!.sourceRunId, withShadow.studentRun!.run.id);

      // 交付逐项不变。
      expect(withShadow.studentRun!.stage, withoutShadow.studentRun!.stage);
      expect(withShadow.studentRun!.stages, withoutShadow.studentRun!.stages);
      expect(withShadow.studentRun!.verdict, withoutShadow.studentRun!.verdict);
      expect(withShadow.studentRun!.verified, withoutShadow.studentRun!.verified);
      expect(withShadow.verified, isTrue);
      expect(withShadow.answerSheet.result, withoutShadow.answerSheet.result);
      expect(withShadow.answerSheet.result, cleanAnswer);
      expect(withShadow.answerSheet.process, withoutShadow.answerSheet.process);
      expect(withShadow.studentRun!.repairCount,
          withoutShadow.studentRun!.repairCount);
      expect(withShadow.studentRun!.verifierCalls,
          withoutShadow.studentRun!.verifierCalls);
      expect(withShadow.studentRun!.run.status,
          withoutShadow.studentRun!.run.status);
      expect(withShadow.studentRun!.run.stopReason,
          withoutShadow.studentRun!.run.stopReason);
      // shadow 不产生额外模型调用（各 1 次 solve + 1 次内容验证）。
      expect(shadowAdapter.requests, hasLength(2));
      expect(baselineAdapter.requests, hasLength(2));
      // 关闭 shadow 时没有结果，旧行为可回归。
      expect(withoutShadow.studentRun!.shadowVerification, isNull);
      expect(withoutShadow.studentRun!.shadowVerificationError, isNull);
    });

    test('解析失败：shadow 只记 unknown/clarification，交付不变', () async {
      final shadowAdapter = FakeModelAdapter([parseFailureTurn(), verifierPassTurn()]);
      final baselineAdapter =
          FakeModelAdapter([parseFailureTurn(), verifierPassTurn()]);

      final withShadow = await buildDefault(shadowAdapter).runStudent(
        question: '求动摩擦因数',
        conversationId: 'conv-1',
      );
      final withoutShadow = await buildNoShadow(baselineAdapter).runStudent(
        question: '求动摩擦因数',
        conversationId: 'conv-1',
      );

      final shadow = withShadow.studentRun!.shadowVerification;
      expect(shadow, isNotNull);
      expect(
        shadow!.status,
        VerificationPipelineStatus.solverClarificationRequired,
      );
      expect(shadow.handoff, isNull);
      expect(shadow.clarification, isNotNull);
      expect(shadow.clarification!.reason, contains('无法解析'));
      expect(shadow.delivery, isNull);

      // 交付与关闭 shadow 时一致。
      expect(withShadow.studentRun!.stage, withoutShadow.studentRun!.stage);
      expect(withShadow.studentRun!.verdict, withoutShadow.studentRun!.verdict);
      expect(withShadow.studentRun!.verified, withoutShadow.studentRun!.verified);
      expect(withShadow.answerSheet.result, withoutShadow.answerSheet.result);
      expect(withShadow.answerSheet.result, '某答案');
      expect(withShadow.studentRun!.shadowVerificationError, isNull);
    });

    test('controller 把本次 run 的最终答案/claims 交给 shadow（只调一次）',
        () async {
      final recorder = _RecordingShadowVerification();
      final adapter = FakeModelAdapter([cleanSolveTurn(), verifierPassTurn()]);
      final controller = StudentModeController(
        solver: StudentSolver(reasonAdapter: adapter),
        traceStore: StudentTraceStore(supportDirectory: () async => temp),
        processAuditorFactory: cleanAuditor(),
        shadowVerifier: recorder,
      );

      final outcome = await controller.runStudent(
        question: shadowQuestion,
        conversationId: 'conv-1',
      );

      expect(recorder.calls, hasLength(1));
      final call = recorder.calls.single;
      expect(call.runId, outcome.studentRun!.run.id);
      expect(call.question, shadowQuestion);
      expect(call.frozenAnswer, outcome.answerSheet.result);
      expect(call.rawReasoning, contains('由向心力公式'));
      expect(call.processText, cleanProcess);
      expect(call.claims, isNotEmpty);
      expect(outcome.studentRun!.shadowVerification, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Claim 落库与验证后经验（设计文档 §5.4 / §5.5 / §7.4）
  // ---------------------------------------------------------------------------
  group('runStudent 落库与经验', () {
    List<ModelEvent> solveTurn() => [
          const ModelTextDelta(
            '【题型】解答题\n【答案】μ=0.5\n【过程】由牛顿第二定律得必要步骤。',
          ),
          const ModelTurnDone(
            finishReason: 'stop',
            promptTokens: 100,
            completionTokens: 40,
          ),
        ];

    List<ModelEvent> verifierPassTurn() => [
          const ModelTextDelta(
            '{"verdict":"pass","issues":[],"confidence":0.9}',
          ),
          const ModelTurnDone(finishReason: 'stop', completionTokens: 10),
        ];

    List<ModelEvent> verifierFailTurn() => [
          const ModelTextDelta(
            '{"verdict":"fail","failure_type":"missing_answer","issues":["缺第(2)问"]}',
          ),
          const ModelTurnDone(finishReason: 'stop', completionTokens: 10),
        ];

    List<ModelEvent> verifierUnknownTurn() => [
          const ModelTextDelta('{"verdict":"unknown","issues":["信息不足"]}'),
          const ModelTurnDone(finishReason: 'stop', completionTokens: 10),
        ];

    StudentModeController buildRunController(
      FakeModelAdapter adapter, {
      ExperienceStore? experienceStore,
      StudentProcessAuditSource Function()? processAuditorFactory,
      StudentRunRecorder? recorder,
    }) {
      return StudentModeController(
        solver: StudentSolver(reasonAdapter: adapter),
        traceStore: StudentTraceStore(supportDirectory: () async => temp),
        experienceStore: experienceStore,
        processAuditorFactory: processAuditorFactory,
        recorder: recorder,
      );
    }

    test('验证通过：写一条 student_exam 经验，带 run/verifier provenance',
        () async {
      final repository = InMemoryExperienceRepository();
      final store = ExperienceStore(repository: repository);
      final adapter = FakeModelAdapter([solveTurn(), verifierPassTurn()]);
      final controller = buildRunController(adapter, experienceStore: store);

      final outcome = await controller.runStudent(
        question: '求动摩擦因数',
        conversationId: 'conv-1',
      );

      expect(outcome.verified, isTrue);
      expect(repository.allRows, hasLength(1));
      final row = repository.allRows.single;
      expect(row.cluster, StudentModeController.experienceCluster);
      expect(row.cluster, 'student_exam');
      expect(row.action, StudentModeController.experienceAction);
      expect(row.action, 'verified_answer');
      expect(row.stateKey, startsWith('q-'));
      expect(row.reward, 1.0);
      expect(row.version, 1);
      expect(row.revokedAt, isNull);
      // provenance 指向这次 run 与独立验证器（不是模型自评）。
      expect(row.provenanceRunId, outcome.studentRun!.run.id);
      expect(row.provenanceVerifierId, 'student_independent_v1');
    });

    test('内容验证 fail（repair 后仍 fail）：不写经验', () async {
      final repository = InMemoryExperienceRepository();
      final store = ExperienceStore(repository: repository);
      // solve -> verify(fail) -> repair -> verify(fail)
      final adapter = FakeModelAdapter([
        solveTurn(),
        verifierFailTurn(),
        solveTurn(),
        verifierFailTurn(),
      ]);
      final controller = buildRunController(adapter, experienceStore: store);

      final outcome = await controller.runStudent(
        question: '求动摩擦因数',
        conversationId: 'conv-1',
      );

      expect(outcome.studentRun!.stage, StudentRunStage.finalizedUnverified);
      expect(outcome.verified, isFalse);
      expect(repository.allRows, isEmpty);
    });

    test('内容验证 unknown：不写经验', () async {
      final repository = InMemoryExperienceRepository();
      final store = ExperienceStore(repository: repository);
      final adapter = FakeModelAdapter([solveTurn(), verifierUnknownTurn()]);
      final controller = buildRunController(adapter, experienceStore: store);

      final outcome = await controller.runStudent(
        question: '求动摩擦因数',
        conversationId: 'conv-1',
      );

      expect(outcome.studentRun!.verdict, Verdict.unknown);
      expect(repository.allRows, isEmpty);
    });

    test('内容 pass 但过程 blocker：降级为未验证，也不写经验', () async {
      final repository = InMemoryExperienceRepository();
      final store = ExperienceStore(repository: repository);
      // 内容 pass 但过程 loop：会先做一次 repair，复验 pass 后过程仍 blocked，
      // 终态只能是 finalized_unverified。
      final adapter = FakeModelAdapter([
        solveTurn(),
        verifierPassTurn(),
        solveTurn(),
        verifierPassTurn(),
      ]);
      final controller = buildRunController(
        adapter,
        experienceStore: store,
        processAuditorFactory: () => _FixedAuditor(
          report: const ProcessReport(
            loopDetected: true,
            stagnation: false,
            repeatedClaimCount: 0,
            selfDoubtCount: 0,
            flags: ['repeated_sentence'],
            extractedClaims: [],
          ),
        ),
      );

      final outcome = await controller.runStudent(
        question: '求动摩擦因数',
        conversationId: 'conv-1',
      );

      expect(outcome.studentRun!.stage, StudentRunStage.finalizedUnverified);
      expect(outcome.studentRun!.verdict, Verdict.pass);
      expect(outcome.verified, isFalse);
      expect(
        outcome.studentRun!.run.stopReason,
        isNotNull,
      );
      expect(outcome.studentRun!.run.stopReason!.id, 'process_loop');
      expect(repository.allRows, isEmpty);
    });

    test('run 结束后 claim 落 agent_claims 行（真实 Drift 表）', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final claim = Claim(
        id: 'claim-abc123',
        kind: ClaimKind.equation,
        canonical: 'μ=0.5',
        statement: '所以 μ=0.5',
        status: ClaimStatus.proposed,
        createdAtMs: 0,
      );
      final adapter = FakeModelAdapter([solveTurn(), verifierPassTurn()]);
      final controller = buildRunController(
        adapter,
        recorder: AgentRunStoreRecorder(AgentRunStore(database)),
        processAuditorFactory: () => _FixedAuditor(claims: [claim]),
      );

      final outcome = await controller.runStudent(
        question: '求动摩擦因数',
        conversationId: 'conv-1',
      );

      expect(outcome.verified, isTrue);
      final rows = await database.select(database.agentClaims).get();
      expect(rows, hasLength(1));
      expect(rows.single.runId, outcome.studentRun!.run.id);
      expect(rows.single.canonical, 'μ=0.5');
      expect(rows.single.statement, '所以 μ=0.5');
      expect(rows.single.status, 'proposed');
      // run 行也落了（recorder 已接线）。
      expect(
        await database.select(database.agentRuns).get(),
        hasLength(1),
      );
    });
  });
}

class _FixedAuditor implements StudentProcessAuditSource {
  _FixedAuditor({
    this.report = ProcessReport.clean,
    List<Claim> claims = const <Claim>[],
  }) : claims = List.unmodifiable(claims);

  final ProcessReport report;
  final List<Claim> claims;

  @override
  Future<StudentProcessAuditResult> audit({
    required String reasoning,
    String? previousReasoning,
    List<String> actionSequence = const [],
    String? stateFingerprint,
    String? previousStateFingerprint,
  }) async {
    return StudentProcessAuditResult(
      report: report,
      claimSummary: ClaimSummary.of(claims),
      claims: claims,
    );
  }
}

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

/// 记录 controller 实际传给 shadow 的输入，再委托真相机；
/// 用来证明生产接线真的接上了，而不是只在 controller 单测里 mock 掉。
class _RecordingShadowVerification implements StudentShadowVerification {
  final List<_ShadowCall> calls = [];
  final StudentShadowVerification _delegate =
      const DeterministicShadowVerification();

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

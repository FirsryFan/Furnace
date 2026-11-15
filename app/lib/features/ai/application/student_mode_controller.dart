import '../../../data/ids.dart';
import '../domain/agent_run.dart';
import '../domain/claim.dart';
import '../domain/model_adapter.dart';
import '../domain/process_auditor.dart';
import '../domain/step_guard.dart';
import '../domain/student_answer_sheet.dart';
import '../domain/student_composition.dart';
import '../domain/student_run.dart';
import '../domain/student_shadow_verification.dart';
import '../domain/student_solver.dart';
import '../domain/verifier.dart';
import '../infrastructure/agent_run_store.dart';
import '../infrastructure/experience_store.dart';
import '../infrastructure/student_process_auditor.dart';
import '../infrastructure/student_trace_store.dart';
import '../infrastructure/student_verifier.dart';

/// The result of one direct student-mode run.
///
/// It wraps [StudentSolverResult] instead of flattening it so no caller can
/// drift from the solver's own definition of "answered" (`result.ok`), the
/// answer sheet, or the usage fields, while the trace location stays a
/// caller-level concern.
class StudentModeOutcome {
  const StudentModeOutcome({
    required this.question,
    required this.result,
    required this.imageCount,
    this.tracePath,
    this.traceError,
    this.studentRun,
  });

  /// A solve that never reached the solver (the controller itself failed).
  /// Kept as an outcome rather than a thrown exception so the caller reports the
  /// failure in the same shape as a normal answer.
  factory StudentModeOutcome.failed({
    required String question,
    required int imageCount,
    required String error,
  }) {
    return StudentModeOutcome(
      question: question,
      imageCount: imageCount,
      result: StudentSolverResult(
        phase: StudentSolvePhase.failed,
        answer: '',
        answerSheet: StudentAnswerSheet.failed(''),
        reasoning: '',
        attempts: 0,
        error: error,
      ),
    );
  }

  final String question;
  final StudentSolverResult result;

  /// How many pictures were handed to the solver for this solve.
  final int imageCount;

  /// Absolute path of the local JSON trace, or null when it could not be
  /// written.
  final String? tracePath;

  /// Why the trace was not written. Non-null only when [tracePath] is null and
  /// the solve itself succeeded far enough to try.
  final String? traceError;

  /// Set only by the new student-run path ([StudentModeController.runStudent]);
  /// null for the legacy direct-solver path and for [StudentModeOutcome.failed].
  ///
  /// It carries the state-machine path, process report and verification so a
  /// caller can show "verified / unverified" without re-parsing anything.
  final StudentRunResult? studentRun;

  bool get ok => result.ok;

  StudentAnswerSheet get answerSheet => result.answerSheet;

  /// Whether this outcome came from the `StudentRun` state machine (new path)
  /// rather than the legacy direct solver call.
  bool get usedStudentRun => studentRun != null;

  /// Whether the answer passed the independent content verifier. The legacy
  /// path never verifies, so it reports false rather than pretending.
  bool get verified => studentRun?.verified ?? false;
}

/// Adapts the infrastructure [AgentRunStore] to the domain [StudentRunRecorder].
///
/// Kept in the application layer so `student_run.dart` (domain) never imports
/// the database: the domain defines the interface, this class is the wiring.
class AgentRunStoreRecorder implements StudentRunRecorder {
  AgentRunStoreRecorder(this._store);

  final AgentRunStore _store;

  @override
  Future<void> saveRun(AgentRunState run) => _store.saveRun(run);

  @override
  Future<void> appendStep(AgentStep step) => _store.saveStep(step);

  @override
  Future<String> saveProcessAudit({
    required String runId,
    required ProcessReport report,
  }) {
    return _store.saveProcessAudit(runId: runId, report: report);
  }

  @override
  Future<String> saveContentVerification({
    required String runId,
    required String verifierId,
    required Verification verification,
  }) {
    return _store.saveVerification(
      runId: runId,
      verifierId: verifierId,
      verification: verification,
      kind: VerifierKind.content,
    );
  }

  @override
  Future<void> saveClaims({
    required String runId,
    required List<Claim> claims,
  }) {
    return _store.saveClaims(runId: runId, claims: claims);
  }
}

/// The application-layer, direct student-mode path.
///
/// This is deliberately **not** a tool and not a second turn of the main agent
/// loop. The caller supplies the question (and the picture) and the isolated
/// student pipeline answers it; there is no main-loop dependency at all - no
/// conversation history, no tool registry - and therefore no chance for the
/// assistant to "decide" whether to delegate or to describe the figure instead
/// of solving it.
///
/// Two entry points:
///
///  * [runStudent] - the design's `StudentRun` state machine
///    (solve → answer → process audit → content verify → repair ≤ 1 → finalize),
///    used by the `student_solver` preset;
///  * [solve] - the legacy direct `StudentSolver` call, kept as the compatibility
///    baseline (design §13.6) and covered by the pre-existing tests.
///
/// The controller owns the three pieces of state that would otherwise leak
/// between the caller and the solver:
///
///  * the [StudentSolver] bound to the 20k/3k budget pair;
///  * the images of the message currently being solved - the picture is passed
///    straight through, the user never has to describe it;
///  * the [StudentTraceStore] that writes the raw reasoning to a local file.
class StudentModeController {
  StudentModeController({
    required StudentSolver solver,
    required StudentTraceStore traceStore,
    Verifier? verifier,
    AnswerOracle? verifierOracle,
    StudentProcessAuditSource Function()? processAuditorFactory,
    StudentRunRecorder? recorder,
    ExperienceStore? experienceStore,
    StudentComposition composition = StudentComposition.standard,
    StepGuard Function()? stepGuardFactory,
    this.shadowVerifier = const DeterministicShadowVerification(),
    int Function()? now,
  })  : _solver = solver,
        _traceStore = traceStore,
        _verifier = verifier,
        _verifierOracle = verifierOracle,
        _processAuditorFactory =
            processAuditorFactory ?? _defaultProcessAuditorFactory,
        _recorder = recorder,
        _experienceStore = experienceStore,
        _composition = composition,
        _stepGuardFactory = stepGuardFactory,
        _now = now;

  static StudentProcessAuditSource _defaultProcessAuditorFactory() =>
      StudentProcessAuditor();

  /// 验证后经验的聚类键（设计文档 §5.5；学生答题归入 `student_exam`）。
  static const String experienceCluster = 'student_exam';

  /// 验证后经验的 action 键：这次 run 得到的经验就是「答案已验证」。
  static const String experienceAction = 'verified_answer';

  final StudentSolver _solver;
  final StudentTraceStore _traceStore;

  /// Independent content verifier. Null means "derive the shipped
  /// `StudentVerifier` from the solver's reasoning adapter" - same model, a
  /// fresh turn with no solver context (design §7.3 "同一模型独立调用").
  final Verifier? _verifier;

  /// 可选标准答案裁决器；只在 verifier 侧使用，不进入 solver prompt。
  final AnswerOracle? _verifierOracle;

  /// One process auditor per run: its `ClaimLedger` holds run-scoped claim
  /// versions and must not leak into the next run.
  final StudentProcessAuditSource Function() _processAuditorFactory;

  /// DB recorder; null means "run without persisting run/steps/verifications"
  /// (the legacy direct path does not persist them either).
  final StudentRunRecorder? _recorder;

  /// 验证后经验库（设计文档 §5.5 / §12 Phase D）；null 表示不写经验。
  final ExperienceStore? _experienceStore;

  final StudentComposition _composition;
  final StepGuard Function()? _stepGuardFactory;

  /// Shadow 预检（task-32/33）：生产学生 run 默认启用确定性 precheck + clean
  /// handoff，只把结果记录在 [StudentRunResult.shadowVerification]，**不参与**
  /// 交付（stage/verdict/verified/answer/repair 都不读它，也不写 DB/UI）。
  ///
  /// 传 `null` 可关闭（测试基线用）。
  final StudentShadowVerification? shadowVerifier;

  final int Function()? _now;

  List<ChatImagePart> _images = const [];

  /// The pictures of the message being solved. The caller sets them before
  /// calling [solve]/[runStudent]; the run receives exactly these unless a
  /// caller passes a one-off list.
  List<ChatImagePart> get currentImages => _images;

  void setImages(Iterable<ChatImagePart> images) {
    _images = List.unmodifiable(images);
  }

  void clearImages() {
    _images = const [];
  }

  /// Runs the full student state machine for [question] (design §3.2/§8).
  ///
  /// This is what the `student_solver` preset uses. The pipeline is bounded:
  /// at most one repair, at most [StudentComposition.maxTotalVerifierCalls]
  /// content verifications, no tools. It never throws for a model-side failure:
  /// a failed run is returned as an outcome (with the answer sheet kept when
  /// there is one).
  ///
  /// [conversationId] is recorded on the `agent_runs` row; [questionId] only
  /// lands in the local trace.
  Future<StudentModeOutcome> runStudent({
    required String question,
    required String conversationId,
    List<ChatImagePart>? images,
    String? questionId,
  }) async {
    final text = question.trim();
    final effectiveImages = List<ChatImagePart>.unmodifiable(images ?? _images);
    if (text.isEmpty && effectiveImages.isEmpty) {
      throw ArgumentError(
        'student mode needs a question text or at least one image',
      );
    }

    // 一次 run 一个 verifier 实例：它的 id 既是 `agent_verifications.verifier`
    // 的取值，也是本次 run 经验 provenance 的一部分。
    final verifier =
        _verifier ??
        StudentVerifier(
          // 验证器只需要“独立重解 + 对照 + JSON”，不需要 solver 的 20k
          // reasoning 预算。用回答 adapter（3k, deepseek-chat）避免 verifier
          // 把 20k 全花在思考上、正文 0 字符、finish=length。
          adapter: _solver.answerAdapter ?? _solver.reasonAdapter,
          oracle: _verifierOracle,
        );
    final run = StudentRun(
      reasonAdapter: _solver.reasonAdapter,
      answerAdapter: _solver.answerAdapter,
      composition: _composition,
      processAuditor: _processAuditorFactory(),
      verifier: verifier,
      recorder: _recorder,
      shadowVerifier: shadowVerifier,
      stepGuard: _stepGuardFactory?.call(),
      now: _now,
    );

    final result = await run.execute(
      runId: Ids.next('run'),
      conversationId: conversationId,
      question: text,
      images: effectiveImages,
    );

    final modelCalls = result.stages
        .where((stage) =>
            stage == StudentRunStage.solving ||
            stage == StudentRunStage.answering ||
            stage == StudentRunStage.repairing)
        .length;
    final solverResult = StudentSolverResult(
      phase: result.answered ? StudentSolvePhase.answered : StudentSolvePhase.failed,
      answer: result.answerSheet.result,
      answerSheet: result.answerSheet,
      reasoning: result.reasoning,
      attempts: modelCalls,
      promptTokens: result.run.promptTokens,
      completionTokens: result.run.completionTokens,
      finishReason: result.finishReason,
      error: result.answered ? null : (result.error ?? 'no usable answer'),
    );

    String? tracePath;
    String? traceError;
    try {
      tracePath = await _traceStore.save(
        question: text,
        questionId: questionId,
        result: solverResult,
      );
      // The trace path belongs on the run row (design §8 persistence).
      result.run.attachTrace(tracePath);
      final recorder = _recorder;
      if (recorder != null) {
        await recorder.saveRun(result.run);
      }
    } catch (error) {
      // A failed trace write must not lose the answer the run already paid
      // for; the card shows the trace problem instead.
      traceError = error.toString();
    }

    // 只在验证通过后写经验（设计文档 §5.5：经验不是模型自评）。
    await _recordVerifiedExperience(
      question: text,
      result: result,
      verifierId: verifier.id,
    );

    return StudentModeOutcome(
      question: text,
      result: solverResult,
      imageCount: effectiveImages.length,
      tracePath: tracePath,
      traceError: traceError,
      studentRun: result,
    );
  }

  /// 验证通过时写一条经验（设计文档 §5.5 / §12 Phase D）。
  ///
  /// 只有**内容验证 pass 且过程审计无 blocker** 的 run 才写：这类 run 的终态是
  /// [StudentRunStage.finalized]，答案卡已经过独立内容验证。[Verdict.fail] /
  /// `unknown` / `error`，以及被过程 blocker 降级的 `finalized_unverified` 都不
  /// 写——经验不能来自「模型自己觉得对」或「只是没看出问题」。
  ///
  /// `state_key` 用题面 hash（同一题面跨 run 可召回），`action` 是
  /// [experienceAction]，并带上 run / verifier 两条 provenance。写失败只吞掉：
  /// 经验是旁路，不能把已经验证的答案变成失败。
  Future<void> _recordVerifiedExperience({
    required String question,
    required StudentRunResult result,
    required String verifierId,
  }) async {
    final store = _experienceStore;
    if (store == null || !result.verified) {
      return;
    }
    final answer = result.answerSheet.result.trim();
    if (answer.isEmpty) {
      return;
    }
    final stateKey = 'q-${stableClaimHash(question)}';
    try {
      await store.record(
        claim: Claim(
          id: 'student-answer-${stableClaimHash(question)}',
          kind: ClaimKind.decision,
          canonical: answer,
          statement: answer,
          status: ClaimStatus.verified,
          checkedVersion: 1,
          evidence: '内容验证 pass（verifier=$verifierId）',
        ),
        cluster: experienceCluster,
        stateKey: stateKey,
        action: experienceAction,
        reward: 1.0,
        provenanceRunId: result.run.id,
        provenanceVerifierId: verifierId,
        nowMs: _now?.call(),
      );
    } catch (_) {
      // 见 doc：经验写失败不改变 run 的结论。
    }
  }

  /// Solves [question] directly with [StudentSolver] (legacy compatibility
  /// path, kept as the design's baseline in §13.6).
  ///
  /// [images] overrides [currentImages] for this call only. A question may be
  /// empty when at least one image is supplied - a photographed problem is a
  /// legitimate input with no typed stem.
  ///
  /// Never throws for a model-side failure: [StudentSolver] reports that as a
  /// failed result. It does throw for a call with neither text nor image,
  /// because that is a caller bug rather than a user-facing answer.
  Future<StudentModeOutcome> solve({
    required String question,
    List<ChatImagePart>? images,
    String? questionId,
  }) async {
    final text = question.trim();
    final effectiveImages = List<ChatImagePart>.unmodifiable(images ?? _images);
    if (text.isEmpty && effectiveImages.isEmpty) {
      throw ArgumentError(
        'student mode needs a question text or at least one image',
      );
    }

    final result = await _solver.solve(question: text, images: effectiveImages);

    String? tracePath;
    String? traceError;
    try {
      tracePath = await _traceStore.save(
        question: text,
        questionId: questionId,
        result: result,
      );
    } catch (error) {
      // A failed trace write must not lose the answer the solver already paid
      // for; the card shows the trace problem instead.
      traceError = error.toString();
    }

    return StudentModeOutcome(
      question: text,
      result: result,
      imageCount: effectiveImages.length,
      tracePath: tracePath,
      traceError: traceError,
    );
  }
}

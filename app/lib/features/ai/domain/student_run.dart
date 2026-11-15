/// 学生模式的状态机：solve → answer → process audit → content verify →
/// repair(≤1) → finalize（设计文档 §3.2 与 §8）。
///
/// 这是学生 preset 的**执行者**，不是主 `AgentLoop` 的一个分支：它不知道
/// 工具注册表、不读会话历史、没有会话发送入口，只拿着
///
///  * 一个 [StudentComposition]（prompt / 预算 / repair 与验证次数上限）；
///  * 两个模型 adapter（reason 20k、answer/repair 3k reserve）；
///  * 一个可选的 [StudentProcessAuditSource]（读 CoT 查循环/自我怀疑/无进展）；
///  * 一个可选的 [Verifier]（只看题目 + 答案卡 + claim 摘要的内容验证）；
///  * 一个可选的 [StudentRunRecorder]（把 run / step / verification 落库）；
///
/// 然后把一次学生作答跑完。依赖全部是 domain 接口，所以本文件不 import 任何
/// infrastructure：状态机可以在没有数据库、没有网络的情况下被测试逐条驱动。
///
/// 两条边界必须守住（测试里是断言）：
///
///  * **内容验证不读 reasoning**：[Verifier.verify] 的签名里根本没有 reasoning
///    参数；本文件也绝不把 CoT 塞进 verifier 的输入。
///  * **失败不伪装成通过**：`fail` 只触发一次 repair，`unknown`/`error` 直接
///    以「未验证」收尾；最终答复卡始终保留（设计文档 §3.2）。
///
/// 第三条边界（设计文档 §7.4）：**过程 blocker 不能静默 pass**。过程审计的
/// 循环/停滞/自我怀疑报告进入本文件的 gate（[StudentProcessBlocker] +
/// [StepGuardDecision]），内容验证即使 pass 也要先 repair 一次；repair 预算用尽
/// 则降级为 `finalized_unverified` 并把 `stop_reason` 记成
/// `process_loop` / `process_self_doubt`——不会无限重写。
///
/// 第四条边界（task-32 shadow 接线）：可选的 [StudentShadowVerification] 在 run
/// 结束时对同一份 reasoning/answer/claims 跑确定性 precheck + clean handoff，
/// 结果只写进 [StudentRunResult.shadowVerification]。它是旁路：不改变
/// stage/verdict/verified/answer、不触发 repair、不调用 Checker LLM、不写 DB；
/// 没注入实现（默认 null）时所有行为与接入前一致。
///
/// 第五条边界（task-41）：可选的 [DeterministicAnswerGate] 在 run 结束时对最终
/// 答案卡跑一次确定性锚点检查（required 缺失 -> fail；ifReferenced 未出现 ->
/// skip；ifUsed 无法判断 -> unknown），结果只写进
/// [StudentRunResult.shadowAnswerGate]。它不 gate 交付、不触发 repair、不改
/// stage/verdict/verified/answer，也不写 DB/UI；默认 null 时行为不变。
library;

import 'dart:convert';

import 'agent_run.dart';
import 'answer_gate.dart';
import 'claim.dart';
import 'model_adapter.dart';
import 'process_auditor.dart';
import 'step_guard.dart';
import 'student_answer_sheet.dart';
import 'student_composition.dart';
import 'student_shadow_verification.dart';
import 'verification_pipeline.dart';
import 'verifier.dart';

/// 学生 run 阶段（设计文档 §8）。
///
/// [AgentPhase] 是全局层落库用的粗阶段；这里保留更细的学生语义，[phase] 给出
/// 两者之间的映射（`auditing` 与 `verifying` 都落 `verify`，`finalized*` 落
/// `present`）。测试断言用户可见的状态机路径时看的是本枚举的顺序。
enum StudentRunStage {
  solving('solving', AgentPhase.solve),
  answering('answering', AgentPhase.answer),
  auditing('auditing', AgentPhase.verify),
  verifying('verifying', AgentPhase.verify),
  repairing('repairing', AgentPhase.repair),
  finalized('finalized', AgentPhase.present),
  finalizedUnverified('finalized_unverified', AgentPhase.present),
  failed('failed', AgentPhase.solve);

  const StudentRunStage(this.id, this.phase);

  /// 落 step / 日志用的稳定值。
  final String id;

  /// 对应的全局 [AgentPhase]。
  final AgentPhase phase;
}

/// 过程层 blocker：过程审计认为「这段推理在打转」的信号。
///
/// 内容验证（[Verifier]）不读 CoT，所以它看不见这些；正因如此，内容判 pass 也
/// 不能把这类运行直接定稿（设计文档 §7.4 / §8）。每个 blocker 对应
/// `agent_runs.stop_reason` 的一个稳定 id。
enum StudentProcessBlocker {
  /// 循环或无进展（`ProcessReport.loopDetected || stagnation`）。
  loop('process_loop', StopReason.processLoop),

  /// 反复自我怀疑达到阈值（`self_doubt` 标记：次数或每千字密度）。
  selfDoubt('process_self_doubt', StopReason.processSelfDoubt);

  const StudentProcessBlocker(this.id, this.stopReason);

  /// 人/日志用的稳定值。
  final String id;

  /// 写进 `agent_runs.stop_reason` 的原因。
  final StopReason stopReason;
}

/// 一次过程审计的结果：报告本身 + 给内容验证器的结构化摘要 + 实际 claim 列表。
///
/// 这个类型放在 domain 而不是 infrastructure，是因为 [StudentRun] 只依赖这个
/// 抽象，`StudentProcessAuditor`（infrastructure）实现它——依赖方向仍是
/// domain ← infrastructure。
class StudentProcessAuditResult {
  const StudentProcessAuditResult({
    required this.report,
    required this.claimSummary,
    this.claims = const <Claim>[],
    this.registeredClaims = 0,
    this.mergedClaims = 0,
  });

  /// 过程审计报告（循环 / 停滞 / 自我怀疑 / 抽取的 claim）。
  final ProcessReport report;

  /// 交给**内容验证器**的结构化摘要；不含 reasoning 原文（设计文档 §7.3）。
  final ClaimSummary claimSummary;

  /// 本次审计实际得到的 claim 列表（有 ClaimLedger 时是去重后的摘要，没有
  /// ledger 时是本次抽取结果）。run 结束时按 run 落 `agent_claims`。
  final List<Claim> claims;

  /// 本次新登记进 ClaimLedger 的 claim 数。
  final int registeredClaims;

  /// 命中已有 claim、发生合并的次数（同一 claim 在版本未变时重复出现）。
  final int mergedClaims;

  /// 过程层 blocker；null 表示过程没有值得拦截的信号。
  ///
  /// 判定口径与设计文档 §7.4 一致：循环/停滞 -> [StudentProcessBlocker.loop]；
  /// `self_doubt` 标记 -> [StudentProcessBlocker.selfDoubt]（该标记在
  /// `ProcessAuditorConfig` 里已经是「次数达到阈值或密度达到阈值」）。循环优先
  /// 于自我怀疑：两者同时出现时先报循环。
  StudentProcessBlocker? get blocker {
    if (report.loopDetected || report.stagnation) {
      return StudentProcessBlocker.loop;
    }
    if (report.flags.contains('self_doubt')) {
      return StudentProcessBlocker.selfDoubt;
    }
    return null;
  }
}

/// 过程审计来源（读 CoT 的那一侧）。
///
/// 学生 v1 由 `StudentProcessAuditor` 实现；以后换成带模型的过程审计也实现
/// 同一个接口。输入只有 reasoning 与调用方已经算好的动作/状态序列，输出是
/// 报告 + 结构化摘要 + 实际 claim 列表（run 结束落 `agent_claims`）。
abstract interface class StudentProcessAuditSource {
  Future<StudentProcessAuditResult> audit({
    required String reasoning,
    String? previousReasoning,
    List<String> actionSequence = const [],
    String? stateFingerprint,
    String? previousStateFingerprint,
  });
}

/// run / step / verification 的持久化接口（由 `AgentRunStore` 适配实现）。
///
/// 定义在 domain 是为了让 [StudentRun] 不 import infrastructure；应用层
/// （`student_mode_controller.dart`）提供 `AgentRunStore` 的适配器。
abstract interface class StudentRunRecorder {
  /// 写入/更新一次运行（每推进一个阶段调一次）。
  Future<void> saveRun(AgentRunState run);

  /// 追加一步（每次模型调用、每次审计/验证一条）。
  Future<void> appendStep(AgentStep step);

  /// 把过程审计写成 `kind = process` 的验证记录。
  Future<String> saveProcessAudit({
    required String runId,
    required ProcessReport report,
  });

  /// 把内容验证写成 `kind = content` 的验证记录。
  Future<String> saveContentVerification({
    required String runId,
    required String verifierId,
    required Verification verification,
  });

  /// 把过程审计抽到的 claim 写成 `agent_claims` 行（设计文档 §5.4）。
  ///
  /// run 结束时调用一次。`claim.id` 是内容 hash（同一段推理的 claim id 稳定），
  /// 因此实现方需要把「哪一次 run」带进行身份；否则同一道题跑两次会互相覆盖。
  Future<void> saveClaims({
    required String runId,
    required List<Claim> claims,
  });
}

/// 一次学生 run 的结果。
///
/// [run] 是最终运行状态（含 phase/status/stop_reason/token/答案卡/trace）；
/// [stages] 是实际走过的状态机路径（测试与排障用）；[reasoning] 是 raw CoT，
/// **只给调用方写 trace**，不进数据库、不进 verifier（设计文档 §5.6/§7.3）。
class StudentRunResult {
  const StudentRunResult({
    required this.run,
    required this.stage,
    required this.stages,
    required this.answerSheet,
    required this.reasoning,
    required this.verdict,
    this.processAudit,
    this.verification,
    this.repairCount = 0,
    this.verifierCalls = 0,
    this.finishReason,
    this.error,
    this.shadowVerification,
    this.shadowVerificationError,
    this.shadowAnswerGate,
    this.shadowAnswerGateError,
  });

  final AgentRunState run;

  /// 终态阶段。
  final StudentRunStage stage;

  /// 实际走过的阶段序列（`[solving, auditing, verifying, finalized]` 等）。
  final List<StudentRunStage> stages;

  final StudentAnswerSheet answerSheet;

  /// raw reasoning（solve + repair 回合），只用于本地 trace。
  final String reasoning;

  /// 最后一次过程审计（没有配置过程审计时为 null）。
  final StudentProcessAuditResult? processAudit;

  /// 最后一次内容验证（没有配置验证器时为 null）。
  final Verification? verification;

  /// 最终内容结论；没有验证器时是 [Verdict.unknown]（未验证，不是 pass）。
  final Verdict verdict;

  final int repairCount;
  final int verifierCalls;
  final String? finishReason;

  /// solve/parse 阶段的错误（模型失败原因等）。
  final String? error;

  /// Shadow 预检结果（task-32）；没有注入 [StudentShadowVerification] 时为 null。
  ///
  /// 只记录确定性 precheck 阶段：clean 时带 `CheckerHandoff`（尚未交给 Checker），
  /// invalid/unknown/解析失败时带 `SolverClarificationRequest`。它**不参与**本次
  /// 交付：stage / verdict / verified / answer 都不读它。
  final VerificationPipelineResult? shadowVerification;

  /// Shadow 预检自身抛错时的错误文本（旁路失败，不改变 run 的结论）。
  final String? shadowVerificationError;

  /// Shadow AnswerGate 结果（task-41）；没有注入 [DeterministicAnswerGate] 时为
  /// null。
  ///
  /// 只记录确定性锚点检查（checked/skipped/issues/verdict），**不参与**本次
  /// 交付：不 gate 答案、不触发 repair、不改 stage/verdict/verified/answer，
  /// 也不写 DB/UI。
  final AnswerGateResult? shadowAnswerGate;

  /// Shadow AnswerGate 自身抛错时的错误文本（旁路失败，不改变 run 的结论）。
  final String? shadowAnswerGateError;

  /// 是否给出了可用答案（与阶段无关：验证失败但答案仍在也是 true）。
  bool get answered => answerSheet.result.trim().isNotEmpty && stage != StudentRunStage.failed;

  /// 是否**按已验证收尾**：内容验证 pass 且过程审计没有 blocker（终态必须是
  /// [StudentRunStage.finalized]）。
  ///
  /// 不能只看 `verdict == pass`：内容 pass 但过程 blocker 的运行会被降级成
  /// `finalized_unverified`（设计文档 §7.4 / §8），它不是已验证。
  bool get verified =>
      verdict == Verdict.pass && stage == StudentRunStage.finalized;

  /// 有答案但没有通过验证（unknown/error/fail/过程 blocker 收尾）。
  bool get unverified => answered && !verified;

  @override
  String toString() => 'StudentRunResult(stage: ${stage.id}, '
      'verdict: ${verdict.id}, repairs: $repairCount, '
      'verifierCalls: $verifierCalls, answered: $answered)';
}

/// 学生 run 状态机本体。
///
/// 每个 run 一个实例（[StepGuard] 持有 run 内历史，不能跨 run 复用）。调用
/// [execute] 一次只跑一次作答；取消/重跑由调用方新建实例完成。
class StudentRun {
  StudentRun({
    required this.reasonAdapter,
    this.answerAdapter,
    this.repairAdapter,
    this.composition = StudentComposition.standard,
    this.processAuditor,
    this.verifier,
    this.recorder,
    this.shadowVerifier,
    this.answerGate,
    StepGuard? stepGuard,
    this.now,
  }) : _stepGuard = stepGuard ?? StepGuard(budget: composition.budget);

  /// reasoning 回合（20k 预算）用的 adapter。
  final ModelAdapter reasonAdapter;

  /// 答案誊写回合（3k reserve）用的 adapter；null 表示复用 [reasonAdapter]。
  final ModelAdapter? answerAdapter;

  /// repair 回合用的 adapter；null 表示复用 answer adapter。
  final ModelAdapter? repairAdapter;

  final StudentComposition composition;

  /// 读 CoT 的过程审计来源；null 表示这一步跳过（学生 v1 总是配置）。
  final StudentProcessAuditSource? processAuditor;

  /// 只看题目/答案卡/claim 摘要的内容验证器；null 表示本次不验证，终态按
  /// `unknown` 收尾（未验证，不是 pass）。
  final Verifier? verifier;

  /// 落库接口；null 表示只跑不落库（纯单元测试/兼容路径）。
  final StudentRunRecorder? recorder;

  /// Shadow 预检依赖（task-32）；null 表示不跑 shadow，旧行为 byte 相同。
  ///
  /// 它只接收 run 结束时的 reasoning/answer/claims，输出
  /// [StudentRunResult.shadowVerification]；不接模型、不写 DB、不改变交付。
  final StudentShadowVerification? shadowVerifier;

  /// Shadow AnswerGate（task-41）；null 表示不跑，行为与接入前一致。
  ///
  /// 只对最终答案卡做确定性锚点检查，结果写进
  /// [StudentRunResult.shadowAnswerGate]；不 gate 答案、不触发 repair、不改
  /// stage/verdict/verified/answer，不写 DB/UI。
  final DeterministicAnswerGate? answerGate;

  /// 可注入时钟（epoch ms），测试用来让 run 的起止可复现。
  final int Function()? now;

  final StepGuard _stepGuard;

  ModelAdapter get _answerAdapter => answerAdapter ?? reasonAdapter;

  ModelAdapter get _repairAdapter => repairAdapter ?? _answerAdapter;

  /// 把一次学生作答跑完。
  ///
  /// [runId] 由调用方给（应用层用 `Ids.next('run')`，测试用固定值），域层不
  /// 自己从时钟造 id。流程与设计文档 §3.2/§8 一致，最多一次 repair、最多
  /// [StudentComposition.maxTotalVerifierCalls] 次内容验证；任何一步失败都不
  /// 抛异常，而是以 [StudentRunResult] 的失败/未验证终态返回。
  Future<StudentRunResult> execute({
    required String runId,
    required String conversationId,
    required String question,
    List<ChatImagePart> images = const [],
    int? startedAt,
  }) async {
    final clock = now ?? () => DateTime.now().millisecondsSinceEpoch;
    final started = startedAt ?? clock();
    final run = AgentRunState.start(
      id: runId,
      conversationId: conversationId,
      presetId: composition.id,
      mode: composition.mode,
      startedAt: started,
    );
    final stages = <StudentRunStage>[];
    var seq = 0;
    var repairCount = 0;
    var verifierCalls = 0;
    var reasoning = '';
    var solveReasoning = '';
    var sheet = StudentAnswerSheet.failed('');
    var verdict = Verdict.unknown;
    Verification? verification;
    StudentProcessAuditResult? processAudit;
    String? finishReason;
    String? error;
    String? lastFingerprint;

    Future<void> saveRun() async {
      final store = recorder;
      if (store == null) {
        return;
      }
      try {
        await store.saveRun(run);
      } catch (_) {
        // 落库失败不阻断作答：答案已经花过模型预算，不能因为 DB 抖动丢掉。
      }
    }

    Future<void> appendStep({
      required AgentPhase phase,
      required AgentStepKind kind,
      required AgentStepStatus status,
      String? summary,
      int? tokens,
      String? stateFingerprint,
      String? claimHash,
    }) async {
      final store = recorder;
      if (store == null) {
        return;
      }
      final step = AgentStep(
        id: '$runId-s$seq',
        runId: runId,
        seq: seq,
        phase: phase,
        kind: kind,
        status: status,
        createdAt: clock(),
        tokens: tokens,
        summary: summary,
        stateFingerprint: stateFingerprint,
        claimHash: claimHash,
      );
      seq += 1;
      try {
        await store.appendStep(step);
      } catch (_) {
        // 同上：审计写失败不该让本次作答失败。
      }
    }

    void enter(StudentRunStage stage) {
      stages.add(stage);
      run.enterPhase(stage.phase);
    }

    String fingerprintOf(StudentRunStage stage, StudentAnswerSheet candidate) {
      return AgentStateFingerprint.of({
        'stage': stage.id,
        'kind': candidate.kind.id,
        'result_chars': candidate.result.trim().length,
        'structured': candidate.structured,
        'process_chars': candidate.process.trim().length,
      });
    }

    Future<StudentProcessAuditResult?> runProcessAudit({
      String? previousReasoning,
      String? previousStateFingerprint,
    }) async {
      final source = processAuditor;
      if (source == null) {
        return null;
      }
      enter(StudentRunStage.auditing);
      final fingerprint = fingerprintOf(StudentRunStage.auditing, sheet);
      StudentProcessAuditResult? result;
      try {
        result = await source.audit(
          reasoning: reasoning,
          previousReasoning: previousReasoning,
          actionSequence: [
            for (final step in stages)
              if (step == StudentRunStage.solving || step == StudentRunStage.repairing)
                step.id,
          ],
          stateFingerprint: fingerprint,
          previousStateFingerprint: previousStateFingerprint,
        );
      } catch (auditError) {
        // 过程审计是启发式旁路：它坏了不能挡住已经拿到的答案。
        error ??= 'process audit failed: $auditError';
        await appendStep(
          phase: AgentPhase.verify,
          kind: AgentStepKind.verify,
          status: AgentStepStatus.failed,
          summary: '过程审计失败',
          stateFingerprint: fingerprint,
        );
        await saveRun();
        return null;
      }
      final report = result.report;
      run.attachProcessReport(jsonEncode(report.toJson()));
      final store = recorder;
      if (store != null) {
        try {
          await store.saveProcessAudit(runId: runId, report: report);
        } catch (_) {
          // 同 saveRun。
        }
      }
      await appendStep(
        phase: AgentPhase.verify,
        kind: AgentStepKind.verify,
        status: AgentStepStatus.ok,
        summary: '过程审计：loop=${report.loopDetected}, '
            'stagnation=${report.stagnation}, flags=${report.flags.join('|')}',
        stateFingerprint: fingerprint,
        claimHash: report.extractedClaims.isEmpty
            ? null
            : report.extractedClaims.first.canonicalHash,
      );
      lastFingerprint = fingerprint;
      await saveRun();
      return result;
    }

    await saveRun();

    // --- solve -------------------------------------------------------------
    enter(StudentRunStage.solving);
    final solve = await _runModel(
      reasonAdapter,
      [
        ChatMessage.system(composition.systemPrompt),
        ChatMessage.user(question, images: images),
      ],
    );
    solveReasoning = solve.reasoning;
    reasoning = solve.reasoning;
    sheet = StudentAnswerSheet.parse(solve.text);
    finishReason = solve.finishReason;
    run.recordStep(
      promptTokens: solve.promptTokens,
      completionTokens: solve.completionTokens,
      reasoningChars: solve.reasoning.length,
    );
    final solveFingerprint = fingerprintOf(StudentRunStage.solving, sheet);
    await appendStep(
      phase: AgentPhase.solve,
      kind: AgentStepKind.model,
      status: solve.failed ? AgentStepStatus.failed : AgentStepStatus.ok,
      summary: 'solve 模型调用',
      tokens: solve.completionTokens,
      stateFingerprint: solveFingerprint,
    );
    lastFingerprint = solveFingerprint;
    await saveRun();
    error ??= solve.error;

    var usable = _isUsableAnswer(sheet, solve.text, solve.finishReason);
    final afterSolve = _stepGuard.check(
      run: run,
      actionKey: AgentActionKey.ofStep(AgentStepKind.model, phase: AgentPhase.solve),
      stateFingerprint: solveFingerprint,
      nowMs: clock(),
      reasoningTokens: run.reasoningTokens,
      completionTokens: run.completionTokens,
      repairsUsed: repairCount,
    );
    if (afterSolve.isStop) {
      return _finalize(
        runId: runId,
        question: question,
        run: run,
        stages: stages,
        stage: usable
            ? StudentRunStage.finalizedUnverified
            : StudentRunStage.failed,
        sheet: sheet,
        reasoning: reasoning,
        verdict: verdict,
        verification: verification,
        processAudit: processAudit,
        repairCount: repairCount,
        verifierCalls: verifierCalls,
        finishReason: finishReason,
        error: error,
        stopReason: afterSolve.reason,
        answeredOverride: usable,
        clock: clock,
        saveRun: saveRun,
      );
    }

    // --- answer（只在 solve 没产出可用答案时）------------------------------
    if (!usable) {
      enter(StudentRunStage.answering);
      final draft = _tail(solve.reasoning, 8000);
      final answerTurn = await _runModel(
        _answerAdapter,
        [
          ChatMessage.system(composition.answerScribePrompt),
          ChatMessage.user(question, images: images),
          if (draft.isNotEmpty) ChatMessage.assistant(content: '草稿：\n$draft'),
          if (draft.isNotEmpty)
            const ChatMessage.user('根据上面的草稿，只写出最终答案；不要重新解题。')
          else
            const ChatMessage.user('只写出最终答案；不要写推理过程。'),
        ],
      );
      reasoning = _joinReasoning(reasoning, answerTurn.reasoning);
      finishReason = answerTurn.finishReason ?? finishReason;
      if (answerTurn.text.trim().isNotEmpty) {
        sheet = StudentAnswerSheet.parse(answerTurn.text);
      }
      run.recordStep(
        promptTokens: answerTurn.promptTokens,
        completionTokens: answerTurn.completionTokens,
        reasoningChars: answerTurn.reasoning.length,
      );
      await appendStep(
        phase: AgentPhase.answer,
        kind: AgentStepKind.answer,
        status: answerTurn.failed ? AgentStepStatus.failed : AgentStepStatus.ok,
        summary: 'answer 模型调用',
        tokens: answerTurn.completionTokens,
        stateFingerprint: fingerprintOf(StudentRunStage.answering, sheet),
      );
      await saveRun();
      error ??= answerTurn.error;
      usable = _isUsableAnswer(sheet, answerTurn.text, answerTurn.finishReason);
    }

    if (!usable) {
      return _finalize(
        runId: runId,
        question: question,
        run: run,
        stages: stages,
        stage: StudentRunStage.failed,
        sheet: sheet,
        reasoning: reasoning,
        verdict: verdict,
        verification: verification,
        processAudit: processAudit,
        repairCount: repairCount,
        verifierCalls: verifierCalls,
        finishReason: finishReason,
        error: error ?? 'no usable answer',
        stopReason: StopReason.solveFailed,
        answeredOverride: false,
        clock: clock,
        saveRun: saveRun,
      );
    }

    // --- process audit ------------------------------------------------------
    processAudit = await runProcessAudit(previousReasoning: solveReasoning);

    // --- verify / repair（最多一次 repair，验证总次数见 composition）-------
    final verifierImpl = verifier;
    final maxVerifierCalls = composition.maxTotalVerifierCalls;
    while (true) {
      if (verifierImpl == null || verifierCalls >= maxVerifierCalls) {
        verdict = Verdict.unknown;
        break;
      }
      enter(StudentRunStage.verifying);
      verifierCalls += 1;
      try {
        verification = await verifierImpl.verify(
          question: question,
          answer: sheet,
          images: images,
          claims: processAudit?.claimSummary ?? const ClaimSummary.empty(),
        );
      } catch (verifyError) {
        verification = Verification.error(message: 'verifier threw: $verifyError');
      }
      verdict = verification.verdict;
      run.attachVerifierVerdict(verdict.id);
      run.addUsage(
        promptTokens: verification.promptTokens ?? 0,
        completionTokens: verification.completionTokens ?? 0,
      );
      final store = recorder;
      if (store != null) {
        try {
          await store.saveContentVerification(
            runId: runId,
            verifierId: verifierImpl.id,
            verification: verification,
          );
        } catch (_) {
          // 验证记录写失败不影响结论本身。
        }
      }
      await appendStep(
        phase: AgentPhase.verify,
        kind: AgentStepKind.verify,
        status: verification.isError ? AgentStepStatus.failed : AgentStepStatus.ok,
        summary: '内容验证：${verdict.id}'
            '${verification.failureType == null ? '' : ' (${verification.failureType!.id})'}',
        stateFingerprint: fingerprintOf(StudentRunStage.verifying, sheet),
      );
      await saveRun();

      // 过程 blocker 门控（设计 §7.4）：内容 pass 也不能盖过过程信号。
      // 有 blocker 且 repair 预算还在 -> 允许一次 repair；预算/复验次数用尽 ->
      // 保留答案、按未验证收尾，不无限重写。
      final processGate = _processGate(
        processAudit,
        repairsUsed: repairCount,
        maxRepair: composition.maxRepair,
      );
      final repairBudgetLeft = repairCount < composition.maxRepair &&
          verifierCalls < maxVerifierCalls;
      // v4 实测：verifier 的 independent answer 在物理题上会自信地给错
      // （wrong_branch），repair 会把原本正确的答案改坏。内容型
      // `wrong_branch` 只作为风险信号，不能触发改写；只有结构性缺口
      // （缺答案/缺小问/过程与答案不自洽/单位端点）才值得一次 repair。
      final structuralFailure = verdict == Verdict.fail &&
          const {
            FailureType.missingAnswer,
            FailureType.incompleteSubQuestion,
            FailureType.inconsistentProcess,
            FailureType.unitOrEndpoint,
          }.contains(verification.failureType);
      final wantsRepair = structuralFailure ||
          (verdict == Verdict.pass && processGate.isRepair);
      if (!wantsRepair || !repairBudgetLeft) {
        break;
      }

      // --- repair 一次 -----------------------------------------------------
      enter(StudentRunStage.repairing);
      repairCount += 1;
      final previousReasoning = reasoning;
      final previousFingerprint = lastFingerprint;
      final repairTurn = await _runModel(
        _repairAdapter,
        [
          ChatMessage.system(composition.repairPrompt),
          ChatMessage.user(question, images: images),
          ChatMessage.assistant(content: sheet.toPlainText()),
          ChatMessage.user(_repairInstruction(verification)),
        ],
      );
      reasoning = _joinReasoning(reasoning, repairTurn.reasoning);
      if (repairTurn.text.trim().isNotEmpty) {
        sheet = StudentAnswerSheet.parse(repairTurn.text);
      }
      run.recordStep(
        promptTokens: repairTurn.promptTokens,
        completionTokens: repairTurn.completionTokens,
        reasoningChars: repairTurn.reasoning.length,
      );
      await appendStep(
        phase: AgentPhase.repair,
        kind: AgentStepKind.repair,
        status: repairTurn.failed ? AgentStepStatus.failed : AgentStepStatus.ok,
        summary: 'repair 模型调用',
        tokens: repairTurn.completionTokens,
        stateFingerprint: fingerprintOf(StudentRunStage.repairing, sheet),
      );
      await saveRun();
      error ??= repairTurn.error;

      // 设计文档 §3.2：repair 后重跑一次过程审计，再复验。
      processAudit = await runProcessAudit(
        previousReasoning: previousReasoning,
        previousStateFingerprint: previousFingerprint,
      );
    }

    // --- finalize -----------------------------------------------------------
    // 过程 blocker 的终态后果：内容 pass 但过程打转 -> finalized_unverified，
    // 并把 stop_reason 记成 process_loop / process_self_doubt（设计 §7.4/§8）。
    final processBlocker = processAudit?.blocker;
    final blockedByProcess = processBlocker != null;
    final finalStage = (verdict == Verdict.pass && !blockedByProcess)
        ? StudentRunStage.finalized
        : StudentRunStage.finalizedUnverified;
    // 过程 blocker 的原因优先于 verifier fail/error：run 已经打转，先说清
    // “为什么停”，不要把 process_loop 掩盖成 verifier_failed。
    final stopReason = processBlocker?.stopReason ??
        (verdict == Verdict.fail ? StopReason.verifierFailed : null);
    return _finalize(
      runId: runId,
      question: question,
      run: run,
      stages: stages,
      stage: finalStage,
      sheet: sheet,
      reasoning: reasoning,
      verdict: verdict,
      verification: verification,
      processAudit: processAudit,
      repairCount: repairCount,
      verifierCalls: verifierCalls,
      finishReason: finishReason,
      error: error,
      stopReason: stopReason,
      answeredOverride: true,
      clock: clock,
      saveRun: saveRun,
    );
  }

  /// 收尾：写答案卡、落终态、保存 run 与 claim 行，返回结果。
  Future<StudentRunResult> _finalize({
    required String runId,
    required String question,
    required AgentRunState run,
    required List<StudentRunStage> stages,
    required StudentRunStage stage,
    required StudentAnswerSheet sheet,
    required String reasoning,
    required Verdict verdict,
    required Verification? verification,
    required StudentProcessAuditResult? processAudit,
    required int repairCount,
    required int verifierCalls,
    required String? finishReason,
    required String? error,
    required StopReason? stopReason,
    required bool answeredOverride,
    required int Function() clock,
    required Future<void> Function() saveRun,
  }) async {
    stages.add(stage);
    run.enterPhase(stage.phase);
    final answered = answeredOverride && sheet.result.trim().isNotEmpty;
    run.attachAnswerSheet(jsonEncode(_storedAnswerSheet(sheet)));
    if (answered && stopReason == null) {
      run.finish(AgentRunStatus.answered, nowMs: clock());
    } else if (answered) {
      run.finish(AgentRunStatus.stopped, stopReason: stopReason, nowMs: clock());
    } else {
      run.finish(
        AgentRunStatus.failed,
        stopReason: stopReason ?? StopReason.solveFailed,
        nowMs: clock(),
      );
    }
    await saveRun();
    // run 结束时把过程审计抽到的 claim 落 `agent_claims`（设计 §5.4）。
    await _saveClaims(runId, processAudit?.claims ?? const <Claim>[]);
    // Shadow 预检（task-32）：只读 run 的最终数据，结果不参与交付、不落库。
    final (shadowVerification, shadowVerificationError) = _runShadowVerification(
      runId: runId,
      question: question,
      sheet: sheet,
      reasoning: reasoning,
      claims: processAudit?.claims ?? const <Claim>[],
    );
    // Shadow AnswerGate（task-41）：只对最终答案卡做确定性锚点检查，旁路。
    final (shadowAnswerGate, shadowAnswerGateError) =
        _runShadowAnswerGate(sheet);

    return StudentRunResult(
      run: run,
      stage: stage,
      stages: List<StudentRunStage>.unmodifiable(stages),
      answerSheet: sheet,
      reasoning: reasoning,
      processAudit: processAudit,
      verification: verification,
      verdict: verdict,
      repairCount: repairCount,
      verifierCalls: verifierCalls,
      finishReason: finishReason,
      error: error,
      shadowVerification: shadowVerification,
      shadowVerificationError: shadowVerificationError,
      shadowAnswerGate: shadowAnswerGate,
      shadowAnswerGateError: shadowAnswerGateError,
    );
  }

  /// 跑一次 shadow 预检（task-32 旁路）。
  ///
  /// 输入全部来自 run 已经得出的最终数据；实现由调用方注入，默认 null 时直接
  /// 返回 `(null, null)`，不产生任何副作用。返回记录 `(结果, 错误)`：
  ///  * 没注入 -> `(null, null)`；
  ///  * 正常 -> `(VerificationPipelineResult, null)`；
  ///  * 实现抛错 -> `(null, 错误文本)`，错误不写进 `error`，不影响交付。
  (VerificationPipelineResult?, String?) _runShadowVerification({
    required String runId,
    required String question,
    required StudentAnswerSheet sheet,
    required String reasoning,
    required List<Claim> claims,
  }) {
    final shadow = shadowVerifier;
    if (shadow == null) {
      return (null, null);
    }
    try {
      return (
        shadow.verify(
          runId: runId,
          question: question,
          frozenAnswer: sheet.result,
          rawReasoning: reasoning,
          processText: sheet.process,
          claims: claims,
        ),
        null,
      );
    } catch (shadowError) {
      // Shadow 是旁路：它坏了也不能改变已经交付的答案/结论。
      return (null, shadowError.toString());
    }
  }

  /// 跑一次 shadow AnswerGate（task-41 旁路）。
  ///
  /// 输入是 run 最终写出的答案卡；实现由调用方注入，默认 null 时直接返回
  /// `(null, null)`。返回记录 `(结果, 错误)`：
  ///  * 正常 -> `(AnswerGateResult, null)`（checked/skipped/issues/verdict 都在
  ///    结果里）；
  ///  * 实现抛错 -> `(null, 错误文本)`，不写进 `error`、不影响交付。
  (AnswerGateResult?, String?) _runShadowAnswerGate(StudentAnswerSheet sheet) {
    final gate = answerGate;
    if (gate == null) {
      return (null, null);
    }
    try {
      return (gate.check(sheet), null);
    } catch (gateError) {
      // Shadow 是旁路：锚点数据有问题也不能改变已经交付的答案/结论。
      return (null, gateError.toString());
    }
  }

  /// 过程 blocker 的 StepGuard 式判定（设计 §7.4：报告进入 StepGuard 决定
  /// forceAnswer/repair/stop）。
  ///
  /// 学生 run 的结论只在这里被过程报告改写：有 blocker 且 repair 预算还在 ->
  /// 允许**一次** repair；预算用尽 -> forceAnswer（保留答案，以未验证收尾）。
  /// 不会因为过程 blocker 无限重写——repair 次数由 composition 的 `maxRepair`
  /// 封顶，且 repair 后复验次数也被 `maxTotalVerifierCalls` 封顶。
  static StepGuardDecision _processGate(
    StudentProcessAuditResult? audit, {
    required int repairsUsed,
    required int maxRepair,
  }) {
    final blocker = audit?.blocker;
    if (blocker == null) {
      return const StepGuardDecision.proceed();
    }
    if (repairsUsed < maxRepair) {
      return StepGuardDecision.repair(
        blocker.stopReason,
        message: '过程审计检测到 ${blocker.id}，允许一次 repair',
      );
    }
    return StepGuardDecision.forceAnswer(
      blocker.stopReason,
      message: '过程审计检测到 ${blocker.id}，repair 预算已用尽：保留答案并按未验证收尾',
    );
  }

  /// 写 claim 行；落库失败不改变已经得出的结论（与 run/step 写失败同一契约）。
  Future<void> _saveClaims(String runId, List<Claim> claims) async {
    final store = recorder;
    if (store == null || claims.isEmpty) {
      return;
    }
    try {
      await store.saveClaims(runId: runId, claims: claims);
    } catch (_) {
      // 过程证据落库失败不推翻本轮结论。
    }
  }

  /// 一次可用答案的判定：有结果文本，且不是被 `finish=length` 截断的输出
  /// （设计文档 §11.3「不出现 finish=length 无答案」）。
  static bool _isUsableAnswer(
    StudentAnswerSheet sheet,
    String text,
    String? finishReason,
  ) {
    if (text.trim().isEmpty) {
      return false;
    }
    if (finishReason == 'length') {
      return false;
    }
    return sheet.result.trim().isNotEmpty;
  }

  /// repair 的用户指令：只复述检查结论，不重述 solver 的 CoT。
  static String _repairInstruction(Verification verification) {
    final issues = verification.issues.isEmpty
        ? '检查没有给出具体问题，请对照题目要求逐项核对答案卡。'
        : '检查指出的问题：\n${verification.issues.map((issue) => '- $issue').join('\n')}';
    final independent = verification.evidence['independent_answer'];
    final independentText = independent is String ? independent.trim() : '';
    final hint = independentText.isEmpty
        ? ''
        : '\n独立检查得到的答案（仅用于对照，不要照抄错误内容）：\n$independentText\n';
    return '$issues$hint\n请修正答案卡后重新输出完整答题卡。';
  }

  /// 落库用的答案卡 JSON：只有结构化字段，**没有** `raw`（raw 是模型答案原文，
  /// 只进本地 trace；见设计文档 §5.1）。
  static Map<String, Object?> _storedAnswerSheet(StudentAnswerSheet sheet) => {
        'kind': sheet.kind.id,
        'choice': sheet.choice,
        'result': sheet.result,
        'process': sheet.process,
        'structured': sheet.structured,
      };

  static String _joinReasoning(String current, String addition) {
    if (addition.trim().isEmpty) {
      return current;
    }
    if (current.trim().isEmpty) {
      return addition;
    }
    return '$current\n\n$addition';
  }

  static String _tail(String text, int max) {
    final value = text.trim();
    if (value.length <= max) {
      return value;
    }
    return value.substring(value.length - max);
  }

  /// 跑一个模型回合，收集 text / reasoning / usage / finishReason。
  Future<_ModelCapture> _runModel(
    ModelAdapter adapter,
    List<ChatMessage> messages,
  ) async {
    final text = StringBuffer();
    final reasoning = StringBuffer();
    int? promptTokens;
    int? completionTokens;
    String? finishReason;
    String? error;
    await for (final event in adapter.runTurn(
      messages: messages,
      tools: const <ModelToolSpec>[],
    )) {
      if (event is ModelTextDelta) {
        text.write(event.text);
      } else if (event is ModelReasoningDelta) {
        reasoning.write(event.text);
      } else if (event is ModelTurnDone) {
        finishReason = event.finishReason;
        promptTokens = _sum(promptTokens, event.promptTokens);
        completionTokens = _sum(completionTokens, event.completionTokens);
      } else if (event is ModelFailure) {
        error = event.message;
      } else if (event is ModelTurnCancelled) {
        error = event.reason ?? 'cancelled';
      }
    }
    return _ModelCapture(
      text: text.toString(),
      reasoning: reasoning.toString(),
      promptTokens: promptTokens ?? 0,
      completionTokens: completionTokens ?? 0,
      finishReason: finishReason,
      error: error,
    );
  }

  static int _sum(int? a, int? b) {
    if (a == null && b == null) {
      return 0;
    }
    return (a ?? 0) + (b ?? 0);
  }
}

/// 一个模型回合的捕获结果。
class _ModelCapture {
  const _ModelCapture({
    required this.text,
    required this.reasoning,
    required this.promptTokens,
    required this.completionTokens,
    this.finishReason,
    this.error,
  });

  final String text;
  final String reasoning;
  final int promptTokens;
  final int completionTokens;
  final String? finishReason;
  final String? error;

  bool get failed => error != null;
}

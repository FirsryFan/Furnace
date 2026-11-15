/// `agent_runs` / `agent_steps` / `agent_verifications` 的数据库读写。
///
/// 这是《STUDENT-MODE-AND-AGENT-LOOP-DESIGN-2026-11-14》§6.1 的
/// `agent_run_store.dart`，也是 §5.6「不把 raw CoT 写入 DB」这条约束的落点：
///
///  * [saveRun] 只接 [AgentRunState]，而它只有 `reasoningChars`（长度）——
///    这个 store 的任何方法都没有一个参数能接收 reasoning 全文；
///  * 要读原文请顺着 `run.tracePath` 去 `<appSupport>/student_solver_traces/`，
///    那是 `StudentTraceStore` 的职责。
///
/// 写路径全部是 upsert / append：一次运行会被反复 [saveRun]（每步更新 phase /
/// status / token），步骤和验证只追加。读路径只有 run / step / verification
/// 三种；claim 由 [saveClaims] 在 run 结束时批量写入（设计文档 §5.4），experience
/// 的写入属于 ExperienceStore（P1）。
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/database/database.dart';
import '../../../data/ids.dart';
import '../domain/agent_run.dart';
import '../domain/claim.dart';
import '../domain/process_auditor.dart';
import '../domain/verifier.dart';

/// 从 `agent_verifications` 读回来的一条验证记录。
class StoredVerification {
  const StoredVerification({
    required this.id,
    required this.runId,
    required this.verifierId,
    required this.kind,
    required this.independent,
    required this.verification,
    required this.createdAt,
    this.processReportJson,
  });

  final String id;
  final String runId;

  /// 验证者标识（`student_independent_v1` / `process_auditor` …）。
  final String verifierId;

  final VerifierKind kind;
  final bool independent;
  final Verification verification;
  final int createdAt;

  /// 过程审计报告原文（`kind = process` 时才有）。
  final String? processReportJson;

  @override
  String toString() => 'StoredVerification($id, $verifierId/${kind.id}, '
      '${verification.verdict.id})';
}

/// 一次运行过程的持久化门面。
class AgentRunStore {
  AgentRunStore(this._db);

  final AppDatabase _db;

  /// 过程审计在 `agent_verifications.verifier` 里的稳定 id。
  static const String processAuditorId = 'process_auditor';

  // --- runs -----------------------------------------------------------------

  /// 写入/更新一次运行。
  ///
  /// 同一 id 反复调用是**覆盖**（运行状态本来就该更新：phase 会推进、token
  /// 会累加、终态只用写一次）。不存在的行则插入。
  Future<void> saveRun(AgentRunState run) async {
    await _db.into(_db.agentRuns).insertOnConflictUpdate(
          AgentRunsCompanion.insert(
            id: run.id,
            conversationId: run.conversationId,
            presetId: run.presetId,
            mode: run.mode.id,
            phase: run.phase.id,
            status: run.status.id,
            stopReason: Value(run.stopReason?.id),
            steps: Value(run.steps),
            promptTokens: Value(run.promptTokens),
            completionTokens: Value(run.completionTokens),
            reasoningTokens: Value(run.reasoningTokens),
            reasoningChars: Value(run.reasoningChars),
            elapsedMs: Value(run.elapsedMs),
            answerSheetJson: Value(run.answerSheetJson),
            tracePath: Value(run.tracePath),
            verifierVerdict: Value(run.verifierVerdict),
            processReportJson: Value(run.processReportJson),
            startedAt: run.startedAt,
            endedAt: Value(run.endedAt),
          ),
        );
  }

  /// 按 id 读一次运行；没有就返回 NULL（不要编一个空运行）。
  Future<AgentRunState?> loadRun(String id) async {
    final row = await (_db.select(_db.agentRuns)
          ..where((table) => table.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _runOf(row);
  }

  /// 最近几次运行；可按会话过滤。按 `started_at` 倒序（最新在前）。
  Future<List<AgentRunState>> recentRuns({
    String? conversationId,
    int limit = 20,
  }) async {
    final query = _db.select(_db.agentRuns)
      ..orderBy([(table) => OrderingTerm.desc(table.startedAt)])
      ..limit(limit);
    if (conversationId != null) {
      query.where((table) => table.conversationId.equals(conversationId));
    }
    final rows = await query.get();
    return [for (final row in rows) _runOf(row)];
  }

  /// 一次运行的所有步骤（按 seq 升序）。
  Future<List<AgentStep>> loadSteps(String runId) async {
    final rows = await (_db.select(_db.agentSteps)
          ..where((table) => table.runId.equals(runId))
          ..orderBy([(table) => OrderingTerm.asc(table.seq)]))
        .get();
    return [for (final row in rows) _stepOf(row)];
  }

  /// 追加一步。`id` / `createdAt` 由本方法生成（[nowMs] 可注入便于测试）。
  ///
  /// 同一 `(runId, seq)` 写两次会撞 `UNIQUE(run_id, seq)`：重放同一 run 时这
  /// 正是想要的——失败得响，而不是悄悄长出重复步骤。
  Future<AgentStep> appendStep({
    required String runId,
    required int seq,
    required AgentPhase phase,
    required AgentStepKind kind,
    AgentStepStatus status = AgentStepStatus.ok,
    String? toolName,
    String? argsHash,
    String? stateFingerprint,
    String? claimHash,
    int? tokens,
    String? summary,
    int? nowMs,
  }) async {
    final step = AgentStep(
      id: Ids.next('step'),
      runId: runId,
      seq: seq,
      phase: phase,
      kind: kind,
      status: status,
      createdAt: nowMs ?? DateTime.now().millisecondsSinceEpoch,
      toolName: toolName,
      argsHash: argsHash,
      stateFingerprint: stateFingerprint,
      claimHash: claimHash,
      tokens: tokens,
      summary: summary,
    );
    await saveStep(step);
    return step;
  }

  /// 原样写入一条已经构造好的步骤（重放 / 测试用）。
  Future<void> saveStep(AgentStep step) async {
    await _db.into(_db.agentSteps).insert(
          AgentStepsCompanion.insert(
            id: step.id,
            runId: step.runId,
            seq: step.seq,
            phase: step.phase.id,
            kind: step.kind.id,
            toolName: Value(step.toolName),
            argsHash: Value(step.argsHash),
            stateFingerprint: Value(step.stateFingerprint),
            claimHash: Value(step.claimHash),
            status: step.status.id,
            tokens: Value(step.tokens),
            summary: Value(step.summary),
            createdAt: step.createdAt,
          ),
        );
  }

  // --- verifications --------------------------------------------------------

  /// 写一条验证记录；返回它的 id。
  ///
  /// [evidenceJson] 由 [Verification.toJson] 生成；[processReportJson] 只有
  /// `kind = process` 的过程审计才有。验证器 id / 类别由调用方给（本方法不
  /// import 具体验证器实现，保持依赖方向：infrastructure 认识 domain 接口）。
  Future<String> saveVerification({
    required String runId,
    required String verifierId,
    required Verification verification,
    VerifierKind kind = VerifierKind.content,
    String? processReportJson,
    int? nowMs,
  }) async {
    final id = Ids.next('verify');
    await _db.into(_db.agentVerifications).insert(
          AgentVerificationsCompanion.insert(
            id: id,
            runId: runId,
            verifier: verifierId,
            kind: Value(kind.id),
            verdict: verification.verdict.id,
            failureType: Value(verification.failureType?.id),
            independent: Value(verification.independent),
            evidenceJson: Value(jsonEncode(verification.toJson())),
            processReportJson: Value(processReportJson),
            promptTokens: Value(verification.promptTokens),
            completionTokens: Value(verification.completionTokens),
            createdAt: nowMs ?? DateTime.now().millisecondsSinceEpoch,
          ),
        );
    return id;
  }

  /// 把一次过程审计写成 `kind = process` 的验证记录；返回 id。
  ///
  /// 过程审计**不判答案对错**，所以这里的 verdict 只描述过程：循环/停滞 -> fail，
  /// 只有自我怀疑标记 -> unknown（看见可疑但没法定性），干净 -> pass。
  /// `independent = false`：它读的就是 solver 的 CoT，不独立于 solver。
  Future<String> saveProcessAudit({
    required String runId,
    required ProcessReport report,
    int? nowMs,
  }) async {
    final verification = _processVerification(report);
    return saveVerification(
      runId: runId,
      verifierId: processAuditorId,
      verification: verification,
      kind: VerifierKind.process,
      processReportJson: jsonEncode(report.toJson()),
      nowMs: nowMs,
    );
  }

  /// 一次运行的验证记录（按写入时间升序）。
  Future<List<StoredVerification>> loadVerifications(String runId) async {
    final rows = await (_db.select(_db.agentVerifications)
          ..where((table) => table.runId.equals(runId))
          ..orderBy([(table) => OrderingTerm.asc(table.createdAt)]))
        .get();
    return [for (final row in rows) _verificationOf(row)];
  }

  // --- claims ---------------------------------------------------------------

  /// 把一次运行抽到的 claim 写成 `agent_claims` 行（设计文档 §5.4）；返回写入行数。
  ///
  /// 行 id 用 `$runId-${claim.id}`：`claim.id` 是内容 hash（`claim-<hash>`），
  /// 同一道题跑两次会抽出同一批 claim，而表主键只有 `id`——不同 run 的同一条
  /// claim 必须是不同的行，否则第二次 run 会覆盖第一次的 `run_id`，证据链就断了。
  /// 同一 run 重复调用是幂等覆盖（同一行 upsert），不会长出重复行。
  ///
  /// `deps_json` 取 [Claim.deps] 的 `[{id, version}]`；过程审计抽取的 claim
  /// `createdAtMs` 是 0（抽取时没有真实时钟），落库时用 [nowMs] 或当前时间补上。
  Future<int> saveClaims({
    required String runId,
    required List<Claim> claims,
    int? nowMs,
  }) async {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    for (final claim in claims) {
      final canonical = claim.canonical.trim().isEmpty
          ? claim.statement.trim()
          : claim.canonical.trim();
      await _db.into(_db.agentClaims).insertOnConflictUpdate(
            AgentClaimsCompanion.insert(
              id: '$runId-${claim.id}',
              runId: runId,
              kind: claim.kind.id,
              canonical: canonical,
              statement: claim.statement,
              depsJson: Value(
                claim.deps.isEmpty
                    ? null
                    : jsonEncode([for (final dep in claim.deps) dep.toJson()]),
              ),
              status: claim.status.id,
              checkMethod: Value(claim.checkMethod?.id),
              checkedVersion: Value(claim.checkedVersion),
              evidence: Value(claim.evidence),
              createdAt: claim.createdAtMs > 0 ? claim.createdAtMs : now,
            ),
          );
    }
    return claims.length;
  }

  // --- mapping --------------------------------------------------------------

  Verification _processVerification(ProcessReport report) {
    if (report.loopDetected) {
      return Verification.fail(
        failureType: FailureType.loop,
        issues: ['过程检测到循环：${report.flags.join(', ')}'],
        evidence: report.toJson(),
        independent: false,
      );
    }
    if (report.stagnation) {
      return Verification.fail(
        failureType: FailureType.stagnation,
        issues: ['过程检测到无进展：${report.flags.join(', ')}'],
        evidence: report.toJson(),
        independent: false,
      );
    }
    if (report.flags.contains('self_doubt')) {
      return Verification.unknown(
        failureType: FailureType.selfDoubt,
        issues: ['过程检测到反复自我怀疑 ${report.selfDoubtCount} 次'],
        evidence: report.toJson(),
        independent: false,
      );
    }
    return Verification.pass(
      evidence: report.toJson(),
      independent: false,
    );
  }

  AgentRunState _runOf(AgentRunRow row) {
    return AgentRunState(
      id: row.id,
      conversationId: row.conversationId,
      presetId: row.presetId,
      mode: AgentMode.fromId(row.mode),
      startedAt: row.startedAt,
      phase: AgentPhase.fromId(row.phase),
      status: AgentRunStatus.fromId(row.status),
      stopReason: StopReason.fromId(row.stopReason),
      steps: row.steps,
      promptTokens: row.promptTokens,
      completionTokens: row.completionTokens,
      reasoningTokens: row.reasoningTokens,
      reasoningChars: row.reasoningChars,
      elapsedMs: row.elapsedMs,
      answerSheetJson: row.answerSheetJson,
      tracePath: row.tracePath,
      verifierVerdict: row.verifierVerdict,
      processReportJson: row.processReportJson,
      endedAt: row.endedAt,
    );
  }

  AgentStep _stepOf(AgentStepRow row) {
    return AgentStep(
      id: row.id,
      runId: row.runId,
      seq: row.seq,
      phase: AgentPhase.fromId(row.phase),
      kind: AgentStepKind.fromId(row.kind),
      status: AgentStepStatus.fromId(row.status),
      createdAt: row.createdAt,
      toolName: row.toolName,
      argsHash: row.argsHash,
      stateFingerprint: row.stateFingerprint,
      claimHash: row.claimHash,
      tokens: row.tokens,
      summary: row.summary,
    );
  }

  StoredVerification _verificationOf(AgentVerificationRow row) {
    final evidenceJson = row.evidenceJson;
    final verification = evidenceJson == null || evidenceJson.isEmpty
        ? Verification(
            verdict: Verdict.fromId(row.verdict),
            failureType: FailureType.fromId(row.failureType),
            independent: row.independent,
            promptTokens: row.promptTokens,
            completionTokens: row.completionTokens,
          )
        : _verificationFromJson(
            evidenceJson,
            fallbackVerdict: row.verdict,
          );
    return StoredVerification(
      id: row.id,
      runId: row.runId,
      verifierId: row.verifier,
      kind: VerifierKind.fromId(row.kind),
      independent: row.independent,
      verification: verification,
      createdAt: row.createdAt,
      processReportJson: row.processReportJson,
    );
  }

  /// `evidence_json` 是[Verification.toJson] 的原文；坏 JSON 时退化成
  /// 「只有 verdict/failure_type 的结论」，绝不把坏数据读成 pass。
  Verification _verificationFromJson(
    String json, {
    required String fallbackVerdict,
  }) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, Object?>) {
        return Verification.fromJson(decoded);
      }
      return Verification(
        verdict: Verdict.fromId(fallbackVerdict),
        independent: false,
      );
    } on FormatException {
      return Verification(
        verdict: Verdict.fromId(fallbackVerdict),
        independent: false,
      );
    }
  }
}

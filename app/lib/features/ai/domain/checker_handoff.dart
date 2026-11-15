/// 确定性 Precheck → Checker teammate 的交接契约（设计 §7.5 / §7.6）。
///
/// 角色关系（设计 §7.5）：
///
///  * **Precheck**（确定性）先跑：发现确定问题 -> [PrecheckOutcome.invalid]，
///    回 solver 改；无法判断 -> [PrecheckOutcome.unknown]，回 solver 弄清楚；
///    只有 [PrecheckOutcome.clean] 才能进入 Checker；
///  * **Checker** 是 agent team 里的独立 teammate，不是 solver 同一模型的自审。
///    它拿到的是处理过的步骤与 claim（[ProcessedStep] / [Claim]）、冻结答案和
///    [CheckerHandoff.allowedCheckerTools]，而不是 solver 的原始 CoT；
///  * invalid/unknown 必须回 solver，**结构上不能构造 [CheckerHandoff]**：
///    本文件唯一公开的构造入口是 [CheckerHandoff.fromPrecheck]，非 clean 直接
///    抛 [StateError]；`CheckerHandoff` 的构造函数是私有的。
///
/// **交付构造必须由确定性程序完成**（2026-11-14 用户确认）：
///
///  * handoff 的字段只能从 run / trace / claim 的解析结果机械生成，不得由任何
///    agent / LLM 生成或摘要；本文件刻意不提供任何「总结/描述」入口；
///  * 每个 handoff 记录 [CheckerHandoff.sourceRunId] /
///    [CheckerHandoff.sourceTraceRef] / [CheckerHandoff.sourceTraceHash] /
///    [CheckerHandoff.schemaVersion]，并带内容 hash
///    [CheckerHandoff.contentHash]；下游可核对交接数据是否来自同一次 run 的
///    trace，以及是否被摘要/改写；
///  * 解析失败（trace/claim 读不出来）**不生成 handoff**，走
///    [PrecheckResult.parseFailure]（= unknown）回 solver 补信息。
///
/// 本文件只定义数据与不变量：不实现 Precheck 规则、不调用模型、不跑 Checker。
library;

import 'dart:convert';

import 'claim.dart';

/// [CheckerHandoff] 的 schema 版本；字段或语义变化时 +1。
const int checkerHandoffSchemaVersion = 1;

/// Precheck 的三态（设计 §7.5 的「确定性预检」）。
enum PrecheckOutcome {
  /// 发现确定问题：回 solver 改（设计 §7.5「invalid 回 solver 改」）。
  invalid('invalid'),

  /// 当前信息无法判断：回 solver 补信息/澄清；**不是 pass**。
  unknown('unknown'),

  /// 没有确定问题：唯一允许交给 Checker 的状态。
  clean('clean');

  const PrecheckOutcome(this.id);

  /// 落库/日志用的稳定值。
  final String id;

  /// 只有 clean 允许进入 Checker（设计 §7.5）。
  bool get allowsCheckerHandoff => this == PrecheckOutcome.clean;

  /// invalid/unknown 都回 solver；区别在语义（改 vs 弄清），不在这里。
  bool get returnsToSolver => !allowsCheckerHandoff;

  /// 宽松解析：未知值退化成 [unknown]，绝不冒充 clean。
  static PrecheckOutcome fromId(String? id) => switch (id) {
        'invalid' => PrecheckOutcome.invalid,
        'clean' => PrecheckOutcome.clean,
        _ => PrecheckOutcome.unknown,
      };
}

/// 确定性 Precheck 的一条发现。
///
/// [code] 是稳定机器标识（如 `answer_missing` / `unit_mismatch`），[detail] 是
/// 人可读说明，[stepId] 指向 solver 的具体步骤（没有就为 null）。预检发现不是
/// 自然语言「再检查一下」：它能被下一层计数、归类、作为教学延伸的素材。
class PrecheckFinding {
  const PrecheckFinding({
    required this.code,
    required this.detail,
    this.stepId,
    this.evidenceRef,
  });

  /// 稳定机器标识，例如 `missing_branch`、`unit_mismatch`。
  final String code;

  /// 人可读的具体说明。
  final String detail;

  /// 关联的 solver 步骤 id；没有具体步骤时为 null。
  final String? stepId;

  /// 证据引用（trace step / claim / 锚点 id），便于 Checker 和排障定位。
  final String? evidenceRef;

  Map<String, Object?> toJson() => {
        'code': code,
        'detail': detail,
        if (stepId != null) 'step_id': stepId,
        if (evidenceRef != null) 'evidence_ref': evidenceRef,
      };
}

/// 回 solver 的澄清/修改请求（Precheck invalid/unknown 的载体）。
///
/// 设计 §7.5：invalid 回 solver 改；unknown 回 solver 弄清。两种路由的区别在
/// [PrecheckResult.outcome]，这里只记录「为什么回」「要 solver 回答什么」。
class SolverClarificationRequest {
  const SolverClarificationRequest({
    required this.reason,
    required this.questions,
    this.affectedSteps = const <String>[],
  });

  /// 具体原因（人可读、可进 solver prompt）。
  final String reason;

  /// solver 必须回答/修正的具体问题；空列表的请求是无效请求。
  final List<String> questions;

  /// 受影响的步骤 id，便于局部重推。
  final List<String> affectedSteps;

  Map<String, Object?> toJson() => {
        'reason': reason,
        'questions': questions,
        'affected_steps': affectedSteps,
      };
}

/// 确定性预检的结论。
///
/// 不变量由工厂保证：
///
///  * [PrecheckResult.clean]：没有 clarification，唯一允许 handoff 的状态；
///    它携带的 [findings] 只能是非阻塞观察（交给 Checker 复核），任何会改答案
///    的确定问题都必须走 [PrecheckResult.invalid] / [PrecheckResult.unknown]；
///  * invalid / unknown：必须带 [SolverClarificationRequest]（具体原因 + 至少
///    一个问题），否则 solver 无法局部重推。
class PrecheckResult {
  const PrecheckResult._({
    required this.outcome,
    required this.findings,
    required this.clarification,
    required this.checkedSteps,
  });

  /// clean：没有阻塞问题。
  factory PrecheckResult.clean({
    List<PrecheckFinding> findings = const <PrecheckFinding>[],
    int checkedSteps = 0,
  }) {
    return PrecheckResult._(
      outcome: PrecheckOutcome.clean,
      findings: List<PrecheckFinding>.unmodifiable(findings),
      clarification: null,
      checkedSteps: checkedSteps,
    );
  }

  /// invalid：发现确定问题，回 solver 改。
  factory PrecheckResult.invalid({
    required String reason,
    required List<String> questions,
    List<PrecheckFinding> findings = const <PrecheckFinding>[],
    List<String> affectedSteps = const <String>[],
    int checkedSteps = 0,
  }) {
    PrecheckResult._requireClarification(reason: reason, questions: questions);
    return PrecheckResult._(
      outcome: PrecheckOutcome.invalid,
      findings: List<PrecheckFinding>.unmodifiable(findings),
      clarification: SolverClarificationRequest(
        reason: reason,
        questions: List<String>.unmodifiable(questions),
        affectedSteps: List<String>.unmodifiable(affectedSteps),
      ),
      checkedSteps: checkedSteps,
    );
  }

  /// unknown：当前信息无法判断，回 solver 补信息（不是 pass）。
  factory PrecheckResult.unknown({
    required String reason,
    required List<String> questions,
    List<PrecheckFinding> findings = const <PrecheckFinding>[],
    List<String> affectedSteps = const <String>[],
    int checkedSteps = 0,
  }) {
    PrecheckResult._requireClarification(reason: reason, questions: questions);
    return PrecheckResult._(
      outcome: PrecheckOutcome.unknown,
      findings: List<PrecheckFinding>.unmodifiable(findings),
      clarification: SolverClarificationRequest(
        reason: reason,
        questions: List<String>.unmodifiable(questions),
        affectedSteps: List<String>.unmodifiable(affectedSteps),
      ),
      checkedSteps: checkedSteps,
    );
  }

  /// 解析失败：run/trace/claim 读不出来或都不成结构时使用。
  ///
  /// 2026-11-14 用户约束：解析失败**不得生成 handoff**，只能走澄清回 solver。
  /// 因此这里固定返回 [PrecheckOutcome.unknown]，`code` 固定为
  /// `trace_parse_failed`，便于统计这类失败。
  factory PrecheckResult.parseFailure({
    required String detail,
    String question = '请重新输出可解析的结构化推理（步骤 + 依据 + claim），便于确定性预检。',
  }) {
    return PrecheckResult.unknown(
      reason: '确定性程序无法解析本次 run/trace/claim：$detail',
      questions: <String>[question],
      findings: <PrecheckFinding>[
        PrecheckFinding(code: 'trace_parse_failed', detail: detail),
      ],
    );
  }

  final PrecheckOutcome outcome;
  final List<PrecheckFinding> findings;

  /// 回 solver 的请求；只有 clean 为 null。
  final SolverClarificationRequest? clarification;

  /// 实际检查过的步骤/锚点数（排障用，不参与判定）。
  final int checkedSteps;

  /// 是否允许进入 Checker：必须 clean 且没有回 solver 的请求。
  bool get allowsCheckerHandoff =>
      outcome.allowsCheckerHandoff && clarification == null;

  static void _requireClarification({
    required String reason,
    required List<String> questions,
  }) {
    if (reason.trim().isEmpty) {
      throw ArgumentError.value(reason, 'reason', 'invalid/unknown 必须给出具体原因');
    }
    if (questions.isEmpty) {
      throw ArgumentError.value(
        questions,
        'questions',
        'invalid/unknown 必须给出至少一个要 solver 回答的问题',
      );
    }
  }
}

/// solver 处理过的一步：交给 Checker 的**结构化过程**，不是原始 CoT。
///
/// [claim] 是这一步成立的断言，[evidence] 是依据（引用的条件/前一步/计算），
/// [sourceStepId] 指回 solver 的步骤 id，[deterministicFlags] 是确定性规则/
/// StepVerifier 给出的信号（§7.7：`invalid` 是硬问题，`valid` 不是认证，所以
/// flags 只作为 Checker 的输入，不作为通过依据）。
class ProcessedStep {
  const ProcessedStep({
    required this.id,
    required this.claim,
    required this.evidence,
    this.sourceStepId,
    this.deterministicFlags = const <String>[],
    this.normalizedClaim,
    this.evidenceRefs = const <String>[],
    this.sourceHash,
  });

  /// 本步在处理后过程中的稳定 id。
  final String id;

  /// 这一步主张什么（一句可核对的断言，保留 solver 原文措辞）。
  final String claim;

  /// 依据：题目条件、定义域、前一步结果或具体计算。
  final String evidence;

  /// 对应的 solver 原始步骤 id（可追溯）；没有对应步骤时为 null。
  final String? sourceStepId;

  /// 确定性检查/StepVerifier 的信号，例如 `unit_ok`、`branch_overlap`。
  final List<String> deterministicFlags;

  /// 归一化后的断言文本；只用于匹配，不替换 [claim] 的原文（确定性预处理
  /// 管线写入；手工构造的 step 可以为 null）。
  final String? normalizedClaim;

  /// 证据引用列表（trace step / claim hash / 锚点 id），供 Checker 定位。
  final List<String> evidenceRefs;

  /// 来源 trace 步骤的 source hash；与 solver 原文一一对应。
  final String? sourceHash;

  Map<String, Object?> toJson() => {
        'id': id,
        'claim': claim,
        'evidence': evidence,
        if (sourceStepId != null) 'source_step_id': sourceStepId,
        'deterministic_flags': deterministicFlags,
        if (normalizedClaim != null) 'normalized_claim': normalizedClaim,
        'evidence_refs': evidenceRefs,
        if (sourceHash != null) 'source_hash': sourceHash,
      };
}

/// 交给独立 Checker teammate 的交接数据（设计 §7.5）。
///
/// 只由 [CheckerHandoff.fromPrecheck] 从 clean precheck 构造；invalid/unknown
/// 会抛 [StateError]，因此「invalid/unknown 不能进入 Checker」不是调用约定，
/// 而是本文件的结构约束。
///
/// “独立 teammate，不是同模型自审”体现在交接内容上：这里没有 solver 的原始
/// CoT、没有 solver 的 system prompt、没有「再检查一下」的模糊指令；Checker 拿
/// 到的是冻结答案、处理过的步骤/claim、预检发现、工具证据，以及它自己被允许
/// 使用的工具（[allowedCheckerTools]）。下一层接线必须把这些交给另一个
/// teammate，而不是把 [CheckerHandoff] 塞回 solver 的 prompt。
///
/// “确定性构造，不是 LLM 摘要”（2026-11-14 用户约束）体现在：
///
///  * 构造函数私有，唯一入口 [CheckerHandoff.fromPrecheck] 是纯函数；所有字段
///    都必须由调用方的确定性解析器从 run/trace/claim 机械得到；
///  * [sourceRunId] / [sourceTraceRef] / [sourceTraceHash] / [schemaVersion]
///    记录来源与版本，[contentHash] 是对整份交接内容的确定性 hash；下游可以用
///    [verifyContentHash] 核对它没有被摘要或改写。
class CheckerHandoff {
  const CheckerHandoff._({
    required this.schemaVersion,
    required this.sourceRunId,
    required this.sourceTraceRef,
    required this.sourceTraceHash,
    required this.contentHash,
    required this.question,
    required this.frozenAnswer,
    required this.processedSteps,
    required this.claims,
    required this.precheckFindings,
    required this.toolEvidence,
    required this.toolEvidenceRefs,
    required this.allowedCheckerTools,
    required this.tokenBudget,
    required this.truncated,
  });

  /// 从 clean 预检构造 handoff（纯函数，只能由确定性程序调用）。
  ///
  /// 强制输入：
  ///  * [precheck] 必须是 clean，否则抛 [StateError]；
  ///  * [sourceRunId] / [sourceTraceRef] / [sourceTraceHash] 必须非空——没有
  ///    来源就没有可追溯性，宁可不 handoff；
  ///  * [frozenAnswer] 必须非空（clean 却没有答案不是可交给 Checker 的输入）。
  ///
  /// 禁止：把模型生成的摘要/复述当作 [processedSteps] 或 [claims]；它们必须
  /// 来自 run/trace/claim 的机械解析。解析失败走 [PrecheckResult.parseFailure]。
  factory CheckerHandoff.fromPrecheck({
    required PrecheckResult precheck,
    required String sourceRunId,
    required String sourceTraceRef,
    required String sourceTraceHash,
    required String question,
    required String frozenAnswer,
    required List<ProcessedStep> processedSteps,
    List<Claim> claims = const <Claim>[],
    Map<String, Object?> toolEvidence = const <String, Object?>{},
    List<String> toolEvidenceRefs = const <String>[],
    List<String> allowedCheckerTools = const <String>[],
    int? tokenBudget,
    bool truncated = false,
  }) {
    if (!precheck.allowsCheckerHandoff) {
      throw StateError(
        'precheck outcome ${precheck.outcome.id} 必须回 solver，'
        '不能构造 CheckerHandoff（只有 clean 才允许 handoff）',
      );
    }
    if (frozenAnswer.trim().isEmpty) {
      throw StateError('clean precheck 的 frozenAnswer 为空：没有可交给 Checker 的答案');
    }
    if (sourceRunId.trim().isEmpty ||
        sourceTraceRef.trim().isEmpty ||
        sourceTraceHash.trim().isEmpty) {
      throw StateError(
          'CheckerHandoff 必须带非空的 sourceRunId/sourceTraceRef/sourceTraceHash');
    }
    final handoff = CheckerHandoff._(
      schemaVersion: checkerHandoffSchemaVersion,
      sourceRunId: sourceRunId,
      sourceTraceRef: sourceTraceRef,
      sourceTraceHash: sourceTraceHash,
      contentHash: '',
      question: question,
      frozenAnswer: frozenAnswer,
      processedSteps: List<ProcessedStep>.unmodifiable(processedSteps),
      claims: List<Claim>.unmodifiable(claims),
      precheckFindings: List<PrecheckFinding>.unmodifiable(precheck.findings),
      toolEvidence: Map<String, Object?>.unmodifiable(toolEvidence),
      toolEvidenceRefs: List<String>.unmodifiable(toolEvidenceRefs),
      allowedCheckerTools: List<String>.unmodifiable(allowedCheckerTools),
      tokenBudget: tokenBudget,
      truncated: truncated,
    );
    // contentHash 覆盖除自身外的全部字段；先占位再一次性算出，构造后不可变。
    return handoff._withContentHash(handoff._computeContentHash());
  }

  /// handoff schema 版本（写入交接数据，供下游判断字段语义）。
  final int schemaVersion;

  /// 来源 run 的稳定 id。
  final String sourceRunId;

  /// 来源 trace 的引用（文件路径 / trace id / step 区间等稳定引用）。
  final String sourceTraceRef;

  /// 确定性程序对 trace/claim 快照计算的 hash（可用 `stableClaimHash`）。
  final String sourceTraceHash;

  /// 整份交接内容的确定性 hash（覆盖 [toJson] 除 `content_hash` 外的全部字段）。
  final String contentHash;

  /// 题目原文/题干结构化文本。
  final String question;

  /// 已冻结的最终答案。过程 repair 不允许改它（设计 §7.5）；真的必须改答案
  /// 就回到 AnswerGate，而不是改 handoff。
  final String frozenAnswer;

  /// 交给 Checker 的结构化过程（不是 raw CoT）。
  final List<ProcessedStep> processedSteps;

  /// 结构化 claim；Checker 用它们核对条件是否真的被用到。
  final List<Claim> claims;

  /// 确定性预检的发现（clean 时只能是非阻塞观察，供 Checker 复核）。
  final List<PrecheckFinding> precheckFindings;

  /// 确定性工具/验证器产出的证据（JSON-safe）。
  final Map<String, Object?> toolEvidence;

  /// 工具证据的稳定引用列表（trace step / claim / 工具结果 id），默认只放引用、
  /// 不放整段证据，避免把大块内容塞进 Checker 上下文。
  final List<String> toolEvidenceRefs;

  /// Checker teammate 允许使用的审核工具 id 列表（由调用方按 preset 给定）。
  final List<String> allowedCheckerTools;

  /// processedSteps 的确定性 token 预算（按字符数保守估算，不精确分词）；
  /// null 表示没有设置预算。
  final int? tokenBudget;

  /// processedSteps 是否因超出 [tokenBudget] 被确定性截断（只丢整段步骤/裁剪
  /// 文本，不做任何 LLM 摘要）。
  final bool truncated;

  /// 来源 trace 快照的 hash（[sourceTraceHash] 的别名，lead 设计用名）。
  String get sourceHash => sourceTraceHash;

  /// 冻结答案的内容身份，用来检测「过程 repair 偷偷改了答案」。
  String get frozenAnswerDigest => stableClaimHash(frozenAnswer);

  /// 重算并核对 [contentHash]：false 表示交接内容被改写过（或 schema 不一致）。
  bool verifyContentHash() => contentHash == _computeContentHash();

  /// 过程修复后重建同一份 handoff：题目、冻结答案、预检发现、允许工具、来源
  /// run 不变；只替换处理后的步骤/claim，并更新来源 trace 引用与 hash。
  ///
  /// 这是唯一允许替换 handoff 内容的入口；因为它保留 [frozenAnswer]，过程
  /// repair 不能借重建 handoff 改最终答案。
  CheckerHandoff withProcess({
    required List<ProcessedStep> processedSteps,
    required String sourceTraceRef,
    required String sourceTraceHash,
    List<Claim>? claims,
    Map<String, Object?>? toolEvidence,
    List<String>? toolEvidenceRefs,
  }) {
    if (sourceTraceRef.trim().isEmpty || sourceTraceHash.trim().isEmpty) {
      throw StateError('withProcess 必须带非空的 sourceTraceRef/sourceTraceHash');
    }
    final handoff = CheckerHandoff._(
      schemaVersion: schemaVersion,
      sourceRunId: sourceRunId,
      sourceTraceRef: sourceTraceRef,
      sourceTraceHash: sourceTraceHash,
      contentHash: '',
      question: question,
      frozenAnswer: frozenAnswer,
      processedSteps: List<ProcessedStep>.unmodifiable(processedSteps),
      claims: List<Claim>.unmodifiable(claims ?? this.claims),
      precheckFindings: precheckFindings,
      toolEvidence:
          Map<String, Object?>.unmodifiable(toolEvidence ?? this.toolEvidence),
      toolEvidenceRefs:
          List<String>.unmodifiable(toolEvidenceRefs ?? this.toolEvidenceRefs),
      allowedCheckerTools: allowedCheckerTools,
      tokenBudget: tokenBudget,
      truncated: truncated,
    );
    return handoff._withContentHash(handoff._computeContentHash());
  }

  CheckerHandoff _withContentHash(String contentHash) => CheckerHandoff._(
        schemaVersion: schemaVersion,
        sourceRunId: sourceRunId,
        sourceTraceRef: sourceTraceRef,
        sourceTraceHash: sourceTraceHash,
        contentHash: contentHash,
        question: question,
        frozenAnswer: frozenAnswer,
        processedSteps: processedSteps,
        claims: claims,
        precheckFindings: precheckFindings,
        toolEvidence: toolEvidence,
        toolEvidenceRefs: toolEvidenceRefs,
        allowedCheckerTools: allowedCheckerTools,
        tokenBudget: tokenBudget,
        truncated: truncated,
      );

  String _computeContentHash() =>
      stableClaimHash(jsonEncode(_canonical(_payload())));

  Map<String, Object?> _payload() => {
        'schema_version': schemaVersion,
        'source_run_id': sourceRunId,
        'source_trace_ref': sourceTraceRef,
        'source_trace_hash': sourceTraceHash,
        'question': question,
        'frozen_answer': frozenAnswer,
        'frozen_answer_digest': frozenAnswerDigest,
        'processed_steps': [for (final step in processedSteps) step.toJson()],
        'claims': [for (final claim in claims) claim.toJson()],
        'precheck_findings': [
          for (final finding in precheckFindings) finding.toJson(),
        ],
        'tool_evidence': toolEvidence,
        'tool_evidence_refs': toolEvidenceRefs,
        'allowed_checker_tools': allowedCheckerTools,
        'token_budget': tokenBudget,
        'truncated': truncated,
      };

  /// 把 map 的 key 递归排序后再编码，避免插入顺序影响 [contentHash]。
  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonical(value[key]),
      };
    }
    if (value is List) {
      return <Object?>[for (final item in value) _canonical(item)];
    }
    return value;
  }

  Map<String, Object?> toJson() => {
        ..._payload(),
        'content_hash': contentHash,
      };
}

/// 验证流水线的纯状态契约：Precheck → Checker teammate → 交付（设计 §7.5）。
///
/// 本文件不跑模型、不跑 Checker、不写库；它只把「什么时候可以 handoff、什么
/// 时候必须回 solver、两次 checker 不过如何交付」写成可单测的纯函数。下一层
/// 接线（应用层）负责真正调用确定性 Precheck 规则与独立的 Checker teammate。
///
/// 状态图：
///
/// ```text
/// precheck.invalid   -> solverRevisionRequired      （回 solver 改，无 handoff）
/// precheck.unknown   -> solverClarificationRequired （回 solver 弄清，无 handoff）
/// precheck.parseFail -> solverClarificationRequired （解析失败，无 handoff）
/// precheck.clean     -> awaitingChecker             （构造 CheckerHandoff）
/// awaitingChecker + checker pass                    -> verified（不生成 extension）
/// awaitingChecker + checker fail（第 1 轮）          -> solverProcessRepairRequired
/// solverProcessRepairRequired + rehandoff           -> awaitingChecker（答案仍冻结）
/// checker fail（第 2 轮）                            -> unverified（交付 + 延伸 + 学习记录）
/// checker uncheckable / fail 无阻塞 issue            -> humanRequired（转人工）
/// ```
///
/// 所有转移都要求 `previous` 来自本流水线；`record` 在以下情况抛 [StateError]：
/// 前一步已终止、前一步没有 [CheckerHandoff]（= invalid/unknown 想进 Checker）。
library;

import 'checker_handoff.dart';
import 'checker_report.dart';
import 'claim.dart';
import 'unverified_delivery.dart';

/// 流水线状态。
enum VerificationPipelineStatus {
  /// precheck invalid：回 solver 改。
  solverRevisionRequired('solver_revision_required'),

  /// precheck unknown / 解析失败：回 solver 补信息（不是 pass）。
  solverClarificationRequired('solver_clarification_required'),

  /// clean handoff 已构造，等 Checker teammate 的审查结果。
  awaitingChecker('awaiting_checker'),

  /// checker 第 1 轮不过：solver 只做局部过程重推，答案冻结。
  solverProcessRepairRequired('solver_process_repair_required'),

  /// checker 通过：正常交付，不生成教学延伸。
  verified('verified'),

  /// checker 两轮不过：答案照常交付，但标 unverified + 延伸 + 学习记录。
  unverified('unverified'),

  /// 系统无法判断：转人工。
  humanRequired('human_required');

  const VerificationPipelineStatus(this.id);

  /// 落库/日志用的稳定值。
  final String id;

  /// 已终止（verified / unverified / humanRequired）。
  bool get isTerminal =>
      this == VerificationPipelineStatus.verified ||
      this == VerificationPipelineStatus.unverified ||
      this == VerificationPipelineStatus.humanRequired;

  /// 是否要回 solver 干活（改答案 / 补信息 / 重推过程）。
  bool get returnsToSolver =>
      this == VerificationPipelineStatus.solverRevisionRequired ||
      this == VerificationPipelineStatus.solverClarificationRequired ||
      this == VerificationPipelineStatus.solverProcessRepairRequired;

  /// 是否在等 Checker 报告（awaitingChecker 或已可接受下一轮）。
  bool get acceptsCheckerReport =>
      this == VerificationPipelineStatus.awaitingChecker ||
      this == VerificationPipelineStatus.solverProcessRepairRequired;
}

/// 一次流水线转移的结果。
///
/// [status] 是当前状态；[clarification] 只在回 solver 的 precheck 路径出现；
/// [handoff] 只在 clean 之后出现；[checkerReport] 是最近一轮 checker 报告；
/// [delivery] 只在未验证交付（unverified / humanRequired）出现——verified 的
/// 正常交付不构造 [UnverifiedDelivery]，因此不会生成教学延伸。
class VerificationPipelineResult {
  const VerificationPipelineResult._({
    required this.status,
    required this.reports,
    this.clarification,
    this.handoff,
    this.checkerReport,
    this.delivery,
  });

  final VerificationPipelineStatus status;

  /// 已收到的 checker 报告，按轮次排列（最多 `maxCheckerRounds` 条）。
  final List<CheckReport> reports;

  /// 回 solver 的澄清/修改请求；只有 precheck invalid/unknown 路径有。
  final SolverClarificationRequest? clarification;

  /// clean 之后交给 Checker teammate 的交接数据。
  final CheckerHandoff? handoff;

  /// 最近一轮 checker 报告。
  final CheckReport? checkerReport;

  /// 未验证交付；verified 路径为 null。
  final UnverifiedDelivery? delivery;

  /// 已收到几轮 checker 报告。
  int get checkerRounds => reports.length;

  /// 是否已终止。
  bool get isTerminal => status.isTerminal;

  /// 是否能接收下一轮 checker 报告（有 handoff 且未终止）。
  bool get canAcceptCheckerReport =>
      handoff != null && status.acceptsCheckerReport;

  /// 交付状态：未终止时为 null；verified 时是 [DeliveryStatus.verified]。
  DeliveryStatus? get deliveryStatus => switch (status) {
        VerificationPipelineStatus.verified => DeliveryStatus.verified,
        VerificationPipelineStatus.unverified =>
          delivery?.status ?? DeliveryStatus.unverified,
        VerificationPipelineStatus.humanRequired =>
          delivery?.status ?? DeliveryStatus.humanRequired,
        _ => null,
      };

  @override
  String toString() => 'VerificationPipelineResult('
      '${status.id}, checkerRounds: $checkerRounds, '
      'hasHandoff: ${handoff != null}, '
      'delivery: ${delivery?.status.id ?? 'null'})';
}

/// Precheck → Checker → 交付的纯状态机。
///
/// 每个 run 一个实例；它只持有确定性构造 handoff 需要的上下文（题目、冻结
/// 答案、结构化步骤、claim、来源 trace 引用、允许的 checker 工具），不持有
/// 模型、数据库或 checker 运行时。轮次状态在 [VerificationPipelineResult] 里，
/// 因此所有转移都是纯函数、可独立单测。
class VerificationPipeline {
  VerificationPipeline({
    required this.question,
    required this.frozenAnswer,
    required List<ProcessedStep> processedSteps,
    required this.provenanceRunId,
    required this.sourceTraceRef,
    required this.sourceTraceHash,
    List<Claim> claims = const <Claim>[],
    Map<String, Object?> toolEvidence = const <String, Object?>{},
    List<String> allowedCheckerTools = const <String>[],
    this.cluster = 'student_exam',
  })  : processedSteps = List<ProcessedStep>.unmodifiable(processedSteps),
        claims = List<Claim>.unmodifiable(claims),
        toolEvidence = Map<String, Object?>.unmodifiable(toolEvidence),
        allowedCheckerTools = List<String>.unmodifiable(allowedCheckerTools) {
    if (provenanceRunId.trim().isEmpty) {
      throw ArgumentError.value(
        provenanceRunId,
        'provenanceRunId',
        '流水线必须知道来源 run id',
      );
    }
    if (sourceTraceRef.trim().isEmpty || sourceTraceHash.trim().isEmpty) {
      throw ArgumentError.value(
        sourceTraceRef,
        'sourceTraceRef',
        '流水线必须知道来源 trace 引用与 hash',
      );
    }
  }

  /// Checker 最多审查两轮（设计 §7.5「最多两轮」）。
  static const int maxCheckerRounds = 2;

  /// 题目原文/题干结构化文本。
  final String question;

  /// 已冻结的最终答案；过程 repair 不允许改它。
  final String frozenAnswer;

  /// 交给 Checker 的结构化过程（不是 raw CoT）。
  final List<ProcessedStep> processedSteps;

  /// 来源 run id（同时写进 handoff 与学习记录的 provenance）。
  final String provenanceRunId;

  /// 来源 trace 的稳定引用（文件路径 / trace id / step 区间）。
  final String sourceTraceRef;

  /// 确定性程序对 trace/claim 快照计算的 hash。
  final String sourceTraceHash;

  /// 结构化 claim（来自 ClaimLedger，是 checker 核对条件的输入）。
  final List<Claim> claims;

  /// 确定性工具/验证器证据（JSON-safe）。
  final Map<String, Object?> toolEvidence;

  /// Checker teammate 允许使用的审核工具 id。
  final List<String> allowedCheckerTools;

  /// 学习记录的经验簇。
  final String cluster;

  /// precheck 之后的第一步：clean -> handoff；invalid/unknown -> 回 solver。
  ///
  /// invalid/unknown 的结果里没有 [VerificationPipelineResult.handoff]，且
  /// [VerificationPipelineResult.clarification] 非空；因此后续 [record] 会抛
  /// [StateError]，invalid/unknown 在结构上进不了 Checker。
  VerificationPipelineResult screen(PrecheckResult precheck) {
    if (precheck.allowsCheckerHandoff) {
      return VerificationPipelineResult._(
        status: VerificationPipelineStatus.awaitingChecker,
        reports: const <CheckReport>[],
        handoff: CheckerHandoff.fromPrecheck(
          precheck: precheck,
          sourceRunId: provenanceRunId,
          sourceTraceRef: sourceTraceRef,
          sourceTraceHash: sourceTraceHash,
          question: question,
          frozenAnswer: frozenAnswer,
          processedSteps: processedSteps,
          claims: claims,
          toolEvidence: toolEvidence,
          allowedCheckerTools: allowedCheckerTools,
        ),
      );
    }
    final status = precheck.outcome == PrecheckOutcome.invalid
        ? VerificationPipelineStatus.solverRevisionRequired
        : VerificationPipelineStatus.solverClarificationRequired;
    return VerificationPipelineResult._(
      status: status,
      reports: const <CheckReport>[],
      clarification: precheck.clarification,
    );
  }

  /// 提交一轮 Checker 报告。
  ///
  ///  * `pass` -> [VerificationPipelineStatus.verified]，不生成教学延伸；
  ///  * 第 1 轮 fail -> [VerificationPipelineStatus.solverProcessRepairRequired]
  ///    （solver 只做局部过程重推，答案冻结）；
  ///  * 第 `maxCheckerRounds` 轮 fail -> [VerificationPipelineStatus.unverified]
  ///    + [UnverifiedDelivery]（含教学延伸与学习记录）；
  ///  * uncheckable / fail 但没有可关闭的阻塞 issue -> 转人工。
  VerificationPipelineResult record({
    required VerificationPipelineResult previous,
    required CheckReport report,
  }) {
    if (previous.isTerminal) {
      throw StateError('流水线已终止（${previous.status.id}），不能再接收 checker 报告');
    }
    final handoff = previous.handoff;
    if (handoff == null) {
      throw StateError(
        '前一步是 ${previous.status.id}，没有 CheckerHandoff：'
        'invalid/unknown 只能回 solver，不能进入 Checker',
      );
    }
    final reports = List<CheckReport>.unmodifiable(
      <CheckReport>[...previous.reports, report],
    );

    if (report.verdict == CheckReportVerdict.uncheckable) {
      return _deliver(
        status: VerificationPipelineStatus.humanRequired,
        handoff: handoff,
        reports: reports,
        report: report,
        reason: 'Checker 无法判断（uncheckable），转人工复核',
      );
    }
    if (report.passed) {
      return VerificationPipelineResult._(
        status: VerificationPipelineStatus.verified,
        reports: reports,
        handoff: handoff,
        checkerReport: report,
      );
    }

    final blocking = report.issues.where((issue) => issue.blocksCompletion);
    if (blocking.isEmpty) {
      // fail 却给不出可关闭的阻塞 issue：无法局部重推，不要猜，转人工。
      return _deliver(
        status: VerificationPipelineStatus.humanRequired,
        handoff: handoff,
        reports: reports,
        report: report,
        reason: 'Checker 判 fail 但没有给出可关闭的阻塞 issue，无法 repair，转人工',
      );
    }
    if (reports.length < maxCheckerRounds) {
      return VerificationPipelineResult._(
        status: VerificationPipelineStatus.solverProcessRepairRequired,
        reports: reports,
        handoff: handoff,
        checkerReport: report,
      );
    }
    // 第 2 轮仍 fail：交付但标 unverified，并生成教学延伸 + 学习记录。
    return _deliver(
      status: VerificationPipelineStatus.unverified,
      handoff: handoff,
      reports: reports,
      report: report,
      reason: _unverifiedReason(reports),
    );
  }

  /// 过程修复后重建 handoff（设计 §7.5：repair process -> recheck）。
  ///
  /// 只替换处理后的步骤/claim 与来源 trace；冻结答案、题目、预检发现、允许
  /// 工具都保留，所以过程 repair 改不了最终答案。已收到的 checker 轮次保留，
  /// 下一轮 [record] 会按第 2 轮处理。
  VerificationPipelineResult rehandoff({
    required VerificationPipelineResult previous,
    required List<ProcessedStep> processedSteps,
    required String sourceTraceRef,
    required String sourceTraceHash,
    List<Claim>? claims,
    Map<String, Object?>? toolEvidence,
  }) {
    if (previous.isTerminal) {
      throw StateError('流水线已终止（${previous.status.id}），不能再重建 handoff');
    }
    final handoff = previous.handoff;
    if (handoff == null) {
      throw StateError('没有 CheckerHandoff：invalid/unknown 只能回 solver');
    }
    if (previous.reports.isEmpty) {
      throw StateError('Checker 还没有给出报告，重建 handoff 没有意义');
    }
    return VerificationPipelineResult._(
      status: VerificationPipelineStatus.awaitingChecker,
      reports: previous.reports,
      handoff: handoff.withProcess(
        processedSteps: processedSteps,
        sourceTraceRef: sourceTraceRef,
        sourceTraceHash: sourceTraceHash,
        claims: claims,
        toolEvidence: toolEvidence,
      ),
    );
  }

  /// 构造未验证交付（教学延伸 + 学习记录都是确定性模板，不调用模型）。
  VerificationPipelineResult _deliver({
    required VerificationPipelineStatus status,
    required CheckerHandoff handoff,
    required List<CheckReport> reports,
    required CheckReport report,
    required String reason,
  }) {
    final issue = _primaryIssue(reports);
    final extension = issue == null
        ? TeachingExtension.generic()
        : TeachingExtension.fromIssue(issue);
    final learningRecord = LearningRecord.fromCategory(
      cluster: cluster,
      issueCategory: issue?.category ?? CheckIssueCategory.other,
      evidence: issue == null
          ? reason
          : '${issue.evidence}；违反：${issue.violated}；最小修复：'
              '${issue.minimalFix}',
      provenanceRunId: provenanceRunId,
    );
    final delivery = status == VerificationPipelineStatus.unverified
        ? UnverifiedDelivery.fromCheckerFailure(
            reason: reason,
            answer: frozenAnswer,
            extension: extension,
            learningRecord: learningRecord,
          )
        : UnverifiedDelivery.humanRequired(
            reason: reason,
            answer: frozenAnswer,
            extension: extension,
            learningRecord: learningRecord,
          );
    return VerificationPipelineResult._(
      status: status,
      reports: reports,
      handoff: handoff,
      checkerReport: report,
      delivery: delivery,
    );
  }

  /// 当前最该报给用户/学习记录的一条 issue：优先最后一轮里的阻塞 issue。
  static CheckIssue? _primaryIssue(List<CheckReport> reports) {
    for (final report in reports.reversed) {
      if (report.issues.isEmpty) {
        continue;
      }
      final blocking =
          report.issues.where((issue) => issue.blocksCompletion).toList();
      return blocking.isNotEmpty ? blocking.last : report.issues.last;
    }
    return null;
  }

  /// 两轮不过的未验证原因（人可读，进 delivery.reason）。
  static String _unverifiedReason(List<CheckReport> reports) {
    final issues = <CheckIssue>[
      for (final report in reports)
        ...report.issues.where((issue) => issue.blocksCompletion),
    ];
    final lastFix =
        issues.isEmpty ? '' : '；最后一条未关闭问题：${issues.last.minimalFix}';
    return 'Checker 连续 ${reports.length} 轮过程审查未通过$lastFix';
  }
}

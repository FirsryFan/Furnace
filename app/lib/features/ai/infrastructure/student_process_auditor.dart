/// 学生模式的过程审计实现：读 reasoning 原文，产出 `ProcessReport`。
///
/// 这是《STUDENT-MODE-AND-AGENT-LOOP-DESIGN-2026-11-14》§7.4 的第二条轨：
///
///  * 内容验证（`student_verifier.dart`）只看题目 + 答案卡 + claim 摘要，
///    **不读** CoT；
///  * 过程审计（本文件）**必须读** CoT，查循环、反复自我怀疑、无进展，并把
///    抽出的 claim 登记进 `ClaimLedger`（同一 claim 在依赖版本未变时重复出现
///    会命中合并）。
///
/// 本文件只是把 domain 的 [ProcessAuditor]（确定性文本启发式）与
/// [ClaimLedger]（claim DAG / 去重 / 摘要）接起来：没有模型调用、没有网络、
/// 没有文件读写，所以同一段 reasoning 永远得到同一份报告。
///
/// 它**不判答案对错**——那是内容验证器的事；它的报告进入 StepGuard（是否
/// forceAnswer/repair/stop 的参考信号）、ClaimLedger、ContextAssembler 摘要与
/// `agent_verifications(kind = process)`。
library;

import '../domain/claim.dart';
import '../domain/process_auditor.dart';
import '../domain/reasoning_ledger.dart';
import '../domain/student_run.dart'
    show StudentProcessAuditResult, StudentProcessAuditSource;

/// 把 [ProcessAuditor] 与 [ClaimLedger] 组合成学生 run 的过程审计来源。
class StudentProcessAuditor implements StudentProcessAuditSource {
  StudentProcessAuditor({
    ProcessAuditor? auditor,
    ClaimLedger? ledger,
  })  : _auditor = auditor ?? ProcessAuditor(),
        _ledger = ledger;

  final ProcessAuditor _auditor;

  /// 一次 run 一个 ledger（claim 的版本/缓存只在 run 内有意义）；null 表示
  /// 只审计、不登记 claim，报告里的 claim 仍来自这次审计的抽取结果。
  final ClaimLedger? _ledger;

  ProcessAuditor get auditor => _auditor;

  ClaimLedger? get ledger => _ledger;

  @override
  Future<StudentProcessAuditResult> audit({
    required String reasoning,
    String? previousReasoning,
    List<String> actionSequence = const [],
    String? stateFingerprint,
    String? previousStateFingerprint,
  }) async {
    final base = _auditor.audit(
      reasoning: reasoning,
      previousReasoning: previousReasoning,
      actionSequence: actionSequence,
      stateFingerprint: stateFingerprint,
      previousStateFingerprint: previousStateFingerprint,
    );

    final ledger = _ledger;
    if (ledger == null) {
      return StudentProcessAuditResult(
        report: base,
        claimSummary: ClaimSummary.of(base.extractedClaims),
        // 没有 ledger 时，本次抽取就是「实际 claim 列表」；run 结束会落库。
        claims: base.extractedClaims,
      );
    }

    var registered = 0;
    var merged = 0;
    for (final claim in base.extractedClaims) {
      try {
        final registration = await ledger.register(claim);
        if (registration.merged) {
          merged += 1;
        } else {
          registered += 1;
        }
      } on StateError {
        // Ledger 满了：保留已登记部分，不把整次审计判成失败。
        break;
      }
    }

    // 摘要取自 ledger（已去重/排序），没有 raw CoT，只有 status/kind/statement。
    final summary = ledger.summary();
    final flags = <String>[...base.flags];
    if (merged > 0 && !flags.contains('repeated_claim')) {
      flags.add('repeated_claim');
    }
    final report = ProcessReport(
      loopDetected: base.loopDetected,
      stagnation: base.stagnation,
      repeatedClaimCount: base.repeatedClaimCount + merged,
      selfDoubtCount: base.selfDoubtCount,
      flags: flags,
      extractedClaims: summary.claims,
      reasoningChars: base.reasoningChars,
      sentenceCount: base.sentenceCount,
      uniqueSentenceCount: base.uniqueSentenceCount,
    );
    return StudentProcessAuditResult(
      report: report,
      claimSummary: summary,
      // ledger 去重后的列表就是这次 run 实际持有的 claim（落 agent_claims 用）。
      claims: summary.claims,
      registeredClaims: registered,
      mergedClaims: merged,
    );
  }
}

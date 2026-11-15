/// 确定性 HandoffBuilder：只有 clean 预检才能构造 [CheckerHandoff]。
///
/// 输入是预处理管线产出的 [NormalizedStep] / [ExtractedClaim]，输出是
/// processedSteps 与 handoff。约束（lead 2026-11-14 设计）：
///
///  * **零模型调用**：只做机械映射，字段来自 trace/claim，不做任何 LLM 摘要；
///  * 默认**不放整段 CoT**：每步只放主张（原文句子拼接）、归一化文本、来源
///    偏移/哈希与证据引用；不放 raw trace 全文；
///  * **tokenBudget**：按字符数保守估算（[estimateStepTokens]）；超预算时做
///    确定性截断——先丢中间步骤（保留首尾 + [mustKeepStepIds] 锚点/带 finding
///    的步骤 + 全部 refs/sourceHash），仍超预算时对最长步骤的文本做首尾裁剪；
///    不调用模型改写/压缩；
///  * invalid/unknown 预检不生成 handoff（此时 [HandoffBuildResult.handoff] 为
///    null）。
library;

import 'checker_handoff.dart';
import 'claim.dart';
import 'claim_extractor.dart';
import 'normalizer.dart';

/// 一次 handoff 构造的结果。
class HandoffBuildResult {
  const HandoffBuildResult({
    required this.precheck,
    required this.handoff,
    required this.processedSteps,
    this.truncated = false,
    this.droppedStepIds = const <String>[],
  });

  final PrecheckResult precheck;

  /// 非 clean 预检时为 null（invalid/unknown 不进入 Checker）。
  final CheckerHandoff? handoff;

  /// 实际放进 handoff 的步骤（截断后；非 clean 时为空）。
  final List<ProcessedStep> processedSteps;

  /// 是否发生确定性截断。
  final bool truncated;

  /// 被整段丢弃的步骤 id（保留 refs 的步骤不会出现在这里）。
  final List<String> droppedStepIds;
}

/// 纯规则 handoff 构造器。
class HandoffBuilder {
  const HandoffBuilder({
    this.tokenBudget = 4000,
    this.maxStepChars = 800,
    this.allowedCheckerTools = const <String>[],
  });

  /// processedSteps 的 token 预算（按字符数保守估算）。
  final int tokenBudget;

  /// 单步 claim/normalizedClaim 的字符上限（超出时机械地保留首尾）。
  final int maxStepChars;

  /// 允许 Checker teammate 使用的审核工具 id。
  final List<String> allowedCheckerTools;

  /// 一步的预算估算：主张 + 归一化主张 + 证据（refs 是元数据，不计入预算）。
  static int estimateStepTokens(ProcessedStep step) =>
      step.claim.runes.length +
      (step.normalizedClaim?.runes.length ?? 0) +
      step.evidence.runes.length;

  /// 机械截断：保留首尾，中间用 `…` 标记；不做任何语义压缩。
  static String clip(String text, int maxChars) {
    final length = text.runes.length;
    if (length <= maxChars) {
      return text;
    }
    final head = (maxChars - 1) ~/ 2;
    final tail = maxChars - 1 - head;
    final runes = text.runes.toList();
    return '${String.fromCharCodes(runes.take(head))}…'
        '${String.fromCharCodes(runes.skip(length - tail))}';
  }

  /// 构造 handoff；invalid/unknown 预检直接返回 null handoff。
  HandoffBuildResult build({
    required String runId,
    required String sourceTraceRef,
    required String sourceTraceHash,
    required String question,
    required String frozenAnswer,
    required PrecheckResult precheck,
    required List<NormalizedStep> normalizedSteps,
    required List<ExtractedClaim> claims,
    List<Claim> structuredClaims = const <Claim>[],
    Map<String, Object?> toolEvidence = const <String, Object?>{},
    List<String> toolEvidenceRefs = const <String>[],
    List<String> mustKeepStepIds = const <String>[],
  }) {
    if (!precheck.allowsCheckerHandoff) {
      return HandoffBuildResult(
        precheck: precheck,
        handoff: null,
        processedSteps: const <ProcessedStep>[],
      );
    }

    final claimsByStep = <String, List<ExtractedClaim>>{};
    for (final claim in claims) {
      claimsByStep
          .putIfAbsent(claim.stepId, () => <ExtractedClaim>[])
          .add(claim);
    }
    final mustKeep = mustKeepStepIds.toSet();
    var processed = <ProcessedStep>[
      for (final step in normalizedSteps)
        _buildStep(
          step,
          claimsByStep[step.stepId] ?? const <ExtractedClaim>[],
          mustKeep.contains(step.stepId),
        ),
    ];

    var truncated = false;
    final dropped = <String>[];
    if (_totalTokens(processed) > tokenBudget) {
      truncated = true;
      final keepIds = <String>{};
      if (processed.isNotEmpty) {
        keepIds
          ..add(processed.first.id)
          ..add(processed.last.id);
      }
      keepIds.addAll(mustKeep.where(
        (id) => processed.any((step) => step.id == id),
      ));
      var used = processed
          .where((step) => keepIds.contains(step.id))
          .fold<int>(0, (sum, step) => sum + estimateStepTokens(step));
      for (final step in processed) {
        if (keepIds.contains(step.id)) {
          continue;
        }
        final cost = estimateStepTokens(step);
        if (used + cost <= tokenBudget) {
          keepIds.add(step.id);
          used += cost;
        } else {
          dropped.add(step.id);
        }
      }
      processed = <ProcessedStep>[
        for (final step in processed)
          if (keepIds.contains(step.id)) step,
      ];
      // 首尾/锚点/refs 是硬要求：即使仍超预算也只裁剪文本，不丢步骤/refs。
      var guard = 0;
      while (_totalTokens(processed) > tokenBudget && guard < 1000) {
        guard++;
        var longestIndex = -1;
        var longestLength = 0;
        for (var index = 0; index < processed.length; index++) {
          final length = processed[index].claim.runes.length +
              (processed[index].normalizedClaim?.runes.length ?? 0);
          if (length > longestLength) {
            longestLength = length;
            longestIndex = index;
          }
        }
        if (longestIndex < 0 || longestLength <= 80) {
          break;
        }
        processed[longestIndex] = _clipStep(
          processed[longestIndex],
          longestLength ~/ 2,
        );
        truncated = true;
      }
    }

    final handoff = CheckerHandoff.fromPrecheck(
      precheck: precheck,
      sourceRunId: runId,
      sourceTraceRef: sourceTraceRef,
      sourceTraceHash: sourceTraceHash,
      question: question,
      frozenAnswer: frozenAnswer,
      processedSteps: processed,
      claims: structuredClaims,
      toolEvidence: toolEvidence,
      toolEvidenceRefs: toolEvidenceRefs,
      allowedCheckerTools: allowedCheckerTools,
      tokenBudget: tokenBudget,
      truncated: truncated,
    );
    return HandoffBuildResult(
      precheck: precheck,
      handoff: handoff,
      processedSteps: List<ProcessedStep>.unmodifiable(processed),
      truncated: truncated,
      droppedStepIds: List<String>.unmodifiable(dropped),
    );
  }

  ProcessedStep _buildStep(
    NormalizedStep step,
    List<ExtractedClaim> stepClaims,
    bool mustKeep,
  ) {
    final flags = <String>{
      for (final kind in stepClaims.map((claim) => claim.kind.id).toSet())
        'claim:$kind',
      if (stepClaims.isEmpty) 'raw_step',
      if (stepClaims.any((claim) => claim.isUnclassified)) 'unclassified',
      if (mustKeep) 'must_keep',
    }.toList();
    final claimText = stepClaims.isEmpty
        ? step.traceStep.rawText
        : stepClaims.map((claim) => claim.text).join('；');
    return ProcessedStep(
      id: step.stepId,
      claim: clip(claimText, maxStepChars),
      evidence: 'trace:${step.stepId}'
          '@[${step.traceStep.sourceStart},${step.traceStep.sourceEnd})',
      sourceStepId: step.stepId,
      deterministicFlags: flags,
      normalizedClaim: clip(step.normalized, maxStepChars),
      evidenceRefs: <String>[
        'trace:${step.stepId}',
        for (final claim in stepClaims) claim.evidenceRef,
      ],
      sourceHash: step.sourceHash,
    );
  }

  ProcessedStep _clipStep(ProcessedStep step, int targetChars) {
    final claimBudget = (targetChars ~/ 2).clamp(20, maxStepChars);
    final normalizedBudget = targetChars - claimBudget;
    return ProcessedStep(
      id: step.id,
      claim: clip(step.claim, claimBudget),
      evidence: step.evidence,
      sourceStepId: step.sourceStepId,
      deterministicFlags: step.deterministicFlags,
      normalizedClaim: step.normalizedClaim == null
          ? null
          : clip(
              step.normalizedClaim!, normalizedBudget.clamp(20, maxStepChars)),
      evidenceRefs: step.evidenceRefs,
      sourceHash: step.sourceHash,
    );
  }

  static int _totalTokens(List<ProcessedStep> steps) =>
      steps.fold<int>(0, (sum, step) => sum + estimateStepTokens(step));
}

/// 确定性预处理管线编排：TraceParser → Normalizer → ClaimExtractor →
/// DeterministicPrecheck → HandoffBuilder（全部纯规则、零模型调用）。
///
/// 这一层是「从 StudentRunResult/trace/claims 机械构造 CheckerHandoff」的入口
/// （lead 2026-11-14 设计）：任何解析/归一化失败都转成
/// `PrecheckResult.parseFailure`（= unknown）回 solver，绝不把不确定交给 Checker，
/// 也绝不让 LLM 补写/摘要。
library;

import 'checker_handoff.dart';
import 'checkpoint.dart';
import 'claim.dart';
import 'claim_extractor.dart';
import 'deterministic_precheck.dart';
import 'handoff_builder.dart';
import 'normalizer.dart';
import 'trace_parser.dart';

/// 一次确定性预处理的完整产物（供排障/落库；handoff 在 build 里）。
class DeterministicPreprocessResult {
  const DeterministicPreprocessResult({
    required this.trace,
    required this.steps,
    required this.claims,
    required this.precheck,
    required this.build,
  });

  final TraceParseResult trace;
  final List<NormalizedStep> steps;
  final List<ExtractedClaim> claims;
  final PrecheckResult precheck;
  final HandoffBuildResult build;

  CheckerHandoff? get handoff => build.handoff;

  bool get hasHandoff => build.handoff != null;
}

/// 纯规则预处理管线。
class DeterministicPreprocessor {
  DeterministicPreprocessor({
    CheckpointSet? checkpoints,
    List<String> branchCases = const <String>[],
    List<String> entityVocabulary = const <String>[],
    this.tokenBudget = 4000,
    List<String> allowedCheckerTools = const <String>[],
    TraceParser? parser,
    Normalizer? normalizer,
    ClaimExtractor? extractor,
    DeterministicPrecheck? precheck,
    HandoffBuilder? builder,
  })  : checkpoints = checkpoints,
        branchCases = List<String>.unmodifiable(branchCases),
        entityVocabulary = List<String>.unmodifiable(entityVocabulary),
        parser = parser ?? const TraceParser(),
        normalizer = normalizer ?? const Normalizer(),
        extractor = extractor ?? const ClaimExtractor(),
        prechecker = precheck ??
            DeterministicPrecheck(
              checkpoints: checkpoints,
              branchCases: branchCases,
            ),
        builder = builder ??
            HandoffBuilder(
              tokenBudget: tokenBudget,
              allowedCheckerTools: allowedCheckerTools,
            );

  /// 题目锚点（required 锚点参与预检；所有锚点命中步骤会被保留）。
  final CheckpointSet? checkpoints;

  /// 分支 case table（空表示不检查分支覆盖）。
  final List<String> branchCases;

  /// 实体词表（ClaimExtractor 只认这些实体，不凭空发明）。
  final List<String> entityVocabulary;

  /// processedSteps 的 token 预算。
  final int tokenBudget;

  final TraceParser parser;
  final Normalizer normalizer;
  final ClaimExtractor extractor;
  final DeterministicPrecheck prechecker;
  final HandoffBuilder builder;

  /// 跑完整条确定性管线。
  DeterministicPreprocessResult run({
    required String runId,
    required String sourceTraceRef,
    required String question,
    required String rawReasoning,
    required String processText,
    required String frozenAnswer,
    List<Claim> structuredClaims = const <Claim>[],
    Map<String, Object?> toolEvidence = const <String, Object?>{},
    List<String> toolEvidenceRefs = const <String>[],
  }) {
    final trace = parser.parse(
      rawReasoning: rawReasoning,
      processText: processText,
    );

    if (!trace.succeeded) {
      // 解析失败：不生成 handoff，回 solver 补信息。
      final precheck = PrecheckResult.parseFailure(
        detail: trace.failure ?? 'trace 解析失败',
      );
      final build = builder.build(
        runId: runId,
        sourceTraceRef: sourceTraceRef,
        sourceTraceHash: trace.sourceHash,
        question: question,
        frozenAnswer: frozenAnswer,
        precheck: precheck,
        normalizedSteps: const <NormalizedStep>[],
        claims: const <ExtractedClaim>[],
        structuredClaims: structuredClaims,
        toolEvidence: toolEvidence,
        toolEvidenceRefs: toolEvidenceRefs,
      );
      return DeterministicPreprocessResult(
        trace: trace,
        steps: const <NormalizedStep>[],
        claims: const <ExtractedClaim>[],
        precheck: precheck,
        build: build,
      );
    }

    final steps = <NormalizedStep>[
      for (final step in trace.steps) normalizer.normalizeStep(step),
    ];
    final claims = <ExtractedClaim>[
      for (final step in steps)
        ...extractor.extract(step, entityVocabulary: entityVocabulary),
    ];
    final precheck = prechecker.check(
      question: question,
      frozenAnswer: frozenAnswer,
      steps: steps,
      claims: claims,
    );
    final build = builder.build(
      runId: runId,
      sourceTraceRef: sourceTraceRef,
      sourceTraceHash: trace.sourceHash,
      question: question,
      frozenAnswer: frozenAnswer,
      precheck: precheck,
      normalizedSteps: steps,
      claims: claims,
      structuredClaims: structuredClaims,
      toolEvidence: toolEvidence,
      toolEvidenceRefs: toolEvidenceRefs,
      mustKeepStepIds: _anchorStepIds(steps),
    );
    return DeterministicPreprocessResult(
      trace: trace,
      steps: steps,
      claims: claims,
      precheck: precheck,
      build: build,
    );
  }

  /// 命中题目锚点约束的步骤 id（确定性；截断时必须保留这些步骤）。
  List<String> _anchorStepIds(List<NormalizedStep> steps) {
    final anchors = checkpoints;
    if (anchors == null) {
      return const <String>[];
    }
    final needles = <String>[
      for (final checkpoint in anchors.checkpoints)
        for (final constraint in checkpoint.constraints)
          if (constraint.isCheckable)
            for (final value in <String>[
              ...constraint.acceptable,
              ...constraint.alternatives,
            ])
              if (normalizer.normalize(value).isNotEmpty)
                normalizer.normalize(value),
    ];
    if (needles.isEmpty) {
      return const <String>[];
    }
    return <String>[
      for (final step in steps)
        if (needles.any((needle) => step.normalized.contains(needle)))
          step.stepId,
    ];
  }
}

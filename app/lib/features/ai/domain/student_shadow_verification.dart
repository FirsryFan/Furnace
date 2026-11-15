/// Shadow 预检：把一次学生 run 的 reasoning / answer / claims 机械送进确定性
/// 预处理管线（TraceParser → Normalizer → ClaimExtractor →
/// DeterministicPrecheck → HandoffBuilder）与 [VerificationPipeline] 的 precheck
/// 阶段，**只记录结果，不改变 run 的交付**。
///
/// 边界（task-32，lead 2026-11-15）：
///
///  * **零模型调用**：本文件不 import 任何 `ModelAdapter`/adapter 抽象；确定性
///    实现只做纯 Dart 规则解析与状态转移；
///  * **不调 Checker**：只跑到 [VerificationPipeline.screen]——clean 时得到
///    `CheckerHandoff`（status = awaitingChecker），invalid/unknown/解析失败时
///    得到 `SolverClarificationRequest`（回 solver）；绝不会把不确定说成 clean；
///  * **不改交付**：结果只挂在 `StudentRunResult.shadowVerification`，不写 DB，
///    不触发 repair，不影响 stage / verdict / verified / answer。
///
/// 为什么不是直接给 `StudentRun` 传一个 `VerificationPipeline?`：流水线实例在
/// 构造时就绑定这份 run 的 `frozenAnswer`/`processedSteps`（见
/// `verification_pipeline.dart` 的构造函数），而这些要等 run 跑完才确定；因此
/// 这里用「等价纯 domain 依赖」——[StudentShadowVerification] 接口——在 run 结束
/// 时用真实输入构造流水线并只跑 precheck 阶段。生产实现见
/// [DeterministicShadowVerification]。
library;

import 'claim.dart';
import 'deterministic_preprocessor.dart';
import 'verification_pipeline.dart';

/// Shadow 预检的纯 domain 依赖。
///
/// 输入是一次 run 结束时已经确定的数据（raw reasoning、答案卡过程、冻结答案、
/// 结构化 claim）；输出是流水线 precheck 阶段的结果。同步且不得抛模型调用：
/// 实现要么是 [DeterministicShadowVerification]（纯规则），要么是测试 fake。
/// **不允许**在这里调用 Checker teammate 或任何 LLM。
abstract interface class StudentShadowVerification {
  VerificationPipelineResult verify({
    required String runId,
    required String question,
    required String frozenAnswer,
    required String rawReasoning,
    required String processText,
    List<Claim> claims = const <Claim>[],
  });
}

/// 进程内共享的默认预处理器。
///
/// [DeterministicPreprocessor] 及其 parser/normalizer/extractor/precheck/builder
/// 都只有 final 配置、没有可变状态，所以生产上所有 run 复用同一个实例即可；
/// [DeterministicShadowVerification] 因此可以提供 `const` 构造（默认接线用）。
final DeterministicPreprocessor _defaultShadowPreprocessor =
    DeterministicPreprocessor();

/// 生产用 shadow 实现：确定性预处理管线 + [VerificationPipeline.screen]。
///
/// 不持有模型/数据库；同一次 run 的两次调用是确定性的（同输入同 handoff
/// contentHash）。`sourceTraceRef` 用 run 的稳定逻辑引用
/// `student_run:<runId>/reasoning`，`sourceTraceHash` 由 TraceParser 对
/// reasoning + process 快照计算，二者都写进 handoff 供下游追溯。
///
/// 无参构造是 `const`，所以默认接线（`StudentModeController`）可以直接写
/// `shadowVerifier: const DeterministicShadowVerification()`。
class DeterministicShadowVerification implements StudentShadowVerification {
  const DeterministicShadowVerification({this.preprocessor});

  /// 可注入的预处理器（测试用不同锚点/分支表）；null 表示进程内默认实例。
  final DeterministicPreprocessor? preprocessor;

  DeterministicPreprocessor get _effectivePreprocessor =>
      preprocessor ?? _defaultShadowPreprocessor;

  @override
  VerificationPipelineResult verify({
    required String runId,
    required String question,
    required String frozenAnswer,
    required String rawReasoning,
    required String processText,
    List<Claim> claims = const <Claim>[],
  }) {
    final sourceTraceRef = 'student_run:$runId/reasoning';
    final preprocessed = _effectivePreprocessor.run(
      runId: runId,
      sourceTraceRef: sourceTraceRef,
      question: question,
      rawReasoning: rawReasoning,
      processText: processText,
      frozenAnswer: frozenAnswer,
      structuredClaims: claims,
    );
    final pipeline = VerificationPipeline(
      question: question,
      frozenAnswer: frozenAnswer,
      processedSteps: preprocessed.build.processedSteps,
      provenanceRunId: runId,
      sourceTraceRef: sourceTraceRef,
      sourceTraceHash: preprocessed.trace.sourceHash,
      claims: claims,
    );
    return pipeline.screen(preprocessed.precheck);
  }
}

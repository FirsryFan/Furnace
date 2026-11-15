/// 内容验证器（ContentVerifier）的接口与四态结论。
///
/// 这是《STUDENT-MODE-AND-AGENT-LOOP-DESIGN-2026-11-14》§7.3：verifier 只看
/// **题目 + 答案卡 + 结构化 claim 摘要**，**不读** solver 的原始 CoT。理由写在
/// §7.4：内容验证要被 solver 的错误推理带偏，就不该看见它；看过程是
/// `ProcessAuditor`（`process_auditor.dart`）的事。
///
/// 四态是刻意的：`pass` / `fail` / `unknown` / `error` 互不冒充——`unknown`
/// 不是 pass（不能静默放行），`error` 也不是 fail（验证器自身出错不等于答案错）。
library;

import 'claim.dart';
import 'model_adapter.dart';
import 'student_answer_sheet.dart';

/// 验证结论（设计文档 §7.3）。
enum Verdict {
  pass('pass'),
  fail('fail'),
  unknown('unknown'),
  error('error');

  const Verdict(this.id);

  /// 落库用的稳定值。
  final String id;

  /// 是否是「答案可用」的结论。只有 pass 算——unknown/error 必须保留成未验证。
  bool get allowsFinalize => this == Verdict.pass;

  /// 是否触发 repair（只有 fail 会）。
  bool get triggersRepair => this == Verdict.fail;

  static Verdict fromId(String? id) => switch (id) {
        'pass' => Verdict.pass,
        'fail' => Verdict.fail,
        'unknown' => Verdict.unknown,
        'error' => Verdict.error,
        _ => Verdict.unknown,
      };
}

/// 失败类型（设计文档 §5.3 `failure_type`）。
///
/// 内容验证与过程审计共用这个枚举：`missing_answer` 这类是内容问题，
/// `loop` / `self_doubt` 这类来自过程审计。分开记录（见
/// `agent_verifications.kind`），但类型词表统一，避免同一个问题两套叫法。
enum FailureType {
  /// 答案卡里没有可用答案。
  missingAnswer('missing_answer'),

  /// 选错分支 / 在已 settled 的分支上重开。
  wrongBranch('wrong_branch'),

  /// 有小问没有回答。
  incompleteSubQuestion('incomplete_sub_question'),

  /// 过程与答案不自洽。
  inconsistentProcess('inconsistent_process'),

  /// 单位 / 端点 / 边界问题。
  unitOrEndpoint('unit_or_endpoint'),

  /// 过程出现循环。
  loop('loop'),

  /// 反复自我怀疑。
  selfDoubt('self_doubt'),

  /// 过程无进展。
  stagnation('stagnation'),

  /// 输出无法解析成答案卡。
  unparsable('unparsable'),

  /// 验证器自身出错。
  verifierError('verifier_error'),

  /// 其它。
  other('other');

  const FailureType(this.id);

  /// 落库用的稳定值。
  final String id;

  static FailureType? fromId(String? id) {
    if (id == null) {
      return null;
    }
    for (final type in FailureType.values) {
      if (type.id == id) {
        return type;
      }
    }
    return null;
  }
}

/// 验证类别：内容验证看答案，过程审计看 CoT（设计文档 §5.3 `kind`）。
enum VerifierKind {
  content('content'),
  process('process');

  const VerifierKind(this.id);

  final String id;

  static VerifierKind fromId(String? id) =>
      id == 'process' ? VerifierKind.process : VerifierKind.content;
}

/// 一次验证的结论（设计文档 §7.3 的 `Verification`）。
class Verification {
  const Verification({
    required this.verdict,
    this.failureType,
    this.issues = const [],
    this.evidence = const {},
    this.independent = true,
    this.confidence,
    this.promptTokens,
    this.completionTokens,
  });

  /// 通过。
  factory Verification.pass({
    List<String> issues = const [],
    Map<String, Object?> evidence = const {},
    bool independent = true,
    double? confidence,
  }) {
    return Verification(
      verdict: Verdict.pass,
      issues: issues,
      evidence: evidence,
      independent: independent,
      confidence: confidence,
    );
  }

  /// 判 fail：必须给 [failureType]（`fail` 却说不清失败类型 = 无法 repair）。
  factory Verification.fail({
    required FailureType failureType,
    List<String> issues = const [],
    Map<String, Object?> evidence = const {},
    bool independent = true,
    double? confidence,
  }) {
    return Verification(
      verdict: Verdict.fail,
      failureType: failureType,
      issues: issues,
      evidence: evidence,
      independent: independent,
      confidence: confidence,
    );
  }

  /// 判不了（不是通过，也不触发 repair）。
  factory Verification.unknown({
    FailureType? failureType,
    List<String> issues = const [],
    Map<String, Object?> evidence = const {},
    bool independent = true,
  }) {
    return Verification(
      verdict: Verdict.unknown,
      failureType: failureType,
      issues: issues,
      evidence: evidence,
      independent: independent,
    );
  }

  /// 验证器自身出错（不是答案错）。
  factory Verification.error({
    String? message,
    Map<String, Object?> evidence = const {},
    bool independent = true,
  }) {
    return Verification(
      verdict: Verdict.error,
      failureType: FailureType.verifierError,
      issues: [if (message != null) message],
      evidence: evidence,
      independent: independent,
    );
  }

  final Verdict verdict;
  final FailureType? failureType;
  final List<String> issues;
  final Map<String, Object?> evidence;

  /// 这次验证是否独立于 solver（内容验证 true；过程审计 false —— 它读的就是
  /// solver 的 CoT）。落库到 `agent_verifications.independent`。
  final bool independent;

  /// 0..1 的置信度；NULL = 没给（vendor 没有校准过的置信度）。
  final double? confidence;

  final int? promptTokens;
  final int? completionTokens;

  bool get isPass => verdict == Verdict.pass;

  bool get isFail => verdict == Verdict.fail;

  bool get isUnknown => verdict == Verdict.unknown;

  bool get isError => verdict == Verdict.error;

  /// 最终答案卡能不能按「已验证」收尾。只有 pass 可以；unknown/error 必须保留
  /// `unverified` / `verifier_error` 标记（设计文档 §3.2 / §9.3）。
  bool get allowsFinalize => verdict.allowsFinalize;

  Map<String, Object?> toJson() => {
        'verdict': verdict.id,
        if (failureType != null) 'failure_type': failureType!.id,
        'issues': issues,
        'evidence': evidence,
        'independent': independent,
        if (confidence != null) 'confidence': confidence,
        if (promptTokens != null) 'prompt_tokens': promptTokens,
        if (completionTokens != null) 'completion_tokens': completionTokens,
      };

  /// 宽松解析：坏 JSON 退化成 `error`，绝不解析成 `pass`。
  factory Verification.fromJson(Object? json) {
    if (json is! Map) {
      return Verification.error(message: '验证结论不是 JSON 对象');
    }
    return Verification(
      verdict: Verdict.fromId(json['verdict'] is String ? json['verdict'] as String : null),
      failureType: FailureType.fromId(
        json['failure_type'] is String ? json['failure_type'] as String : null,
      ),
      issues: [
        if (json['issues'] is List)
          for (final issue in json['issues'] as List)
            if (issue is String) issue,
      ],
      evidence: json['evidence'] is Map
          ? {
              for (final entry in (json['evidence'] as Map).entries)
                entry.key.toString(): entry.value,
            }
          : const {},
      independent: json['independent'] is bool ? json['independent'] as bool : true,
      confidence: json['confidence'] is num
          ? (json['confidence'] as num).toDouble()
          : null,
      promptTokens: json['prompt_tokens'] is int ? json['prompt_tokens'] as int : null,
      completionTokens:
          json['completion_tokens'] is int ? json['completion_tokens'] as int : null,
    );
  }

  @override
  String toString() => 'Verification(${verdict.id}'
      '${failureType == null ? '' : ': ${failureType!.id}'}, '
      'issues: ${issues.length}, independent: $independent)';
}

/// 内容验证器接口（设计文档 §7.3）。
///
/// 输入刻意**没有** `reasoning` 参数：只看题目、答案卡、图与结构化 claim 摘要。
/// 实现者（学生 v1 是 `StudentVerifier`，后续可换成真实 LLM judge）必须保证
/// 这个签名不被偷偷加回原始 CoT——否则 §7.4 的双轨拆分就失效了。
///
/// [id] 是落进 `agent_verifications.verifier` 的稳定标识；[kind] 固定
/// [VerifierKind.content]（过程审计有自己的类，不走这个接口）。
abstract interface class Verifier {
  /// 稳定标识（如 `student_independent_v1`）。
  String get id;

  /// 验证类别；内容验证器一律 [VerifierKind.content]。
  VerifierKind get kind;

  /// 验证一份答案卡。
  ///
  /// [claims] 是 ProcessAuditor / ClaimLedger 产出的结构化摘要（claim 模块的
  /// [ClaimSummary]），不是原始 CoT；没有过程审计时传 `const
  /// ClaimSummary.empty()`。
  Future<Verification> verify({
    required String question,
    required StudentAnswerSheet answer,
    List<ChatImagePart> images,
    required ClaimSummary claims,
  });
}

/// 可选的确定性答案裁决器（有标准答案时使用）。
///
/// 设计原则（用户 2026-11-14 明确）：独立重解只能用于“发现差异”，不能把
/// 重解结果当成标准；如果能拿到经过治理的标准答案/rubric，就跳过 LLM judge，
/// 用确定性比较给出 pass/fail。标准答案只在 verifier 侧使用，绝不进入 solver
/// prompt，也不进入 solver 的 CoT。
abstract interface class AnswerOracle {
  /// 稳定标识，例如 `teacher_confirmed_rubric`。
  String get id;

  /// 对候选答案卡做确定性检查；返回四态之一。
  Future<Verification> check({
    required String question,
    required StudentAnswerSheet answer,
  });
}

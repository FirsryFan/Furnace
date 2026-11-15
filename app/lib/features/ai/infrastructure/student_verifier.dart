/// 学生模式的内容验证器：一次**独立**的模型调用，只判答案卡内容。
///
/// 这是《STUDENT-MODE-AND-AGENT-LOOP-DESIGN-2026-11-14》§7.3 的实现，§7.4 的
/// 双轨拆分决定了它**能看见什么**：
///
///  * 能看见：题目文字、题图、候选答案卡、过程审计产出的结构化 claim 摘要；
///  * 看不见：solver 的 reasoning 原文（[Verifier.verify] 的签名里就没有这个
///    参数）、任何官方答案 / 答案文件 / 答案记录文件。
///
/// 为什么这么拆：内容对错要被独立判断，不能被 solver 的错误推理带偏；而
/// 「反复怀疑 / 循环」由 `StudentProcessAuditor` 从 CoT 里看。这个文件因此
/// 不 import `dart:io`，也不读任何文件——它拿到的输入就是全部输入。
///
/// 输出是严格四态：`pass / fail / unknown / error`（[Verdict]）。模型返回的
/// JSON 解析失败、模型调用失败、模型没给 verdict，都不会被当成 `pass`：前两者
/// 落 `error`，模型明确给 `unknown` 落 `unknown`——设计文档 §3.2「unknown/error
/// 不伪装成 pass」。
library;

import 'dart:convert';

import '../domain/claim.dart';
import '../domain/model_adapter.dart';
import '../domain/student_answer_sheet.dart';
import '../domain/verifier.dart';

/// 学生 v1 的独立内容验证器（设计文档 §7.3）。
///
/// 「同一模型独立调用」：它复用应用配置的同一个模型（构造时注入的
/// [adapter]），但每次验证是一个全新的、只含题目/答案卡/claim 摘要的回合，
/// 与 solver 的会话没有任何共享上下文。
class StudentVerifier implements Verifier {
  StudentVerifier({
    required this.adapter,
    this.id = defaultId,
    this.systemPrompt = verificationSystemPrompt,
    this.oracle,
  });

  /// 可选的标准答案裁决器。有它时完全跳过模型 judge；标准答案只在
  /// verifier 侧使用，不进入 solver prompt。
  final AnswerOracle? oracle;

  /// 落进 `agent_verifications.verifier` 的稳定标识。
  static const String defaultId = 'student_independent_v1';

  /// 验证用的模型 adapter（与 solver 同一个模型配置，独立回合）。
  final ModelAdapter adapter;

  @override
  final String id;

  /// 验证员 prompt；测试可覆盖，但默认版本不含任何题目答案提示。
  final String systemPrompt;

  @override
  VerifierKind get kind => VerifierKind.content;

  @override
  Future<Verification> verify({
    required String question,
    required StudentAnswerSheet answer,
    List<ChatImagePart> images = const [],
    required ClaimSummary claims,
  }) async {
    final oracleCheck = oracle;
    if (oracleCheck != null) {
      return oracleCheck.check(question: question, answer: answer);
    }
    final text = StringBuffer();
    String? finishReason;
    String? error;
    int? promptTokens;
    int? completionTokens;

    await for (final event in adapter.runTurn(
      messages: [
        ChatMessage.system(systemPrompt),
        ChatMessage.user(
          _verificationInput(
            question: question,
            answer: answer,
            claims: claims,
          ),
          images: images,
        ),
      ],
      tools: const <ModelToolSpec>[],
    )) {
      if (event is ModelTextDelta) {
        text.write(event.text);
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

    if (error != null) {
      return Verification.error(
        message: 'verifier model failed: $error',
        evidence: {
          'source': 'model',
          if (finishReason != null) 'finish_reason': finishReason,
        },
      );
    }

    final raw = _extractJson(text.toString());
    if (raw == null) {
      // 没有可解析的结论 ≠ 通过。verifier 自身没给出可用结论，记 error。
      return Verification.error(
        message: 'verifier output was not a JSON verdict object',
        evidence: {
          'source': 'model',
          if (finishReason != null) 'finish_reason': finishReason,
          'output_chars': text.length,
          'raw_output': text.length <= 4000
              ? text.toString()
              : text.toString().substring(0, 4000),
        },
      );
    }

    final verdict = Verdict.fromId(
      raw['verdict'] is String ? raw['verdict'] as String : null,
    );
    final failureType = FailureType.fromId(
      raw['failure_type'] is String ? raw['failure_type'] as String : null,
    );
    final issues = <String>[
      if (raw['issues'] is List)
        for (final issue in raw['issues'] as List)
          if (issue is String && issue.trim().isNotEmpty) issue.trim(),
      if (raw['issues'] is String &&
          (raw['issues'] as String).trim().isNotEmpty)
        (raw['issues'] as String).trim(),
    ];
    final evidence = <String, Object?>{
      'source': 'model',
      if (finishReason != null) 'finish_reason': finishReason,
      if (raw['verdict'] is String) 'raw_verdict': raw['verdict'],
      if (raw['failure_type'] is String) 'raw_failure_type': raw['failure_type'],
      if (raw['independent_answer'] is String)
        'independent_answer': raw['independent_answer'],
      if (raw['confidence'] is num) 'confidence': raw['confidence'],
      if (raw['evidence'] is Map)
        for (final entry in (raw['evidence'] as Map).entries)
          'model_${entry.key}': entry.value,
    };
    final confidence = raw['confidence'] is num
        ? (raw['confidence'] as num).toDouble().clamp(0.0, 1.0)
        : null;

    return Verification(
      verdict: verdict,
      failureType: verdict == Verdict.fail
          ? (failureType ?? FailureType.other)
          : failureType,
      issues: issues,
      evidence: evidence,
      independent: true,
      confidence: confidence,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
    );
  }

  /// 验证员看到的输入：题目 + 候选答案卡 + claim 摘要。
  ///
  /// 刻意没有 reasoning 参数：内容验证不读 solver 的链式思考（§7.4）。
  static String _verificationInput({
    required String question,
    required StudentAnswerSheet answer,
    required ClaimSummary claims,
  }) {
    final stem = question.trim().isEmpty ? '（题目只有图片，请从图中读题）' : question.trim();
    return '''
题目：
$stem

候选答案卡：
${answer.toPlainText()}

过程审计抽取的 claim 摘要（结构化；不是推理原文，仅作参考）：
${claims.toPromptText()}

请按系统提示逐项检查，只输出 JSON。''';
  }

  /// 验证员 prompt：独立重解 + 差异复核 + 严格四态 + 严格 JSON 输出。
  ///
  /// 关键不是“独立答案 = 标准”，而是：
  ///   1) 独立重解只用来**发现差异**；
  ///   2) 对每一个差异再推理一次，判断候选和独立答案哪边成立；
  ///   3) 不能因为“和我不同”就直接 fail；也不能因为“和我相同”就直接 pass。
  /// 有标准答案时走 [AnswerOracle]，根本不调用本 prompt。
  static const String verificationSystemPrompt = '''
你是一名独立、严格的考场检查员。你会收到题目（可能带图）、候选答案卡、以及过程审计抽取的 claim 摘要（仅供参考，不是推理原文）。
工作顺序：
1. 先独立解一遍题目，得到你自己的结论；这个结论只是**对照物**，不是标准答案。
2. 列出候选答案卡与你的结论的每一个差异（分支、区间、端点、小问）。
3. 针对每个差异**重新独立思考一次**：哪边有推导/条件支持？不要因为“与我不同”就判错，也不要因为“与我相同”就判对。
4. 最后判断候选是否覆盖题目全部要求。
判定口径：
- pass：逐项复核后，候选的每个结论都有依据，且覆盖全部小问；
- fail：能明确指出候选某个结论与题目条件矛盾，或漏写/多写；
- unknown：你无法独立复核某个差异——不是通过；
- error：无法读取题目 / 答案卡。
只输出一个 JSON 对象，不要输出任何其它文字：
{"verdict":"pass|fail|unknown|error","independent_answer":"你的独立结论（可空，只作对照）","failure_type":"missing_answer|wrong_branch|incomplete_sub_question|inconsistent_process|unit_or_endpoint|unparsable|other","issues":["一句话一个问题"],"evidence":{"key":"value"},"confidence":0.0}''';

  /// 从模型输出里取出第一个**可解析的** JSON 对象。
  ///
  /// 不能简单地取 first `{` 到 last `}`：verifier 的 independent answer 里可能含
  /// LaTeX 花括号，输出前后也可能有解释文字。这里逐字符扫描，跟踪字符串与转义，
  /// 只尝试括号闭合的候选；任何一个能 `jsonDecode` 成 Map 就返回。
  static Map<String, Object?>? _extractJson(String text) {
    var value = text.trim();
    if (value.isEmpty) {
      return null;
    }
    value = value.replaceAll(RegExp(r'```(?:json)?', caseSensitive: false), '');
    for (var start = value.indexOf('{');
        start >= 0;
        start = value.indexOf('{', start + 1)) {
      var depth = 0;
      var inString = false;
      var escaped = false;
      for (var i = start; i < value.length; i++) {
        final ch = value[i];
        if (inString) {
          if (escaped) {
            escaped = false;
          } else if (ch == r'\\') {
            escaped = true;
          } else if (ch == '"') {
            inString = false;
          }
          continue;
        }
        if (ch == '"') {
          inString = true;
        } else if (ch == '{') {
          depth += 1;
        } else if (ch == '}') {
          depth -= 1;
          if (depth == 0) {
            final candidate = value.substring(start, i + 1);
            try {
              final decoded = jsonDecode(candidate);
              if (decoded is Map) {
                return decoded.cast<String, Object?>();
              }
            } on FormatException {
              // Try the next opening brace.
            }
            break;
          }
        }
      }
    }
    return null;
  }

  static int? _sum(int? a, int? b) {
    if (a == null && b == null) {
      return null;
    }
    return (a ?? 0) + (b ?? 0);
  }
}

/// 基于结构化 rubric 的确定性内容验证。
///
/// 这是 [AnswerOracle] 的一个通用实现：内容/题库治理侧提供“每个小问应出现
/// 哪些结论片段”的 rubric，verifier 对候选答案卡做归一化后的包含检查。
/// 它不调用模型，也不把答案写进 solver prompt；它只在 verifier 侧使用。
///
/// 规则是**保守**的：required 规则缺少任意一条就 fail；forbidden 规则命中任意
/// 一条也 fail。无法规则化的开放题不应使用本类，而应使用独立的模型 verifier
/// 或人工复核。
library;

import '../domain/student_answer_sheet.dart';
import '../domain/verifier.dart';

/// 一条 rubric 要求：归一化后的答案文本必须包含 [anyOf] 中至少一个片段。
class RubricRequirement {
  const RubricRequirement({
    required this.label,
    required this.anyOf,
    this.required = true,
  });

  /// 人类可读的小问标签，例如 `(2) 轨道支`。
  final String label;

  /// 可接受的归一化文本片段；至少命中一个。空列表表示“无法规则化”的
  /// 小问，调用方不应把它作为 required 规则。
  final List<String> anyOf;

  /// false 表示这是 forbidden 之外的软提示，当前实现只处理 required。
  final bool required;
}

/// 把 LaTeX / 全角符号 / 空白压成便于规则匹配的形式。
class AnswerTextNormalizer {
  static String normalize(String raw) {
    var text = raw
        .replaceAll(r'\leq', '<=')
        .replaceAll(r'\le', '<=')
        .replaceAll(r'\geq', '>=')
        .replaceAll(r'\ge', '>=')
        .replaceAll(r'\dfrac', '')
        .replaceAll(r'\frac', '')
        .replaceAll(r'\sin', 'sin')
        .replaceAll(r'\theta', 'theta')
        .replaceAll(r'\left', '')
        .replaceAll(r'\right', '')
        .replaceAll(RegExp(r'\\\(|\\\)|\\\[|\\\]|\\'), '')
        .replaceAll(RegExp(r'[{}$]'), '')
        .replaceAll(RegExp(r'[ _]'), '')
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('≤', '<=')
        .replaceAll('≥', '>=')
        .replaceAll('，', ',')
        .replaceAll('。', '.');
    return text.toLowerCase();
  }
}

/// 用 [RubricRequirement] 做确定性判分的 [AnswerOracle]。
class RubricAnswerOracle implements AnswerOracle {
  RubricAnswerOracle({
    required this.id,
    required this.requirements,
    this.forbidden = const <String>[],
  });

  @override
  final String id;

  final List<RubricRequirement> requirements;

  /// 归一化后不得出现的片段（例如错误的另一支）。
  final List<String> forbidden;

  @override
  Future<Verification> check({
    required String question,
    required StudentAnswerSheet answer,
  }) async {
    final text = AnswerTextNormalizer.normalize(
      '${answer.result}\n${answer.process}',
    );
    final issues = <String>[];

    for (final requirement in requirements) {
      if (!requirement.required) {
        continue;
      }
      if (requirement.anyOf.isEmpty) {
        issues.add('${requirement.label}：rubric 无法规则化');
        continue;
      }
      final hit = requirement.anyOf.any(
        (needle) => text.contains(AnswerTextNormalizer.normalize(needle)),
      );
      if (!hit) {
        issues.add('${requirement.label}：缺少可接受结论');
      }
    }
    for (final needle in forbidden) {
      if (text.contains(AnswerTextNormalizer.normalize(needle))) {
        issues.add('命中禁止结论：$needle');
      }
    }
    if (issues.isEmpty) {
      return Verification.pass();
    }
    return Verification(
      verdict: Verdict.fail,
      failureType: FailureType.wrongBranch,
      issues: issues,
      evidence: {'oracle': id},
      independent: true,
    );
  }
}

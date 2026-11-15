/// 确定性 AnswerGate：只检查 required 锚点与可判断的 conditional 锚点。
///
/// 这是设计 §7.5/§7.6 的 AnswerGate 层，独立于 Checker Agent：
///  * required：任何解法都必须满足；缺失直接 fail；
///  * ifReferenced：答案/过程里出现该锚点标签时才检查；未出现不罚；
///  * ifUsed：缺少结构化“使用”信息，当前不判 fail，返回 unknown；
///  * 无法判断的锚点不冒充 pass。
///
/// 它不读 solver 的原始 CoT；只看结构化答案卡文本。Checker 才看 CoT。
library;

import 'checkpoint.dart';
import 'student_answer_sheet.dart';
import 'verifier.dart';

/// AnswerGate 的结论。
class AnswerGateResult {
  const AnswerGateResult({
    required this.verdict,
    this.issues = const <String>[],
    this.checkedCheckpoints = 0,
    this.skippedCheckpoints = 0,
  });

  final Verdict verdict;
  final List<String> issues;
  final int checkedCheckpoints;
  final int skippedCheckpoints;

  bool get passed => verdict == Verdict.pass;
}

/// 确定性锚点检查器。
class DeterministicAnswerGate {
  DeterministicAnswerGate({
    required this.checkpoints,
    this.id = 'deterministic_answer_gate',
  });

  final CheckpointSet checkpoints;
  final String id;

  AnswerGateResult check(StudentAnswerSheet answer) {
    final text = _normalize('${answer.result}\n${answer.process}');
    final issues = <String>[];
    var checked = 0;
    var skipped = 0;
    var unknown = false;

    for (final checkpoint in checkpoints.checkpoints) {
      final referenced = _referenced(text, checkpoint);
      if (checkpoint.scope == CheckpointScope.ifUsed && !referenced) {
        skipped += 1;
        unknown = true;
        continue;
      }
      if (checkpoint.scope == CheckpointScope.ifReferenced && !referenced) {
        skipped += 1;
        continue;
      }
      if (!checkpoint.constraints.any((c) => c.isCheckable)) {
        unknown = true;
        issues.add('${checkpoint.label}：锚点没有可执行约束');
        continue;
      }
      checked += 1;
      final missing = checkpoint.constraints.where((constraint) {
        final needles = [
          ...constraint.acceptable,
          ...constraint.alternatives,
        ].map(_normalize).where((s) => s.isNotEmpty);
        return needles.isNotEmpty && !needles.any(text.contains);
      }).toList();
      if (missing.isNotEmpty) {
        issues.add(
          '${checkpoint.label}：缺少必要条件'
          '（${missing.map((m) => m.description.isEmpty ? m.kind.id : m.description).join('；')}）',
        );
      }
    }

    if (issues.isNotEmpty) {
      return AnswerGateResult(
        verdict: Verdict.fail,
        issues: issues,
        checkedCheckpoints: checked,
        skippedCheckpoints: skipped,
      );
    }
    if (unknown) {
      // 有无法判断的锚点，不能冒充 pass。
      return AnswerGateResult(
        verdict: Verdict.unknown,
        checkedCheckpoints: checked,
        skippedCheckpoints: skipped,
      );
    }
    return AnswerGateResult(
      verdict: Verdict.pass,
      checkedCheckpoints: checked,
      skippedCheckpoints: skipped,
    );
  }

  /// 锚点是否在答案文本中被引用。标签/ID 都归一化后做包含判断；这是
  /// AnswerGate 的保守近似，结构化 claim 引用应由 Checker 做。
  static bool _referenced(String text, Checkpoint checkpoint) {
    final id = _normalize(checkpoint.id);
    final label = _normalize(checkpoint.label);
    return (id.isNotEmpty && text.contains(id)) ||
        (label.isNotEmpty && text.contains(label));
  }

  static String _normalize(String raw) => raw
      .replaceAll(r'\leq', '<=')
      .replaceAll(r'\le', '<=')
      .replaceAll(r'\geq', '>=')
      .replaceAll(r'\ge', '>=')
      .replaceAll(r'\dfrac', '')
      .replaceAll(r'\frac', '')
      .replaceAll(r'\sin', 'sin')
      .replaceAll(r'\theta', 'theta')
      .replaceAll(RegExp(r'\\\(|\\\)|\\\[|\\\]|\\'), '')
      .replaceAll(RegExp(r'[{}$]'), '')
      .replaceAll(RegExp(r'[ _/]'), '')
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('≤', '<=')
      .replaceAll('≥', '>=')
      .toLowerCase();
}

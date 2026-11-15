/// 把确定性 [DeterministicAnswerGate] 适配成学生内容验证器。
///
/// 这样 AnswerGate 可以沿现有 `StudentRun` 的 verifier 插槽接入，而不需要改
/// 状态机：required 锚点缺失 -> fail；无法判断 -> unknown；不会静默 pass。
///
/// 它只看答案卡，不读 CoT；CoT 过程由 ProcessAuditor / Checker 负责。
library;

import '../domain/answer_gate.dart';
import '../domain/claim.dart';
import '../domain/model_adapter.dart';
import '../domain/student_answer_sheet.dart';
import '../domain/verifier.dart';

class AnswerGateVerifier implements Verifier {
  AnswerGateVerifier(this._gate);

  final DeterministicAnswerGate _gate;

  @override
  String get id => _gate.id;

  @override
  VerifierKind get kind => VerifierKind.content;

  @override
  Future<Verification> verify({
    required String question,
    required StudentAnswerSheet answer,
    List<ChatImagePart> images = const [],
    required ClaimSummary claims,
  }) async {
    final result = _gate.check(answer);
    return Verification(
      verdict: result.verdict,
      failureType:
          result.verdict == Verdict.fail ? FailureType.wrongBranch : null,
      issues: result.issues,
      evidence: {
        'oracle': _gate.id,
        'checked_checkpoints': result.checkedCheckpoints,
        'skipped_checkpoints': result.skippedCheckpoints,
      },
      independent: true,
    );
  }
}

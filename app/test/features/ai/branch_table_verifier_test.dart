import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/branch_table_verifier.dart';
import 'package:furnace/features/ai/domain/claim.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart';
import 'package:furnace/features/ai/domain/student_answer_sheet.dart';
import 'package:furnace/features/ai/domain/verifier.dart';

class _PassVerifier implements Verifier {
  @override
  String get id => 'fake_pass';
  @override
  VerifierKind get kind => VerifierKind.content;
  @override
  Future<Verification> verify({
    required String question,
    required StudentAnswerSheet answer,
    List<ChatImagePart> images = const [],
    required ClaimSummary claims,
  }) async =>
      Verification.pass();
}

void main() {
  final verifier = BranchTableVerifier(base: _PassVerifier());

  test('choice/fill-in bypass the branch-table requirement', () async {
    final choice = StudentAnswerSheet(
      kind: StudentQuestionKind.choice,
      raw: '【题型】选择题\n【答案】D',
      result: 'D',
      choice: 'D',
      structured: true,
    );
    final result = await verifier.verify(
      question: 'q',
      answer: choice,
      claims: ClaimSummary.empty(),
    );
    expect(result.verdict, Verdict.pass);
  });

  test('solution without branch table fails with repairable type', () async {
    final answer = StudentAnswerSheet(
      kind: StudentQuestionKind.solution,
      raw: '【题型】解答题\n【答案】a\n【过程】直接算',
      result: 'a',
      process: '直接算',
      structured: true,
    );
    final result = await verifier.verify(
      question: 'q',
      answer: answer,
      claims: ClaimSummary.empty(),
    );
    expect(result.verdict, Verdict.fail);
    expect(result.failureType, FailureType.incompleteSubQuestion);
    expect(result.evidence['source'], 'branch_table_verifier');
  });

  test('solution with branch table passes', () async {
    final answer = StudentAnswerSheet(
      kind: StudentQuestionKind.solution,
      raw: '【题型】解答题\n【答案】a\n【过程】【分支表】A/B',
      result: 'a',
      process: '【分支表】A/B',
      structured: true,
    );
    final result = await verifier.verify(
      question: 'q',
      answer: answer,
      claims: ClaimSummary.empty(),
    );
    expect(result.verdict, Verdict.pass);
  });
}

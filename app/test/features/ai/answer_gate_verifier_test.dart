import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/answer_gate.dart';
import 'package:furnace/features/ai/domain/checkpoint.dart';
import 'package:furnace/features/ai/domain/claim.dart';
import 'package:furnace/features/ai/domain/student_answer_sheet.dart';
import 'package:furnace/features/ai/domain/verifier.dart';
import 'package:furnace/features/ai/infrastructure/answer_gate_verifier.dart';

void main() {
  final gate = DeterministicAnswerGate(
    id: 'q15_checkpoints',
    checkpoints: const CheckpointSet(checkpoints: [
      Checkpoint(
        id: 'mass',
        label: '质量比',
        kind: CheckpointKind.relation,
        scope: CheckpointScope.required,
        constraints: [
          CheckpointConstraint(
            kind: CheckpointConstraintKind.symbolic,
            acceptable: ['m2m1<=1'],
            description: '轨道支',
          ),
          CheckpointConstraint(
            kind: CheckpointConstraintKind.symbolic,
            acceptable: ['m2m1=7'],
            description: '抛体支',
          ),
        ],
      ),
    ]),
  );

  StudentAnswerSheet sheet(String text) => StudentAnswerSheet(
        kind: StudentQuestionKind.solution,
        raw: text,
        result: text,
        process: text,
        structured: true,
      );

  test('adapter passes a satisfied required checkpoint', () async {
    final verifier = AnswerGateVerifier(gate);
    final result = await verifier.verify(
      question: 'q15',
      answer: sheet(r'm_2/m_1\le1 或 m_2/m_1=7'),
      claims: const ClaimSummary.empty(),
    );
    expect(result.verdict, Verdict.pass, reason: '${result.issues}');
    expect(result.independent, isTrue);
  });

  test('adapter fails and reports missing branch', () async {
    final verifier = AnswerGateVerifier(gate);
    final result = await verifier.verify(
      question: 'q15',
      answer: sheet(r'm_2/m_1=7'),
      claims: const ClaimSummary.empty(),
    );
    expect(result.verdict, Verdict.fail);
    expect(result.issues.join(), contains('轨道支'));
  });
}

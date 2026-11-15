import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/answer_gate.dart';
import 'package:furnace/features/ai/domain/checkpoint.dart';
import 'package:furnace/features/ai/domain/student_answer_sheet.dart';
import 'package:furnace/features/ai/domain/verifier.dart';

void main() {
  Checkpoint required(String id, String label, List<String> acceptable) =>
      Checkpoint(
        id: id,
        label: label,
        kind: CheckpointKind.relation,
        scope: CheckpointScope.required,
        constraints: [
          CheckpointConstraint(
            kind: CheckpointConstraintKind.symbolic,
            acceptable: acceptable,
            description: label,
          ),
        ],
      );

  StudentAnswerSheet sheet(String text) => StudentAnswerSheet(
        kind: StudentQuestionKind.solution,
        raw: text,
        result: text,
        process: text,
        structured: true,
      );

  test('required anchors: both branches and interval pass', () {
    final gate = DeterministicAnswerGate(
      checkpoints: CheckpointSet(checkpoints: [
        required('mass-track', '轨道支', ['m2m1<=1']),
        required('mass-seven', '抛体支', ['m2m1=7']),
        required('energy', '能量区间', ['172', '12']),
        required('domain', '定义域', ['m2m1>0']),
      ]),
    );
    final result = gate.check(
      sheet(r'质量比 m_2/m_1\le1 或 m_2/m_1=7；17/2 \le E \le12；m_2/m_1>0'),
    );
    expect(result.verdict, Verdict.pass, reason: '${result.issues}');
  });

  test('required anchor missing -> fail, not pass', () {
    final gate = DeterministicAnswerGate(
      checkpoints: CheckpointSet(checkpoints: [
        required('mass-track', '轨道支', ['m2m1<=1']),
      ]),
    );
    final result = gate.check(sheet(r'质量比 m_2/m_1=7'));
    expect(result.verdict, Verdict.fail);
    expect(result.issues, isNotEmpty);
  });

  test('ifReferenced anchor is skipped when absent', () {
    final gate = DeterministicAnswerGate(
      checkpoints: CheckpointSet(checkpoints: [
        const Checkpoint(
          id: 'vc',
          label: '临界速度',
          kind: CheckpointKind.quantity,
          scope: CheckpointScope.ifReferenced,
          constraints: [
            CheckpointConstraint(
              kind: CheckpointConstraintKind.symbolic,
              acceptable: ['vc2=gr'],
            ),
          ],
        ),
      ]),
    );
    final skipped = gate.check(sheet('最终能量为 12'));
    expect(skipped.verdict, Verdict.pass);
    expect(skipped.skippedCheckpoints, 1);

    final referenced = gate.check(sheet('临界速度 vc2=gr 成立'));
    expect(referenced.verdict, Verdict.pass);
  });

  test('ifUsed without structured usage -> unknown, not fake pass', () {
    final gate = DeterministicAnswerGate(
      checkpoints: CheckpointSet(checkpoints: [
        const Checkpoint(
          id: 'vc',
          label: '临界速度',
          kind: CheckpointKind.quantity,
          scope: CheckpointScope.ifUsed,
          constraints: [
            CheckpointConstraint(
              kind: CheckpointConstraintKind.symbolic,
              acceptable: ['vc2=gr'],
            ),
          ],
        ),
      ]),
    );
    final result = gate.check(sheet('答案 12'));
    expect(result.verdict, Verdict.unknown);
  });
}

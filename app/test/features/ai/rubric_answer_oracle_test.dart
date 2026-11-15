import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/student_answer_sheet.dart';
import 'package:furnace/features/ai/domain/verifier.dart';
import 'package:furnace/features/ai/infrastructure/rubric_answer_oracle.dart';

void main() {
  final oracle = RubricAnswerOracle(
    id: 'q15_teacher_rubric',
    requirements: const [
      RubricRequirement(label: '(1)', anyOf: ['gsin', 'g sin']),
      RubricRequirement(
        label: '(2) 轨道支',
        anyOf: ['m2m1<=1', 'm2/m1<=1', 'm_2m_1<=1'],
      ),
      RubricRequirement(
        label: '(2) 抛体支',
        anyOf: ['m2m1=7', 'm2/m1=7', 'm_2m_1=7'],
      ),
      RubricRequirement(label: '(3) 下界', anyOf: ['172', '17/2']),
      RubricRequirement(label: '(3) 上界', anyOf: ['12']),
    ],
  );

  StudentAnswerSheet sheet(String result) => StudentAnswerSheet(
        kind: StudentQuestionKind.solution,
        raw: result,
        result: result,
        process: result,
        structured: true,
      );

  test('two branches + interval pass deterministically', () async {
    final result = await oracle.check(
      question: 'q15',
      answer: sheet(
        r'(1) g\sin\theta; (2) m_2/m_1\le1 or m_2/m_1=7; '
        r'(3) 17/2 m_1gR\sin\theta \le E_{k0}\le12m_1gR\sin\theta',
      ),
    );
    expect(result.verdict, Verdict.pass, reason: '${result.issues}');
  });

  test('missing track branch fails without a model call', () async {
    final result = await oracle.check(
      question: 'q15',
      answer: sheet(r'(2) m_2/m_1=7; (3) 17/2 \le E \le12'),
    );
    expect(result.verdict, Verdict.fail);
    expect(result.issues.join(), contains('轨道支'));
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/student_answer_sheet.dart';
import 'package:furnace/features/ai/domain/verifier.dart';

/// Deterministic teacher-confirmed Q15 oracle.
///
/// This is a **test fixture**, not a product answer key and never enters the
/// solver prompt. It exists to prove the `AnswerOracle` path: when a governed
/// rubric is available, the same candidate answer gets the same verdict without
/// another model call.
class Q15TeacherOracle implements AnswerOracle {
  @override
  String get id => 'q15_teacher_confirmed';

  static String _norm(String raw) => raw
      .replaceAll(r'\leq', '<=')
      .replaceAll(r'\le', '<=')
      .replaceAll(r'\geq', '>=')
      .replaceAll(r'\ge', '>=')
      .replaceAll(RegExp(r'\\\(|\\\)|\\\[|\\\]|\\'), '')
      .replaceAll(RegExp(r'[${}]'), '')
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('≤', '<=')
      .replaceAll('≥', '>=');

  @override
  Future<Verification> check({
    required String question,
    required StudentAnswerSheet answer,
  }) async {
    final text = _norm('${answer.result}\n${answer.process}');
    final issues = <String>[];

    if (!text.contains('g sin') && !text.contains('gsin')) {
      issues.add('(1) 缺少 g sinθ');
    }
    final hasTrack = (text.contains('m2/m1<=1') ||
        text.contains('m_2/m_1<=1') ||
        text.contains('m2m1<=1') ||
        text.contains('m_2m_1<=1') ||
        text.contains('m乙/m甲<=1') ||
        text.contains('m乙m甲<=1'));
    final hasSeven = text.contains('m2/m1=7') ||
        text.contains('m_2/m_1=7') ||
        text.contains('m2m1=7') ||
        text.contains('m_2m_1=7') ||
        text.contains('m乙/m甲=7') ||
        text.contains('m乙m甲=7');
    if (!hasTrack) {
      issues.add('(2) 缺少 m2/m1≤1 轨道支');
    }
    if (!hasSeven) {
      issues.add('(2) 缺少 m2/m1=7 抛体支');
    }
    final hasLower = text.contains('172') || text.contains('17/2');
    final hasUpper = text.contains('12');
    if (!hasLower) {
      issues.add('(3) 缺少 17/2 下界');
    }
    if (!hasUpper) {
      issues.add('(3) 缺少 12 上界');
    }
    if (issues.isEmpty) {
      return Verification.pass();
    }
    return Verification(
      verdict: Verdict.fail,
      failureType: FailureType.wrongBranch,
      issues: issues,
      evidence: const {'oracle': 'q15_teacher_confirmed'},
      independent: true,
    );
  }
}

void main() {
  test('deterministic oracle: v3 correct content passes, v5 misses branches',
      () async {
    final v3 = _loadAnswer(
      r'E:\Workspaces\agent-control\10-projects\agent-control-plane\student-mode-v3-q15.json',
    );
    final v5 = _loadAnswer(
      r'E:\Workspaces\agent-control\10-projects\agent-control-plane\student-mode-v5-q15.json',
    );
    final oracle = Q15TeacherOracle();

    final pass = await oracle.check(question: 'q15', answer: v3);
    expect(pass.verdict, Verdict.pass, reason: '${pass.issues}');

    final fail = await oracle.check(question: 'q15', answer: v5);
    expect(fail.verdict, Verdict.fail);
    expect(fail.issues, isNotEmpty);
  });
}

StudentAnswerSheet _loadAnswer(String path) {
  final raw = jsonDecode(File(path).readAsStringSync()) as List;
  final first = raw.first as Map<String, Object?>;
  final sheet = (first['answer_sheet'] as Map).cast<String, Object?>();
  return StudentAnswerSheet(
    kind: StudentQuestionKind.fromId(sheet['kind'] as String?),
    raw: (sheet['raw'] as String?) ?? '',
    result: (sheet['result'] as String?) ?? '',
    process: (sheet['process'] as String?) ?? '',
    structured: sheet['structured'] == true,
  );
}

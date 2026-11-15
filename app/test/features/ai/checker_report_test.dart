import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/checker_report.dart';
import 'package:furnace/features/ai/domain/repair_plan.dart';

void main() {
  const issue = CheckIssue(
    id: 'i1',
    stepId: 's3',
    category: CheckIssueCategory.missingCase,
    severity: CheckSeverity.fatal,
    evidence: '分支表只覆盖 k<=1',
    violated: 'domain k>0 未被覆盖',
    minimalFix: '补 k=7 分支并重推',
  );

  test('blocking issue prevents completion', () {
    final report = CheckReport(
      answerVersion: 'a1',
      cotVersion: 'c1',
      verdict: CheckReportVerdict.processFail,
      issues: const [issue],
    );
    expect(report.passed, isFalse);
    expect(report.hasBlockingIssues, isTrue);
  });

  test('repair plan must cover every blocking issue', () {
    final report = CheckReport(
      answerVersion: 'a1',
      cotVersion: 'c1',
      verdict: CheckReportVerdict.processFail,
      issues: const [issue],
    );
    final missing = RepairPlan(
      answerVersion: 'a1',
      cotVersion: 'c1',
      actions: const [],
    );
    expect(missing.covers(report), isFalse);

    final complete = RepairPlan(
      answerVersion: 'a1',
      cotVersion: 'c1',
      actions: const [
        RepairAction(
          issueId: 'i1',
          firstInvalidStep: 's3',
          replacementSteps: ['s3-new'],
          affectedClaims: ['c-mass'],
          invalidatedDependencies: ['c-energy'],
        ),
      ],
    );
    expect(complete.covers(report), isTrue);
  });
}

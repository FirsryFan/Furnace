/// Checker Agent 的结构化报告与 repair 计划。
///
/// 设计 §7.5/§7.6：Checker 一次性报告全部逻辑问题；solver 只按 issue 做局部
/// 重推。报告不是自然语言“再检查一下”，而是可逐条关闭的结构化对象。
library;

/// Checker 发现的问题类别。
enum CheckIssueCategory {
  missingCase('missing_case'),
  unjustifiedStep('unjustified_step'),
  invalidAlgebra('invalid_algebra'),
  unit('unit'),
  conditionUnused('condition_unused'),
  contradiction('contradiction'),
  circular('circular'),
  undefinedSymbol('undefined_symbol'),
  branchOverlap('branch_overlap'),
  endpoint('endpoint'),
  other('other');

  const CheckIssueCategory(this.id);
  final String id;
}

enum CheckSeverity {
  fatal('fatal'),
  major('major'),
  minor('minor');

  const CheckSeverity(this.id);
  final String id;
}

/// 一条可关闭的检查问题。
class CheckIssue {
  const CheckIssue({
    required this.id,
    required this.stepId,
    required this.category,
    required this.severity,
    required this.evidence,
    required this.violated,
    required this.minimalFix,
    this.affectedClaims = const <String>[],
  });

  final String id;
  final String stepId;
  final CheckIssueCategory category;
  final CheckSeverity severity;

  /// 具体引用：哪一步、哪条条件、哪段证据。
  final String evidence;

  /// 违反的规则/条件。
  final String violated;

  /// 最小修复要求；不能是“再检查一下”。
  final String minimalFix;

  final List<String> affectedClaims;

  bool get blocksCompletion =>
      severity == CheckSeverity.fatal || severity == CheckSeverity.major;
}

enum CheckReportVerdict {
  processPass('process_pass'),
  processFail('process_fail'),
  uncheckable('uncheckable');

  const CheckReportVerdict(this.id);
  final String id;
}

/// 一次 Checker 审查的完整报告。
class CheckReport {
  const CheckReport({
    required this.answerVersion,
    required this.cotVersion,
    required this.verdict,
    this.issues = const <CheckIssue>[],
  });

  final String answerVersion;
  final String cotVersion;
  final CheckReportVerdict verdict;
  final List<CheckIssue> issues;

  bool get hasBlockingIssues => issues.any((issue) => issue.blocksCompletion);

  bool get passed =>
      verdict == CheckReportVerdict.processPass && !hasBlockingIssues;

  Map<String, Object?> toJson() => {
        'answer_version': answerVersion,
        'cot_version': cotVersion,
        'verdict': verdict.id,
        'issues': [
          for (final issue in issues)
            {
              'id': issue.id,
              'step_id': issue.stepId,
              'category': issue.category.id,
              'severity': issue.severity.id,
              'evidence': issue.evidence,
              'violated': issue.violated,
              'minimal_fix': issue.minimalFix,
              'affected_claims': issue.affectedClaims,
            },
        ],
      };
}

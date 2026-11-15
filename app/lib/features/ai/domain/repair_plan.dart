/// Checker 报告 → solver 局部修复计划。
///
/// 设计 §7.5：repair 不得改已通过的最终答案；从最早失效步骤开始，失效下游，
/// 一次覆盖所有 blocking issue。
library;

import 'checker_report.dart';

/// 一条修复动作。
class RepairAction {
  const RepairAction({
    required this.issueId,
    required this.firstInvalidStep,
    required this.replacementSteps,
    this.affectedClaims = const <String>[],
    this.invalidatedDependencies = const <String>[],
  });

  final String issueId;
  final String firstInvalidStep;
  final List<String> replacementSteps;
  final List<String> affectedClaims;
  final List<String> invalidatedDependencies;
}

/// 一次 repair 的计划。
class RepairPlan {
  const RepairPlan({
    required this.answerVersion,
    required this.cotVersion,
    required this.actions,
  });

  final String answerVersion;
  final String cotVersion;
  final List<RepairAction> actions;

  /// 每个 blocking issue 必须有一条对应动作，不能只修一个。
  bool covers(CheckReport report) {
    final covered = actions.map((action) => action.issueId).toSet();
    return report.issues
        .where((issue) => issue.blocksCompletion)
        .every((issue) => covered.contains(issue.id));
  }
}

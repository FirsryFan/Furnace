/// 组卷质量评价在**应用层**的装配：卷子 + 题库原始候选 + 知识点名 → `PaperQualityReport`。
///
/// 领域分工：17 条判据全在 `domain/services/paper/paper_quality_report.dart`（纯逻辑，
/// 不碰 drift / Riverpod），这里只负责补两样 Plan 里没有的东西：
///
/// * **逐题难度**：`PaperPlan` / `PaperItem` 不保留难度（难度只在组卷打分时被消费），
///   而质量报告的难度分布/过平/偏离目标都需要逐题读数——从 `paperCandidatesProvider`
///   （题库原始候选，`PaperCandidate.difficulty`）回填，不重新读库；
/// * **展示名**：学科用 `CapabilityAction.subjectLabelsZh`（与收题页/组卷页同一份），
///   知识点名走 `paperKnowledgePointLabelsProvider`。
///
/// 不传/缺少难度不会让报告变成假数据：报告会出 `difficulty_data_unavailable` /
/// `difficulty_data_partial` 的 info，而不是把没读数当 0。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/paper/paper_quality_report.dart';
import '../../../domain/services/reasoning/capability_action.dart';
import 'paper_plan_provider.dart';

/// 题库里**有难度读数**的题：questionId → 1..10 的数值。
///
/// 只收有限值：NaN / ±inf 是坏数据，交给报告按「没有读数」处理，
/// 不能拿它参与均值或分桶。
final paperQualityDifficultiesProvider =
    FutureProvider.autoDispose<Map<String, double>>((ref) async {
  final candidates = await ref.watch(paperCandidatesProvider.future);
  final difficulties = <String, double>{};
  for (final candidate in candidates) {
    final difficulty = candidate.difficulty;
    if (difficulty == null || !difficulty.isFinite) continue;
    difficulties[candidate.questionId] = difficulty;
  }
  return Map<String, double>.unmodifiable(difficulties);
});

/// 当前卷子的质量报告（跟着组卷要求与题库一起变）。
///
/// 空卷也会产出报告（只有 `empty_plan` 一条 error），页面不需要先判空。
final paperQualityReportProvider =
    FutureProvider.autoDispose<PaperQualityReport>((ref) async {
  final plan = await ref.watch(paperPlanProvider.future);
  final knowledgePointNames =
      await ref.watch(paperKnowledgePointLabelsProvider.future);
  final difficulties = await ref.watch(paperQualityDifficultiesProvider.future);
  final spec = ref.watch(paperSpecProvider);
  return PaperQualityReport.build(
    plan: plan,
    subjectNames: CapabilityAction.subjectLabelsZh,
    knowledgePointNames: knowledgePointNames,
    difficultyByQuestionId: difficulties,
    targetDifficulty: spec.targetDifficulty,
  );
});

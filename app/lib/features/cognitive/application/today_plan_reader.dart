/// 今日清单的读法：把「今天到期的卡」读出来，交给纯逻辑的 `TodayPlanner`。
///
/// 页面与别的入口共用这一份读法，理由和 `library_diagnosis_reader.dart` 一样：
/// 读表只有一处，页面不自己筛卡、不自己算价格（一个数字一个来源）。这一层
/// **不做判定**：到期与否由 `getDueCardStates` 说了算，价格与次序由
/// `TodayPlanner` 说了算。
///
/// 这一页只做**复习侧**。候选题的价格来自 `ProblemEvaluator` 的反事实字段，
/// 而候选题目录目前只有模型调用（`plan_today` / `evaluate_problem_fit`）才会
/// 给，所以这里传一份空报告 —— 空报告的意思是「这次没有题目」，不是「题目
/// 没有价格」。等 UI 有了自己的候选题目录，换掉 [kNoProblemCandidates] 即可。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/repositories/anki_repository.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/cognitive/cognitive_model.dart';
import '../../../domain/services/cognitive/problem_evaluator.dart';
import '../../../domain/services/scheduling/today_plan.dart';

/// 这一次没有候选题：不是「题目没有价格」，而是压根没有题目。
const ProblemEvaluationReport kNoProblemCandidates = ProblemEvaluationReport(
  evaluations: <ProblemEvaluation>[],
  fastLayerRan: false,
  nodesWithoutMs: <String>[],
);

/// 读一份今天要照做的清单（复习侧）。
///
/// [moment] 是调用方的时钟：到期判断与 `nowHours` 用同一个瞬间，否则同一张卡
/// 可能在「到期」与「现在几点」之间被算到两个不同的时刻。
Future<TodayPlan> readTodayPlan({
  required AnkiRepository ankiRepository,
  required DateTime moment,
  int maxActions = TodayPlanner.kTodayPlanDefaultMaxActions,
  double horizonHours = TodayPlanner.kTodayPlanDefaultHorizonHours,
}) async {
  final cards =
      await ankiRepository.getDueCardStates(moment.millisecondsSinceEpoch);
  final points = await ankiRepository.getKnowledgePoints();
  return TodayPlanner.build(
    cards: cards,
    problems: kNoProblemCandidates,
    nowHours: modelHoursOf(moment),
    knowledgePointNames: {for (final point in points) point.id: point.title},
    maxActions: maxActions,
    horizonHours: horizonHours,
  );
}

/// 今天的清单。
///
/// 数据库一有写入就重算：答完一张卡，它的 `dueAt` / `lastReviewedAt` 变了，
/// 这一页接着就该少一件事（或换成另一件）—— 与复习页看的是同一个
/// `dataRevision`，所以两页不会各说各话。
final todayPlanProvider = FutureProvider<TodayPlan>((ref) {
  ref.watchDatabaseRevision();
  return readTodayPlan(
    ankiRepository: ref.watch(ankiRepositoryProvider),
    moment: DateTime.now(),
  );
});

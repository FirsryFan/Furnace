/// 配题推荐的**读表与 provider 层**（application 层，不碰界面、不调模型）。
///
/// 打分 / 理由 / 排序全在 `domain/services/reasoning/practice_recommendation.dart`
/// （纯逻辑，不碰 drift）；这里只负责把题库行拼成
/// `PracticeQuestionCandidate`，再把洞察（`ChainInsights`）与学习建议
/// （`LearningAdvicePlan`）喂给 `PracticeRecommendationPlan.build`。
///
/// 全量读取：推荐要从整个题库里挑，`QuestionRepository.all()` 默认只回 200 条，
/// 用它会漏掉老题。题库是本地 SQLite、行数万级以内，一次读完可接受。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/database/app_database_provider.dart';
import '../../../data/database/database.dart';
import '../../../domain/services/reasoning/practice_recommendation.dart';
import '../../../domain/services/scheduling/thread_balance_inputs.dart';
import 'chain_insights_reader.dart';
import 'learning_advice_provider.dart';
import 'question_corpus_reader.dart';

/// 读一次全库，拼出配题推荐的候选投影。
///
/// 顺序按题目 id 稳定排序 —— 推荐排序只取决于内容与 `build` 的确定性比较，
/// 不取决于读表顺序（同分时保留先出现者，稳定顺序让结果可复现）。
Future<List<PracticeQuestionCandidate>> readPracticeQuestionCandidates(
  AppDatabase db,
) async {
  final questionRows = await db.select(db.questions).get();
  final linkRows = await db.select(db.objectTags).get();
  final actionsByQuestion = await readChainActionTypes(db);

  // 题目 → 覆盖知识点：同一标签既挂题目、又挂知识点 → 这道题覆盖那个知识点。
  // 规则只写在这一处（`TaskKnowledgePointResolver`），组卷 / 相似题 / 体检 / 推荐共用。
  final pointsByQuestion = TaskKnowledgePointResolver.resolveFromTagLinks(
    <ObjectTagLink>[
      for (final row in linkRows)
        ObjectTagLink(
          tagId: row.tagId,
          objectType: row.objectType,
          objectId: row.objectId,
        ),
    ],
    sourceObjectType: kQuestionObjectType,
  );

  final sortedQuestions = <Question>[...questionRows]
    ..sort((a, b) => a.id.compareTo(b.id));

  return <PracticeQuestionCandidate>[
    for (final row in sortedQuestions)
      PracticeQuestionCandidate(
        questionId: row.id,
        serialNo: row.serialNo,
        subjectKey: _nonEmpty(row.subjectKey),
        sourceLevel: _nonEmpty(row.sourceLevel),
        difficulty: _finiteOrNull(row.difficulty),
        aiQuality: _finiteOrNull(row.aiQuality),
        knowledgePointIds: List<String>.unmodifiable(
          pointsByQuestion[row.id] ?? const <String>[],
        ),
        actionTypes: List<String>.unmodifiable(
          actionsByQuestion[row.id] ?? const <String>[],
        ),
        hasAnswer: _hasText(row.answer),
        hasSolution: _hasText(row.solution),
      ),
  ];
}

/// 候选题目投影；跟数据库修订号走，刚收的题 / 刚拆的链立即算进来。
final practiceCandidatesProvider =
    FutureProvider.autoDispose<List<PracticeQuestionCandidate>>((ref) async {
  ref.watchDatabaseRevision();
  return readPracticeQuestionCandidates(ref.watch(appDatabaseProvider));
});

/// 全库配题推荐：洞察 + 学习建议 + 候选投影 → `PracticeRecommendationPlan`。
///
/// 目标难度暂不传（null = 不按难度贴目标打分）；最多 10 道、未知动作补习默认开。
/// 词表 / 题库读取失败沿用上游 provider 的退化口径，不在这里重建。
final practiceRecommendationProvider =
    FutureProvider.autoDispose<PracticeRecommendationPlan>((ref) async {
  final insights = await ref.watch(chainInsightsProvider.future);
  final advice = await ref.watch(learningAdviceProvider.future);
  final candidates = await ref.watch(practiceCandidatesProvider.future);
  return PracticeRecommendationPlan.build(
    insights: insights,
    advicePlan: advice,
    candidates: candidates,
  );
});

String? _nonEmpty(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

double? _finiteOrNull(double? value) {
  if (value == null || !value.isFinite) return null;
  return value;
}

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

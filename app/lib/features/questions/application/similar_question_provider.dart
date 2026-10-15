/// 找相似题（Q12）在**应用层**的输入读取：题库 + 挂载关系 + 库里已有的思维链
/// → `SimilarQuestionFinder.rank`。
///
/// 领域分工：
///
/// * 相似度、排序、理由全在 `domain/services/paper/similar_questions.dart`
///   （Q12，纯逻辑、可离线测）；这个文件只做"读表 + 拼装"，是找题前唯一的 IO 点。
/// * 题目的覆盖知识点复用 `paperCandidatesProvider`（Q11 已建，题干为空的题不进题库）。
///   挂载关系一律走 `TaskKnowledgePointResolver.resolveFromTagLinks(..., sourceObjectType:
///   kQuestionObjectType)`，不在这里重写规则。
/// * 思维链只读**库里已有的**：一道题的最新一条链（`reasoning_chains` 按
///   `createdAt` 最新，平手比 id）的步骤 `idx` 升序，取 `actionType` 序列。
///   AI 解题跑过一次就落库（`questionReasoningServiceProvider` 默认 `save: true`），
///   所以"找相似题"的跨学科能力对齐用的是真实解过的题，不是猜的。
///   库里没有链 = 序列为空（不冒充有信号）。
///
/// 阈值 / 权重 / 上限都留在领域层（`kMinSimilarityScore` 等），这一层不重复设参。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/database/app_database_provider.dart';
import '../../../domain/services/paper/similar_questions.dart';
import 'paper_plan_provider.dart';

/// 一道题的最新一条链的步骤动作序列（`idx` 升序），键是题目 id。
///
/// 读表主体在 `question_corpus_reader.dart` 的 `readChainActionTypes`（AI 工具层
/// 用同一份，避免两处"题目 → 动作序列"的推导分叉）；这里只加数据版本。
final chainActionTypesProvider =
    FutureProvider.autoDispose<Map<String, List<String>>>((ref) async {
  ref.watchDatabaseRevision();
  return readChainActionTypes(ref.watch(appDatabaseProvider));
});

/// 题库里的全部题目，带上各自的覆盖知识点与已有思维链动作序列。
final similarCandidatesProvider =
    FutureProvider.autoDispose<List<SimilarityCandidate>>((ref) async {
  final candidates = await ref.watch(paperCandidatesProvider.future);
  final actionTypes = await ref.watch(chainActionTypesProvider.future);

  return [
    for (final candidate in candidates)
      SimilarityCandidate(
        questionId: candidate.questionId,
        knowledgePointIds: candidate.matchedKnowledgePointIds,
        subjectKey: candidate.subjectKey,
        questionType: candidate.questionType,
        sourceLevel: candidate.sourceLevel,
        difficulty: candidate.difficulty,
        actionTypes: actionTypes[candidate.questionId] ?? const <String>[],
      ),
  ];
});

/// 一道题的相似度基准（它自己的知识点、学科、难度、思维链动作）。
///
/// 题不在题库快照里（题干为空，或刚被删）时回落到直接读题目行：知识点与动作可能
/// 为空，但至少能按学科/来源给出候选，而不是整页空白。
final similarQuestionFocusProvider =
    FutureProvider.autoDispose.family<SimilarityFocus?, String>(
  (ref, questionId) async {
    final id = questionId.trim();
    if (id.isEmpty) return null;

    final candidates = await ref.watch(similarCandidatesProvider.future);
    for (final candidate in candidates) {
      if (candidate.questionId == id) {
        return SimilarityFocus(
          questionId: candidate.questionId,
          knowledgePointIds: candidate.knowledgePointIds,
          subjectKey: candidate.subjectKey,
          questionType: candidate.questionType,
          difficulty: candidate.difficulty,
          actionTypes: candidate.actionTypes,
        );
      }
    }

    final database = ref.watch(appDatabaseProvider);
    final row = await (database.select(database.questions)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;

    final actions = await ref.watch(chainActionTypesProvider.future);
    return SimilarityFocus(
      questionId: row.id,
      subjectKey: row.subjectKey,
      questionType: row.questionType,
      difficulty: row.difficulty,
      actionTypes: actions[row.id] ?? const <String>[],
    );
  },
);

/// 给一道题找库里的相似题（默认上限 10 条，阈值见领域层 `kMinSimilarityScore`）。
///
/// **一道都不相似时返回空列表**：这里不出题、不凑数——真没有就如实说"库里还没有
/// 相似的题"，提示去收题（`PaperComposer` 那边同理只报缺口）。
final similarQuestionsProvider =
    FutureProvider.autoDispose.family<List<SimilarQuestion>, String>(
  (ref, questionId) async {
    final focus =
        await ref.watch(similarQuestionFocusProvider(questionId).future);
    if (focus == null) return const [];

    final candidates = await ref.watch(similarCandidatesProvider.future);
    final names = await ref.watch(paperKnowledgePointLabelsProvider.future);

    return SimilarQuestionFinder.rank(
      focus: focus,
      candidates: candidates,
      knowledgePointNames: names,
    );
  },
);

/// 来源中文名**不在这里**：`question_vocab_labels.dart` 的 `sourceLevelLabel(l10n, …)`
/// 已经是全 app 唯一一份（收题页 / 详情页 / 组卷页都用它），再写一份就会分叉。
/// 来源权重口径同样只留在领域层（`kSourceLevelPriority`），这里不做透传。

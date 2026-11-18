/// Release-safe 组卷回退：不调用在 Windows AOT 下会原生崩溃的
/// `PaperComposer.compose`，只按题库顺序/题组取题，保证组卷页可用。
///
/// 这是一个**明确降级**：没有认知读数、没有分数解释；页面上仍可看卷面、
/// 复制/打印。根因修好后应删除本文件，回到 `PaperComposer`。
library;

import '../../../domain/services/paper/paper_composer.dart';

PaperPlan buildFallbackPaperPlan({
  required List<PaperCandidate> candidates,
  required PaperSpec spec,
}) {
  final subjectFilter = spec.subjectKeys;
  final picked = <PaperCandidate>[];
  for (final candidate in candidates) {
    if (subjectFilter.isNotEmpty &&
        !subjectFilter.contains(candidate.subjectKey)) {
      continue;
    }
    if (picked.length >= spec.targetCount) break;
    picked.add(candidate);
  }

  final items = <PaperItem>[
    for (var i = 0; i < picked.length; i++)
      PaperItem(
        questionId: picked[i].questionId,
        subjectKey: picked[i].subjectKey,
        sourceLevel: picked[i].sourceLevel,
        questionType: picked[i].questionType,
        knowledgePointId: null,
        matchedKnowledgePointIds: const <String>[],
        zone: PaperZone.unknown,
        need: kUnknownNeed,
        quality: 0.5,
        score: 0.5,
        reasonZh: '简版组卷：按题库顺序选取（认知读数未接入）',
        improvementNote: '先完成这道题；做完后按错因补缺。',
        backgroundZh: '未标注知识点',
        groupQuestionIds: picked[i].groupQuestionIds,
      ),
  ];

  return PaperPlan(
    items: items,
    uncoveredKnowledgePointIds: const <String>[],
    deferredKnowledgePointIds: const <String>[],
    byKnowledgePoint: const <String, int>{},
    candidateCount: picked.length,
    requestedCount: spec.targetCount,
    overallNeed: 0,
    weights: const PaperWeights(),
  );
}

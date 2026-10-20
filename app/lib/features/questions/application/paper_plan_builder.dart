/// 组卷的"装配"只有这一处：题库 + 挂载 + 诊断结论 + 能力动作画像 → `PaperPlan`。
///
/// 领域分工没变：排序/打分在 `domain/services/paper/paper_composer.dart`，读表在
/// `question_corpus_reader.dart`。这里补的是"读表之后、compose 之前"的那段拼装，
/// 因为**页面和 AI 工具必须给出同一份卷子**（D2：一个数字一个来源）：
///
/// * 页面（`paper_plan_provider.dart`）：题库/诊断/画像都来自已经缓存并联动数据
///   版本的 provider；
/// * 工具（`features/ai/tools/paper_tools.dart`）：工具没有 `Ref`，自己
///   `readPaperCorpus` + `readLibraryDiagnosis(model: 默认模型)` + 推理链样本。
///
/// 两边注入的 IO 可以不同（页面能换模型，工具只能默认模型，`diagnosis_ran` 会如实
/// 说明），但"怎么把读数、动作序列拼进候选"必须相同 —— 否则同一份库会排出两份卷子。
library;

import '../../../data/database/database.dart';
import '../../../domain/services/cognitive/library_diagnosis.dart';
import '../../../domain/services/paper/paper_composer.dart';
import '../../../domain/services/reasoning/capability_profile.dart';
import 'question_corpus_reader.dart';

/// 一次组卷装配的结果：卷子本身 + 这次实际喂了几条打分读数。
class PaperPlanBuild {
  const PaperPlanBuild({required this.plan, required this.readingsUsed});

  final PaperPlan plan;

  /// 喂给组卷器的读数条数（只有拿到 `danger`/`weak` 结论的知识点才有读数）。
  final int readingsUsed;
}

/// 「我最该练的动作」：画像里平均卡点风险过线的动作，最多 [kPreferredActionLimit] 个。
///
/// 命中只把候选往前排一点、不做过滤（见 `PaperComposer`）；这是一条**未标定**的
/// 先验，所以调用方可以整条关掉（`PaperSpec.preferCapabilityActions` /
/// 工具的 `use_capability_profile`）。
List<String> preferredActionTypesOf(Iterable<CapabilityReading> profile) {
  return <String>[
    for (final reading in profile)
      if (reading.avgStuckRisk != null &&
          reading.avgStuckRisk! >= CapabilityProfile.riskyThreshold)
        reading.actionType,
  ].take(kPreferredActionLimit).toList();
}

/// 按 [spec] 从 [corpus] 里组一份卷子；[preferredActionTypes] 由调用方先决定
/// （空表 = 完全不参考画像，卷子与没有画像时逐字段一致）。
///
/// [detailedNotes] 只改文案（选卷理由 / 改进建议 / 知识点背景与缺口解释句），
/// 不改排序、分数、配额：页面传 true 给用户看可核实依据，AI 工具不传，
/// 避免工具输出无谓变长。
Future<PaperPlanBuild> buildPaperPlan({
  required AppDatabase db,
  required PaperCorpus corpus,
  required PaperSpec spec,
  required LibraryDiagnosis diagnosis,
  required List<String> preferredActionTypes,
  bool detailedNotes = false,
}) async {
  final coveredPointIds = <String>{
    for (final candidate in corpus.candidates)
      ...candidate.matchedKnowledgePointIds,
  };

  // 每道题最新一条链的动作序列：候选带上它，组卷器才能算"命中比例"。
  final chainActions = await readChainActionTypes(db);
  final candidates = <PaperCandidate>[
    for (final candidate in corpus.candidates)
      PaperCandidate(
        questionId: candidate.questionId,
        subjectKey: candidate.subjectKey,
        sourceLevel: candidate.sourceLevel,
        questionType: candidate.questionType,
        difficulty: candidate.difficulty,
        aiQuality: candidate.aiQuality,
        trapNote: candidate.trapNote,
        matchedKnowledgePointIds: candidate.matchedKnowledgePointIds,
        actionTypes: chainActions[candidate.questionId] ?? const <String>[],
      ),
  ];

  final readings = await readPaperReadings(
    db,
    coveredKnowledgePointIds: coveredPointIds,
    diagnosis: diagnosis,
  );

  return PaperPlanBuild(
    readingsUsed: readings.length,
    plan: PaperComposer.compose(
      candidates: candidates,
      spec: spec,
      readings: readings,
      knowledgePointNames: corpus.knowledgePointNames,
      knowledgePointTagPaths: corpus.knowledgePointTagPaths,
      preferredActionTypes: preferredActionTypes,
      // 页面默认要「这套卷为什么这样排」的可核实依据；AI 工具不传，保持短文案。
      detailedNotes: detailedNotes,
    ),
  );
}

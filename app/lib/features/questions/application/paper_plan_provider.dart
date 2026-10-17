/// 组卷（Q9 纯逻辑）在**应用层**的输入读取：题库 + 挂载关系 + 认知读数 → `PaperPlan`。
///
/// 领域分工：
///
/// * 排序与打分全在 `domain/services/paper/paper_composer.dart`（Q9，已提交）；
/// * 读表本身在 `question_corpus_reader.dart`（无 Riverpod 的纯函数）：这里只负责
///   "数据版本 + 拼装"，是组卷前唯一的 IO 点；AI 工具层用同一份读表函数，不重写；
/// * 诊断结论走**认知页自己的 provider**（`cognitiveLibraryDiagnosisProvider`），
///   不在这里重算——页面上说"危险"的知识点，组卷必须也按危险处理，两边共用同一次
///   诊断（D2：一个数字一个来源）。这条跨 feature 的 import 方向是
///   `questions/application → cognitive/presentation`，与 Thread 那边（Q6）同源；
///   观察层的读表 + 跑 runner 已经搬到
///   `cognitive/application/library_diagnosis_reader.dart`（Q13），所以 AI 工具
///   （`compose_paper`）能和页面跑**同一份**诊断，不必各自复制读表逻辑。
///
/// 一个刻意的取舍：**只有拿到诊断结论（`danger` / `weak`）的知识点才进打分读数**。
/// `CognitiveReadingsAdapter` 会为"只有测评先验、没有诊断结论"的点也产出读数，而
/// 组卷器把"不是危险区、也不是发展区"的读数一律映射成 `PaperZone.healthy`
/// （need 0.15，**低于**"未知"的 0.35）——直接喂进去等于把"没测过"当成"学得好"。
/// 所以这里按结论过滤：没有结论的点按未知处理，先验仍作为已诊断点的 R0 补充
/// （`PaperItem.reasonZh` 会带上 `R0=`）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/database/app_database_provider.dart';
import '../../../domain/services/paper/paper_composer.dart';
import '../../../domain/services/reasoning/capability_profile.dart';
import '../../cognitive/presentation/cognitive_model_page.dart'
    show cognitiveLibraryDiagnosisProvider;
import 'capability_profile_provider.dart';
import 'question_corpus_reader.dart';

/// `PaperCorpus` 的公开路径保持在这里：组卷页与找相似题都从这个文件导入它，
/// 类本身搬到了 `question_corpus_reader.dart`（AI 工具层也要用那份读表函数）。
export 'question_corpus_reader.dart'
    show PaperCorpus, readChainActionTypes, readPaperCorpus, readQuestionStems;

/// 读一次题库，拼出组卷需要的两张表（题目 + 知识点名/标签路径）。
final paperCorpusProvider =
    FutureProvider.autoDispose<PaperCorpus>((ref) async {
  ref.watchDatabaseRevision();
  return readPaperCorpus(ref.watch(appDatabaseProvider));
});

/// 题库里的全部题目（`PaperCandidate`）。
final paperCandidatesProvider =
    FutureProvider.autoDispose<List<PaperCandidate>>(
  (ref) async => (await ref.watch(paperCorpusProvider.future)).candidates,
);

/// 知识点 id → 标题。
final paperKnowledgePointLabelsProvider =
    FutureProvider.autoDispose<Map<String, String>>(
  (ref) async =>
      (await ref.watch(paperCorpusProvider.future)).knowledgePointNames,
);

/// 题库里出现过的学科键，供组卷页做筛选项。
final paperSubjectOptionsProvider = FutureProvider.autoDispose<List<String>>(
  (ref) async => (await ref.watch(paperCorpusProvider.future)).subjectKeys,
);

/// 用户手上的组卷要求（默认 10 题、不筛学科、不设难度/来源下限）。
final paperSpecProvider =
    NotifierProvider<PaperSpecNotifier, PaperSpec>(PaperSpecNotifier.new);

/// 组卷要求的可变状态。`PaperSpec` 是纯值对象（无 `copyWith`），所以每次改动都
/// 显式重建：可空字段要能"清空"，光靠 `null` 分不清"没改"和"设成 null"。
class PaperSpecNotifier extends Notifier<PaperSpec> {
  @override
  PaperSpec build() => const PaperSpec(targetCount: 10);

  /// 想要几道题（钳到 1..200：0 题没有意义，200 以上只是误触）。
  void setTargetCount(int count) {
    final safe = count < 1 ? 1 : (count > 200 ? 200 : count);
    _update(targetCount: safe);
  }

  /// 点一下学科 chip：已选则取消，未选则加上。
  void toggleSubject(String subjectKey) {
    final key = subjectKey.trim();
    if (key.isEmpty) return;
    final next = <String>{...state.subjectKeys};
    if (!next.remove(key)) {
      next.add(key);
    }
    _update(subjectKeys: next);
  }

  /// 清空学科筛选（空集 = 不限学科）。
  void clearSubjects() => _update(subjectKeys: const <String>{});

  /// 回到默认要求（10 题、不筛学科、不设难度/来源下限/每点上限）。
  void reset() => state = const PaperSpec(targetCount: 10);

  /// 来源分级下限（`gaokao` / `provincial_diagnostic` / …）；null 或空串 = 不限。
  void setMinSourceLevel(String? level) {
    final trimmed = level?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      _update(clearMinSourceLevel: true);
    } else {
      _update(minSourceLevel: trimmed);
    }
  }

  /// 目标难度（1..10）；null / NaN = 不按难度挑。
  void setTargetDifficulty(double? difficulty) {
    if (difficulty == null || difficulty.isNaN) {
      _update(clearTargetDifficulty: true);
    } else {
      _update(targetDifficulty: difficulty.clamp(1.0, 10.0));
    }
  }

  /// 每个知识点最多出几道；null 或 <1 = 由组卷器按候选分布算。
  void setPerKnowledgePointCap(int? cap) {
    if (cap == null || cap < 1) {
      _update(clearCap: true);
    } else {
      _update(perKnowledgePointCap: cap);
    }
  }

  void _update({
    int? targetCount,
    Set<String>? subjectKeys,
    int? perKnowledgePointCap,
    bool clearCap = false,
    double? targetDifficulty,
    bool clearTargetDifficulty = false,
    String? minSourceLevel,
    bool clearMinSourceLevel = false,
  }) {
    final current = state;
    state = PaperSpec(
      targetCount: targetCount ?? current.targetCount,
      subjectKeys: subjectKeys ?? current.subjectKeys,
      perKnowledgePointCap: clearCap
          ? null
          : (perKnowledgePointCap ?? current.perKnowledgePointCap),
      targetDifficulty: clearTargetDifficulty
          ? null
          : (targetDifficulty ?? current.targetDifficulty),
      minSourceLevel: clearMinSourceLevel
          ? null
          : (minSourceLevel ?? current.minSourceLevel),
    );
  }
}

/// 当前要求下的一份卷子。题库为空时也会给出一个空 `PaperPlan`（`items` 空、
/// `candidateCount` 0），页面据此显示"题库还没有题"而不是报错。
final paperPlanProvider = FutureProvider.autoDispose<PaperPlan>((ref) async {
  ref.watchDatabaseRevision();
  final corpus = await ref.watch(paperCorpusProvider.future);
  final spec = ref.watch(paperSpecProvider);

  final coveredPointIds = <String>{
    for (final candidate in corpus.candidates)
      ...candidate.matchedKnowledgePointIds,
  };
  final diagnosis = await ref.watch(cognitiveLibraryDiagnosisProvider.future);

  // 「我最该练的动作」来自能力动作画像（推理层读数）；没解过链的库这里是空表，
  // 组卷行为与之前完全一致。取"平均风险过线（>= 0.6）"的前几个，顺序就是画像的
  // 排序（最该练的在前）。
  final profile = await ref.watch(capabilityProfileProvider.future);
  final preferredActions = <String>[
    for (final reading in profile)
      if (reading.avgStuckRisk != null &&
          reading.avgStuckRisk! >= CapabilityProfile.riskyThreshold)
        reading.actionType,
  ].take(kPreferredActionLimit).toList();

  // 每道题最新一条链的动作序列：候选带上它，组卷器才能算"命中比例"。
  final chainActions =
      await readChainActionTypes(ref.read(appDatabaseProvider));
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

  return PaperComposer.compose(
    candidates: candidates,
    spec: spec,
    readings: await readPaperReadings(
      ref.read(appDatabaseProvider),
      coveredKnowledgePointIds: coveredPointIds,
      diagnosis: diagnosis,
    ),
    knowledgePointNames: corpus.knowledgePointNames,
    knowledgePointTagPaths: corpus.knowledgePointTagPaths,
    preferredActionTypes: preferredActions,
  );
});

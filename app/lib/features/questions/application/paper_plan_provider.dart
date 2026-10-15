/// 组卷（Q9 纯逻辑）在**应用层**的输入读取：题库 + 挂载关系 + 认知读数 → `PaperPlan`。
///
/// 领域分工：
///
/// * 排序与打分全在 `domain/services/paper/paper_composer.dart`（Q9，已提交）；
/// * 这个文件只做"读表 + 拼装"，是组卷前唯一的 IO 点；
/// * 诊断结论走**认知页自己的 provider**（`cognitiveLibraryDiagnosisProvider`），
///   不在这里重算——页面上说"危险"的知识点，组卷必须也按危险处理，两边共用同一次
///   诊断（D2：一个数字一个来源）。这条跨 feature 的 import 方向是
///   `questions/application → cognitive/presentation`，与 Thread 那边（Q6）同源；
///   观察层将来搬到 `cognitive/application/` 时改一行 import 即可。
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
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/cognitive/fast_diagnosis.dart';
import '../../../domain/services/cognitive/knowledge_point_tag_bridge.dart';
import '../../../domain/services/paper/paper_composer.dart';
import '../../../domain/services/scheduling/cognitive_readings.dart';
import '../../../domain/services/scheduling/domain_balance.dart'
    show KnowledgePointReading;
import '../../../domain/services/scheduling/thread_balance_inputs.dart';
import '../../cognitive/presentation/cognitive_model_page.dart'
    show cognitiveLibraryDiagnosisProvider;

/// 题库 + 知识点名字的一次读取快照：组卷、学科可选项、知识点名共用它，
/// 免得每个 provider 各读一遍表。
class PaperCorpus {
  const PaperCorpus({
    required this.candidates,
    required this.knowledgePointNames,
    required this.knowledgePointTagPaths,
  });

  /// 题干非空的全部题目（`state` 不筛：还没加工的题也能进卷，只是质量分低）。
  final List<PaperCandidate> candidates;

  /// 知识点 id → 标题（`KnowledgePoints.title`），用于理由行说人话。
  final Map<String, String> knowledgePointNames;

  /// 知识点 id → 它直挂的标签路径（`Tags.path`，形如 `文化课/学科/数学`），
  /// 用来给理由行补学科背景；挂载了标签但路径为空的点不会出现在这里。
  final Map<String, List<String>> knowledgePointTagPaths;

  bool get isEmpty => candidates.isEmpty;

  /// 题库里出现过的学科键（去空、去重、排序）。
  List<String> get subjectKeys {
    final keys = <String>{
      for (final candidate in candidates)
        if (candidate.subjectKey.trim().isNotEmpty) candidate.subjectKey.trim(),
    }.toList()
      ..sort();
    return keys;
  }
}

/// 读一次题库，拼出组卷需要的两张表（题目 + 知识点名/标签路径）。
final paperCorpusProvider =
    FutureProvider.autoDispose<PaperCorpus>((ref) async {
  ref.watchDatabaseRevision();
  final db = ref.watch(appDatabaseProvider);

  final questionRows = await db.select(db.questions).get();
  final pointRows = await db.select(db.knowledgePoints).get();
  final tagRows = await db.select(db.tags).get();
  final linkRows = await db.select(db.objectTags).get();

  final objectLinks = <ObjectTagLink>[
    for (final row in linkRows)
      ObjectTagLink(
        tagId: row.tagId,
        objectType: row.objectType,
        objectId: row.objectId,
      ),
  ];
  // 题目自己的覆盖点：同一标签既挂题目、又挂知识点 → 这道题覆盖那个知识点。
  final pointsByQuestion = TaskKnowledgePointResolver.resolveFromTagLinks(
    objectLinks,
    sourceObjectType: kQuestionObjectType,
  );
  // 知识点挂的标签（键空间 Q8：`Tags.id` 是 `tag-…`，知识点 id 是 `kp-…`）。
  final tagIdsByPoint =
      KnowledgePointTagBridge.tagIdsByKnowledgePoint(objectLinks);
  final pathByTagId = <String, String>{
    for (final row in tagRows)
      if ((row.path ?? '').trim().isNotEmpty) row.id: row.path!.trim(),
  };

  return PaperCorpus(
    candidates: <PaperCandidate>[
      for (final row in questionRows)
        if (row.stem.trim().isNotEmpty)
          PaperCandidate(
            questionId: row.id,
            subjectKey: row.subjectKey,
            sourceLevel: row.sourceLevel,
            questionType: row.questionType,
            difficulty: row.difficulty,
            aiQuality: row.aiQuality,
            trapNote: row.trapNote,
            matchedKnowledgePointIds:
                pointsByQuestion[row.id] ?? const <String>[],
          ),
    ],
    knowledgePointNames: <String, String>{
      for (final row in pointRows)
        if (row.title.trim().isNotEmpty) row.id: row.title.trim(),
    },
    knowledgePointTagPaths: <String, List<String>>{
      for (final entry in tagIdsByPoint.entries)
        entry.key: <String>[
          for (final tagId in entry.value)
            if (pathByTagId.containsKey(tagId)) pathByTagId[tagId]!,
        ],
    },
  );
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

  return PaperComposer.compose(
    candidates: corpus.candidates,
    spec: spec,
    readings: await _readingsFor(ref, coveredPointIds),
    knowledgePointNames: corpus.knowledgePointNames,
    knowledgePointTagPaths: corpus.knowledgePointTagPaths,
  );
});

/// 诊断结论 + 先验 → 组卷读数（见文件头那条取舍）。
///
/// 读数覆盖**两类**知识点：题库里有候选的（用来打分），以及诊断出危险/发展区但题库
/// 一道候选都没有的（组卷器要靠它把"该去收题"的点报进
/// `PaperPlan.uncoveredKnowledgePointIds`——如果只喂有候选的点，这个清单永远是空的）。
Future<List<KnowledgePointReading>> _readingsFor(
  Ref ref,
  Set<String> coveredPointIds,
) async {
  final diagnosis = await ref.watch(cognitiveLibraryDiagnosisProvider.future);
  // 快层没跑 = 没有结论 = 全部按未知，"没跑"不是"健康"。
  if (!diagnosis.fastLayerRan) return const <KnowledgePointReading>[];
  final verdicts = diagnosis.byKnowledgePoint;
  final diagnosedIds = <String>{
    for (final entry in verdicts.entries)
      if (_isDiagnosed(entry.value)) entry.key,
  };
  final ids = <String>{...coveredPointIds, ...diagnosedIds};
  if (ids.isEmpty) return const <KnowledgePointReading>[];
  final priors =
      await ref.watch(assessmentRepositoryProvider).priorEstimatesFor(ids);
  return <KnowledgePointReading>[
    for (final reading in CognitiveReadingsAdapter.readingsFor(
      knowledgePointIds: ids,
      diagnosisByKnowledgePoint: verdicts,
      priors: priors,
    ))
      if (_isDiagnosed(verdicts[reading.knowledgePointId])) reading,
  ];
}

bool _isDiagnosed(BottleneckType? verdict) =>
    verdict == BottleneckType.danger || verdict == BottleneckType.weak;

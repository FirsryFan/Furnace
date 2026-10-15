/// 题库的**读表函数**（纯 Dart，不依赖 Riverpod）：组卷 / 找相似题 / AI 工具
/// 三处都要"读一次题库"，读法只写这一遍。
///
/// 为什么要从 provider 里搬出来：provider 只能活在 Riverpod 容器里，而 AI 工具
/// (`features/ai/tools/…`) 拿到的是裸的 `AppDatabase`（`ToolRegistry.forApp`
/// 只有 `db` 和几个仓库，没有 `Ref`）。如果读表逻辑留在 provider 内部，工具要么
/// 自己重写一遍"题目 → 知识点"的推导（两处规则必然分叉），要么为拿一个 `Ref`
/// 改掉工具注册工厂的签名。抽成函数是第三种、也是更小的做法：
/// provider = 数据版本 + 这层函数；工具 = 直接用这层函数。
///
/// 领域分工不变：题目 → 覆盖知识点一律走
/// `TaskKnowledgePointResolver.resolveFromTagLinks(..., sourceObjectType:
/// kQuestionObjectType)`，知识点 → 标签走 `KnowledgePointTagBridge`（键空间 Q8），
/// 阈值/权重/排序全留在 `domain/services/…`。这个文件只做读表与投影。
library;

import '../../../data/database/database.dart';
import '../../../data/repositories/assessment_repository.dart';
import '../../../domain/services/cognitive/fast_diagnosis.dart';
import '../../../domain/services/cognitive/knowledge_point_tag_bridge.dart';
import '../../../domain/services/cognitive/library_diagnosis.dart';
import '../../../domain/services/paper/paper_composer.dart';
import '../../../domain/services/scheduling/cognitive_readings.dart';
import '../../../domain/services/scheduling/domain_balance.dart';
import '../../../domain/services/scheduling/thread_balance_inputs.dart';

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
Future<PaperCorpus> readPaperCorpus(AppDatabase db) async {
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
}

/// 一道题的最新一条链的步骤动作序列（`idx` 升序），键是题目 id。
///
/// 全部题目只读一次：`reasoning_chains` + `reasoning_steps` 各查一遍，
/// 免得为每道题各查一次表。一道题可能有多条链（不同模型/不同次）：只认最新那条，
/// 平手比 id，结果确定。`createdAt` 是 epoch 毫秒（int），不是 DateTime。
Future<Map<String, List<String>>> readChainActionTypes(AppDatabase db) async {
  final chains = await db.select(db.reasoningChains).get();
  final steps = await db.select(db.reasoningSteps).get();

  // 每条链的动作序列（idx 升序）。
  final actionsByChain = <String, List<String>>{};
  final sortedSteps = [...steps]..sort((a, b) {
      final byChain = a.chainId.compareTo(b.chainId);
      return byChain != 0 ? byChain : a.idx.compareTo(b.idx);
    });
  for (final step in sortedSteps) {
    final action = step.actionType.trim();
    if (action.isEmpty) continue;
    (actionsByChain[step.chainId] ??= <String>[]).add(action);
  }

  final latestByQuestion = <String, ({int createdAt, String id})>{};
  for (final chain in chains) {
    final questionId = chain.questionId.trim();
    if (questionId.isEmpty) continue;
    final current = latestByQuestion[questionId];
    final isNewer = current == null ||
        chain.createdAt > current.createdAt ||
        (chain.createdAt == current.createdAt &&
            chain.id.compareTo(current.id) > 0);
    if (isNewer) {
      latestByQuestion[questionId] = (createdAt: chain.createdAt, id: chain.id);
    }
  }

  return {
    for (final entry in latestByQuestion.entries)
      entry.key: List<String>.unmodifiable(
        actionsByChain[entry.value.id] ?? const <String>[],
      ),
  };
}

/// 题目 id → 题干（已 trim，空题干不进结果）。
///
/// `SimilarQuestion` / `SimilarityCandidate` 里**没有题干**（领域层只比信号，不搬
/// 大段文本），所以"要让用户/模型看到是哪道题"的地方都得回表取一次。给 [ids]
/// 时只查这些行（AI 工具一次只返回十来条，不必扫全表）；不给就是全表。
Future<Map<String, String>> readQuestionStems(
  AppDatabase db, {
  Iterable<String>? ids,
}) async {
  final wanted = ids == null
      ? null
      : <String>{
          for (final id in ids)
            if (id.trim().isNotEmpty) id.trim(),
        };
  if (wanted != null && wanted.isEmpty) return const <String, String>{};

  final query = db.select(db.questions);
  if (wanted != null) {
    query.where((t) => t.id.isIn(wanted));
  }
  final rows = await query.get();
  return <String, String>{
    for (final row in rows)
      if (row.stem.trim().isNotEmpty) row.id: row.stem.trim(),
  };
}

/// 诊断结论 + 测评先验 → 组卷读数（Q11 的取舍，搬到这里好让 AI 工具复用）。
///
/// 读数覆盖**两类**知识点：题库里有候选的（用来打分），以及诊断出危险/发展区但题库
/// 一道候选都没有的（组卷器要靠它把"该去收题"的点报进
/// `PaperPlan.uncoveredKnowledgePointIds`——如果只喂有候选的点，这个清单永远是空的）。
///
/// 一个刻意的取舍：**只有拿到诊断结论（`danger` / `weak`）的知识点才进打分读数**。
/// `CognitiveReadingsAdapter` 会为"只有测评先验、没有诊断结论"的点也产出读数，而
/// 组卷器把"不是危险区、也不是发展区"的读数一律映射成 `PaperZone.healthy`
/// （need 0.15，**低于**"未知"的 0.35）——直接喂进去等于把"没测过"当成"学得好"。
/// 所以这里按结论过滤：没有结论的点按未知处理，先验仍作为已诊断点的 R0 补充
/// （`PaperItem.reasonZh` 会带上 `R0=`）。
///
/// [diagnosis] 用 `LibraryDiagnosis`（而不是裸 map）是为了让
/// "快层没跑"（`fastLayerRan == false`）与"跑了、没发现瓶颈"保持可区分：
/// 前者返回空读数（"没跑"不是"健康"），后者才按结论过滤。
Future<List<KnowledgePointReading>> readPaperReadings(
  AppDatabase db, {
  required Set<String> coveredKnowledgePointIds,
  required LibraryDiagnosis diagnosis,
}) async {
  // 快层没跑 = 没有结论 = 全部按未知，"没跑"不是"健康"。
  if (!diagnosis.fastLayerRan) return const <KnowledgePointReading>[];
  final verdicts = diagnosis.byKnowledgePoint;
  final diagnosedIds = <String>{
    for (final entry in verdicts.entries)
      if (_isDiagnosed(entry.value)) entry.key,
  };
  final ids = <String>{...coveredKnowledgePointIds, ...diagnosedIds};
  if (ids.isEmpty) return const <KnowledgePointReading>[];
  final priors = await AssessmentRepository(db).priorEstimatesFor(ids);
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

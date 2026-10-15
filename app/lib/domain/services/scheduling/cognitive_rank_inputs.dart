/// 认知排序的"接线"：把已经读出来的素材编译成 [CognitiveRankInputs]。
///
/// 三种输入分别来自：α(τ)（`features/thread/application/study_rhythm_reader.dart`
/// 的读数）、线程当前目标（`thread_states.goal_node_id`，是标签树上的一个标签 id）、
/// 刚活动过的知识点（`review_logs` / `exposure_logs` → `card_states.knowledge_point_id`）。
/// 这里只做一件事：在标签图上量"候选任务挂着的知识点"离这些起点有多远。
/// **不碰数据库、不看时钟**，所以距离规则可以在测试里用手搭的标签树钉住。
///
/// 三条纪律：
///
/// - 图与边沿用 `DiffusionBoost` 的那张图（无向：父↔子、同父兄弟）。它是"够不够得着"
///   的粗判据，**不是**认知模型的量（D5 / `MINDNET_CONTRACT` §6.5），所以这里算出来的
///   只是排序用的加成，不能当诊断展示。
/// - 知识点没有标签、图上不连通、或超过 [kCognitiveRankMaxHops] 跳：一律**不写 origin**。
///   宁可什么都不说，也不猜一条近路。
/// - 没有起点（既没有目标、也没有刚活动）时返回的 inputs 里一个 origin 都没有，
///   于是 `CognitiveRank.rank` 退化成"按 `baseIndex` 原样返回"——接线没接上时，
///   用户看到的仍是原来的次序。
library;

import '../cloze/diffusion_boost.dart';
import 'cognitive_rank.dart';

/// 一次接线所需的全部素材。
///
/// 全部字段都是"读好的事实"：没有一个是这里推断出来的。`tagNodes` 是标签树的
/// 投影（节点 = 标签，`Tags.parentId` 就是边），距离只在这张图上算。
class CognitiveRankSeed {
  const CognitiveRankSeed({
    required this.availability,
    required this.tagNodes,
    this.goalNodeId,
    this.activeKnowledgePointIds = const <String>[],
    this.knowledgePointTagIds = const <String, List<String>>{},
    this.knowledgePointNames = const <String, String>{},
  });

  /// "什么都不知道"：注意力中性、没有起点、没有标签图。
  static const CognitiveRankSeed empty = CognitiveRankSeed(
    availability: 1,
    tagNodes: <MindNodeInfo>[],
  );

  /// α(τ)，0..1。没有读数时调用方传 1（中性），由 `CognitiveRank` 统一处理边界。
  final double availability;

  /// 标签树投影，给 [DiffusionBoost.distance] 用。
  final List<MindNodeInfo> tagNodes;

  /// 线程当前目标所在的标签（`ThreadState.goalNodeId`），null = 没设目标。
  final String? goalNodeId;

  /// 刚复习/刚读过的知识点 id（近因活动的"节点"落在知识点上，不在标签上）。
  final List<String> activeKnowledgePointIds;

  /// 知识点 id → 它挂着的标签 id。缺 key 或空列表 = 这个知识点没有标签。
  final Map<String, List<String>> knowledgePointTagIds;

  /// 知识点 id → 显示名，理由行说话用。
  final Map<String, String> knowledgePointNames;

  bool get hasOrigins =>
      goalNodeId != null || activeKnowledgePointIds.isNotEmpty;
}

/// 纯逻辑接线。
abstract final class CognitiveRankWiring {
  /// 把素材 + 候选任务编译成 [CognitiveRankInputs]。
  ///
  /// 只有候选真正挂着的知识点会被算距离（不会为库里每个知识点都跑一遍 BFS），
  /// 且顺序全部显式排序：同一份素材喂两次必须得到同一个结果。
  static CognitiveRankInputs build({
    required CognitiveRankSeed seed,
    required List<CognitiveRankCandidate> candidates,
  }) {
    final names = seed.knowledgePointNames;
    // 没有图就没有"距离"这回事：`DiffusionBoost.distance` 对同一个 id 会返回 0，
    // 哪怕它根本不在图里。空图时不下任何距离结论，免得把"两个一样的字符串"当成
    // "同一个节点"。理由行的 `via` 名字则靠 [CognitiveRankSeed.knowledgePointNames]，
    // 0 跳那一档说的是"刚活动过/就是当前目标"，所以名字只出现在 1/2 跳的句子里。
    if (!seed.hasOrigins || seed.tagNodes.isEmpty) {
      return CognitiveRankInputs(
        availability: seed.availability,
        knowledgePointNames: names,
      );
    }

    final activeIds = seed.activeKnowledgePointIds.toList()..sort();
    final wanted = <String>{
      for (final candidate in candidates) ...candidate.knowledgePointIds,
    }.toList()
      ..sort();

    final origins = <String, CognitiveRankOrigin>{};
    for (final knowledgePointId in wanted) {
      final tags = seed.knowledgePointTagIds[knowledgePointId];
      if (tags == null || tags.isEmpty) {
        // 没有标签 = 无从判断远近，不写 origin（理由行会如实说"没有认知读数"）。
        continue;
      }
      final origin = _nearest(
        nodes: seed.tagNodes,
        goalNodeId: seed.goalNodeId,
        activeKnowledgePointIds: activeIds,
        knowledgePointTagIds: seed.knowledgePointTagIds,
        candidateTags: tags,
      );
      if (origin != null) {
        origins[knowledgePointId] = origin;
      }
    }

    return CognitiveRankInputs(
      availability: seed.availability,
      originByKnowledgePoint: origins,
      knowledgePointNames: names,
    );
  }

  /// 候选的若干个标签里，离任一 ["起点标签"] 最近的那一条。
  ///
  /// 平手规则与 `CognitiveRank._nearestOrigin` 一致：跳数小者胜；同跳数
  /// **活动优先于目标**（刚做过的事比远处目标更该影响"现在做什么"）；
  /// 再同则按 via 的 id 排序，保证结果与集合遍历顺序无关。
  static CognitiveRankOrigin? _nearest({
    required List<MindNodeInfo> nodes,
    required String? goalNodeId,
    required List<String> activeKnowledgePointIds,
    required Map<String, List<String>> knowledgePointTagIds,
    required List<String> candidateTags,
  }) {
    final tags = candidateTags.toList()..sort();
    CognitiveRankOrigin? best;

    for (final tag in tags) {
      for (final activeId in activeKnowledgePointIds) {
        final originTags = knowledgePointTagIds[activeId];
        if (originTags == null) {
          continue;
        }
        final sortedOrigins = originTags.toList()..sort();
        for (final originTag in sortedOrigins) {
          final hops = DiffusionBoost.distance(nodes, originTag, tag);
          if (hops == null) {
            continue;
          }
          best = _better(
            best,
            CognitiveRankOrigin(
              hops: hops,
              link: CognitiveRankLink.activity,
              viaKnowledgePointId: activeId,
            ),
          );
        }
      }

      if (goalNodeId != null) {
        final hops = DiffusionBoost.distance(nodes, goalNodeId, tag);
        if (hops != null) {
          best = _better(
            best,
            CognitiveRankOrigin(
              hops: hops,
              link: CognitiveRankLink.goal,
              viaKnowledgePointId: goalNodeId,
            ),
          );
        }
      }
    }

    // 最近的一条都太远，就等于够不着：不写 origin，而不是写一个"距离很远"的 origin。
    if (best == null || best.hops > kCognitiveRankMaxHops) {
      return null;
    }
    return best;
  }

  static CognitiveRankOrigin _better(
    CognitiveRankOrigin? current,
    CognitiveRankOrigin candidate,
  ) {
    if (current == null) {
      return candidate;
    }
    if (candidate.hops != current.hops) {
      return candidate.hops < current.hops ? candidate : current;
    }
    final currentIsActivity = current.link == CognitiveRankLink.activity;
    final candidateIsActivity = candidate.link == CognitiveRankLink.activity;
    if (currentIsActivity != candidateIsActivity) {
      return candidateIsActivity ? candidate : current;
    }
    final currentVia = current.viaKnowledgePointId ?? '';
    final candidateVia = candidate.viaKnowledgePointId ?? '';
    return candidateVia.compareTo(currentVia) < 0 ? candidate : current;
  }
}

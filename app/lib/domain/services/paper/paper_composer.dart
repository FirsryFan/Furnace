/// 组卷器：从**已有的**题目里凑出一份"现在练什么最值"的卷子。
///
/// 用户口径（历史记录）：
/// * 组卷要**按薄弱/危险区知识点精准凑题**，而不是按时间或随机抽；
/// * 每题要附**提升点建议**与**知识背景**，让人知道"为什么做这道、做完下一步做什么"；
/// * **AI 不能自己出题**——所以凑不出题时如实报缺口（`uncoveredKnowledgePointIds`），
///   绝不用模型生成一道题来填空。
///
/// 这个文件是纯逻辑：不读库、不碰 drift、不碰 Flutter。谁把 `Questions` 行 +
/// `object_tags` 的题目↔知识点关系读成 [PaperCandidate]，谁就能拿到一份可解释的卷子。
library;

import '../reasoning/capability_action.dart' show CapabilityAction;
import '../scheduling/domain_balance.dart' show KnowledgePointReading;
import '../srs/dsr_memory.dart';
import 'subject_quota.dart';

/// **未标定**：一道题如果命中"我最该练的动作"，分数乘上 `1 + 这个系数 × 命中比例`。
///
/// 0.15 是刻意的保守值：能力动作画像本身是派生读数（`capability_profile.dart`），
/// 把它当硬过滤会把"没解过链的题"整体排除，那不是"练得准"，那是"只练解过的题"。
/// 这里只让"命中的排前面一点"，卷子里仍然会混进没链的题。标定之后（`docs/CALIBRATION.md`）
/// 再谈把它变成权重之一。
const double kPreferredActionBoost = 0.15;

/// 一次最多拿几个"最该练的动作"参与排序。
///
/// 3 个：再多就会让整份卷子被同一类动作占满，反而丢掉"按薄弱知识点精准凑题"这条
/// 更硬的排序依据。
const int kPreferredActionLimit = 3;

/// 来源分级的优先级（`gaokao` 最高，`unknown` 最低）。
///
/// 与 `data/repositories/question_repository.dart` 的 `kSourceLevelWeight`
/// **同序**：那边是检索排序用的整数分值，这里是 [0,1] 的权重分量。两张表由
/// `test/domain/services/paper/paper_composer_test.dart` 钉在一起，改一张必须改两张。
const Map<String, double> kSourceLevelPriority = {
  'gaokao': 1.0,
  'provincial_diagnostic': 0.8,
  'elite_school': 0.6,
  'school': 0.4,
  'personal': 0.2,
  'unknown': 0.0,
};

/// 危险区的"该练程度"。
const double kDangerNeed = 1.0;

/// 发展区的"该练程度"。
const double kDevelopmentNeed = 0.6;

/// 没有读数的"该练程度"。
///
/// 刻意**高于**已知健康（[kHealthyNeed]）："不知道"不等于"没问题"，把未知排在健康
/// 之前，人才有动力先把读数建立起来。这与本仓库其它读数口径一致（D2：一个数字一个来源，
/// 缺数据不许冒充好数据）。
const double kUnknownNeed = 0.35;

/// 已知健康的"该练程度"。
const double kHealthyNeed = 0.15;

/// 一个知识点现在的样子。
enum PaperZone {
  danger('危险区'),
  development('发展区'),
  healthy('健康'),
  unknown('没有读数');

  const PaperZone(this.labelZh);

  /// 中文标签（界面文案最终由 UI 决定，这里只保证可读与可解释）。
  final String labelZh;
}

/// 由读数得到 [PaperZone]；`null`（没有这个知识点的读数）是 [PaperZone.unknown]。
PaperZone paperZoneOf(KnowledgePointReading? reading) {
  if (reading == null) return PaperZone.unknown;
  if (reading.inDangerZone) return PaperZone.danger;
  if (reading.inDevelopmentZone) return PaperZone.development;
  return PaperZone.healthy;
}

/// 由读数得到"该练程度"。
double paperNeedOf(KnowledgePointReading? reading) {
  switch (paperZoneOf(reading)) {
    case PaperZone.danger:
      return kDangerNeed;
    case PaperZone.development:
      return kDevelopmentNeed;
    case PaperZone.healthy:
      return kHealthyNeed;
    case PaperZone.unknown:
      return kUnknownNeed;
  }
}

/// 三个分量的权重。
class PaperWeights {
  const PaperWeights({
    this.need = 0.55,
    this.quality = 0.25,
    this.difficultyFit = 0.20,
  });

  /// 该练程度（危险区 > 发展区 > 没有读数 > 健康）。
  final double need;

  /// 题源质量（来源分级 + AI 加工质量）。
  final double quality;

  /// 难度贴合度（只有给了 `targetDifficulty` 才有区别，否则恒为中性）。
  final double difficultyFit;

  double get sum => need + quality + difficultyFit;

  /// 归一化到和为 1；和 ≤ 0 时原样返回（宁可退化，也不悄悄改成别的权重）。
  PaperWeights normalized() {
    final total = sum;
    if (total <= 0) return this;
    return PaperWeights(
      need: need / total,
      quality: quality / total,
      difficultyFit: difficultyFit / total,
    );
  }

  Map<String, double> toMap() => {
        'need': need,
        'quality': quality,
        'difficulty_fit': difficultyFit,
      };
}

/// 一道**候选**题（题库里已有的一行，加上它挂的知识点）。
class PaperCandidate {
  const PaperCandidate({
    required this.questionId,
    required this.subjectKey,
    this.sourceLevel = 'unknown',
    this.questionType = 'solution',
    this.difficulty,
    this.aiQuality,
    this.trapNote,
    this.matchedKnowledgePointIds = const [],
    this.actionTypes = const [],
  });

  final String questionId;
  final String subjectKey;

  /// `gaokao` / `provincial_diagnostic` / `elite_school` / `school` /
  /// `personal` / `unknown`（`docs/QUESTION_BANK_DESIGN.md` §1）。
  final String sourceLevel;

  /// `single_choice` / `multi_choice` / `fill_blank` / `solution` / `open`。
  final String questionType;

  /// 1..10（先验或 AI 或人工，语义见 `difficultySource`，这里只关心数值）。
  final double? difficulty;

  /// AI 加工质量（假定 0..1；缺失按 0 处理）。
  final double? aiQuality;

  /// 已知易错点/坑（`Questions.trapNote`），有就写进提升点建议。
  final String? trapNote;

  /// 这道题挂到的知识点（由「题目与知识点共享同一标签」推出，
  /// 见 `TaskKnowledgePointResolver.resolveFromTagLinks`，`sourceObjectType: kQuestionObjectType`）。
  final List<String> matchedKnowledgePointIds;

  /// 这道题**最新一条**解题链上的能力动作序列（`reasoning_steps.action_type`，
  /// 见 `readChainActionTypes`）；没有链就是空表。
  ///
  /// 组卷用它回答"这道题能不能练到我最该练的那类动作"——动作词表是跨学科的，所以
  /// 这一维可以在数学卷上被物理题命中（`docs/REASONING_LAYER_DESIGN.md` §3）。
  final List<String> actionTypes;

  /// 来源分级优先级。
  double get sourcePriority => kSourceLevelPriority[sourceLevel.trim()] ?? 0.0;

  /// AI 加工质量，钳到 [0,1]。
  double get qualityScore {
    final value = aiQuality;
    if (value == null || value.isNaN) return 0.0;
    return value.clamp(0.0, 1.0);
  }
}

/// 这份卷子的要求。
class PaperSpec {
  const PaperSpec({
    required this.targetCount,
    this.subjectKeys = const {},
    this.perKnowledgePointCap,
    this.targetDifficulty,
    this.minSourceLevel,
    this.subjectQuota,
    this.preferCapabilityActions = true,
  });

  /// 想要几道题。
  final int targetCount;

  /// 只要这些学科（空集 = 不限）。
  final Set<String> subjectKeys;

  /// 每个知识点最多出几道；`null` = 由 [PaperComposer] 按候选分布算。
  final int? perKnowledgePointCap;

  /// 目标难度（1..10）；`null` = 不按难度挑。
  final double? targetDifficulty;

  /// 来源分级下限（含）；`null` = 不限。
  final String? minSourceLevel;

  /// 按学科配额（上限/下限）；`null` = 不启用（历史行为逐字节不变）。
  ///
  /// 启用后：先按学科保底逐科补齐，再按分数序填充；知识点上限先于学科上限；
  /// targetCount 是硬上限（保底也不得突破）。被学科上限挡下的候选不是
  /// 静默丢弃，而是记进 PaperPlan.quotaBlockedQuestions；没凑够保底的学科
  /// 记进 PaperPlan.subjectShortfalls。
  final SubjectQuota? subjectQuota;

  /// 组卷时要不要参考"我最该练的动作"（能力动作画像，未标定）。
  ///
  /// 默认 `true`，但**必须可关**：加成本身是未标定的先验（[kPreferredActionBoost]），
  /// 与仓库其它未标定读数同一条纪律——显式标注、能关掉。关掉之后 `compose` 收到的
  /// 偏好为空，卷子与"没有画像"时逐字段一致。
  final bool preferCapabilityActions;
}

/// 卷子上的一道题，带"为什么是它"。
class PaperItem {
  const PaperItem({
    required this.questionId,
    required this.subjectKey,
    required this.sourceLevel,
    required this.questionType,
    required this.knowledgePointId,
    required this.matchedKnowledgePointIds,
    required this.zone,
    required this.need,
    required this.quality,
    required this.score,
    required this.reasonZh,
    required this.improvementNote,
    required this.backgroundZh,
    this.matchedPreferredActions = const [],
  });

  final String questionId;
  final String subjectKey;
  final String sourceLevel;
  final String questionType;

  /// 这道题"最主要在补哪个点"：挂到的知识点里最该练的那个（`null` = 没挂知识点）。
  final String? knowledgePointId;
  final List<String> matchedKnowledgePointIds;
  final PaperZone zone;
  final double need;
  final double quality;
  final double score;

  /// 这道题的链里**命中"我最该练的动作"**的那几个 key（排序、去重；空 = 没命中）。
  ///
  /// 只有能力动作画像给出了"最该练"的动作时才可能非空；它只是排序时的透明度，
  /// 不是能力评估结论（画像本身也是派生读数，见 `capability_profile.dart`）。
  final List<String> matchedPreferredActions;

  /// 为什么排它（中文，可解释；措辞归领域层，界面不许另写一套）。
  final String reasonZh;

  /// 提升点建议（做完这题练到什么、注意什么；有 `trapNote` 会附上）。
  final String improvementNote;

  /// 知识背景（标签路径 → 知识点名 → 知识点 id → "未标注知识点"）。
  final String backgroundZh;

  Map<String, Object?> toJson() => {
        'question_id': questionId,
        'subject_key': subjectKey,
        'source_level': sourceLevel,
        'question_type': questionType,
        'knowledge_point_id': knowledgePointId,
        'matched_knowledge_point_ids': matchedKnowledgePointIds,
        'zone': zone.name,
        'need': DsrMemory.round6(need),
        'quality': DsrMemory.round6(quality),
        'score': DsrMemory.round6(score),
        'reason': reasonZh,
        'improvement_note': improvementNote,
        'background': backgroundZh,
        if (matchedPreferredActions.isNotEmpty)
          'matched_preferred_actions': matchedPreferredActions,
      };
}

/// 一份卷子。
class PaperPlan {
  const PaperPlan({
    required this.items,
    required this.uncoveredKnowledgePointIds,
    required this.deferredKnowledgePointIds,
    required this.byKnowledgePoint,
    required this.candidateCount,
    required this.requestedCount,
    required this.overallNeed,
    required this.weights,
    this.preferredActionTypes = const [],
    this.bySubject = const {},
    this.quotaBlockedQuestions = const [],
    this.subjectShortfalls = const [],
    this.subjectQuota,
  });

  /// 选中的题（**贪心选择顺序**，与每知识点配额有关，不是单纯的分数降序）。
  final List<PaperItem> items;

  /// 危险/发展区、但题库里**一道候选都没有**的知识点（如实报缺口，不生成题）。
  final List<String> uncoveredKnowledgePointIds;

  /// 危险/发展区、有候选但这轮**没排进来**的知识点（配额/数量限制造成）。
  final List<String> deferredKnowledgePointIds;

  /// 每个知识点被排了几道（含被"顺带覆盖"的第二知识点）。
  final Map<String, int> byKnowledgePoint;

  /// 进入打分前还剩多少候选（过滤之后）。
  final int candidateCount;

  /// 想要的题数。
  final int requestedCount;

  /// 选中题的平均"该练程度"；没选中任何题时是 0。
  final double overallNeed;

  final PaperWeights weights;

  /// 这一份卷子实际参考的"我最该练的动作"（空 = 没参考：关掉了或没有画像）。
  ///
  /// 界面据此显示"本卷按「…」这类动作排过（未标定，可关）"；工具把它放进 `modelResult`。
  final List<String> preferredActionTypes;

  /// 每个学科被排了几道（学科键已 trim；空学科键不进这张表）。
  ///
  /// 空表 = 没启用学科配额（或一道都没选中）。
  final Map<String, int> bySubject;

  /// 本来能进卷、但被学科上限挡下的候选（按扫描顺序；不静默丢题）。
  final List<QuotaBlockedQuestion> quotaBlockedQuestions;

  /// 没达到学科保底的缺口（按学科键字典序；空 = 没有缺口或没配保底）。
  final List<SubjectQuotaShortfall> subjectShortfalls;

  /// 这次组卷实际生效的学科配额（已归一化：trim/排序/保底优先）；`null` = 没启用。
  final SubjectQuotaResolved? subjectQuota;

  /// 有保底、但题库里一道候选都没有的学科（缺口在收题，不在配额）。
  List<String> get uncoveredSubjectKeys => [
        for (final shortfall in subjectShortfalls)
          if (shortfall.isUncovered) shortfall.subjectKey,
      ];

  /// 没凑够（题库不足或过滤太严）。
  bool get isShort => items.length < requestedCount;

  bool get isEmpty => items.isEmpty;

  Map<String, Object?> toJson() => {
        'schema': 'mindnet.paper_plan/1',
        'items': [for (final item in items) item.toJson()],
        'uncovered_knowledge_points': uncoveredKnowledgePointIds,
        'deferred_knowledge_points': deferredKnowledgePointIds,
        'by_knowledge_point': byKnowledgePoint,
        'candidate_count': candidateCount,
        'requested_count': requestedCount,
        'is_short': isShort,
        'overall_need': DsrMemory.round6(overallNeed),
        'weights': weights.toMap(),
        if (preferredActionTypes.isNotEmpty)
          'preferred_action_types': preferredActionTypes,
        // 学科配额：启用才出键（默认不启用 → 一个键都不多，历史输出逐字节一致）。
        if (subjectQuota != null) 'by_subject': bySubject,
        if (subjectQuota != null)
          'quota_blocked_questions': [
            for (final blocked in quotaBlockedQuestions) blocked.toJson(),
          ],
        if (subjectQuota != null)
          'subject_shortfalls': [
            for (final shortfall in subjectShortfalls) shortfall.toJson(),
          ],
        if (subjectQuota != null) 'subject_quota': subjectQuota!.toJson(),
      };
}

/// 组卷的三个步骤：过滤 → 打分 → 带配额的贪心。
///
/// 确定性：同一份输入（哪怕顺序不同）永远给出同一份卷子；tie-break 依次是
/// 分数 → 来源分级 → AI 质量 → 题目 id。
///
/// 学科配额（PaperSpec.subjectQuota，默认关闭）：
/// 1. 过滤 → 打分 → tie-break 排序 → 每知识点上限，全部与不启用时一致；
/// 2. 保底阶段：按学科键字典序，逐科把该科候选按分数序补到下限
///    （受每知识点上限与 targetCount 约束）；
/// 3. 填充阶段：仍按分数序，先查每知识点上限（旧的 continue 语义不变），
///    再查学科上限——超限的候选记进 PaperPlan.quotaBlockedQuestions，不静默丢弃；
/// 4. 选完后：每个没达到保底的学科记进 PaperPlan.subjectShortfalls；
/// 5. targetCount 是硬上限（保底也不得突破）；没配置的学科、空学科键不受限；
/// 6. 同科 min > max 时保底优先，上限在归一化时抬到 min。
/// 默认 `subjectQuota == null` 时以上分支全不进入 → 输出与历史逐字节一致。
abstract final class PaperComposer {
  static PaperPlan compose({
    required List<PaperCandidate> candidates,
    required PaperSpec spec,
    List<KnowledgePointReading> readings = const [],
    Map<String, String> knowledgePointNames = const {},
    Map<String, List<String>> knowledgePointTagPaths = const {},
    PaperWeights weights = const PaperWeights(),
    List<String> preferredActionTypes = const [],
  }) {
    final readingsById = {
      for (final reading in readings) reading.knowledgePointId: reading,
    };
    final normalized = weights.normalized();
    // 去空、去重、保序（画像是按"最该练"排好序的），最多取前 3 个。
    final preferred = preferredActionTypes
        .map((action) => action.trim())
        .where((action) => action.isNotEmpty)
        .toSet()
        .take(kPreferredActionLimit)
        .toList();

    final usable = [
      for (final candidate in candidates)
        if (_passesFilters(candidate, spec)) candidate,
    ];

    final scored = [
      for (final candidate in usable)
        _score(candidate, readingsById, normalized, spec, preferred),
    ];

    final pointsWithCandidates = <String>{
      for (final entry in scored) ...entry.coveredPoints,
    };
    final cap = spec.perKnowledgePointCap ??
        _defaultCap(spec.targetCount, pointsWithCandidates.length);

    scored.sort(_byScoreThenProvenance);

    final requestedQuota = spec.subjectQuota;
    final quota = (requestedQuota != null && requestedQuota.isEnabled)
        ? requestedQuota.resolve()
        : null;

    final picked = <_Scored>[];
    final pickedIds = <String>{};
    final usedPerPoint = <String, int>{};
    final usedPerSubject = <String, int>{};
    final quotaBlocked = <QuotaBlockedQuestion>[];

    // 每知识点上限（旧语义）：每个挂到的点都到上限才跳过；没挂点的题不限。
    bool pointCapAllows(_Scored entry) =>
        entry.coveredPoints.isEmpty ||
        !entry.coveredPoints
            .every((point) => (usedPerPoint[point] ?? 0) >= cap);

    void pick(_Scored entry) {
      picked.add(entry);
      pickedIds.add(entry.candidate.questionId);
      for (final point in entry.coveredPoints) {
        usedPerPoint[point] = (usedPerPoint[point] ?? 0) + 1;
      }
      if (quota != null) {
        final subjectKey = entry.candidate.subjectKey.trim();
        usedPerSubject[subjectKey] = (usedPerSubject[subjectKey] ?? 0) + 1;
      }
    }

    if (quota != null) {
      // 保底阶段：学科键字典序，逐科按分数序补到下限（受知识点上限/targetCount 约束）。
      final minimumSubjects = quota.minPerSubject.keys.toList()..sort();
      for (final subjectKey in minimumSubjects) {
        final minimum = quota.minPerSubject[subjectKey]!;
        if (minimum <= 0) continue;
        for (final entry in scored) {
          if ((usedPerSubject[subjectKey] ?? 0) >= minimum) break;
          if (picked.length >= spec.targetCount) break;
          if (pickedIds.contains(entry.candidate.questionId)) continue;
          if (entry.candidate.subjectKey.trim() != subjectKey) continue;
          if (!pointCapAllows(entry)) continue;
          pick(entry);
        }
      }
    }

    for (final entry in scored) {
      if (picked.length >= spec.targetCount) break;
      // 只有启用配额时才按 id 去重（关闭时保持历史行为逐字节不变）。
      if (quota != null && pickedIds.contains(entry.candidate.questionId)) {
        continue;
      }
      if (!pointCapAllows(entry)) continue;
      if (quota != null) {
        final subjectKey = entry.candidate.subjectKey.trim();
        final maximum = quota.maxPerSubject[subjectKey];
        if (maximum != null && (usedPerSubject[subjectKey] ?? 0) >= maximum) {
          quotaBlocked.add(QuotaBlockedQuestion(
            questionId: entry.candidate.questionId,
            subjectKey: subjectKey,
            subjectLimit: maximum,
          ));
          continue;
        }
      }
      pick(entry);
    }

    // 学科汇总/缺口（只在启用配额时才算；关闭时两张表都是空）。
    final bySubject = <String, int>{};
    final subjectShortfalls = <SubjectQuotaShortfall>[];
    if (quota != null) {
      final pickedSubjects = usedPerSubject.keys.toList()..sort();
      for (final subjectKey in pickedSubjects) {
        if (subjectKey.isEmpty) continue;
        bySubject[subjectKey] = usedPerSubject[subjectKey]!;
      }
      final availablePerSubject = <String, int>{};
      for (final entry in scored) {
        final subjectKey = entry.candidate.subjectKey.trim();
        if (subjectKey.isEmpty) continue;
        availablePerSubject[subjectKey] =
            (availablePerSubject[subjectKey] ?? 0) + 1;
      }
      final minimumSubjects = quota.minPerSubject.keys.toList()..sort();
      for (final subjectKey in minimumSubjects) {
        final minimum = quota.minPerSubject[subjectKey]!;
        if (minimum <= 0) continue;
        final selected = usedPerSubject[subjectKey] ?? 0;
        if (selected >= minimum) continue;
        subjectShortfalls.add(SubjectQuotaShortfall(
          subjectKey: subjectKey,
          minimumCount: minimum,
          selectedCount: selected,
          availableCount: availablePerSubject[subjectKey] ?? 0,
        ));
      }
    }

    final items = [
      for (final entry in picked)
        PaperItem(
          questionId: entry.candidate.questionId,
          subjectKey: entry.candidate.subjectKey,
          sourceLevel: entry.candidate.sourceLevel,
          questionType: entry.candidate.questionType,
          knowledgePointId: entry.primaryPointId,
          matchedKnowledgePointIds: entry.coveredPoints,
          zone: entry.zone,
          need: entry.need,
          quality: entry.quality,
          score: entry.score,
          reasonZh: _reasonZh(
            pointId: entry.primaryPointId,
            pointLabel: _labelOf(
              entry.primaryPointId,
              knowledgePointNames,
              knowledgePointTagPaths,
            ),
            zone: entry.zone,
            reading: readingsById[entry.primaryPointId],
            matchedPreferredActions: entry.matchedPreferredActions,
          ),
          improvementNote: _improvementNote(entry.candidate, entry.zone),
          backgroundZh: _backgroundZh(
            entry.primaryPointId,
            knowledgePointNames,
            knowledgePointTagPaths,
          ),
          matchedPreferredActions: entry.matchedPreferredActions,
        ),
    ];

    final chosenPoints = <String>{
      for (final entry in picked) ...entry.coveredPoints,
    };
    final uncovered = <String>[];
    final deferred = <String>[];
    for (final entry in readingsById.entries) {
      if (paperNeedOf(entry.value) < kDevelopmentNeed) continue;
      if (!pointsWithCandidates.contains(entry.key)) {
        uncovered.add(entry.key);
      } else if (!chosenPoints.contains(entry.key)) {
        deferred.add(entry.key);
      }
    }
    uncovered.sort();
    deferred.sort();

    final byKnowledgePoint = <String, int>{};
    for (final entry in picked) {
      for (final point in entry.coveredPoints) {
        byKnowledgePoint[point] = (byKnowledgePoint[point] ?? 0) + 1;
      }
    }

    final overallNeed = items.isEmpty
        ? 0.0
        : items.fold<double>(0, (sum, item) => sum + item.need) / items.length;

    return PaperPlan(
      items: items,
      uncoveredKnowledgePointIds: uncovered,
      deferredKnowledgePointIds: deferred,
      byKnowledgePoint: Map.unmodifiable(byKnowledgePoint),
      candidateCount: scored.length,
      requestedCount: spec.targetCount,
      overallNeed: overallNeed,
      weights: normalized,
      preferredActionTypes: List<String>.unmodifiable(preferred),
      bySubject: Map.unmodifiable(bySubject),
      quotaBlockedQuestions: List.unmodifiable(quotaBlocked),
      subjectShortfalls: List.unmodifiable(subjectShortfalls),
      subjectQuota: quota,
    );
  }

  static bool _passesFilters(PaperCandidate candidate, PaperSpec spec) {
    if (spec.subjectKeys.isNotEmpty &&
        !spec.subjectKeys.contains(candidate.subjectKey)) {
      return false;
    }
    final floor = spec.minSourceLevel;
    if (floor != null) {
      final minimum = kSourceLevelPriority[floor.trim()];
      if (minimum != null && candidate.sourcePriority < minimum) return false;
    }
    return true;
  }

  static _Scored _score(
    PaperCandidate candidate,
    Map<String, KnowledgePointReading> readingsById,
    PaperWeights weights,
    PaperSpec spec,
    List<String> preferred,
  ) {
    final points = candidate.matchedKnowledgePointIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    String? primary;
    var need = kUnknownNeed;
    var zone = PaperZone.unknown;
    for (final point in points) {
      final pointNeed = paperNeedOf(readingsById[point]);
      final better = primary == null || pointNeed > need;
      if (better) {
        primary = point;
        need = pointNeed;
        zone = paperZoneOf(readingsById[point]);
      }
    }

    final quality =
        candidate.sourcePriority * 0.7 + candidate.qualityScore * 0.3;
    final difficultyFit =
        _difficultyFit(candidate.difficulty, spec.targetDifficulty);
    final rawScore = weights.need * need +
        weights.quality * quality +
        weights.difficultyFit * difficultyFit;

    // 「我最该练的动作」只做透明加成：命中比例 × 一个保守系数，乘在总分上。
    // 没有偏好（preferred 空）时乘数恒为 1，历史行为一个字节都不变。
    final actions =
        candidate.actionTypes.map((action) => action.trim()).toSet();
    final matched = <String>[
      for (final action in preferred)
        if (actions.contains(action)) action,
    ];
    final actionFit =
        preferred.isEmpty ? 0.0 : matched.length / preferred.length;
    final score = rawScore * (1 + kPreferredActionBoost * actionFit);

    return _Scored(
      candidate: candidate,
      coveredPoints: points,
      primaryPointId: primary,
      zone: zone,
      need: need,
      quality: quality,
      difficultyFit: difficultyFit,
      score: score,
      matchedPreferredActions: matched,
    );
  }

  /// 有目标难度：越接近越贴合；没有目标难度：恒为 1（中性，不奖励也不惩罚）。
  static double _difficultyFit(double? difficulty, double? target) {
    if (target == null) return 1.0;
    if (difficulty == null) return 0.5;
    final gap = (difficulty - target).abs() / 9.0;
    return (1.0 - gap).clamp(0.0, 1.0);
  }

  static int _defaultCap(int targetCount, int pointCount) {
    if (pointCount <= 0) return targetCount < 1 ? 1 : targetCount;
    final raw = (targetCount + pointCount - 1) ~/ pointCount;
    return raw < 1 ? 1 : raw;
  }

  static int _byScoreThenProvenance(_Scored a, _Scored b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    final bySource =
        b.candidate.sourcePriority.compareTo(a.candidate.sourcePriority);
    if (bySource != 0) return bySource;
    final byQuality =
        b.candidate.qualityScore.compareTo(a.candidate.qualityScore);
    if (byQuality != 0) return byQuality;
    return a.candidate.questionId.compareTo(b.candidate.questionId);
  }

  static String _reasonZh({
    required String? pointId,
    required String pointLabel,
    required PaperZone zone,
    required KnowledgePointReading? reading,
    List<String> matchedPreferredActions = const [],
  }) {
    final preferredNote = matchedPreferredActions.isEmpty
        ? ''
        : ' 这题会练到「${matchedPreferredActions.map(_actionLabel).join('、')}」'
            '这类动作（来自你的能力动作画像）。';
    if (pointId == null) {
      return '这道题还没有挂知识点，先按未知处理（未知不当作健康）。$preferredNote';
    }
    final readingNote = reading?.priorR0 == null
        ? ''
        : '目前先验 R0≈${_two(reading!.priorR0!)}、置信度 ${_two(reading.priorConfidence)}；';
    final base = switch (zone) {
      PaperZone.danger =>
        '$readingNote知识点「$pointLabel」在危险区（自信高、实际提取不出来），这份卷先练它。',
      PaperZone.development =>
        '$readingNote知识点「$pointLabel」在发展区（有读数但还偏弱），现在练收益最大。',
      PaperZone.healthy => '$readingNote知识点「$pointLabel」目前读数是健康的，作为保温/巩固排进来。',
      PaperZone.unknown => '知识点「$pointLabel」还没有你的读数，按未知处理（未知不当作健康）。',
    };
    return '$base$preferredNote';
  }

  /// 动作 key → 中文名；词表外的 key 原样返回（不硬塞一个"未知动作"）。
  static String _actionLabel(String key) =>
      CapabilityAction.byKey(key)?.labelZh ?? key;

  static String _improvementNote(PaperCandidate candidate, PaperZone zone) {
    final base = switch (zone) {
      PaperZone.danger => '别整套刷：只把关键那一步慢速重做一遍，并写出每一步的依据。',
      PaperZone.development => '按现在的节奏做完，对答案时把错因写下来（下一轮才有读数）。',
      PaperZone.healthy => '当保温题：限时完成，答对就过。',
      PaperZone.unknown => '先做一遍并把结果记进系统，下一轮才知道它属于哪一档。',
    };
    final trap = (candidate.trapNote ?? '').trim();
    return trap.isEmpty ? base : '$base 这题的已知坑：$trap';
  }

  static String _labelOf(
    String? pointId,
    Map<String, String> names,
    Map<String, List<String>> paths,
  ) {
    if (pointId == null) return '未标注知识点';
    final path = paths[pointId];
    if (path != null && path.isNotEmpty) {
      final last = path.last.trim();
      if (last.isNotEmpty) return last;
    }
    final name = (names[pointId] ?? '').trim();
    return name.isEmpty ? pointId : name;
  }

  static String _backgroundZh(
    String? pointId,
    Map<String, String> names,
    Map<String, List<String>> paths,
  ) {
    if (pointId == null) return '未标注知识点';
    final path = paths[pointId];
    if (path != null && path.isNotEmpty) {
      final joined = path.map((part) => part.trim()).where((p) => p.isNotEmpty);
      if (joined.isNotEmpty) return joined.join(' / ');
    }
    final name = (names[pointId] ?? '').trim();
    return name.isEmpty ? pointId : name;
  }

  static String _two(double value) => value.toStringAsFixed(2);
}

class _Scored {
  const _Scored({
    required this.candidate,
    required this.coveredPoints,
    required this.primaryPointId,
    required this.zone,
    required this.need,
    required this.quality,
    required this.difficultyFit,
    required this.score,
    required this.matchedPreferredActions,
  });

  final PaperCandidate candidate;
  final List<String> coveredPoints;
  final String? primaryPointId;
  final PaperZone zone;
  final double need;
  final double quality;
  final double difficultyFit;
  final double score;
  final List<String> matchedPreferredActions;
}

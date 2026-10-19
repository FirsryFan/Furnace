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
import 'domain_quota.dart';
import 'source_level_labels.dart';
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
    this.domainQuota,
    this.manualIncludeQuestionIds,
    this.manualExcludeQuestionIds,
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

  /// 按领域配额（标签顶级域的上限/下限）；`null` = 不启用（历史行为逐字节不变）。
  ///
  /// 领域来自 [compose] 的 `knowledgePointTagPaths`（每条标签路径的第一段，见
  /// `DomainQuotaResolver`）。与 [subjectQuota] 同时启用时的确定次序见
  /// [PaperComposer.compose] 文档。被领域上限挡下的候选不静默丢弃，记进
  /// `PaperPlan.quotaBlockedByDomain`；没凑够保底的领域记进
  /// `PaperPlan.domainShortfalls`。
  final DomainQuota? domainQuota;

  /// 手工**必收**的题目 id；`null` = 不启用（历史行为逐字节不变）。
  ///
  /// 非 null（含空集）即视为启用：空集只代表"没有必收题"，与 `null` 的区别是
  /// `PaperPlan.toJson` 会多出手工相关四键（输出契约，测试钉住）。
  ///
  /// 语义（与 [manualExcludeQuestionIds] 同时看）：
  /// * **排除优先**：同一 id 同时出现在必收与排除里时，排除生效；它记进
  ///   [PaperPlan.manualConflictQuestionIds]，不算进卷、也不算缺失；
  /// * 必收题在保底与填充**之前**入选，不受知识点上限、学科上限、领域上限
  ///   （以及 [subjectKeys] / [minSourceLevel] 过滤）限制——用户点名就要；
  /// * 只受 [targetCount] 硬上限：装不下时按 id 字典序取前若干个，其余记进
  ///   [PaperPlan.manualSkippedQuestionIds]；
  /// * 候选池里根本没有这个 id 时记进 [PaperPlan.manualMissingQuestionIds]；
  /// * 必收题仍走正常打分（`PaperItem` 的 zone / need / score 照算），并计入
  ///   [PaperPlan.bySubject] / [PaperPlan.byDomain] 与各配额计数（占用该科/该域的
  ///   名额，保底不会为它重复补题）。
  final Set<String>? manualIncludeQuestionIds;

  /// 手工**排除**的题目 id；`null` = 不启用（历史行为逐字节不变）。
  ///
  /// 排除优先级最高：候选池里这些题在**任何阶段**都不选（保底、填充也不选），
  /// 并从 `candidateCount` 里去掉。与 [manualIncludeQuestionIds] 冲突时排除生效，
  /// 冲突 id 记进 [PaperPlan.manualConflictQuestionIds]。
  final Set<String>? manualExcludeQuestionIds;

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

/// 缺口的一句话解释（[PaperPlan.uncoveredKnowledgePointNotes] /
/// [PaperPlan.deferredKnowledgePointNotes] 的元素）。
///
/// 只在调用方开 `PaperComposer.compose(detailedNotes: true)` 时产出；默认不生成，
/// 历史输出逐字节不变。措辞归领域层，界面/导出直接展示，不再自己拼一套。
class PaperGapNote {
  const PaperGapNote({
    required this.knowledgePointId,
    required this.labelZh,
    required this.messageZh,
  });

  final String knowledgePointId;

  /// 知识点显示名（标签路径最后一段 → 名字 → id）。
  final String labelZh;

  /// 缺口原因 + 下一步动作（中文，可执行）。
  final String messageZh;

  Map<String, Object?> toJson() => {
        'knowledge_point_id': knowledgePointId,
        'label_zh': labelZh,
        'message': messageZh,
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
    this.byDomain = const {},
    this.quotaBlockedByDomain = const [],
    this.domainShortfalls = const [],
    this.domainQuota,
    this.manualSelectionEnabled = false,
    this.manualIncludedCount = 0,
    this.manualMissingQuestionIds = const [],
    this.manualSkippedQuestionIds = const [],
    this.manualConflictQuestionIds = const [],
    this.uncoveredKnowledgePointNotes = const [],
    this.deferredKnowledgePointNotes = const [],
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

  /// 每个领域被排了几道（领域键已 trim、按字典序；主领域 + 附加领域全量统计）。
  ///
  /// 一道题可能同时属于多个领域，所以这张表的条目数可以大于题目数；
  /// 无领域的题不进这张表。空表 = 没启用领域配额（或一道都没选中）。
  final Map<String, int> byDomain;

  /// 本来能进卷、但被领域上限挡下的候选（按扫描顺序；不静默丢题）。
  final List<DomainQuotaBlockedQuestion> quotaBlockedByDomain;

  /// 没达到领域保底的缺口（按领域键字典序；空 = 没有缺口或没配保底）。
  final List<DomainQuotaShortfall> domainShortfalls;

  /// 这次组卷实际生效的领域配额（已归一化：trim/排序/保底优先）；`null` = 没启用。
  final DomainQuotaResolved? domainQuota;

  /// 是否启用了手工指定/排除（`PaperSpec.manualIncludeQuestionIds` 或
  /// `manualExcludeQuestionIds` 任一非 null；空集也算启用）。
  ///
  /// 只有 `true` 时 `toJson` 才追加手工相关四键；`false`（默认）时旧输出逐字节不变。
  final bool manualSelectionEnabled;

  /// 实际进卷的手工必收题数（不含因 [requestedCount] 上限被挤掉的、也不含缺失/冲突）。
  final int manualIncludedCount;

  /// 要求必收、但候选池里根本没有的题目 id（按 id 字典序；不静默丢）。
  final List<String> manualMissingQuestionIds;

  /// 要求必收、但被 [requestedCount] 硬上限挤掉的题目 id（按 id 字典序；不静默丢）。
  final List<String> manualSkippedQuestionIds;

  /// 同时出现在必收与排除里的题目 id（排除生效，未进卷；按 id 字典序）。
  final List<String> manualConflictQuestionIds;

  /// 未覆盖知识点的解释句（`detailedNotes: true` 才产出；默认空表 = 不出键）。
  ///
  /// 与 [uncoveredKnowledgePointIds] 一一对应（顺序相同）：缺什么、下一步做什么。
  final List<PaperGapNote> uncoveredKnowledgePointNotes;

  /// 被挤掉知识点的解释句（`detailedNotes: true` 才产出；默认空表 = 不出键）。
  ///
  /// 与 [deferredKnowledgePointIds] 一一对应（顺序相同）：为什么这轮没排上、怎么调。
  final List<PaperGapNote> deferredKnowledgePointNotes;

  /// 有保底、但题库里一道候选都没有的学科（缺口在收题，不在配额）。
  List<String> get uncoveredSubjectKeys => [
        for (final shortfall in subjectShortfalls)
          if (shortfall.isUncovered) shortfall.subjectKey,
      ];

  /// 有保底、但题库里一道候选都没有的领域（缺口在收题，不在配额）。
  List<String> get uncoveredDomains => [
        for (final shortfall in domainShortfalls)
          if (shortfall.isUncovered) shortfall.domain,
      ];

  /// 没凑够（题库不足或过滤太严）。
  bool get isShort => items.length < requestedCount;

  bool get isEmpty => items.isEmpty;

  Map<String, Object?> toJson() => {
        'schema': 'mindnet.paper_plan/1',
        'items': [for (final item in items) item.toJson()],
        'uncovered_knowledge_points': uncoveredKnowledgePointIds,
        'deferred_knowledge_points': deferredKnowledgePointIds,
        // 缺口解释句：只有 detailedNotes 产出时非空（默认不出键，历史输出一致）。
        if (uncoveredKnowledgePointNotes.isNotEmpty)
          'uncovered_knowledge_point_notes': [
            for (final note in uncoveredKnowledgePointNotes) note.toJson(),
          ],
        if (deferredKnowledgePointNotes.isNotEmpty)
          'deferred_knowledge_point_notes': [
            for (final note in deferredKnowledgePointNotes) note.toJson(),
          ],
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
        // 领域配额：独立开关；启用才出键（都关闭时历史输出逐字节一致）。
        if (domainQuota != null) 'by_domain': byDomain,
        if (domainQuota != null)
          'quota_blocked_by_domain': [
            for (final blocked in quotaBlockedByDomain) blocked.toJson(),
          ],
        if (domainQuota != null)
          'domain_shortfalls': [
            for (final shortfall in domainShortfalls) shortfall.toJson(),
          ],
        if (domainQuota != null) 'domain_quota': domainQuota!.toJson(),
        // 手工指定/排除：独立的开关；null 时四键都不出（历史输出逐字节一致）。
        if (manualSelectionEnabled)
          'manual_included_count': manualIncludedCount,
        if (manualSelectionEnabled)
          'manual_missing_question_ids': manualMissingQuestionIds,
        if (manualSelectionEnabled)
          'manual_skipped_question_ids': manualSkippedQuestionIds,
        if (manualSelectionEnabled)
          'manual_conflict_question_ids': manualConflictQuestionIds,
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
///
/// 领域配额（PaperSpec.domainQuota，默认关闭；与学科配额同时启用时）：
/// 7. 领域 = 知识点标签路径的顶级域（`DomainQuotaResolver`）；一道题取所有
///    知识点的领域并集、字典序第一个为主领域，附加领域只回报不判定；
/// 8. 次序固定：学科保底 → 领域保底 → 填充；targetCount 始终是硬上限；
/// 9. 领域保底阶段受知识点上限与学科上限约束（学科上限更硬，挡下不计 blocked），
///    不再强制领域上限（同域 min > max 已在归一化时抬到 min，保底优先）；
/// 10. 填充阶段依次查 知识点上限 → 学科上限 → 领域主领域上限；被领域上限
///     挡下的候选记进 PaperPlan.quotaBlockedByDomain，不静默丢弃；
/// 11. 没配置的领域不限；max=0 的领域不取；没挂知识点/没标签路径的题按
///     无领域处理、不进领域判定；附加领域只在 PaperPlan.byDomain 里出现；
/// 12. 未覆盖（`DomainQuotaShortfall.isUncovered`）的领域进
///     PaperPlan.uncoveredDomains：缺口在收题，不在配额。
///
/// 手工指定/排除（PaperSpec.manualIncludeQuestionIds / manualExcludeQuestionIds，默认关闭）：
/// 13. 排除优先：排除 id 在任何阶段都不选，并从 `candidateCount` 里去掉；
/// 14. 必收题在学科保底/领域保底/填充**之前**入选，不受知识点上限、学科上限、
///     领域上限（以及 `subjectKeys` / `minSourceLevel` 过滤）限制，只受
///     `targetCount` 硬上限；装不下的按 id 字典序记进
///     PaperPlan.manualSkippedQuestionIds，不静默丢；
/// 15. 候选池里没有的必收 id 记进 PaperPlan.manualMissingQuestionIds；与排除
///     冲突的 id 记进 PaperPlan.manualConflictQuestionIds（排除生效）；
/// 16. 必收题仍走正常打分，并计入 PaperPlan.bySubject / byDomain 与各配额计数
///     （占该科/该域名额，保底不会为它重复补题）。
/// 文案详情（`compose(detailedNotes: true)`，默认关闭）：
/// 17. 默认 `false` 时 `PaperItem` 三条文案与缺口列表逐字节不变；
/// 18. 打开后只在理由/建议/背景里追加**可核实**信息（本卷第几题、需求 / 质量分 /
///     综合得分 / 权重、本题还覆盖的知识点），并生成
///     `PaperPlan.uncoveredKnowledgePointNotes` / `deferredKnowledgePointNotes`
///     回答缺口「缺什么、下一步怎么做」；排序、分数、配额与默认完全一致。
///
/// 默认 `subjectQuota == null && domainQuota == null` 且手工两集合都为 `null` 时
/// 以上分支全不进入 → 输出与历史逐字节一致。
abstract final class PaperComposer {
  static PaperPlan compose({
    required List<PaperCandidate> candidates,
    required PaperSpec spec,
    List<KnowledgePointReading> readings = const [],
    Map<String, String> knowledgePointNames = const {},
    Map<String, List<String>> knowledgePointTagPaths = const {},
    PaperWeights weights = const PaperWeights(),
    List<String> preferredActionTypes = const [],
    bool detailedNotes = false,
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

    // 手工指定/排除（默认 null：enabled=false，下面两个分支都不改变历史行为）。
    final manual = _ManualSelection.resolve(spec);

    final usable = [
      for (final candidate in candidates)
        if (!manual.excludeIdSet.contains(candidate.questionId.trim()) &&
            (_passesFilters(candidate, spec) ||
                manual.includeIdSet.contains(candidate.questionId.trim())))
          candidate,
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

    final requestedDomainQuota = spec.domainQuota;
    final domainQuota =
        (requestedDomainQuota != null && requestedDomainQuota.isEnabled)
            ? requestedDomainQuota.resolve()
            : null;
    final domainsByPoint = domainQuota == null
        ? const <String, List<String>>{}
        : DomainQuotaResolver.domainsByKnowledgePoint(
            knowledgePointTagPaths,
          );
    final domainsByQuestion = <String, QuestionDomains>{};
    if (domainQuota != null) {
      for (final entry in scored) {
        domainsByQuestion[entry.candidate.questionId] =
            DomainQuotaResolver.questionDomains(
          domainsByPoint,
          entry.coveredPoints,
        );
      }
    }

    final picked = <_Scored>[];
    final pickedIds = <String>{};
    final usedPerPoint = <String, int>{};
    final usedPerSubject = <String, int>{};
    final quotaBlocked = <QuotaBlockedQuestion>[];
    // 领域配额只按主领域计数；附加领域不参与上限/保底判定。
    final usedPerDomain = <String, int>{};
    final domainBlocked = <DomainQuotaBlockedQuestion>[];

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
      if (domainQuota != null) {
        final primaryDomain =
            domainsByQuestion[entry.candidate.questionId]?.primaryDomain;
        if (primaryDomain != null) {
          usedPerDomain[primaryDomain] =
              (usedPerDomain[primaryDomain] ?? 0) + 1;
        }
      }
    }

    // 手工必收：排除优先；必收在保底/填充之前入选，只受 targetCount 硬上限。
    final manualMissing = <String>[];
    final manualSkipped = <String>[];
    var manualIncludedCount = 0;
    if (manual.enabled) {
      // scored 已按同一 tie-break 排序：同一 id 多候选时取最优的那条（确定性）。
      final scoredById = <String, _Scored>{};
      for (final entry in scored) {
        scoredById.putIfAbsent(entry.candidate.questionId.trim(), () => entry);
      }
      for (final id in manual.includeIds) {
        // 与排除冲突：排除生效，冲突已记进 manual.conflicts，不算缺失/挤掉。
        if (manual.excludeIdSet.contains(id)) continue;
        final entry = scoredById[id];
        if (entry == null) {
          manualMissing.add(id);
          continue;
        }
        if (picked.length >= spec.targetCount) {
          manualSkipped.add(id);
          continue;
        }
        pick(entry);
        manualIncludedCount++;
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

    if (domainQuota != null) {
      // 领域保底阶段：域键字典序、逐域按分数序补到下限。
      // 保底不强制领域上限（min>max 已在归一化抬上限）；但不得突破学科上限。
      final minimumDomains = domainQuota.minPerDomain.keys.toList()..sort();
      for (final domain in minimumDomains) {
        final minimum = domainQuota.minPerDomain[domain]!;
        if (minimum <= 0) continue;
        for (final entry in scored) {
          if ((usedPerDomain[domain] ?? 0) >= minimum) break;
          if (picked.length >= spec.targetCount) break;
          if (pickedIds.contains(entry.candidate.questionId)) continue;
          if (domainsByQuestion[entry.candidate.questionId]?.primaryDomain !=
              domain) {
            continue;
          }
          if (!pointCapAllows(entry)) continue;
          if (quota != null) {
            final subjectKey = entry.candidate.subjectKey.trim();
            final maximum = quota.maxPerSubject[subjectKey];
            if (maximum != null &&
                (usedPerSubject[subjectKey] ?? 0) >= maximum) {
              continue;
            }
          }
          pick(entry);
        }
      }
    }

    for (final entry in scored) {
      if (picked.length >= spec.targetCount) break;
      // 只有启用配额或手工必收时才按 id 去重（都关闭时保持历史行为逐字节不变）。
      if ((quota != null ||
              domainQuota != null ||
              manual.includeIdSet.isNotEmpty) &&
          pickedIds.contains(entry.candidate.questionId)) {
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
      if (domainQuota != null) {
        final primaryDomain =
            domainsByQuestion[entry.candidate.questionId]?.primaryDomain;
        if (primaryDomain != null) {
          final maximum = domainQuota.maxPerDomain[primaryDomain];
          if (maximum != null &&
              (usedPerDomain[primaryDomain] ?? 0) >= maximum) {
            domainBlocked.add(DomainQuotaBlockedQuestion(
              questionId: entry.candidate.questionId,
              domain: primaryDomain,
              domainLimit: maximum,
            ));
            continue;
          }
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

    // 领域汇总/缺口（只在启用领域配额时才算；关闭时三张表都是空）。
    final byDomainCounts = <String, int>{};
    final domainShortfalls = <DomainQuotaShortfall>[];
    if (domainQuota != null) {
      for (final entry in picked) {
        final assignment = domainsByQuestion[entry.candidate.questionId];
        if (assignment == null) continue;
        for (final domain in assignment.allDomains) {
          byDomainCounts[domain] = (byDomainCounts[domain] ?? 0) + 1;
        }
      }
      final availablePerDomain = <String, int>{};
      for (final entry in scored) {
        final primaryDomain =
            domainsByQuestion[entry.candidate.questionId]?.primaryDomain;
        if (primaryDomain == null) continue;
        availablePerDomain[primaryDomain] =
            (availablePerDomain[primaryDomain] ?? 0) + 1;
      }
      final minimumDomains = domainQuota.minPerDomain.keys.toList()..sort();
      for (final domain in minimumDomains) {
        final minimum = domainQuota.minPerDomain[domain]!;
        if (minimum <= 0) continue;
        final selected = usedPerDomain[domain] ?? 0;
        if (selected >= minimum) continue;
        domainShortfalls.add(DomainQuotaShortfall(
          domain: domain,
          minimumCount: minimum,
          selectedCount: selected,
          availableCount: availablePerDomain[domain] ?? 0,
        ));
      }
    }
    final sortedDomainKeys = byDomainCounts.keys.toList()..sort();
    final byDomain = <String, int>{
      for (final domain in sortedDomainKeys) domain: byDomainCounts[domain]!,
    };

    // 每个知识点在过滤后还剩多少候选（缺口解释句里只报真实数量）。
    final availability = <String, int>{};
    for (final entry in scored) {
      for (final point in entry.coveredPoints) {
        availability[point] = (availability[point] ?? 0) + 1;
      }
    }

    final items = <PaperItem>[];
    for (var index = 0; index < picked.length; index++) {
      final entry = picked[index];
      final pointLabel = _labelOf(
        entry.primaryPointId,
        knowledgePointNames,
        knowledgePointTagPaths,
      );
      final reading = readingsById[entry.primaryPointId];
      items.add(
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
          reasonZh: detailedNotes
              ? _detailedReasonZh(
                  itemIndex: index + 1,
                  entry: entry,
                  pointLabel: pointLabel,
                  reading: reading,
                  weights: normalized,
                )
              : _reasonZh(
                  pointId: entry.primaryPointId,
                  pointLabel: pointLabel,
                  zone: entry.zone,
                  reading: reading,
                  matchedPreferredActions: entry.matchedPreferredActions,
                ),
          improvementNote: detailedNotes
              ? _detailedImprovementNote(
                  candidate: entry.candidate,
                  zone: entry.zone,
                  pointLabel: pointLabel,
                )
              : _improvementNote(entry.candidate, entry.zone),
          backgroundZh: detailedNotes
              ? _detailedBackgroundZh(
                  primaryPointId: entry.primaryPointId,
                  matchedKnowledgePointIds: entry.coveredPoints,
                  names: knowledgePointNames,
                  paths: knowledgePointTagPaths,
                )
              : _backgroundZh(
                  entry.primaryPointId,
                  knowledgePointNames,
                  knowledgePointTagPaths,
                ),
          matchedPreferredActions: entry.matchedPreferredActions,
        ),
      );
    }

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

    // 缺口解释句：只在 detailedNotes 时生成（默认空表 → toJson 不出键）。
    final uncoveredNotes = <PaperGapNote>[];
    final deferredNotes = <PaperGapNote>[];
    if (detailedNotes) {
      for (final point in uncovered) {
        final label = _labelOf(
          point,
          knowledgePointNames,
          knowledgePointTagPaths,
        );
        final zone = paperZoneOf(readingsById[point]);
        uncoveredNotes.add(
          PaperGapNote(
            knowledgePointId: point,
            labelZh: label,
            messageZh: '知识点「$label」在${zone.labelZh}，题库里一道候选都没有：'
                '先收这个知识点的题（拍照或组卷网入库），不要用模型生成。',
          ),
        );
      }
      for (final point in deferred) {
        final label = _labelOf(
          point,
          knowledgePointNames,
          knowledgePointTagPaths,
        );
        final zone = paperZoneOf(readingsById[point]);
        final available = availability[point] ?? 0;
        deferredNotes.add(
          PaperGapNote(
            knowledgePointId: point,
            labelZh: label,
            messageZh: '知识点「$label」在${zone.labelZh}，题库里有 $available 道可用候选，'
                '但这轮没排进来（被目标题数或配额挤掉）：把目标题数调大，'
                '或提高该知识点的每题上限。',
          ),
        );
      }
    }

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
      byDomain: Map.unmodifiable(byDomain),
      quotaBlockedByDomain: List.unmodifiable(domainBlocked),
      domainShortfalls: List.unmodifiable(domainShortfalls),
      domainQuota: domainQuota,
      manualSelectionEnabled: manual.enabled,
      manualIncludedCount: manualIncludedCount,
      manualMissingQuestionIds: List.unmodifiable(manualMissing),
      manualSkippedQuestionIds: List.unmodifiable(manualSkipped),
      manualConflictQuestionIds: List.unmodifiable(manual.conflicts),
      uncoveredKnowledgePointNotes: List.unmodifiable(uncoveredNotes),
      deferredKnowledgePointNotes: List.unmodifiable(deferredNotes),
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

  /// 详细版选卷理由（`detailedNotes: true`）：在原有理由后补上**这份卷子真实的**
  /// 排序依据——第几题、需求（来自 zone 读数）、质量分（来源档位 + AI 质量）、
  /// 综合得分与当前权重。数字全部取自 [entry] 与 [weights]，不另外估算。
  static String _detailedReasonZh({
    required int itemIndex,
    required _Scored entry,
    required String pointLabel,
    required KnowledgePointReading? reading,
    required PaperWeights weights,
  }) {
    final base = _reasonZh(
      pointId: entry.primaryPointId,
      pointLabel: pointLabel,
      zone: entry.zone,
      reading: reading,
      matchedPreferredActions: entry.matchedPreferredActions,
    );
    final sourceKey = entry.candidate.sourceLevel.trim();
    final sourceLabel = sourceKey.isEmpty || sourceKey == 'unknown'
        ? '来源未标注'
        : '来源 ${sourceLevelLabel(sourceKey)}';
    return '本卷第 $itemIndex 题。$base这题在这份卷子里的排序依据：'
        '需求 ${_two(entry.need)}（${entry.zone.labelZh}）、'
        '质量分 ${_two(entry.quality)}（$sourceLabel）、'
        '综合得分 ${_two(entry.score)}；'
        '排序权重 需求 ${_two(weights.need)} / 质量 ${_two(weights.quality)} / '
        '难度贴合 ${_two(weights.difficultyFit)}（未标定，见 PAPER_COMPOSER_DESIGN §4）。';
  }

  /// 详细版改进建议（`detailedNotes: true`）：点名它为哪个知识点服务，并给出
  /// 可执行的下一步（把结果记进系统，才会产生下一轮读数）。
  static String _detailedImprovementNote({
    required PaperCandidate candidate,
    required PaperZone zone,
    required String pointLabel,
  }) {
    final base = _improvementNote(candidate, zone);
    return '为知识点「$pointLabel」：$base '
        '下一步：做完把这题的结果记进系统（这一轮会产生下一轮的读数）。';
  }

  /// 详细版知识点背景（`detailedNotes: true`）：除主知识点路径外，列出这道题
  /// 还覆盖了哪些知识点（只列真实挂载，重复与主知识点自身跳过）。
  static String _detailedBackgroundZh({
    required String? primaryPointId,
    required List<String> matchedKnowledgePointIds,
    required Map<String, String> names,
    required Map<String, List<String>> paths,
  }) {
    final base = _backgroundZh(primaryPointId, names, paths);
    final seen = <String>{};
    final primaryKey = (primaryPointId ?? '').trim();
    if (primaryKey.isNotEmpty) seen.add(primaryKey);
    final extras = <String>[];
    for (final id in matchedKnowledgePointIds) {
      final key = id.trim();
      if (key.isEmpty || !seen.add(key)) continue;
      extras.add(_labelOf(key, names, paths));
    }
    if (extras.isEmpty) return base;
    return '$base；本题还覆盖：${extras.join('、')}';
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

/// `PaperSpec` 里的手工指定/排除，归一化之后的样子。
///
/// 归一化口径：id 先 `trim`、丢掉空串、去重；必收顺序与冲突列表按 id 字典序，
/// 保证 `Set` 输入顺序不同也得到同一份卷子。排除集合只做成员判断。
/// `enabled` = 两个集合里任一非 `null`（空集也算启用：输出契约需要如实表达
/// "用户开了这个开关但没点名"，与 `null` 的"没开"区分）。
class _ManualSelection {
  const _ManualSelection({
    required this.enabled,
    required this.includeIds,
    required this.includeIdSet,
    required this.excludeIdSet,
    required this.conflicts,
  });

  factory _ManualSelection.resolve(PaperSpec spec) {
    final rawInclude = spec.manualIncludeQuestionIds;
    final rawExclude = spec.manualExcludeQuestionIds;
    final includeIdSet = _cleanIds(rawInclude);
    final excludeIdSet = _cleanIds(rawExclude);
    final includeIds = includeIdSet.toList()..sort();
    final conflicts = includeIdSet.intersection(excludeIdSet).toList()..sort();
    return _ManualSelection(
      enabled: rawInclude != null || rawExclude != null,
      includeIds: List.unmodifiable(includeIds),
      includeIdSet: Set.unmodifiable(includeIdSet),
      excludeIdSet: Set.unmodifiable(excludeIdSet),
      conflicts: List.unmodifiable(conflicts),
    );
  }

  final bool enabled;

  /// 排好序的必收 id：`targetCount` 装不下时按这个顺序取前若干个。
  final List<String> includeIds;
  final Set<String> includeIdSet;
  final Set<String> excludeIdSet;

  /// 同时出现在必收与排除里的 id（排除生效）。
  final List<String> conflicts;

  static Set<String> _cleanIds(Set<String>? ids) {
    if (ids == null) return const <String>{};
    final cleaned = <String>{};
    for (final id in ids) {
      final trimmed = id.trim();
      if (trimmed.isNotEmpty) cleaned.add(trimmed);
    }
    return cleaned;
  }
}

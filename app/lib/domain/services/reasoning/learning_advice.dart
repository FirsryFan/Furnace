/// 学习建议聚合：把「洞察读数」与「能力动作画像」变成一份确定性的建议清单。
///
/// 为什么需要这一层：§12 的画像与 §14 的洞察都是**读数**（哪里风险高、哪些动作
/// 在链里出现），用户看完还得自己想「那我接下来做什么」。这一层只回答一个问题：
/// **基于现在真有的读数，下一步最该做的一件事是什么？**
///
/// 诚实性规则（与推理层其它读数同一条口径）：
/// 1. **只基于真读数**：练习建议只在某动作的高风险步数达到阈值时才给出，detail 里
///    写清步数 / 题数 / 高风险数；不写「按这个方法肯定能提高」这类没有依据的话。
/// 2. **没有输入就说没有**：空输入返回一条 `noData`，不虚构题数、不编「暂无异常」。
/// 3. **未知动作不吞**：词表外的动作会单独给一条 `reviewVocabulary` 建议，并说明
///    「词表还不认识它们，不是没问题」——词表会变，静默忽略会掩盖契约漂移。
/// 4. **不落库**：本层是派生计算，输入改变时重新 [LearningAdvicePlan.build] 即可。
///
/// 这一层不读数据库、不读时钟、不依赖 Flutter；`profile` 与 `insights` 都由调用方
/// 现算后传入。
library;

import 'capability_profile.dart';
import 'chain_insights.dart';

/// 建议的种类。枚举顺序也是同一优先带内的稳定排序依据。
enum LearningAdviceKind {
  /// 该练某个高风险动作：某动作的高风险步数达到阈值。
  practiceAction,

  /// 有题还没有解题链：先去题目详情页按一次「AI 解题」。
  collectChains,

  /// 出现词表外动作：考虑扩充自定义词表。
  reviewVocabulary,

  /// 数据健康、没有达到练习阈值的动作：继续按当前节奏练。
  keepGoing,

  /// 还没有任何链或读数：先制造第一份数据。
  noData,
}

/// 一条学习建议。
class LearningAdvice {
  LearningAdvice({
    required this.kind,
    required this.priority,
    required this.titleZh,
    required this.detailZh,
    this.actionType,
    this.actionLabelZh,
    this.questionCount,
    this.stepCount,
    this.highRiskStepCount,
    List<String> knowledgePointIds = const <String>[],
  }) : knowledgePointIds = List<String>.unmodifiable(knowledgePointIds);

  /// 建议种类。
  final LearningAdviceKind kind;

  /// 优先级：小的在前。同一个建议带里编号越小越该先做（见 [LearningAdvicePlan.build]）。
  final int priority;

  /// 一行标题（中文）。
  final String titleZh;

  /// 给用户看的理由；只写真实的步数 / 题数 / 高风险数，不写没有依据的承诺。
  final String detailZh;

  /// 关联的能力动作 key；不针对单个动作的建议为 null。
  final String? actionType;

  /// 关联能力动作的展示名（词表外时就是原串）；不针对单个动作时为 null。
  final String? actionLabelZh;

  /// 涉及的题目数；**没有读数时是 null**，不拿 0 冒充「没有题」。
  final int? questionCount;

  /// 涉及的步骤数；没有读数时是 null。
  final int? stepCount;

  /// 其中被判为高风险的步骤数；没有风险读数时是 null。
  final int? highRiskStepCount;

  /// 关联的知识点 id 列表（不可变）。
  ///
  /// 当前**恒为空**：§14 的洞察聚合层没有按「动作 × 知识点」交叉的读数，编造关联
  /// 比不填更坏。等交叉读数落地后再由调用方填进来。
  final List<String> knowledgePointIds;

  /// 序列化（字段全部 snake_case）。
  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind.name,
        'priority': priority,
        'title_zh': titleZh,
        'detail_zh': detailZh,
        'action_type': actionType,
        'action_label_zh': actionLabelZh,
        'question_count': questionCount,
        'step_count': stepCount,
        'high_risk_step_count': highRiskStepCount,
        'knowledge_point_ids': knowledgePointIds,
      };
}

/// 一次学习建议计算的结果（不可变、纯数据）。
class LearningAdvicePlan {
  LearningAdvicePlan._(List<LearningAdvice> advices)
      : advices = List<LearningAdvice>.unmodifiable(advices);

  /// 空结果。`build` 在空输入时会返回一条 `noData`，不会返回它；它用于调用方
  /// 表示「本次不展示建议」这类显式空态。
  static LearningAdvicePlan empty() =>
      LearningAdvicePlan._(const <LearningAdvice>[]);

  /// 按顺序排好的建议（priority 升序 → kind 枚举序 → actionType 字典序）。
  final List<LearningAdvice> advices;

  /// 建议条数。
  int get length => advices.length;

  /// 是否没有建议。
  bool get isEmpty => advices.isEmpty;

  /// 是否有建议。
  bool get isNotEmpty => advices.isNotEmpty;

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
        'advice_count': advices.length,
        'is_empty': isEmpty,
        'advices': <Object?>[for (final advice in advices) advice.toJson()],
      };

  /// 练习建议的优先带起点；带内按「高风险步数降序」编号，保证最该练的排前面。
  static const int _practicePriorityBase = 100;

  /// 「有题缺链」的优先带。
  static const int _collectPriority = 200;

  /// 「扩充词表」的优先带。
  static const int _reviewPriority = 300;

  /// 「继续练」的优先带。
  static const int _keepGoingPriority = 400;

  /// 「没有数据」的优先带。
  static const int _noDataPriority = 500;

  /// 带内最多 100 个练习建议（rank 0..99），超出后共用一个 priority，靠
  /// kind / actionType 兜底排序。
  static const int _maxPracticeRank = 99;

  /// 生成建议清单。
  ///
  /// [insights]：§14 的洞察读数（必需；调用方用当前词表 overlay 聚合后再传）。
  /// [profile]：§12 的能力动作画像读数（可选：画像比洞察窄，只作为补充证据）。
  /// [highRiskMinSteps]：至少几个高风险步才给练习建议；默认 3。小于 1 按 1 处理
  /// （0 会让任何动作都够格，等于没有阈值）。
  /// [maxAdvices]：最多返回几条；默认 5。小于 1 按 1 处理，保证有数据时不会返回
  /// 空白计划（调用方要空态请用 [LearningAdvicePlan.empty]）。
  /// [corpusQuestionCount]：题库总题数。**可选且默认 null**：调用方拿不到就传 null，
  /// 本层不会产出 `collectChains`、也不会虚构题数；传了才用它和
  /// [ChainInsights.questionCount] 比较，判断还有多少题没有链。负数按 0 处理。
  ///
  /// 排序：priority 升序 → [LearningAdviceKind] 枚举序 → actionType 字典序
  /// （null 按空串）→ titleZh 字典序（最后兜底，保证同输入同输出）。
  static LearningAdvicePlan build({
    required ChainInsights insights,
    List<CapabilityReading> profile = const <CapabilityReading>[],
    int highRiskMinSteps = 3,
    int maxAdvices = 5,
    int? corpusQuestionCount,
  }) {
    final minSteps = highRiskMinSteps < 1 ? 1 : highRiskMinSteps;
    final limit = maxAdvices < 1 ? 1 : maxAdvices;
    final corpus = corpusQuestionCount == null
        ? null
        : (corpusQuestionCount < 0 ? 0 : corpusQuestionCount);

    final advices = <LearningAdvice>[];
    final practiceCandidates = _practiceCandidates(
      insights: insights,
      profile: profile,
      minSteps: minSteps,
    );
    for (var rank = 0; rank < practiceCandidates.length; rank++) {
      advices.add(
        _practiceAdvice(
          practiceCandidates[rank],
          priority: _practicePriorityBase +
              (rank > _maxPracticeRank ? _maxPracticeRank : rank),
          minSteps: minSteps,
        ),
      );
    }

    final unknownActions = insights.unknownActions;
    if (unknownActions.isNotEmpty) {
      advices.add(_reviewAdvice(unknownActions));
    }

    final hasCollectChains = corpus != null && corpus > insights.questionCount;
    if (hasCollectChains) {
      advices.add(
        _collectAdvice(corpus: corpus, questionCount: insights.questionCount),
      );
    }

    final hasReadings = insights.isNotEmpty || profile.isNotEmpty;
    if (practiceCandidates.isEmpty &&
        unknownActions.isEmpty &&
        !hasCollectChains &&
        hasReadings) {
      advices.add(_keepGoingAdvice(
          insights: insights, profile: profile, minSteps: minSteps));
    }

    if (advices.isEmpty) {
      advices.add(_noDataAdvice(corpus: corpus));
    }

    advices.sort(_compareAdvices);
    final kept = advices.length > limit ? advices.sublist(0, limit) : advices;
    return LearningAdvicePlan._(kept);
  }

  static List<_PracticeCandidate> _practiceCandidates({
    required ChainInsights insights,
    required List<CapabilityReading> profile,
    required int minSteps,
  }) {
    final seen = <String>{};
    final candidates = <_PracticeCandidate>[];
    for (final action in insights.actions) {
      // 未知动作不进练习建议：词表都不认识它，详情页也没有可展示的中文名。
      if (!action.known || action.highRiskStepCount < minSteps) {
        continue;
      }
      if (!seen.add(action.actionType)) {
        continue;
      }
      candidates.add(
        _PracticeCandidate(
          actionType: action.actionType,
          label: action.label,
          questionCount: action.questionCount,
          stepCount: action.stepCount,
          highRiskStepCount: action.highRiskStepCount,
        ),
      );
    }
    for (final reading in profile) {
      final key = reading.actionType.trim();
      if (!reading.known || key.isEmpty || reading.riskyStepCount < minSteps) {
        continue;
      }
      if (!seen.add(key)) {
        // 洞察读数更全（有题数），同一个动作不重复给两条建议。
        continue;
      }
      candidates.add(
        _PracticeCandidate(
          actionType: key,
          label: reading.label,
          questionCount: null,
          stepCount: reading.stepCount,
          highRiskStepCount: reading.riskyStepCount,
        ),
      );
    }
    candidates.sort(_comparePracticeCandidates);
    return candidates;
  }

  static int _comparePracticeCandidates(
    _PracticeCandidate a,
    _PracticeCandidate b,
  ) {
    final byHighRisk = b.highRiskStepCount.compareTo(a.highRiskStepCount);
    if (byHighRisk != 0) {
      return byHighRisk;
    }
    final aQuestions = a.questionCount;
    final bQuestions = b.questionCount;
    if (aQuestions != bQuestions) {
      if (aQuestions == null) {
        return 1;
      }
      if (bQuestions == null) {
        return -1;
      }
      return bQuestions.compareTo(aQuestions);
    }
    final bySteps = b.stepCount.compareTo(a.stepCount);
    if (bySteps != 0) {
      return bySteps;
    }
    return a.actionType.compareTo(b.actionType);
  }

  static LearningAdvice _practiceAdvice(
    _PracticeCandidate candidate, {
    required int priority,
    required int minSteps,
  }) {
    final facts = candidate.questionCount == null
        ? '「${candidate.label}」共 ${candidate.stepCount} 步，其中 '
            '${candidate.highRiskStepCount} 步高风险（阈值 $minSteps 步），题目数暂无读数'
        : '「${candidate.label}」共 ${candidate.stepCount} 步、'
            '${candidate.questionCount} 道题，其中 '
            '${candidate.highRiskStepCount} 步高风险（阈值 $minSteps 步）';
    return LearningAdvice(
      kind: LearningAdviceKind.practiceAction,
      priority: priority,
      titleZh: '练「${candidate.label}」',
      detailZh: '$facts。建议找同类题专门练这一步，做完用自检确认是否还卡；'
          '这不保证分数一定提高，只说明这是当前读数里达到练习阈值的动作。',
      actionType: candidate.actionType,
      actionLabelZh: candidate.label,
      questionCount: candidate.questionCount,
      stepCount: candidate.stepCount,
      highRiskStepCount: candidate.highRiskStepCount,
    );
  }

  static LearningAdvice _reviewAdvice(List<ChainActionInsight> unknownActions) {
    final shown = unknownActions
        .take(5)
        .map((action) => '「${action.actionType}」')
        .join('、');
    final total = unknownActions.length;
    final stepCount =
        unknownActions.fold<int>(0, (sum, action) => sum + action.stepCount);
    final suffix = total > 5 ? '（只列前 5 个，共 $total 个）' : '（共 $total 个）';
    return LearningAdvice(
      kind: LearningAdviceKind.reviewVocabulary,
      priority: _reviewPriority,
      titleZh: '扩充能力动作词表',
      detailZh: '这次读数里有 $total 个动作当前词表还不认识：$shown$suffix。'
          '这不是没问题：词表不认识它们，这些步骤无法参与画像与建议。'
          '考虑把它们加进自定义能力动作词表；加完之后这些读数才会被按动作聚合。',
      stepCount: stepCount,
    );
  }

  static LearningAdvice _collectAdvice({
    required int corpus,
    required int questionCount,
  }) {
    final detail = questionCount == 0
        ? '题库里有 $corpus 道题，但当前还没有任何解题链。没有链就没有步骤读数，'
            '建议去题目详情页按一次「AI 解题」，链和步骤读数会自动进入建议。'
        : '题库里有 $corpus 道题，当前洞察只覆盖 $questionCount 道题，'
            '还有 ${corpus - questionCount} 道题没有解题链。'
            '建议去这些题的详情页按一次「AI 解题」，链和步骤读数会自动进入建议。';
    return LearningAdvice(
      kind: LearningAdviceKind.collectChains,
      priority: _collectPriority,
      titleZh: '给还没有解题链的题按一次「AI 解题」',
      detailZh: detail,
      questionCount: corpus,
    );
  }

  static LearningAdvice _keepGoingAdvice({
    required ChainInsights insights,
    required List<CapabilityReading> profile,
    required int minSteps,
  }) {
    final detail = insights.isNotEmpty
        ? '已有 ${insights.chainCount} 条链、${insights.stepCount} 步读数、'
            '${insights.questionCount} 道题，但没有任何动作的高风险步数达到 '
            '$minSteps 步，也没有词表外动作。继续按当前节奏练；新链会自动进入下一轮建议。'
        : '能力动作画像里已有 ${profile.length} 个动作的读数，但没有任何动作的高风险步数'
            '达到 $minSteps 步，也没有词表外动作。继续按当前节奏练。';
    return LearningAdvice(
      kind: LearningAdviceKind.keepGoing,
      priority: _keepGoingPriority,
      titleZh: '数据健康，继续按当前节奏练',
      detailZh: detail,
    );
  }

  static LearningAdvice _noDataAdvice({required int? corpus}) {
    final detail = corpus == null
        ? '还没有任何思维链或能力动作读数，也没有传题库题数（无法判断有多少题缺链）。'
            '先去题目详情页按一次「AI 解题」，再回来看建议。'
        : corpus == 0
            ? '还没有任何思维链或能力动作读数，题库里也还没有题目。'
                '先去题库加题，再在题目详情页按一次「AI 解题」。'
            : '还没有任何思维链或能力动作读数。先去题目详情页按一次「AI 解题」，再回来看建议。';
    return LearningAdvice(
      kind: LearningAdviceKind.noData,
      priority: _noDataPriority,
      titleZh: '还没有学习数据',
      detailZh: detail,
    );
  }

  static int _compareAdvices(LearningAdvice a, LearningAdvice b) {
    final byPriority = a.priority.compareTo(b.priority);
    if (byPriority != 0) {
      return byPriority;
    }
    final byKind = a.kind.index.compareTo(b.kind.index);
    if (byKind != 0) {
      return byKind;
    }
    final byAction = (a.actionType ?? '').compareTo(b.actionType ?? '');
    if (byAction != 0) {
      return byAction;
    }
    return a.titleZh.compareTo(b.titleZh);
  }
}

class _PracticeCandidate {
  const _PracticeCandidate({
    required this.actionType,
    required this.label,
    required this.questionCount,
    required this.stepCount,
    required this.highRiskStepCount,
  });

  final String actionType;
  final String label;
  final int? questionCount;
  final int stepCount;
  final int highRiskStepCount;
}

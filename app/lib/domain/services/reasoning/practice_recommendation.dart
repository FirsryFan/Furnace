/// 推理层：下一步练哪几道题——确定性配题推荐（纯逻辑）。
///
/// 输入三样东西：§14 的思维链洞察读数（[ChainInsights]）、§15 的学习建议
/// （[LearningAdvicePlan]）和一批题目候选投影（[PracticeQuestionCandidate]）；
/// 输出一份可解释的推荐计划（[PracticeRecommendationPlan]）。本层不读文件、
/// 不碰 DB、不调模型、不 import Flutter，只做确定性打分与排序，方便单测和
/// 后续页面/provider 接线。
///
/// 口径（写给接线方）：
/// - 偏好只来自真实读数：学习建议里 practiceAction 的 actionType 与
///   knowledgePointIds，加上洞察里 highRiskByKnowledgePoint 的卡点知识点。
///   调用方显式传 preferredActionTypes / preferredKnowledgePointIds 时覆盖
///   上述默认（显式传空集 = 明确要求「不按动作/知识点偏好」，不等于没传）。
/// - 未知动作补习只在 includeUnknownActionScaffold 为 true 且候选动作命中
///   insights.unknownActions 时生效；关掉后既不加分也不产生理由。
/// - 难度分只在目标难度与题目难度都是有限数时计算；NaN / ±inf 一律当作
///   「没有读数」，不参与打分、不产生偏难/偏易理由。分数始终是有限 double。
/// - 缺解析 / 缺答案会显式扣分并留下理由（missingSolution / missingAnswer），
///   不静默吞掉；答案与解析都齐时留下 upToDate 理由（资料完整）。
/// - 排序完全确定：分数降序 → 命中动作数降序 → 题号（null 最后）升序 →
///   questionId 升序。截断到 maxQuestions 后，剩余题目 id 全部进
///   skippedQuestionIds，不静默消失；maxQuestions <= 0 时推荐为空、全部跳过。
/// - 空输入 / 空候选不抛异常，返回 isEmpty 为 true 的空计划。
/// - 候选里 aiQuality、subjectKey、sourceLevel 是给后续标定预留的字段，
///   当前不参与打分（保留是为了不反复改调用方投影代码）。
library;

import 'chain_insights.dart';
import 'learning_advice.dart';

/// 单题被推荐的理由。
///
/// 枚举声明顺序就是 [PracticeRecommendation.reasons] 的输出顺序：
/// 正向命中 → 资料完整 → 缺失提示 → 难度提示 → 无关联。
enum PracticeRecommendationReason {
  /// 命中学习建议里的练习动作。
  matchedAdviceAction,

  /// 命中高风险（卡点）知识点。
  matchedHighRiskKnowledgePoint,

  /// 命中词表还不认识的动作，先补基础（includeUnknownActionScaffold 关闭
  /// 时不产生此理由）。
  unknownActionScaffold,

  /// 答案与解析都齐全，题目资料是最新的。
  upToDate,

  /// 缺解析（已扣分）。
  missingSolution,

  /// 缺答案（已扣分）。
  missingAnswer,

  /// 难度高于目标（只提示，不额外扣分）。
  tooHard,

  /// 难度低于目标（只提示，不额外扣分）。
  tooEasy,

  /// 没有命中任何动作 / 知识点 / 未知动作补习偏好，只是被请求进来。
  unrelated,
}

/// 配题推荐的输入：一道题目的轻量投影（由调用方从题库行模型拼出）。
class PracticeQuestionCandidate {
  const PracticeQuestionCandidate({
    required this.questionId,
    this.serialNo,
    this.subjectKey,
    this.sourceLevel,
    this.difficulty,
    this.aiQuality,
    this.knowledgePointIds = const <String>[],
    this.actionTypes = const <String>[],
    this.hasAnswer,
    this.hasSolution,
  });

  /// 题目 id；trim 后为空串的候选会被丢弃（不进 requestCount，也不进
  /// skippedQuestionIds）。
  final String questionId;

  /// 展示用题号（题库序号）；null 表示没有题号，排序时排在最后。
  final int? serialNo;

  /// 学科键（当前不参与打分，后续标定用）。
  final String? subjectKey;

  /// 来源层级（当前不参与打分，后续标定用）。
  final String? sourceLevel;

  /// 难度读数；非有限数（NaN / ±inf）按「没有读数」处理。
  final double? difficulty;

  /// AI 质量读数（当前不参与打分，后续标定用）。
  final double? aiQuality;

  /// 本题涉及的知识点；空串 / 空白项会被忽略。
  final List<String> knowledgePointIds;

  /// 本题可用的能力动作 key；空串 / 空白项会被忽略。
  final List<String> actionTypes;

  /// 是否有答案；null = 未知，不扣分也不提示。
  final bool? hasAnswer;

  /// 是否有解析；null = 未知，不扣分也不提示。
  final bool? hasSolution;
}

/// 单题推荐结果。
class PracticeRecommendation {
  const PracticeRecommendation({
    required this.questionId,
    required this.score,
    required this.rank,
    required this.reasons,
    required this.matchedActionTypes,
    required this.matchedKnowledgePointIds,
    this.serialNo,
  });

  /// 题目 id（已 trim）。
  final String questionId;

  /// 展示用题号，原样从候选带过来。
  final int? serialNo;

  /// 确定性得分（有限 double；可能为负，因为缺解析会扣分）。
  final double score;

  /// 名次，从 1 起。
  final int rank;

  /// 理由，按 [PracticeRecommendationReason] 枚举声明顺序排列。
  final List<PracticeRecommendationReason> reasons;

  /// 命中的偏好动作 key，按候选 actionTypes 的给出顺序去重。
  final List<String> matchedActionTypes;

  /// 命中的偏好知识点 id，按候选 knowledgePointIds 的给出顺序去重。
  final List<String> matchedKnowledgePointIds;

  /// 固定键序的 JSON：question_id, serial_no, score, rank, reasons,
  /// matched_action_types, matched_knowledge_point_ids。
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'question_id': questionId,
      'serial_no': serialNo,
      'score': score,
      'rank': rank,
      'reasons': <String>[for (final reason in reasons) reason.name],
      'matched_action_types': List<String>.of(matchedActionTypes),
      'matched_knowledge_point_ids': List<String>.of(matchedKnowledgePointIds),
    };
  }
}

/// 配题推荐计划。
class PracticeRecommendationPlan {
  PracticeRecommendationPlan._({
    required this.recommendations,
    required this.skippedQuestionIds,
    required this.requestCount,
    required this.maxQuestions,
  });

  /// 默认最多推荐几道题。
  static const int defaultMaxQuestions = 10;

  /// 每个命中偏好动作的分值。
  static const double adviceActionScore = 3.0;

  /// 每个命中卡点知识点的分值。
  static const double highRiskKnowledgePointScore = 2.0;

  /// 命中未知动作、需要补习时的分值（可被 includeUnknownActionScaffold 关闭）。
  static const double unknownActionScaffoldScore = 1.5;

  /// 难度与目标完全一致时的最大难度分。
  static const double difficultyMatchScore = 2.0;

  /// 难度贴近的容差：差值不超过它就不提示偏难/偏易。
  static const double difficultyTolerance = 0.5;

  /// 缺解析的扣分。
  static const double missingSolutionPenalty = 1.5;

  /// 缺答案的扣分。
  static const double missingAnswerPenalty = 1.0;

  /// 生成配题推荐计划。
  ///
  /// [insights]：§14 的洞察读数（调用方用当前词表 overlay 聚合后再传）。
  /// [advicePlan]：§15 的学习建议；只读其中 practiceAction 建议的 actionType
  /// 与 knowledgePointIds。没有练习建议时，知识点偏好退回
  /// insights.highRiskByKnowledgePoint。
  /// [candidates]：候选题目投影；questionId trim 后为空的候选直接丢弃。
  /// [maxQuestions]：最多返回几道；小于 0 按 0 处理（推荐为空、全部进
  /// skippedQuestionIds），默认 [defaultMaxQuestions]。
  /// [preferredActionTypes]：显式动作偏好集合；传 null = 用学习建议里的
  /// 练习动作。传空集 = 明确要求没有动作偏好（不是「不过滤」）。
  /// [preferredKnowledgePointIds]：显式知识点偏好；传 null = 学习建议知识点
  /// 并上洞察里的卡点知识点。传空集 = 明确要求没有知识点偏好。
  /// [targetDifficulty]：目标难度；NaN / ±inf 按没有目标处理。
  /// [includeUnknownActionScaffold]：是否给「词表不认识的动作」加分并标记
  /// unknownActionScaffold。
  ///
  /// 排序：score 降序 → matchedActionTypes 长度降序 → serialNo（null 最后）
  /// 升序 → questionId 升序。同 questionId 的候选去重，保留分数更高者；
  /// 同分保留先出现者。requestCount 是去重后有效候选数。
  static PracticeRecommendationPlan build({
    required ChainInsights insights,
    required LearningAdvicePlan advicePlan,
    required Iterable<PracticeQuestionCandidate> candidates,
    int maxQuestions = defaultMaxQuestions,
    Set<String>? preferredActionTypes,
    Set<String>? preferredKnowledgePointIds,
    double? targetDifficulty,
    bool includeUnknownActionScaffold = true,
  }) {
    final limit = maxQuestions < 0 ? 0 : maxQuestions;

    final Set<String> actionPreferences = _normalizeKeys(
      preferredActionTypes ?? _adviceActionTypes(advicePlan),
    ).toSet();
    final Set<String> knowledgePreferences = _normalizeKeys(
      preferredKnowledgePointIds ??
          <String>[
            ..._adviceKnowledgePointIds(advicePlan),
            for (final group in insights.highRiskByKnowledgePoint) group.key,
          ],
    ).toSet();
    final Set<String> unknownActions = _normalizeKeys(
      <String>[for (final action in insights.unknownActions) action.actionType],
    ).toSet();

    final scoredById = <String, _ScoredCandidate>{};
    for (final candidate in candidates) {
      final questionId = candidate.questionId.trim();
      if (questionId.isEmpty) {
        continue;
      }
      final scored = _score(
        candidate: candidate,
        questionId: questionId,
        actionPreferences: actionPreferences,
        knowledgePreferences: knowledgePreferences,
        unknownActions: unknownActions,
        targetDifficulty: targetDifficulty,
        includeUnknownActionScaffold: includeUnknownActionScaffold,
      );
      final existing = scoredById[questionId];
      if (existing == null || scored.score > existing.score) {
        scoredById[questionId] = scored;
      }
    }

    final ordered = scoredById.values.toList()..sort(_compareScored);
    final recommended =
        ordered.length > limit ? ordered.sublist(0, limit) : ordered;
    final skipped = ordered.length > limit
        ? ordered.sublist(limit)
        : const <_ScoredCandidate>[];

    return PracticeRecommendationPlan._(
      recommendations:
          List<PracticeRecommendation>.unmodifiable(<PracticeRecommendation>[
        for (var i = 0; i < recommended.length; i++)
          _toRecommendation(recommended[i], rank: i + 1),
      ]),
      skippedQuestionIds: List<String>.unmodifiable(<String>[
        for (final candidate in skipped) candidate.questionId,
      ]),
      requestCount: scoredById.length,
      maxQuestions: limit,
    );
  }

  /// 推荐结果，按 [PracticeRecommendation.rank] 升序。
  final List<PracticeRecommendation> recommendations;

  /// 因为 maxQuestions 截断而没进推荐的题目 id，保持与推荐相同的排序；
  /// questionId trim 后为空的候选不会出现在这里（它们一开始就被丢弃）。
  final List<String> skippedQuestionIds;

  /// 去重后的有效候选数（即打分过的题目数），不是传入的原始条数。
  final int requestCount;

  /// 生效的推荐上限（负数已被夹成 0）。
  final int maxQuestions;

  /// 是否没有任何推荐（候选为空、全部无效或 maxQuestions 为 0 时都为 true）。
  bool get isEmpty => recommendations.isEmpty;

  /// 是否至少有一条推荐。
  bool get isNotEmpty => recommendations.isNotEmpty;

  /// 被截断的题目数量。
  int get skippedCount => skippedQuestionIds.length;

  /// 固定键序的 JSON：recommendation_count, skipped_count, request_count,
  /// is_empty, max_questions, recommendations, skipped_question_ids。
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'recommendation_count': recommendations.length,
      'skipped_count': skippedQuestionIds.length,
      'request_count': requestCount,
      'is_empty': isEmpty,
      'max_questions': maxQuestions,
      'recommendations': <Object?>[
        for (final recommendation in recommendations) recommendation.toJson(),
      ],
      'skipped_question_ids': List<String>.of(skippedQuestionIds),
    };
  }

  static _ScoredCandidate _score({
    required PracticeQuestionCandidate candidate,
    required String questionId,
    required Set<String> actionPreferences,
    required Set<String> knowledgePreferences,
    required Set<String> unknownActions,
    required double? targetDifficulty,
    required bool includeUnknownActionScaffold,
  }) {
    final actions = _normalizeKeys(candidate.actionTypes);
    final knowledgePoints = _normalizeKeys(candidate.knowledgePointIds);

    final matchedActions = <String>[
      for (final action in actions)
        if (actionPreferences.contains(action)) action,
    ];
    final matchedKnowledgePoints = <String>[
      for (final knowledgePoint in knowledgePoints)
        if (knowledgePreferences.contains(knowledgePoint)) knowledgePoint,
    ];
    final matchedUnknown = includeUnknownActionScaffold
        ? <String>[
            for (final action in actions)
              if (unknownActions.contains(action)) action,
          ]
        : const <String>[];
    final hasUnknownScaffold = matchedUnknown.isNotEmpty;

    var score = matchedActions.length * adviceActionScore;
    score += matchedKnowledgePoints.length * highRiskKnowledgePointScore;
    if (hasUnknownScaffold) {
      score += unknownActionScaffoldScore;
    }

    final target = _finiteOrNull(targetDifficulty);
    final difficulty = _finiteOrNull(candidate.difficulty);
    var tooHard = false;
    var tooEasy = false;
    if (target != null && difficulty != null) {
      final distance = (difficulty - target).abs();
      final difficultyScore = (difficultyMatchScore - distance)
          .clamp(0.0, difficultyMatchScore)
          .toDouble();
      score += difficultyScore;
      if (distance > difficultyTolerance) {
        if (difficulty > target) {
          tooHard = true;
        } else if (difficulty < target) {
          tooEasy = true;
        }
      }
    }

    final missingSolution = candidate.hasSolution == false;
    final missingAnswer = candidate.hasAnswer == false;
    if (missingSolution) {
      score -= missingSolutionPenalty;
    }
    if (missingAnswer) {
      score -= missingAnswerPenalty;
    }

    final hasPositiveMatch = matchedActions.isNotEmpty ||
        matchedKnowledgePoints.isNotEmpty ||
        hasUnknownScaffold;

    final reasons = <PracticeRecommendationReason>[
      if (matchedActions.isNotEmpty)
        PracticeRecommendationReason.matchedAdviceAction,
      if (matchedKnowledgePoints.isNotEmpty)
        PracticeRecommendationReason.matchedHighRiskKnowledgePoint,
      if (hasUnknownScaffold)
        PracticeRecommendationReason.unknownActionScaffold,
      if (candidate.hasAnswer == true && candidate.hasSolution == true)
        PracticeRecommendationReason.upToDate,
      if (missingSolution) PracticeRecommendationReason.missingSolution,
      if (missingAnswer) PracticeRecommendationReason.missingAnswer,
      if (tooHard) PracticeRecommendationReason.tooHard,
      if (tooEasy) PracticeRecommendationReason.tooEasy,
      if (!hasPositiveMatch) PracticeRecommendationReason.unrelated,
    ];

    return _ScoredCandidate(
      questionId: questionId,
      serialNo: candidate.serialNo,
      score: score,
      reasons: List<PracticeRecommendationReason>.unmodifiable(reasons),
      matchedActionTypes: List<String>.unmodifiable(matchedActions),
      matchedKnowledgePointIds:
          List<String>.unmodifiable(matchedKnowledgePoints),
    );
  }

  static PracticeRecommendation _toRecommendation(
    _ScoredCandidate scored, {
    required int rank,
  }) {
    return PracticeRecommendation(
      questionId: scored.questionId,
      serialNo: scored.serialNo,
      score: scored.score,
      rank: rank,
      reasons: scored.reasons,
      matchedActionTypes: scored.matchedActionTypes,
      matchedKnowledgePointIds: scored.matchedKnowledgePointIds,
    );
  }

  static int _compareScored(_ScoredCandidate a, _ScoredCandidate b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) {
      return byScore;
    }
    final byMatchedActions =
        b.matchedActionTypes.length.compareTo(a.matchedActionTypes.length);
    if (byMatchedActions != 0) {
      return byMatchedActions;
    }
    final aSerial = a.serialNo;
    final bSerial = b.serialNo;
    if (aSerial != bSerial) {
      if (aSerial == null) {
        return 1;
      }
      if (bSerial == null) {
        return -1;
      }
      final bySerial = aSerial.compareTo(bSerial);
      if (bySerial != 0) {
        return bySerial;
      }
    }
    return a.questionId.compareTo(b.questionId);
  }

  static Iterable<String> _adviceActionTypes(LearningAdvicePlan plan) sync* {
    for (final advice in plan.advices) {
      if (advice.kind != LearningAdviceKind.practiceAction) {
        continue;
      }
      final actionType = advice.actionType?.trim();
      if (actionType == null || actionType.isEmpty) {
        continue;
      }
      yield actionType;
    }
  }

  static Iterable<String> _adviceKnowledgePointIds(
      LearningAdvicePlan plan) sync* {
    for (final advice in plan.advices) {
      if (advice.kind != LearningAdviceKind.practiceAction) {
        continue;
      }
      for (final knowledgePointId in advice.knowledgePointIds) {
        yield knowledgePointId;
      }
    }
  }

  /// trim、去空、按出现顺序去重；匹配时大小写敏感（词表 key 约定为小写蛇形）。
  static List<String> _normalizeKeys(Iterable<String> source) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in source) {
      final key = raw.trim();
      if (key.isEmpty || !seen.add(key)) {
        continue;
      }
      result.add(key);
    }
    return result;
  }

  static double? _finiteOrNull(double? value) {
    if (value == null || !value.isFinite) {
      return null;
    }
    return value;
  }
}

/// 中间态：候选 + 已算好的分数与命中集合。
class _ScoredCandidate {
  const _ScoredCandidate({
    required this.questionId,
    required this.serialNo,
    required this.score,
    required this.reasons,
    required this.matchedActionTypes,
    required this.matchedKnowledgePointIds,
  });

  final String questionId;
  final int? serialNo;
  final double score;
  final List<PracticeRecommendationReason> reasons;
  final List<String> matchedActionTypes;
  final List<String> matchedKnowledgePointIds;
}

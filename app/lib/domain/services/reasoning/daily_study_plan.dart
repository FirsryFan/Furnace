/// 推理层：今日学习计划生成——把「洞察读数 + 学习建议 + 配题推荐 + 到期卡片」
/// 合成一份确定性的「今天做什么」计划（纯逻辑）。
///
/// 为什么需要这一层：§14 的洞察回答「哪里风险高」，§15 的建议回答「下一步最该
/// 做什么」，§22 的配题回答「练哪几道」；用户真正需要的是把它们排进当天有限的
/// 时间里。这一层只做排序、预算分配与中文文案，不读数据库、不读时钟、不调模型、
/// 不 import Flutter；输入全部由调用方现算后传入（到期卡片数量也由调用方注入）。
///
/// 诚实性规则（与推理层其它读数同一条口径）：
/// 1. **只排真有的东西**：练习步骤只在配题推荐真的给出推荐时生成；学习建议里有
///    practiceAction 但没有推荐时不会凭空造练习步骤。
/// 2. **没有数据就说没有**：没有任何证据时返回单条 noData 步骤（0 分钟），
///    不虚构题数 / 知识点 / 计划。
/// 3. **未知动作不写练习步骤**：词表外动作由洞察的 unknownActions 单独给一条
///    reviewVocabulary 步骤，练习步骤只来自配题推荐。
/// 4. **缺链信号不虚构**：collectChains 步骤只来自学习建议里已有的 collectChains
///    建议（调用方传了 corpusQuestionCount 时才会出现）；本层不拿
///    insights.chainCount 去猜题库总数。
/// 5. **预算如实**：所有步骤的 estimatedMinutes 之和不超过 dailyMinutes；
///    放不进预算或超过 maxSteps 的候选步骤计入 skippedStepCount，不静默消失。
/// 6. **确定性**：不读时钟、不随机、不依赖 Map 迭代顺序；同一输入两次调用结果相同。
///
/// 优先级（priority 小的先做）：复习到期卡片 100 → 练习配题 200 → 补齐思维链 300
/// → 补能力动作词表 400 → 继续保持 500 → 没有数据 600。
///
/// 自然时长：到期卡片 ceil(dueCardCount / 2) 分钟；练习每道题 2 分钟；补齐
/// 思维链 5 分钟；补词表 3 分钟；继续保持 1 分钟；没有数据 0 分钟。预算不够时，
/// 当天最后一步可以使用剩下的 1 分钟以上时间：到期卡片按 min(剩余, 自然) 截断，
/// 练习按剩余预算缩减题数（缩到 0 道就跳过），其它步骤放不下时用剩余分钟作为
/// 最后一步；剩余分钟为 0 的候选一律跳过。
library;

import 'chain_insights.dart';
import 'learning_advice.dart';
import 'practice_recommendation.dart';

/// 计划里的一步属于哪一类。枚举声明顺序只用于同优先级兜底排序；
/// 实际优先级由 [DailyStudyPlan.build] 分配的数字决定。
enum DailyPlanStepKind {
  /// 练习配题推荐里的题（每道约 2 分钟）。
  practiceQuestions('练习配题推荐'),

  /// 复习到期卡片（间隔重复队列）。
  reviewDueCards('复习到期卡片'),

  /// 补齐没有思维链的题，后续洞察 / 建议才有依据。
  collectChains('补齐思维链'),

  /// 补能力动作词表：把词表还不认识的动作收进去。
  reviewVocabulary('补能力动作词表'),

  /// 数据健康、没有新的高风险点：按当前节奏继续。
  keepGoing('继续保持'),

  /// 没有任何可用数据：如实说今天没有可依据的数据。
  noData('今天没有可依据的数据');

  const DailyPlanStepKind(this.labelZh);

  /// 中文展示名。
  final String labelZh;
}

/// 今日计划里的一步（不可变、纯数据）。
class DailyPlanStep {
  DailyPlanStep({
    required this.kind,
    required this.priority,
    required this.titleZh,
    required this.detailZh,
    required this.estimatedMinutes,
    this.actionType,
    List<String> knowledgePointIds = const <String>[],
    List<String> questionIds = const <String>[],
    this.cardCount,
  })  : knowledgePointIds = List<String>.unmodifiable(knowledgePointIds),
        questionIds = List<String>.unmodifiable(questionIds);

  /// 步骤种类。
  final DailyPlanStepKind kind;

  /// 优先级：小的在前。数字由 [DailyStudyPlan.build] 按固定优先级带分配。
  final int priority;

  /// 一行标题（中文）。
  final String titleZh;

  /// 给用户看的理由；只写真实的步数 / 题数 / 卡片数，不写没有依据的承诺。
  final String detailZh;

  /// 这一步预计花几分钟；所有步骤之和不超过计划的预算。
  final int estimatedMinutes;

  /// 关联的能力动作 key；不针对单个动作的步骤为 null。
  final String? actionType;

  /// 关联的知识点 id（不可变、已去重）。只有练习步骤会填，且只来自
  /// 学习建议的练习动作 / 配题推荐的命中知识点。
  final List<String> knowledgePointIds;

  /// 关联的题目 id（不可变、按推荐名次排序）。只有练习步骤会填。
  final List<String> questionIds;

  /// 到期卡片张数；只有 reviewDueCards 步骤会填。
  final int? cardCount;

  /// 固定键序的 JSON：kind, priority, title_zh, detail_zh, estimated_minutes,
  /// action_type, knowledge_point_ids, question_ids, card_count。
  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind.name,
        'priority': priority,
        'title_zh': titleZh,
        'detail_zh': detailZh,
        'estimated_minutes': estimatedMinutes,
        'action_type': actionType,
        'knowledge_point_ids': List<String>.of(knowledgePointIds),
        'question_ids': List<String>.of(questionIds),
        'card_count': cardCount,
      };
}

/// 一份今日学习计划（不可变、纯数据）。
class DailyStudyPlan {
  DailyStudyPlan._({
    required List<DailyPlanStep> steps,
    required this.totalMinutes,
    required List<String> focusKnowledgePointIds,
    required this.skippedStepCount,
  })  : steps = List<DailyPlanStep>.unmodifiable(steps),
        focusKnowledgePointIds =
            List<String>.unmodifiable(focusKnowledgePointIds);

  /// 默认每天可用分钟数。
  static const int defaultDailyMinutes = 30;

  /// 默认最多几步。
  static const int defaultMaxSteps = 5;

  /// 每天可用分钟数的下限（小于它按 1 分钟处理）。
  static const int minDailyMinutes = 1;

  /// 步骤数上限的下限。
  static const int minStepLimit = 1;

  /// 步骤数上限的上限（再多也排不下，且会冲淡当天的重点）。
  static const int maxStepLimit = 8;

  /// 焦点知识点最多几个。
  static const int maxFocusKnowledgePoints = 5;

  static const int _reviewDueCardsPriority = 100;
  static const int _practicePriority = 200;
  static const int _collectChainsPriority = 300;
  static const int _reviewVocabularyPriority = 400;
  static const int _keepGoingPriority = 500;
  static const int _noDataPriority = 600;

  static const int _minutesPerQuestion = 2;
  static const int _collectChainsMinutes = 5;
  static const int _reviewVocabularyMinutes = 3;
  static const int _keepGoingMinutes = 1;

  /// 词表步骤最多列几个动作名（避免文案过长）。
  static const int _maxVocabularyNames = 5;

  /// 排好的步骤（按优先级升序；没有数据时是单条 noData）。
  final List<DailyPlanStep> steps;

  /// 所有步骤的预计分钟数之和，一定不超过生效后的每日预算。
  final int totalMinutes;

  /// 当天要优先关注的知识点 id（去重、最多
  /// [maxFocusKnowledgePoints] 个）：先按步骤顺序取练习步骤的知识点，
  /// 再补学习建议里练习动作的知识点（同样去重、保序）。
  final List<String> focusKnowledgePointIds;

  /// 因为预算不够或超过步骤上限而没有排进计划的候选步骤数。
  final int skippedStepCount;

  /// 是否没有任何步骤。build 在有数据时不会返回空计划（最差也有
  /// keepGoing 或 noData 一步），此 getter 供调用方防御性判断。
  bool get isEmpty => steps.isEmpty;

  /// 是否至少一步。
  bool get isNotEmpty => steps.isNotEmpty;

  /// 固定键序的 JSON：steps, total_minutes, focus_knowledge_point_ids,
  /// skipped_step_count, is_empty。
  Map<String, Object?> toJson() => <String, Object?>{
        'steps': <Object?>[for (final step in steps) step.toJson()],
        'total_minutes': totalMinutes,
        'focus_knowledge_point_ids': List<String>.of(focusKnowledgePointIds),
        'skipped_step_count': skippedStepCount,
        'is_empty': isEmpty,
      };

  /// 生成今天的学习计划。
  ///
  /// [insights]：§14 的洞察读数（必需；调用方用当前词表 overlay 聚合后再传）。
  /// [advices]：§15 的学习建议（必需；练习动作 / 补链 / 补词表信号都从这来）。
  /// [recommendations]：§22 的配题推荐；null 或空计划表示没有推荐，此时不会
  /// 生成练习步骤（哪怕学习建议里还有练习动作）。
  /// [dueCardCount]：到期卡片张数，由调用方从间隔重复队列读出后注入；
  /// null 或 <= 0 表示没有到期卡片。本层不读时钟、不读数据库。
  /// [dailyMinutes]：当天可用分钟数，默认 [defaultDailyMinutes]；小于
  /// [minDailyMinutes] 按 [minDailyMinutes] 处理。
  /// [maxSteps]：最多几步，默认 [defaultMaxSteps]；小于 [minStepLimit] 按
  /// [minStepLimit] 处理、大于 [maxStepLimit] 按 [maxStepLimit] 处理。
  ///
  /// 排序：固定优先级带（到期卡片 → 练习 → 补齐思维链 → 补词表 → 继续保持）；
  /// 没有数据时只返回单条 noData。
  static DailyStudyPlan build({
    required ChainInsights insights,
    required LearningAdvicePlan advices,
    PracticeRecommendationPlan? recommendations,
    int? dueCardCount,
    int dailyMinutes = defaultDailyMinutes,
    int maxSteps = defaultMaxSteps,
  }) {
    final budget =
        dailyMinutes < minDailyMinutes ? minDailyMinutes : dailyMinutes;
    final stepLimit = maxSteps < minStepLimit
        ? minStepLimit
        : (maxSteps > maxStepLimit ? maxStepLimit : maxSteps);
    final cards =
        dueCardCount == null || dueCardCount <= 0 ? null : dueCardCount;

    final practiceAdvices = <LearningAdvice>[
      for (final advice in advices.advices)
        if (advice.kind == LearningAdviceKind.practiceAction) advice,
    ];
    final collectAdvice =
        _firstAdvice(advices, LearningAdviceKind.collectChains);
    final recommendedQuestions =
        recommendations == null || recommendations.isEmpty
            ? const <PracticeRecommendation>[]
            : recommendations.recommendations;

    final hasEvidence = insights.isNotEmpty ||
        recommendedQuestions.isNotEmpty ||
        cards != null ||
        advices.advices.any(
          (advice) => advice.kind != LearningAdviceKind.noData,
        );

    if (!hasEvidence) {
      final step = _noDataStep();
      return DailyStudyPlan._(
        steps: <DailyPlanStep>[step],
        totalMinutes: 0,
        focusKnowledgePointIds: _focusKnowledgePointIds(
          steps: <DailyPlanStep>[step],
          practiceAdvices: practiceAdvices,
        ),
        skippedStepCount: 0,
      );
    }

    final builders = <DailyPlanStep? Function(int remainingMinutes)>[];
    if (cards != null) {
      final cardTotal = cards;
      builders.add(
        (int remainingMinutes) => _reviewDueCardsStep(
          cards: cardTotal,
          remainingMinutes: remainingMinutes,
        ),
      );
    }
    if (recommendedQuestions.isNotEmpty) {
      builders.add(
        (int remainingMinutes) => _practiceStep(
          recommendations: recommendedQuestions,
          practiceAdvices: practiceAdvices,
          remainingMinutes: remainingMinutes,
        ),
      );
    }
    if (collectAdvice != null) {
      final advice = collectAdvice;
      builders.add(
        (int remainingMinutes) => _collectChainsStep(
          advice: advice,
          remainingMinutes: remainingMinutes,
        ),
      );
    }
    if (insights.unknownActions.isNotEmpty) {
      builders.add(
        (int remainingMinutes) => _reviewVocabularyStep(
          unknownActions: insights.unknownActions,
          remainingMinutes: remainingMinutes,
        ),
      );
    }

    final steps = <DailyPlanStep>[];
    var skippedStepCount = 0;
    var remaining = budget;
    if (builders.isEmpty) {
      steps.add(_keepGoingStep(remainingMinutes: remaining));
    } else {
      for (final buildStep in builders) {
        if (steps.length >= stepLimit) {
          skippedStepCount++;
          continue;
        }
        final step = buildStep(remaining);
        if (step == null) {
          skippedStepCount++;
          continue;
        }
        steps.add(step);
        remaining -= step.estimatedMinutes;
      }
      if (steps.isEmpty) {
        steps.add(
          _keepGoingStep(remainingMinutes: remaining < 1 ? 1 : remaining),
        );
      }
    }

    return DailyStudyPlan._(
      steps: steps,
      totalMinutes: _sumMinutes(steps),
      focusKnowledgePointIds: _focusKnowledgePointIds(
        steps: steps,
        practiceAdvices: practiceAdvices,
      ),
      skippedStepCount: skippedStepCount,
    );
  }
}

LearningAdvice? _firstAdvice(LearningAdvicePlan plan, LearningAdviceKind kind) {
  for (final advice in plan.advices) {
    if (advice.kind == kind) {
      return advice;
    }
  }
  return null;
}

DailyPlanStep? _reviewDueCardsStep({
  required int cards,
  required int remainingMinutes,
}) {
  if (remainingMinutes < 1) {
    return null;
  }
  final natural = (cards + 1) ~/ 2;
  final minutes = remainingMinutes < natural ? remainingMinutes : natural;
  final buffer = StringBuffer()
    ..write('到期卡片 ')
    ..write(cards)
    ..write(' 张，安排约 ')
    ..write(minutes)
    ..write(' 分钟清理；到期队列优先清掉，避免越积越多。');
  return DailyPlanStep(
    kind: DailyPlanStepKind.reviewDueCards,
    priority: DailyStudyPlan._reviewDueCardsPriority,
    titleZh: '复习到期卡片',
    detailZh: buffer.toString(),
    estimatedMinutes: minutes,
    cardCount: cards,
  );
}

DailyPlanStep? _practiceStep({
  required List<PracticeRecommendation> recommendations,
  required List<LearningAdvice> practiceAdvices,
  required int remainingMinutes,
}) {
  final maxByBudget = remainingMinutes ~/ DailyStudyPlan._minutesPerQuestion;
  final count = recommendations.length < maxByBudget
      ? recommendations.length
      : maxByBudget;
  if (count < 1) {
    return null;
  }
  final questionIds = <String>[
    for (var i = 0; i < count; i++) recommendations[i].questionId,
  ];
  final actionType = _practiceActionType(practiceAdvices, recommendations);
  final knowledgePointIds =
      _practiceKnowledgePointIds(practiceAdvices, recommendations);
  final buffer = StringBuffer()
    ..write('从配题推荐里取前 ')
    ..write(count)
    ..write(' 道题练习（每道约 ')
    ..write(DailyStudyPlan._minutesPerQuestion)
    ..write(' 分钟）');
  if (actionType != null) {
    buffer
      ..write('，重点动作：')
      ..write(actionType);
  }
  buffer.write('。');
  return DailyPlanStep(
    kind: DailyPlanStepKind.practiceQuestions,
    priority: DailyStudyPlan._practicePriority,
    titleZh: '练习配题推荐',
    detailZh: buffer.toString(),
    estimatedMinutes: count * DailyStudyPlan._minutesPerQuestion,
    actionType: actionType,
    knowledgePointIds: knowledgePointIds,
    questionIds: questionIds,
  );
}

String? _practiceActionType(
  List<LearningAdvice> practiceAdvices,
  List<PracticeRecommendation> recommendations,
) {
  for (final advice in practiceAdvices) {
    final raw = advice.actionType;
    if (raw == null) {
      continue;
    }
    final trimmed = raw.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  for (final recommendation in recommendations) {
    for (final raw in recommendation.matchedActionTypes) {
      final trimmed = raw.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
  }
  return null;
}

List<String> _practiceKnowledgePointIds(
  List<LearningAdvice> practiceAdvices,
  List<PracticeRecommendation> recommendations,
) {
  final ordered = <String>[];
  void addAll(Iterable<String> ids) {
    for (final raw in ids) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty || ordered.contains(trimmed)) {
        continue;
      }
      ordered.add(trimmed);
    }
  }

  for (final advice in practiceAdvices) {
    addAll(advice.knowledgePointIds);
  }
  if (ordered.isEmpty) {
    for (final recommendation in recommendations) {
      addAll(recommendation.matchedKnowledgePointIds);
    }
  }
  return ordered;
}

DailyPlanStep? _collectChainsStep({
  required LearningAdvice advice,
  required int remainingMinutes,
}) {
  if (remainingMinutes < 1) {
    return null;
  }
  const natural = DailyStudyPlan._collectChainsMinutes;
  final minutes = remainingMinutes < natural ? remainingMinutes : natural;
  final detail = advice.detailZh.trim();
  return DailyPlanStep(
    kind: DailyPlanStepKind.collectChains,
    priority: DailyStudyPlan._collectChainsPriority,
    titleZh: '补齐思维链',
    detailZh: detail.isEmpty ? '还有题没有思维链；先补几条链，后续洞察与建议才有依据。' : detail,
    estimatedMinutes: minutes,
    actionType: advice.actionType,
  );
}

DailyPlanStep? _reviewVocabularyStep({
  required List<ChainActionInsight> unknownActions,
  required int remainingMinutes,
}) {
  if (remainingMinutes < 1) {
    return null;
  }
  const natural = DailyStudyPlan._reviewVocabularyMinutes;
  final minutes = remainingMinutes < natural ? remainingMinutes : natural;
  final names = <String>[];
  for (final action in unknownActions) {
    final name = action.actionType.trim();
    if (name.isEmpty || names.contains(name)) {
      continue;
    }
    names.add(name);
    if (names.length >= DailyStudyPlan._maxVocabularyNames) {
      break;
    }
  }
  final buffer = StringBuffer()
    ..write('词表还不认识 ')
    ..write(unknownActions.length)
    ..write(' 个动作');
  if (names.isNotEmpty) {
    buffer
      ..write('：')
      ..write(names.join('、'));
  }
  buffer.write('；先补词表，别把未知动作当成没问题。');
  return DailyPlanStep(
    kind: DailyPlanStepKind.reviewVocabulary,
    priority: DailyStudyPlan._reviewVocabularyPriority,
    titleZh: '补能力动作词表',
    detailZh: buffer.toString(),
    estimatedMinutes: minutes,
  );
}

DailyPlanStep _keepGoingStep({required int remainingMinutes}) {
  const natural = DailyStudyPlan._keepGoingMinutes;
  final minutes = remainingMinutes < natural ? remainingMinutes : natural;
  return DailyPlanStep(
    kind: DailyPlanStepKind.keepGoing,
    priority: DailyStudyPlan._keepGoingPriority,
    titleZh: '继续保持',
    detailZh: '今天没有新的高风险点；按当前节奏继续练，保持手感即可。',
    estimatedMinutes: minutes,
  );
}

DailyPlanStep _noDataStep() => DailyPlanStep(
      kind: DailyPlanStepKind.noData,
      priority: DailyStudyPlan._noDataPriority,
      titleZh: '今天没有可依据的数据',
      detailZh: '今天没有到期卡片、没有配题推荐、也没有思维链读数；'
          '今天不虚构计划，先去收题或拆一道思维链。',
      estimatedMinutes: 0,
    );

int _sumMinutes(List<DailyPlanStep> steps) {
  var total = 0;
  for (final step in steps) {
    total += step.estimatedMinutes;
  }
  return total;
}

List<String> _focusKnowledgePointIds({
  required List<DailyPlanStep> steps,
  required List<LearningAdvice> practiceAdvices,
}) {
  final focus = <String>[];
  void addAll(Iterable<String> ids) {
    for (final raw in ids) {
      if (focus.length >= DailyStudyPlan.maxFocusKnowledgePoints) {
        return;
      }
      final trimmed = raw.trim();
      if (trimmed.isEmpty || focus.contains(trimmed)) {
        continue;
      }
      focus.add(trimmed);
    }
  }

  for (final step in steps) {
    addAll(step.knowledgePointIds);
  }
  for (final advice in practiceAdvices) {
    addAll(advice.knowledgePointIds);
  }
  return focus;
}

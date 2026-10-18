/// 思维链洞察聚合：把一批已入库的思维链读成学习信号。
///
/// 一条链只说明「这一道题的这一步有风险」；把许多条链按能力动作、卡点与
/// 知识点聚合起来，才能回答三个问题：
/// 1. 模型/学生实际在哪些动作上花步子、又卡在哪些动作上？
/// 2. 高危步集中在哪些题、哪些知识点上？
/// 3. 词表里哪些动作从没出现过、哪些动作还是词表不认识的（自定义/未知）？
///
/// 诚实性规则（与推理层其它读数同一条口径）：
/// * **只聚合真有的读数**：`stuckRisk` 为 null 的步只算条数，不进平均/最高值；
///   一个动作一条读数都没有时，平均值与最高值都是 null，不插补 0。
/// * **未知动作不吞**：词表不认识的 `actionType` 原样保留在聚合结果里，
///   并单独给出 [ChainInsights.unknownActions]；自定义动作同理进
///   [ChainInsights.customActions]。
/// * **没有样本就说没有**：空输入返回空的聚合结果，且「从未出现的动作」也
///   给空列表——没有样本时声称「全部动作都没用过」是在编结论。
///
/// 异常输入口径（全部有测试守着）：
/// * `chainId` 去空白后为空 → 整条链丢弃并计入 [ChainInsights.ignoredChainCount]；
/// * 重复 `chainId` → 只保留第一条并计入 [ChainInsights.duplicateChainCount]；
/// * `actionType` 去空白后为空 → 该步丢弃并计入
///   [ChainInsights.ignoredStepCount]；
/// * 同一链内重复 `index`（DB 主键口径）→ 只保留第一条并计入
///   [ChainInsights.duplicateStepCount]；`index` 为 null 的步不参与重复检测；
/// * `stuckRisk` 为 NaN / ±infinity → 按「没有读数」处理并计入
///   [ChainInsights.invalidRiskStepCount]；有限但越界的值先夹到 0..1 再参与，
///   并计入 [ChainInsights.clampedRiskStepCount]；
/// * 空 `questionId` 的链步骤照常统计动作，但不计入题数、也不进题目维度；
/// * 阈值非有限 → 退回 [ChainInsights.defaultHighRiskThreshold]；否则夹到 0..1。
///
/// 纯 Dart：不 import Flutter / 数据库 / 网络，不抛异常、无 IO；输出列表全部
/// 不可变且排序确定（不依赖 Map 迭代顺序），可直接用于 UI 或快照测试。
library;

import 'capability_action.dart';
import 'capability_action_overlay.dart';
import 'reasoning_prompt.dart';

/// 聚合输入里的一步（轻量行模型，由调用方从 `ReasoningSteps` 或
/// [ParsedStep] 投影）。
class ChainInsightStep {
  const ChainInsightStep({
    required this.actionType,
    this.index,
    this.stuckRisk,
    this.knownAction,
    this.knowledgeHints = const <String>[],
    this.occurredAt,
  });

  /// 从解析后的步骤投影。
  ///
  /// [ParsedStep.stuckRisk] 是解析器的既有契约（缺失时取 0.5 中性值），
  /// 这里原样继承，不另行插补。
  factory ChainInsightStep.fromParsedStep(
    ParsedStep step, {
    DateTime? occurredAt,
  }) {
    return ChainInsightStep(
      actionType: step.actionType,
      index: step.index,
      stuckRisk: step.stuckRisk,
      knownAction: step.knownAction,
      knowledgeHints: step.knowledgeHints,
      occurredAt: occurredAt,
    );
  }

  /// `ReasoningSteps.actionType` 的原串；未知动作也保留。
  final String actionType;

  /// 链内序号（`ReasoningSteps.idx`，从 0 起）。null = 不参与重复检测。
  final int? index;

  /// 卡点风险（约定 0..1）；null = 没测到。
  final double? stuckRisk;

  /// 入库时的 knownAction 判定；null = 由当前词表重新推断。
  ///
  /// 用户自定义词表会变，所以库里读回的旧标记可能过期；传 null 让聚合用
  /// 当前词表重新判定，是更稳的默认。
  final bool? knownAction;

  /// 这一步涉及的知识点（可空；空串/空白项会被忽略）。
  final List<String> knowledgeHints;

  /// 这一步发生/入库的时间；null 表示没时间戳。
  final DateTime? occurredAt;
}

/// 聚合输入里的一条链（轻量行模型，由调用方从 `ReasoningChains` +
/// `ReasoningSteps` 拼出）。
class ChainInsightChain {
  const ChainInsightChain({
    required this.chainId,
    required this.questionId,
    required this.steps,
    this.occurredAt,
  });

  /// 从解析后的链投影；[chainId] / [questionId] 由调用方提供（解析结果本身
  /// 不带这两个标识）。
  factory ChainInsightChain.fromParsedChain(
    ParsedChain chain, {
    required String chainId,
    required String questionId,
    DateTime? occurredAt,
  }) {
    return ChainInsightChain(
      chainId: chainId,
      questionId: questionId,
      steps: <ChainInsightStep>[
        for (final step in chain.steps) ChainInsightStep.fromParsedStep(step),
      ],
      occurredAt: occurredAt,
    );
  }

  /// 链 id（`ReasoningChains.id`）；空白视为无效链。
  final String chainId;

  /// 所属题 id（`ReasoningChains.questionId`）；空串 = 调用方没有题目归属。
  final String questionId;

  /// 链内步骤，按 UI/入库顺序。
  final List<ChainInsightStep> steps;

  /// 链的创建时间；步没有自己的时间戳时作为兜底。
  final DateTime? occurredAt;

  /// 步数。由 [steps] 派生：DB 的 `ReasoningChains.stepCount` 冗余列只服务
  /// 列表页，聚合以实际步骤为准，避免两处口径打架。
  int get stepCount => steps.length;
}

/// 一个能力动作的聚合读数。
class ChainActionInsight {
  const ChainActionInsight({
    required this.actionType,
    required this.label,
    required this.known,
    required this.custom,
    required this.stepCount,
    required this.questionCount,
    required this.knownActionRatio,
    required this.highRiskStepCount,
    required this.highRiskQuestionCount,
    required this.highRiskChainCount,
    required this.averageStuckRisk,
    required this.maxStuckRisk,
    required this.lastSeenAt,
  });

  /// 原串 key（未知动作时就是它本身）。
  final String actionType;

  /// 展示名：词表里有的用中文名，没有的用原串。
  final String label;

  /// 当前词表认不认识这个 key。
  final bool known;

  /// 是否是用户自定义（overlay）动作。
  final bool custom;

  /// 出现的步骤数（含没有风险读数的步）。
  final int stepCount;

  /// 涉及的不同题目数（按去重 questionId；空 questionId 不计）。
  final int questionCount;

  /// 有 knownAction 标记的步占比（0..1）。入库时未注入自定义词表可能存 false，
  /// 读回时传 `knownAction: null` 让聚合按当前词表重新判定。
  final double knownActionRatio;

  /// 被判为高风险的步骤数（`stuckRisk >= 阈值`）。
  final int highRiskStepCount;

  /// 出现过高危步的不同题目数。
  final int highRiskQuestionCount;

  /// 出现过高危步的不同链数。
  final int highRiskChainCount;

  /// 有读数的步骤的平均卡点风险；一条读数都没有时是 null。
  final double? averageStuckRisk;

  /// 有读数的步骤里的最高卡点风险；一条读数都没有时是 null。
  final double? maxStuckRisk;

  /// 这个动作最近一次出现的时刻（步时间优先、链时间兜底）；没时间戳时 null。
  final DateTime? lastSeenAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'action_type': actionType,
        'label': label,
        'known': known,
        'custom': custom,
        'step_count': stepCount,
        'question_count': questionCount,
        'known_action_ratio': knownActionRatio,
        'high_risk_step_count': highRiskStepCount,
        'high_risk_question_count': highRiskQuestionCount,
        'high_risk_chain_count': highRiskChainCount,
        'average_stuck_risk': averageStuckRisk,
        'max_stuck_risk': maxStuckRisk,
        'last_seen_at': lastSeenAt?.toIso8601String(),
      };
}

/// 一个高风险维度（题目或知识点）的高危步计数。
class ChainHighRiskGroup {
  const ChainHighRiskGroup({
    required this.key,
    required this.highRiskStepCount,
    required this.questionCount,
    required this.chainCount,
  });

  /// 题目 id 或知识点名。
  final String key;

  /// 该维度下的高危步数。
  final int highRiskStepCount;

  /// 涉及的不同题目数。
  final int questionCount;

  /// 涉及的不同链数。
  final int chainCount;

  Map<String, Object?> toJson() => <String, Object?>{
        'key': key,
        'high_risk_step_count': highRiskStepCount,
        'question_count': questionCount,
        'chain_count': chainCount,
      };
}

/// 一批思维链的聚合洞察。
///
/// 用 [ChainInsights.aggregate] 构造；构造结果不可变、纯数据。
class ChainInsights {
  const ChainInsights._({
    required this.highRiskThreshold,
    required this.chainCount,
    required this.stepCount,
    required this.questionCount,
    required this.ignoredChainCount,
    required this.duplicateChainCount,
    required this.ignoredStepCount,
    required this.duplicateStepCount,
    required this.invalidRiskStepCount,
    required this.clampedRiskStepCount,
    required this.highRiskStepCount,
    required this.highRiskChainCount,
    required this.actions,
    required this.customActions,
    required this.unknownActions,
    required this.neverUsedActions,
    required this.highRiskByQuestion,
    required this.highRiskByKnowledgePoint,
  });

  /// 判「高危步」的默认门槛，与详情页红条 / 画像层一致。
  static const double defaultHighRiskThreshold = 0.6;

  /// 聚合入口。同步、纯函数、不抛异常。
  ///
  /// [catalog] 传 null 表示只用内置词表；要认用户自定义动作请传
  /// `overlay.catalog`（传自定义词表时内置动作仍然认识）。
  static ChainInsights aggregate({
    required Iterable<ChainInsightChain> chains,
    CapabilityActionCatalog? catalog,
    double highRiskThreshold = defaultHighRiskThreshold,
  }) {
    final known = catalog ?? CapabilityActionCatalog.builtIn;
    final threshold = _normalizeThreshold(highRiskThreshold);
    final seenChainIds = <String>{};
    final questionIds = <String>{};
    final buckets = <String, _ActionBucket>{};
    final questionBuckets = <String, _HighRiskBucket>{};
    final knowledgeBuckets = <String, _HighRiskBucket>{};
    final highRiskChainIds = <String>{};

    var chainCount = 0;
    var stepCount = 0;
    var ignoredChainCount = 0;
    var duplicateChainCount = 0;
    var ignoredStepCount = 0;
    var duplicateStepCount = 0;
    var invalidRiskStepCount = 0;
    var clampedRiskStepCount = 0;
    var highRiskStepCount = 0;

    for (final chain in chains) {
      final chainId = chain.chainId.trim();
      if (chainId.isEmpty) {
        ignoredChainCount++;
        continue;
      }
      if (!seenChainIds.add(chainId)) {
        duplicateChainCount++;
        continue;
      }
      chainCount++;
      final questionId = chain.questionId.trim();
      if (questionId.isNotEmpty) {
        questionIds.add(questionId);
      }
      final seenIndexes = <int>{};
      for (final step in chain.steps) {
        final actionType = step.actionType.trim();
        if (actionType.isEmpty) {
          ignoredStepCount++;
          continue;
        }
        final index = step.index;
        if (index != null && !seenIndexes.add(index)) {
          duplicateStepCount++;
          continue;
        }
        stepCount++;
        final rawRisk = step.stuckRisk;
        double? risk;
        if (rawRisk != null) {
          if (!rawRisk.isFinite) {
            invalidRiskStepCount++;
          } else {
            final clamped = _clampRisk(rawRisk);
            if (clamped != rawRisk) {
              clampedRiskStepCount++;
            }
            risk = clamped;
          }
        }
        final knownAction =
            step.knownAction ?? (known.byKey(actionType) != null);
        final seenAt = step.occurredAt ?? chain.occurredAt;
        final bucket = buckets.putIfAbsent(actionType, _ActionBucket.new);
        bucket.stepCount++;
        if (knownAction) {
          bucket.knownStepCount++;
        }
        if (questionId.isNotEmpty) {
          bucket.questionIds.add(questionId);
        }
        bucket.recordSeenAt(seenAt);
        if (risk != null) {
          bucket.recordRisk(risk);
          if (risk >= threshold) {
            highRiskStepCount++;
            highRiskChainIds.add(chainId);
            bucket.highRiskStepCount++;
            bucket.highRiskChainIds.add(chainId);
            if (questionId.isNotEmpty) {
              bucket.highRiskQuestionIds.add(questionId);
              questionBuckets
                  .putIfAbsent(questionId, _HighRiskBucket.new)
                  .add(questionId: questionId, chainId: chainId);
            }
            final hints = <String>{
              for (final hint in step.knowledgeHints)
                if (hint.trim().isNotEmpty) hint.trim(),
            };
            for (final hint in hints) {
              knowledgeBuckets
                  .putIfAbsent(hint, _HighRiskBucket.new)
                  .add(questionId: questionId, chainId: chainId);
            }
          }
        }
      }
    }

    final actions = <ChainActionInsight>[
      for (final entry in buckets.entries)
        _insightOf(entry.key, entry.value, known),
    ];
    actions.sort(_compareActions);
    final customActions = <ChainActionInsight>[
      for (final insight in actions)
        if (insight.custom) insight,
    ];
    final unknownActions = <ChainActionInsight>[
      for (final insight in actions)
        if (!insight.known) insight,
    ];
    final neverUsedActions = stepCount == 0
        ? const <CapabilityAction>[]
        : <CapabilityAction>[
            for (final action in known.actions)
              if (!buckets.containsKey(action.key)) action,
          ];
    final highRiskByQuestion = <ChainHighRiskGroup>[
      for (final entry in questionBuckets.entries)
        entry.value.toGroup(entry.key),
    ]..sort(_compareGroups);
    final highRiskByKnowledgePoint = <ChainHighRiskGroup>[
      for (final entry in knowledgeBuckets.entries)
        entry.value.toGroup(entry.key),
    ]..sort(_compareGroups);

    return ChainInsights._(
      highRiskThreshold: threshold,
      chainCount: chainCount,
      stepCount: stepCount,
      questionCount: questionIds.length,
      ignoredChainCount: ignoredChainCount,
      duplicateChainCount: duplicateChainCount,
      ignoredStepCount: ignoredStepCount,
      duplicateStepCount: duplicateStepCount,
      invalidRiskStepCount: invalidRiskStepCount,
      clampedRiskStepCount: clampedRiskStepCount,
      highRiskStepCount: highRiskStepCount,
      highRiskChainCount: highRiskChainIds.length,
      actions: List<ChainActionInsight>.unmodifiable(actions),
      customActions: List<ChainActionInsight>.unmodifiable(customActions),
      unknownActions: List<ChainActionInsight>.unmodifiable(unknownActions),
      neverUsedActions: List<CapabilityAction>.unmodifiable(neverUsedActions),
      highRiskByQuestion: List<ChainHighRiskGroup>.unmodifiable(
        highRiskByQuestion,
      ),
      highRiskByKnowledgePoint: List<ChainHighRiskGroup>.unmodifiable(
        highRiskByKnowledgePoint,
      ),
    );
  }

  /// 聚合实际使用的阈值（已归一到 0..1）。
  final double highRiskThreshold;

  /// 有效链数（chainId 去重后）。
  final int chainCount;

  /// 有效步数（丢弃空 actionType / 重复 index 之后）。
  final int stepCount;

  /// 涉及的不同题目数（questionId 去重、空串不计）。
  final int questionCount;

  /// 因 chainId 为空被丢弃的链数。
  final int ignoredChainCount;

  /// 因 chainId 重复被丢弃的链数。
  final int duplicateChainCount;

  /// 因 actionType 为空被丢弃的步数。
  final int ignoredStepCount;

  /// 因同一链内 index 重复被丢弃的步数。
  final int duplicateStepCount;

  /// 因 stuckRisk 非有限（NaN/±inf）被当作「无读数」的步数。
  final int invalidRiskStepCount;

  /// 因 stuckRisk 越界被夹到 0..1 的步数（仍参与统计）。
  final int clampedRiskStepCount;

  /// 全部动作的高危步总数。
  final int highRiskStepCount;

  /// 出现过高危步的不同链数。
  final int highRiskChainCount;

  /// 全部动作的聚合，按「步数降序 → 题数降序 → 高危步降序 → 平均风险降序
  /// （null 最后）→ actionType 升序」排序。
  final List<ChainActionInsight> actions;

  /// [actions] 里当前词表认定为用户自定义动作的子集（保持同一排序）。
  final List<ChainActionInsight> customActions;

  /// [actions] 里当前词表不认识的动作为子集（保持同一排序）。
  final List<ChainActionInsight> unknownActions;

  /// 当前词表里有、但这批链里一步都没出现的动作，按词表顺序（内置在前）。
  ///
  /// 空输入时是空列表：没有样本就不声称「全部动作都没用过」。
  final List<CapabilityAction> neverUsedActions;

  /// 高危步按题目维度计数（只含非空 questionId），排序同 [actions] 的稳定口径。
  final List<ChainHighRiskGroup> highRiskByQuestion;

  /// 高危步按知识点维度计数；空白知识点忽略。
  final List<ChainHighRiskGroup> highRiskByKnowledgePoint;

  /// 没有任何有效步骤。
  bool get isEmpty => stepCount == 0;

  /// 有至少一步有效数据。
  bool get isNotEmpty => stepCount > 0;

  /// 序列化（供调试/快照/以后的分析页面；DateTime 用 ISO 8601）。
  Map<String, Object?> toJson() => <String, Object?>{
        'high_risk_threshold': highRiskThreshold,
        'chain_count': chainCount,
        'step_count': stepCount,
        'question_count': questionCount,
        'ignored_chain_count': ignoredChainCount,
        'duplicate_chain_count': duplicateChainCount,
        'ignored_step_count': ignoredStepCount,
        'duplicate_step_count': duplicateStepCount,
        'invalid_risk_step_count': invalidRiskStepCount,
        'clamped_risk_step_count': clampedRiskStepCount,
        'high_risk_step_count': highRiskStepCount,
        'high_risk_chain_count': highRiskChainCount,
        'actions': <Object?>[for (final action in actions) action.toJson()],
        'custom_actions': <Object?>[
          for (final action in customActions) action.toJson(),
        ],
        'unknown_actions': <Object?>[
          for (final action in unknownActions) action.toJson(),
        ],
        'never_used_actions': <String>[
          for (final action in neverUsedActions) action.key,
        ],
        'high_risk_by_question': <Object?>[
          for (final group in highRiskByQuestion) group.toJson(),
        ],
        'high_risk_by_knowledge_point': <Object?>[
          for (final group in highRiskByKnowledgePoint) group.toJson(),
        ],
      };

  static ChainActionInsight _insightOf(
    String actionType,
    _ActionBucket bucket,
    CapabilityActionCatalog catalog,
  ) {
    final action = catalog.byKey(actionType);
    return ChainActionInsight(
      actionType: actionType,
      label: action?.labelZh ?? actionType,
      known: action != null,
      custom: catalog.isCustomKey(actionType),
      stepCount: bucket.stepCount,
      questionCount: bucket.questionIds.length,
      knownActionRatio: bucket.knownStepCount / bucket.stepCount,
      highRiskStepCount: bucket.highRiskStepCount,
      highRiskQuestionCount: bucket.highRiskQuestionIds.length,
      highRiskChainCount: bucket.highRiskChainIds.length,
      averageStuckRisk:
          bucket.riskCount == 0 ? null : bucket.riskSum / bucket.riskCount,
      maxStuckRisk: bucket.maxRisk,
      lastSeenAt: bucket.lastSeenAt,
    );
  }

  static int _compareActions(
      ChainActionInsight left, ChainActionInsight right) {
    final byStepCount = right.stepCount.compareTo(left.stepCount);
    if (byStepCount != 0) {
      return byStepCount;
    }
    final byQuestionCount = right.questionCount.compareTo(left.questionCount);
    if (byQuestionCount != 0) {
      return byQuestionCount;
    }
    final byHighRisk =
        right.highRiskStepCount.compareTo(left.highRiskStepCount);
    if (byHighRisk != 0) {
      return byHighRisk;
    }
    final leftAverage = left.averageStuckRisk;
    final rightAverage = right.averageStuckRisk;
    if (leftAverage != null && rightAverage == null) {
      return -1;
    }
    if (leftAverage == null && rightAverage != null) {
      return 1;
    }
    if (leftAverage != null && rightAverage != null) {
      final byAverage = rightAverage.compareTo(leftAverage);
      if (byAverage != 0) {
        return byAverage;
      }
    }
    return left.actionType.compareTo(right.actionType);
  }

  static int _compareGroups(ChainHighRiskGroup left, ChainHighRiskGroup right) {
    final byHighRisk =
        right.highRiskStepCount.compareTo(left.highRiskStepCount);
    if (byHighRisk != 0) {
      return byHighRisk;
    }
    final byChainCount = right.chainCount.compareTo(left.chainCount);
    if (byChainCount != 0) {
      return byChainCount;
    }
    final byQuestionCount = right.questionCount.compareTo(left.questionCount);
    if (byQuestionCount != 0) {
      return byQuestionCount;
    }
    return left.key.compareTo(right.key);
  }

  static double _normalizeThreshold(double value) {
    if (!value.isFinite) {
      return defaultHighRiskThreshold;
    }
    return _clampRisk(value);
  }

  static double _clampRisk(double value) {
    if (value < 0) {
      return 0.0;
    }
    if (value > 1) {
      return 1.0;
    }
    return value;
  }
}

class _ActionBucket {
  int stepCount = 0;
  int knownStepCount = 0;
  final Set<String> questionIds = <String>{};
  int highRiskStepCount = 0;
  final Set<String> highRiskQuestionIds = <String>{};
  final Set<String> highRiskChainIds = <String>{};
  int riskCount = 0;
  double riskSum = 0;
  double? maxRisk;
  DateTime? lastSeenAt;

  void recordSeenAt(DateTime? seenAt) {
    if (seenAt == null) {
      return;
    }
    final current = lastSeenAt;
    if (current == null || seenAt.isAfter(current)) {
      lastSeenAt = seenAt;
    }
  }

  void recordRisk(double risk) {
    riskCount++;
    riskSum += risk;
    final current = maxRisk;
    if (current == null || risk > current) {
      maxRisk = risk;
    }
  }
}

class _HighRiskBucket {
  int highRiskStepCount = 0;
  final Set<String> questionIds = <String>{};
  final Set<String> chainIds = <String>{};

  void add({required String questionId, required String chainId}) {
    highRiskStepCount++;
    if (questionId.isNotEmpty) {
      questionIds.add(questionId);
    }
    chainIds.add(chainId);
  }

  ChainHighRiskGroup toGroup(String key) => ChainHighRiskGroup(
        key: key,
        highRiskStepCount: highRiskStepCount,
        questionCount: questionIds.length,
        chainCount: chainIds.length,
      );
}

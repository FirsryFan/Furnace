/// 学习洞察页的数据拼装：洞察读数 + 学习建议 + 能力词表 + 知识点中文名。
///
/// 这一层只做拼装，没有业务口径：动作 / 卡点 / 建议全部来自
/// [ChainInsights] 与 [LearningAdvicePlan]（纯逻辑），读库只有"知识点标题"这一次。
/// 失败退化：词表读不到时退回内置词表并把 [LearningInsightData.vocabOverlayFallback]
/// 置为 true —— 用户自定义词表坏掉只影响 known / custom 判定，不该让整页打不开。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/database/app_database_provider.dart';
import '../../../data/database/database.dart' show AppDatabase;
import '../../../domain/services/reasoning/capability_action.dart';
import '../../../domain/services/reasoning/capability_action_overlay.dart';
import '../../../domain/services/reasoning/chain_insights.dart';
import '../../../domain/services/reasoning/learning_advice.dart';
import 'capability_vocabulary_store.dart';
import 'chain_insights_reader.dart';
import 'learning_advice_provider.dart';

/// 一行"能力动作分布"，字段与 [ChainActionInsight] 一一对应（界面直接渲染）。
class LearningInsightActionRow {
  const LearningInsightActionRow({
    required this.actionType,
    required this.labelZh,
    required this.known,
    required this.custom,
    required this.stepCount,
    required this.questionCount,
    required this.highRiskStepCount,
    this.averageStuckRisk,
    this.lastSeenAt,
  });

  factory LearningInsightActionRow.fromInsight(ChainActionInsight insight) {
    return LearningInsightActionRow(
      actionType: insight.actionType,
      labelZh: insight.label,
      known: insight.known,
      custom: insight.custom,
      stepCount: insight.stepCount,
      questionCount: insight.questionCount,
      highRiskStepCount: insight.highRiskStepCount,
      averageStuckRisk: insight.averageStuckRisk,
      lastSeenAt: insight.lastSeenAt,
    );
  }

  final String actionType;
  final String labelZh;
  final bool known;
  final bool custom;
  final int stepCount;
  final int questionCount;
  final int highRiskStepCount;

  /// null = 这些步骤都没有风险读数（不是 0）。
  final double? averageStuckRisk;
  final DateTime? lastSeenAt;

  bool get hasRiskReading => averageStuckRisk != null;
}

/// 一行"卡点热区"：知识点维度（id + 中文名 + 高危步数 / 题数 / 链数）。
class LearningInsightStuckRow {
  const LearningInsightStuckRow({
    required this.knowledgePointId,
    required this.titleZh,
    required this.highRiskStepCount,
    required this.questionCount,
    required this.chainCount,
  });

  factory LearningInsightStuckRow.fromGroup(
    ChainHighRiskGroup group, {
    required String titleZh,
  }) {
    return LearningInsightStuckRow(
      knowledgePointId: group.key,
      titleZh: titleZh,
      highRiskStepCount: group.highRiskStepCount,
      questionCount: group.questionCount,
      chainCount: group.chainCount,
    );
  }

  final String knowledgePointId;
  final String titleZh;
  final int highRiskStepCount;
  final int questionCount;
  final int chainCount;
}

/// 一行"动作 × 知识点交叉卡点"。
class LearningInsightActionKnowledgeRow {
  const LearningInsightActionKnowledgeRow({
    required this.actionType,
    required this.actionLabelZh,
    required this.knowledgePointId,
    required this.knowledgePointTitleZh,
    required this.highRiskStepCount,
    required this.questionCount,
    required this.chainCount,
  });

  final String actionType;
  final String actionLabelZh;
  final String knowledgePointId;
  final String knowledgePointTitleZh;
  final int highRiskStepCount;
  final int questionCount;
  final int chainCount;
}

/// 一张"下一步做什么"建议卡（知识点带中文名，读不到时回退 id）。
class LearningInsightAdviceCard {
  const LearningInsightAdviceCard({
    required this.kind,
    required this.priority,
    required this.titleZh,
    required this.detailZh,
    required this.knowledgePointIds,
    required this.knowledgePointTitles,
    this.actionType,
    this.actionLabelZh,
    this.questionCount,
    this.stepCount,
    this.highRiskStepCount,
  });

  factory LearningInsightAdviceCard.fromAdvice(
    LearningAdvice advice, {
    required String Function(String id) titleOf,
  }) {
    return LearningInsightAdviceCard(
      kind: advice.kind,
      priority: advice.priority,
      titleZh: advice.titleZh,
      detailZh: advice.detailZh,
      actionType: advice.actionType,
      actionLabelZh: advice.actionLabelZh,
      questionCount: advice.questionCount,
      stepCount: advice.stepCount,
      highRiskStepCount: advice.highRiskStepCount,
      knowledgePointIds: advice.knowledgePointIds,
      knowledgePointTitles: List<String>.unmodifiable(
        advice.knowledgePointIds.map(titleOf),
      ),
    );
  }

  final LearningAdviceKind kind;
  final int priority;
  final String titleZh;
  final String detailZh;
  final String? actionType;
  final String? actionLabelZh;
  final int? questionCount;
  final int? stepCount;
  final int? highRiskStepCount;
  final List<String> knowledgePointIds;
  final List<String> knowledgePointTitles;

  bool get hasKnowledgePoints => knowledgePointIds.isNotEmpty;
}

/// 学习洞察页的一次性数据快照。
class LearningInsightData {
  LearningInsightData._({
    required this.insights,
    required this.advices,
    required this.actionCatalog,
    required this.knowledgePointTitles,
    required this.actionRows,
    required this.unknownRows,
    required this.neverUsedActions,
    required this.stuckRows,
    required this.actionKnowledgeRows,
    required this.adviceCards,
    required this.vocabOverlayFallback,
  });

  factory LearningInsightData.build({
    required ChainInsights insights,
    required LearningAdvicePlan advices,
    required CapabilityActionOverlay overlay,
    required Map<String, String> knowledgePointTitles,
    bool vocabOverlayFallback = false,
  }) {
    final dedupedTitles = <String, String>{
      for (final entry in knowledgePointTitles.entries)
        if (entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty)
          entry.key.trim(): entry.value.trim(),
    };
    String titleOf(String id) {
      final trimmed = id.trim();
      final title = dedupedTitles[trimmed];
      if (title == null || title.isEmpty) {
        return trimmed;
      }
      return title;
    }

    final catalog = overlay.catalog;
    final catalogByKey = <String, CapabilityAction>{
      for (final action in catalog.actions) action.key: action,
    };
    String actionLabel(String key) {
      final trimmed = key.trim();
      final action = catalogByKey[trimmed];
      if (action == null) {
        return trimmed;
      }
      return action.labelZh;
    }

    return LearningInsightData._(
      insights: insights,
      advices: advices,
      actionCatalog: Map<String, CapabilityAction>.unmodifiable(catalogByKey),
      knowledgePointTitles: Map<String, String>.unmodifiable(dedupedTitles),
      actionRows: List<LearningInsightActionRow>.unmodifiable(
        insights.actions.map(LearningInsightActionRow.fromInsight),
      ),
      unknownRows: List<LearningInsightActionRow>.unmodifiable(
        insights.unknownActions.map(LearningInsightActionRow.fromInsight),
      ),
      neverUsedActions: List<CapabilityAction>.unmodifiable(
        insights.neverUsedActions,
      ),
      stuckRows: List<LearningInsightStuckRow>.unmodifiable(
        insights.highRiskByKnowledgePoint.map(
          (group) => LearningInsightStuckRow.fromGroup(
            group,
            titleZh: titleOf(group.key),
          ),
        ),
      ),
      actionKnowledgeRows: List<LearningInsightActionKnowledgeRow>.unmodifiable(
        insights.highRiskByActionAndKnowledgePoint.map(
          (group) => LearningInsightActionKnowledgeRow(
            actionType: group.actionType,
            actionLabelZh: actionLabel(group.actionType),
            knowledgePointId: group.knowledgePointId,
            knowledgePointTitleZh: titleOf(group.knowledgePointId),
            highRiskStepCount: group.highRiskStepCount,
            questionCount: group.questionCount,
            chainCount: group.chainCount,
          ),
        ),
      ),
      adviceCards: List<LearningInsightAdviceCard>.unmodifiable(
        advices.advices.map(
          (advice) => LearningInsightAdviceCard.fromAdvice(
            advice,
            titleOf: titleOf,
          ),
        ),
      ),
      vocabOverlayFallback: vocabOverlayFallback,
    );
  }

  final ChainInsights insights;
  final LearningAdvicePlan advices;
  final Map<String, CapabilityAction> actionCatalog;

  /// 本次页面真正用到的知识点标题（id -> title）；读不到的 id 不在表里。
  final Map<String, String> knowledgePointTitles;

  final List<LearningInsightActionRow> actionRows;
  final List<LearningInsightActionRow> unknownRows;
  final List<CapabilityAction> neverUsedActions;
  final List<LearningInsightStuckRow> stuckRows;
  final List<LearningInsightActionKnowledgeRow> actionKnowledgeRows;
  final List<LearningInsightAdviceCard> adviceCards;

  /// 词表偏好读不到、退回内置词表（页面应提示"自定义词表没读到"）。
  final bool vocabOverlayFallback;

  bool get hasActivity => insights.stepCount > 0;

  bool get isEmpty => !hasActivity && advices.isEmpty;

  bool get hasUnknownActions => unknownRows.isNotEmpty;

  bool get hasKnowledgePointGaps => stuckRows.isNotEmpty;
}

/// 学习洞察页的数据。与执行链 / 步骤 / 词表偏好同一份口径：
/// 链写入后 chainInsightCorpusProvider 会随数据库修订号重算，这里跟着刷新；
/// 知识点改名同样由修订号触发重读。
final learningInsightDataProvider =
    FutureProvider<LearningInsightData>((ref) async {
  ref.watchDatabaseRevision();
  final insights = await ref.watch(chainInsightsProvider.future);
  final advices = await ref.watch(learningAdviceProvider.future);

  var overlay = CapabilityActionOverlay.empty;
  var overlayFallback = false;
  try {
    overlay = await ref.watch(capabilityActionOverlayProvider.future);
  } on Object {
    overlay = CapabilityActionOverlay.empty;
    overlayFallback = true;
  }

  final knowledgePointIds = <String>{};
  for (final advice in advices.advices) {
    for (final id in advice.knowledgePointIds) {
      final trimmed = id.trim();
      if (trimmed.isNotEmpty) {
        knowledgePointIds.add(trimmed);
      }
    }
  }
  for (final group in insights.highRiskByKnowledgePoint) {
    final trimmed = group.key.trim();
    if (trimmed.isNotEmpty) {
      knowledgePointIds.add(trimmed);
    }
  }
  for (final group in insights.highRiskByActionAndKnowledgePoint) {
    final trimmed = group.knowledgePointId.trim();
    if (trimmed.isNotEmpty) {
      knowledgePointIds.add(trimmed);
    }
  }

  final titles = knowledgePointIds.isEmpty
      ? const <String, String>{}
      : await readKnowledgePointTitles(
          ref.watch(appDatabaseProvider),
          knowledgePointIds,
        );

  return LearningInsightData.build(
    insights: insights,
    advices: advices,
    overlay: overlay,
    knowledgePointTitles: titles,
    vocabOverlayFallback: overlayFallback,
  );
});

/// 只查用到的知识点标题；空集合不发查询，读不到的 id 不编造（界面回退显示 id）。
Future<Map<String, String>> readKnowledgePointTitles(
  AppDatabase db,
  Set<String> ids,
) async {
  if (ids.isEmpty) {
    return const <String, String>{};
  }
  final rows = await (db.select(db.knowledgePoints)
        ..where((table) => table.id.isIn(ids)))
      .get();
  final titles = <String, String>{};
  for (final row in rows) {
    final title = row.title.trim();
    if (title.isNotEmpty) {
      titles[row.id] = title;
    }
  }
  return Map<String, String>.unmodifiable(titles);
}

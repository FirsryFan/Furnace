/// 学习洞察页的「下一步练什么」区块：把配题推荐计划摊成可点的行。
///
/// 口径全部在 [practiceRecommendationProvider]（洞察 + 学习建议 + 候选投影
/// 已经算好分数与理由）；本文件只做展示：
/// * 顺序、rank、理由顺序都照 provider 给的原样，页面不重排；
/// * 理由最多展示 3 条，其余折叠成「另有 N 条理由」，不静默丢；
/// * 被目标题数上限截掉的题用 skippedQuestionIds 如实提示，不假装全列了；
/// * 命中动作按能力词表翻中文，词表外动作直接显示 key（不猜名字）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/reasoning/capability_action.dart';
import '../../../domain/services/reasoning/practice_recommendation.dart';
import '../../../l10n/app_localizations.dart';
import '../application/practice_recommendation_provider.dart';
import 'question_detail_page.dart';
import 'question_media_view.dart';

/// 区块根 key。
const Key practiceRecommendationSectionKey =
    Key('practice-recommendation-section');

/// 空推荐文案 key。
const Key practiceRecommendationEmptyKey = Key('practice-recommendation-empty');

/// 降级文案 key。
const Key practiceRecommendationErrorKey = Key('practice-recommendation-error');

/// 「还有 N 道没显示」提示 key。
const Key practiceRecommendationSkippedKey =
    Key('practice-recommendation-skipped');

/// 理由最多展示几条，其余折叠。
const int practiceRecommendationVisibleReasonLimit = 3;

/// 单行 key（按题目 id 区分，测试与滚动定位都用它）。
Key practiceRecommendationRowKey(String questionId) =>
    ValueKey<String>('practice-recommendation-row-$questionId');

/// 单条理由 -> 界面文案（枚举 -> l10n）。
String practiceRecommendationReasonLabel(
  AppLocalizations l10n,
  PracticeRecommendationReason reason,
) =>
    switch (reason) {
      PracticeRecommendationReason.matchedAdviceAction =>
        l10n.practiceRecommendationReasonMatchedAdviceAction,
      PracticeRecommendationReason.matchedHighRiskKnowledgePoint =>
        l10n.practiceRecommendationReasonMatchedHighRiskKnowledgePoint,
      PracticeRecommendationReason.unknownActionScaffold =>
        l10n.practiceRecommendationReasonUnknownActionScaffold,
      PracticeRecommendationReason.upToDate =>
        l10n.practiceRecommendationReasonUpToDate,
      PracticeRecommendationReason.missingSolution =>
        l10n.practiceRecommendationReasonMissingSolution,
      PracticeRecommendationReason.missingAnswer =>
        l10n.practiceRecommendationReasonMissingAnswer,
      PracticeRecommendationReason.tooHard =>
        l10n.practiceRecommendationReasonTooHard,
      PracticeRecommendationReason.tooEasy =>
        l10n.practiceRecommendationReasonTooEasy,
      PracticeRecommendationReason.unrelated =>
        l10n.practiceRecommendationReasonUnrelated,
    };

/// 只取前 [limit] 条理由；limit <= 0 返回空。
List<PracticeRecommendationReason> practiceRecommendationVisibleReasons(
  List<PracticeRecommendationReason> reasons, {
  int limit = practiceRecommendationVisibleReasonLimit,
}) {
  if (limit <= 0) return const <PracticeRecommendationReason>[];
  return reasons.take(limit).toList(growable: false);
}

/// 被折叠掉的理由条数（0 表示不需要显示「另有 N 条」）。
int practiceRecommendationHiddenReasonCount(
  List<PracticeRecommendationReason> reasons, {
  int limit = practiceRecommendationVisibleReasonLimit,
}) {
  if (limit <= 0) return reasons.length;
  if (reasons.length <= limit) return 0;
  return reasons.length - limit;
}

/// 命中动作的中文名：按词表 key 查 labelZh，查不到就显示 key 本身。
String practiceRecommendationActionLabels(
  PracticeRecommendation recommendation,
  Map<String, CapabilityAction> actionCatalog,
) {
  final labels = <String>[];
  for (final raw in recommendation.matchedActionTypes) {
    final key = raw.trim();
    if (key.isEmpty) continue;
    final label = actionCatalog[key]?.labelZh.trim() ?? '';
    labels.add(label.isEmpty ? key : label);
  }
  return labels.join('、');
}

/// 是否显示「还有 N 道没显示」：只看 skipped 名单。
bool practiceRecommendationShowsSkipped(PracticeRecommendationPlan plan) =>
    plan.skippedQuestionIds.isNotEmpty;

/// 「下一步练什么」区块。
///
/// loading 安静不占高；error 一行降级（不影响页面其它区块）；空计划一句空文案。
class PracticeRecommendationSection extends ConsumerWidget {
  const PracticeRecommendationSection({super.key, required this.actionCatalog});

  /// 能力动作词表（用来把命中动作翻成中文名）。
  final Map<String, CapabilityAction> actionCatalog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ref.watch(practiceRecommendationProvider).when(
          loading: () => const SizedBox.shrink(),
          error: (error, stackTrace) => Card(
            key: practiceRecommendationErrorKey,
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Text(
                l10n.practiceRecommendationFailed,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
          data: (plan) => _PracticeRecommendationCard(
            plan: plan,
            actionCatalog: actionCatalog,
            l10n: l10n,
          ),
        );
  }
}

class _PracticeRecommendationCard extends StatelessWidget {
  const _PracticeRecommendationCard({
    required this.plan,
    required this.actionCatalog,
    required this.l10n,
  });

  final PracticeRecommendationPlan plan;
  final Map<String, CapabilityAction> actionCatalog;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: practiceRecommendationSectionKey,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.checklist,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.practiceRecommendationTitle,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (plan.isEmpty)
              Text(
                l10n.practiceRecommendationEmpty,
                key: practiceRecommendationEmptyKey,
                style: theme.textTheme.bodyMedium,
              )
            else ...[
              for (final recommendation in plan.recommendations)
                _PracticeRecommendationRow(
                  recommendation: recommendation,
                  actionCatalog: actionCatalog,
                  l10n: l10n,
                ),
              if (practiceRecommendationShowsSkipped(plan))
                Padding(
                  key: practiceRecommendationSkippedKey,
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    l10n.practiceRecommendationSkipped(
                      plan.skippedQuestionIds.length,
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PracticeRecommendationRow extends StatelessWidget {
  const _PracticeRecommendationRow({
    required this.recommendation,
    required this.actionCatalog,
    required this.l10n,
  });

  final PracticeRecommendation recommendation;
  final Map<String, CapabilityAction> actionCatalog;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hiddenReasons = practiceRecommendationHiddenReasonCount(
      recommendation.reasons,
    );
    final reasonParts = <String>[
      for (final reason in practiceRecommendationVisibleReasons(
        recommendation.reasons,
      ))
        practiceRecommendationReasonLabel(l10n, reason),
      if (hiddenReasons > 0)
        l10n.practiceRecommendationMoreReasons(hiddenReasons),
    ];
    final actions = practiceRecommendationActionLabels(
      recommendation,
      actionCatalog,
    );
    return InkWell(
      key: practiceRecommendationRowKey(recommendation.questionId),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              QuestionDetailPage(questionId: recommendation.questionId),
        ),
      ),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.practiceRecommendationRank(recommendation.rank),
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(width: 8),
            QuestionSerialBadgeById(
              questionId: recommendation.questionId,
              copyable: false,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (reasonParts.isNotEmpty)
                    Text(
                      reasonParts.join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                  if (actions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        l10n.practiceRecommendationActions(actions),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../cognitive/presentation/today_plan_page.dart';
import 'deck_list_page.dart';
import 'knowledge_edge_page.dart';
import 'knowledge_insight_page.dart';
import 'review_plan_page.dart';

/// 复习模块的唯一入口页。
///
/// 以前这里是「复习 / 管理」两个 Tab：管理页负责手动建知识点和卡模板，
/// 实际使用中几乎没人会从手机上手搓卡片，却让第一屏多了一个看不懂的 Tab，
/// 右上角还堆了 4–5 个图标。现在只保留「选卡组 → 开始复习」这一条主线：
///
/// * 标题只有一个：卡组；
/// * 主操作只有一个，且带文字：新建卡组；
/// * 其余低频操作（卡组设置、复习偏好、知识线索、认知洞察、今日清单）
///   全部收进「更多」菜单，不再各自占一个图标。
class KnowledgePage extends ConsumerWidget {
  const KnowledgePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.deckListTitle),
        actions: [
          TextButton.icon(
            key: deckListCreateActionKey,
            onPressed: () => _openPlans(context),
            icon: const Icon(Icons.add, size: 18),
            label: Text(l10n.deckListCreate),
          ),
          PopupMenuButton<_KnowledgeMoreAction>(
            tooltip: l10n.knowledgeMoreActions,
            icon: const Icon(Icons.more_vert),
            onSelected: (action) {
              switch (action) {
                case _KnowledgeMoreAction.cardGroups:
                  _openPlans(context);
                case _KnowledgeMoreAction.reviewPreferences:
                  showReviewPreferencesDialog(context);
                case _KnowledgeMoreAction.edges:
                  _push(context, const KnowledgeEdgePage());
                case _KnowledgeMoreAction.insight:
                  _push(context, const KnowledgeInsightPage());
                case _KnowledgeMoreAction.todayPlan:
                  _push(context, const TodayPlanPage());
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _KnowledgeMoreAction.cardGroups,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.folder_shared_outlined),
                  title: Text(l10n.settingsCardGroups),
                ),
              ),
              PopupMenuItem(
                value: _KnowledgeMoreAction.reviewPreferences,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.tune),
                  title: Text(l10n.reviewPreferences),
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: _KnowledgeMoreAction.edges,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.hub_outlined),
                  title: Text(l10n.knowledgeEdges),
                ),
              ),
              PopupMenuItem(
                value: _KnowledgeMoreAction.insight,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.insights),
                  title: Text(l10n.knowledgeInsight),
                ),
              ),
              PopupMenuItem(
                value: _KnowledgeMoreAction.todayPlan,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.checklist),
                  title: Text(l10n.todayPlanTitle),
                ),
              ),
            ],
          ),
        ],
      ),
      body: const DeckListPage(),
    );
  }

  void _openPlans(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const ReviewPlanPage(),
      ),
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => page),
    );
  }
}

/// The low-frequency entries behind the app bar's overflow menu.
enum _KnowledgeMoreAction {
  cardGroups,
  reviewPreferences,
  edges,
  insight,
  todayPlan,
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../cognitive/presentation/today_plan_page.dart';
import 'anki_manage_page.dart';
import 'knowledge_edge_page.dart';
import 'knowledge_insight_page.dart';
import 'review_page.dart';
import 'review_plan_page.dart';

/// The Knowledge module (blueprint 4; user annotation 19).
///
/// Two tabs, because the practice screen must stay free of management
/// clutter: 复习 (flow) and 管理 (knowledge points / templates). "Today's
/// review" is a separate screen reached from the app bar - and so is 复习计划,
/// where the two persisted review preferences and the per-group daily plan live
/// (the practice screen deliberately keeps no settings furniture).
class KnowledgePage extends ConsumerStatefulWidget {
  const KnowledgePage({super.key});

  @override
  ConsumerState<KnowledgePage> createState() => _KnowledgePageState();
}

class _KnowledgePageState extends ConsumerState<KnowledgePage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_index == 0 ? l10n.navAnki : l10n.ankiManage),
        actions: [
          IconButton(
            // A one-tap path to the two review preferences from the review
            // screen itself, without leaving the queue: the block is the same
            // widget the plan page shows.
            tooltip: l10n.reviewPreferences,
            icon: const Icon(Icons.tune),
            onPressed: () => showReviewPreferencesDialog(context),
          ),
          IconButton(
            tooltip: l10n.reviewPlanTitle,
            icon: const Icon(Icons.event_available),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => const ReviewPlanPage(),
              ),
            ),
          ),
          // 用户反馈（m29307）：五个图标挤在标题栏里，看不出主次。复习用到的
          // 两个（偏好、计划）留在外面，"看数据"类的三个（线索边 / 洞察 / 今日
          // 清单）收进一个菜单——它们不是复习流程里每轮都要点的东西。
          PopupMenuButton<_KnowledgeMoreAction>(
            tooltip: l10n.knowledgeMoreActions,
            icon: const Icon(Icons.more_vert),
            onSelected: (action) {
              final page = switch (action) {
                // 线索边：资料里的连接确认之后落在 `knowledge_edges` 里，这一页是
                // 它们唯一的读法（一份只读清单 —— 有写者没读者等于没落地）。
                _KnowledgeMoreAction.edges => const KnowledgeEdgePage(),
                _KnowledgeMoreAction.insight => const KnowledgeInsightPage(),
                // 今日清单：把「今天做这几件事」摆到人面前（roadmap §1 控制层那
                // 一行的界面面）。它只列到期的卡，候选题的价格要模型给。
                _KnowledgeMoreAction.todayPlan => const TodayPlanPage(),
              };
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (context) => page),
              );
            },
            itemBuilder: (context) => [
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
      body: IndexedStack(
        index: _index,
        children: const [
          ReviewPage(),
          AnkiManagePage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.psychology_outlined),
            selectedIcon: const Icon(Icons.psychology),
            label: l10n.knowledgeReviewTab,
          ),
          NavigationDestination(
            icon: const Icon(Icons.library_books_outlined),
            selectedIcon: const Icon(Icons.library_books),
            label: l10n.ankiManage,
          ),
        ],
      ),
    );
  }
}

/// The "read the data" entries hidden behind the app bar's overflow menu.
enum _KnowledgeMoreAction { edges, insight, todayPlan }

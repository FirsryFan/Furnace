/// MindNet 顶层模块页：**用户层学习状态**首页（task-103 删繁就简）。
///
/// 用户反馈：认知模型/MindNet 的测试入口、评价体系、可视化太复杂，用户看什么、
/// 开发者看什么没明确。现在这一页只回答四件事：
///
/// 1. 当前档位 S/A/B/C/D/`?`；
/// 2. 3 个强项 + 3 个弱项（知识点，带证据状态）；
/// 3. 今日复习/任务数量 + 一个主按钮「开始复习」；
/// 4. 一句话趋势（最近一周复习），没有数据说「证据不足」。
///
/// 2026-11-15 第二遍清理（task-113）：这就是用户层「学习状态」的**唯一**入口，
/// 外壳导航标签从 `MindNet` 改成「学习状态」；设置页不再放「认知模型」原页。
/// 档位与强弱项以**知识点**为观测单位（不是闪存卡张数），所以这里读起来是
/// 学习状态，不是闪存卡统计。开发者字段统一在设置页开发者分区的
/// 「开发者信息（只读）」里（`CognitiveDeveloperPage`）。
///
/// 数字全部来自 provider，这一页不复制读数、不写库
/// （`learning_status_view.dart` 是四块的唯一实现）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import 'learning_status_view.dart';

class MindNetPage extends ConsumerWidget {
  const MindNetPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navMindnet),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.commonRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // 四块各自取数：刷新必须一起失效，否则会出现半新半旧的首页。
              ref.invalidate(learningStatusProvider);
              ref.invalidate(dueCardCountProvider);
              ref.invalidate(todayTaskCountProvider);
              ref.invalidate(weeklyReviewTrendProvider);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          Text(
            l10n.mindnetStatusIntro,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          const LearningStatusView(),
          const SizedBox(height: 16),
          const LearningStatusEntries(),
        ],
      ),
    );
  }
}

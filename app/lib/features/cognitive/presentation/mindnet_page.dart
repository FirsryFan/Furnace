import 'package:flutter/material.dart';
import 'package:furnace/l10n/app_localizations.dart';

import '../../assessment/presentation/assessment_center_page.dart';
import 'cognitive_graph_page.dart';
import 'cognitive_model_page.dart';
import 'mechanism_page.dart';
import 'today_plan_page.dart';

/// MindNet 顶层模块页：用户模型引擎的入口。
///
/// 这一页只做导航，不复制读数：每个子页仍从各自的 provider 取数（认知模型页
/// 读 cognitiveReadingsProvider、网络图自己查库、机制页读 mechanismPanelProvider），
/// 放在这里再读一遍只会让同一屏有两份真相。
///
/// 条目顺序按「先看清、再行动」：认知模型 → 知识网络 → 今日清单 → 机制参数 →
/// 评测中心。五个子页都是既有页面，本页不新增任何业务逻辑。
class MindNetPage extends StatelessWidget {
  const MindNetPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entries = <_MindNetEntry>[
      _MindNetEntry(
        icon: Icons.insights_outlined,
        title: l10n.cognitiveModelTitle,
        subtitle: l10n.cognitiveModelSubtitle,
        builder: (_) => const CognitiveModelPage(),
      ),
      _MindNetEntry(
        icon: Icons.hub_outlined,
        title: l10n.cognitiveGraphTitle,
        subtitle: l10n.cognitiveGraphTapHint,
        builder: (_) => const CognitiveGraphPage(),
      ),
      _MindNetEntry(
        icon: Icons.today_outlined,
        title: l10n.todayPlanTitle,
        subtitle: l10n.todayPlanUncalibrated,
        builder: (_) => const TodayPlanPage(),
      ),
      _MindNetEntry(
        icon: Icons.tune,
        title: l10n.mechanismPanelTitle,
        subtitle: l10n.mechanismPanelSubtitle,
        builder: (_) => const MechanismPage(),
      ),
      _MindNetEntry(
        icon: Icons.assessment_outlined,
        title: l10n.settingsAssessmentTitle,
        subtitle: l10n.assessmentCenterIntro,
        builder: (_) => const AssessmentCenterPage(),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navMindnet)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              l10n.mindnetIntro,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          for (final entry in entries) _MindNetTile(entry: entry),
        ],
      ),
    );
  }
}

/// One row of the MindNet hub: a title, a one-line explanation and the page to
/// open. A value type so the list above stays declarative and testable.
class _MindNetEntry {
  const _MindNetEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.builder,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final WidgetBuilder builder;
}

class _MindNetTile extends StatelessWidget {
  const _MindNetTile({required this.entry});

  final _MindNetEntry entry;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(entry.icon),
      title: Text(entry.title),
      subtitle: Text(entry.subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: entry.builder),
      ),
    );
  }
}

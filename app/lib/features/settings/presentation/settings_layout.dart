/// 设置页的版式零件（2026-11-15 设置页重构）。
///
/// 重构前的设置页是把 20 个 `ListTile` 平铺在一个 `ListView` 里：没有分区，
/// 开发者/原型入口和普通学生入口混在一起。这里把"分区标题 + 卡片 + 统一行"
/// 抽成三个零件，设置页和它的分区组件（数据/外观）共用同一套间距与层级，
/// 免得每个文件各写一份 `_SectionHeader`（原来就重复了两份）。
///
/// 层级固定为：
///  * [SettingsSectionHeader] —— 页面级分区标题（图标 + 主色标题），卡片外；
///  * [SettingsSectionCard]   —— 一个分区的卡片容器；
///  * [SettingsGroupHeader]   —— 卡片内的二级小标题（数据/题库/诊断包等）；
///  * [SettingsNavTile]       —— 统一的行：leading 图标 + 标题 +（副标题）+
///    右箭头；动作行（导入/导出）不导航，所以不用它，免得假装有下一层。
library;

import 'package:flutter/material.dart';

/// 页面级分区标题：图标 + 主色标题，可带一个 trailing 动作（开发者折叠按钮）。
class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 卡片内的二级小标题：比页面分区轻一档（次要文字色，无主色图标块）。
class SettingsGroupHeader extends StatelessWidget {
  const SettingsGroupHeader({super.key, required this.title, this.icon});

  final String title;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 15,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
          ],
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 一个分区的内容卡片：圆角 + 细描边，行与行之间不画分割线（M3 的列表间距
/// 已经够清楚，加线只会把卡片切碎）。
class SettingsSectionCard extends StatelessWidget {
  const SettingsSectionCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// 统一的导航行：leading 图标 + 标题 + 可选副标题 + 右箭头。
///
/// [tileKey] 放在内部 [ListTile] 上（测试按 key 找这一行，也按 key 点它）。
class SettingsNavTile extends StatelessWidget {
  const SettingsNavTile({
    super.key,
    this.tileKey,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final Key? tileKey;
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: tileKey,
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

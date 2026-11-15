/// 设置页顶部的「档案卡」。
///
/// 只读摘要：本机档案的名字 + 身份；点按（或右上角铅笔）改名。
/// 2026-11-15 重构前的设置页第一行只是一个 `ListTile`，名字之外什么都看不出；
/// 现在它是页面最上面一张卡，普通学生第一眼先看到"我是谁"。
///
/// 注意：`profiles` 表只有 `displayName` / `avatarColor`（见
/// `data/database/tables.dart`），没有"学习阶段"列，本次重构也不改 DB schema，
/// 所以卡片不显示一个没有数据来源的阶段字段。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/repository_providers.dart';
import '../../../l10n/app_localizations.dart';
import 'settings_providers.dart';

/// 顶部档案卡（测试按 key 找整张卡）。
const Key settingsProfileCardKey = Key('settings-profile-card');

/// 改名按钮（和整卡点按等价）。
const Key settingsProfileEditButtonKey = Key('settings-profile-edit-button');

/// 改名对话框里的输入框。
const Key settingsProfileNameFieldKey = Key('settings-profile-name-field');

class SettingsProfileCard extends ConsumerWidget {
  const SettingsProfileCard({super.key});

  /// 没有档案行时的占位名（与重构前 `settings_page.dart` 的 `User` 一致）。
  static const String fallbackDisplayName = 'User';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final rawName = profile?.displayName.trim() ?? '';
    final name = rawName.isEmpty ? fallbackDisplayName : rawName;
    final initial = _initialOf(name);

    return Card(
      key: settingsProfileCardKey,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: InkWell(
        onTap: () => _editName(context, ref),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor:
                    _avatarColor(profile?.avatarColor, theme.colorScheme),
                foregroundColor: theme.colorScheme.onPrimary,
                child: Text(
                  initial,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _IdentityChip(label: l10n.settingsProfileIdentity),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.settingsProfileEditHint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                key: settingsProfileEditButtonKey,
                tooltip: l10n.settingsProfileName,
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _editName(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 名字首字（中文按第一个字符，英文按首个字母大写）。
  static String _initialOf(String name) {
    final first = String.fromCharCode(name.runes.first);
    return first.toUpperCase();
  }

  /// 档案头像色：有 `avatarColor` 用它；没有就用主题主色（不随机，截图稳定）。
  static Color _avatarColor(int? value, ColorScheme scheme) {
    if (value == null) {
      return scheme.primary;
    }
    const palette = <Color>[
      Color(0xFF2F6F4F),
      Color(0xFF35608F),
      Color(0xFF8F5A35),
      Color(0xFF6B4F8F),
      Color(0xFF8F3545),
      Color(0xFF356F7A),
    ];
    return palette[value.abs() % palette.length];
  }

  Future<void> _editName(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(
      text: ref.read(currentProfileProvider).valueOrNull?.displayName ?? '',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsProfileName),
        content: TextField(
          key: settingsProfileNameFieldKey,
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.commonName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) {
      return;
    }
    await ref.read(settingsRepositoryProvider).updateProfileName(name);
    ref.invalidate(currentProfileProvider);
  }
}

/// 档案卡上的身份徽标（"学生"）。
class _IdentityChip extends StatelessWidget {
  const _IdentityChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

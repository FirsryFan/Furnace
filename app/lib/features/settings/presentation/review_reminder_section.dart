/// 设置页「复习提醒」区块：开关 + 每天提醒时刻。
///
/// 数据在 schema v28 的两列（`review_reminder_enabled` /
/// `review_reminder_minutes`）；排程与通知文案由
/// `features/anki/application/review_reminder_service.dart` 负责。本文件只管
/// 读写设置并把结果交给服务刷新，不自己算下一次提醒时间。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/scheduling/review_reminder_plan.dart';
import '../../../l10n/app_localizations.dart';
import '../../anki/application/review_reminder_service.dart';
import '../../anki/presentation/review_reminder_texts.dart';

/// 复习提醒在设置页里的入口行（测试与文档都按它定位）。
const Key reviewReminderSectionKey = Key('review-reminder-section');

/// 开关与时间所在的对话框。
const Key reviewReminderDialogKey = Key('review-reminder-dialog');

/// 对话框里的开关。
const Key reviewReminderSwitchKey = Key('review-reminder-switch');

/// 对话框里的「提醒时间」行（仅开启时出现）。
const Key reviewReminderTimeTileKey = Key('review-reminder-time');

/// 读侧折叠后的设置：开关 + 每天时刻（分钟，0 表示 00:00）。
class ReviewReminderSetting {
  const ReviewReminderSetting({
    required this.enabled,
    required this.minutesOfDay,
  });

  final bool enabled;
  final int minutesOfDay;
}

/// 分钟数 → `HH:mm`。
///
/// 0 分钟是 `00:00`，1439 是 `23:59`；越界值按边界显示，不抛异常（越界值
/// 根本进不了库：`SettingsRepository.updateReviewReminderMinutes` 会拒绝）。
String reviewReminderMinutesText(int minutes) {
  final clamped = minutes < 0 ? 0 : (minutes > 1439 ? 1439 : minutes);
  final hour = clamped ~/ 60;
  final minute = clamped % 60;
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// 当前开关与时刻。NULL 分钟用域层出厂默认（20:00），与升级前的行为一致。
final reviewReminderSettingsProvider =
    FutureProvider.autoDispose<ReviewReminderSetting>((ref) async {
  ref.watchDatabaseRevision();
  final repository = ref.watch(settingsRepositoryProvider);
  final enabled = await repository.getReviewReminderEnabled();
  final minutes = await repository.getReviewReminderMinutes();
  return ReviewReminderSetting(
    enabled: enabled,
    minutesOfDay: minutes ?? kDefaultReviewReminderMinutesOfDay,
  );
});

/// 设置页里的一行：标题、当前状态、点开对话框。
class ReviewReminderSection extends ConsumerWidget {
  const ReviewReminderSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // loading / error 都整块隐藏：设置页其它入口不因为有读失败而错位。
    final setting = ref.watch(reviewReminderSettingsProvider).valueOrNull;
    if (setting == null) {
      return const SizedBox.shrink();
    }
    return ListTile(
      key: reviewReminderSectionKey,
      leading: const Icon(Icons.notifications_active_outlined),
      title: Text(l10n.reviewReminderSettingTitle),
      subtitle: Text(
        setting.enabled
            ? l10n.reviewReminderSettingOn(
                reviewReminderMinutesText(setting.minutesOfDay),
              )
            : l10n.reviewReminderSettingOff,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showReviewReminderDialog(context, setting: setting),
    );
  }
}

/// 打开开关与时间对话框。
Future<void> showReviewReminderDialog(
  BuildContext context, {
  required ReviewReminderSetting setting,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ReviewReminderDialog(setting: setting),
  );
}

class _ReviewReminderDialog extends ConsumerStatefulWidget {
  const _ReviewReminderDialog({required this.setting});

  final ReviewReminderSetting setting;

  @override
  ConsumerState<_ReviewReminderDialog> createState() =>
      _ReviewReminderDialogState();
}

class _ReviewReminderDialogState extends ConsumerState<_ReviewReminderDialog> {
  late bool _enabled = widget.setting.enabled;
  late int _minutes = widget.setting.minutesOfDay;
  bool _saving = false;

  /// 改动即写库：先落库、再让读侧重读，最后让服务重排通知。
  ///
  /// 普通异常吞掉（通知排不上不该把开关卡死）；权限被拒单独提示，免得
  /// 用户以为提醒已经生效。
  Future<void> _apply({bool? enabled, int? minutes}) async {
    if (_saving) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nextEnabled = enabled ?? _enabled;
    final nextMinutes = minutes ?? _minutes;
    setState(() {
      _enabled = nextEnabled;
      _minutes = nextMinutes;
      _saving = true;
    });
    try {
      final repository = ref.read(settingsRepositoryProvider);
      if (enabled != null) {
        await repository.updateReviewReminderEnabled(nextEnabled);
      }
      if (minutes != null) {
        await repository.updateReviewReminderMinutes(nextMinutes);
      }
      ref.invalidate(reviewReminderSettingsProvider);
      final outcome = await ref
          .read(reviewReminderServiceProvider)
          .refresh(texts: reviewReminderTextsFor(l10n));
      if (!mounted) {
        return;
      }
      if (outcome.permissionDenied) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.reviewReminderPermissionDenied)),
        );
      }
    } catch (error) {
      // 排程失败（插件不可用等）不反转开关：设置已经落库，下次打开再试。
      debugPrint('复习提醒刷新失败：$error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _pickTime() async {
    if (_saving) {
      return;
    }
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _minutes ~/ 60, minute: _minutes % 60),
    );
    if (picked == null || !mounted) {
      return;
    }
    await _apply(minutes: picked.hour * 60 + picked.minute);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      key: reviewReminderDialogKey,
      title: Text(l10n.reviewReminderDialogTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              key: reviewReminderSwitchKey,
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.reviewReminderToggleTitle),
              subtitle: Text(l10n.reviewReminderToggleHint),
              value: _enabled,
              onChanged: _saving ? null : (value) => _apply(enabled: value),
            ),
            if (_enabled)
              ListTile(
                key: reviewReminderTimeTileKey,
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.reviewReminderTimeLabel),
                trailing: Text(
                  reviewReminderMinutesText(_minutes),
                  style: theme.textTheme.titleMedium,
                ),
                onTap: _saving ? null : _pickTime,
              ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.reviewReminderDialogBody,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
      ],
    );
  }
}

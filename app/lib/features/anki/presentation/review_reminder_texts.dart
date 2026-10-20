/// 复习提醒通知文案：把 `AppLocalizations` 翻成服务层要的
/// `ReviewReminderTexts`。
///
/// 服务层（`features/anki/application/review_reminder_service.dart`）不依赖
/// l10n，只认纯字符串与回调；标题与正文跟随当前界面语言。
library;

import '../../../l10n/app_localizations.dart';
import '../application/review_reminder_service.dart';

/// 按 [AppLocalizations] 组装通知标题与正文。
ReviewReminderTexts reviewReminderTextsFor(AppLocalizations l10n) {
  return ReviewReminderTexts(
    title: l10n.reviewReminderNotificationTitle,
    dueNowBody: (count) => l10n.reviewReminderNotificationDueBody(count),
    dueSoonBody: l10n.reviewReminderNotificationSoonBody,
  );
}

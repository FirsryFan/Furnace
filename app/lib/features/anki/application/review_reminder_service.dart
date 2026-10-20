/// 复习提醒的 application 层：读设置与到期数据，规划时刻，落到本地通知。
///
/// 这一层只做编排，不放判断逻辑：读数来自 `SettingsRepository` /
/// `AnkiRepository`，时刻规划是纯函数 `planReviewReminder`，通知由
/// `ReminderNotifier` 执行。所以测试只需要内存库 + fake notifier，
/// 不需要 Flutter 插件，也不需要真实系统闹钟。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/notification_provider.dart';
import '../../../core/notifications/reminder_notifier.dart';
import '../../../data/repositories/anki_repository.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../domain/services/scheduling/review_reminder_plan.dart';

/// 复习提醒占用的本地通知 id。
///
/// 任务提醒也用同一套通知 id 命名空间（`task.id.hashCode & 0x7fffffff`），
/// 所以理论上有 1/2^31 的概率正好撞上某条任务的 id。换这个常量只会让已经
/// 排上的旧复习提醒失效（数据不动），代价远小于给通知另造一套存储，
/// 因此这里接受这点理论碰撞。
const int kReviewReminderNotificationId = 20261021;

/// [ReviewReminderService.refresh] 需要的文案，由 UI 层注入。
///
/// application 层不硬编码中文（l10n 由页面负责），这里只描述三段文字的形状。
class ReviewReminderTexts {
  const ReviewReminderTexts({
    required this.title,
    required this.dueNowBody,
    required this.dueSoonBody,
  });

  /// 通知标题；dueSoon 复用同一个标题，只有正文不同。
  final String title;

  /// 现在就有到期卡时的正文；带上张数，比只说「有卡到期」有用。
  final String Function(int dueCardCount) dueNowBody;

  /// 今天还有卡在偏好时刻之前到期时的正文。
  final String dueSoonBody;
}

/// 一次 [ReviewReminderService.refresh] 的结果。
///
/// 字段口径（反直觉但固定，调用方不要自己改语义）：
/// - [cancelled] 表示「这次 refresh 调用过取消」，不是「最终没有提醒」。
///   成功排程时它也是 true：refresh 的口径是 cancel-then-schedule，先清掉
///   上一次排的通知再按新计划重排，这样重复调用是幂等重置，不会叠出两条。
/// - [scheduled] 表示这次是否排了提醒。
/// - [permissionDenied] 只在「应该排、但系统不给通知权限」（notifier 返回
///   false）时为 true。
class ReviewReminderOutcome {
  const ReviewReminderOutcome({
    required this.plan,
    required this.scheduled,
    required this.cancelled,
    required this.permissionDenied,
  });

  /// 这次算出来的计划（含原因与时刻）。
  final ReviewReminderPlan plan;

  /// 这次是否成功排上提醒。
  final bool scheduled;

  /// 这次 refresh 是否调用过取消（成功排程时也为 true，见类注释）。
  final bool cancelled;

  /// 应该排但系统没给权限时为 true；其余情况一律 false。
  final bool permissionDenied;

  /// 键是 snake_case（与 plan / 组卷等既有 toJson 风格一致）；[plan] 内嵌
  /// `plan.toJson()`，不把它的字段平铺进来。
  Map<String, Object?> toJson() => <String, Object?>{
        'scheduled': scheduled,
        'cancelled': cancelled,
        'permission_denied': permissionDenied,
        'plan': plan.toJson(),
      };
}

/// 把「复习提醒该不该排、排在什么时候」落到系统本地通知上。
///
/// 每次 [refresh] 都是完整重算 + 幂等重置（先取消再按新计划排），调用方
/// 可以在设置变化、应用回到前台、复习完一批卡之后都直接调它。
class ReviewReminderService {
  ReviewReminderService({
    required SettingsRepository settings,
    required AnkiRepository anki,
    required ReminderNotifier notifier,
    DateTime Function()? clock,
    int notificationId = kReviewReminderNotificationId,
  })  : _settings = settings,
        _anki = anki,
        _notifier = notifier,
        _clock = clock ?? DateTime.now,
        _notificationId = notificationId;

  final SettingsRepository _settings;
  final AnkiRepository _anki;
  final ReminderNotifier _notifier;

  /// 注入的时钟（默认 [DateTime.now]）。
  ///
  /// 到期查询与「下一次到期」查询都用这个时钟的毫秒值，不能在里面混用
  /// `DateTime.now()`：测试注入了固定时刻，仓储却按真实时间过滤，两边就
  /// 不同步了。
  final DateTime Function() _clock;

  /// 这条提醒占用的通知 id。
  final int _notificationId;

  /// 重新算一次复习提醒并落到通知上；每次调用都是幂等重置。
  ///
  /// 固定流程：
  /// 1. 读设置（开关 + 偏好时刻，NULL 时刻读域层默认 20:00），数到期卡，
  ///    找下一次到期。
  /// 2. 交给 `planReviewReminder` 算计划。
  /// 3. 先取消旧通知，再按计划决定排不排（顺序固定，见下方注释）。
  ///
  /// 排程口径：
  /// - 开关关掉 → 只取消。
  /// - 有到期卡 → 排到严格晚于 now 的下一个偏好时刻，正文用
  ///   [ReviewReminderTexts.dueNowBody]（带张数）。
  /// - 没有到期卡、下一次到期严格早于偏好时刻 → 排到下一次到期，正文用
  ///   [ReviewReminderTexts.dueSoonBody]。
  /// - 其余 → 只取消。
  ///
  /// 通知插件的异常不在这里吞掉：调用方（设置页/启动接线）自己 try/catch，
  /// 否则应用层会把「没排上」误当成成功。
  Future<ReviewReminderOutcome> refresh({
    required ReviewReminderTexts texts,
  }) async {
    final DateTime now = _clock();
    final bool enabled = await _settings.getReviewReminderEnabled();
    final int minutes = await _settings.getReviewReminderMinutes() ??
        kDefaultReviewReminderMinutesOfDay;
    final int nowMillis = now.millisecondsSinceEpoch;
    final int dueCardCount = (await _anki.getDueCardStates(nowMillis)).length;
    final int? nextDueAtMillis = await _anki.nextDueAtAfter(nowMillis);
    final ReviewReminderPlan plan = planReviewReminder(
      now: now,
      preferredMinutesOfDay: minutes,
      dueCardCount: dueCardCount,
      nextDueAtMillis: nextDueAtMillis,
      enabled: enabled,
    );
    // 先取消：上一次 refresh 排过的通知不该和这一次并存（幂等重置）。
    await _notifier.cancelReminder(_notificationId);
    if (!plan.shouldSchedule) {
      return ReviewReminderOutcome(
        plan: plan,
        scheduled: false,
        cancelled: true,
        permissionDenied: false,
      );
    }
    final String body = plan.reason == ReviewReminderReason.dueNow
        ? texts.dueNowBody(plan.dueCardCount)
        : texts.dueSoonBody;
    final bool scheduled = await _notifier.scheduleReminder(
      id: _notificationId,
      title: texts.title,
      body: body,
      when: plan.when!,
    );
    return ReviewReminderOutcome(
      plan: plan,
      scheduled: scheduled,
      cancelled: true,
      permissionDenied: !scheduled,
    );
  }
}

/// 应用内默认的复习提醒服务（真机通知实现 + 真实仓储）。
final reviewReminderServiceProvider = Provider<ReviewReminderService>((ref) {
  return ReviewReminderService(
    settings: ref.watch(settingsRepositoryProvider),
    anki: ref.watch(ankiRepositoryProvider),
    notifier: ref.watch(notificationServiceProvider),
  );
});

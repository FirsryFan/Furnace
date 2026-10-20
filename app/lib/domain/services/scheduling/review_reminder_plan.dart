/// 复习提醒时刻规划（纯逻辑）。
///
/// 把「下一次复习提醒该排在什么时候」算成一个纯函数：不读系统时钟、不写通知、
/// 不碰数据库与 IO，输入输出都是普通 Dart 值，方便 application 层注入：
///
/// ```dart
/// final plan = planReviewReminder(
///   now: DateTime.now(),
///   preferredMinutesOfDay: 20 * 60,
///   dueCardCount: dueStates.length,
///   nextDueAtMillis: earliestDueAt?.millisecondsSinceEpoch,
/// );
/// if (plan.shouldSchedule) {
///   // 用 plan.when（必然晚于 now）去排本地通知。
/// }
/// ```
///
/// 口径（与 task-98 契约一致）：
/// - [planReviewReminder] 永不抛异常；极端毫秒时间戳视为「没有下一次到期」。
/// - `enabled == false` 压过一切，返回 [ReviewReminderReason.disabled]。
/// - 有到期卡 → [ReviewReminderReason.dueNow]，排到严格晚于 `now` 的下一个偏好时刻。
/// - 没有到期卡但有 `nextDueAtMillis`：已过期 → `dueNow`；严格早于偏好时刻 →
///   [ReviewReminderReason.dueSoon]（排到下一次到期）；否则
///   [ReviewReminderReason.nothingDue]。
/// - 偏好分钟数 clamp 到 `0..1439`，`dueCardCount` clamp 到 `>= 0`。
library;

/// 计划给出这一时刻的原因。
enum ReviewReminderReason {
  /// 现在就有到期卡（或者下一次到期时间已经过去）。
  dueNow,

  /// 没有到期卡，但下一次到期严格早于下一个偏好提醒时刻。
  dueSoon,

  /// 没有到期卡，也没有更早的下一次到期。
  nothingDue,

  /// 用户关掉了复习提醒；压过其它所有判断。
  disabled,
}

/// 默认偏好提醒时刻：20:00。
const int kDefaultReviewReminderMinutesOfDay = 20 * 60;

const int _kMinutesPerDay = 24 * 60;
const int _kLastMinuteOfDay = _kMinutesPerDay - 1;

/// 一次复习提醒规划结果。
///
/// [when] 只在 [shouldSchedule] 为 true 时给出，且保证严格晚于调用方的 `now`。
class ReviewReminderPlan {
  const ReviewReminderPlan({
    required this.shouldSchedule,
    required this.reason,
    required this.dueCardCount,
    this.when,
  });

  /// 是否应该排提醒。
  final bool shouldSchedule;

  /// 为什么给出这个计划。
  final ReviewReminderReason reason;

  /// 到期卡数量，已 clamp 到 `>= 0`。
  final int dueCardCount;

  /// 提醒时刻；只有 [shouldSchedule] 为 true 时非空。
  final DateTime? when;

  /// 不需要排提醒时为 true。
  bool get isEmpty => !shouldSchedule;

  Map<String, Object?> toJson() => <String, Object?>{
        'should_schedule': shouldSchedule,
        'reason': reason.name,
        'due_card_count': dueCardCount,
        'when': when?.toIso8601String(),
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ReviewReminderPlan &&
        other.shouldSchedule == shouldSchedule &&
        other.reason == reason &&
        other.dueCardCount == dueCardCount &&
        other.when?.millisecondsSinceEpoch == when?.millisecondsSinceEpoch;
  }

  @override
  int get hashCode => Object.hash(
        shouldSchedule,
        reason,
        dueCardCount,
        when?.millisecondsSinceEpoch,
      );

  @override
  String toString() => 'ReviewReminderPlan(shouldSchedule: $shouldSchedule, '
      'reason: ${reason.name}, dueCardCount: $dueCardCount, '
      'when: ${when?.toIso8601String()})';
}

/// 规划下一次复习提醒应该排在什么时候。
///
/// 纯函数：[now] 由调用方注入，不读系统时钟；永不抛异常。参数口径见库注释。
ReviewReminderPlan planReviewReminder({
  required DateTime now,
  required int preferredMinutesOfDay,
  required int dueCardCount,
  int? nextDueAtMillis,
  bool enabled = true,
}) {
  final int cards = dueCardCount < 0 ? 0 : dueCardCount;
  final int safeMinutes = _clampMinutesOfDay(preferredMinutesOfDay);
  if (!enabled) {
    return ReviewReminderPlan(
      shouldSchedule: false,
      reason: ReviewReminderReason.disabled,
      dueCardCount: cards,
    );
  }
  final DateTime nextPreferred = _nextPreferredTime(now, safeMinutes);
  if (cards > 0) {
    return ReviewReminderPlan(
      shouldSchedule: true,
      reason: ReviewReminderReason.dueNow,
      dueCardCount: cards,
      when: nextPreferred,
    );
  }
  if (nextDueAtMillis != null) {
    DateTime? nextDue;
    try {
      nextDue = DateTime.fromMillisecondsSinceEpoch(nextDueAtMillis);
    } catch (_) {
      // 极端毫秒戳超出 DateTime 可表示范围，按「没有下一次到期」处理。
      nextDue = null;
    }
    if (nextDue != null) {
      if (!nextDue.isAfter(now)) {
        return ReviewReminderPlan(
          shouldSchedule: true,
          reason: ReviewReminderReason.dueNow,
          dueCardCount: cards,
          when: nextPreferred,
        );
      }
      if (nextDue.isBefore(nextPreferred)) {
        return ReviewReminderPlan(
          shouldSchedule: true,
          reason: ReviewReminderReason.dueSoon,
          dueCardCount: cards,
          when: nextDue,
        );
      }
    }
  }
  return ReviewReminderPlan(
    shouldSchedule: false,
    reason: ReviewReminderReason.nothingDue,
    dueCardCount: cards,
  );
}

int _clampMinutesOfDay(int value) {
  if (value < 0) {
    return 0;
  }
  if (value > _kLastMinuteOfDay) {
    return _kLastMinuteOfDay;
  }
  return value;
}

DateTime _nextPreferredTime(DateTime now, int minutesOfDay) {
  final int hour = minutesOfDay ~/ 60;
  final int minute = minutesOfDay % 60;
  final DateTime today = DateTime(now.year, now.month, now.day, hour, minute);
  if (today.isAfter(now)) {
    return today;
  }
  // 用日期构造器加法让月末、年末、闰年由 DateTime 自动进位；
  // 不要用 Duration(days: 1)，否则夏令时/跨月会算错。
  return DateTime(now.year, now.month, now.day + 1, hour, minute);
}

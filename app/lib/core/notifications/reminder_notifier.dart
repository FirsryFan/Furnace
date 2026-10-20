/// 本地通知的最小抽象（纯 Dart 接口，不依赖 Flutter 插件）。
///
/// 复习提醒服务只认这个接口：真机实现是 `NotificationService`
/// （flutter_local_notifications），测试里换成记录调用的 fake，
/// application 层因此不直接依赖通知插件，也不需要初始化插件。
library;

/// 排一条一次性本地提醒通知的抽象。
abstract interface class ReminderNotifier {
  /// 在 [when] 排一条标题 [title]、正文 [body] 的通知，沿用调用方给的 [id]。
  ///
  /// 返回系统是否会真的显示它：Android 13+ 的用户拒绝了通知权限时返回
  /// false，调用方应当告诉用户，而不是让用户以为提醒已经排上。
  Future<bool> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  });

  /// 取消 [id] 对应的通知；没有排过时也必须是安全的空操作。
  Future<void> cancelReminder(int id);
}

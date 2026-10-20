import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'reminder_notifier.dart';

/// Local notification wrapper for event reminders.
///
/// Branding: the app is Furnace, so the Windows notification entry
/// and the Android channel say so too. The Windows AppUserModelId and GUID must
/// stay stable per installation - changing them makes Windows treat the app as
/// a different program and drops previously scheduled reminders, so they are
/// only ever changed together with a note in PROGRESS.md.
class NotificationService implements ReminderNotifier {
  NotificationService() {
    tzdata.initializeTimeZones();
  }

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// 插件初始化：第一次排程/取消时才做，而且只做一次。
  ///
  /// 以前放在构造函数里，问题是没有平台实现的环境（widget test、以及只挂着
  /// 外壳但没人用通知的页面）一构造就抛 `LateInitializationError`，把与通知
  /// 无关的界面一起拖垮。改成惰性之后，构造只准备时区库（纯 Dart），失败与否
  /// 由真正调用排程/取消的那条路径决定——服务层已经写明异常由调用方处理。
  Future<bool?>? _initialized;

  Future<bool?> _ensureInitialized() {
    return _initialized ??= _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        windows: WindowsInitializationSettings(
          appName: 'Furnace',
          appUserModelId: 'com.furnace.app',
          guid: 'b7c4e1a2-3f56-4d18-9a70-2c8e5f0b1d33',
        ),
      ),
    );
  }

  /// The answer to "may we post notifications here?", cached per run.
  bool? _permissionGranted;

  /// Schedules a one-shot local notification at [when].
  ///
  /// Returns **false when the system will not show it** - on Android 13+ the
  /// notification permission is a runtime one, and a refused permission means
  /// the reminder is silently dropped by the OS. The caller is expected to tell
  /// the user rather than let them believe the reminder was armed.
  ///
  /// The scheduling itself is done with `TZDateTime.from`, which keeps the
  /// *instant* (`when` is an absolute moment, however it is rendered). The
  /// timezone database is only needed because the plugin's API demands a
  /// `TZDateTime`; no local-location lookup is involved, so a phone set to any
  /// timezone fires at the moment the user picked.
  @override
  Future<bool> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    await _ensureInitialized();
    if (!await _mayPostNotifications()) {
      return false;
    }
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(when, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'reminders',
          'Task reminders',
          channelDescription: 'Notifications for task reminders',
        ),
        windows: WindowsNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
    return true;
  }

  /// Cancels a scheduled reminder by id.
  @override
  Future<void> cancelReminder(int id) async {
    await _ensureInitialized();
    await _plugin.cancel(id: id);
  }

  /// Asks Android for the notification permission, once per app run.
  ///
  /// Android 13 (API 33) turned `POST_NOTIFICATIONS` into a runtime permission:
  /// the manifest entry declares the intent, but until the app asks, the system
  /// never shows the dialog and every notification is dropped. That made task
  /// reminders do nothing at all on a current phone while looking scheduled.
  /// On older Android and on the desktop platforms there is nothing to ask, and
  /// the plugin's own implementation simply answers true.
  Future<bool> _mayPostNotifications() async {
    final cached = _permissionGranted;
    if (cached != null) {
      return cached;
    }
    if (!Platform.isAndroid) {
      _permissionGranted = true;
      return true;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission() ?? false;
    _permissionGranted = granted;
    return granted;
  }
}

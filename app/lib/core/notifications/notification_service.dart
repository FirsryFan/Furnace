import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Local notification wrapper for event reminders.
///
/// Branding: the app is Furnace, so the Windows notification entry
/// and the Android channel say so too. The Windows AppUserModelId and GUID must
/// stay stable per installation - changing them makes Windows treat the app as
/// a different program and drops previously scheduled reminders, so they are
/// only ever changed together with a note in PROGRESS.md.
class NotificationService {
  NotificationService() {
    tzdata.initializeTimeZones();
    _initialized = _plugin.initialize(
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

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  late final Future<bool?> _initialized;

  /// Schedules a one-shot local notification at [when].
  Future<void> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    await _initialized;
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
  }

  /// Cancels a scheduled reminder by id.
  Future<void> cancelReminder(int id) async {
    await _initialized;
    await _plugin.cancel(id: id);
  }
}

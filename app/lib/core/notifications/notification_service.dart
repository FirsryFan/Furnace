import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Local notification wrapper for task reminders.
class NotificationService {
  NotificationService() {
    tzdata.initializeTimeZones();
    _initialized = _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        windows: WindowsInitializationSettings(
          appName: 'KnowFlow',
          appUserModelId: 'com.knowflow.app',
          guid: 'a1b2c3d4-0000-0000-0000-000000000000',
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

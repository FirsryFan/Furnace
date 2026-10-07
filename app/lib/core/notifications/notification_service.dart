import 'dart:io';

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
  Future<bool> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    await _initialized;
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
  Future<void> cancelReminder(int id) async {
    await _initialized;
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

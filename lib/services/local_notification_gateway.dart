import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'notification_gateway.dart';
import 'reminder_schedule.dart';

/// [NotificationGateway] backed by `flutter_local_notifications`.
///
/// Every call is best-effort: if the plugin or the platform is unavailable the
/// app keeps working without reminders.
class LocalNotificationGateway implements NotificationGateway {
  LocalNotificationGateway({
    FlutterLocalNotificationsPlugin? plugin,
    this.onReminderTapped,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _channelId = 'study_reminders';
  static const _channelName = 'Study Reminders';
  static const _channelDescription =
      'A quiet daily reminder about the kanji left today.';

  final FlutterLocalNotificationsPlugin _plugin;

  /// Called when the user taps a reminder while the app is running.
  final VoidCallback? onReminderTapped;

  Future<bool>? _initialization;

  /// Prepares the plugin and the local time zone database once.
  Future<bool> _ensureInitialized() {
    return _initialization ??= _initialize();
  }

  Future<bool> _initialize() async {
    try {
      tz_data.initializeTimeZones();
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));

      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // Permission is requested later, when the user turns reminders on.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: _handleResponse,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  void _handleResponse(NotificationResponse response) {
    if (response.payload != dailyReminderKey) return;
    onReminderTapped?.call();
  }

  @override
  Future<NotificationPermission> permission() async {
    if (!await _ensureInitialized()) return NotificationPermission.denied;

    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        final enabled = await android.areNotificationsEnabled();
        return enabled ?? false
            ? NotificationPermission.granted
            : NotificationPermission.denied;
      }

      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        final options = await ios.checkPermissions();
        if (options == null) return NotificationPermission.notDetermined;
        return options.isEnabled
            ? NotificationPermission.granted
            : NotificationPermission.denied;
      }
    } catch (_) {
      return NotificationPermission.denied;
    }

    // Platforms without a permission prompt.
    return NotificationPermission.granted;
  }

  @override
  Future<NotificationPermission> requestPermission() async {
    if (!await _ensureInitialized()) return NotificationPermission.denied;

    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        final granted = await android.requestNotificationsPermission();
        return granted ?? false
            ? NotificationPermission.granted
            : NotificationPermission.denied;
      }

      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        final granted = await ios.requestPermissions(alert: true);
        return granted ?? false
            ? NotificationPermission.granted
            : NotificationPermission.denied;
      }
    } catch (_) {
      return NotificationPermission.denied;
    }

    return NotificationPermission.granted;
  }

  @override
  Future<void> cancelDailyReminder() async {
    if (!await _ensureInitialized()) return;
    try {
      await _plugin.cancel(id: dailyReminderId);
    } catch (_) {
      // A reminder that cannot be cancelled must not break the app.
    }
  }

  @override
  Future<void> scheduleDailyReminder({
    required DateTime when,
    required String title,
    required String body,
  }) async {
    if (!await _ensureInitialized()) return;

    try {
      await _plugin.zonedSchedule(
        id: dailyReminderId,
        title: title,
        body: body,
        payload: dailyReminderKey,
        scheduledDate: tz.TZDateTime.from(when, tz.local),
        // A study reminder does not warrant an exact alarm.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.low,
            priority: Priority.low,
          ),
          iOS: DarwinNotificationDetails(
            presentBadge: false,
            presentSound: false,
          ),
        ),
      );
    } catch (_) {
      // Scheduling is best-effort; studying continues either way.
    }
  }

  @override
  Future<bool> openSystemSettings() async {
    if (!await _ensureInitialized()) return false;
    try {
      return await _plugin.openAppNotificationSettings() ?? false;
    } catch (_) {
      return false;
    }
  }
}

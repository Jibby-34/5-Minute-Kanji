import 'package:fiveminutekanji/services/notification_gateway.dart';

/// Records what the scheduler asked the OS to do.
class FakeNotificationGateway implements NotificationGateway {
  FakeNotificationGateway({
    this.permissionStatus = NotificationPermission.granted,
    this.permissionOnRequest,
    this.failOnSchedule = false,
  });

  NotificationPermission permissionStatus;

  /// Answer given to [requestPermission]. Defaults to [permissionStatus].
  NotificationPermission? permissionOnRequest;

  /// Simulates a broken notification plugin.
  bool failOnSchedule;

  final List<ScheduledNotification> scheduled = [];
  int cancelCount = 0;
  int requestCount = 0;
  int openSettingsCount = 0;

  /// The reminder the OS is currently holding, if any.
  ScheduledNotification? get pending =>
      scheduled.isEmpty ? null : scheduled.last;

  bool get hasPending => pending != null;

  @override
  Future<NotificationPermission> permission() async => permissionStatus;

  @override
  Future<NotificationPermission> requestPermission() async {
    requestCount++;
    permissionStatus = permissionOnRequest ?? permissionStatus;
    return permissionStatus;
  }

  @override
  Future<void> cancelDailyReminder() async {
    cancelCount++;
    scheduled.clear();
  }

  @override
  Future<void> scheduleDailyReminder({
    required DateTime when,
    required String title,
    required String body,
  }) async {
    if (failOnSchedule) {
      throw StateError('notification plugin unavailable');
    }
    scheduled.add(ScheduledNotification(when: when, title: title, body: body));
  }

  @override
  Future<bool> openSystemSettings() async {
    openSettingsCount++;
    return true;
  }
}

class ScheduledNotification {
  const ScheduledNotification({
    required this.when,
    required this.title,
    required this.body,
  });

  final DateTime when;
  final String title;
  final String body;

  @override
  String toString() => 'ScheduledNotification($when, "$title", "$body")';
}

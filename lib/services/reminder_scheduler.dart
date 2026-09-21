import '../core/utils/clock.dart';
import '../repositories/progress_repository.dart';
import 'daily_workload.dart';
import 'notification_gateway.dart';
import 'reminder_schedule.dart';

/// Owns the app's single daily reminder.
///
/// Call [reschedule] whenever something that can change today's workload
/// settles: app start or resume, a finished sitting, or a settings change.
/// The SRS engine knows nothing about this.
class ReminderScheduler {
  ReminderScheduler({
    required this.gateway,
    required this.progressRepository,
    required this.workloadService,
    Clock? clock,
  }) : clock = clock ?? DateTime.now;

  final NotificationGateway gateway;
  final ProgressRepository progressRepository;
  final DailyWorkloadService workloadService;
  final Clock clock;

  Future<void> _queue = Future<void>.value();

  /// Cancels the pending reminder and schedules at most one replacement.
  ///
  /// Never throws: a failing notification stack must not stop the user from
  /// studying.
  Future<void> reschedule() {
    // Serialised so two overlapping calls cannot interleave cancel/schedule.
    _queue = _queue.then((_) => _reschedule());
    return _queue;
  }

  Future<void> _reschedule() async {
    try {
      final settings = await progressRepository.getSettings();
      final notifications = settings.notifications;

      await gateway.cancelDailyReminder();
      if (!notifications.dailyReminderEnabled) return;
      if (await gateway.permission() != NotificationPermission.granted) return;

      final now = clock();
      final reminder = planDailyReminder(
        now: now,
        notifications: notifications,
        startOfDay: settings.startOfDay,
        workload: await workloadService.read(now: now),
      );
      if (reminder == null) return;

      await gateway.scheduleDailyReminder(
        when: reminder.scheduledFor,
        title: reminderTitle,
        body: reminder.body,
      );
    } catch (_) {
      // Leave the reminder cancelled rather than propagate the failure.
    }
  }

  Future<NotificationPermission> permission() => gateway.permission();

  /// Asks the OS for permission, then brings the reminder in line with the
  /// answer.
  Future<NotificationPermission> requestPermission() async {
    final result = await gateway.requestPermission();
    await reschedule();
    return result;
  }

  Future<bool> openSystemSettings() => gateway.openSystemSettings();
}

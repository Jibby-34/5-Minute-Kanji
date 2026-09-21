import 'package:flutter/foundation.dart';

import '../../core/models/notification_settings.dart';
import '../../core/models/progress.dart';
import '../../core/models/start_of_day.dart';
import '../../repositories/progress_repository.dart';
import '../../services/daily_workload_estimator.dart';
import '../../services/notification_gateway.dart';
import '../../services/reminder_scheduler.dart';

class SettingsController extends ChangeNotifier {
  SettingsController({
    required this.progressRepository,
    this.reminderScheduler,
    this.estimator = const DailyWorkloadEstimator(),
  });

  final ProgressRepository progressRepository;

  /// Absent in tests and on platforms without notifications.
  final ReminderScheduler? reminderScheduler;
  final DailyWorkloadEstimator estimator;

  bool loading = true;
  AppSettings settings = const AppSettings();
  DailyWorkloadEstimate estimate = const DailyWorkloadEstimate(
    minMinutes: 0,
    maxMinutes: 0,
  );
  NotificationPermission notificationPermission =
      NotificationPermission.granted;

  /// Whether the OS prompt has already been shown this session. Once it has,
  /// the only way back is system settings.
  bool permissionRequested = false;

  int get newKanjiPerDay => settings.newKanjiPerDay;

  StartOfDay get startOfDay => settings.startOfDay;

  NotificationSettings get notifications => settings.notifications;

  bool get dailyReminderEnabled => notifications.dailyReminderEnabled;

  ReminderTime get reminderTime => notifications.reminderTime;

  /// True when reminders are on but the OS will not deliver them.
  bool get remindersBlockedBySystem =>
      dailyReminderEnabled &&
      notificationPermission != NotificationPermission.granted;

  /// Whether the block can still be cleared with an in-app prompt. Once the OS
  /// has been asked, only system settings can turn notifications back on.
  bool get canRequestPermission =>
      !permissionRequested &&
      notificationPermission != NotificationPermission.granted;

  Future<void> load() async {
    loading = true;
    notifyListeners();

    try {
      settings = await progressRepository.getSettings();
      _refreshEstimate();
    } catch (_) {
      settings = const AppSettings();
      _refreshEstimate();
    }

    await _refreshPermission();

    loading = false;
    notifyListeners();
  }

  Future<void> setNewKanjiPerDay(int value) async {
    final clamped = AppSettings.clampNewKanjiPerDay(value);
    if (clamped == settings.newKanjiPerDay && !loading) {
      _refreshEstimate();
      notifyListeners();
      return;
    }

    settings = settings.copyWith(newKanjiPerDay: clamped);
    _refreshEstimate();
    notifyListeners();
    await progressRepository.saveSettings(settings);
    await reminderScheduler?.reschedule();
  }

  Future<void> setStartOfDay(StartOfDay value) async {
    final next = StartOfDay.normalize(hour: value.hour, minute: value.minute);
    if (next == settings.startOfDay && !loading) return;

    settings = settings.copyWith(startOfDay: next);
    notifyListeners();
    await progressRepository.saveSettings(settings);
    // The reminder is pinned to a study day, which just moved.
    await reminderScheduler?.reschedule();
  }

  Future<void> setDailyReminderEnabled(bool value) async {
    if (value == dailyReminderEnabled && !loading) return;

    await _saveNotifications(
      notifications.copyWith(dailyReminderEnabled: value),
    );

    // The permission prompt belongs here: the user has just asked for
    // reminders, and nowhere else in the app interrupts them for it.
    if (value && notificationPermission != NotificationPermission.granted) {
      await requestPermission();
    }
  }

  Future<void> setReminderTime(ReminderTime value) async {
    final next = ReminderTime.normalize(hour: value.hour, minute: value.minute);
    if (next == reminderTime && !loading) return;

    await _saveNotifications(notifications.copyWith(reminderTime: next));
  }

  Future<void> requestPermission() async {
    final scheduler = reminderScheduler;
    if (scheduler == null) return;

    permissionRequested = true;
    notificationPermission = await scheduler.requestPermission();
    notifyListeners();
  }

  Future<void> openSystemNotificationSettings() async {
    await reminderScheduler?.openSystemSettings();
  }

  /// Picks up a permission change made in system settings while the app was in
  /// the background.
  Future<void> refreshPermission() async {
    await _refreshPermission();
    notifyListeners();
    await reminderScheduler?.reschedule();
  }

  Future<void> _saveNotifications(NotificationSettings next) async {
    settings = settings.copyWith(notifications: next);
    notifyListeners();
    await progressRepository.saveSettings(settings);
    await reminderScheduler?.reschedule();
  }

  Future<void> _refreshPermission() async {
    final scheduler = reminderScheduler;
    if (scheduler == null) return;
    try {
      notificationPermission = await scheduler.permission();
    } catch (_) {
      notificationPermission = NotificationPermission.granted;
    }
  }

  void _refreshEstimate() {
    estimate = estimator.estimate(
      newKanjiPerDay: settings.newKanjiPerDay,
      averageSecondsPerCard: settings.averageSecondsPerCard,
    );
  }
}

/// What the operating system currently allows.
enum NotificationPermission {
  /// The app may post notifications.
  granted,

  /// The user has been asked and notifications are off. Re-enabling them may
  /// require a trip to system settings.
  denied,

  /// The user has not been asked yet.
  notDetermined,
}

/// The device-side half of the reminder system.
///
/// Keeping this behind an interface lets the scheduling rules be tested
/// without Android or iOS.
abstract class NotificationGateway {
  Future<NotificationPermission> permission();

  /// Asks the OS for permission. Only call this in response to the user
  /// turning reminders on.
  Future<NotificationPermission> requestPermission();

  Future<void> cancelDailyReminder();

  /// Replaces any pending daily reminder with one scheduled for [when].
  Future<void> scheduleDailyReminder({
    required DateTime when,
    required String title,
    required String body,
  });

  /// Opens the OS notification settings for this app. Returns whether a
  /// settings screen could be opened.
  Future<bool> openSystemSettings();
}

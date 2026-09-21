/// Time of day the daily study reminder fires. Default is 7:00 PM.
///
/// Kept free of Flutter types so reminder scheduling can be unit-tested
/// without a widget tree or a platform channel.
class ReminderTime {
  const ReminderTime({this.hour = defaultHour, this.minute = defaultMinute});

  static const int defaultHour = 19;
  static const int defaultMinute = 0;
  static const defaults = ReminderTime();

  final int hour;
  final int minute;

  static ReminderTime normalize({required int hour, required int minute}) {
    return ReminderTime(hour: hour.clamp(0, 23), minute: minute.clamp(0, 59));
  }

  /// Minutes elapsed since local midnight. Used to order a reminder against
  /// the configurable start of day.
  int get minutesFromMidnight => hour * 60 + minute;

  @override
  bool operator ==(Object other) {
    return other is ReminderTime &&
        hour == other.hour &&
        minute == other.minute;
  }

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() =>
      'ReminderTime(${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')})';
}

/// Everything the MVP reminder system needs to remember.
///
/// Stored inside [AppSettings] so reminders share the app's existing local
/// persistence instead of introducing a second store.
class NotificationSettings {
  const NotificationSettings({
    this.dailyReminderEnabled = true,
    this.reminderTime = ReminderTime.defaults,
  });

  static const defaults = NotificationSettings();

  final bool dailyReminderEnabled;
  final ReminderTime reminderTime;

  NotificationSettings copyWith({
    bool? dailyReminderEnabled,
    ReminderTime? reminderTime,
  }) {
    return NotificationSettings(
      dailyReminderEnabled: dailyReminderEnabled ?? this.dailyReminderEnabled,
      reminderTime: reminderTime ?? this.reminderTime,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dailyReminderEnabled': dailyReminderEnabled,
      'reminderHour': reminderTime.hour,
      'reminderMinute': reminderTime.minute,
    };
  }

  static NotificationSettings fromJson(Map<String, dynamic>? json) {
    if (json == null) return defaults;
    return NotificationSettings(
      dailyReminderEnabled: json['dailyReminderEnabled'] as bool? ?? true,
      reminderTime: ReminderTime.normalize(
        hour:
            (json['reminderHour'] as num?)?.toInt() ?? ReminderTime.defaultHour,
        minute:
            (json['reminderMinute'] as num?)?.toInt() ??
            ReminderTime.defaultMinute,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is NotificationSettings &&
        dailyReminderEnabled == other.dailyReminderEnabled &&
        reminderTime == other.reminderTime;
  }

  @override
  int get hashCode => Object.hash(dailyReminderEnabled, reminderTime);
}

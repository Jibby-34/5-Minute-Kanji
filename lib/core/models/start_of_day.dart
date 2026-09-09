/// When the user's study day begins. Default is 4:00 AM.
///
/// All daily study logic (new-kanji limits, review windows, streaks)
/// should go through this type instead of assuming midnight.
class StartOfDay {
  const StartOfDay({this.hour = defaultHour, this.minute = defaultMinute});

  static const int defaultHour = 4;
  static const int defaultMinute = 0;
  static const defaults = StartOfDay();

  final int hour;
  final int minute;

  static StartOfDay normalize({required int hour, required int minute}) {
    return StartOfDay(hour: hour.clamp(0, 23), minute: minute.clamp(0, 59));
  }

  /// Calendar date of the study day that contains [now] (midnight local).
  ///
  /// Times before today's start belong to the previous calendar date.
  /// At exactly [hour]:[minute], the new study day begins.
  DateTime studyDate(DateTime now) {
    final startToday = DateTime(now.year, now.month, now.day, hour, minute);
    if (now.isBefore(startToday)) {
      final previous = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 1));
      return DateTime(previous.year, previous.month, previous.day);
    }
    return DateTime(now.year, now.month, now.day);
  }

  /// Instant when the study day that contains [now] began.
  DateTime startOfStudyDay(DateTime now) {
    final date = studyDate(now);
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  /// Instant when the next study day begins.
  DateTime startOfNextStudyDay(DateTime now) {
    final start = startOfStudyDay(now);
    final nextDate = DateTime(
      start.year,
      start.month,
      start.day,
    ).add(const Duration(days: 1));
    return DateTime(nextDate.year, nextDate.month, nextDate.day, hour, minute);
  }

  bool isSameStudyDay(DateTime a, DateTime b) => studyDate(a) == studyDate(b);

  @override
  bool operator ==(Object other) {
    return other is StartOfDay && hour == other.hour && minute == other.minute;
  }

  @override
  int get hashCode => Object.hash(hour, minute);
}

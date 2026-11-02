/// When the user's study day begins. Default is 4:00 AM.
///
/// All daily study logic (new-kanji limits, review windows, days studied)
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
  ///
  /// [now] is an instant. UTC values and a device that has changed time
  /// zones are read in the current local zone.
  DateTime studyDate(DateTime now) {
    final local = now.toLocal();
    final startToday = localClockTime(
      year: local.year,
      month: local.month,
      day: local.day,
      hour: hour,
      minute: minute,
    );
    if (local.isBefore(startToday)) return addCalendarDays(local, -1);
    return addCalendarDays(local, 0);
  }

  /// Instant when the study day that contains [now] began.
  DateTime startOfStudyDay(DateTime now) {
    final date = studyDate(now);
    return localClockTime(
      year: date.year,
      month: date.month,
      day: date.day,
      hour: hour,
      minute: minute,
    );
  }

  /// Instant when the next study day begins.
  DateTime startOfNextStudyDay(DateTime now) {
    final next = addCalendarDays(studyDate(now), 1);
    return localClockTime(
      year: next.year,
      month: next.month,
      day: next.day,
      hour: hour,
      minute: minute,
    );
  }

  bool isSameStudyDay(DateTime a, DateTime b) => studyDate(a) == studyDate(b);

  @override
  bool operator ==(Object other) {
    return other is StartOfDay && hour == other.hour && minute == other.minute;
  }

  @override
  int get hashCode => Object.hash(hour, minute);
}

/// Local calendar date [days] away from [instant].
///
/// [Duration] of one day is 24 hours. A daylight-saving day is 23 or 25
/// hours, so adding that duration can stay on the same date or skip one.
/// This steps the civil calendar instead, which also crosses a new year and
/// a leap day on the date the calendar shows. The result is local midnight
/// of that date.
DateTime addCalendarDays(DateTime instant, int days) {
  final local = instant.toLocal();
  return DateTime(local.year, local.month, local.day + days);
}

/// Local instant when the clock reads [hour]:[minute] on that civil date.
///
/// A spring-forward gap has no such clock time. The boundary is then the
/// first instant after the clocks jump, which is when that time has already
/// passed. A fall-back hour happens twice; the earlier one is used, so the
/// study day begins the first time the clock shows it.
DateTime localClockTime({
  required int year,
  required int month,
  required int day,
  required int hour,
  required int minute,
}) {
  final exact = DateTime(year, month, day, hour, minute);
  if (exact.year == year &&
      exact.month == month &&
      exact.day == day &&
      exact.hour == hour &&
      exact.minute == minute) {
    return exact;
  }

  final earliest = DateTime(year, month, day);
  final target = hour * 60 + minute;
  if (_clockReached(earliest, year, month, day, target)) return earliest;

  var low = earliest.microsecondsSinceEpoch;
  var high = DateTime(year, month, day + 1).microsecondsSinceEpoch;
  if (high <= low) return earliest;
  while (high - low > 1) {
    final mid = low + ((high - low) ~/ 2);
    final at = DateTime.fromMicrosecondsSinceEpoch(mid);
    if (_clockReached(at, year, month, day, target)) {
      high = mid;
    } else {
      low = mid;
    }
  }
  return DateTime.fromMicrosecondsSinceEpoch(high);
}

bool _clockReached(
  DateTime instant,
  int year,
  int month,
  int day,
  int targetMinutes,
) {
  if (instant.year != year || instant.month != month || instant.day != day) {
    final instantDay = DateTime(instant.year, instant.month, instant.day);
    final targetDay = DateTime(year, month, day);
    return instantDay.isAfter(targetDay);
  }
  return instant.hour * 60 + instant.minute >= targetMinutes;
}

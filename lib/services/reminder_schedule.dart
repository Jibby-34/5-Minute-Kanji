import '../core/models/notification_settings.dart';
import '../core/models/start_of_day.dart';
import 'daily_workload.dart';

/// Stable identity of the one daily reminder. Scheduling always cancels this
/// id first, so reminders can never accumulate.
const String dailyReminderKey = '5-minute-kanji-daily-reminder';

/// Numeric form of [dailyReminderKey] required by the OS notification APIs.
const int dailyReminderId = 1001;

const String reminderTitle = '5-Minute Kanji';

/// Body used when the reminder belongs to a later study day, whose workload
/// cannot be known yet. Deliberately countless rather than wrong.
const String upcomingDayReminderBody = "Time for today's kanji.";

/// The single reminder that should be pending, with the text it will show.
class DailyReminder {
  const DailyReminder({required this.scheduledFor, required this.body});

  final DateTime scheduledFor;
  final String body;

  @override
  bool operator ==(Object other) {
    return other is DailyReminder &&
        scheduledFor == other.scheduledFor &&
        body == other.body;
  }

  @override
  int get hashCode => Object.hash(scheduledFor, body);

  @override
  String toString() => 'DailyReminder($scheduledFor, "$body")';
}

/// Instant inside the study day beginning on [studyDate] when the reminder
/// fires.
///
/// A reminder set earlier than the start of day belongs to the *following*
/// calendar date, because that is when the study day reaches that clock time.
/// With a 4:00 AM start of day, a 2:00 AM reminder for the study day of the
/// 5th fires at 2:00 AM on the 6th.
DateTime reminderInstantForStudyDay({
  required DateTime studyDate,
  required ReminderTime reminderTime,
  required StartOfDay startOfDay,
}) {
  final date = DateTime(studyDate.year, studyDate.month, studyDate.day);
  final startMinutes = startOfDay.hour * 60 + startOfDay.minute;
  final fireDate = reminderTime.minutesFromMidnight < startMinutes
      ? date.add(const Duration(days: 1))
      : date;
  return DateTime(
    fireDate.year,
    fireDate.month,
    fireDate.day,
    reminderTime.hour,
    reminderTime.minute,
  );
}

/// Decides which single reminder should be pending at [now], or `null` when
/// none should be.
///
/// A local notification's text is fixed when it is scheduled and the app
/// cannot recompute it in the background, so only a reminder inside the
/// current study day carries counts. Past that, the reminder is countless and
/// is only held when work is actually expected by then.
DailyReminder? planDailyReminder({
  required DateTime now,
  required NotificationSettings notifications,
  required StartOfDay startOfDay,
  required DailyWorkload workload,
}) {
  if (!notifications.dailyReminderEnabled) return null;

  final today = startOfDay.studyDate(now);
  final instantToday = reminderInstantForStudyDay(
    studyDate: today,
    reminderTime: notifications.reminderTime,
    startOfDay: startOfDay,
  );

  if (workload.remainingCount > 0 && instantToday.isAfter(now)) {
    return DailyReminder(
      scheduledFor: instantToday,
      body: reminderBodyFor(workload),
    );
  }

  // Today's work is either finished or its reminder time has passed. Never
  // fire late; hold the next study day's reminder instead.
  final instantNextDay = reminderInstantForStudyDay(
    studyDate: today.add(const Duration(days: 1)),
    reminderTime: notifications.reminderTime,
    startOfDay: startOfDay,
  );
  final nextReviewAt = workload.nextReviewAt;
  if (nextReviewAt == null || nextReviewAt.isAfter(instantNextDay)) return null;

  return DailyReminder(
    scheduledFor: instantNextDay,
    body: upcomingDayReminderBody,
  );
}

/// Reminder text for [workload], worded like the Home screen.
///
/// The estimate is omitted rather than faked when it is unavailable.
String reminderBodyFor(DailyWorkload workload) {
  final count = workload.remainingCount;
  final noun = workload.countsNewKanji
      ? 'kanji'
      : count == 1
      ? 'review'
      : 'reviews';
  final remaining = 'You have $count $noun left today.';

  final minutes = workload.estimatedMinutes;
  if (minutes <= 0) return remaining;
  return '$remaining About $minutes ${minutes == 1 ? 'minute' : 'minutes'}.';
}

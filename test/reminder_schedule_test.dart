import 'package:fiveminutekanji/core/models/notification_settings.dart';
import 'package:fiveminutekanji/core/models/start_of_day.dart';
import 'package:fiveminutekanji/services/daily_workload.dart';
import 'package:fiveminutekanji/services/reminder_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DailyWorkload workload({
    int newRemaining = 0,
    int due = 0,
    int minutes = 0,
    DateTime? nextReviewAt,
    StartOfDay startOfDay = StartOfDay.defaults,
  }) {
    return DailyWorkload(
      dueCount: due,
      newRemainingToday: newRemaining,
      estimatedMinutes: minutes,
      startOfDay: startOfDay,
      nextReviewAt: nextReviewAt,
    );
  }

  group('reminder instant', () {
    test('a reminder after the start of day stays on its own date', () {
      final instant = reminderInstantForStudyDay(
        studyDate: DateTime(2026, 9, 21),
        reminderTime: ReminderTime.defaults,
        startOfDay: const StartOfDay(hour: 4),
      );

      expect(instant, DateTime(2026, 9, 21, 19));
    });

    test(
      'a reminder before the start of day falls on the next calendar date',
      () {
        // With a 4:00 AM boundary, 2:00 AM is still the 21st's study day.
        final instant = reminderInstantForStudyDay(
          studyDate: DateTime(2026, 9, 21),
          reminderTime: const ReminderTime(hour: 2),
          startOfDay: const StartOfDay(hour: 4),
        );

        expect(instant, DateTime(2026, 9, 22, 2));
      },
    );

    test('a reminder exactly at the start of day opens the study day', () {
      final instant = reminderInstantForStudyDay(
        studyDate: DateTime(2026, 9, 21),
        reminderTime: const ReminderTime(hour: 4),
        startOfDay: const StartOfDay(hour: 4),
      );

      expect(instant, DateTime(2026, 9, 21, 4));
    });
  });

  group('planning', () {
    test('work left before the reminder time schedules today', () {
      final plan = planDailyReminder(
        now: DateTime(2026, 9, 21, 9),
        notifications: NotificationSettings.defaults,
        startOfDay: StartOfDay.defaults,
        workload: workload(
          newRemaining: 7,
          minutes: 4,
          nextReviewAt: DateTime(2026, 9, 21, 9),
        ),
      );

      expect(plan?.scheduledFor, DateTime(2026, 9, 21, 19));
      expect(plan?.body, 'You have 7 kanji left today. About 4 minutes.');
    });

    test('a disabled reminder plans nothing', () {
      final plan = planDailyReminder(
        now: DateTime(2026, 9, 21, 9),
        notifications: const NotificationSettings(dailyReminderEnabled: false),
        startOfDay: StartOfDay.defaults,
        workload: workload(newRemaining: 7, minutes: 4),
      );

      expect(plan, isNull);
    });

    test('a finished day is not reminded again today', () {
      final plan = planDailyReminder(
        now: DateTime(2026, 9, 21, 9),
        notifications: NotificationSettings.defaults,
        startOfDay: StartOfDay.defaults,
        workload: workload(nextReviewAt: DateTime(2026, 9, 22, 4)),
      );

      expect(plan?.scheduledFor, DateTime(2026, 9, 22, 19));
      expect(plan?.body, upcomingDayReminderBody);
    });

    test('a finished day with no work ahead plans nothing', () {
      final plan = planDailyReminder(
        now: DateTime(2026, 9, 21, 9),
        notifications: NotificationSettings.defaults,
        startOfDay: StartOfDay.defaults,
        workload: workload(nextReviewAt: DateTime(2026, 9, 28, 9)),
      );

      expect(plan, isNull);
    });

    test('an empty deck plans nothing', () {
      final plan = planDailyReminder(
        now: DateTime(2026, 9, 21, 9),
        notifications: NotificationSettings.defaults,
        startOfDay: StartOfDay.defaults,
        workload: DailyWorkload.empty,
      );

      expect(plan, isNull);
    });

    test('opening the app after the reminder time does not fire late', () {
      final plan = planDailyReminder(
        now: DateTime(2026, 9, 21, 20, 30),
        notifications: NotificationSettings.defaults,
        startOfDay: StartOfDay.defaults,
        workload: workload(
          newRemaining: 7,
          minutes: 4,
          nextReviewAt: DateTime(2026, 9, 21, 20, 30),
        ),
      );

      expect(plan?.scheduledFor, DateTime(2026, 9, 22, 19));
      expect(plan?.body, upcomingDayReminderBody);
    });

    test('at the reminder minute the reminder moves to the next day', () {
      final plan = planDailyReminder(
        now: DateTime(2026, 9, 21, 19),
        notifications: NotificationSettings.defaults,
        startOfDay: StartOfDay.defaults,
        workload: workload(
          newRemaining: 3,
          minutes: 2,
          nextReviewAt: DateTime(2026, 9, 21, 19),
        ),
      );

      expect(plan?.scheduledFor, DateTime(2026, 9, 22, 19));
    });

    test('before the start of day the reminder belongs to the study day', () {
      // 3:00 AM on the 22nd is still the 21st's study day, so its 7:00 PM
      // reminder has already passed.
      final plan = planDailyReminder(
        now: DateTime(2026, 9, 22, 3),
        notifications: NotificationSettings.defaults,
        startOfDay: const StartOfDay(hour: 4),
        workload: workload(
          newRemaining: 2,
          minutes: 1,
          nextReviewAt: DateTime(2026, 9, 22, 3),
        ),
      );

      expect(plan?.scheduledFor, DateTime(2026, 9, 22, 19));
    });

    test('an early reminder is planned inside the current study day', () {
      final plan = planDailyReminder(
        now: DateTime(2026, 9, 21, 22),
        notifications: const NotificationSettings(
          reminderTime: ReminderTime(hour: 2),
        ),
        startOfDay: const StartOfDay(hour: 4),
        workload: workload(
          newRemaining: 5,
          minutes: 3,
          nextReviewAt: DateTime(2026, 9, 21, 22),
        ),
      );

      expect(plan?.scheduledFor, DateTime(2026, 9, 22, 2));
      expect(plan?.body, 'You have 5 kanji left today. About 3 minutes.');
    });

    test('a later start of day moves the reminder with it', () {
      final notifications = const NotificationSettings(
        reminderTime: ReminderTime(hour: 6),
      );
      final now = DateTime(2026, 9, 21, 22);
      final work = workload(newRemaining: 4, minutes: 2, nextReviewAt: now);

      final withEarlyBoundary = planDailyReminder(
        now: now,
        notifications: notifications,
        startOfDay: const StartOfDay(hour: 4),
        workload: work,
      );
      final withLateBoundary = planDailyReminder(
        now: now,
        notifications: notifications,
        startOfDay: const StartOfDay(hour: 8),
        workload: work,
      );

      // 6:00 AM belongs to a day that starts at 4:00 AM, so today's reminder
      // has already passed and only a countless one is left. With an 8:00 AM
      // boundary the same clock time is still ahead inside today.
      expect(withEarlyBoundary?.scheduledFor, DateTime(2026, 9, 22, 6));
      expect(withEarlyBoundary?.body, upcomingDayReminderBody);
      expect(withLateBoundary?.scheduledFor, DateTime(2026, 9, 22, 6));
      expect(
        withLateBoundary?.body,
        'You have 4 kanji left today. About 2 minutes.',
      );
    });
  });

  group('wording', () {
    test('reviews are named when no new kanji are left', () {
      expect(
        reminderBodyFor(workload(due: 12, minutes: 6)),
        'You have 12 reviews left today. About 6 minutes.',
      );
      expect(
        reminderBodyFor(workload(due: 1, minutes: 1)),
        'You have 1 review left today. About 1 minute.',
      );
    });

    test('a missing estimate is omitted rather than invented', () {
      expect(
        reminderBodyFor(workload(newRemaining: 2)),
        'You have 2 kanji left today.',
      );
    });

    test('a missing estimate still schedules a reminder', () {
      final plan = planDailyReminder(
        now: DateTime(2026, 9, 21, 9),
        notifications: NotificationSettings.defaults,
        startOfDay: StartOfDay.defaults,
        workload: workload(
          newRemaining: 2,
          nextReviewAt: DateTime(2026, 9, 21, 9),
        ),
      );

      expect(plan?.scheduledFor, DateTime(2026, 9, 21, 19));
      expect(plan?.body, 'You have 2 kanji left today.');
    });
  });
}

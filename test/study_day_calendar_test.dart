import 'package:flutter_test/flutter_test.dart';
import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/notification_settings.dart';
import 'package:fiveminutekanji/core/models/progress.dart';
import 'package:fiveminutekanji/core/models/start_of_day.dart';
import 'package:fiveminutekanji/core/utils/time_format.dart';
import 'package:fiveminutekanji/services/daily_workload.dart';
import 'package:fiveminutekanji/services/due_card_selector.dart';
import 'package:fiveminutekanji/services/reminder_schedule.dart';

import 'support/fakes.dart';

void main() {
  const start = StartOfDay(hour: 4);
  const selector = DueCardSelector();

  CardSchedule reviewDue(DateTime dueAt) {
    return CardSchedule(
      cardId: 'review',
      state: CardLearningState.review,
      reviewCount: 2,
      correctCount: 2,
      incorrectCount: 0,
      dueAt: dueAt,
      interval: const Duration(days: 4),
      ease: 2.5,
      lastReviewedAt: dueAt.subtract(const Duration(days: 4)),
      consecutiveGoodCount: 2,
    );
  }

  test('calendar steps cross a new year and a leap day', () {
    expect(
      addCalendarDays(DateTime(2026, 12, 31, 23), 1),
      DateTime(2027, 1, 1),
    );
    expect(
      addCalendarDays(DateTime(2027, 1, 1, 2), -1),
      DateTime(2026, 12, 31),
    );
    expect(addCalendarDays(DateTime(2024, 2, 28), 1), DateTime(2024, 2, 29));
    expect(addCalendarDays(DateTime(2024, 2, 29), 1), DateTime(2024, 3, 1));
    expect(addCalendarDays(DateTime(2025, 2, 28), 1), DateTime(2025, 3, 1));

    expect(start.studyDate(DateTime(2027, 1, 1, 2)), DateTime(2026, 12, 31));
    expect(
      start.startOfNextStudyDay(DateTime(2026, 12, 31, 12)),
      DateTime(2027, 1, 1, 4),
    );
    expect(start.studyDate(DateTime(2024, 3, 1, 2)), DateTime(2024, 2, 29));
    expect(start.studyDate(DateTime(2025, 3, 1, 2)), DateTime(2025, 2, 28));
    expect(
      start.startOfNextStudyDay(DateTime(2024, 2, 29, 12)),
      DateTime(2024, 3, 1, 4),
    );
  });

  test('a UTC instant is read on the local civil date', () {
    final local = DateTime(2026, 6, 15, 22);
    expect(start.studyDate(local.toUtc()), start.studyDate(local));
    expect(start.isSameStudyDay(local.toUtc(), local), isTrue);
    expect(calendarDay(local.toUtc()), calendarDay(local));
    expect(calendarDayKey(local.toUtc()), calendarDayKey(local));
  });

  test('a due instant keeps its offset when it is stored', () {
    const raw = '2026-11-02T01:00:00.000+09:00';
    final due = DateTime.parse(raw);
    final restored = CardSchedule.fromJson({
      'cardId': 'review',
      'state': 'review',
      'dueAt': raw,
    });

    expect(due.toUtc(), DateTime.utc(2026, 11, 1, 16));
    expect(restored, isNotNull);
    expect(restored!.dueAt.toUtc(), due.toUtc());

    final now = DateTime(2026, 11, 1, 15);
    expect(
      selector.isAvailableToday(restored, now, startOfDay: start),
      due.isBefore(start.startOfNextStudyDay(now)),
    );
  });

  test('study days follow the civil date when a local day is not 24 hours', () {
    for (var month = 1; month <= 12; month++) {
      for (var day = 1; day <= 28; day++) {
        final midnight = DateTime(2026, month, day);
        final nextDate = DateTime(2026, month, day + 1);
        final previousDate = DateTime(2026, month, day - 1);
        expect(addCalendarDays(midnight, 1), nextDate);
        expect(addCalendarDays(midnight, -1), previousDate);

        final driftedForward = midnight.add(const Duration(days: 1));
        if (driftedForward.year != nextDate.year ||
            driftedForward.month != nextDate.month ||
            driftedForward.day != nextDate.day) {
          final afternoon = DateTime(2026, month, day, 15);
          final boundary = start.startOfNextStudyDay(afternoon);
          expect(boundary.year, nextDate.year);
          expect(boundary.month, nextDate.month);
          expect(boundary.day, nextDate.day);
          expect(boundary.hour, 4);
          final dueAt = DateTime(2026, month, day, 10);
          expect(
            selector.isAvailableToday(
              reviewDue(dueAt),
              afternoon,
              startOfDay: start,
            ),
            isTrue,
            reason: 'review at $dueAt on a 25-hour local day',
          );
        }

        final driftedBack = nextDate.subtract(const Duration(days: 1));
        if (driftedBack.year != midnight.year ||
            driftedBack.month != midnight.month ||
            driftedBack.day != midnight.day) {
          final early = DateTime(
            nextDate.year,
            nextDate.month,
            nextDate.day,
            1,
          );
          expect(start.studyDate(early), midnight);
          expect(
            start.startOfNextStudyDay(early),
            DateTime(nextDate.year, nextDate.month, nextDate.day, 4),
          );
        }
      }
    }
  });

  test('a skipped clock time starts at the first instant after the jump', () {
    final normalized = DateTime(2026, 3, 8, 2, 30);
    if (normalized.hour == 2 && normalized.minute == 30) return;

    expect(
      localClockTime(year: 2026, month: 3, day: 8, hour: 2, minute: 30),
      DateTime(2026, 3, 8, 3),
    );
    const duringGap = StartOfDay(hour: 2, minute: 30);
    expect(
      duringGap.startOfStudyDay(DateTime(2026, 3, 8, 12)),
      DateTime(2026, 3, 8, 3),
    );
    expect(duringGap.studyDate(DateTime(2026, 3, 8, 1)), DateTime(2026, 3, 7));
    expect(
      duringGap.studyDate(DateTime(2026, 3, 8, 3, 15)),
      DateTime(2026, 3, 8),
    );
  });

  test('a repeated clock time starts the first time the clock shows it', () {
    final first = DateTime(2026, 11, 1, 1, 30);
    final second = first.add(const Duration(hours: 1));
    final repeats =
        first.hour == 1 &&
        second.hour == 1 &&
        first.timeZoneOffset != second.timeZoneOffset;
    if (!repeats) return;

    expect(
      localClockTime(year: 2026, month: 11, day: 1, hour: 1, minute: 30),
      first,
    );
    const overlap = StartOfDay(hour: 1, minute: 30);
    expect(overlap.startOfStudyDay(DateTime(2026, 11, 1, 12)), first);
    expect(overlap.studyDate(second), DateTime(2026, 11, 1));
  });

  test(
    'the fall-back study plan still contains reviews due that day',
    () async {
      final now = DateTime(2026, 11, 1, 15);
      final dueAt = DateTime(2026, 11, 1, 10);
      final cards = [testCard('new'), testCard('review')];
      final progress = MemoryProgressRepository(
        schedules: {'review': reviewDue(dueAt)},
        settings: const AppSettings(newKanjiPerDay: 1),
      );
      final workload = await DailyWorkloadService(
        kanjiRepository: FakeKanjiRepository(cards),
        progressRepository: progress,
      ).read(now: now);

      expect(workload.dueCount, 1);
      expect(workload.sessionCards.map((card) => card.id), contains('review'));
      expect(workload.allocation.reviewCards, 1);
      expect(workload.allocation.newCards, 1);

      final nextDay = await DailyWorkloadService(
        kanjiRepository: FakeKanjiRepository(cards),
        progressRepository: progress,
      ).read(now: DateTime(2026, 11, 2, 15));
      expect(nextDay.dueCount, 1);
      expect(nextDay.sessionCards.map((card) => card.id), contains('review'));
    },
  );

  test('tomorrow still means the next civil study day after a long day', () {
    expect(
      formatNextReview(
        DateTime(2026, 11, 2, 10),
        DateTime(2026, 11, 1, 20),
        startOfDay: start,
      ),
      'tomorrow',
    );

    final plan = planDailyReminder(
      now: DateTime(2026, 11, 1, 20),
      notifications: NotificationSettings.defaults,
      startOfDay: start,
      workload: DailyWorkload(
        dueCount: 0,
        newRemainingToday: 0,
        estimatedMinutes: 0,
        startOfDay: start,
        nextReviewAt: DateTime(2026, 11, 2, 9),
      ),
    );
    expect(plan?.scheduledFor, DateTime(2026, 11, 2, 19));
  });
}

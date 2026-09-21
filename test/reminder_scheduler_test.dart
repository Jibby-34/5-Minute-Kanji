import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/kanji_card.dart';
import 'package:fiveminutekanji/core/models/notification_settings.dart';
import 'package:fiveminutekanji/core/models/progress.dart';
import 'package:fiveminutekanji/core/models/review.dart';
import 'package:fiveminutekanji/core/models/start_of_day.dart';
import 'package:fiveminutekanji/core/models/study_phase.dart';
import 'package:fiveminutekanji/features/home/home_controller.dart';
import 'package:fiveminutekanji/features/review/review_controller.dart';
import 'package:fiveminutekanji/features/settings/settings_controller.dart';
import 'package:fiveminutekanji/services/daily_workload.dart';
import 'package:fiveminutekanji/services/notification_gateway.dart';
import 'package:fiveminutekanji/services/reminder_schedule.dart';
import 'package:fiveminutekanji/services/reminder_scheduler.dart';
import 'package:fiveminutekanji/services/srs_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_notifications.dart';
import 'support/fakes.dart';

void main() {
  var now = DateTime(2026, 9, 21, 9);
  final cards = [testCard('a', keyword: 'one'), testCard('b', keyword: 'two')];

  ReminderScheduler scheduler(
    MemoryProgressRepository progress,
    FakeNotificationGateway gateway, {
    List<KanjiCard>? deck,
  }) {
    return ReminderScheduler(
      gateway: gateway,
      progressRepository: progress,
      workloadService: DailyWorkloadService(
        kanjiRepository: FakeKanjiRepository(deck ?? cards),
        progressRepository: progress,
      ),
      clock: () => now,
    );
  }

  setUp(() {
    now = DateTime(2026, 9, 21, 9);
  });

  test('reminders default to on at 7:00 PM', () async {
    const settings = AppSettings();

    expect(settings.notifications.dailyReminderEnabled, isTrue);
    expect(settings.notifications.reminderTime, const ReminderTime(hour: 19));
  });

  test('an enabled reminder is scheduled with today\'s workload', () async {
    final progress = MemoryProgressRepository();
    await progress.seedIfNeeded(const ['a', 'b'], now: now);
    final gateway = FakeNotificationGateway();

    await scheduler(progress, gateway).reschedule();

    expect(gateway.scheduled, hasLength(1));
    expect(gateway.pending?.when, DateTime(2026, 9, 21, 19));
    expect(gateway.pending?.title, '5-Minute Kanji');
    expect(
      gateway.pending?.body,
      'You have 2 kanji left today. About 1 minute.',
    );
  });

  test('rescheduling never leaves more than one reminder', () async {
    final progress = MemoryProgressRepository();
    await progress.seedIfNeeded(const ['a', 'b'], now: now);
    final gateway = FakeNotificationGateway();
    final reminders = scheduler(progress, gateway);

    await reminders.reschedule();
    await reminders.reschedule();
    await Future.wait([reminders.reschedule(), reminders.reschedule()]);

    expect(gateway.scheduled, hasLength(1));
    expect(gateway.cancelCount, 4);
  });

  test('disabling reminders cancels the pending notification', () async {
    final progress = MemoryProgressRepository();
    await progress.seedIfNeeded(const ['a', 'b'], now: now);
    final gateway = FakeNotificationGateway();
    final reminders = scheduler(progress, gateway);
    await reminders.reschedule();
    expect(gateway.hasPending, isTrue);

    await progress.saveSettings(
      const AppSettings(
        notifications: NotificationSettings(dailyReminderEnabled: false),
      ),
    );
    await reminders.reschedule();

    expect(gateway.hasPending, isFalse);
    expect(gateway.scheduled, isEmpty);
  });

  test('changing the reminder time replaces the notification', () async {
    final progress = MemoryProgressRepository();
    await progress.seedIfNeeded(const ['a', 'b'], now: now);
    final gateway = FakeNotificationGateway();
    final reminders = scheduler(progress, gateway);
    await reminders.reschedule();

    await progress.saveSettings(
      const AppSettings(
        notifications: NotificationSettings(
          reminderTime: ReminderTime(hour: 21, minute: 30),
        ),
      ),
    );
    await reminders.reschedule();

    expect(gateway.scheduled, hasLength(1));
    expect(gateway.pending?.when, DateTime(2026, 9, 21, 21, 30));
  });

  test('a finished day holds no reminder for today', () async {
    final tomorrow = DateTime(2026, 9, 22, 9);
    final progress = MemoryProgressRepository(
      settings: const AppSettings(newKanjiPerDay: 0),
      schedules: {
        for (final card in cards)
          card.id: CardSchedule(
            cardId: card.id,
            state: CardLearningState.review,
            reviewCount: 1,
            correctCount: 1,
            incorrectCount: 0,
            dueAt: tomorrow,
            interval: const Duration(days: 1),
            ease: 2.5,
            lastReviewedAt: now,
          ),
      },
    );
    final gateway = FakeNotificationGateway();

    await scheduler(progress, gateway).reschedule();

    expect(gateway.pending?.when, DateTime(2026, 9, 22, 19));
    expect(gateway.pending?.body, upcomingDayReminderBody);
  });

  test('a day with nothing left and nothing ahead schedules nothing', () async {
    final progress = MemoryProgressRepository(
      settings: const AppSettings(newKanjiPerDay: 0),
      schedules: {
        for (final card in cards)
          card.id: CardSchedule(
            cardId: card.id,
            state: CardLearningState.review,
            reviewCount: 1,
            correctCount: 1,
            incorrectCount: 0,
            dueAt: DateTime(2026, 9, 28, 9),
            interval: const Duration(days: 7),
            ease: 2.5,
            lastReviewedAt: now,
          ),
      },
    );
    final gateway = FakeNotificationGateway();

    await scheduler(progress, gateway).reschedule();

    expect(gateway.scheduled, isEmpty);
    expect(gateway.cancelCount, 1);
  });

  test('finishing the day\'s work drops the pending reminder', () async {
    final progress = MemoryProgressRepository(
      settings: const AppSettings(newKanjiPerDay: 1),
    );
    await progress.seedIfNeeded(const ['a'], now: now);
    final gateway = FakeNotificationGateway();
    final reminders = scheduler(progress, gateway, deck: [cards.first]);
    final home = HomeController(
      kanjiRepository: FakeKanjiRepository([cards.first]),
      progressRepository: progress,
      reminderScheduler: reminders,
      clock: () => now,
    );

    await home.load();
    expect(gateway.pending?.when, DateTime(2026, 9, 21, 19));

    final review = ReviewController(
      progressRepository: progress,
      srsEngine: const SrsEngine(),
      cards: [cards.first],
      config: const ReviewSessionConfig(
        duration: Duration(minutes: 5),
        maxCards: 1,
      ),
      startTime: now,
      clock: () => now,
      schedules: Map<String, CardSchedule>.from(progress.schedules),
    );
    expect(review.phase, StudyPhase.learn);
    review.beginPractice();
    await review.completePractice();
    review.submit();
    await review.rate(ReviewResult.good);

    // Home reloads when a sitting ends, which re-plans the reminder.
    await home.load(showLoading: false);

    expect(home.isCaughtUp, isTrue);
    expect(gateway.pending?.body, upcomingDayReminderBody);
    expect(
      gateway.pending?.when.isAfter(DateTime(2026, 9, 21, 19)),
      isTrue,
      reason: 'a completed day must not be reminded again today',
    );
  });

  test(
    'a denied permission schedules nothing but keeps the app usable',
    () async {
      final progress = MemoryProgressRepository();
      await progress.seedIfNeeded(const ['a', 'b'], now: now);
      final gateway = FakeNotificationGateway(
        permissionStatus: NotificationPermission.denied,
      );

      await scheduler(progress, gateway).reschedule();

      expect(gateway.scheduled, isEmpty);
      expect(
        (await progress.getSettings()).notifications.dailyReminderEnabled,
        isTrue,
      );
    },
  );

  test('a failing notification plugin does not throw', () async {
    final progress = MemoryProgressRepository();
    await progress.seedIfNeeded(const ['a', 'b'], now: now);
    final gateway = FakeNotificationGateway(failOnSchedule: true);

    await expectLater(scheduler(progress, gateway).reschedule(), completes);
    expect(gateway.scheduled, isEmpty);
  });

  group('settings', () {
    test(
      'turning reminders on asks for permission once and schedules',
      () async {
        final progress = MemoryProgressRepository(
          settings: const AppSettings(
            notifications: NotificationSettings(dailyReminderEnabled: false),
          ),
        );
        await progress.seedIfNeeded(const ['a', 'b'], now: now);
        final gateway = FakeNotificationGateway(
          permissionStatus: NotificationPermission.notDetermined,
          permissionOnRequest: NotificationPermission.granted,
        );
        final controller = SettingsController(
          progressRepository: progress,
          reminderScheduler: scheduler(progress, gateway),
        );
        await controller.load();

        await controller.setDailyReminderEnabled(true);

        expect(gateway.requestCount, 1);
        expect(controller.dailyReminderEnabled, isTrue);
        expect(controller.remindersBlockedBySystem, isFalse);
        expect(gateway.scheduled, hasLength(1));
        expect(gateway.pending?.when, DateTime(2026, 9, 21, 19));
        expect(
          (await progress.getSettings()).notifications.dailyReminderEnabled,
          isTrue,
        );
      },
    );

    test('turning reminders off cancels and persists', () async {
      final progress = MemoryProgressRepository();
      await progress.seedIfNeeded(const ['a', 'b'], now: now);
      final gateway = FakeNotificationGateway();
      final reminders = scheduler(progress, gateway);
      final controller = SettingsController(
        progressRepository: progress,
        reminderScheduler: reminders,
      );
      await controller.load();
      await reminders.reschedule();
      expect(gateway.hasPending, isTrue);

      await controller.setDailyReminderEnabled(false);

      expect(gateway.hasPending, isFalse);
      expect(gateway.requestCount, 0);
      expect(
        (await progress.getSettings()).notifications.dailyReminderEnabled,
        isFalse,
      );
    });

    test(
      'a denied prompt keeps reminders on and offers system settings',
      () async {
        final progress = MemoryProgressRepository(
          settings: const AppSettings(
            notifications: NotificationSettings(dailyReminderEnabled: false),
          ),
        );
        await progress.seedIfNeeded(const ['a', 'b'], now: now);
        final gateway = FakeNotificationGateway(
          permissionStatus: NotificationPermission.notDetermined,
          permissionOnRequest: NotificationPermission.denied,
        );
        final controller = SettingsController(
          progressRepository: progress,
          reminderScheduler: scheduler(progress, gateway),
        );
        await controller.load();

        await controller.setDailyReminderEnabled(true);

        expect(controller.dailyReminderEnabled, isTrue);
        expect(controller.remindersBlockedBySystem, isTrue);
        expect(controller.canRequestPermission, isFalse);
        expect(gateway.scheduled, isEmpty);

        await controller.openSystemNotificationSettings();
        expect(gateway.openSettingsCount, 1);

        // The user is never prompted again on their own.
        await controller.setReminderTime(const ReminderTime(hour: 20));
        expect(gateway.requestCount, 1);
      },
    );

    test('changing the reminder time persists and reschedules', () async {
      final progress = MemoryProgressRepository();
      await progress.seedIfNeeded(const ['a', 'b'], now: now);
      final gateway = FakeNotificationGateway();
      final controller = SettingsController(
        progressRepository: progress,
        reminderScheduler: scheduler(progress, gateway),
      );
      await controller.load();

      await controller.setReminderTime(const ReminderTime(hour: 6, minute: 45));

      expect(controller.reminderTime, const ReminderTime(hour: 6, minute: 45));
      expect(
        (await progress.getSettings()).notifications.reminderTime,
        const ReminderTime(hour: 6, minute: 45),
      );
      expect(gateway.scheduled, hasLength(1));
      // 6:45 AM has passed inside today's study day, so the next one is used.
      expect(gateway.pending?.when, DateTime(2026, 9, 22, 6, 45));
    });

    test('changing the start of day re-plans the reminder', () async {
      final progress = MemoryProgressRepository(
        settings: const AppSettings(
          notifications: NotificationSettings(
            reminderTime: ReminderTime(hour: 6),
          ),
        ),
      );
      await progress.seedIfNeeded(const ['a', 'b'], now: now);
      final gateway = FakeNotificationGateway();
      final reminders = scheduler(progress, gateway);
      final controller = SettingsController(
        progressRepository: progress,
        reminderScheduler: reminders,
      );
      await controller.load();
      await reminders.reschedule();
      expect(gateway.pending?.when, DateTime(2026, 9, 22, 6));
      expect(gateway.pending?.body, upcomingDayReminderBody);

      // A 7:00 AM boundary puts 6:00 AM at the end of the study day, which is
      // still ahead of 9:00 AM on the 21st.
      await controller.setStartOfDay(const StartOfDay(hour: 7));

      expect(gateway.scheduled, hasLength(1));
      expect(gateway.pending?.when, DateTime(2026, 9, 22, 6));
      expect(
        gateway.pending?.body,
        'You have 2 kanji left today. About 1 minute.',
      );
    });
  });
}

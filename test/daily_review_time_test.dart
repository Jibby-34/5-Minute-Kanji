import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/progress.dart';
import 'package:fiveminutekanji/core/models/review.dart';
import 'package:fiveminutekanji/core/models/start_of_day.dart';
import 'package:fiveminutekanji/core/theme/app_theme.dart';
import 'package:fiveminutekanji/data/shared_prefs_progress_repository.dart';
import 'package:fiveminutekanji/features/review/review_controller.dart';
import 'package:fiveminutekanji/features/review/review_screen.dart';
import 'package:fiveminutekanji/repositories/progress_repository.dart';
import 'package:fiveminutekanji/services/daily_review_clock.dart';
import 'package:fiveminutekanji/services/srs_engine.dart';
import 'package:fiveminutekanji/services/srs_scheduler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  final morning = DateTime(2026, 9, 2, 8);
  const startOfDay = StartOfDay();

  DailyReviewClock clockAt(DateTime start) {
    return DailyReviewClock(startedAt: start, startOfDay: startOfDay);
  }

  group('DailyReviewClock', () {
    test('counts only the time the clock is running', () {
      final clock = clockAt(morning);
      final paused = morning.add(const Duration(minutes: 2));
      clock.pause(paused);

      final resumed = paused.add(const Duration(minutes: 40));
      clock.resume(resumed);
      final done = resumed.add(const Duration(seconds: 30));

      expect(clock.totalAt(done), const Duration(minutes: 2, seconds: 30));
    });

    test('adds earlier sittings from the same study day', () {
      final clock = clockAt(morning)
        ..accrued = const Duration(minutes: 3)
        ..accruedDay = DateTime(2026, 9, 2);
      final later = morning.add(const Duration(minutes: 1, seconds: 5));

      expect(clock.totalAt(later), const Duration(minutes: 4, seconds: 5));
    });

    test('a new study day drops yesterday and keeps time after 4:00 AM', () {
      final late = DateTime(2026, 9, 2, 3, 50);
      final clock = clockAt(late)
        ..accrued = const Duration(minutes: 5)
        ..accruedDay = DateTime(2026, 9, 1);

      final afterBoundary = DateTime(2026, 9, 2, 4, 10);
      expect(clock.totalAt(afterBoundary), const Duration(minutes: 10));
    });

    test('a pause across the study-day boundary does not carry yesterday', () {
      final late = DateTime(2026, 9, 2, 3, 40);
      final clock = clockAt(late)..accruedDay = DateTime(2026, 9, 1);
      clock.pause(DateTime(2026, 9, 2, 3, 55));
      clock.resume(DateTime(2026, 9, 2, 4, 10));

      expect(
        clock.totalAt(DateTime(2026, 9, 2, 4, 12)),
        const Duration(minutes: 2),
      );
    });

    test('uses the configured start of day', () {
      final clock = DailyReviewClock(
        startedAt: DateTime(2026, 9, 2, 5, 50),
        startOfDay: const StartOfDay(hour: 6),
      );
      expect(
        clock.totalAt(DateTime(2026, 9, 2, 6, 5)),
        const Duration(minutes: 5),
      );
    });
  });

  group('DailyReviewTime storage', () {
    test(
      'survives a new repository and resets on the next study day',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final first = SharedPrefsProgressRepository(prefs);
        await first.saveDailyReviewTime(
          DailyReviewTime(
            date: DateTime(2026, 9, 2),
            duration: const Duration(minutes: 3, seconds: 4),
          ),
        );

        final restarted = SharedPrefsProgressRepository(prefs);
        final loaded = await restarted.getDailyReviewTime();
        expect(loaded.duration, const Duration(minutes: 3, seconds: 4));
        expect(
          loaded.forDay(morning).duration,
          const Duration(minutes: 3, seconds: 4),
        );
        expect(
          loaded.forDay(morning.add(const Duration(days: 1))).duration,
          Duration.zero,
        );
      },
    );

    test('missing or negative stored time reads as zero', () {
      expect(DailyReviewTime.fromJson(null).duration, Duration.zero);
      expect(
        DailyReviewTime.fromJson({'durationMs': -20}).duration,
        Duration.zero,
      );
    });
  });

  group('ReviewController daily review time', () {
    CardSchedule due(String id) {
      return CardSchedule(
        cardId: id,
        state: CardLearningState.review,
        reviewCount: 1,
        correctCount: 1,
        incorrectCount: 0,
        dueAt: morning,
        interval: SrsEngine.graduatingInterval,
        ease: 2.5,
        lastReviewedAt: morning,
        consecutiveGoodCount: 1,
      );
    }

    ReviewController open({
      required MemoryProgressRepository progress,
      required DateTime Function() clock,
      required DateTime start,
      List<String> ids = const ['a'],
    }) {
      return ReviewController(
        progressRepository: progress,
        srsEngine: const SrsEngine(),
        cards: ids.map(testCard).toList(),
        config: const ReviewSessionConfig(
          duration: Duration(minutes: 5),
          maxCards: 3,
        ),
        startTime: start,
        clock: clock,
        schedules: {for (final id in ids) id: due(id)},
      );
    }

    test('sittings on the same study day add up across restarts', () async {
      final progress = MemoryProgressRepository();
      await progress.saveDailyReviewTime(
        DailyReviewTime(
          date: DateTime(2026, 9, 2),
          duration: const Duration(minutes: 2),
        ),
      );
      var current = morning;
      final first = open(
        progress: progress,
        clock: () => current,
        start: current,
      );
      current = morning.add(const Duration(seconds: 15));
      first.pauseReviewTime();
      await first.checkpointReviewTime();
      await first.hydrate();

      expect(
        (await progress.getDailyReviewTime()).duration,
        const Duration(minutes: 2, seconds: 15),
      );

      current = morning.add(const Duration(minutes: 30));
      final second = open(
        progress: progress,
        clock: () => current,
        start: current,
      );
      await second.hydrate();
      current = current.add(const Duration(seconds: 20));
      second.submit();
      final summary = await second.rate(ReviewResult.good);

      expect(summary?.duration, const Duration(minutes: 2, seconds: 35));
      expect(
        (await progress.getDailyReviewTime()).duration,
        const Duration(minutes: 2, seconds: 35),
      );
    });

    test('time in the background is left out of the daily total', () async {
      final progress = MemoryProgressRepository();
      var current = morning;
      final controller = open(
        progress: progress,
        clock: () => current,
        start: current,
      );
      await controller.hydrate();
      current = morning.add(const Duration(minutes: 1));
      controller.pauseReviewTime();
      await controller.checkpointReviewTime();

      current = morning.add(const Duration(minutes: 50));
      controller.resumeReviewTime();
      await controller.checkpointReviewTime();
      expect(
        (await progress.getDailyReviewTime()).duration,
        const Duration(minutes: 1),
      );

      current = current.add(const Duration(seconds: 10));
      controller.submit();
      final summary = await controller.rate(ReviewResult.good);
      expect(summary?.duration, const Duration(minutes: 1, seconds: 10));
    });

    test('the next study day starts from zero', () async {
      final progress = MemoryProgressRepository();
      await progress.saveDailyReviewTime(
        DailyReviewTime(
          date: DateTime(2026, 9, 2),
          duration: const Duration(minutes: 4),
        ),
      );
      final nextDay = DateTime(2026, 9, 3, 8);
      var current = nextDay;
      final controller = open(
        progress: progress,
        clock: () => current,
        start: current,
      );
      await controller.hydrate();
      current = nextDay.add(const Duration(seconds: 12));
      controller.submit();
      final summary = await controller.rate(ReviewResult.good);

      expect(summary?.duration, const Duration(seconds: 12));
      expect(
        (await progress.getDailyReviewTime()).forDay(nextDay).duration,
        const Duration(seconds: 12),
      );
    });
  });

  testWidgets('pausing the app saves today and ignores the time away', (
    tester,
  ) async {
    var current = morning;
    final progress = MemoryProgressRepository();
    await progress.saveSchedule(
      CardSchedule(
        cardId: 'a',
        state: CardLearningState.review,
        reviewCount: 1,
        correctCount: 1,
        incorrectCount: 0,
        dueAt: morning,
        interval: SrsEngine.graduatingInterval,
        ease: 2.5,
        lastReviewedAt: morning,
        consecutiveGoodCount: 1,
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ProgressRepository>.value(value: progress),
          Provider<SrsScheduler>.value(value: const SrsEngine()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: ReviewScreen(
            cards: [testCard('a')],
            config: const ReviewSessionConfig(duration: Duration(minutes: 5)),
            clock: () => current,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    current = morning.add(const Duration(minutes: 1, seconds: 5));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(
      (await progress.getDailyReviewTime()).duration,
      const Duration(minutes: 1, seconds: 5),
    );

    current = morning.add(const Duration(minutes: 20));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    current = current.add(const Duration(seconds: 8));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(
      (await progress.getDailyReviewTime()).duration,
      const Duration(minutes: 1, seconds: 13),
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/progress.dart';
import 'package:fiveminutekanji/core/models/review.dart';
import 'package:fiveminutekanji/core/models/start_of_day.dart';
import 'package:fiveminutekanji/data/shared_prefs_progress_repository.dart';
import 'package:fiveminutekanji/features/home/home_controller.dart';
import 'package:fiveminutekanji/features/review/review_controller.dart';
import 'package:fiveminutekanji/features/settings/settings_controller.dart';
import 'package:fiveminutekanji/services/srs_engine.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 2, 8);

  CardSchedule dueReview(String id) {
    return CardSchedule(
      cardId: id,
      state: CardLearningState.review,
      reviewCount: 1,
      correctCount: 1,
      incorrectCount: 0,
      dueAt: now,
      interval: SrsEngine.graduatingInterval,
      ease: 2.5,
      lastReviewedAt: now,
      consecutiveGoodCount: 1,
    );
  }

  test('calendar day rollover zeroes the new-kanji count', () {
    final stored = DailyNewKanjiProgress(date: now, count: 4);
    expect(stored.forDay(now).count, 4);
    expect(stored.forDay(now.add(const Duration(days: 1))).count, 0);
    expect(
      stored.forDay(now.add(const Duration(days: 1))).remainingAllowance(5),
      5,
    );
  });

  test('count does not reset until the configured start of day', () {
    const start = StartOfDay(hour: 4);
    final stored = DailyNewKanjiProgress(date: DateTime(2026, 9, 8), count: 4);
    expect(
      stored.forDay(DateTime(2026, 9, 9, 3, 59), startOfDay: start).count,
      4,
    );
    expect(stored.forDay(DateTime(2026, 9, 9, 4), startOfDay: start).count, 0);
  });

  test('changing the daily limit does not reset today\'s count', () {
    final today = DailyNewKanjiProgress(date: now, count: 4);
    expect(today.remainingAllowance(10), 6);
    expect(today.remainingAllowance(3), 0);
    expect(today.count, 4);
  });

  test('finishing learn increments the daily counter once', () async {
    final progress = MemoryProgressRepository();
    await progress.seedIfNeeded(const ['a', 'b'], now: now);
    final controller = ReviewController(
      progressRepository: progress,
      srsEngine: const SrsEngine(),
      cards: [testCard('a'), testCard('b')],
      config: const ReviewSessionConfig(
        duration: Duration(minutes: 5),
        maxCards: 2,
      ),
      startTime: now,
      clock: () => now,
      schedules: Map<String, CardSchedule>.from(progress.schedules),
    );

    controller.beginPractice();
    await controller.completePractice();

    expect(progress.dailyNewKanji.count, 1);
    expect(progress.dailyNewKanji.date, DateTime(2026, 9, 2));
    expect(
      (await progress.getSchedule('a'))!.state,
      CardLearningState.learning,
    );
  });

  test(
    're-reviewing an encountered card does not increment the counter',
    () async {
      final progress = MemoryProgressRepository(
        schedules: {'a': dueReview('a')},
      );
      final controller = ReviewController(
        progressRepository: progress,
        srsEngine: const SrsEngine(),
        cards: [testCard('a')],
        config: const ReviewSessionConfig(
          duration: Duration(minutes: 5),
          maxCards: 1,
        ),
        startTime: now,
        clock: () => now,
        schedules: Map<String, CardSchedule>.from(progress.schedules),
      );

      controller.submit();
      await controller.rate(ReviewResult.good);

      expect(progress.dailyNewKanji.count, 0);
    },
  );

  test('practice learn does not increment the daily counter', () async {
    final progress = MemoryProgressRepository();
    await progress.seedIfNeeded(const ['a'], now: now);
    final controller = ReviewController(
      progressRepository: progress,
      srsEngine: const SrsEngine(),
      cards: [testCard('a')],
      config: const ReviewSessionConfig(
        duration: Duration(minutes: 5),
        maxCards: 1,
      ),
      isPractice: true,
      startTime: now,
      clock: () => now,
      schedules: Map<String, CardSchedule>.from(progress.schedules),
    );

    controller.beginPractice();
    await controller.completePractice();
    expect(progress.dailyNewKanji.count, 0);
    expect((await progress.getSchedule('a'))!.state, CardLearningState.newCard);
  });

  test('sessions stop introducing new kanji after the daily limit', () async {
    final cards = List.generate(8, (i) => testCard('n$i'));
    final progress = MemoryProgressRepository(
      settings: const AppSettings(newKanjiPerDay: 2),
      dailyNewKanji: DailyNewKanjiProgress(date: now, count: 2),
    );
    await progress.seedIfNeeded(
      cards.map((card) => card.id).toList(),
      now: now,
    );
    final home = HomeController(
      kanjiRepository: FakeKanjiRepository(cards),
      progressRepository: progress,
      config: const ReviewSessionConfig(
        duration: Duration(minutes: 5),
        maxCards: 25,
      ),
      clock: () => now,
    );

    await home.load();
    expect(home.newRemainingToday, 0);
    expect(await home.cardsForSession(practice: false), isEmpty);
  });

  test('a zero daily limit introduces no new kanji', () async {
    final progress = MemoryProgressRepository(
      settings: const AppSettings(newKanjiPerDay: 0),
      schedules: {
        'a': CardSchedule.fresh('a', now),
        'b': CardSchedule.fresh('b', now),
        'r': dueReview('r'),
      },
    );
    final home = HomeController(
      kanjiRepository: FakeKanjiRepository([
        testCard('a'),
        testCard('b'),
        testCard('r'),
      ]),
      progressRepository: progress,
      config: const ReviewSessionConfig(
        duration: Duration(minutes: 5),
        maxCards: 25,
      ),
      clock: () => now,
    );

    await home.load();
    final session = await home.cardsForSession(practice: false);
    expect(home.newRemainingToday, 0);
    expect(session.map((card) => card.id), ['r']);
  });

  test('settings and daily count survive a new repository instance', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final first = SharedPrefsProgressRepository(prefs);
    await first.saveSettings(
      const AppSettings(
        newKanjiPerDay: 12,
        startOfDay: StartOfDay(hour: 5, minute: 45),
      ),
    );
    await first.saveDailyNewKanji(
      DailyNewKanjiProgress(date: DateTime(2026, 9, 2), count: 4),
    );

    final restarted = SharedPrefsProgressRepository(prefs);
    expect((await restarted.getSettings()).newKanjiPerDay, 12);
    expect(
      (await restarted.getSettings()).startOfDay,
      const StartOfDay(hour: 5, minute: 45),
    );
    final daily = await restarted.getDailyNewKanji();
    expect(daily.count, 4);
    expect(daily.forDay(now).count, 4);
    expect(daily.forDay(now.add(const Duration(days: 1))).count, 0);
  });

  test('changing the setting updates the workload estimate', () async {
    final progress = MemoryProgressRepository();
    final settings = SettingsController(progressRepository: progress);
    await settings.load();
    expect(settings.newKanjiPerDay, 5);
    final fiveLabel = settings.estimate.label;

    await settings.setNewKanjiPerDay(20);
    expect(settings.newKanjiPerDay, 20);
    expect(progress.settings.newKanjiPerDay, 20);
    expect(settings.estimate.minMinutes, greaterThan(5));
    expect(settings.estimate.label, isNot(fiveLabel));
  });

  test('saved settings without a start of day default to 4:00 AM', () {
    final settings = AppSettings.fromJson({'newKanjiPerDay': 8});
    expect(settings.newKanjiPerDay, 8);
    expect(settings.startOfDay, const StartOfDay(hour: 4));
  });

  test('changing start of day persists and is used immediately', () async {
    final progress = MemoryProgressRepository(
      dailyNewKanji: DailyNewKanjiProgress(
        date: DateTime(2026, 9, 8),
        count: 4,
      ),
    );
    final settings = SettingsController(progressRepository: progress);
    await settings.load();
    expect(settings.startOfDay, const StartOfDay(hour: 4));

    await settings.setStartOfDay(const StartOfDay(hour: 2, minute: 15));
    expect(settings.startOfDay, const StartOfDay(hour: 2, minute: 15));
    expect(progress.settings.startOfDay, const StartOfDay(hour: 2, minute: 15));

    final lateNight = DateTime(2026, 9, 9, 3);
    expect(
      (await progress.getDailyNewKanji())
          .forDay(lateNight, startOfDay: const StartOfDay(hour: 4))
          .count,
      4,
    );
    expect(
      (await progress.getDailyNewKanji())
          .forDay(lateNight, startOfDay: progress.settings.startOfDay)
          .count,
      0,
    );
  });
}

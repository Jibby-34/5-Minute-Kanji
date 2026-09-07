import 'package:flutter_test/flutter_test.dart';
import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/progress.dart';
import 'package:fiveminutekanji/core/models/review.dart';
import 'package:fiveminutekanji/core/models/study_phase.dart';
import 'package:fiveminutekanji/features/home/home_controller.dart';
import 'package:fiveminutekanji/features/review/review_controller.dart';
import 'package:fiveminutekanji/services/srs_engine.dart';

import 'support/fakes.dart';

void main() {
  var now = DateTime(2026, 9, 2, 8);
  final cards = [testCard('a', keyword: 'one'), testCard('b', keyword: 'two')];

  HomeController home(MemoryProgressRepository progress) {
    return HomeController(
      kanjiRepository: FakeKanjiRepository(cards),
      progressRepository: progress,
      config: const ReviewSessionConfig(
        duration: Duration(minutes: 5),
        maxCards: 25,
        averageSecondsPerCard: 12,
      ),
      clock: () => now,
    );
  }

  test('first launch counts new kanji separately from due reviews', () async {
    final progress = MemoryProgressRepository();
    await progress.seedIfNeeded(const ['a', 'b'], now: now);
    final controller = home(progress);

    await controller.load();

    expect(controller.dueCount, 0);
    expect(controller.newRemainingToday, 2);
    expect(controller.remainingToday, 2);
    expect(controller.estimatedMinutes, 1);
    expect(controller.isCaughtUp, isFalse);
    expect(controller.streak, 0);
  });

  test(
    'learning a kanji decreases remaining before the first retrieval',
    () async {
      final progress = MemoryProgressRepository();
      await progress.seedIfNeeded(const ['a', 'b'], now: now);
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

      final controller = home(progress);
      await controller.load();
      expect(controller.newRemainingToday, 1);
      expect(controller.remainingToday, 1);
      expect(controller.dueCount, 1);
      expect(controller.isCaughtUp, isFalse);
    },
  );

  test('Good removes a card from due until its interval elapses', () async {
    final progress = MemoryProgressRepository();
    await progress.seedIfNeeded(const ['a', 'b'], now: now);
    await progress.saveSchedule(
      CardSchedule(
        cardId: 'a',
        state: CardLearningState.review,
        reviewCount: 1,
        correctCount: 1,
        incorrectCount: 0,
        dueAt: now,
        interval: SrsEngine.graduatingInterval,
        ease: 2.5,
        lastReviewedAt: now,
        consecutiveGoodCount: 1,
      ),
    );
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
    expect(review.phase, StudyPhase.recall);
    review.submit();
    await review.rate(ReviewResult.good);

    final controller = home(progress);
    await controller.load();
    expect(controller.dueCount, 0);
    expect(controller.newRemainingToday, 1);
    expect((await controller.cardsForSession(practice: false)).single.id, 'b');

    final reviewed = await progress.getSchedule('a');
    now = reviewed!.dueAt;
    await controller.load();
    expect(controller.dueCount, 1);
    expect(controller.newRemainingToday, 1);
  });

  test('cards due later today count as today\'s workload', () async {
    final today = DateTime(2026, 9, 2, 8);
    final laterToday = DateTime(2026, 9, 2, 18);
    final tomorrow = DateTime(2026, 9, 3, 8);
    final progress = MemoryProgressRepository(
      schedules: {
        'a': CardSchedule(
          cardId: 'a',
          state: CardLearningState.review,
          reviewCount: 1,
          correctCount: 1,
          incorrectCount: 0,
          dueAt: laterToday,
          interval: const Duration(hours: 6),
          ease: 2.5,
          lastReviewedAt: today,
        ),
        'b': CardSchedule(
          cardId: 'b',
          state: CardLearningState.review,
          reviewCount: 1,
          correctCount: 1,
          incorrectCount: 0,
          dueAt: tomorrow,
          interval: const Duration(days: 1),
          ease: 2.5,
          lastReviewedAt: today,
        ),
      },
    );
    final controller = HomeController(
      kanjiRepository: FakeKanjiRepository(cards),
      progressRepository: progress,
      config: const ReviewSessionConfig(
        duration: Duration(minutes: 5),
        maxCards: 25,
        averageSecondsPerCard: 12,
      ),
      clock: () => today,
    );
    await controller.load();

    expect(controller.dueCount, 1);
    expect(controller.newRemainingToday, 0);
    expect(controller.isCaughtUp, isFalse);
    expect((await controller.cardsForSession(practice: false)).single.id, 'a');
    expect(controller.nextReviewAt, today);
  });

  test('caught-up home does not start a review session', () async {
    final later = now.add(const Duration(days: 3));
    final progress = MemoryProgressRepository(
      schedules: {
        'a': CardSchedule(
          cardId: 'a',
          state: CardLearningState.review,
          reviewCount: 1,
          correctCount: 1,
          incorrectCount: 0,
          dueAt: later,
          interval: const Duration(days: 3),
          ease: 2.5,
          lastReviewedAt: now,
        ),
        'b': CardSchedule(
          cardId: 'b',
          state: CardLearningState.review,
          reviewCount: 1,
          correctCount: 1,
          incorrectCount: 0,
          dueAt: later,
          interval: const Duration(days: 3),
          ease: 2.5,
          lastReviewedAt: now,
        ),
      },
    );
    final controller = home(progress);
    await controller.load();

    expect(controller.isCaughtUp, isTrue);
    expect(controller.dueCount, 0);
    expect(controller.newRemainingToday, 0);
    expect(controller.nextReviewAt, later);
    expect(await controller.cardsForSession(practice: false), isEmpty);
  });

  test('session mixes a few new cards with due reviews', () async {
    final mixCards = [
      testCard('r1'),
      testCard('r2'),
      testCard('r3'),
      testCard('r4'),
      testCard('r5'),
      testCard('n1'),
      testCard('n2'),
      testCard('n3'),
      testCard('n4'),
    ];
    final progress = MemoryProgressRepository(
      settings: const AppSettings(newKanjiPerDay: 10),
      schedules: {
        for (final id in ['r1', 'r2', 'r3', 'r4', 'r5'])
          id: CardSchedule(
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
          ),
        for (final id in ['n1', 'n2', 'n3', 'n4'])
          id: CardSchedule.fresh(id, now),
      },
    );
    final controller = HomeController(
      kanjiRepository: FakeKanjiRepository(mixCards),
      progressRepository: progress,
      config: const ReviewSessionConfig(
        duration: Duration(minutes: 5),
        maxCards: 25,
        averageSecondsPerCard: 12,
      ),
      clock: () => now,
    );
    await controller.load();
    final session = await controller.cardsForSession(practice: false);

    expect(controller.dueCount, 5);
    expect(controller.newRemainingToday, 4);
    expect(
      session.where((card) => card.id.startsWith('n')).length,
      lessThan(4),
    );
    expect(session.where((card) => card.id.startsWith('r')).length, 5);
    expect(session.first.id.startsWith('n'), isFalse);
  });
}

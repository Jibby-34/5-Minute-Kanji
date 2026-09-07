import 'package:flutter_test/flutter_test.dart';
import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/review.dart';
import 'package:fiveminutekanji/core/models/study_phase.dart';
import 'package:fiveminutekanji/features/review/review_controller.dart';
import 'package:fiveminutekanji/services/due_card_selector.dart';
import 'package:fiveminutekanji/services/srs_engine.dart';

import 'support/fakes.dart';

void main() {
  final now = DateTime(2026, 9, 2, 8);
  const config = ReviewSessionConfig(
    duration: Duration(minutes: 5),
    maxCards: 3,
  );

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

  Future<ReviewController> controllerFor({
    required MemoryProgressRepository progress,
    required List<String> ids,
    bool practice = false,
    bool alreadyReviewed = false,
    DateTime Function()? clock,
  }) async {
    final cards = ids.map(testCard).toList();
    await progress.seedIfNeeded(ids, now: now);
    if (alreadyReviewed) {
      for (final id in ids) {
        await progress.saveSchedule(dueReview(id));
      }
    }
    return ReviewController(
      progressRepository: progress,
      srsEngine: const SrsEngine(),
      cards: cards,
      config: config,
      isPractice: practice,
      startTime: now,
      clock: clock ?? () => now,
      schedules: Map<String, CardSchedule>.from(progress.schedules),
    );
  }

  test(
    'Good updates SRS state and ends the session on the last card',
    () async {
      final progress = MemoryProgressRepository();
      final controller = await controllerFor(
        progress: progress,
        ids: ['a'],
        alreadyReviewed: true,
      );

      expect(controller.current?.id, 'a');
      expect(controller.phase, StudyPhase.recall);
      controller.submit();
      final summary = await controller.rate(ReviewResult.good);

      expect(summary, isNotNull);
      expect(summary!.reviewedCount, 1);
      expect(summary.successfulCount, 1);
      expect(controller.isComplete, isTrue);

      final schedule = await progress.getSchedule('a');
      expect(schedule!.state, CardLearningState.review);
      expect(
        schedule.interval,
        const Duration(days: 3) - const Duration(hours: 12),
      );
      expect(schedule.dueAt, now.add(schedule.interval));
      expect(schedule.reviewCount, 2);
      expect(schedule.correctCount, 2);
      expect(schedule.incorrectCount, 0);
      expect(schedule.lastReviewedAt, now);
      expect(progress.history.single.rating, ReviewResult.good);
      expect(progress.streak.current, 1);
    },
  );

  test('Again keeps the card in-session and schedules a soon review', () async {
    final progress = MemoryProgressRepository();
    final controller = await controllerFor(
      progress: progress,
      ids: ['a', 'b'],
      alreadyReviewed: true,
    );

    expect(controller.phase, StudyPhase.recall);
    controller.submit();
    expect(await controller.rate(ReviewResult.again), isNull);
    expect(controller.isComplete, isFalse);
    expect(controller.current?.id, 'b');

    final schedule = await progress.getSchedule('a');
    expect(schedule!.state, CardLearningState.learning);
    expect(schedule.dueAt, now.add(SrsEngine.againInterval));
    expect(schedule.incorrectCount, 1);
    expect(schedule.correctCount, 1);
    expect(schedule.lastReviewedAt, now);
    expect(progress.streak.current, 0);
  });

  test(
    'Again then Good on the same card writes the final Good schedule',
    () async {
      final progress = MemoryProgressRepository();
      final controller = await controllerFor(
        progress: progress,
        ids: ['a'],
        alreadyReviewed: true,
      );

      controller.submit();
      await controller.rate(ReviewResult.again);
      expect(controller.current?.id, 'a');
      expect(controller.submitted, isFalse);
      expect(controller.phase, StudyPhase.recall);

      controller.submit();
      final summary = await controller.rate(ReviewResult.good);

      expect(summary, isNotNull);
      final schedule = await progress.getSchedule('a');
      expect(schedule!.state, CardLearningState.review);
      expect(schedule.dueAt, now.add(SrsEngine.graduatingInterval));
      expect(schedule.reviewCount, 3);
      expect(schedule.incorrectCount, 1);
      expect(schedule.correctCount, 2);
      expect(progress.history.map((entry) => entry.rating), [
        ReviewResult.again,
        ReviewResult.good,
      ]);
    },
  );

  test('practice does not change stored schedules', () async {
    final progress = MemoryProgressRepository();
    final controller = await controllerFor(
      progress: progress,
      ids: ['a'],
      practice: true,
    );

    expect(controller.phase, StudyPhase.learn);
    controller.beginPractice();
    expect(controller.phase, StudyPhase.practice);
    await controller.completePractice();
    expect(controller.phase, StudyPhase.recall);
    controller.submit();
    await controller.rate(ReviewResult.good);

    final schedule = await progress.getSchedule('a');
    expect(schedule!.state, CardLearningState.newCard);
    expect(schedule.reviewCount, 0);
    expect(progress.history.single.isPractice, isTrue);
  });

  test(
    'finishing learn keeps the SRS interval and moves to another card',
    () async {
      final progress = MemoryProgressRepository();
      final controller = await controllerFor(
        progress: progress,
        ids: ['a', 'b'],
      );

      expect(controller.current?.id, 'a');
      expect(controller.phase, StudyPhase.learn);
      controller.beginPractice();
      expect(await controller.completePractice(), isNull);

      expect(controller.current?.id, 'b');
      expect(controller.phase, StudyPhase.learn);

      final schedule = await progress.getSchedule('a');
      expect(schedule!.state, CardLearningState.learning);
      expect(schedule.dueAt, now.add(SrsEngine.newLearnInterval));
      expect(schedule.interval, SrsEngine.newLearnInterval);
      expect(schedule.isDueAt(now), isFalse);
      expect(progress.history, isEmpty);
    },
  );

  test('remainingToDraw counts learns and their later retrievals', () async {
    final progress = MemoryProgressRepository();
    final controller = await controllerFor(progress: progress, ids: ['a', 'b']);

    expect(controller.remainingToDraw, 4);
    controller.beginPractice();
    expect(controller.remainingToDraw, 4);
    expect(await controller.completePractice(), isNull);
    expect(controller.remainingToDraw, 3);

    controller.beginPractice();
    await controller.completePractice();
    expect(controller.remainingToDraw, 2);
    expect(controller.phase, StudyPhase.recall);

    controller.submit();
    expect(controller.remainingToDraw, 1);
    expect(await controller.rate(ReviewResult.good), isNull);
    expect(controller.remainingToDraw, 1);
  });

  test('remainingToDraw counts previous-day reviews once each', () async {
    final progress = MemoryProgressRepository();
    final controller = await controllerFor(
      progress: progress,
      ids: ['a', 'b'],
      alreadyReviewed: true,
    );

    expect(controller.remainingToDraw, 2);
    controller.submit();
    expect(controller.remainingToDraw, 1);
    expect(await controller.rate(ReviewResult.good), isNull);
    expect(controller.remainingToDraw, 1);
  });

  test('a newly learned card is retrieved later in the same sitting', () async {
    final progress = MemoryProgressRepository();
    final controller = await controllerFor(progress: progress, ids: ['a', 'b']);

    controller.beginPractice();
    await controller.completePractice();
    expect(controller.current?.id, 'b');
    expect(controller.phase, StudyPhase.learn);

    controller.beginPractice();
    await controller.completePractice();
    expect(controller.current?.id, 'a');
    expect(controller.phase, StudyPhase.recall);
    controller.submit();
    expect(await controller.rate(ReviewResult.good), isNull);

    expect(controller.current?.id, 'b');
    expect(controller.phase, StudyPhase.recall);
  });

  test('after learn the next card stays mixed, not the same kanji', () async {
    final progress = MemoryProgressRepository();
    await progress.seedIfNeeded(const ['r', 'n', 's'], now: now);
    await progress.saveSchedule(dueReview('r'));
    await progress.saveSchedule(dueReview('s'));
    final controller = ReviewController(
      progressRepository: progress,
      srsEngine: const SrsEngine(),
      cards: [testCard('r'), testCard('n'), testCard('s')],
      config: config,
      startTime: now,
      clock: () => now,
      schedules: Map<String, CardSchedule>.from(progress.schedules),
    );

    expect(controller.current?.id, 'r');
    expect(controller.phase, StudyPhase.recall);
    controller.submit();
    await controller.rate(ReviewResult.good);

    expect(controller.current?.id, 'n');
    expect(controller.phase, StudyPhase.learn);
    controller.beginPractice();
    await controller.completePractice();

    expect(controller.current?.id, 's');
    expect(controller.phase, StudyPhase.recall);
    expect(controller.current?.id, isNot('n'));
  });

  test(
    'the only new card is retrieved after learn before the sitting ends',
    () async {
      final progress = MemoryProgressRepository();
      final controller = await controllerFor(progress: progress, ids: ['a']);

      controller.beginPractice();
      expect(await controller.completePractice(), isNull);
      expect(controller.isComplete, isFalse);
      expect(controller.current?.id, 'a');
      expect(controller.phase, StudyPhase.recall);

      final learned = await progress.getSchedule('a');
      expect(learned!.state, CardLearningState.learning);
      expect(learned.isDueAt(now), isFalse);

      controller.submit();
      final summary = await controller.rate(ReviewResult.good);
      expect(summary, isNotNull);
      expect(controller.isComplete, isTrue);
      expect(progress.streak.current, 1);
    },
  );

  test(
    'later-today cards can be finished in one sitting without waiting',
    () async {
      final afternoon = DateTime(2026, 9, 2, 13);
      final evening = DateTime(2026, 9, 2, 18);
      final noon = DateTime(2026, 9, 2, 12);
      final tomorrow = DateTime(2026, 9, 3, 8);
      final progress = MemoryProgressRepository(
        schedules: {
          'now': CardSchedule(
            cardId: 'now',
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
          'afternoon': CardSchedule(
            cardId: 'afternoon',
            state: CardLearningState.review,
            reviewCount: 1,
            correctCount: 1,
            incorrectCount: 0,
            dueAt: afternoon,
            interval: SrsEngine.graduatingInterval,
            ease: 2.5,
            lastReviewedAt: now,
            consecutiveGoodCount: 1,
          ),
          'evening': CardSchedule(
            cardId: 'evening',
            state: CardLearningState.review,
            reviewCount: 1,
            correctCount: 1,
            incorrectCount: 0,
            dueAt: evening,
            interval: SrsEngine.graduatingInterval,
            ease: 2.5,
            lastReviewedAt: now,
            consecutiveGoodCount: 1,
          ),
          'short': CardSchedule(
            cardId: 'short',
            state: CardLearningState.review,
            reviewCount: 1,
            correctCount: 1,
            incorrectCount: 0,
            dueAt: noon,
            interval: const Duration(hours: 4),
            ease: 2.5,
            lastReviewedAt: now.subtract(const Duration(hours: 4)),
            consecutiveGoodCount: 1,
          ),
          'tomorrow': CardSchedule(
            cardId: 'tomorrow',
            state: CardLearningState.review,
            reviewCount: 1,
            correctCount: 1,
            incorrectCount: 0,
            dueAt: tomorrow,
            interval: const Duration(days: 1),
            ease: 2.5,
            lastReviewedAt: now,
            consecutiveGoodCount: 1,
          ),
        },
      );
      const selector = DueCardSelector();
      final all = [
        testCard('now'),
        testCard('afternoon'),
        testCard('evening'),
        testCard('short'),
        testCard('tomorrow'),
      ];
      final selected = selector.select(
        cards: all,
        schedules: progress.schedules,
        now: now,
        limit: 25,
        maxNewCards: 0,
      );
      expect(selected.map((card) => card.id).toSet(), {
        'now',
        'afternoon',
        'evening',
        'short',
      });
      expect(selected.map((card) => card.id), isNot(contains('tomorrow')));

      final controller = ReviewController(
        progressRepository: progress,
        srsEngine: const SrsEngine(),
        cards: selected,
        config: const ReviewSessionConfig(
          duration: Duration(minutes: 5),
          maxCards: 25,
        ),
        startTime: now,
        clock: () => now,
        schedules: Map<String, CardSchedule>.from(progress.schedules),
      );

      while (!controller.isComplete) {
        expect(controller.current?.id, isNot('tomorrow'));
        controller.submit();
        await controller.rate(ReviewResult.good);
      }

      expect(controller.summary, isNotNull);
      expect(progress.schedules['tomorrow']!.dueAt, tomorrow);
      for (final id in ['now', 'afternoon', 'evening', 'short']) {
        final schedule = progress.schedules[id]!;
        expect(schedule.isDueAt(now), isFalse);
        expect(selector.isAvailableToday(schedule, now), isFalse);
        expect(schedule.dueAt.isBefore(DateTime(2026, 9, 3)), isFalse);
      }
    },
  );

  test('introduced SRS state survives a new controller instance', () async {
    final progress = MemoryProgressRepository();
    final first = await controllerFor(progress: progress, ids: ['a', 'b']);
    first.beginPractice();
    await first.completePractice();

    final later = now.add(SrsEngine.newLearnInterval);
    final restarted = ReviewController(
      progressRepository: progress,
      srsEngine: const SrsEngine(),
      cards: [testCard('a')],
      config: config,
      startTime: later,
      clock: () => later,
      schedules: Map<String, CardSchedule>.from(progress.schedules),
    );

    expect(restarted.phase, StudyPhase.recall);
    expect(restarted.current?.id, 'a');
    final schedule = await progress.getSchedule('a');
    expect(schedule!.state, CardLearningState.learning);
    expect(schedule.dueAt, now.add(SrsEngine.newLearnInterval));
  });
}

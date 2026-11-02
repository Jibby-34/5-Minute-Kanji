import 'package:flutter_test/flutter_test.dart';
import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/daily_session_plan.dart';
import 'package:fiveminutekanji/core/models/kanji_card.dart';
import 'package:fiveminutekanji/core/models/progress.dart';
import 'package:fiveminutekanji/core/models/review.dart';
import 'package:fiveminutekanji/core/models/study_day_type.dart';
import 'package:fiveminutekanji/core/models/study_phase.dart';
import 'package:fiveminutekanji/features/review/review_controller.dart';
import 'package:fiveminutekanji/services/adaptive_session_adjuster.dart';
import 'package:fiveminutekanji/services/card_time_estimator.dart';
import 'package:fiveminutekanji/services/daily_workload.dart';
import 'package:fiveminutekanji/services/review_session.dart';
import 'package:fiveminutekanji/services/srs_engine.dart';

import 'support/fakes.dart';

void main() {
  const adjuster = AdaptiveSessionAdjuster();
  const goal = Duration(seconds: 100);

  AdaptiveQueueCard card(
    String id, {
    required double priority,
    required int seconds,
    bool current = false,
    bool protected = false,
  }) {
    return AdaptiveQueueCard(
      id: id,
      card: testCard(id),
      priority: priority,
      estimated: Duration(seconds: seconds),
      protected: protected || current,
      isCurrent: current,
    );
  }

  AdaptiveQueueDecision decide({
    Duration elapsed = const Duration(seconds: 20),
    Duration sittingGoal = goal,
    required List<AdaptiveQueueCard> queue,
    List<AdaptiveQueueCard> replacements = const [],
    Set<String> droppedIds = const {},
    int adjustmentsUsed = 0,
    int? maxQueueLength,
    AdaptiveSessionAdjuster engine = adjuster,
  }) {
    return engine.decide(
      elapsed: elapsed,
      goal: sittingGoal,
      queue: queue,
      replacements: replacements,
      droppedIds: droppedIds,
      adjustmentsUsed: adjustmentsUsed,
      maxQueueLength: maxQueueLength ?? queue.length,
    );
  }

  group('SessionPaceTracker', () {
    test('matching times leave the historical estimate unchanged', () {
      final pace = SessionPaceTracker()
        ..record(const Duration(seconds: 18), const Duration(seconds: 18));

      expect(pace.factor, 1);
      expect(
        pace.scale(const Duration(seconds: 18)),
        const Duration(seconds: 18),
      );
    });

    test('a slow sitting raises later estimates and a fast one does not', () {
      final slow = SessionPaceTracker()
        ..record(const Duration(seconds: 18), const Duration(seconds: 40))
        ..record(const Duration(seconds: 18), const Duration(seconds: 40));
      expect(slow.factor, greaterThan(1));
      expect(
        slow.scale(const Duration(seconds: 18)),
        greaterThan(const Duration(seconds: 18)),
      );

      final fast = SessionPaceTracker()
        ..record(const Duration(seconds: 18), const Duration(seconds: 8));
      expect(fast.factor, 1);
      expect(
        fast.scale(const Duration(seconds: 18)),
        const Duration(seconds: 18),
      );
    });
  });

  group('AdaptiveSessionAdjuster', () {
    test('a normal sitting inside the goal is left alone', () {
      final decision = decide(
        elapsed: const Duration(seconds: 30),
        queue: [
          card('now', priority: 2, seconds: 18, current: true),
          card('next', priority: 1, seconds: 18),
        ],
      );

      expect(decision.changed, isFalse);
      expect(decision.steps, isEmpty);
      expect(decision.projectedBefore, const Duration(seconds: 66));
    });

    test('slow reviews over the threshold drop the lowest future cards', () {
      final decision = decide(
        elapsed: const Duration(seconds: 20),
        queue: [
          card('now', priority: 3, seconds: 10, current: true),
          card('low', priority: 1, seconds: 30),
          card('mid', priority: 2, seconds: 30),
          card('high', priority: 5, seconds: 30),
        ],
      );

      expect(decision.changed, isTrue);
      expect(
        decision.projectedBefore,
        greaterThan(goal + const Duration(seconds: 15)),
      );
      expect(decision.steps.map((step) => step.removedId), ['low']);
      expect(decision.steps.single.replacement, isNull);
      expect(
        decision.projectedAfter,
        lessThanOrEqualTo(goal - const Duration(seconds: 10)),
      );
      expect(decision.eligibleIds, containsAll(['low', 'mid', 'high']));
      expect(decision.describe(), contains('removed=low'));
    });

    test('new and relearning cards are never removed', () {
      final decision = decide(
        elapsed: const Duration(seconds: 80),
        queue: [
          card('now', priority: 0.1, seconds: 40, current: true),
          card('fresh', priority: 0.1, seconds: 52, protected: true),
          card('again', priority: 0.1, seconds: 40, protected: true),
          card('review', priority: 0.2, seconds: 30),
        ],
      );

      expect(decision.steps.map((step) => step.removedId), ['review']);
      expect(decision.protectedCount, 3);
    });

    test('an ordinary review that failed this sitting stays protected', () {
      final decision = decide(
        elapsed: const Duration(seconds: 80),
        queue: [
          card('now', priority: 3, seconds: 10, current: true),
          card('failed-review', priority: 0.1, seconds: 90, protected: true),
          card('other', priority: 1, seconds: 30),
        ],
      );

      expect(
        decision.steps.map((step) => step.removedId),
        isNot(contains('failed-review')),
      );
      expect(decision.steps.map((step) => step.removedId), ['other']);
    });

    test('the lowest priority eligible review leaves before a higher one', () {
      final decision = decide(
        elapsed: const Duration(seconds: 20),
        queue: [
          card('now', priority: 9, seconds: 10, current: true),
          card('low', priority: 1, seconds: 30),
          card('mid', priority: 2, seconds: 30),
          card('high', priority: 5, seconds: 30),
        ],
      );

      expect(decision.steps.map((step) => step.removedId), ['low']);
      expect(decision.eligibleIds, containsAll(['mid', 'high']));
    });

    test('comparable priorities drop the review that saves more time', () {
      final decision = decide(
        elapsed: const Duration(seconds: 30),
        sittingGoal: const Duration(seconds: 60),
        queue: [
          card('now', priority: 4, seconds: 10, current: true),
          card('short-low', priority: 1.0, seconds: 10),
          card('long-near', priority: 1.1, seconds: 40),
        ],
      );

      expect(decision.steps.map((step) => step.removedId), ['long-near']);
      expect(decision.projectedAfter <= const Duration(seconds: 50), isTrue);
    });

    test(
      'a clearly lower priority leaves even when it is the shorter card',
      () {
        final decision = decide(
          elapsed: const Duration(seconds: 30),
          sittingGoal: const Duration(seconds: 60),
          queue: [
            card('now', priority: 4, seconds: 10, current: true),
            card('short-low', priority: 1, seconds: 20),
            card('long-high', priority: 2, seconds: 40),
          ],
        );

        expect(decision.steps.first.removedId, 'short-low');
      },
    );

    test('a long review is swapped for a shorter equal-or-better one', () {
      final replacement = card('short', priority: 1.2, seconds: 10);
      final decision = decide(
        elapsed: const Duration(seconds: 60),
        queue: [
          card('now', priority: 3, seconds: 20, current: true),
          card('long', priority: 1, seconds: 40),
        ],
        replacements: [replacement],
      );

      expect(decision.steps, hasLength(1));
      expect(decision.steps.single.removedId, 'long');
      expect(decision.steps.single.replacementId, 'short');
      expect(decision.steps.single.estimatedSaved, const Duration(seconds: 30));
      expect(
        decision.projectedAfter,
        lessThanOrEqualTo(goal - const Duration(seconds: 10)),
      );
    });

    test('a few seconds saved does not justify a swap', () {
      final decision = decide(
        elapsed: const Duration(seconds: 60),
        queue: [
          card('now', priority: 3, seconds: 20, current: true),
          card('long', priority: 1, seconds: 40),
        ],
        replacements: [card('almost', priority: 2, seconds: 36)],
      );

      expect(decision.steps.single.removedId, 'long');
      expect(decision.steps.single.replacement, isNull);
    });

    test('with no shorter stand-in the card is only removed', () {
      final decision = decide(
        elapsed: const Duration(seconds: 60),
        queue: [
          card('now', priority: 3, seconds: 20, current: true),
          card('long', priority: 1, seconds: 40),
        ],
      );

      expect(decision.steps.single.replacement, isNull);
      expect(decision.steps.single.removedId, 'long');
    });

    test('a sitting of only protected cards is allowed to run long', () {
      final decision = decide(
        elapsed: const Duration(seconds: 90),
        queue: [
          card('now', priority: 1, seconds: 40, current: true),
          card('fresh', priority: 1, seconds: 52, protected: true),
          card('learning', priority: 1, seconds: 21, protected: true),
        ],
      );

      expect(decision.changed, isFalse);
      expect(decision.projectedBefore, greaterThan(goal));
      expect(decision.eligibleCount, 0);
    });

    test('a dropped card is not brought back in a later pass', () {
      final first = decide(
        elapsed: const Duration(seconds: 60),
        queue: [
          card('now', priority: 3, seconds: 20, current: true),
          card('long', priority: 1, seconds: 40),
        ],
        replacements: [card('short', priority: 2, seconds: 10)],
      );
      expect(first.steps.single.removedId, 'long');

      final again = decide(
        elapsed: const Duration(seconds: 70),
        queue: [
          card('now', priority: 3, seconds: 20, current: true),
          card('short', priority: 2, seconds: 10),
          card('other', priority: 1, seconds: 40),
        ],
        replacements: [
          card('long', priority: 5, seconds: 5),
          card('short', priority: 2, seconds: 10),
        ],
        droppedIds: {'long'},
      );

      expect(
        again.steps.map((step) => step.removedId),
        isNot(contains('long')),
      );
      expect(
        again.steps.map((step) => step.replacementId),
        isNot(contains('long')),
      );
    });

    test('the card on screen is never removed', () {
      final decision = decide(
        elapsed: const Duration(seconds: 80),
        queue: [
          card('on-screen', priority: 0.1, seconds: 90, current: true),
          card('later', priority: 2, seconds: 30),
        ],
      );

      expect(decision.steps.map((step) => step.removedId), ['later']);
    });

    test('swaps do not grow the queue past its original length', () {
      final decision = decide(
        elapsed: const Duration(seconds: 60),
        queue: [
          card('now', priority: 3, seconds: 20, current: true),
          card('long', priority: 1, seconds: 40),
        ],
        replacements: [
          card('a', priority: 3, seconds: 10),
          card('b', priority: 3, seconds: 8),
        ],
        maxQueueLength: 2,
      );

      expect(decision.steps, hasLength(1));
      expect(decision.steps.single.replacementId, isNotNull);
    });

    test('adjustments stop at the configured cap', () {
      final engine = AdaptiveSessionAdjuster(
        config: const AdaptiveQueueConfig(maximumAdjustmentsPerSession: 2),
      );
      final decision = decide(
        engine: engine,
        elapsed: const Duration(seconds: 90),
        queue: [
          card('now', priority: 9, seconds: 10, current: true),
          for (var i = 0; i < 6; i++)
            card('r$i', priority: i.toDouble(), seconds: 30),
        ],
      );

      expect(decision.steps, hasLength(2));
      expect(decision.adjustmentsUsed, 2);
      expect(decision.projectedAfter, greaterThan(goal));

      final stopped = decide(
        engine: engine,
        elapsed: const Duration(seconds: 90),
        adjustmentsUsed: 2,
        queue: [
          card('now', priority: 9, seconds: 10, current: true),
          card('still', priority: 1, seconds: 30),
        ],
      );
      expect(stopped.changed, isFalse);
    });

    test('a slightly lower priority can replace a card when it saves time', () {
      final decision = decide(
        elapsed: const Duration(seconds: 60),
        queue: [
          card('now', priority: 3, seconds: 20, current: true),
          card('long', priority: 1, seconds: 40),
        ],
        replacements: [card('bit-lower', priority: 0.9, seconds: 10)],
      );

      expect(decision.steps.single.replacementId, 'bit-lower');
    });

    test('a large priority drop is not worth the time savings', () {
      final decision = decide(
        elapsed: const Duration(seconds: 60),
        queue: [
          card('now', priority: 3, seconds: 20, current: true),
          card('long', priority: 1, seconds: 40),
        ],
        replacements: [card('unrelated', priority: 0.1, seconds: 10)],
      );

      expect(decision.steps.single.replacement, isNull);
    });
  });

  group('ReviewSession', () {
    test('dropped cards stay out and the card on screen stays', () {
      final session = ReviewSession(
        config: ReviewSessionConfig.fiveMinute,
        cards: [testCard('now'), testCard('later'), testCard('low')],
      );

      session.applyAdaptiveSteps(const [
        AdaptiveQueueStep(
          removedId: 'now',
          estimatedSaved: Duration(seconds: 10),
        ),
        AdaptiveQueueStep(
          removedId: 'low',
          estimatedSaved: Duration(seconds: 30),
        ),
      ]);

      expect(session.current?.id, 'now');
      expect(session.queued.map((queued) => queued.id), ['now', 'later']);
      expect(session.isDropped('low'), isTrue);
      expect(session.pool.map((pooled) => pooled.id), contains('low'));
      expect(session.adjustmentsMade, 1);

      session.offerDue([testCard('now'), testCard('later'), testCard('low')]);
      expect(session.queued.map((queued) => queued.id), ['now', 'later']);
      expect(session.continueWith(testCard('low')), isFalse);
    });

    test('Again protects the requeued card for the rest of the sitting', () {
      final session = ReviewSession(
        config: ReviewSessionConfig.fiveMinute,
        cards: [testCard('review'), testCard('next')],
      );

      session.recordRating(ReviewResult.again);
      expect(session.isRelearningProtected('review'), isTrue);
      expect(session.queued.map((queued) => queued.id), contains('review'));

      final saved = session.checkpoint();
      session.restore(saved);
      expect(session.isRelearningProtected('review'), isTrue);
    });

    test('undo restores a queue from before a drop', () {
      final session = ReviewSession(
        config: ReviewSessionConfig.fiveMinute,
        cards: [testCard('now'), testCard('later'), testCard('low')],
      );
      final saved = session.checkpoint();
      session.recordRating(ReviewResult.good);
      session.applyAdaptiveSteps(const [
        AdaptiveQueueStep(
          removedId: 'low',
          estimatedSaved: Duration(seconds: 20),
        ),
      ]);
      expect(session.isDropped('low'), isTrue);
      expect(session.current?.id, 'later');

      session.restore(saved);
      expect(session.current?.id, 'now');
      expect(session.isDropped('low'), isFalse);
      expect(session.adjustmentsMade, 0);
      expect(session.queued.map((queued) => queued.id), [
        'now',
        'later',
        'low',
      ]);
    });
  });

  group('ReviewController', () {
    final now = DateTime(2026, 9, 2, 8);

    CardSchedule dueReview(String id) {
      return CardSchedule(
        cardId: id,
        state: CardLearningState.review,
        reviewCount: 1,
        correctCount: 1,
        incorrectCount: 0,
        dueAt: now,
        interval: const Duration(days: 1),
        ease: 2.5,
        lastReviewedAt: now.subtract(const Duration(days: 1)),
        consecutiveGoodCount: 1,
      );
    }

    CardSchedule learning(String id) {
      return CardSchedule(
        cardId: id,
        state: CardLearningState.learning,
        reviewCount: 1,
        correctCount: 0,
        incorrectCount: 1,
        dueAt: now,
        interval: const Duration(minutes: 1),
        ease: 2.3,
        lastReviewedAt: now.subtract(const Duration(minutes: 1)),
      );
    }

    List<String> ids(int count) => [
      for (var i = 0; i < count; i++) 'c${i.toString().padLeft(2, '0')}',
    ];

    Future<ReviewController> open({
      required MemoryProgressRepository progress,
      required List<KanjiCard> cards,
      required Map<String, CardSchedule> schedules,
      DateTime? startTime,
      DateTime Function()? clock,
      bool studyAnyway = false,
      List<KanjiCard>? extraDueReviews,
      AdaptiveSessionAdjuster? queueAdjuster,
      CardTimeEstimator? timeEstimator,
    }) async {
      return ReviewController(
        progressRepository: progress,
        srsEngine: const SrsEngine(),
        cards: cards,
        config: const ReviewSessionConfig(duration: Duration(minutes: 3)),
        isStudyAnyway: studyAnyway,
        startTime: startTime ?? now,
        clock: clock ?? () => now,
        schedules: schedules,
        extraDueReviews: extraDueReviews,
        queueAdjuster: queueAdjuster ?? const AdaptiveSessionAdjuster(),
        timeEstimator: timeEstimator ?? const CardTimeEstimator(),
      );
    }

    test(
      'reviews that match their estimates do not change the queue',
      () async {
        final names = ids(3);
        final schedules = {for (final id in names) id: dueReview(id)};
        var current = now;
        final progress = MemoryProgressRepository(
          settings: const AppSettings(dailyStudyMinutes: 5, newKanjiPerDay: 0),
          schedules: schedules,
        );
        final controller = await open(
          progress: progress,
          cards: names.map(testCard).toList(),
          schedules: schedules,
          clock: () => current,
        );

        current = now.add(const Duration(seconds: 18));
        controller.submit();
        expect(await controller.rate(ReviewResult.good), isNull);

        expect(controller.lastQueueAdjustment, isNull);
        expect(controller.session.queued.map((card) => card.id), [
          'c01',
          'c02',
        ]);
        expect(controller.remainingToDraw, 2);
      },
    );

    test(
      'slow reviews shorten the assigned queue and leave SRS alone',
      () async {
        final names = ids(12);
        final schedules = {for (final id in names) id: dueReview(id)};
        final before = {for (final id in names) id: schedules[id]!.toJson()};
        final plan = DailySessionPlan(
          studyDate: DateTime(2026, 9, 2),
          budgetMinutes: 3,
          newKanjiPerDay: 0,
          cardIds: names,
        );
        var current = now;
        final progress = MemoryProgressRepository(
          settings: const AppSettings(dailyStudyMinutes: 3, newKanjiPerDay: 0),
          schedules: schedules,
          dailySessionPlan: plan,
        );
        final controller = await open(
          progress: progress,
          cards: names.map(testCard).toList(),
          schedules: schedules,
          clock: () => current,
        );

        current = now.add(const Duration(seconds: 60));
        controller.submit();
        expect(await controller.rate(ReviewResult.good), isNull);

        expect(controller.session.adjustmentsMade, 5);
        expect(controller.session.queued.map((card) => card.id), [
          'c01',
          'c07',
          'c08',
          'c09',
          'c10',
          'c11',
        ]);
        expect(controller.remainingToDraw, 6);
        expect(controller.current?.id, 'c01');
        for (final id in ['c02', 'c03', 'c04', 'c05', 'c06']) {
          expect(controller.session.isDropped(id), isTrue);
          expect(progress.schedules[id]!.toJson(), before[id]);
        }
        expect(progress.history.map((entry) => entry.cardId), ['c00']);
        expect(progress.dailySessionPlan.cardIds, names);
        expect(progress.dailySessionPlan.completed, isFalse);

        final workload = await DailyWorkloadService(
          kanjiRepository: FakeKanjiRepository(names.map(testCard).toList()),
          progressRepository: progress,
        ).read(now: current);
        expect(workload.overflowCards, isEmpty);
        expect(workload.sessionCards.map((card) => card.id), contains('c02'));

        controller.session.offerDue([testCard('c02')]);
        expect(
          controller.session.queued.map((card) => card.id),
          isNot(contains('c02')),
        );

        controller.submit();
        expect(await controller.rate(ReviewResult.good), isNull);
        expect(controller.session.adjustmentsMade, 5);
        expect(controller.session.queued.map((card) => card.id), [
          'c07',
          'c08',
          'c09',
          'c10',
          'c11',
        ]);
      },
    );

    test('undo puts a dropped review back into the sitting', () async {
      final names = ids(12);
      final schedules = {for (final id in names) id: dueReview(id)};
      var current = now;
      final progress = MemoryProgressRepository(
        settings: const AppSettings(dailyStudyMinutes: 3, newKanjiPerDay: 0),
        schedules: schedules,
      );
      final controller = await open(
        progress: progress,
        cards: names.map(testCard).toList(),
        schedules: schedules,
        clock: () => current,
      );

      current = now.add(const Duration(seconds: 60));
      controller.submit();
      expect(await controller.rate(ReviewResult.good), isNull);
      expect(controller.session.isDropped('c02'), isTrue);

      expect(await controller.undoLastAnswer(), isTrue);
      expect(controller.current?.id, 'c00');
      expect(controller.session.isDropped('c02'), isFalse);
      expect(controller.session.adjustmentsMade, 0);
      expect(controller.session.queued.map((card) => card.id), names);
      expect(controller.lastQueueAdjustment, isNull);
    });

    test(
      'new and learning cards stay while ordinary reviews can leave',
      () async {
        final reviewNames = ids(8);
        final schedules = {
          for (final id in reviewNames) id: dueReview(id),
          'learn': learning('learn'),
        };
        var current = now;
        final progress = MemoryProgressRepository(
          settings: const AppSettings(dailyStudyMinutes: 3, newKanjiPerDay: 2),
          schedules: schedules,
        );
        final cards = [
          testCard('fresh'),
          testCard('learn'),
          ...reviewNames.map(testCard),
          testCard('fresh-later'),
        ];
        final controller = await open(
          progress: progress,
          cards: cards,
          schedules: schedules,
          clock: () => current,
        );

        expect(controller.phase, StudyPhase.learn);
        current = now.add(const Duration(seconds: 40));
        controller.beginPractice();
        expect(await controller.completePractice(), isNull);

        final queued = controller.session.queued
            .map((card) => card.id)
            .toList();
        expect(queued, contains('fresh'));
        expect(queued, contains('fresh-later'));
        expect(queued, contains('learn'));
        expect(controller.session.isDropped('fresh'), isFalse);
        expect(controller.session.isDropped('learn'), isFalse);
        expect(controller.session.droppedIds, isNotEmpty);
      },
    );

    test(
      'Again protects that card even though it started as a review',
      () async {
        final names = ids(8);
        final schedules = {for (final id in names) id: dueReview(id)};
        var current = now;
        final progress = MemoryProgressRepository(
          settings: const AppSettings(dailyStudyMinutes: 3, newKanjiPerDay: 0),
          schedules: schedules,
        );
        final controller = await open(
          progress: progress,
          cards: names.map(testCard).toList(),
          schedules: schedules,
          clock: () => current,
        );

        current = now.add(const Duration(seconds: 60));
        controller.submit();
        expect(await controller.rate(ReviewResult.again), isNull);

        expect(controller.session.isRelearningProtected('c00'), isTrue);
        expect(
          controller.session.queued.map((card) => card.id),
          contains('c00'),
        );
        expect(progress.schedules['c00']!.state, CardLearningState.learning);
        expect(controller.session.isDropped('c00'), isFalse);
        expect(controller.session.droppedIds, isNotEmpty);
        expect(controller.current?.id, isNot('c00'));
      },
    );

    test('a long review can be replaced by a shorter due review', () async {
      final schedules = {
        'c00': dueReview('c00'),
        'c01': dueReview('c01'),
        'c02': dueReview('c02'),
        'short': CardSchedule(
          cardId: 'short',
          state: CardLearningState.review,
          reviewCount: 8,
          correctCount: 8,
          incorrectCount: 0,
          dueAt: now,
          interval: const Duration(days: 40),
          ease: 2.5,
          lastReviewedAt: now.subtract(const Duration(days: 40)),
          consecutiveGoodCount: 8,
        ),
      };
      final before = schedules['c02']!.toJson();
      final progress = MemoryProgressRepository(
        settings: const AppSettings(dailyStudyMinutes: 3, newKanjiPerDay: 0),
        schedules: schedules,
      );
      final controller = await open(
        progress: progress,
        cards: [testCard('c00'), testCard('c01'), testCard('c02')],
        schedules: schedules,
        startTime: now.subtract(const Duration(seconds: 120)),
        extraDueReviews: [testCard('short')],
        queueAdjuster: const AdaptiveSessionAdjuster(
          config: AdaptiveQueueConfig(priorityTolerance: 2),
        ),
        timeEstimator: const CardTimeEstimator(
          reviewCard: Duration(seconds: 40),
          matureCard: Duration(seconds: 8),
        ),
      );

      controller.submit();
      expect(await controller.rate(ReviewResult.good), isNull);

      expect(controller.session.queued.map((card) => card.id), [
        'c01',
        'short',
      ]);
      expect(controller.session.isDropped('c02'), isTrue);
      expect(progress.schedules['c02']!.toJson(), before);
      expect(progress.history.map((entry) => entry.cardId), ['c00']);
      expect(
        controller.session.queued,
        hasLength(controller.session.initialCount - 1),
      );
    });

    test('a protected-only sitting is allowed to pass the goal', () async {
      final names = ['l0', 'l1', 'l2', 'l3'];
      final schedules = {for (final id in names) id: learning(id)};
      final progress = MemoryProgressRepository(
        settings: const AppSettings(dailyStudyMinutes: 3, newKanjiPerDay: 0),
        schedules: schedules,
      );
      final controller = await open(
        progress: progress,
        cards: names.map(testCard).toList(),
        schedules: schedules,
        startTime: now.subtract(const Duration(minutes: 6)),
      );

      controller.submit();
      expect(await controller.rate(ReviewResult.good), isNull);

      expect(controller.lastQueueAdjustment, isNull);
      expect(controller.session.droppedIds, isEmpty);
      expect(controller.session.queued.map((card) => card.id), [
        'l1',
        'l2',
        'l3',
      ]);
    });

    test(
      'Study Anyway does not receive cards dropped from the assigned queue',
      () async {
        final names = ids(12);
        final schedules = {for (final id in names) id: dueReview(id)};
        final plan = DailySessionPlan(
          studyDate: DateTime(2026, 9, 2),
          budgetMinutes: 3,
          newKanjiPerDay: 0,
          dayType: StudyDayType.normal,
          cardIds: names,
        );
        var current = now;
        final progress = MemoryProgressRepository(
          settings: const AppSettings(dailyStudyMinutes: 3, newKanjiPerDay: 0),
          schedules: schedules,
          dailySessionPlan: plan,
        );
        final controller = await open(
          progress: progress,
          cards: names.map(testCard).toList(),
          schedules: schedules,
          clock: () => current,
        );

        current = now.add(const Duration(seconds: 60));
        controller.submit();
        expect(await controller.rate(ReviewResult.good), isNull);
        expect(controller.session.isDropped('c02'), isTrue);

        final workload = await DailyWorkloadService(
          kanjiRepository: FakeKanjiRepository(names.map(testCard).toList()),
          progressRepository: progress,
        ).read(now: current);

        expect(workload.studyAnywayAvailable, isFalse);
        expect(workload.overflowCards, isEmpty);
        expect(workload.dayType, StudyDayType.normal);
        expect(progress.dailySessionPlan.cardIds, names);
      },
    );

    test(
      'a reinforcement day still plans no new kanji and keeps learning cards',
      () async {
        final reviews = [
          for (var i = 0; i < 8; i++)
            testCard('r${i.toString().padLeft(2, '0')}'),
        ];
        final news = [testCard('n0'), testCard('n1')];
        final schedules = {
          for (final card in reviews)
            card.id: CardSchedule(
              cardId: card.id,
              state: CardLearningState.review,
              reviewCount: 4,
              correctCount: 4,
              incorrectCount: 0,
              dueAt: now,
              interval: const Duration(days: 10),
              ease: 2.5,
              lastReviewedAt: now.subtract(const Duration(days: 17)),
            ),
        };
        final progress = MemoryProgressRepository(
          settings: const AppSettings(dailyStudyMinutes: 30, newKanjiPerDay: 5),
          schedules: schedules,
        );
        final workload = await DailyWorkloadService(
          kanjiRepository: FakeKanjiRepository([...reviews, ...news]),
          progressRepository: progress,
        ).read(now: now);

        expect(workload.dayType, StudyDayType.reinforcement);
        expect(workload.allocation.newCards, 0);
        expect(
          workload.sessionCards.map((card) => card.id),
          isNot(contains('n0')),
        );

        final learningCard = card(
          'learning',
          priority: 0.2,
          seconds: 40,
          protected: true,
        );
        final queue = [
          card('now', priority: 1, seconds: 20, current: true),
          learningCard,
          for (final review in workload.sessionCards)
            card(review.id, priority: 1, seconds: 30),
        ];
        final decision = decide(
          elapsed: const Duration(minutes: 20),
          sittingGoal: const Duration(minutes: 5),
          queue: queue,
          replacements: [
            card('n0', priority: 5, seconds: 8, protected: true),
            card('shorter', priority: 2, seconds: 8),
          ],
        );

        expect(
          decision.steps.map((step) => step.removedId),
          isNot(contains('learning')),
        );
        expect(
          decision.steps.map((step) => step.replacementId),
          isNot(contains('n0')),
        );
        expect(progress.dailySessionPlan.dayType, StudyDayType.reinforcement);
        expect(progress.dailySessionPlan.cardIds, isNot(contains('n0')));
      },
    );
  });
}

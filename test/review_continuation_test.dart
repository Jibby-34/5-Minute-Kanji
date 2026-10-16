import 'package:flutter_test/flutter_test.dart';
import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/daily_session_plan.dart';
import 'package:fiveminutekanji/core/models/kanji_card.dart';
import 'package:fiveminutekanji/core/models/progress.dart';
import 'package:fiveminutekanji/core/models/review.dart';
import 'package:fiveminutekanji/core/models/study_phase.dart';
import 'package:fiveminutekanji/features/review/review_controller.dart';
import 'package:fiveminutekanji/services/daily_workload.dart';
import 'package:fiveminutekanji/services/srs_engine.dart';

import 'support/fakes.dart';

void main() {
  final now = DateTime(2026, 9, 2, 8);
  const goal = Duration(minutes: 5);

  CardSchedule reviewCard(
    String id, {
    DateTime? dueAt,
    int incorrect = 0,
    Duration interval = const Duration(days: 1),
  }) {
    return CardSchedule(
      cardId: id,
      state: CardLearningState.review,
      reviewCount: incorrect + 1,
      correctCount: 1,
      incorrectCount: incorrect,
      dueAt: dueAt ?? now,
      interval: interval,
      ease: 2.5,
      lastReviewedAt: now.subtract(interval),
      consecutiveGoodCount: 1,
    );
  }

  Future<ReviewController> open({
    required MemoryProgressRepository progress,
    required List<KanjiCard> deck,
    required List<KanjiCard> sessionCards,
    required DateTime Function() clock,
    bool studyAnyway = false,
  }) async {
    return ReviewController(
      progressRepository: progress,
      srsEngine: const SrsEngine(),
      cards: sessionCards,
      config: const ReviewSessionConfig(
        duration: Duration(minutes: 5),
        maxCards: 20,
      ),
      isStudyAnyway: studyAnyway,
      startTime: now,
      clock: clock,
      schedules: Map<String, CardSchedule>.from(progress.schedules),
      workloadService: DailyWorkloadService(
        kanjiRepository: FakeKanjiRepository(deck),
        progressRepository: progress,
      ),
    );
  }

  Future<SessionSummary?> pass(ReviewController controller) async {
    expect(controller.phase, StudyPhase.recall);
    controller.submit();
    return controller.rate(ReviewResult.good);
  }

  MemoryProgressRepository progressFor(Map<String, CardSchedule> schedules) {
    return MemoryProgressRepository(
      settings: const AppSettings(dailyStudyMinutes: 5, newKanjiPerDay: 0),
      schedules: schedules,
    );
  }

  test(
    'allotted cards finished under the goal continue with the next priority card',
    () async {
      final deck = [testCard('allotted'), testCard('next'), testCard('later')];
      final progress = progressFor({
        'allotted': reviewCard('allotted', incorrect: 1),
        'next': reviewCard('next', incorrect: 4),
        'later': reviewCard('later', dueAt: now.add(const Duration(days: 3))),
      });
      final current = now.add(const Duration(minutes: 3));
      final before = progress.schedules['next']!.toJson();
      final controller = await open(
        progress: progress,
        deck: deck,
        sessionCards: [deck.first],
        clock: () => current,
      );

      expect(await pass(controller), isNull);
      expect(controller.isComplete, isFalse);
      expect(controller.current?.id, 'next');
      expect(controller.session.startTime, now);
      expect(
        controller.reviewClock.totalAt(current),
        const Duration(minutes: 3),
      );
      expect(progress.schedules['next']!.toJson(), before);
      expect(progress.history.map((entry) => entry.cardId), ['allotted']);

      final summary = await pass(controller);
      expect(summary, isNotNull);
      expect(summary!.reviewedCount, 2);
      expect(summary.duration, const Duration(minutes: 3));
      expect(progress.history.map((entry) => entry.cardId), [
        'allotted',
        'next',
      ]);
      expect(
        progress.schedules['later']!.dueAt,
        now.add(const Duration(days: 3)),
      );
    },
  );

  test(
    'allotted cards finished with no due cards left complete immediately',
    () async {
      final deck = [testCard('only'), testCard('tomorrow')];
      final tomorrow = now.add(const Duration(days: 2));
      final progress = progressFor({
        'only': reviewCard('only'),
        'tomorrow': reviewCard('tomorrow', dueAt: tomorrow),
      });
      final current = now.add(const Duration(minutes: 1));
      final controller = await open(
        progress: progress,
        deck: deck,
        sessionCards: [deck.first],
        clock: () => current,
      );

      final summary = await pass(controller);
      expect(summary, isNotNull);
      expect(controller.isComplete, isTrue);
      expect(summary!.reviewedCount, 1);
      expect(summary.duration, const Duration(minutes: 1));
      expect(progress.history.single.cardId, 'only');
      expect(progress.schedules['tomorrow']!.dueAt, tomorrow);
      expect(progress.schedules['tomorrow']!.reviewCount, 1);
    },
  );

  test(
    'reaching the time goal stops continuation while due cards remain',
    () async {
      final deck = [testCard('first'), testCard('second'), testCard('third')];
      final progress = progressFor({
        'first': reviewCard('first', incorrect: 1),
        'second': reviewCard('second', incorrect: 3),
        'third': reviewCard('third', incorrect: 2),
      });
      await progress.saveDailySessionPlan(
        DailySessionPlan(
          studyDate: DateTime(2026, 9, 2),
          budgetMinutes: 5,
          newKanjiPerDay: 0,
          cardIds: const ['first'],
        ),
      );
      var current = now.add(const Duration(minutes: 3));
      final controller = await open(
        progress: progress,
        deck: deck,
        sessionCards: [deck.first],
        clock: () => current,
      );

      expect(await pass(controller), isNull);
      expect(controller.current?.id, 'second');
      expect(progress.dailySessionPlan.completed, isFalse);
      expect(progress.schedules['third']!.reviewCount, 3);

      current = now.add(goal);
      final summary = await pass(controller);

      expect(summary, isNotNull);
      expect(controller.isComplete, isTrue);
      expect(controller.session.startTime, now);
      expect(summary!.duration, goal);
      expect(summary.reviewedCount, 2);
      expect(progress.history.map((entry) => entry.cardId), [
        'first',
        'second',
      ]);
      expect(progress.schedules['third']!.reviewCount, 3);
      expect(progress.dailySessionPlan.completed, isTrue);

      final workload = await DailyWorkloadService(
        kanjiRepository: FakeKanjiRepository(deck),
        progressRepository: progress,
      ).read(now: current);
      expect(workload.studyAnywayAvailable, isTrue);
      expect(workload.overflowCards.map((card) => card.id), ['third']);
    },
  );

  test(
    'an allotment that already meets the time goal is not extended',
    () async {
      final deck = [testCard('a'), testCard('b'), testCard('extra')];
      final progress = progressFor({
        'a': reviewCard('a'),
        'b': reviewCard('b'),
        'extra': reviewCard('extra', incorrect: 5),
      });
      final current = now.add(goal);
      final controller = await open(
        progress: progress,
        deck: deck,
        sessionCards: [deck[0], deck[1]],
        clock: () => current,
      );

      expect(await pass(controller), isNull);
      expect(controller.current?.id, 'b');
      final summary = await pass(controller);

      expect(summary, isNotNull);
      expect(controller.isComplete, isTrue);
      expect(progress.history.map((entry) => entry.cardId), ['a', 'b']);
      expect(progress.schedules['extra']!.incorrectCount, 5);
      expect(summary!.duration, goal);
    },
  );

  test(
    'several extra cards continue in priority order without duplicates',
    () async {
      final deck = [
        testCard('low'),
        testCard('mid'),
        testCard('high'),
        testCard('top'),
        testCard('future'),
      ];
      final progress = progressFor({
        'low': reviewCard('low', incorrect: 1),
        'mid': reviewCard('mid', incorrect: 2),
        'high': reviewCard('high', incorrect: 4),
        'top': reviewCard('top', incorrect: 8),
        'future': reviewCard(
          'future',
          incorrect: 20,
          dueAt: now.add(const Duration(days: 4)),
        ),
      });
      final workload = DailyWorkloadService(
        kanjiRepository: FakeKanjiRepository(deck),
        progressRepository: progress,
      );
      final ranked = await workload.eligibleByPriority(now: now);
      expect(ranked.map((card) => card.id), ['top', 'high', 'mid', 'low']);

      final allotment = [ranked[2], ranked[3]];
      final controller = await open(
        progress: progress,
        deck: deck,
        sessionCards: allotment,
        clock: () => now.add(const Duration(minutes: 1)),
      );

      final shown = <String>[];
      SessionSummary? summary;
      while (summary == null && shown.length < 8) {
        shown.add(controller.current!.id);
        controller.submit();
        summary = await controller.rate(ReviewResult.good);
      }

      expect(shown, ['mid', 'low', 'top', 'high']);
      expect(shown.toSet(), hasLength(shown.length));
      expect(shown, isNot(contains('future')));
      expect(summary, isNotNull);
    },
  );

  test(
    'a card that becomes ineligible during the session is skipped',
    () async {
      final deck = [testCard('allotted'), testCard('keep'), testCard('drop')];
      final progress = progressFor({
        'allotted': reviewCard('allotted', incorrect: 1),
        'keep': reviewCard('keep', incorrect: 5),
        'drop': reviewCard('drop', incorrect: 3),
      });
      final controller = await open(
        progress: progress,
        deck: deck,
        sessionCards: [deck.first],
        clock: () => now.add(const Duration(minutes: 1)),
      );

      expect(await pass(controller), isNull);
      expect(controller.current?.id, 'keep');
      await progress.saveSchedule(
        reviewCard('drop', dueAt: now.add(const Duration(days: 3))),
      );

      final summary = await pass(controller);
      expect(summary, isNotNull);
      expect(controller.isComplete, isTrue);
      expect(progress.history.map((entry) => entry.cardId), [
        'allotted',
        'keep',
      ]);
      expect(
        progress.schedules['drop']!.dueAt,
        now.add(const Duration(days: 3)),
      );
      expect(progress.schedules['drop']!.reviewCount, 1);
    },
  );

  test(
    'Again keeps the existing requeue and does not pull the next card',
    () async {
      final deck = [testCard('allotted'), testCard('retry'), testCard('after')];
      final progress = progressFor({
        'allotted': reviewCard('allotted', incorrect: 1),
        'retry': reviewCard('retry', incorrect: 6),
        'after': reviewCard('after', incorrect: 3),
      });
      final current = now.add(const Duration(minutes: 1));
      final controller = await open(
        progress: progress,
        deck: deck,
        sessionCards: [deck.first],
        clock: () => current,
      );

      expect(await pass(controller), isNull);
      expect(controller.current?.id, 'retry');
      controller.submit();
      expect(await controller.rate(ReviewResult.again), isNull);
      expect(controller.current?.id, 'retry');
      expect(controller.phase, StudyPhase.recall);

      final retried = progress.schedules['retry']!;
      expect(retried.state, CardLearningState.learning);
      expect(retried.dueAt, current.add(SrsEngine.againInterval));
      expect(retried.incorrectCount, 7);
      expect(progress.schedules['after']!.incorrectCount, 3);
      expect(progress.history.map((entry) => entry.rating), [
        ReviewResult.good,
        ReviewResult.again,
      ]);

      expect(await pass(controller), isNull);
      expect(controller.current?.id, 'after');
      final summary = await pass(controller);
      expect(summary, isNotNull);
      expect(progress.history.map((entry) => entry.cardId), [
        'allotted',
        'retry',
        'retry',
        'after',
      ]);
    },
  );

  test('Study Anyway reviews its own cards and does not auto-extend', () async {
    final deck = [testCard('given'), testCard('also'), testCard('left-out')];
    final progress = progressFor({
      'given': reviewCard('given'),
      'also': reviewCard('also'),
      'left-out': reviewCard('left-out', incorrect: 4),
    });
    final underGoal = await open(
      progress: progress,
      deck: deck,
      sessionCards: [deck[0], deck[1]],
      clock: () => now.add(const Duration(minutes: 1)),
      studyAnyway: true,
    );

    expect(await pass(underGoal), isNull);
    final finished = await pass(underGoal);
    expect(finished, isNotNull);
    expect(underGoal.isComplete, isTrue);
    expect(progress.history.map((entry) => entry.cardId), ['given', 'also']);
    expect(progress.schedules['left-out']!.incorrectCount, 4);

    final pastGoal = await open(
      progress: progressFor({
        'given': reviewCard('given'),
        'also': reviewCard('also'),
      }),
      deck: [deck[0], deck[1]],
      sessionCards: [deck[0], deck[1]],
      clock: () => now.add(const Duration(minutes: 12)),
      studyAnyway: true,
    );
    expect(await pass(pastGoal), isNull);
    final keptGoing = await pass(pastGoal);
    expect(keptGoing, isNotNull);
    expect(pastGoal.session.reviewedCount, 2);
    expect(keptGoing!.duration, const Duration(minutes: 12));
  });

  test('earlier study today counts toward the daily time goal', () async {
    final deck = [testCard('allotted'), testCard('extra')];
    final progress = MemoryProgressRepository(
      settings: const AppSettings(dailyStudyMinutes: 5, newKanjiPerDay: 0),
      schedules: {
        'allotted': reviewCard('allotted'),
        'extra': reviewCard('extra', incorrect: 2),
      },
      dailyReviewTime: DailyReviewTime(
        date: DateTime(2026, 9, 2),
        duration: const Duration(minutes: 4),
      ),
    );
    final current = now.add(const Duration(minutes: 2));
    final controller = await open(
      progress: progress,
      deck: deck,
      sessionCards: [deck.first],
      clock: () => current,
    );

    final summary = await pass(controller);
    expect(summary, isNotNull);
    expect(controller.isComplete, isTrue);
    expect(summary!.duration, const Duration(minutes: 6));
    expect(progress.history.single.cardId, 'allotted');
    expect(progress.schedules['extra']!.incorrectCount, 2);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/kanji_card.dart';
import 'package:fiveminutekanji/core/models/progress.dart';
import 'package:fiveminutekanji/core/models/review.dart';
import 'package:fiveminutekanji/core/models/review_duration.dart';
import 'package:fiveminutekanji/core/models/study_phase.dart';
import 'package:fiveminutekanji/features/review/review_controller.dart';
import 'package:fiveminutekanji/services/card_priority_scorer.dart';
import 'package:fiveminutekanji/services/daily_workload.dart';
import 'package:fiveminutekanji/services/srs_engine.dart';

import 'support/fakes.dart';

void main() {
  final now = DateTime(2026, 9, 2, 8);
  const engine = SrsEngine();
  const scorer = CardPriorityScorer();
  const config = ReviewSessionConfig(
    duration: Duration(minutes: 5),
    maxCards: 20,
  );

  CardSchedule matureCard(String id) {
    return CardSchedule(
      cardId: id,
      state: CardLearningState.review,
      reviewCount: 8,
      correctCount: 8,
      incorrectCount: 0,
      dueAt: now,
      interval: const Duration(days: 40),
      ease: 2.5,
      lastReviewedAt: now.subtract(const Duration(days: 40)),
      consecutiveGoodCount: 8,
    );
  }

  CardSchedule youngCard(String id) {
    return CardSchedule(
      cardId: id,
      state: CardLearningState.learning,
      reviewCount: 2,
      correctCount: 0,
      incorrectCount: 2,
      dueAt: now,
      interval: const Duration(minutes: 1),
      ease: 2.3,
      lastReviewedAt: now.subtract(const Duration(minutes: 1)),
    );
  }

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

  List<KanjiCard> deck(int count) {
    return [
      for (var i = 0; i < count; i++)
        testCard('c${i.toString().padLeft(2, '0')}'),
    ];
  }

  ReviewDurationModel pace({
    int globalMs = 0,
    int globalCount = 0,
    int newMs = 0,
    int newCount = 0,
    int youngMs = 0,
    int youngCount = 0,
    int matureMs = 0,
    int matureCount = 0,
  }) {
    return ReviewDurationModel(
      global: PaceStats(ewmaMs: globalMs, count: globalCount),
      newCards: PaceStats(ewmaMs: newMs, count: newCount),
      young: PaceStats(ewmaMs: youngMs, count: youngCount),
      mature: PaceStats(ewmaMs: matureMs, count: matureCount),
    );
  }

  DailyWorkloadService service(
    MemoryProgressRepository progress,
    List<KanjiCard> cards,
  ) {
    return DailyWorkloadService(
      kanjiRepository: FakeKanjiRepository(cards),
      progressRepository: progress,
    );
  }

  test(
    'a learned pace changes how many priority cards fit the time goal',
    () async {
      final cards = deck(40);
      final schedules = {
        for (final card in cards) card.id: matureCard(card.id),
      };
      final slow = MemoryProgressRepository(
        settings: const AppSettings(dailyStudyMinutes: 5, newKanjiPerDay: 0),
        schedules: schedules,
        reviewDurations: pace(
          globalMs: 30000,
          globalCount: 20,
          matureMs: 30000,
          matureCount: 20,
        ),
      );
      final defaults = MemoryProgressRepository(
        settings: const AppSettings(dailyStudyMinutes: 5, newKanjiPerDay: 0),
        schedules: {for (final card in cards) card.id: matureCard(card.id)},
      );

      final slowPlan = await service(slow, cards).read(now: now);
      final defaultPlan = await service(defaults, cards).read(now: now);

      expect(slowPlan.sessionCards.map((card) => card.id), [
        for (var i = 0; i < 10; i++) 'c${i.toString().padLeft(2, '0')}',
      ]);
      expect(
        defaultPlan.sessionCards.length,
        greaterThan(slowPlan.sessionCards.length),
      );
      expect(defaultPlan.sessionCards.first.id, 'c00');
      expect(slowPlan.sessionCards.first.id, defaultPlan.sessionCards.first.id);
    },
  );

  test(
    'a long high-priority card is kept ahead of shorter lower-priority ones',
    () async {
      final mature = [
        for (var i = 0; i < 20; i++)
          testCard('m${i.toString().padLeft(2, '0')}'),
      ];
      final cards = [testCard('young'), ...mature];
      final schedules = {
        'young': youngCard('young'),
        for (final card in mature) card.id: matureCard(card.id),
      };
      expect(
        scorer.score(schedule: schedules['young'], now: now, isNew: false),
        greaterThan(
          scorer.score(schedule: schedules['m00'], now: now, isNew: false),
        ),
      );

      final progress = MemoryProgressRepository(
        settings: const AppSettings(dailyStudyMinutes: 3, newKanjiPerDay: 0),
        schedules: schedules,
        reviewDurations: pace(
          globalMs: 12000,
          globalCount: 40,
          youngMs: 40000,
          youngCount: 20,
          matureMs: 8000,
          matureCount: 20,
        ),
      );

      final plan = await service(progress, cards).read(now: now);
      final ids = plan.sessionCards.map((card) => card.id).toList();

      expect(ids.first, 'young');
      expect(ids, contains('m00'));
      expect(ids, isNot(contains('m19')));
      expect(ids.length, lessThan(mature.length));
    },
  );

  test(
    'fast new-card estimates still stop at the daily new-card cap',
    () async {
      final news = [for (var i = 0; i < 10; i++) testCard('n$i')];
      final reviews = [for (var i = 0; i < 5; i++) testCard('r$i')];
      final progress = MemoryProgressRepository(
        settings: const AppSettings(dailyStudyMinutes: 30, newKanjiPerDay: 2),
        schedules: {for (final card in reviews) card.id: matureCard(card.id)},
        reviewDurations: pace(
          globalMs: 4000,
          globalCount: 30,
          newMs: 4000,
          newCount: 30,
        ),
      );

      final plan = await service(progress, [
        ...news,
        ...reviews,
      ]).read(now: now);
      final selectedNew = plan.sessionCards.where(
        (card) => card.id.startsWith('n'),
      );

      expect(selectedNew, hasLength(2));
      expect(plan.sessionCards.length, greaterThan(2));
    },
  );

  test('no eligible cards leave the session empty', () async {
    final cards = [testCard('later')];
    final progress = MemoryProgressRepository(
      settings: const AppSettings(dailyStudyMinutes: 5, newKanjiPerDay: 0),
      schedules: {
        'later': matureCard(
          'later',
        ).copyWith(dueAt: now.add(const Duration(days: 3))),
      },
      reviewDurations: pace(
        globalMs: 8000,
        globalCount: 20,
        matureMs: 8000,
        matureCount: 20,
      ),
    );

    final plan = await service(progress, cards).read(now: now);

    expect(plan.sessionCards, isEmpty);
    expect(plan.dueCount, 0);
    expect(plan.recommendedComplete, isFalse);
    expect(plan.remainingCount, 0);
  });

  test(
    'continuation follows the clock and priority, not the pace model',
    () async {
      final cards = [testCard('allotted'), testCard('next'), testCard('later')];
      final progress = MemoryProgressRepository(
        settings: const AppSettings(dailyStudyMinutes: 5, newKanjiPerDay: 0),
        schedules: {
          'allotted': dueReview('allotted'),
          'next': dueReview('next'),
          'later': dueReview(
            'later',
          ).copyWith(dueAt: now.add(const Duration(days: 3))),
        },
        reviewDurations: pace(
          globalMs: 90000,
          globalCount: 20,
          youngMs: 90000,
          youngCount: 20,
        ),
      );
      var current = now;
      final beforeNext = progress.schedules['next']!.toJson();
      final controller = ReviewController(
        progressRepository: progress,
        srsEngine: engine,
        cards: [cards.first],
        config: config,
        startTime: now,
        clock: () => current,
        schedules: Map<String, CardSchedule>.from(progress.schedules),
        workloadService: service(progress, cards),
      );

      current = now.add(const Duration(seconds: 12));
      controller.submit();
      expect(await controller.rate(ReviewResult.good), isNull);

      expect(controller.current?.id, 'next');
      expect(controller.session.startTime, now);
      expect(
        controller.reviewClock.totalAt(current),
        const Duration(seconds: 12),
      );
      expect(progress.schedules['next']!.toJson(), beforeNext);
      expect(progress.reviewDurations.young.count, 21);
      expect(progress.history.single.timeOnCard, const Duration(seconds: 12));

      current = now.add(const Duration(minutes: 5));
      controller.submit();
      final summary = await controller.rate(ReviewResult.good);

      expect(summary, isNotNull);
      expect(controller.isComplete, isTrue);
      expect(summary!.duration, const Duration(minutes: 5));
      expect(summary.reviewedCount, 2);
      expect(progress.history.map((entry) => entry.cardId), [
        'allotted',
        'next',
      ]);
      expect(
        progress.schedules['later']!.dueAt,
        now.add(const Duration(days: 3)),
      );
      expect(
        progress.schedules['later']!.reviewCount,
        dueReview('later').reviewCount,
      );
      expect(controller.session.startTime, now);
      expect(progress.reviewDurations.young.count, 21);
    },
  );

  test('reaching the goal with nothing left still ends the sitting', () async {
    final cards = [testCard('only'), testCard('tomorrow')];
    final tomorrow = now.add(const Duration(days: 2));
    final progress = MemoryProgressRepository(
      settings: const AppSettings(dailyStudyMinutes: 5, newKanjiPerDay: 0),
      schedules: {
        'only': dueReview('only'),
        'tomorrow': dueReview('tomorrow').copyWith(dueAt: tomorrow),
      },
    );
    var current = now;
    final controller = ReviewController(
      progressRepository: progress,
      srsEngine: engine,
      cards: [cards.first],
      config: config,
      startTime: now,
      clock: () => current,
      schedules: Map<String, CardSchedule>.from(progress.schedules),
      workloadService: service(progress, cards),
    );

    current = now.add(const Duration(seconds: 15));
    controller.submit();
    final summary = await controller.rate(ReviewResult.good);

    expect(summary, isNotNull);
    expect(controller.isComplete, isTrue);
    expect(progress.history.single.cardId, 'only');
    expect(progress.schedules['tomorrow']!.dueAt, tomorrow);
    expect(progress.schedules['tomorrow']!.reviewCount, 1);
    expect(progress.reviewDurations.young.count, 1);
  });

  test(
    'a finished review records its pace without changing SRS timing',
    () async {
      final progress = MemoryProgressRepository();
      await progress.seedIfNeeded(const ['a'], now: now);
      await progress.saveSchedule(matureCard('a'));
      final before = (await progress.getSchedule('a'))!;
      var current = now;
      final controller = ReviewController(
        progressRepository: progress,
        srsEngine: engine,
        cards: [testCard('a')],
        config: config,
        startTime: now,
        clock: () => current,
        schedules: {'a': before},
      );

      current = now.add(const Duration(seconds: 15));
      expect(controller.phase, StudyPhase.recall);
      controller.submit();
      await controller.rate(ReviewResult.good);

      final after = (await progress.getSchedule('a'))!;
      final expected = engine.schedule(
        current: before,
        result: ReviewResult.good,
        now: current,
      );
      expect(after.dueAt, expected.dueAt);
      expect(after.interval, expected.interval);
      expect(after.reviewCount, expected.reviewCount);
      expect(after.lastReviewedAt, expected.lastReviewedAt);
      expect(after.state, expected.state);
      expect(progress.reviewDurations.mature.count, 1);
      expect(progress.reviewDurations.young.count, 0);
      expect(progress.history.single.timeOnCard, const Duration(seconds: 15));
      expect(
        controller.reviewClock.totalAt(current),
        const Duration(seconds: 15),
      );
      expect(progress.history, hasLength(1));
    },
  );

  test(
    'each card keeps its own active time and the session clock keeps running',
    () async {
      final progress = MemoryProgressRepository(
        schedules: {'a': dueReview('a'), 'b': dueReview('b')},
      );
      var current = now;
      final controller = ReviewController(
        progressRepository: progress,
        srsEngine: engine,
        cards: [testCard('a'), testCard('b')],
        config: config,
        startTime: now,
        clock: () => current,
        schedules: Map<String, CardSchedule>.from(progress.schedules),
      );

      current = now.add(const Duration(seconds: 10));
      controller.submit();
      expect(await controller.rate(ReviewResult.good), isNull);
      expect(controller.current?.id, 'b');

      current = now.add(const Duration(seconds: 25));
      controller.submit();
      final summary = await controller.rate(ReviewResult.good);

      expect(progress.history.map((entry) => entry.timeOnCard), [
        const Duration(seconds: 10),
        const Duration(seconds: 15),
      ]);
      expect(summary!.duration, const Duration(seconds: 25));
      expect(controller.session.startTime, now);
      expect(progress.reviewDurations.young.count, 2);
      expect(progress.reviewDurations.global.count, 2);
    },
  );

  test('time in the background is not learned as card time', () async {
    final progress = MemoryProgressRepository(schedules: {'a': dueReview('a')});
    var current = now;
    final controller = ReviewController(
      progressRepository: progress,
      srsEngine: engine,
      cards: [testCard('a')],
      config: config,
      startTime: now,
      clock: () => current,
      schedules: {'a': dueReview('a')},
    );

    current = now.add(const Duration(seconds: 10));
    controller.pauseReviewTime();
    current = now.add(const Duration(minutes: 5, seconds: 10));
    controller.resumeReviewTime();
    current = now.add(const Duration(minutes: 5, seconds: 18));
    controller.submit();
    final summary = await controller.rate(ReviewResult.good);

    expect(progress.history.single.timeOnCard, const Duration(seconds: 18));
    expect(summary!.duration, const Duration(seconds: 18));
    expect(progress.reviewDurations.young.count, 1);
    expect(progress.reviewDurations.young.ewmaMs, lessThan(30000));
  });

  test('a new introduction is timed separately from later reviews', () async {
    final progress = MemoryProgressRepository();
    await progress.seedIfNeeded(const ['a'], now: now);
    var current = now;
    final controller = ReviewController(
      progressRepository: progress,
      srsEngine: engine,
      cards: [testCard('a')],
      config: config,
      startTime: now,
      clock: () => current,
      schedules: Map<String, CardSchedule>.from(progress.schedules),
    );

    expect(controller.phase, StudyPhase.learn);
    current = now.add(const Duration(seconds: 30));
    controller.beginPractice();
    await controller.completePractice();

    final schedule = (await progress.getSchedule('a'))!;
    expect(schedule.state, CardLearningState.learning);
    expect(schedule.interval, SrsEngine.newLearnInterval);
    expect(schedule.dueAt, current.add(SrsEngine.newLearnInterval));
    expect(schedule.reviewCount, 0);
    expect(progress.history, isEmpty);
    expect(progress.reviewDurations.newCards.count, 1);
    expect(progress.reviewDurations.young.count, 0);
    expect(progress.reviewDurations.mature.count, 0);
  });

  test(
    'mark as known, practice, and abandoned cards do not train the model',
    () async {
      final known = MemoryProgressRepository();
      await known.seedIfNeeded(const ['a'], now: now);
      var current = now;
      final knownController = ReviewController(
        progressRepository: known,
        srsEngine: engine,
        cards: [testCard('a')],
        config: config,
        startTime: now,
        clock: () => current,
        schedules: Map<String, CardSchedule>.from(known.schedules),
      );
      current = now.add(const Duration(seconds: 40));
      await knownController.markCurrentAsKnown();
      expect(known.reviewDurations, ReviewDurationModel.empty);
      expect((await known.getSchedule('a'))!.state, CardLearningState.review);

      final practice = MemoryProgressRepository();
      await practice.seedIfNeeded(const ['b'], now: now);
      current = now;
      final practiceController = ReviewController(
        progressRepository: practice,
        srsEngine: engine,
        cards: [testCard('b')],
        config: config,
        isPractice: true,
        startTime: now,
        clock: () => current,
        schedules: Map<String, CardSchedule>.from(practice.schedules),
      );
      current = now.add(const Duration(seconds: 20));
      practiceController.beginPractice();
      await practiceController.completePractice();
      practiceController.submit();
      await practiceController.rate(ReviewResult.good);
      expect(practice.reviewDurations, ReviewDurationModel.empty);
      expect(practice.history.single.isPractice, isTrue);
      expect(
        (await practice.getSchedule('b'))!.state,
        CardLearningState.newCard,
      );

      final abandoned = MemoryProgressRepository(
        schedules: {'c': dueReview('c')},
      );
      current = now;
      final abandonedController = ReviewController(
        progressRepository: abandoned,
        srsEngine: engine,
        cards: [testCard('c')],
        config: config,
        startTime: now,
        clock: () => current,
        schedules: {'c': dueReview('c')},
      );
      current = now.add(const Duration(minutes: 2));
      abandonedController.pauseReviewTime();
      await abandonedController.checkpointReviewTime();
      expect(abandoned.reviewDurations, ReviewDurationModel.empty);
      expect((await abandoned.getSchedule('c'))!.reviewCount, 1);
      expect(abandoned.history, isEmpty);
    },
  );

  test(
    'a zero-length review updates SRS and leaves the pace model alone',
    () async {
      final progress = MemoryProgressRepository(
        schedules: {'a': dueReview('a')},
      );
      final before = progress.schedules['a']!;
      final controller = ReviewController(
        progressRepository: progress,
        srsEngine: engine,
        cards: [testCard('a')],
        config: config,
        startTime: now,
        clock: () => now,
        schedules: {'a': before},
      );

      controller.submit();
      await controller.rate(ReviewResult.again);

      final after = (await progress.getSchedule('a'))!;
      final expected = engine.schedule(
        current: before,
        result: ReviewResult.again,
        now: now,
      );
      expect(after.dueAt, expected.dueAt);
      expect(after.interval, expected.interval);
      expect(after.incorrectCount, expected.incorrectCount);
      expect(progress.reviewDurations, ReviewDurationModel.empty);
      expect(progress.history.single.timeOnCard, Duration.zero);
    },
  );
}

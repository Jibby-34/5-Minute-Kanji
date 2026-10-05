import 'package:flutter_test/flutter_test.dart';
import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/daily_session_plan.dart';
import 'package:fiveminutekanji/core/models/kanji_card.dart';
import 'package:fiveminutekanji/core/models/progress.dart';
import 'package:fiveminutekanji/core/models/review.dart';
import 'package:fiveminutekanji/core/models/start_of_day.dart';
import 'package:fiveminutekanji/services/card_priority_scorer.dart';
import 'package:fiveminutekanji/services/card_time_estimator.dart';
import 'package:fiveminutekanji/services/daily_workload.dart';
import 'package:fiveminutekanji/services/session_planner.dart';
import 'package:fiveminutekanji/services/srs_engine.dart';

import 'support/fakes.dart';

void main() {
  final now = DateTime(2026, 9, 2, 8);
  const scorer = CardPriorityScorer();
  const estimator = CardTimeEstimator();
  const planner = SessionPlanner();

  CardSchedule reviewCard(
    String id, {
    DateTime? dueAt,
    Duration interval = const Duration(days: 1),
    int incorrect = 0,
    int consecutive = 1,
    CardLearningState state = CardLearningState.review,
    DateTime? lastReviewedAt,
  }) {
    return CardSchedule(
      cardId: id,
      state: state,
      reviewCount: incorrect + consecutive,
      correctCount: consecutive,
      incorrectCount: incorrect,
      dueAt: dueAt ?? now,
      interval: interval,
      ease: 2.5,
      lastReviewedAt: lastReviewedAt ?? now.subtract(interval),
      consecutiveGoodCount: consecutive,
    );
  }

  SessionCandidate candidate({
    required String id,
    required double priority,
    required Duration estimated,
    bool isNew = false,
  }) {
    return SessionCandidate(
      card: testCard(id),
      priority: priority,
      estimated: estimated,
      isNew: isNew,
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

  List<KanjiCard> deck(int count, {String prefix = 'c'}) {
    return [
      for (var i = 0; i < count; i++)
        testCard('$prefix${i.toString().padLeft(2, '0')}'),
    ];
  }

  test('a 5-minute budget selects fewer cards than a 15-minute budget', () {
    final cards = [
      for (var i = 0; i < 30; i++)
        candidate(
          id: 'c${i.toString().padLeft(2, '0')}',
          priority: 30 - i.toDouble(),
          estimated: const Duration(seconds: 20),
        ),
    ];

    final five = planner.plan(
      candidates: cards,
      budget: const Duration(minutes: 5),
      maxNewCards: 0,
    );
    final fifteen = planner.plan(
      candidates: cards,
      budget: const Duration(minutes: 15),
      maxNewCards: 0,
    );

    expect(five.selected.length, lessThan(fifteen.selected.length));
    expect(five.selected.length, 15);
    expect(fifteen.selected.length, 30);
  });

  test('higher-priority cards are selected before lower-priority ones', () {
    final failing = candidate(
      id: 'fail',
      priority: 4,
      estimated: const Duration(seconds: 24),
    );
    final steady = candidate(
      id: 'steady',
      priority: 1.2,
      estimated: const Duration(seconds: 20),
    );
    final stable = candidate(
      id: 'stable',
      priority: 0.2,
      estimated: const Duration(seconds: 14),
    );

    final plan = planner.plan(
      candidates: [stable, failing, steady],
      budget: const Duration(seconds: 30),
      maxNewCards: 0,
    );

    expect(plan.selected.map((item) => item.card.id), ['fail']);
    expect(plan.overflow.map((item) => item.card.id), ['steady', 'stable']);
  });

  test('selected cards fit approximately within the configured time', () {
    final cards = [
      for (var i = 0; i < 40; i++)
        candidate(
          id: 'c$i',
          priority: 40 - i.toDouble(),
          estimated: const Duration(seconds: 20),
        ),
    ];
    const budget = Duration(minutes: 5);
    final plan = planner.plan(
      candidates: cards,
      budget: budget,
      maxNewCards: 0,
    );

    final upper = (budget.inSeconds * planner.upperTolerance).round();
    expect(plan.estimated.inSeconds, lessThanOrEqualTo(upper));
    expect(plan.estimated.inSeconds, greaterThan(budget.inSeconds - 30));
  });

  test(
    'cards that do not fit are kept for Study Anyway, in priority order',
    () {
      final cards = [
        candidate(id: 'a', priority: 1, estimated: const Duration(seconds: 20)),
        candidate(id: 'b', priority: 3, estimated: const Duration(seconds: 20)),
        candidate(id: 'c', priority: 2, estimated: const Duration(seconds: 20)),
      ];
      final plan = planner.plan(
        candidates: cards,
        budget: const Duration(seconds: 25),
        maxNewCards: 0,
      );

      expect(plan.selected.map((item) => item.card.id), ['b']);
      expect(plan.overflow.map((item) => item.card.id), ['c', 'a']);
    },
  );

  test('a single important card longer than the budget is still included', () {
    final long = candidate(
      id: 'long',
      priority: 5,
      estimated: const Duration(minutes: 10),
    );
    final rest = [
      for (var i = 0; i < 4; i++)
        candidate(
          id: 's$i',
          priority: 1,
          estimated: const Duration(seconds: 20),
        ),
    ];

    final plan = planner.plan(
      candidates: [...rest, long],
      budget: const Duration(minutes: 5),
      maxNewCards: 0,
    );

    expect(plan.selected.map((item) => item.card.id), ['long']);
    expect(plan.overflow, hasLength(4));
  });

  test(
    'one or two short cards are kept even when they do not fill the time',
    () {
      final plan = planner.plan(
        candidates: [
          candidate(
            id: 'only',
            priority: 1,
            estimated: const Duration(seconds: 20),
          ),
        ],
        budget: const Duration(minutes: 30),
        maxNewCards: 0,
      );

      expect(plan.selected.single.card.id, 'only');
      expect(plan.overflow, isEmpty);
    },
  );

  test('new-card limits stay in force even when the time budget is large', () {
    final news = [
      for (var i = 0; i < 6; i++)
        candidate(
          id: 'n$i',
          priority: 1,
          estimated: const Duration(seconds: 30),
          isNew: true,
        ),
    ];

    final plan = planner.plan(
      candidates: news,
      budget: const Duration(minutes: 30),
      maxNewCards: 2,
    );

    expect(plan.selected.map((item) => item.card.id).toList(), ['n0', 'n1']);
    expect(plan.overflow, isEmpty);
  });

  test('Again ranks above Good for the same card', () {
    final base = reviewCard('k');
    const engine = SrsEngine();
    final again = engine.schedule(
      current: base,
      result: ReviewResult.again,
      now: now,
    );
    final good = engine.schedule(
      current: base,
      result: ReviewResult.good,
      now: now,
    );

    final againScore = scorer.score(schedule: again, now: now, isNew: false);
    final goodScore = scorer.score(schedule: good, now: now, isNew: false);
    expect(againScore, greaterThan(goodScore));
  });

  test('a recent failure outranks a stable card that is also available', () {
    final failed = reviewCard(
      'fail',
      state: CardLearningState.learning,
      interval: const Duration(minutes: 1),
      incorrect: 2,
      consecutive: 0,
      lastReviewedAt: now.subtract(const Duration(minutes: 5)),
    );
    final stable = reviewCard(
      'stable',
      interval: const Duration(days: 60),
      consecutive: 8,
      dueAt: now.add(const Duration(hours: 2)),
      lastReviewedAt: now.subtract(const Duration(days: 3)),
    );

    expect(
      scorer.score(schedule: failed, now: now, isNew: false),
      greaterThan(scorer.score(schedule: stable, now: now, isNew: false)),
    );
  });

  test('missing days do not grow the session past the time budget', () async {
    final cards = deck(40);
    final progress = MemoryProgressRepository(
      settings: const AppSettings(dailyStudyMinutes: 5, newKanjiPerDay: 0),
      schedules: {
        for (final card in cards)
          card.id: reviewCard(
            card.id,
            dueAt: now.subtract(const Duration(days: 3)),
            incorrect: int.parse(card.id.substring(1)),
          ),
      },
    );

    final monday = await service(progress, cards).read(now: now);
    expect(monday.sessionCards.length, lessThan(20));
    expect(monday.estimatedMinutes, lessThanOrEqualTo(6));
    expect(monday.studyAnywayAvailable, isFalse);

    final tuesday = await service(
      progress,
      cards,
    ).read(now: now.add(const Duration(days: 1)));
    expect(tuesday.sessionCards.length, monday.sessionCards.length);
    expect(tuesday.estimatedMinutes, lessThanOrEqualTo(6));
  });

  test('changing daily study time recalculates the next session', () async {
    final cards = deck(40);
    final progress = MemoryProgressRepository(
      settings: const AppSettings(dailyStudyMinutes: 5, newKanjiPerDay: 0),
      schedules: {for (final card in cards) card.id: reviewCard(card.id)},
    );
    final before = {
      for (final card in cards) card.id: progress.schedules[card.id]!.dueAt,
    };

    final short = await service(progress, cards).read(now: now);
    await progress.saveSettings(
      const AppSettings(dailyStudyMinutes: 15, newKanjiPerDay: 0),
    );
    final longer = await service(progress, cards).read(now: now);

    expect(short.sessionCards.length, lessThan(longer.sessionCards.length));
    for (final card in cards) {
      expect(progress.schedules[card.id]!.dueAt, before[card.id]);
      expect(progress.schedules[card.id]!.state, CardLearningState.review);
    }
  });

  test('changing start of day rebuilds who is eligible today', () async {
    final evening = DateTime(2026, 9, 8, 20);
    final cards = [testCard('soon'), testCard('later')];
    final progress = MemoryProgressRepository(
      settings: const AppSettings(
        dailyStudyMinutes: 5,
        newKanjiPerDay: 0,
        startOfDay: StartOfDay(hour: 4),
      ),
      schedules: {
        'soon': reviewCard(
          'soon',
          dueAt: DateTime(2026, 9, 9, 3, 30),
          lastReviewedAt: evening.subtract(const Duration(hours: 6)),
        ),
        'later': reviewCard(
          'later',
          dueAt: DateTime(2026, 9, 10, 8),
          lastReviewedAt: evening,
        ),
      },
    );

    final first = await service(progress, cards).read(now: evening);
    expect(first.sessionCards.map((card) => card.id), ['soon']);

    await progress.saveSettings(
      const AppSettings(
        dailyStudyMinutes: 5,
        newKanjiPerDay: 0,
        startOfDay: StartOfDay(hour: 3),
      ),
    );
    final second = await service(progress, cards).read(now: evening);
    expect(second.sessionCards, isEmpty);
    expect(second.studyAnywayAvailable, isFalse);
    expect(progress.schedules['soon']!.dueAt, DateTime(2026, 9, 9, 3, 30));
  });

  test(
    'the daily new-card limit caps both the session and Study Anyway',
    () async {
      final cards = [for (var i = 0; i < 6; i++) testCard('n$i')];
      final progress = MemoryProgressRepository(
        settings: const AppSettings(dailyStudyMinutes: 30, newKanjiPerDay: 2),
        schedules: {
          for (final card in cards) card.id: CardSchedule.fresh(card.id, now),
        },
      );

      final workload = await service(progress, cards).read(now: now);
      expect(workload.sessionCards.map((card) => card.id), ['n0', 'n1']);

      await progress.saveDailySessionPlan(
        progress.dailySessionPlan.copyWith(completed: true),
      );
      final done = await service(progress, cards).read(now: now);
      expect(done.recommendedComplete, isTrue);
      expect(done.remainingCount, 0);
      expect(done.overflowCards.map((card) => card.id), ['n0', 'n1']);
      expect(done.studyAnywayAvailable, isTrue);
    },
  );

  test(
    'future cards stay out of the session and out of Study Anyway',
    () async {
      final tomorrow = now.add(const Duration(days: 2));
      final cards = [testCard('due'), testCard('future'), testCard('fresh')];
      final progress = MemoryProgressRepository(
        settings: const AppSettings(newKanjiPerDay: 0),
        schedules: {
          'due': reviewCard('due'),
          'future': reviewCard('future', dueAt: tomorrow),
          'fresh': CardSchedule.fresh('fresh', now),
        },
      );

      final workload = await service(progress, cards).read(now: now);
      expect(workload.sessionCards.map((card) => card.id), ['due']);

      await progress.saveDailySessionPlan(
        progress.dailySessionPlan.copyWith(completed: true),
      );
      final done = await service(progress, cards).read(now: now);
      expect(done.overflowCards.map((card) => card.id), ['due']);
      expect(done.sessionCards, isEmpty);
    },
  );

  test(
    'leaving a card out of the session does not change its SRS state',
    () async {
      final cards = deck(20);
      final progress = MemoryProgressRepository(
        settings: const AppSettings(dailyStudyMinutes: 5, newKanjiPerDay: 0),
        schedules: {
          for (final card in cards)
            card.id: reviewCard(
              card.id,
              incorrect: int.parse(card.id.substring(1)),
            ),
        },
      );
      final before = {
        for (final entry in progress.schedules.entries)
          entry.key: entry.value.toJson(),
      };

      final workload = await service(progress, cards).read(now: now);
      expect(workload.sessionCards.length, lessThan(cards.length));

      for (final card in cards) {
        expect(progress.schedules[card.id]!.toJson(), before[card.id]);
      }
    },
  );

  test('finishing the planned session leaves the rest optional', () async {
    final cards = deck(20);
    final progress = MemoryProgressRepository(
      settings: const AppSettings(dailyStudyMinutes: 5, newKanjiPerDay: 0),
      schedules: {
        for (final card in cards)
          card.id: reviewCard(
            card.id,
            incorrect: int.parse(card.id.substring(1)),
          ),
      },
    );

    final planned = await service(progress, cards).read(now: now);
    final selected = planned.sessionCards.map((card) => card.id).toSet();
    expect(selected, isNotEmpty);
    expect(planned.studyAnywayAvailable, isFalse);

    for (final id in selected) {
      progress.schedules[id] = reviewCard(
        id,
        dueAt: now.add(const Duration(days: 4)),
      );
    }
    await progress.saveDailySessionPlan(
      progress.dailySessionPlan.copyWith(completed: true),
    );

    final done = await service(progress, cards).read(now: now);
    expect(done.recommendedComplete, isTrue);
    expect(done.remainingCount, 0);
    expect(done.sessionCards, isEmpty);
    expect(done.studyAnywayAvailable, isTrue);
    expect(
      done.overflowCards.map((card) => card.id),
      isNot(containsAll(selected)),
    );

    final scores = [
      for (final card in done.overflowCards)
        scorer.score(
          schedule: progress.schedules[card.id],
          now: now,
          isNew: false,
        ),
    ];
    for (var i = 1; i < scores.length; i++) {
      expect(scores[i], lessThanOrEqualTo(scores[i - 1]));
    }
  });

  test('no eligible cards means no Study Anyway session', () async {
    final later = now.add(const Duration(days: 3));
    final cards = [testCard('a'), testCard('b')];
    final progress = MemoryProgressRepository(
      schedules: {
        'a': reviewCard('a', dueAt: later),
        'b': reviewCard('b', dueAt: later),
      },
    );

    final workload = await service(progress, cards).read(now: now);
    expect(workload.sessionCards, isEmpty);
    expect(workload.overflowCards, isEmpty);
    expect(workload.studyAnywayAvailable, isFalse);
    expect(workload.remainingCount, 0);
  });

  test('a restarted app keeps the same planned cards', () async {
    final cards = deck(12);
    final progress = MemoryProgressRepository(
      settings: const AppSettings(newKanjiPerDay: 0),
      schedules: {for (final card in cards) card.id: reviewCard(card.id)},
    );
    final first = await service(progress, cards).read(now: now);
    final second = await service(progress, cards).read(now: now);

    expect(
      second.sessionCards.map((card) => card.id),
      first.sessionCards.map((card) => card.id),
    );
    expect(progress.dailySessionPlan.completed, isFalse);
  });

  test(
    'quitting halfway keeps the unfinished plan instead of refilling it',
    () async {
      final cards = deck(20);
      final progress = MemoryProgressRepository(
        settings: const AppSettings(dailyStudyMinutes: 5, newKanjiPerDay: 0),
        schedules: {for (final card in cards) card.id: reviewCard(card.id)},
      );
      final planned = await service(progress, cards).read(now: now);
      final finished = planned.sessionCards.first.id;
      progress.schedules[finished] = reviewCard(
        finished,
        dueAt: now.add(const Duration(days: 2)),
      );

      final resumed = await service(progress, cards).read(now: now);
      expect(
        resumed.sessionCards.map((card) => card.id),
        isNot(contains(finished)),
      );
      expect(resumed.sessionCards.length, planned.sessionCards.length - 1);
      expect(resumed.recommendedComplete, isFalse);
      expect(resumed.studyAnywayAvailable, isFalse);
    },
  );

  test('a legacy new-kanji allowance migrates back to a study time', () {
    final fromGoal = AppSettings.fromJson({'newKanjiPerDay': 4});
    expect(fromGoal.dailyStudyMinutes, 5);

    final explicit = AppSettings.fromJson({
      'newKanjiPerDay': 4,
      'dailyStudyMinutes': 20,
    });
    expect(explicit.dailyStudyMinutes, 20);
    expect(const AppSettings().dailyStudyMinutes, 5);
  });

  test('time estimates stay on the estimator, not in the planner', () {
    final fresh = CardSchedule.fresh('n', now);
    final learning = reviewCard(
      'l',
      state: CardLearningState.learning,
      interval: const Duration(minutes: 10),
    );
    final mature = reviewCard('m', interval: const Duration(days: 40));

    expect(
      estimator.estimate(fresh, isNew: true),
      greaterThan(estimator.estimate(learning, isNew: false)),
    );
    expect(
      estimator.estimate(learning, isNew: false),
      greaterThan(estimator.estimate(mature, isNew: false)),
    );
  });

  test(
    'an empty stored plan is not treated as a finished day with overflow',
    () {
      const plan = DailySessionPlan();
      expect(
        plan.matches(
          studyDate: now,
          budgetMinutes: 5,
          newKanjiPerDay: 5,
          startOfDay: StartOfDay.defaults,
        ),
        isFalse,
      );
    },
  );
}

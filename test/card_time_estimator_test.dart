import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/review_duration.dart';
import 'package:fiveminutekanji/data/shared_prefs_progress_repository.dart';
import 'package:fiveminutekanji/services/active_duration_timer.dart';
import 'package:fiveminutekanji/services/card_time_estimator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 2, 8);
  const estimator = CardTimeEstimator();

  CardSchedule learning() {
    return CardSchedule(
      cardId: 'learning',
      state: CardLearningState.learning,
      reviewCount: 1,
      correctCount: 0,
      incorrectCount: 1,
      dueAt: now,
      interval: const Duration(minutes: 10),
      ease: 2.3,
      lastReviewedAt: now.subtract(const Duration(minutes: 10)),
    );
  }

  CardSchedule youngReview() {
    return CardSchedule(
      cardId: 'young',
      state: CardLearningState.review,
      reviewCount: 2,
      correctCount: 2,
      incorrectCount: 0,
      dueAt: now,
      interval: const Duration(days: 1),
      ease: 2.5,
      lastReviewedAt: now.subtract(const Duration(days: 1)),
      consecutiveGoodCount: 2,
    );
  }

  CardSchedule mature() {
    return CardSchedule(
      cardId: 'mature',
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

  ReviewDurationModel observe(
    ReviewDurationModel model,
    Duration duration, {
    CardSchedule? schedule,
    bool isNew = false,
    int times = 1,
  }) {
    var current = model;
    for (var i = 0; i < times; i++) {
      final next = estimator.learn(
        current,
        schedule: schedule,
        isNew: isNew,
        duration: duration,
      );
      expect(next, isNotNull);
      current = next!;
    }
    return current;
  }

  CardTimeEstimator trained(ReviewDurationModel model) {
    return estimator.withModel(model);
  }

  test('no history keeps the fixed paces', () {
    final fresh = CardSchedule.fresh('n', now);
    expect(estimator.estimate(fresh, isNew: true), const Duration(seconds: 21));
    expect(
      estimator.estimate(learning(), isNew: false),
      const Duration(seconds: 17),
    );
    expect(
      estimator.estimate(youngReview(), isNew: false),
      const Duration(seconds: 14),
    );
    expect(
      estimator.estimate(mature(), isNew: false),
      const Duration(seconds: 10),
    );
    expect(estimator.model, ReviewDurationModel.empty);
  });

  test('new, young, and mature cards use different paces', () {
    expect(
      estimator.paceFor(CardSchedule.fresh('n', now), isNew: true),
      ReviewPace.newCard,
    );
    expect(estimator.paceFor(learning(), isNew: false), ReviewPace.young);
    expect(estimator.paceFor(youngReview(), isNew: false), ReviewPace.young);
    expect(estimator.paceFor(mature(), isNew: false), ReviewPace.mature);

    final model = observe(
      observe(
        observe(
          ReviewDurationModel.empty,
          const Duration(seconds: 40),
          isNew: true,
          times: 12,
        ),
        const Duration(seconds: 20),
        schedule: youngReview(),
        times: 12,
      ),
      const Duration(seconds: 8),
      schedule: mature(),
      times: 12,
    );
    final paced = trained(model);

    expect(
      paced.estimate(CardSchedule.fresh('n', now), isNew: true).inSeconds,
      inInclusiveRange(36, 44),
    );
    expect(
      paced.estimate(learning(), isNew: false).inSeconds,
      inInclusiveRange(18, 22),
    );
    expect(
      paced.estimate(youngReview(), isNew: false).inSeconds,
      inInclusiveRange(18, 22),
    );
    expect(
      paced.estimate(mature(), isNew: false).inSeconds,
      inInclusiveRange(7, 10),
    );
  });

  test('a pace with no samples keeps its default beside other history', () {
    final model = observe(
      ReviewDurationModel.empty,
      const Duration(seconds: 8),
      schedule: mature(),
      times: 12,
    );
    final paced = trained(model);

    expect(
      paced.estimate(CardSchedule.fresh('n', now), isNew: true),
      const Duration(seconds: 21),
    );
    expect(
      paced.estimate(learning(), isNew: false),
      const Duration(seconds: 17),
    );
    expect(
      paced.estimate(youngReview(), isNew: false),
      const Duration(seconds: 14),
    );
    expect(paced.estimate(mature(), isNew: false).inSeconds, lessThan(10));
  });

  test('a handful of samples cannot jump to an extreme pace', () {
    final model = observe(
      ReviewDurationModel.empty,
      const Duration(seconds: 60),
      schedule: youngReview(),
      times: 2,
    );
    final paced = trained(model);
    final young = paced.estimate(youngReview(), isNew: false).inSeconds;
    final learningPace = paced.estimate(learning(), isNew: false).inSeconds;

    expect(young, inInclusiveRange(14, 25));
    expect(learningPace, inInclusiveRange(16, 28));
    expect(young, lessThan(40));
    expect(model.young.count, 2);
  });

  test('one very long or very short review barely moves the estimate', () {
    final slow = trained(
      observe(
        ReviewDurationModel.empty,
        const Duration(seconds: 180),
        schedule: mature(),
      ),
    );
    final fast = trained(
      observe(
        ReviewDurationModel.empty,
        const Duration(seconds: 1),
        schedule: mature(),
      ),
    );

    expect(
      slow.estimate(mature(), isNew: false).inSeconds,
      inInclusiveRange(10, 12),
    );
    expect(
      fast.estimate(mature(), isNew: false).inSeconds,
      inInclusiveRange(8, 10),
    );
  });

  test('enough similar reviews settle on that pace', () {
    final model = observe(
      ReviewDurationModel.empty,
      const Duration(seconds: 20),
      schedule: mature(),
      times: 12,
    );

    expect(
      trained(model).estimate(mature(), isNew: false).inSeconds,
      inInclusiveRange(18, 22),
    );
    expect(model.mature.count, 12);
    expect(model.global.count, 12);
    expect(model.newCards.count, 0);
    expect(model.young.count, 0);
  });

  test('invalid durations leave the model untouched', () {
    const original = ReviewDurationModel.empty;
    for (final duration in [
      Duration.zero,
      const Duration(milliseconds: -1),
      const Duration(milliseconds: 999),
      const Duration(seconds: 181),
      const Duration(minutes: 30),
    ]) {
      expect(
        estimator.learn(
          original,
          schedule: mature(),
          isNew: false,
          duration: duration,
        ),
        isNull,
      );
    }
  });

  test('a corrupt stored pace is ignored instead of trusted', () {
    expect(PaceStats.fromJson({'count': 40, 'ewmaMs': -5}), PaceStats.empty);
    expect(
      PaceStats.fromJson({
        'count': 40,
        'ewmaMs': const Duration(hours: 2).inMilliseconds,
      }),
      PaceStats.empty,
    );
    expect(ReviewDurationModel.fromJson(null), ReviewDurationModel.empty);
  });

  test(
    'learned paces survive a new repository without touching SRS state',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final first = SharedPrefsProgressRepository(prefs);
      await first.seedIfNeeded(const ['rtk_001'], now: now);
      final schedule = (await first.getSchedule('rtk_001'))!;
      final learned = observe(
        ReviewDurationModel.empty,
        const Duration(seconds: 20),
        schedule: mature(),
        times: 12,
      );
      await first.saveReviewDurationModel(learned);

      final restarted = SharedPrefsProgressRepository(prefs);
      final loaded = await restarted.getReviewDurationModel();
      final kept = await restarted.getSchedule('rtk_001');

      expect(loaded.mature.count, learned.mature.count);
      expect(loaded.mature.ewmaMs, learned.mature.ewmaMs);
      expect(loaded.global.count, learned.global.count);
      expect(kept!.state, schedule.state);
      expect(kept.dueAt, schedule.dueAt);
      expect(kept.reviewCount, schedule.reviewCount);
      expect(
        estimator.withModel(loaded).estimate(mature(), isNew: false).inSeconds,
        inInclusiveRange(18, 22),
      );
    },
  );

  test('an older progress file with no pace data still loads', () async {
    final fresh = CardSchedule.fresh('rtk_001', now);
    SharedPreferences.setMockInitialValues({
      'progress_v1': jsonEncode({
        'schedules': {'rtk_001': fresh.toJson()},
        'settings': {'newKanjiPerDay': 5, 'dailyStudyMinutes': 5},
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    final repository = SharedPrefsProgressRepository(prefs);

    expect(
      await repository.getReviewDurationModel(),
      ReviewDurationModel.empty,
    );
    final schedule = await repository.getSchedule('rtk_001');
    expect(schedule!.state, CardLearningState.newCard);
    expect(schedule.dueAt, fresh.dueAt);
    expect(
      estimator.estimate(schedule, isNew: true),
      const Duration(seconds: 21),
    );
  });

  group('ActiveDurationTimer', () {
    test('background time is left out and the next start is empty', () {
      final timer = ActiveDurationTimer();
      final start = now;
      timer.start(start);
      timer.pause(start.add(const Duration(seconds: 10)));
      timer.resume(start.add(const Duration(minutes: 5)));
      expect(
        timer.elapsedAt(start.add(const Duration(minutes: 5, seconds: 8))),
        const Duration(seconds: 18),
      );

      final next = start.add(const Duration(minutes: 6));
      timer.start(next);
      expect(
        timer.elapsedAt(next.add(const Duration(seconds: 4))),
        const Duration(seconds: 4),
      );
    });

    test('pause and resume before a card starts do nothing', () {
      final timer = ActiveDurationTimer();
      timer.pause(now);
      timer.resume(now.add(const Duration(minutes: 1)));
      expect(
        timer.elapsedAt(now.add(const Duration(minutes: 2))),
        Duration.zero,
      );
    });
  });
}

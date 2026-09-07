import 'package:flutter_test/flutter_test.dart';
import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/review.dart';
import 'package:fiveminutekanji/services/initial_known_card_schedule.dart';
import 'package:fiveminutekanji/services/srs_engine.dart';

void main() {
  const engine = SrsEngine();
  final now = DateTime(2026, 9, 2, 8);

  CardSchedule fresh() => CardSchedule.fresh('rtk_001', now);

  test('introduce puts a new card into learning with a future due time', () {
    final next = engine.introduce(current: fresh(), now: now);

    expect(next.state, CardLearningState.learning);
    expect(next.interval, SrsEngine.newLearnInterval);
    expect(next.dueAt, now.add(SrsEngine.newLearnInterval));
    expect(next.reviewCount, 0);
    expect(next.correctCount, 0);
    expect(next.lastReviewedAt, isNull);
    expect(next.isDueAt(now), isFalse);
    expect(next.isDueAt(now.add(SrsEngine.newLearnInterval)), isTrue);
  });

  test('markAsKnown puts a new card into review ~30 days out', () {
    final next = engine.markAsKnown(current: fresh(), now: now);
    final expected = calculateInitialKnownCardSchedule('rtk_001');

    expect(next.state, CardLearningState.review);
    expect(next.interval, expected);
    expect(next.dueAt, now.add(expected));
    expect(next.interval.inDays, inInclusiveRange(15, 45));
    expect(next.reviewCount, 0);
    expect(next.correctCount, 0);
    expect(next.consecutiveGoodCount, 0);
    expect(next.isDueAt(now), isFalse);
    expect(
      next.isDueAt(now.add(expected).subtract(const Duration(seconds: 1))),
      isFalse,
    );
    expect(next.isDueAt(now.add(expected)), isTrue);
  });

  test('markAsKnown does not change cards that are already in SRS', () {
    final learning = engine.introduce(current: fresh(), now: now);
    final again = engine.markAsKnown(current: learning, now: now);
    expect(again.state, learning.state);
    expect(again.dueAt, learning.dueAt);
    expect(again.interval, learning.interval);
  });

  test('markAsKnown accepts a custom initial interval', () {
    const custom = Duration(days: 90);
    final next = engine.markAsKnown(
      current: fresh(),
      now: now,
      interval: custom,
    );
    expect(next.interval, custom);
    expect(next.dueAt, now.add(custom));
  });

  test('introduce does not change cards that are already in SRS', () {
    final learning = engine.introduce(current: fresh(), now: now);
    final again = engine.introduce(current: learning, now: now);
    expect(again.state, learning.state);
    expect(again.dueAt, learning.dueAt);
    expect(again.interval, learning.interval);
  });

  test('Again keeps the card in learning and due in about a minute', () {
    final next = engine.schedule(
      current: fresh(),
      result: ReviewResult.again,
      now: now,
    );

    expect(next.state, CardLearningState.learning);
    expect(next.interval, SrsEngine.againInterval);
    expect(next.dueAt, now.add(SrsEngine.againInterval));
    expect(next.incorrectCount, 1);
    expect(next.ease, lessThan(2.5));
  });

  test('Hard on a new card uses a short learning interval', () {
    final next = engine.schedule(
      current: fresh(),
      result: ReviewResult.hard,
      now: now,
    );

    expect(next.state, CardLearningState.learning);
    expect(next.interval, SrsEngine.learningHardInterval);
    expect(next.dueAt, now.add(SrsEngine.learningHardInterval));
    expect(next.correctCount, 1);
  });

  test('Good graduates new cards to review at one day', () {
    final next = engine.schedule(
      current: fresh(),
      result: ReviewResult.good,
      now: now,
    );

    expect(next.state, CardLearningState.review);
    expect(next.interval, SrsEngine.graduatingInterval);
    expect(next.dueAt, now.add(SrsEngine.graduatingInterval));
    expect(next.correctCount, 1);
  });

  test('Good on a review card grows the interval by ease', () {
    final current = CardSchedule(
      cardId: 'rtk_001',
      state: CardLearningState.review,
      reviewCount: 1,
      correctCount: 1,
      incorrectCount: 0,
      dueAt: now,
      interval: const Duration(days: 1),
      ease: 2.5,
    );

    final next = engine.schedule(
      current: current,
      result: ReviewResult.good,
      now: now,
    );

    expect(next.state, CardLearningState.review);
    expect(next.interval, const Duration(days: 3) - const Duration(hours: 12));
    expect(next.dueAt, now.add(next.interval));
  });

  test('ease never drops below the minimum', () {
    final current = fresh().copyWith(ease: 1.35);
    final next = engine.schedule(
      current: current,
      result: ReviewResult.again,
      now: now,
    );
    expect(next.ease, SrsEngine.minEase);
  });

  test('Again on a review card lapses it into learning', () {
    final current = CardSchedule(
      cardId: 'rtk_001',
      state: CardLearningState.review,
      reviewCount: 4,
      correctCount: 4,
      incorrectCount: 0,
      dueAt: now,
      interval: const Duration(days: 6),
      ease: 2.5,
    );

    final next = engine.schedule(
      current: current,
      result: ReviewResult.again,
      now: now,
    );

    expect(next.state, CardLearningState.learning);
    expect(next.interval, SrsEngine.againInterval);
    expect(next.dueAt, now.add(SrsEngine.againInterval));
    expect(next.incorrectCount, 1);
    expect(next.reviewCount, 5);
    expect(next.lastReviewedAt, now);
  });

  test('same inputs always produce the same schedule', () {
    final current = fresh();
    final first = engine.schedule(
      current: current,
      result: ReviewResult.good,
      now: now,
    );
    final second = engine.schedule(
      current: current,
      result: ReviewResult.good,
      now: now,
    );

    expect(first.state, second.state);
    expect(first.dueAt, second.dueAt);
    expect(first.interval, second.interval);
    expect(first.reviewCount, second.reviewCount);
    expect(first.correctCount, second.correctCount);
    expect(first.ease, second.ease);
    expect(first.lastReviewedAt, second.lastReviewedAt);
    expect(first.consecutiveGoodCount, second.consecutiveGoodCount);
  });

  test('Good increments consecutiveGoodCount', () {
    final next = engine.schedule(
      current: fresh(),
      result: ReviewResult.good,
      now: now,
    );
    expect(next.consecutiveGoodCount, 1);
  });

  test('Again resets consecutiveGoodCount', () {
    final current = fresh().copyWith(
      state: CardLearningState.review,
      reviewCount: 3,
      correctCount: 3,
      consecutiveGoodCount: 3,
    );
    final next = engine.schedule(
      current: current,
      result: ReviewResult.again,
      now: now,
    );
    expect(next.consecutiveGoodCount, 0);
  });

  test('Hard resets consecutiveGoodCount', () {
    final current = fresh().copyWith(
      state: CardLearningState.review,
      reviewCount: 2,
      correctCount: 2,
      consecutiveGoodCount: 2,
    );
    final next = engine.schedule(
      current: current,
      result: ReviewResult.hard,
      now: now,
    );
    expect(next.consecutiveGoodCount, 0);
  });

  test('three Goods then Again clears the consecutive streak', () {
    var schedule = fresh();
    for (var i = 0; i < 3; i++) {
      schedule = engine.schedule(
        current: schedule,
        result: ReviewResult.good,
        now: now,
      );
    }
    expect(schedule.consecutiveGoodCount, 3);

    schedule = engine.schedule(
      current: schedule,
      result: ReviewResult.again,
      now: now,
    );
    expect(schedule.consecutiveGoodCount, 0);
  });
}

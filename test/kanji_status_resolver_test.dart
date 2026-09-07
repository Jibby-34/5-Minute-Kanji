import 'package:flutter_test/flutter_test.dart';
import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/kanji_status.dart';
import 'package:fiveminutekanji/core/models/review.dart';
import 'package:fiveminutekanji/services/kanji_status_resolver.dart';
import 'package:fiveminutekanji/services/srs_engine.dart';

void main() {
  const resolver = KanjiStatusResolver();
  const engine = SrsEngine();
  final now = DateTime(2026, 9, 2, 8);

  CardSchedule fresh() => CardSchedule.fresh('rtk_001', now);

  test('null and unreviewed schedules are not encountered', () {
    expect(resolver.resolve(null), KanjiProgressStatus.notEncountered);
    expect(resolver.resolve(fresh()), KanjiProgressStatus.notEncountered);
  });

  test('completing learn marks the card as learning', () {
    final introduced = engine.introduce(current: fresh(), now: now);
    expect(resolver.resolve(introduced), KanjiProgressStatus.learning);
  });

  test('mark as known is learning, not mastered', () {
    final known = engine.markAsKnown(current: fresh(), now: now);
    expect(resolver.resolve(known), KanjiProgressStatus.learning);
    expect(
      known.consecutiveGoodCount,
      lessThan(KanjiStatusResolver.masteredConsecutiveGoods),
    );
  });

  test('a first review is learning', () {
    final reviewed = engine.schedule(
      current: fresh(),
      result: ReviewResult.good,
      now: now,
    );
    expect(resolver.resolve(reviewed), KanjiProgressStatus.learning);
  });

  test('three consecutive Goods is mastered', () {
    var schedule = fresh();
    for (var i = 0; i < 3; i++) {
      schedule = engine.schedule(
        current: schedule,
        result: ReviewResult.good,
        now: now,
      );
    }
    expect(
      schedule.consecutiveGoodCount,
      KanjiStatusResolver.masteredConsecutiveGoods,
    );
    expect(resolver.resolve(schedule), KanjiProgressStatus.mastered);
  });

  test('Again after mastered returns to learning', () {
    var schedule = fresh();
    for (var i = 0; i < 3; i++) {
      schedule = engine.schedule(
        current: schedule,
        result: ReviewResult.good,
        now: now,
      );
    }
    expect(resolver.resolve(schedule), KanjiProgressStatus.mastered);

    schedule = engine.schedule(
      current: schedule,
      result: ReviewResult.again,
      now: now,
    );
    expect(resolver.resolve(schedule), KanjiProgressStatus.learning);
  });

  test(
    'legacy schedules with reviews but no consecutive count are learning',
    () {
      final legacy = CardSchedule(
        cardId: 'rtk_001',
        state: CardLearningState.review,
        reviewCount: 4,
        correctCount: 4,
        incorrectCount: 0,
        dueAt: now,
        interval: const Duration(days: 1),
        ease: 2.5,
      );
      expect(legacy.consecutiveGoodCount, 0);
      expect(resolver.resolve(legacy), KanjiProgressStatus.learning);
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/kanji_card.dart';
import 'package:fiveminutekanji/core/models/start_of_day.dart';
import 'package:fiveminutekanji/data/hardcoded_kanji_data.dart';
import 'package:fiveminutekanji/services/due_card_selector.dart';
import 'package:fiveminutekanji/services/session_new_card_budget.dart';
import 'package:fiveminutekanji/services/srs_engine.dart';

import 'support/fakes.dart';

void main() {
  const selector = DueCardSelector();
  final now = DateTime(2026, 9, 2, 8);
  final cards = [testCard('new'), testCard('review'), testCard('learning')];

  CardSchedule schedule(
    String id,
    CardLearningState state, {
    required DateTime dueAt,
  }) {
    return CardSchedule(
      cardId: id,
      state: state,
      reviewCount: 1,
      correctCount: state == CardLearningState.learning ? 0 : 1,
      incorrectCount: state == CardLearningState.learning ? 1 : 0,
      dueAt: dueAt,
      interval: const Duration(minutes: 1),
      ease: 2.5,
    );
  }

  test('new cards are mixed into due cards instead of grouped together', () {
    final selected = selector.select(
      cards: cards,
      schedules: {
        'new': CardSchedule.fresh('new', now),
        'review': schedule(
          'review',
          CardLearningState.review,
          dueAt: now.subtract(const Duration(hours: 1)),
        ),
        'learning': schedule(
          'learning',
          CardLearningState.learning,
          dueAt: now.subtract(const Duration(minutes: 1)),
        ),
      },
      now: now,
      limit: 10,
      maxNewCards: 1,
    );

    expect(selected.map((card) => card.id), ['learning', 'new', 'review']);
  });

  test('future cards are not selected or counted as due reviews', () {
    final later = now.add(const Duration(days: 1));
    final schedules = {
      'new': CardSchedule.fresh('new', now),
      'review': schedule('review', CardLearningState.review, dueAt: later),
      'learning': schedule(
        'learning',
        CardLearningState.learning,
        dueAt: later,
      ),
    };

    expect(
      selector
          .select(cards: cards, schedules: schedules, now: now, limit: 10)
          .map((card) => card.id),
      ['new'],
    );
    expect(selector.countDue(cards: cards, schedules: schedules, now: now), 0);
    expect(selector.countNew(cards: cards, schedules: schedules), 1);
    expect(
      selector.nextFutureDue(cards: cards, schedules: schedules, now: now),
      later,
    );
  });

  test('cards due later today are in the daily window', () {
    final afternoon = DateTime(2026, 9, 2, 14);
    final evening = DateTime(2026, 9, 2, 23);
    final tomorrow = DateTime(2026, 9, 3, 8);
    final dueCards = [
      testCard('morning'),
      testCard('afternoon'),
      testCard('evening'),
      testCard('tomorrow'),
    ];
    final schedules = {
      'morning': schedule('morning', CardLearningState.review, dueAt: now),
      'afternoon': schedule(
        'afternoon',
        CardLearningState.review,
        dueAt: afternoon,
      ),
      'evening': schedule(
        'evening',
        CardLearningState.learning,
        dueAt: evening,
      ),
      'tomorrow': schedule(
        'tomorrow',
        CardLearningState.review,
        dueAt: tomorrow,
      ),
    };

    final selected = selector.select(
      cards: dueCards,
      schedules: schedules,
      now: now,
      limit: 10,
    );
    expect(selected.map((card) => card.id), [
      'evening',
      'morning',
      'afternoon',
    ]);
    expect(
      selector.countDue(cards: dueCards, schedules: schedules, now: now),
      3,
    );
    expect(
      selector.nextFutureDue(cards: dueCards, schedules: schedules, now: now),
      tomorrow,
    );
    expect(schedules['afternoon']!.isDueAt(now), isFalse);
    expect(selector.isAvailableToday(schedules['afternoon']!, now), isTrue);
  });

  test('a sub-day interval due later today is available once', () {
    final noon = DateTime(2026, 9, 2, 12);
    final card = testCard('short');
    final schedules = {
      'short': CardSchedule(
        cardId: 'short',
        state: CardLearningState.review,
        reviewCount: 1,
        correctCount: 1,
        incorrectCount: 0,
        dueAt: noon,
        interval: const Duration(hours: 4),
        ease: 2.5,
      ),
    };

    final selected = selector.select(
      cards: [card],
      schedules: schedules,
      now: now,
      limit: 10,
    );
    expect(selected.map((card) => card.id), ['short']);
    expect(selected.length, 1);
    expect(selector.countDue(cards: [card], schedules: schedules, now: now), 1);
    expect(schedules['short']!.isDueAt(now), isFalse);
  });

  test('a sub-day interval that lands tomorrow stays unavailable', () {
    final evening = DateTime(2026, 9, 2, 22);
    final dueAt = evening.add(const Duration(hours: 6));
    final card = testCard('late');
    final schedules = {
      'late': CardSchedule(
        cardId: 'late',
        state: CardLearningState.review,
        reviewCount: 1,
        correctCount: 1,
        incorrectCount: 0,
        dueAt: dueAt,
        interval: const Duration(hours: 6),
        ease: 2.5,
      ),
    };

    expect(
      selector.select(
        cards: [card],
        schedules: schedules,
        now: evening,
        limit: 10,
      ),
      isEmpty,
    );
    expect(
      selector.countDue(cards: [card], schedules: schedules, now: evening),
      0,
    );
    expect(
      selector.nextFutureDue(cards: [card], schedules: schedules, now: evening),
      dueAt,
    );
  });

  test('an introduced card is available today before its SRS due time', () {
    const engine = SrsEngine();
    final introduced = engine.introduce(
      current: CardSchedule.fresh('new', now),
      now: now,
    );

    expect(introduced.isDueAt(now), isFalse);
    expect(selector.isAvailableToday(introduced, now), isTrue);
    expect(
      selector
          .select(
            cards: cards,
            schedules: {
              'new': introduced,
              'review': schedule(
                'review',
                CardLearningState.review,
                dueAt: now,
              ),
              'learning': schedule(
                'learning',
                CardLearningState.learning,
                dueAt: now,
              ),
            },
            now: now,
            limit: 10,
          )
          .map((card) => card.id),
      ['learning', 'new', 'review'],
    );
  });

  test('maxNewCards 0 excludes unencountered kanji', () {
    final selected = selector.select(
      cards: cards,
      schedules: {
        'new': CardSchedule.fresh('new', now),
        'review': schedule('review', CardLearningState.review, dueAt: now),
        'learning': schedule(
          'learning',
          CardLearningState.learning,
          dueAt: now,
        ),
      },
      now: now,
      limit: 10,
      maxNewCards: 0,
    );

    expect(selected.map((card) => card.id), ['learning', 'review']);
  });

  test('new cards are spread through reviews instead of clumped', () {
    final reviewCards = [
      testCard('r1'),
      testCard('r2'),
      testCard('r3'),
      testCard('r4'),
      testCard('r5'),
    ];
    final newCards = [testCard('n1'), testCard('n2'), testCard('n3')];
    final selected = selector.select(
      cards: [...reviewCards, ...newCards],
      schedules: {
        for (final card in reviewCards)
          card.id: schedule(card.id, CardLearningState.review, dueAt: now),
        for (final card in newCards) card.id: CardSchedule.fresh(card.id, now),
      },
      now: now,
      limit: 20,
      maxNewCards: 3,
    );

    final kinds = selected
        .map((card) => card.id.startsWith('n') ? 'N' : 'R')
        .toList();
    final pattern = kinds.join();
    expect(pattern.startsWith('N'), isFalse);
    expect(pattern.contains('NNN'), isFalse);
    expect(pattern.contains('NN'), isFalse);
    expect(pattern, isNot('NRNRNRRR'));
    expect(pattern, isNot('NNNRRRRR'));
    expect(pattern, isNot('RRRRRNNN'));
    expect(kinds.where((ch) => ch == 'N').length, 3);
    expect(kinds.where((ch) => ch == 'R').length, 5);
    expect(selected.first.id, 'r1');
  });

  test(
    'due reviews are not dropped just to fill the sitting with new cards',
    () {
      final reviewCards = List.generate(10, (i) => testCard('r$i'));
      final newCards = List.generate(10, (i) => testCard('n$i'));
      final selected = selector.select(
        cards: [...reviewCards, ...newCards],
        schedules: {
          for (final card in reviewCards)
            card.id: schedule(card.id, CardLearningState.review, dueAt: now),
          for (final card in newCards)
            card.id: CardSchedule.fresh(card.id, now),
        },
        now: now,
        limit: 10,
        maxNewCards: sessionNewCardLimit(
          sessionCapacity: 10,
          dueReviewCount: 10,
          remainingDaily: 10,
        ),
      );

      final newCount = selected.where((card) => card.id.startsWith('n')).length;
      final reviewCount = selected
          .where((card) => card.id.startsWith('r'))
          .length;
      expect(newCount, lessThan(reviewCount));
      expect(newCount, inInclusiveRange(1, 3));
      expect(reviewCount, greaterThanOrEqualTo(7));
    },
  );

  test('new kanji follow JLPT n5 then n4, then lowest id', () {
    final n5 = testCard('n5-080', jlptLevel: JlptLevel.n5);
    final n4First = testCard(
      'n4-001',
      keyword: 'same',
      jlptLevel: JlptLevel.n4,
    );
    final n5LowerId = testCard('n5-001', jlptLevel: JlptLevel.n5);
    final n3 = testCard('n3-001', jlptLevel: JlptLevel.n3);
    final selected = selector.select(
      cards: [n4First, n3, n5, n5LowerId],
      schedules: const {},
      now: now,
      limit: 4,
      maxNewCards: 4,
    );

    expect(selected.map((card) => card.id), [
      'n5-001',
      'n5-080',
      'n4-001',
      'n3-001',
    ]);
  });

  test('hardcoded deck picks remaining n5 before n4-001 same', () {
    final learnedN5 = hardcodedKanjiCards
        .where((card) => card.jlptLevel == JlptLevel.n5)
        .take(20)
        .toList();
    final schedules = {
      for (final card in learnedN5)
        card.id: schedule(card.id, CardLearningState.review, dueAt: now),
    };
    final selected = selector.select(
      cards: hardcodedKanjiCards,
      schedules: schedules,
      now: now,
      limit: 1,
      maxNewCards: 1,
    );

    expect(selected, isNotEmpty);
    expect(selected.first.jlptLevel, JlptLevel.n5);
    expect(selected.first.id, isNot('n4-001'));
  });

  test('cards due before start of day stay in today\'s window', () {
    const start = StartOfDay(hour: 4);
    final beforeBoundary = DateTime(2026, 9, 3, 3, 59);
    final atBoundary = DateTime(2026, 9, 3, 4);
    final dueCards = [testCard('before'), testCard('at')];
    final schedules = {
      'before': schedule(
        'before',
        CardLearningState.review,
        dueAt: beforeBoundary,
      ),
      'at': schedule('at', CardLearningState.review, dueAt: atBoundary),
    };

    expect(
      selector.isAvailableToday(schedules['before']!, now, startOfDay: start),
      isTrue,
    );
    expect(
      selector.isAvailableToday(schedules['at']!, now, startOfDay: start),
      isFalse,
    );
    expect(
      selector
          .select(
            cards: dueCards,
            schedules: schedules,
            now: now,
            limit: 10,
            startOfDay: start,
          )
          .map((card) => card.id),
      ['before'],
    );
    expect(
      selector.countDue(
        cards: dueCards,
        schedules: schedules,
        now: now,
        startOfDay: start,
      ),
      1,
    );
    expect(
      selector.nextFutureDue(
        cards: dueCards,
        schedules: schedules,
        now: now,
        startOfDay: start,
      ),
      atBoundary,
    );
  });

  test('3:59 AM is still yesterday\'s review window', () {
    const start = StartOfDay(hour: 4);
    final lateNight = DateTime(2026, 9, 3, 3, 59);
    final dueAtBoundary = DateTime(2026, 9, 3, 4);
    final card = testCard('boundary');
    final schedules = {
      'boundary': schedule(
        'boundary',
        CardLearningState.review,
        dueAt: dueAtBoundary,
      ),
    };

    expect(
      selector.isAvailableToday(
        schedules['boundary']!,
        lateNight,
        startOfDay: start,
      ),
      isFalse,
    );
    expect(
      selector.isAvailableToday(
        schedules['boundary']!,
        dueAtBoundary,
        startOfDay: start,
      ),
      isTrue,
    );
  });
}

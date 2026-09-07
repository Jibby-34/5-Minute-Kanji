import 'package:flutter_test/flutter_test.dart';
import 'package:fiveminutekanji/core/models/kanji_card.dart';
import 'package:fiveminutekanji/core/models/review.dart';
import 'package:fiveminutekanji/services/review_session.dart';

const _cards = [
  KanjiCard(
    id: 'a',
    character: '一',
    meaning: 'one',
    keyword: 'one',
    mnemonic: 'one',
    components: [],
    strokeCount: 1,
  ),
  KanjiCard(
    id: 'b',
    character: '二',
    meaning: 'two',
    keyword: 'two',
    mnemonic: 'two',
    components: [],
    strokeCount: 2,
  ),
  KanjiCard(
    id: 'c',
    character: '三',
    meaning: 'three',
    keyword: 'three',
    mnemonic: 'three',
    components: [],
    strokeCount: 3,
  ),
];

void main() {
  test('Again requeues the card a few places later', () {
    final session = ReviewSession(
      config: ReviewSessionConfig.fiveMinute,
      cards: _cards,
    );

    expect(session.current?.id, 'a');
    session.recordRating(ReviewResult.again);
    expect(session.current?.id, 'b');
    session.recordRating(ReviewResult.good);
    expect(session.current?.id, 'c');
    session.recordRating(ReviewResult.good);
    expect(session.current?.id, 'a');
    expect(session.isComplete, isFalse);
    session.recordRating(ReviewResult.good);
    expect(session.isComplete, isTrue);
    expect(session.againCount, 1);
    expect(session.successfulCount, 2);
    expect(session.reviewedCount, 3);
  });

  test('completing learn drops the card instead of keeping it current', () {
    final session = ReviewSession(
      config: ReviewSessionConfig.fiveMinute,
      cards: _cards,
    );

    expect(session.completeIntroduction()?.id, 'a');
    expect(session.current?.id, 'b');
    expect(session.hasReviewed('a'), isTrue);
    expect(session.displayIndex, 2);
  });

  test(
    'offerDue mixes missing cards later instead of jumping to the front',
    () {
      final session = ReviewSession(
        config: ReviewSessionConfig.fiveMinute,
        cards: _cards,
      );

      session.completeIntroduction();
      expect(session.current?.id, 'b');
      session.offerDue([_cards[0], _cards[1], _cards[2]]);
      expect(session.current?.id, 'b');
      session.recordRating(ReviewResult.good);
      expect(session.current?.id, 'c');
      session.recordRating(ReviewResult.good);
      expect(session.current?.id, 'a');
    },
  );

  test('session config drives max cards, not a hardcoded five', () {
    const config = ReviewSessionConfig(
      duration: Duration(minutes: 2),
      averageSecondsPerCard: 12,
    );
    expect(config.effectiveMaxCards, 10);
  });
}

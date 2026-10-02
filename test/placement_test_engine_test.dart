import 'package:flutter_test/flutter_test.dart';

import 'package:fiveminutekanji/core/models/kanji_card.dart';
import 'package:fiveminutekanji/core/models/placement.dart';
import 'package:fiveminutekanji/services/placement_test_engine.dart';

import 'support/fakes.dart';

void main() {
  const engine = PlacementTestEngine();

  /// Pool in difficulty order: the first 100 are N5, the rest N4, so ids and
  /// difficulty rank line up.
  List<KanjiCard> pool(int count) {
    return [
      for (var i = 0; i < count; i++)
        testCard(
          'k${i.toString().padLeft(3, '0')}',
          character: String.fromCharCode(0x4E00 + i),
          jlptLevel: i < 100 ? JlptLevel.n5 : JlptLevel.n4,
        ),
    ];
  }

  int rankOf(KanjiCard card) => int.parse(card.id.substring(1));

  /// Plays a whole test for a user who knows every kanji ranked below
  /// [knownThrough].
  ({PlacementRun run, List<PlacementAnswer> answers}) takeTest(
    List<KanjiCard> cards, {
    required int knownThrough,
    PlacementTestEngine engine = const PlacementTestEngine(),
  }) {
    final answers = <PlacementAnswer>[];
    final run = engine.replay(cards, const []);
    while (!run.isFinished) {
      final question = run.currentQuestion!;
      final answer = PlacementAnswer(
        cardId: question.id,
        known: rankOf(question) < knownThrough,
      );
      answers.add(answer);
      run.record(answer);
    }
    return (run: run, answers: answers);
  }

  test('stays inside the question budget at every ability level', () {
    for (final knownThrough in [0, 10, 60, 100, 150, 220, 250]) {
      final test = takeTest(pool(250), knownThrough: knownThrough);

      expect(
        test.run.answeredCount,
        inInclusiveRange(engine.minQuestions, engine.maxQuestions),
        reason: 'knows $knownThrough',
      );
    }
  });

  test('samples across difficulty instead of walking from the easiest', () {
    final cards = pool(250);
    final test = takeTest(cards, knownThrough: 150);
    final ranks = test.answers.map((answer) {
      return rankOf(cards.firstWhere((card) => card.id == answer.cardId));
    }).toList();

    // An experienced learner is not kept in beginner kanji: the test reaches
    // well past the easiest band and covers both JLPT levels present.
    expect(ranks.reduce((a, b) => a > b ? a : b), greaterThan(180));
    expect(ranks.where((rank) => rank >= 100), isNotEmpty);
    expect(ranks.where((rank) => rank < 100), isNotEmpty);

    // Questions within a band are spread, not consecutive.
    final sorted = List<int>.of(ranks)..sort();
    expect(sorted, isNot(List.generate(ranks.length, (i) => i)));
  });

  test('opens with the easiest kanji in the pool', () {
    final cards = pool(250);
    final first = engine.replay(cards, const []).currentQuestion;

    expect(first?.id, cards.first.id);
  });

  test('places a learner near the boundary they actually have', () {
    final cards = pool(250);
    final outcome = takeTest(cards, knownThrough: 150).run.outcome();

    // One difficulty band of slack: the test infers whole bands rather than
    // asking about all 250 kanji.
    expect(outcome.knownCardIds.length, closeTo(150, 25));
    expect(outcome.startingLevel, JlptLevel.n4);
  });

  test('a user who knows nothing is marked known for nothing', () {
    final outcome = takeTest(pool(250), knownThrough: 0).run.outcome();

    expect(outcome.knownCardIds, isEmpty);
    expect(outcome.answeredCount, engine.minQuestions);
    expect(outcome.startingLevel, JlptLevel.n5);
  });

  test('a user who knows everything is marked known for everything', () {
    final cards = pool(250);
    final outcome = takeTest(cards, knownThrough: 250).run.outcome();

    expect(outcome.knownCardIds, hasLength(cards.length));
    expect(outcome.startingLevel, isNull);
  });

  test('an answered kanji is never overruled by its band', () {
    final cards = pool(250);
    final run = engine.replay(cards, const []);
    final answers = <PlacementAnswer>[];
    String? refusedInEasyBand;
    String? claimedInHardBand;

    while (!run.isFinished) {
      final question = run.currentQuestion!;
      final rank = rankOf(question);
      var known = rank < 150;
      if (known && refusedInEasyBand == null) {
        known = false;
        refusedInEasyBand = question.id;
      } else if (!known && claimedInHardBand == null) {
        known = true;
        claimedInHardBand = question.id;
      }
      final answer = PlacementAnswer(cardId: question.id, known: known);
      answers.add(answer);
      run.record(answer);
    }

    final known = run.outcome().knownCardIds;
    expect(known, isNot(contains(refusedInEasyBand)));
    expect(known, contains(claimedInHardBand));
  });

  test('a replayed run resumes on the question it was left on', () {
    final cards = pool(250);
    final interrupted = engine.replay(cards, const []);
    final answers = <PlacementAnswer>[];
    for (var i = 0; i < 7; i++) {
      final question = interrupted.currentQuestion!;
      final answer = PlacementAnswer(
        cardId: question.id,
        known: rankOf(question) < 150,
      );
      answers.add(answer);
      interrupted.record(answer);
    }

    final resumed = engine.replay(cards, answers);

    expect(resumed.answeredCount, 7);
    expect(resumed.currentQuestion?.id, interrupted.currentQuestion?.id);
    expect(resumed.outcome().knownCardIds, interrupted.outcome().knownCardIds);
  });

  test('an answer for a kanji that left the pool is ignored', () {
    final cards = pool(250);
    final resumed = engine.replay(cards, const [
      PlacementAnswer(cardId: 'gone', known: true),
    ]);

    expect(resumed.answeredCount, 0);
    expect(resumed.currentQuestion?.id, cards.first.id);
  });

  test('a pool too small to band still finishes', () {
    final cards = pool(4);
    final test = takeTest(cards, knownThrough: 4);

    expect(test.run.answeredCount, lessThanOrEqualTo(cards.length));
    expect(test.run.outcome().knownCardIds, hasLength(cards.length));
    expect(engine.estimatedQuestionCount(cards.length), cards.length);
  });

  test('an empty pool is finished before it starts', () {
    final run = engine.replay(const [], const []);

    expect(run.isFinished, isTrue);
    expect(run.currentQuestion, isNull);
    expect(run.outcome().knownCardIds, isEmpty);
    expect(run.outcome().startingLevel, isNull);
    expect(run.estimatedTotal, 0);
  });

  test('bands cover the pool in difficulty order without gaps', () {
    final cards = pool(250);
    final bands = engine.bands(cards);

    expect(bands, hasLength(engine.maxBands));
    expect(
      bands.expand((band) => band).map((card) => card.id),
      cards.map((card) => card.id),
    );
    expect(bands.every((band) => band.length >= engine.minBandSize), isTrue);
  });
}

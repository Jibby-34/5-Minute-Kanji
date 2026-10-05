import 'package:flutter_test/flutter_test.dart';

import 'package:fiveminutekanji/core/models/kanji_card.dart';
import 'package:fiveminutekanji/core/models/placement.dart';
import 'package:fiveminutekanji/data/hardcoded_kanji_repository.dart';
import 'package:fiveminutekanji/services/placement_test_engine.dart';

import 'support/fakes.dart';

void main() {
  const engine = PlacementTestEngine();

  late List<KanjiCard> cards;

  setUpAll(() async {
    cards = await const HardcodedKanjiRepository().getAll();
  });

  int countThrough(JlptLevel level) {
    final ceiling = JlptLevel.sectionOrder.indexOf(level);
    return cards
        .where(
          (card) => JlptLevel.sectionOrder.indexOf(card.jlptLevel) <= ceiling,
        )
        .length;
  }

  bool knowsThrough(KanjiCard card, JlptLevel? level) {
    if (level == null) return false;
    return JlptLevel.sectionOrder.indexOf(card.jlptLevel) <=
        JlptLevel.sectionOrder.indexOf(level);
  }

  ({PlacementRun run, List<PlacementAnswer> answers}) takeTest(
    bool Function(KanjiCard card) knows, {
    PlacementTestEngine engine = const PlacementTestEngine(),
    List<KanjiCard>? pool,
  }) {
    final source = pool ?? cards;
    final answers = <PlacementAnswer>[];
    final run = engine.replay(source, const []);
    while (!run.isFinished) {
      final question = run.currentQuestion!;
      final answer = PlacementAnswer(
        cardId: question.id,
        known: knows(question),
      );
      answers.add(answer);
      run.record(answer);
    }
    return (run: run, answers: answers);
  }

  test(
    'the full catalog has every JLPT level and stays within 20 questions',
    () {
      final levels = cards.map((card) => card.jlptLevel).toSet();
      expect(
        levels,
        containsAll(const [
          JlptLevel.n5,
          JlptLevel.n4,
          JlptLevel.n3,
          JlptLevel.n2,
          JlptLevel.n1,
        ]),
      );

      for (final level in [null, JlptLevel.n5, JlptLevel.n3, JlptLevel.n1]) {
        final test = takeTest((card) => knowsThrough(card, level));
        expect(
          test.run.answeredCount,
          inInclusiveRange(
            engine.minimumQuestions,
            PlacementTestEngine.questionCap,
          ),
          reason: 'knows through $level',
        );
        expect(
          test.answers.map((answer) => answer.cardId).toSet(),
          hasLength(test.answers.length),
          reason: 'knows through $level',
        );
      }

      expect(
        engine.estimatedQuestionCount(cards.length),
        PlacementTestEngine.questionCap,
      );
    },
  );

  test('a higher maxQuestions still cannot exceed 20', () {
    const uncapped = PlacementTestEngine(maxQuestions: 100, minQuestions: 100);
    final test = takeTest((_) => false, engine: uncapped);

    expect(test.run.answeredCount, PlacementTestEngine.questionCap);
    expect(
      uncapped.estimatedQuestionCount(cards.length),
      PlacementTestEngine.questionCap,
    );
  });

  test('samples across N5–N1 instead of the first cards in the file', () {
    final test = takeTest((card) => knowsThrough(card, JlptLevel.n2));
    final asked = test.answers.map((answer) => answer.cardId).toSet();
    final askedLevels = cards
        .where((card) => asked.contains(card.id))
        .map((card) => card.jlptLevel)
        .toSet();

    expect(askedLevels, contains(JlptLevel.n5));
    expect(askedLevels, contains(JlptLevel.n1));
    expect(
      asked,
      isNot(cards.take(test.answers.length).map((card) => card.id).toSet()),
    );
  });

  test('opens with the easiest kanji in the pool', () {
    final first = engine.replay(cards, const []).currentQuestion;

    expect(first?.id, cards.first.id);
    expect(first?.jlptLevel, JlptLevel.n5);
  });

  test('places a learner on the JLPT boundary they demonstrated', () {
    final nothing = takeTest((_) => false).run.outcome();
    expect(nothing.knownCardIds, isEmpty);
    expect(nothing.startingLevel, JlptLevel.n5);
    expect(nothing.answeredCount, engine.minimumQuestions);

    final n5 = takeTest(
      (card) => knowsThrough(card, JlptLevel.n5),
    ).run.outcome();
    expect(n5.knownCardIds, hasLength(countThrough(JlptLevel.n5)));
    expect(n5.startingLevel, JlptLevel.n4);

    final n4 = takeTest(
      (card) => knowsThrough(card, JlptLevel.n4),
    ).run.outcome();
    expect(n4.knownCardIds, hasLength(countThrough(JlptLevel.n4)));
    expect(n4.startingLevel, JlptLevel.n3);

    final n3 = takeTest(
      (card) => knowsThrough(card, JlptLevel.n3),
    ).run.outcome();
    expect(n3.knownCardIds, hasLength(countThrough(JlptLevel.n3)));
    expect(n3.startingLevel, JlptLevel.n2);

    final n2 = takeTest(
      (card) => knowsThrough(card, JlptLevel.n2),
    ).run.outcome();
    expect(n2.knownCardIds, hasLength(countThrough(JlptLevel.n2)));
    expect(n2.startingLevel, JlptLevel.n1);

    final everything = takeTest((_) => true).run.outcome();
    expect(everything.knownCardIds, hasLength(cards.length));
    expect(everything.startingLevel, isNull);
  });

  test('places a learner inside a JLPT level, not only on its edge', () {
    final bands = engine.bands(cards);

    ({PlacementOutcome outcome, int answered}) placeAt(int bandCount) {
      final prefix = bands
          .take(bandCount)
          .expand((band) => band.map((card) => card.id))
          .toSet();
      final test = takeTest((card) => prefix.contains(card.id));
      return (outcome: test.run.outcome(), answered: test.run.answeredCount);
    }

    // Two fifths of the way through N5. Obvious early, so it stops once the
    // minimum confirmation questions are in, not at the 20-question cap.
    final earlyN5 = placeAt(2);
    expect(earlyN5.answered, engine.minimumQuestions);
    expect(earlyN5.outcome.resumesMidLevel, isTrue);
    expect(earlyN5.outcome.startingLevel, JlptLevel.n5);
    expect(
      earlyN5.outcome.knownCardIds,
      hasLength(bands.take(2).expand((band) => band).length),
    );

    // Just under halfway through N3.
    final midN3 = placeAt(12);
    expect(midN3.answered, lessThanOrEqualTo(PlacementTestEngine.questionCap));
    expect(midN3.outcome.resumesMidLevel, isTrue);
    expect(midN3.outcome.startingLevel, JlptLevel.n3);
    expect(
      midN3.outcome.knownCardIds.toSet(),
      bands.take(12).expand((band) => band.map((card) => card.id)).toSet(),
    );

    // Three fifths of the way through N1, with everything easier known.
    final midN1 = placeAt(23);
    expect(midN1.answered, lessThanOrEqualTo(PlacementTestEngine.questionCap));
    expect(midN1.outcome.resumesMidLevel, isTrue);
    expect(midN1.outcome.startingLevel, JlptLevel.n1);
    expect(
      midN1.outcome.knownCardIds.toSet(),
      bands.take(23).expand((band) => band.map((card) => card.id)).toSet(),
    );
    expect(midN1.outcome.knownCardIds.length, lessThan(cards.length));
    expect(
      midN1.outcome.knownCardIds.length,
      greaterThan(countThrough(JlptLevel.n2)),
    );
  });

  test('an answered kanji is never overruled by its band', () {
    final run = engine.replay(cards, const []);
    String? refusedInEasyBand;
    String? claimedInHardBand;
    var seenHard = false;

    while (!run.isFinished) {
      final question = run.currentQuestion!;
      final level = JlptLevel.sectionOrder.indexOf(question.jlptLevel);
      var known = level <= JlptLevel.sectionOrder.indexOf(JlptLevel.n2);
      if (!known) seenHard = true;
      // Flip one answer on each side of the boundary, but only after the
      // climb has reached a hard kanji. Refusing the opening question would
      // end the search before any hard kanji is shown.
      if (known && seenHard && refusedInEasyBand == null) {
        known = false;
        refusedInEasyBand = question.id;
      } else if (!known && claimedInHardBand == null) {
        known = true;
        claimedInHardBand = question.id;
      }
      run.record(PlacementAnswer(cardId: question.id, known: known));
    }

    expect(refusedInEasyBand, isNotNull);
    expect(claimedInHardBand, isNotNull);

    final known = run.outcome().knownCardIds;
    expect(known, isNot(contains(refusedInEasyBand)));
    expect(known, contains(claimedInHardBand));
  });

  test('a replayed run resumes on the question it was left on', () {
    final interrupted = engine.replay(cards, const []);
    final answers = <PlacementAnswer>[];
    for (var i = 0; i < 7; i++) {
      final question = interrupted.currentQuestion!;
      final answer = PlacementAnswer(
        cardId: question.id,
        known: question.jlptLevel == JlptLevel.n5,
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
    final resumed = engine.replay(cards, const [
      PlacementAnswer(cardId: 'gone', known: true),
    ]);

    expect(resumed.answeredCount, 0);
    expect(resumed.currentQuestion?.id, cards.first.id);
  });

  test('a pool too small to band still finishes', () {
    final few = [
      for (var i = 0; i < 4; i++)
        testCard('k$i', jlptLevel: JlptLevel.n5, character: '$i'),
    ];
    final test = takeTest((_) => true, pool: few);

    expect(test.run.answeredCount, lessThanOrEqualTo(few.length));
    expect(test.run.outcome().knownCardIds, hasLength(few.length));
    expect(engine.estimatedQuestionCount(few.length), few.length);
  });

  test('an empty pool is finished before it starts', () {
    final run = engine.replay(const [], const []);

    expect(run.isFinished, isTrue);
    expect(run.currentQuestion, isNull);
    expect(run.outcome().knownCardIds, isEmpty);
    expect(run.outcome().startingLevel, isNull);
    expect(run.estimatedTotal, 0);
  });

  test('bands cover every level without mixing them or leaving gaps', () {
    final bands = engine.bands(cards);

    expect(bands, hasLength(25));
    final slices = <JlptLevel, int>{};
    for (final band in bands) {
      final level = band.first.jlptLevel;
      slices[level] = (slices[level] ?? 0) + 1;
    }
    expect(slices[JlptLevel.n5], 5);
    expect(slices[JlptLevel.n4], 5);
    expect(slices[JlptLevel.n3], 5);
    expect(slices[JlptLevel.n2], 5);
    expect(slices[JlptLevel.n1], 5);
    expect(
      bands.expand((band) => band).map((card) => card.id),
      cards.map((card) => card.id),
    );
    expect(
      bands.every(
        (band) => band.map((card) => card.jlptLevel).toSet().length == 1,
      ),
      isTrue,
    );
    expect(bands.map((band) => band.first.jlptLevel).toSet(), {
      JlptLevel.n5,
      JlptLevel.n4,
      JlptLevel.n3,
      JlptLevel.n2,
      JlptLevel.n1,
    });
    expect(bands.every((band) => band.isNotEmpty), isTrue);
  });
}

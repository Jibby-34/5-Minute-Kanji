import 'package:flutter_test/flutter_test.dart';

import 'package:fiveminutekanji/core/models/kanji_card.dart';
import 'package:fiveminutekanji/core/models/placement.dart';
import 'package:fiveminutekanji/data/hardcoded_kanji_repository.dart';
import 'package:fiveminutekanji/services/due_card_selector.dart';
import 'package:fiveminutekanji/services/placement_test_engine.dart';

import 'support/fakes.dart';

void main() {
  const engine = PlacementTestEngine();

  late List<KanjiCard> cards;
  late List<KanjiCard> ordered;

  setUpAll(() async {
    cards = await const HardcodedKanjiRepository().getAll();
    ordered = List<KanjiCard>.of(cards)..sort(compareKanjiLearnOrder);
  });

  int indexOf(KanjiCard card) =>
      ordered.indexWhere((item) => item.id == card.id);

  bool knowsFirst(KanjiCard card, int count) => indexOf(card) < count;

  int countThrough(JlptLevel level) {
    final ceiling = JlptLevel.sectionOrder.indexOf(level);
    return ordered
        .where(
          (card) => JlptLevel.sectionOrder.indexOf(card.jlptLevel) <= ceiling,
        )
        .length;
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

  test('stays within 20 questions and never estimates above the truth', () {
    final levels = ordered.map((card) => card.jlptLevel).toSet();
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

    for (final cutoff in [0, 1, 40, 80, 250, 600, 1027, 1800, 2220]) {
      final test = takeTest((card) => knowsFirst(card, cutoff));
      expect(
        test.run.answeredCount,
        inInclusiveRange(1, PlacementTestEngine.questionCap),
        reason: 'cutoff $cutoff',
      );
      expect(
        test.answers.map((answer) => answer.cardId).toSet(),
        hasLength(test.answers.length),
        reason: 'cutoff $cutoff',
      );
      expect(
        test.run.outcome().knownCardIds.length,
        lessThanOrEqualTo(cutoff),
        reason: 'cutoff $cutoff',
      );
      expect(
        cutoff - test.run.outcome().knownCardIds.length,
        lessThanOrEqualTo(3),
        reason: 'cutoff $cutoff',
      );
    }

    expect(
      engine.estimatedQuestionCount(cards.length),
      PlacementTestEngine.questionCap,
    );
  });

  test('a higher maxQuestions still cannot exceed 20', () {
    const uncapped = PlacementTestEngine(maxQuestions: 100);
    final test = takeTest((_) => false, engine: uncapped);

    expect(
      test.run.answeredCount,
      lessThanOrEqualTo(PlacementTestEngine.questionCap),
    );
    expect(test.run.outcome().knownCardIds, isEmpty);
    expect(
      uncapped.estimatedQuestionCount(cards.length),
      PlacementTestEngine.questionCap,
    );
  });

  test('steps upward, then searches backward after the first miss', () {
    final test = takeTest(
      (card) => knowsFirst(card, countThrough(JlptLevel.n2)),
    );
    final indexes = [
      for (final answer in test.answers)
        indexOf(ordered.firstWhere((card) => card.id == answer.cardId)),
    ];
    final firstMiss = test.answers.indexWhere((answer) => !answer.known);

    expect(firstMiss, greaterThan(0));
    for (var i = 1; i <= firstMiss; i++) {
      expect(indexes[i], greaterThan(indexes[i - 1]));
    }
    expect(indexes[firstMiss + 1], lessThan(indexes[firstMiss]));
    expect(indexes, isNot(List.generate(indexes.length, (i) => i)));
  });

  test('opens with the easiest kanji in the pool', () {
    final first = engine.replay(cards, const []).currentQuestion;

    expect(first?.id, ordered.first.id);
    expect(first?.jlptLevel, JlptLevel.n5);
  });

  test('places a learner on the JLPT boundary they demonstrated', () {
    final nothing = takeTest((_) => false).run.outcome();
    expect(nothing.knownCardIds, isEmpty);
    expect(nothing.startingLevel, JlptLevel.n5);
    expect(nothing.answeredCount, 1);
    expect(nothing.resumesMidLevel, isFalse);

    final n5 = takeTest(
      (card) => knowsFirst(card, countThrough(JlptLevel.n5)),
    ).run.outcome();
    expect(n5.knownCardIds, hasLength(countThrough(JlptLevel.n5)));
    expect(n5.startingLevel, JlptLevel.n4);
    expect(n5.resumesMidLevel, isFalse);

    final n4 = takeTest(
      (card) => knowsFirst(card, countThrough(JlptLevel.n4)),
    ).run.outcome();
    expect(n4.knownCardIds, hasLength(countThrough(JlptLevel.n4)));
    expect(n4.startingLevel, JlptLevel.n3);

    final n3 = takeTest(
      (card) => knowsFirst(card, countThrough(JlptLevel.n3)),
    ).run.outcome();
    expect(n3.knownCardIds, hasLength(countThrough(JlptLevel.n3)));
    expect(n3.startingLevel, JlptLevel.n2);

    final n2 = takeTest(
      (card) => knowsFirst(card, countThrough(JlptLevel.n2)),
    ).run.outcome();
    expect(n2.knownCardIds, hasLength(countThrough(JlptLevel.n2)));
    expect(n2.startingLevel, JlptLevel.n1);

    final everything = takeTest((_) => true).run.outcome();
    expect(everything.knownCardIds, hasLength(cards.length));
    expect(everything.startingLevel, isNull);
  });

  test('places a learner inside a JLPT level', () {
    final n5Count = countThrough(JlptLevel.n5);
    final earlyN5 = takeTest((card) => knowsFirst(card, 40)).run.outcome();
    expect(earlyN5.knownCardIds, hasLength(40));
    expect(earlyN5.startingLevel, JlptLevel.n5);
    expect(earlyN5.resumesMidLevel, isTrue);
    expect(earlyN5.knownCardIds.length, lessThan(n5Count));

    final n3Start = countThrough(JlptLevel.n4);
    final midN3 = n3Start + 120;
    final insideN3 = takeTest((card) => knowsFirst(card, midN3)).run.outcome();
    expect(insideN3.knownCardIds.length, lessThanOrEqualTo(midN3));
    expect(midN3 - insideN3.knownCardIds.length, lessThanOrEqualTo(3));
    expect(insideN3.startingLevel, JlptLevel.n3);
    expect(insideN3.resumesMidLevel, isTrue);

    final n1Start = countThrough(JlptLevel.n2);
    final midN1 = n1Start + 400;
    final insideN1 = takeTest((card) => knowsFirst(card, midN1)).run.outcome();
    expect(insideN1.knownCardIds.length, lessThanOrEqualTo(midN1));
    expect(insideN1.knownCardIds.length, greaterThan(n1Start));
    expect(midN1 - insideN1.knownCardIds.length, lessThanOrEqualTo(3));
    expect(insideN1.startingLevel, JlptLevel.n1);
    expect(insideN1.resumesMidLevel, isTrue);
  });

  test('an explicit answer is never overruled by the boundary', () {
    final missed = ordered[10];
    final claimed = ordered[400];
    final run = engine.replay(ordered, [
      PlacementAnswer(cardId: ordered.first.id, known: true),
      PlacementAnswer(cardId: missed.id, known: false),
      PlacementAnswer(cardId: claimed.id, known: true),
    ]);

    final known = run.outcome().knownCardIds;
    expect(known, isNot(contains(missed.id)));
    expect(known, contains(claimed.id));
    // The one known answer above the miss does not mark the gap as known.
    expect(known.length, lessThan(50));
  });

  test('a replayed run resumes on the question it was left on', () {
    final interrupted = engine.replay(cards, const []);
    final answers = <PlacementAnswer>[];
    for (var i = 0; i < 7; i++) {
      final question = interrupted.currentQuestion!;
      final answer = PlacementAnswer(
        cardId: question.id,
        known: indexOf(question) < 500,
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
    expect(resumed.currentQuestion?.id, ordered.first.id);
  });

  test('a pool of a few kanji still finishes', () {
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
}

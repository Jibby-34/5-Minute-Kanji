import 'package:flutter_test/flutter_test.dart';
import 'package:fiveminutekanji/core/models/kanji_card.dart';
import 'package:fiveminutekanji/core/models/placement.dart';
import 'package:fiveminutekanji/services/placement_model.dart';
import 'package:fiveminutekanji/services/placement_test_engine.dart';

import 'support/fakes.dart';

void main() {
  List<KanjiCard> ladder() {
    return [
      for (var difficulty = 1; difficulty <= 100; difficulty++)
        testCard(
          'd-${difficulty.toString().padLeft(3, '0')}',
          difficulty: difficulty,
          jlptLevel: _levelFor(difficulty),
          character: '$difficulty',
        ),
    ];
  }

  PlacementRun answerAll(
    List<KanjiCard> cards,
    bool Function(KanjiCard card) knows, {
    int seed = 1,
  }) {
    final run = PlacementTestEngine(
      selectionSeed: seed,
    ).replay(cards, const []);
    var guard = 0;
    while (run.currentQuestion != null) {
      final question = run.currentQuestion!;
      run.record(PlacementAnswer(cardId: question.id, known: knows(question)));
      guard++;
      expect(guard, lessThanOrEqualTo(placementMaxQuestions));
    }
    return run;
  }

  test('the prior is uniform and the curve is soft at the boundary', () {
    final posterior = PlacementPosterior();
    expect(posterior.mean, closeTo(50.5, 0.001));
    expect(posterior.credibleInterval.low, 10);
    expect(posterior.credibleInterval.high, 90);
    expect(placementProbabilityCorrect(50, 50), closeTo(0.5, 0.001));
  });

  test('one answer moves the estimate without pinning it', () {
    final cards = ladder();
    final hard = cards.firstWhere((card) => card.difficulty == 95);
    final easy = cards.firstWhere((card) => card.difficulty == 8);

    final raised = PlacementTestEngine().replay(cards, [
      PlacementAnswer(cardId: hard.id, known: true),
    ]);
    expect(raised.estimatedDifficulty, greaterThan(50.5));
    expect(raised.estimatedDifficulty, lessThan(80));

    final lowered = PlacementTestEngine().replay(cards, [
      PlacementAnswer(cardId: easy.id, known: false),
    ]);
    expect(lowered.estimatedDifficulty, lessThan(50.5));
    expect(lowered.estimatedDifficulty, greaterThan(25));
  });

  test('a beginner stays low and hard kanji are not marked known', () {
    final cards = ladder();
    final run = answerAll(cards, (card) => card.difficulty <= 25);
    final outcome = run.outcome();

    expect(run.answeredCount, inInclusiveRange(1, placementMaxQuestions));
    expect(outcome.estimatedDifficulty, lessThan(45));
    expect(outcome.estimatedDifficulty, greaterThan(8));
    expect(outcome.intervalLow, lessThanOrEqualTo(outcome.intervalHigh));
    expect(outcome.headline, anyOf(contains('N5'), contains('N4')));
    expect(outcome.headline, isNot(contains('N1')));

    final byId = {for (final card in cards) card.id: card};
    for (final id in outcome.knownCardIds) {
      expect(byId[id]!.difficulty, lessThanOrEqualTo(25));
    }
    final hardest = cards.last;
    expect(outcome.knownCardIds, isNot(contains(hardest.id)));
    expect(outcome.confirmCardIds, isNot(contains(hardest.id)));
    expect(outcome.confirmCardIds, isNotEmpty);
  });

  test('an intermediate estimate stays in the middle of the scale', () {
    final cards = ladder();
    final run = answerAll(cards, (card) {
      if (card.difficulty <= 35) return true;
      if (card.difficulty >= 65) return false;
      return card.difficulty.isEven;
    });
    final outcome = run.outcome();

    expect(outcome.estimatedDifficulty, inInclusiveRange(30, 70));
    expect(outcome.intervalHigh - outcome.intervalLow, greaterThan(5));
    expect(outcome.headline, isNot(contains('N1')));
    expect(outcome.headline, isNot(contains('N5')));
  });

  test('an advanced learner is not placed by a single hard success', () {
    final cards = ladder();
    final onlyHard = PlacementTestEngine().replay(cards, [
      PlacementAnswer(
        cardId: cards.firstWhere((card) => card.difficulty == 98).id,
        known: true,
      ),
    ]);
    expect(onlyHard.estimatedDifficulty, lessThan(80));

    final run = answerAll(cards, (card) => card.difficulty <= 80);
    expect(run.estimatedDifficulty, greaterThan(60));
    expect(run.estimatedDifficulty, lessThan(100));
    expect(run.outcome().headline, contains('N1'));
  });

  test('mixed answers move the estimate without erasing tested kanji', () {
    final cards = ladder();
    final missed = cards.firstWhere((card) => card.difficulty == 6);
    final claimed = cards.firstWhere((card) => card.difficulty == 92);
    final run = PlacementTestEngine().replay(cards, [
      for (final difficulty in [5, 12, 18, 40, 55])
        PlacementAnswer(
          cardId: cards.firstWhere((card) => card.difficulty == difficulty).id,
          known: true,
        ),
      PlacementAnswer(cardId: missed.id, known: false),
      for (final difficulty in [45, 70, 88])
        PlacementAnswer(
          cardId: cards.firstWhere((card) => card.difficulty == difficulty).id,
          known: false,
        ),
      PlacementAnswer(cardId: claimed.id, known: true),
    ]);
    final outcome = run.outcome();

    expect(outcome.estimatedDifficulty, inInclusiveRange(20, 80));
    expect(outcome.knownCardIds, contains(claimed.id));
    expect(outcome.knownCardIds, isNot(contains(missed.id)));
    expect(outcome.confirmCardIds, isNot(contains(missed.id)));
    expect(outcome.knownCardIds, isNot(contains(cards.last.id)));
  });

  test('the test never asks a 21st question', () {
    final cards = ladder();
    final run = answerAll(cards, (card) => card.difficulty.isEven);
    expect(run.answeredCount, lessThanOrEqualTo(20));
    expect(run.currentQuestion, isNull);

    final extra = cards.firstWhere(
      (card) => run.steps.every((step) => step.cardId != card.id),
    );
    run.record(PlacementAnswer(cardId: extra.id, known: true));
    expect(run.answeredCount, lessThanOrEqualTo(20));
    expect(run.steps, hasLength(run.answeredCount));
  });

  test('a higher maxQuestions still cannot exceed 20', () {
    final cards = ladder();
    final run = PlacementTestEngine(maxQuestions: 100).replay(cards, const []);
    var asked = 0;
    while (run.currentQuestion != null) {
      run.record(
        PlacementAnswer(cardId: run.currentQuestion!.id, known: false),
      );
      asked++;
    }
    expect(asked, lessThanOrEqualTo(placementMaxQuestions));
    expect(
      PlacementTestEngine(
        maxQuestions: 100,
      ).estimatedQuestionCount(cards.length),
      placementMaxQuestions,
    );
  });

  test('the same seed resumes on the same kanji', () {
    final cards = ladder();
    const engine = PlacementTestEngine(selectionSeed: 7);
    final first = engine.replay(cards, const []);
    final answers = <PlacementAnswer>[];
    for (var i = 0; i < 4; i++) {
      final question = first.currentQuestion!;
      final answer = PlacementAnswer(cardId: question.id, known: true);
      answers.add(answer);
      first.record(answer);
    }
    final pending = first.currentQuestion!;

    final resumed = engine.replay(cards, answers);
    expect(resumed.currentQuestion?.id, pending.id);
    expect(
      resumed.estimatedDifficulty,
      closeTo(first.estimatedDifficulty, 0.001),
    );
    expect(resumed.steps, hasLength(4));
  });

  test('different seeds can choose different kanji near a target', () {
    final cards = [
      for (var copy = 0; copy < 6; copy++)
        testCard('near-$copy', difficulty: 10, jlptLevel: JlptLevel.n5),
    ];
    final firstIds = {
      for (var seed = 1; seed <= 12; seed++)
        PlacementTestEngine(
          selectionSeed: seed,
        ).replay(cards, const []).currentQuestion?.id,
    };
    expect(firstIds.length, greaterThan(1));
  });

  test('a kanji with no difficulty is not asked', () {
    final cards = [
      testCard('blank', difficulty: 0),
      testCard('easy', difficulty: 4, jlptLevel: JlptLevel.n5),
    ];
    final run = PlacementTestEngine().replay(cards, const []);
    final asked = <String>[];
    while (run.currentQuestion != null) {
      asked.add(run.currentQuestion!.id);
      run.record(
        PlacementAnswer(cardId: run.currentQuestion!.id, known: false),
      );
    }
    expect(asked, ['easy']);
  });

  test('an empty pool is finished before it starts', () {
    final run = PlacementTestEngine().replay(const [], const []);
    expect(run.isFinished, isTrue);
    expect(run.outcome().nothingToPlace, isTrue);
    expect(run.outcome().knownCardIds, isEmpty);
  });

  test('the label follows the catalog, not equal JLPT slices', () {
    final cards = [
      for (var difficulty = 1; difficulty <= 8; difficulty++)
        testCard(
          'n5-$difficulty',
          difficulty: difficulty,
          jlptLevel: JlptLevel.n5,
        ),
      for (var difficulty = 9; difficulty <= 16; difficulty++)
        testCard(
          'n4-$difficulty',
          difficulty: difficulty,
          jlptLevel: JlptLevel.n4,
        ),
    ];
    final corpus = PlacementCorpus(cards);
    expect(corpus.positionFor(4), 4);
    expect(
      corpus.describe(estimatedDifficulty: 4, intervalHigh: 4).headline,
      "You're roughly mid N5",
    );
    expect(
      corpus.describe(estimatedDifficulty: 9, intervalHigh: 12).headline,
      "You're roughly early N4",
    );
    expect(
      corpus.describe(estimatedDifficulty: 4, intervalHigh: 12).detail,
      contains('N4'),
    );
  });
}

JlptLevel _levelFor(int difficulty) {
  if (difficulty <= 20) return JlptLevel.n5;
  if (difficulty <= 40) return JlptLevel.n4;
  if (difficulty <= 60) return JlptLevel.n3;
  if (difficulty <= 80) return JlptLevel.n2;
  return JlptLevel.n1;
}

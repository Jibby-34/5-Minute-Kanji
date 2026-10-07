import 'package:flutter_test/flutter_test.dart';
import 'package:fiveminutekanji/core/models/kanji_card.dart';
import 'package:fiveminutekanji/core/models/placement.dart';
import 'package:fiveminutekanji/data/hardcoded_kanji_repository.dart';
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
    PlacementSelfAssessment? assessment,
  }) {
    final run = PlacementTestEngine(
      selectionSeed: seed,
    ).replay(cards, const [], selfAssessment: assessment);
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

    final hardest = cards.last;
    expect(outcome.knownCardIds, isNot(contains(hardest.id)));
    expect(outcome.confirmCardIds, isEmpty);
    for (final id in outcome.knownCardIds) {
      final card = cards.firstWhere((card) => card.id == id);
      expect(card.difficulty, lessThanOrEqualTo(25));
    }
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
    // On this ladder, difficulty 80 is the end of N2. The label follows
    // the kanji we are willing to skip, which stays inside that level.
    expect(run.outcome().headline, contains('N2'));
    for (final card in cards.where((card) => card.jlptLevel == JlptLevel.n1)) {
      expect(run.outcome().knownCardIds, isNot(contains(card.id)));
    }
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
    expect(outcome.knownCardIds, isNot(contains(cards.last.id)));
  });

  test('the known set follows difficulty, not JLPT level', () {
    final cards = [
      testCard('n5-hard', difficulty: 90, jlptLevel: JlptLevel.n5),
      testCard('n5-easy', difficulty: 80, jlptLevel: JlptLevel.n5),
      testCard('n4-001', difficulty: 40, jlptLevel: JlptLevel.n4),
      testCard('n4-002', difficulty: 41, jlptLevel: JlptLevel.n4),
      testCard('n4-003', difficulty: 42, jlptLevel: JlptLevel.n4),
      testCard('n1-easy', difficulty: 1, jlptLevel: JlptLevel.n1),
      testCard('n1-also', difficulty: 2, jlptLevel: JlptLevel.n1),
    ];
    // This helper still turns a position into a JLPT prefix for labels.
    // The outcome below does not use it when deciding which kanji are known.
    final before = PlacementCorpus(cards).idsKnownBefore(50);
    expect(before, containsAll(['n5-hard', 'n5-easy', 'n4-001', 'n4-002']));
    expect(before, isNot(contains('n1-easy')));
    expect(before, isNot(contains('n4-003')));

    final run = PlacementTestEngine().replay(cards, [
      PlacementAnswer(cardId: 'n5-hard', known: false),
      PlacementAnswer(cardId: 'n1-easy', known: true),
    ]);
    final known = run.outcome().knownCardIds;
    expect(known, isNot(contains('n5-hard')));
    expect(known, contains('n1-easy'));
    expect(known, contains('n1-also'));
    expect(known, isNot(contains('n5-easy')));
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

  test('the self-assessment slices overlap by position, not raw thirds', () {
    final cards = ladder();
    final beginner = placementBandFor(cards, PlacementSelfAssessment.beginner)!;
    final intermediate = placementBandFor(
      cards,
      PlacementSelfAssessment.intermediate,
    )!;
    final expert = placementBandFor(cards, PlacementSelfAssessment.expert)!;

    expect(beginner.high, greaterThanOrEqualTo(intermediate.low));
    expect(intermediate.high, greaterThanOrEqualTo(expert.low));
    expect(beginner.center, lessThan(intermediate.center));
    expect(intermediate.center, lessThan(expert.center));
    expect(placementBandFor(cards, PlacementSelfAssessment.newUser), isNull);

    // Four kanji with a gap. 35% of the list is the second card, not
    // difficulty 35.
    final gapped = [
      testCard('a', difficulty: 1),
      testCard('b', difficulty: 2),
      testCard('c', difficulty: 3),
      testCard('d', difficulty: 100),
    ];
    final early = placementBandFor(gapped, PlacementSelfAssessment.beginner)!;
    expect(early.high, 2);
    expect(early.low, 1);
  });

  test('the starting bell sits in the slice and still has a tail', () {
    final cards = ladder();
    for (final assessment in [
      PlacementSelfAssessment.beginner,
      PlacementSelfAssessment.intermediate,
      PlacementSelfAssessment.expert,
    ]) {
      final band = placementBandFor(cards, assessment)!;
      final posterior = PlacementPosterior.centered(
        band.center,
        spread: placementSelfAssessmentSpreadFor(band),
      );
      var inside = 0.0;
      var outside = 0.0;
      final weights = posterior.weights;
      for (var index = 0; index < weights.length; index++) {
        final position = index + placementMinDifficulty;
        if (position >= band.low && position <= band.high) {
          inside += weights[index];
        } else {
          outside += weights[index];
        }
      }
      expect(inside, greaterThan(outside));
      expect(outside, greaterThan(0.05));
      expect(posterior.mean, closeTo(band.center, 12));
    }

    final beginner = PlacementTestEngine().replay(
      cards,
      const [],
      selfAssessment: PlacementSelfAssessment.beginner,
    );
    final intermediate = PlacementTestEngine().replay(
      cards,
      const [],
      selfAssessment: PlacementSelfAssessment.intermediate,
    );
    final expert = PlacementTestEngine().replay(
      cards,
      const [],
      selfAssessment: PlacementSelfAssessment.expert,
    );
    expect(
      beginner.estimatedDifficulty,
      lessThan(intermediate.estimatedDifficulty),
    );
    expect(
      intermediate.estimatedDifficulty,
      lessThan(expert.estimatedDifficulty),
    );
  });

  test('opening questions come from the selected slice', () {
    final cards = ladder();
    final cases = {
      PlacementSelfAssessment.beginner: placementBandFor(
        cards,
        PlacementSelfAssessment.beginner,
      )!,
      PlacementSelfAssessment.intermediate: placementBandFor(
        cards,
        PlacementSelfAssessment.intermediate,
      )!,
      PlacementSelfAssessment.expert: placementBandFor(
        cards,
        PlacementSelfAssessment.expert,
      )!,
    };

    for (final entry in cases.entries) {
      final run = PlacementTestEngine(
        selectionSeed: 4,
      ).replay(cards, const [], selfAssessment: entry.key);
      final opening = <int>[];
      for (var n = 0; n < 3; n++) {
        final question = run.currentQuestion!;
        opening.add(question.difficulty);
        run.record(PlacementAnswer(cardId: question.id, known: false));
      }
      for (final difficulty in opening) {
        expect(difficulty, greaterThanOrEqualTo(entry.value.low));
        expect(difficulty, lessThanOrEqualTo(entry.value.high));
      }
    }

    final beginner = cases[PlacementSelfAssessment.beginner]!;
    expect(beginner.high, lessThan(50));
    final expert = cases[PlacementSelfAssessment.expert]!;
    expect(expert.low, greaterThan(40));
  });

  test('a strong performance can leave the starting slice', () {
    final cards = ladder();
    final beginner = placementBandFor(cards, PlacementSelfAssessment.beginner)!;
    final climbed = answerAll(
      cards,
      (card) => true,
      assessment: PlacementSelfAssessment.beginner,
    );
    expect(climbed.answeredCount, lessThanOrEqualTo(placementMaxQuestions));
    expect(
      climbed.steps.any((step) => step.difficulty > beginner.high),
      isTrue,
    );
    expect(climbed.estimatedDifficulty, greaterThan(beginner.high + 15));

    final intermediate = placementBandFor(
      cards,
      PlacementSelfAssessment.intermediate,
    )!;
    final rose = answerAll(
      cards,
      (card) => true,
      assessment: PlacementSelfAssessment.intermediate,
    );
    expect(rose.estimatedDifficulty, greaterThan(intermediate.center + 15));
    expect(
      rose.steps.any((step) => step.difficulty > intermediate.high),
      isTrue,
    );
  });

  test('a weak performance can fall below the starting slice', () {
    final cards = ladder();
    final expert = placementBandFor(cards, PlacementSelfAssessment.expert)!;
    final fell = answerAll(
      cards,
      (card) => false,
      assessment: PlacementSelfAssessment.expert,
    );
    expect(fell.answeredCount, lessThanOrEqualTo(placementMaxQuestions));
    expect(fell.steps.any((step) => step.difficulty < expert.low), isTrue);
    expect(fell.estimatedDifficulty, lessThan(expert.low - 10));
    expect(fell.outcome().knownCardIds, isNot(contains(cards.last.id)));

    final intermediate = placementBandFor(
      cards,
      PlacementSelfAssessment.intermediate,
    )!;
    final dropped = answerAll(
      cards,
      (card) => false,
      assessment: PlacementSelfAssessment.intermediate,
    );
    expect(dropped.estimatedDifficulty, lessThan(intermediate.center - 10));
    expect(
      dropped.steps.any((step) => step.difficulty < intermediate.low),
      isTrue,
    );

    final excelled = answerAll(
      cards,
      (card) => true,
      assessment: PlacementSelfAssessment.intermediate,
    );
    expect(
      dropped.estimatedDifficulty,
      lessThan(excelled.estimatedDifficulty - 25),
    );
    expect(
      dropped.outcome().knownCardIds.length,
      lessThan(excelled.outcome().knownCardIds.length),
    );
    for (final step in dropped.steps) {
      expect(dropped.outcome().knownCardIds, isNot(contains(step.cardId)));
    }
  });

  test('the real catalog opens inside each slice and can leave it', () async {
    final cards = await const HardcodedKanjiRepository().getAll();
    for (final assessment in const [
      PlacementSelfAssessment.beginner,
      PlacementSelfAssessment.intermediate,
      PlacementSelfAssessment.expert,
    ]) {
      final band = placementBandFor(cards, assessment)!;
      final opening = PlacementTestEngine(
        selectionSeed: 3,
      ).replay(cards, const [], selfAssessment: assessment);
      final question = opening.currentQuestion!;
      expect(question.difficulty, inInclusiveRange(band.low, band.high));
    }

    final beginner = placementBandFor(cards, PlacementSelfAssessment.beginner)!;
    final climbed = answerAll(
      cards,
      (card) => true,
      assessment: PlacementSelfAssessment.beginner,
    );
    expect(climbed.answeredCount, lessThanOrEqualTo(placementMaxQuestions));
    expect(
      climbed.steps.any((step) => step.difficulty > beginner.high),
      isTrue,
    );
    expect(climbed.estimatedDifficulty, greaterThan(beginner.center + 10));

    final expert = placementBandFor(cards, PlacementSelfAssessment.expert)!;
    final fell = answerAll(
      cards,
      (card) => false,
      assessment: PlacementSelfAssessment.expert,
    );
    expect(fell.steps.any((step) => step.difficulty < expert.low), isTrue);
    expect(fell.estimatedDifficulty, lessThan(expert.center - 10));
    final hardest = placementRanked(cards).last;
    expect(fell.outcome().knownCardIds, isNot(contains(hardest.id)));
  });

  test(
    'the known set does not skip kanji above the demonstrated level',
    () async {
      final cards = await const HardcodedKanjiRepository().getAll();
      final cases = <(int, PlacementSelfAssessment)>[
        (10, PlacementSelfAssessment.beginner),
        (35, PlacementSelfAssessment.intermediate),
        (80, PlacementSelfAssessment.expert),
      ];
      for (final (truth, assessment) in cases) {
        final run = answerAll(
          cards,
          (card) => card.difficulty <= truth,
          assessment: assessment,
        );
        final known = run.outcome().knownCardIds.toSet();
        expect(known, isNotEmpty);
        var lowestMiss = placementMaxDifficulty + 1;
        for (final step in run.steps) {
          if (step.correct) {
            expect(known, contains(step.cardId));
          } else {
            expect(known, isNot(contains(step.cardId)));
            if (step.difficulty < lowestMiss) lowestMiss = step.difficulty;
          }
        }
        for (final card in cards) {
          if (!known.contains(card.id)) continue;
          final claimed = run.steps.any(
            (step) => step.cardId == card.id && step.correct,
          );
          if (claimed) continue;
          expect(card.difficulty, lessThan(lowestMiss));
          expect(card.difficulty, lessThanOrEqualTo(truth));
        }
      }

      final overclaimed = answerAll(
        cards,
        (card) => card.difficulty <= 10,
        assessment: PlacementSelfAssessment.expert,
      );
      final extra = cards.where(
        (card) =>
            overclaimed.outcome().knownCardIds.contains(card.id) &&
            card.difficulty > 10,
      );
      expect(extra.length, lessThan(80));
    },
  );

  test('the same self-assessment resumes on the same kanji', () {
    final cards = ladder();
    const engine = PlacementTestEngine(selectionSeed: 7);
    final first = engine.replay(
      cards,
      const [],
      selfAssessment: PlacementSelfAssessment.beginner,
    );
    final answers = <PlacementAnswer>[];
    for (var i = 0; i < 4; i++) {
      final question = first.currentQuestion!;
      final answer = PlacementAnswer(cardId: question.id, known: true);
      answers.add(answer);
      first.record(answer);
    }
    final pending = first.currentQuestion!;
    final resumed = engine.replay(
      cards,
      answers,
      selfAssessment: PlacementSelfAssessment.beginner,
    );
    expect(resumed.currentQuestion?.id, pending.id);
    expect(
      resumed.estimatedDifficulty,
      closeTo(first.estimatedDifficulty, 0.001),
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

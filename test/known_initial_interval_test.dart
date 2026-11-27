import 'package:flutter_test/flutter_test.dart';

import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/placement.dart';
import 'package:fiveminutekanji/core/models/review.dart';
import 'package:fiveminutekanji/services/initial_known_card_schedule.dart';
import 'package:fiveminutekanji/services/mark_as_known.dart';
import 'package:fiveminutekanji/services/placement_service.dart';
import 'package:fiveminutekanji/services/srs_engine.dart';

import 'support/fakes.dart';

void main() {
  final now = DateTime(2026, 9, 2, 8);
  const engine = SrsEngine();

  List<int> flat(int count, int difficulty) {
    return List<int>.filled(count, difficulty);
  }

  test('an advanced user waits longer than a beginner for the same kanji', () {
    final known = flat(40, 50);
    const id = 'n5-040';

    final beginner = calculateProficiencyAdjustedKnownInterval(
      kanjiId: id,
      difficulty: 50,
      knownDifficulties: known,
      proficiency: KnownIntervalProficiency.beginner,
    );
    final advanced = calculateProficiencyAdjustedKnownInterval(
      kanjiId: id,
      difficulty: 50,
      knownDifficulties: known,
      proficiency: KnownIntervalProficiency.advanced,
    );

    expect(
      knownRelativeDifficultyMultiplier(
        difficulty: 50,
        knownDifficulties: known,
      ),
      closeTo(knownMultiplierAverage, 0.001),
    );
    expect(advanced.inDays, greaterThan(beginner.inDays));
    expect(
      advanced.inDays - beginner.inDays,
      greaterThanOrEqualTo(
        knownIntervalAdvancedDays -
            knownIntervalBeginnerDays -
            knownIntervalScatterMaxDays -
            knownIntervalScatterRadius(knownIntervalBeginnerDays),
      ),
    );
    expect(
      proficiencyFromEstimatedDifficulty(10),
      KnownIntervalProficiency.beginner,
    );
    expect(
      proficiencyFromEstimatedDifficulty(40),
      KnownIntervalProficiency.intermediate,
    );
    expect(
      proficiencyFromEstimatedDifficulty(60),
      KnownIntervalProficiency.advanced,
    );
    expect(
      proficiencyFromEstimatedDifficulty(90),
      KnownIntervalProficiency.expert,
    );
    expect(
      proficiencyFromPlacement(
        estimatedDifficulty: 90,
        selfAssessment: PlacementSelfAssessment.beginner,
      ),
      KnownIntervalProficiency.expert,
    );
    expect(
      proficiencyFromPlacement(selfAssessment: PlacementSelfAssessment.newUser),
      KnownIntervalProficiency.beginner,
    );
    expect(proficiencyFromPlacement(), KnownIntervalProficiency.advanced);
  });

  test(
    'an easier kanji waits longer than a harder kanji for the same user',
    () {
      final known = [...flat(60, 50), 10, 90];
      final easyMultiplier = knownRelativeDifficultyMultiplier(
        difficulty: 10,
        knownDifficulties: known,
      );
      final hardMultiplier = knownRelativeDifficultyMultiplier(
        difficulty: 90,
        knownDifficulties: known,
      );
      final midpoint = knownRelativeDifficultyMultiplier(
        difficulty: 35,
        knownDifficulties: [...flat(80, 50), 35],
      );
      final average = knownRelativeDifficultyMultiplier(
        difficulty: 50,
        knownDifficulties: flat(80, 50),
      );

      expect(easyMultiplier, greaterThan(knownMultiplierEasier));
      expect(hardMultiplier, lessThan(knownMultiplierHarder));
      expect(midpoint, greaterThan(average));
      expect(midpoint, lessThan(easyMultiplier));

      final easy = calculateProficiencyAdjustedKnownInterval(
        kanjiId: 'easy',
        difficulty: 10,
        knownDifficulties: known,
        proficiency: KnownIntervalProficiency.advanced,
      );
      final hard = calculateProficiencyAdjustedKnownInterval(
        kanjiId: 'hard',
        difficulty: 90,
        knownDifficulties: known,
        proficiency: KnownIntervalProficiency.advanced,
      );
      expect(easy.inDays, greaterThan(hard.inDays + 20));

      final forward = calculateProficiencyAdjustedKnownInterval(
        kanjiId: 'mid',
        difficulty: 40,
        knownDifficulties: [10, 40, 70],
        proficiency: KnownIntervalProficiency.intermediate,
      );
      final reversed = calculateProficiencyAdjustedKnownInterval(
        kanjiId: 'mid',
        difficulty: 40,
        knownDifficulties: [70, 10, 40],
        proficiency: KnownIntervalProficiency.intermediate,
      );
      expect(forward, reversed);
    },
  );

  test('a kanji near the user average gets about the level base interval', () {
    final known = [...flat(40, 50), 51];
    final multiplier = knownRelativeDifficultyMultiplier(
      difficulty: 51,
      knownDifficulties: known,
    );
    final interval = calculateProficiencyAdjustedKnownInterval(
      kanjiId: 'near',
      difficulty: 51,
      knownDifficulties: known,
      proficiency: KnownIntervalProficiency.intermediate,
    );

    expect(multiplier, closeTo(knownMultiplierAverage, 0.05));
    expect(
      (interval.inDays - knownIntervalIntermediateDays).abs(),
      lessThanOrEqualTo(knownIntervalScatterMaxDays),
    );
    expect(interval, Duration(days: interval.inDays));
  });

  test('a very small known set does not produce an extreme multiplier', () {
    final easy = knownRelativeDifficultyMultiplier(
      difficulty: 1,
      knownDifficulties: const [1, 100],
    );
    final hard = knownRelativeDifficultyMultiplier(
      difficulty: 100,
      knownDifficulties: const [1, 100],
    );
    final oneSample = knownRelativeDifficultyMultiplier(
      difficulty: 100,
      knownDifficulties: const [1],
    );

    expect(easy, greaterThan(knownMultiplierAverage));
    expect(easy, lessThan(knownMultiplierEasier));
    expect(hard, lessThan(knownMultiplierAverage));
    expect(hard, greaterThan(knownMultiplierHarder));
    expect(oneSample, greaterThan(knownMultiplierHarder));
    expect(oneSample, lessThan(knownMultiplierAverage));

    final lone = calculateProficiencyAdjustedKnownInterval(
      kanjiId: 'only',
      difficulty: 5,
      knownDifficulties: const [5],
      proficiency: KnownIntervalProficiency.beginner,
    );
    expect(
      (lone.inDays - knownIntervalBeginnerDays).abs(),
      lessThanOrEqualTo(knownIntervalScatterRadius(knownIntervalBeginnerDays)),
    );
  });

  test('an empty known set falls back to the level base interval', () {
    expect(
      knownRelativeDifficultyMultiplier(
        difficulty: 100,
        knownDifficulties: const [],
      ),
      knownMultiplierAverage,
    );
    expect(
      knownRelativeDifficultyMultiplier(
        difficulty: 100,
        knownDifficulties: const [0, -4],
      ),
      knownMultiplierAverage,
    );

    final interval = calculateProficiencyAdjustedKnownInterval(
      kanjiId: 'empty',
      difficulty: 100,
      knownDifficulties: const [],
      proficiency: KnownIntervalProficiency.beginner,
    );
    expect(
      (interval.inDays - knownIntervalBeginnerDays).abs(),
      lessThanOrEqualTo(knownIntervalScatterRadius(knownIntervalBeginnerDays)),
    );
    expect(
      interval.inDays,
      inInclusiveRange(knownIntervalMinDays, knownIntervalMaxDays),
    );
  });

  test(
    'manual selection and the placement test both use the new interval',
    () async {
      final baseline = [
        for (var i = 0; i < 24; i++) testCard('b$i', difficulty: 40),
      ];
      final easy = testCard('easy', difficulty: 10);
      final hard = testCard('hard', difficulty: 80);
      final extra = testCard('extra', difficulty: 40);
      final kept = testCard('kept', difficulty: 40);
      final cards = [...baseline, easy, hard, extra, kept];
      final progress = MemoryProgressRepository();
      await progress.seedIfNeeded(
        cards.map((card) => card.id).toList(),
        now: now,
      );
      final established = CardSchedule(
        cardId: 'kept',
        state: CardLearningState.review,
        reviewCount: 5,
        correctCount: 5,
        incorrectCount: 0,
        dueAt: now.add(const Duration(days: 12)),
        interval: const Duration(days: 12),
        ease: 2.5,
        lastReviewedAt: now,
        consecutiveGoodCount: 5,
      );
      await progress.saveSchedule(established);
      await progress.savePlacement(
        const PlacementProgress(
          completed: true,
          selfAssessment: PlacementSelfAssessment.intermediate,
        ),
      );

      final manual = MarkAsKnownService(
        progressRepository: progress,
        srsEngine: engine,
        kanjiRepository: FakeKanjiRepository(cards),
        clock: () => now,
      );
      final manualIds = [...baseline.map((card) => card.id), 'easy', 'hard'];
      await manual.markKanjiAsKnownAll(manualIds, now: now);

      final manualDifficulties = [
        for (final card in [...baseline, easy, hard]) card.difficulty,
      ];
      expect(
        (await progress.getSchedule('easy'))!.interval,
        calculateProficiencyAdjustedKnownInterval(
          kanjiId: 'easy',
          difficulty: easy.difficulty,
          knownDifficulties: manualDifficulties,
          proficiency: KnownIntervalProficiency.intermediate,
        ),
      );
      expect(
        (await progress.getSchedule('easy'))!.interval.inDays,
        greaterThan((await progress.getSchedule('hard'))!.interval.inDays),
      );
      expect(
        (await progress.getSchedule('kept'))!.interval,
        established.interval,
      );
      expect((await progress.getSchedule('kept'))!.reviewCount, 5);
      expect((await progress.getSchedule('easy'))!.introducedAsKnown, isTrue);

      final placed = MemoryProgressRepository();
      final placedCards = [...baseline, extra];
      await placed.seedIfNeeded(
        placedCards.map((card) => card.id).toList(),
        now: now,
      );
      await placed.savePlacement(
        const PlacementProgress(
          selfAssessment: PlacementSelfAssessment.beginner,
        ),
      );
      final placedMarker = MarkAsKnownService(
        progressRepository: placed,
        srsEngine: engine,
        kanjiRepository: FakeKanjiRepository(placedCards),
        clock: () => now,
      );
      await PlacementService(
        kanjiRepository: FakeKanjiRepository(placedCards),
        progressRepository: placed,
        markAsKnown: placedMarker,
        clock: () => now,
      ).complete(
        PlacementOutcome(
          knownCardIds: baseline.map((card) => card.id).toList(),
          answeredCount: 12,
          estimatedDifficulty: 90,
        ),
      );

      final placedDifficulties = [for (final card in baseline) card.difficulty];
      expect((await placed.getPlacement()).estimatedDifficulty, 90);
      expect(
        (await placed.getSchedule('b0'))!.interval,
        calculateProficiencyAdjustedKnownInterval(
          kanjiId: 'b0',
          difficulty: 40,
          knownDifficulties: placedDifficulties,
          proficiency: KnownIntervalProficiency.expert,
        ),
      );
      expect(
        (await placed.getSchedule('b0'))!.interval.inDays,
        greaterThan(
          calculateProficiencyAdjustedKnownInterval(
            kanjiId: 'b0',
            difficulty: 40,
            knownDifficulties: placedDifficulties,
            proficiency: KnownIntervalProficiency.beginner,
          ).inDays,
        ),
      );

      await placedMarker.markKanjiAsKnown('extra', now: now);
      expect(
        (await placed.getSchedule('extra'))!.interval,
        calculateProficiencyAdjustedKnownInterval(
          kanjiId: 'extra',
          difficulty: 40,
          knownDifficulties: [...placedDifficulties, extra.difficulty],
          proficiency: KnownIntervalProficiency.expert,
        ),
      );

      final unscored = MemoryProgressRepository();
      await unscored.seedIfNeeded(const ['blank'], now: now);
      await MarkAsKnownService(
        progressRepository: unscored,
        srsEngine: engine,
        kanjiRepository: FakeKanjiRepository([testCard('blank')]),
        clock: () => now,
      ).markKanjiAsKnown('blank', now: now);
      expect(
        (await unscored.getSchedule('blank'))!.interval,
        calculateInitialKnownCardSchedule('blank'),
      );

      final restored = PlacementProgress.fromJson(
        const PlacementProgress(
          completed: true,
          selfAssessment: PlacementSelfAssessment.intermediate,
          estimatedDifficulty: 62.5,
        ).toJson(),
      );
      expect(restored.estimatedDifficulty, 62.5);
      expect(
        PlacementProgress.fromJson(const {
          'estimatedDifficulty': 0,
        }).estimatedDifficulty,
        isNull,
      );
    },
  );

  test('Again and Good still use the existing SRS intervals', () {
    final initial = calculateProficiencyAdjustedKnownInterval(
      kanjiId: 'reviewed',
      difficulty: 40,
      knownDifficulties: flat(30, 40),
      proficiency: KnownIntervalProficiency.beginner,
    );
    final known = engine.markAsKnown(
      current: CardSchedule.fresh('reviewed', now),
      now: now,
      interval: initial,
    );
    final later = now.add(initial);

    final good = engine.schedule(
      current: known,
      result: ReviewResult.good,
      now: later,
    );
    final scaled = (initial.inSeconds * SrsEngine.defaultEase).round();
    final minimum = SrsEngine.graduatingInterval.inSeconds;
    final expectedGood = Duration(seconds: scaled < minimum ? minimum : scaled);
    expect(good.interval, expectedGood);
    expect(
      good.interval.inSeconds,
      greaterThan(SrsEngine.graduatingInterval.inSeconds),
    );
    expect(good.interval, isNot(initial));
    expect(good.reviewCount, 1);
    expect(good.consecutiveGoodCount, 1);
    expect(good.introducedAsKnown, isTrue);

    final again = engine.schedule(
      current: known,
      result: ReviewResult.again,
      now: later,
    );
    expect(again.interval, SrsEngine.againInterval);
    expect(again.dueAt, later.add(SrsEngine.againInterval));
    expect(again.state, CardLearningState.learning);
    expect(again.introducedAsKnown, isTrue);

    final roundTrip = CardSchedule.fromJson(known.toJson());
    expect(roundTrip!.introducedAsKnown, isTrue);
    expect(roundTrip.interval, initial);
  });

  test('a large known set still scatters due days around its own interval', () {
    const count = 80;
    final ids = [
      for (var i = 0; i < count; i++) 'k${i.toString().padLeft(3, '0')}',
    ];
    final difficulties = flat(count, 50);
    final days = [
      for (final id in ids)
        calculateProficiencyAdjustedKnownInterval(
          kanjiId: id,
          difficulty: 50,
          knownDifficulties: difficulties,
          proficiency: KnownIntervalProficiency.advanced,
        ).inDays,
    ];
    final radius = knownIntervalScatterRadius(knownIntervalAdvancedDays);
    final lowest = days.reduce((a, b) => a < b ? a : b);
    final highest = days.reduce((a, b) => a > b ? a : b);

    expect(days.toSet().length, greaterThanOrEqualTo(5));
    expect(days.toSet(), isNot(equals({knownIntervalAdvancedDays})));
    expect(
      days.every((day) => (day - knownIntervalAdvancedDays).abs() <= radius),
      isTrue,
    );
    expect(highest - lowest, lessThanOrEqualTo(radius * 2));
    expect(
      highest - lowest,
      lessThan(knownIntervalAdvancedDays - knownIntervalBeginnerDays),
    );

    for (final id in ids) {
      final beginner = calculateProficiencyAdjustedKnownInterval(
        kanjiId: id,
        difficulty: 50,
        knownDifficulties: difficulties,
        proficiency: KnownIntervalProficiency.beginner,
      );
      final advanced = calculateProficiencyAdjustedKnownInterval(
        kanjiId: id,
        difficulty: 50,
        knownDifficulties: difficulties,
        proficiency: KnownIntervalProficiency.advanced,
      );
      expect(advanced.inDays, greaterThan(beginner.inDays));
    }
  });
}

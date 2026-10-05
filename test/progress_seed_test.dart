import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/daily_session_plan.dart';
import 'package:fiveminutekanji/core/models/placement.dart';
import 'package:fiveminutekanji/core/models/progress.dart';
import 'package:fiveminutekanji/core/models/review.dart';
import 'package:fiveminutekanji/data/hardcoded_kanji_repository.dart';
import 'package:fiveminutekanji/data/legacy_kanji_id_remap.dart';
import 'package:fiveminutekanji/data/shared_prefs_progress_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('first launch seeds every card as new and due now', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final progress = SharedPrefsProgressRepository(prefs);
    const kanji = HardcodedKanjiRepository();
    final cards = await kanji.getAll();

    await progress.seedIfNeeded(cards.map((card) => card.id).toList());

    final schedules = await progress.getSchedules();
    expect(schedules.length, cards.length);
    expect(
      schedules.values.every(
        (schedule) => schedule.state == CardLearningState.newCard,
      ),
      isTrue,
    );
    expect(
      schedules.values.every((schedule) => schedule.isDueAt(DateTime.now())),
      isTrue,
    );
  });

  test('corrupt local data is ignored and can be re-seeded', () async {
    SharedPreferences.setMockInitialValues({'progress_v1': '{not-json'});
    final prefs = await SharedPreferences.getInstance();
    final progress = SharedPrefsProgressRepository(prefs);

    await progress.seedIfNeeded(const ['rtk_001', 'rtk_002']);

    final schedules = await progress.getSchedules();
    expect(schedules.keys, containsAll(['rtk_001', 'rtk_002']));
  });

  test('seed does not overwrite an existing schedule', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final progress = SharedPrefsProgressRepository(prefs);
    final later = DateTime.now().add(const Duration(days: 3));

    await progress.saveSchedule(
      CardSchedule(
        cardId: 'rtk_001',
        state: CardLearningState.review,
        reviewCount: 4,
        correctCount: 4,
        incorrectCount: 0,
        dueAt: later,
        interval: const Duration(days: 3),
        ease: 2.5,
      ),
    );

    await progress.seedIfNeeded(const ['rtk_001', 'rtk_002']);
    final existing = await progress.getSchedule('rtk_001');
    expect(existing?.state, CardLearningState.review);
    expect(existing?.reviewCount, 4);
    expect(
      (await progress.getSchedule('rtk_002'))?.state,
      CardLearningState.newCard,
    );
  });

  test('legacy ids follow the character and are not remapped twice', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final progress = SharedPrefsProgressRepository(prefs);
    final later = DateTime.utc(2026, 1, 15);
    const kanji = HardcodedKanjiRepository();
    final cards = await kanji.getAll();
    final ids = cards.map((card) => card.id).toSet();

    // n5-002 used to be 二, which is n5-009 now. n5-081 is not in the new list.
    expect(legacyKanjiIdRemap['n5-002'], 'n5-009');
    expect(ids.contains('n5-081'), isFalse);
    expect(legacyKanjiIdRemap.containsKey('n5-081'), isTrue);

    await progress.saveSchedule(
      CardSchedule(
        cardId: 'n5-002',
        state: CardLearningState.review,
        reviewCount: 4,
        correctCount: 4,
        incorrectCount: 0,
        dueAt: later,
        interval: const Duration(days: 4),
        ease: 2.5,
      ),
    );
    await progress.saveSchedule(
      CardSchedule(
        cardId: 'n5-081',
        state: CardLearningState.learning,
        reviewCount: 1,
        correctCount: 0,
        incorrectCount: 1,
        dueAt: later,
        interval: const Duration(minutes: 10),
        ease: 2.5,
      ),
    );
    await progress.addHistory(
      ReviewHistoryEntry(
        cardId: 'n5-002',
        rating: ReviewResult.good,
        timestamp: later,
        timeOnCard: const Duration(seconds: 3),
      ),
    );
    await progress.saveDailySessionPlan(
      DailySessionPlan(
        studyDate: later,
        budgetMinutes: 5,
        newKanjiPerDay: 3,
        cardIds: const ['n5-002', 'n5-081'],
      ),
    );
    await progress.savePlacement(
      const PlacementProgress(
        completed: false,
        answers: [PlacementAnswer(cardId: 'n5-002', known: true)],
      ),
    );

    await progress.seedIfNeeded(cards.map((card) => card.id).toList());

    final moved = await progress.getSchedule('n5-009');
    expect(moved?.state, CardLearningState.review);
    expect(moved?.reviewCount, 4);
    expect(moved?.dueAt, later);

    final orphanTarget = legacyKanjiIdRemap['n5-081']!;
    expect((await progress.getSchedule(orphanTarget))?.reviewCount, 1);
    expect(await progress.getSchedule('n5-081'), isNull);

    // The id n5-002 now belongs to a different kanji, so it is a new card.
    expect(
      (await progress.getSchedule('n5-002'))?.state,
      CardLearningState.newCard,
    );
    expect((await progress.getSchedule('n5-002'))?.reviewCount, 0);

    expect((await progress.getHistory()).single.cardId, 'n5-009');
    expect((await progress.getDailySessionPlan()).cardIds, [
      'n5-009',
      orphanTarget,
    ]);
    final placement = await progress.getPlacement();
    expect(placement.completed, isFalse);
    expect(placement.answers, isEmpty);
    expect((await progress.getSchedules()).length, cards.length);

    final restarted = SharedPrefsProgressRepository(prefs);
    await restarted.seedIfNeeded(cards.map((card) => card.id).toList());
    expect((await restarted.getSchedule('n5-009'))?.reviewCount, 4);
    expect((await restarted.getSchedule('n5-002'))?.reviewCount, 0);
  });

  test('progress seeded from the current catalog is not remapped', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final progress = SharedPrefsProgressRepository(prefs);
    const kanji = HardcodedKanjiRepository();
    final cards = await kanji.getAll();
    final later = DateTime.utc(2026, 3, 1);

    await progress.seedIfNeeded(cards.map((card) => card.id).toList());
    await progress.saveSchedule(
      CardSchedule(
        cardId: 'n5-002',
        state: CardLearningState.review,
        reviewCount: 6,
        correctCount: 6,
        incorrectCount: 0,
        dueAt: later,
        interval: const Duration(days: 6),
        ease: 2.5,
      ),
    );

    final restarted = SharedPrefsProgressRepository(prefs);
    await restarted.seedIfNeeded(cards.map((card) => card.id).toList());

    expect((await restarted.getSchedule('n5-002'))?.reviewCount, 6);
    expect(
      (await restarted.getSchedule('n5-009'))?.state,
      CardLearningState.newCard,
    );
    expect((await restarted.getSchedule('n5-009'))?.reviewCount, 0);
  });
}

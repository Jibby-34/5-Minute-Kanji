import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/data/hardcoded_kanji_repository.dart';
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
}

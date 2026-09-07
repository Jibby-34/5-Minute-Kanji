import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/review.dart';
import 'package:fiveminutekanji/data/shared_prefs_progress_repository.dart';
import 'package:fiveminutekanji/services/srs_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const engine = SrsEngine();
  final now = DateTime(2026, 9, 2, 8, 0, 0);

  Future<SharedPreferencesProgressFixture> fixture() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return SharedPreferencesProgressFixture(prefs);
  }

  test(
    'Good persists a later due date that survives a new repository',
    () async {
      final env = await fixture();
      final first = SharedPrefsProgressRepository(env.prefs);
      await first.seedIfNeeded(const ['rtk_001'], now: now);

      final updated = engine.schedule(
        current: (await first.getSchedule('rtk_001'))!,
        result: ReviewResult.good,
        now: now,
      );
      await first.saveSchedule(updated);

      final restarted = SharedPrefsProgressRepository(env.prefs);
      final loaded = await restarted.getSchedule('rtk_001');

      expect(loaded, isNotNull);
      expect(loaded!.cardId, 'rtk_001');
      expect(loaded.state, CardLearningState.review);
      expect(loaded.dueAt, now.add(SrsEngine.graduatingInterval));
      expect(loaded.interval, SrsEngine.graduatingInterval);
      expect(loaded.reviewCount, 1);
      expect(loaded.correctCount, 1);
      expect(loaded.incorrectCount, 0);
      expect(loaded.lastReviewedAt, now);
      expect(loaded.consecutiveGoodCount, 1);
      expect(loaded.isDueAt(now), isFalse);
      expect(loaded.isDueAt(now.add(const Duration(hours: 23))), isFalse);
      expect(loaded.isDueAt(now.add(SrsEngine.graduatingInterval)), isTrue);
    },
  );

  test('Again persists a much sooner due date across restart', () async {
    final env = await fixture();
    final first = SharedPrefsProgressRepository(env.prefs);
    await first.seedIfNeeded(const ['rtk_001'], now: now);

    final updated = engine.schedule(
      current: (await first.getSchedule('rtk_001'))!,
      result: ReviewResult.again,
      now: now,
    );
    await first.saveSchedule(updated);

    final restarted = SharedPrefsProgressRepository(env.prefs);
    final loaded = await restarted.getSchedule('rtk_001');

    expect(loaded!.state, CardLearningState.learning);
    expect(loaded.dueAt, now.add(SrsEngine.againInterval));
    expect(loaded.interval, SrsEngine.againInterval);
    expect(loaded.reviewCount, 1);
    expect(loaded.incorrectCount, 1);
    expect(loaded.correctCount, 0);
    expect(loaded.lastReviewedAt, now);
    expect(loaded.isDueAt(now.add(const Duration(seconds: 30))), isFalse);
    expect(loaded.isDueAt(now.add(SrsEngine.againInterval)), isTrue);
  });

  test('seed after restart does not overwrite reviewed cards', () async {
    final env = await fixture();
    final first = SharedPrefsProgressRepository(env.prefs);
    await first.seedIfNeeded(const ['rtk_001', 'rtk_002'], now: now);
    await first.saveSchedule(
      engine.schedule(
        current: (await first.getSchedule('rtk_001'))!,
        result: ReviewResult.good,
        now: now,
      ),
    );

    final restarted = SharedPrefsProgressRepository(env.prefs);
    await restarted.seedIfNeeded(const ['rtk_001', 'rtk_002'], now: now);
    final reviewed = await restarted.getSchedule('rtk_001');
    final fresh = await restarted.getSchedule('rtk_002');

    expect(reviewed!.state, CardLearningState.review);
    expect(reviewed.reviewCount, 1);
    expect(fresh!.state, CardLearningState.newCard);
    expect(fresh.reviewCount, 0);
  });

  test('consecutiveGoodCount survives a new repository', () async {
    final env = await fixture();
    final first = SharedPrefsProgressRepository(env.prefs);
    await first.seedIfNeeded(const ['rtk_001'], now: now);

    var schedule = (await first.getSchedule('rtk_001'))!;
    for (var i = 0; i < 3; i++) {
      schedule = engine.schedule(
        current: schedule,
        result: ReviewResult.good,
        now: now,
      );
    }
    await first.saveSchedule(schedule);

    final restarted = SharedPrefsProgressRepository(env.prefs);
    final loaded = await restarted.getSchedule('rtk_001');

    expect(loaded!.consecutiveGoodCount, 3);
    expect(loaded.reviewCount, 3);
  });

  test(
    'introduce persists a future learning due date across restart',
    () async {
      final env = await fixture();
      final first = SharedPrefsProgressRepository(env.prefs);
      await first.seedIfNeeded(const ['rtk_001'], now: now);

      final updated = engine.introduce(
        current: (await first.getSchedule('rtk_001'))!,
        now: now,
      );
      await first.saveSchedule(updated);

      final restarted = SharedPrefsProgressRepository(env.prefs);
      final loaded = await restarted.getSchedule('rtk_001');

      expect(loaded!.state, CardLearningState.learning);
      expect(loaded.dueAt, now.add(SrsEngine.newLearnInterval));
      expect(loaded.interval, SrsEngine.newLearnInterval);
      expect(loaded.reviewCount, 0);
      expect(loaded.isDueAt(now), isFalse);
      expect(loaded.isDueAt(now.add(SrsEngine.newLearnInterval)), isTrue);
    },
  );

  test('missing consecutiveGoodCount in JSON defaults to 0', () {
    final parsed = CardSchedule.fromJson({
      'cardId': 'rtk_001',
      'state': 'review',
      'reviewCount': 2,
      'correctCount': 2,
      'incorrectCount': 0,
      'dueAt': now.toIso8601String(),
      'intervalSeconds': 86400,
      'ease': 2.5,
    });

    expect(parsed, isNotNull);
    expect(parsed!.consecutiveGoodCount, 0);
    expect(parsed.reviewCount, 2);
  });
}

class SharedPreferencesProgressFixture {
  SharedPreferencesProgressFixture(this.prefs);

  final SharedPreferences prefs;
}

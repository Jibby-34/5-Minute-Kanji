import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/kanji_status.dart';
import 'package:fiveminutekanji/core/models/progress.dart';
import 'package:fiveminutekanji/core/models/review.dart';
import 'package:fiveminutekanji/core/models/study_phase.dart';
import 'package:fiveminutekanji/data/shared_prefs_progress_repository.dart';
import 'package:fiveminutekanji/features/home/home_controller.dart';
import 'package:fiveminutekanji/features/review/review_controller.dart';
import 'package:fiveminutekanji/services/due_card_selector.dart';
import 'package:fiveminutekanji/services/initial_known_card_schedule.dart';
import 'package:fiveminutekanji/services/kanji_status_resolver.dart';
import 'package:fiveminutekanji/services/mark_as_known.dart';
import 'package:fiveminutekanji/services/srs_engine.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 2, 8);
  const engine = SrsEngine();
  const resolver = KanjiStatusResolver();
  const selector = DueCardSelector();

  CardSchedule learning(String id) {
    return CardSchedule(
      cardId: id,
      state: CardLearningState.learning,
      reviewCount: 0,
      correctCount: 0,
      incorrectCount: 0,
      dueAt: now.add(SrsEngine.newLearnInterval),
      interval: SrsEngine.newLearnInterval,
      ease: 2.5,
    );
  }

  CardSchedule mastered(String id) {
    return CardSchedule(
      cardId: id,
      state: CardLearningState.review,
      reviewCount: 3,
      correctCount: 3,
      incorrectCount: 0,
      dueAt: now.add(const Duration(days: 6)),
      interval: const Duration(days: 6),
      ease: 2.5,
      lastReviewedAt: now,
      consecutiveGoodCount: 3,
    );
  }

  MarkAsKnownService service(MemoryProgressRepository progress) {
    return MarkAsKnownService(
      progressRepository: progress,
      srsEngine: engine,
      clock: () => now,
    );
  }

  test(
    'markKanjiAsKnown schedules a future due date and is learning',
    () async {
      final progress = MemoryProgressRepository();
      await progress.seedIfNeeded(const ['a'], now: now);
      progress.dailyNewKanji = DailyNewKanjiProgress(date: now, count: 2);

      final marked = await service(progress).markKanjiAsKnown('a', now: now);

      expect(marked, isNotNull);
      expect(marked!.state, CardLearningState.review);
      expect(marked.interval, calculateInitialKnownCardSchedule('a'));
      expect(marked.dueAt, now.add(calculateInitialKnownCardSchedule('a')));
      expect(marked.interval.inDays, inInclusiveRange(15, 45));
      expect(marked.isDueAt(now), isFalse);
      expect(resolver.resolve(marked), KanjiProgressStatus.learning);
      expect(progress.dailyNewKanji.count, 2);
    },
  );

  test(
    'markKanjiAsKnown does not overwrite learning or mastered cards',
    () async {
      final originalLearning = learning('b');
      final originalMastered = mastered('c');
      final progress = MemoryProgressRepository(
        schedules: {
          'a': CardSchedule.fresh('a', now),
          'b': originalLearning,
          'c': originalMastered,
        },
      );

      final marked = await service(
        progress,
      ).markKanjiAsKnownAll(const ['a', 'b', 'c'], now: now);

      expect(marked.map((schedule) => schedule.cardId), ['a']);
      expect((await progress.getSchedule('b'))!.dueAt, originalLearning.dueAt);
      expect(
        (await progress.getSchedule('b'))!.state,
        CardLearningState.learning,
      );
      expect(
        (await progress.getSchedule('c'))!.consecutiveGoodCount,
        originalMastered.consecutiveGoodCount,
      );
      expect(
        resolver.resolve(await progress.getSchedule('c')),
        KanjiProgressStatus.mastered,
      );
    },
  );

  test('mass mark uses the same SRS result as individual mark', () async {
    final individualProgress = MemoryProgressRepository();
    final massProgress = MemoryProgressRepository();
    await individualProgress.seedIfNeeded(const ['a', 'b'], now: now);
    await massProgress.seedIfNeeded(const ['a', 'b'], now: now);

    final individual = service(individualProgress);
    await individual.markKanjiAsKnown('a', now: now);
    await individual.markKanjiAsKnown('b', now: now);

    await service(massProgress).markKanjiAsKnownAll(const ['a', 'b'], now: now);

    for (final id in ['a', 'b']) {
      final one = (await individualProgress.getSchedule(id))!;
      final many = (await massProgress.getSchedule(id))!;
      expect(many.state, one.state);
      expect(many.dueAt, one.dueAt);
      expect(many.interval, one.interval);
      expect(many.consecutiveGoodCount, one.consecutiveGoodCount);
      expect(resolver.resolve(many), KanjiProgressStatus.learning);
    }
  });

  test('known cards are no longer new and are not immediately due', () async {
    final progress = MemoryProgressRepository();
    await progress.seedIfNeeded(const ['a', 'b'], now: now);
    await service(progress).markKanjiAsKnown('a', now: now);

    final cards = [testCard('a'), testCard('b')];
    final schedules = await progress.getSchedules();
    expect(selector.isNew(schedules['a']), isFalse);
    expect(selector.isNew(schedules['b']), isTrue);
    expect(selector.isDue(schedules['a'], now), isFalse);
    expect(selector.countNew(cards: cards, schedules: schedules), 1);
    expect(selector.countDue(cards: cards, schedules: schedules, now: now), 0);
  });

  test(
    'marking as known does not consume the daily new-kanji allowance',
    () async {
      final cards = List.generate(6, (i) => testCard('n$i'));
      final progress = MemoryProgressRepository(
        settings: const AppSettings(newKanjiPerDay: 2),
      );
      await progress.seedIfNeeded(
        cards.map((card) => card.id).toList(),
        now: now,
      );

      await service(
        progress,
      ).markKanjiAsKnownAll(['n0', 'n1', 'n2', 'n3'], now: now);

      final home = HomeController(
        kanjiRepository: FakeKanjiRepository(cards),
        progressRepository: progress,
        config: const ReviewSessionConfig(
          duration: Duration(minutes: 5),
          maxCards: 25,
        ),
        clock: () => now,
      );
      await home.load();

      expect(progress.dailyNewKanji.count, 0);
      expect(home.newRemainingToday, 2);
      final session = await home.cardsForSession(practice: false);
      expect(session.map((card) => card.id), ['n4', 'n5']);
    },
  );

  test(
    'learn-flow mark as known skips intro and does not increment daily',
    () async {
      final progress = MemoryProgressRepository();
      await progress.seedIfNeeded(const ['a', 'b'], now: now);
      final controller = ReviewController(
        progressRepository: progress,
        srsEngine: engine,
        cards: [testCard('a'), testCard('b')],
        config: const ReviewSessionConfig(
          duration: Duration(minutes: 5),
          maxCards: 2,
        ),
        startTime: now,
        clock: () => now,
        schedules: Map<String, CardSchedule>.from(progress.schedules),
      );

      expect(controller.phase, StudyPhase.learn);
      await controller.markCurrentAsKnown();

      expect(progress.dailyNewKanji.count, 0);
      final schedule = await progress.getSchedule('a');
      expect(schedule!.dueAt, now.add(calculateInitialKnownCardSchedule('a')));
      expect(resolver.resolve(schedule), KanjiProgressStatus.learning);
      expect(controller.current?.id, 'b');
      expect(controller.phase, StudyPhase.learn);
    },
  );

  test('known schedule survives a new repository instance', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final first = SharedPrefsProgressRepository(prefs);
    await first.seedIfNeeded(const ['rtk_001'], now: now);

    await MarkAsKnownService(
      progressRepository: first,
      srsEngine: engine,
      clock: () => now,
    ).markKanjiAsKnown('rtk_001', now: now);

    final restarted = SharedPrefsProgressRepository(prefs);
    final loaded = await restarted.getSchedule('rtk_001');
    expect(loaded!.state, CardLearningState.review);
    expect(loaded.interval, calculateInitialKnownCardSchedule('rtk_001'));
    expect(loaded.dueAt, now.add(calculateInitialKnownCardSchedule('rtk_001')));
    expect(resolver.resolve(loaded), KanjiProgressStatus.learning);
  });

  test('one known card lands about 30 days out', () async {
    final progress = MemoryProgressRepository();
    await progress.seedIfNeeded(const ['solo'], now: now);

    final marked = await service(progress).markKanjiAsKnown('solo', now: now);

    expect(marked!.interval.inDays, closeTo(30, 15));
    expect(
      marked.dueAt.difference(now).inDays,
      inInclusiveRange(initialKnownMinDays, initialKnownMaxDays),
    );
  });

  test(
    'two known cards get different due dates when the window allows',
    () async {
      final progress = MemoryProgressRepository();
      await progress.seedIfNeeded(const ['alpha', 'bravo'], now: now);

      await service(
        progress,
      ).markKanjiAsKnownAll(const ['alpha', 'bravo'], now: now);

      final first = (await progress.getSchedule('alpha'))!;
      final second = (await progress.getSchedule('bravo'))!;
      expect(first.dueAt, isNot(second.dueAt));
      expect(first.interval, calculateInitialKnownCardSchedule('alpha'));
      expect(second.interval, calculateInitialKnownCardSchedule('bravo'));
    },
  );

  test('a large batch is spread across the initial window', () async {
    final ids = [
      for (var i = 0; i < 200; i++) 'n5-${i.toString().padLeft(3, '0')}',
    ];
    final progress = MemoryProgressRepository();
    await progress.seedIfNeeded(ids, now: now);

    await service(progress).markKanjiAsKnownAll(ids, now: now);

    final days = [
      for (final id in ids) progress.schedules[id]!.interval.inDays,
    ];
    expect(days.every((day) => day >= 15 && day <= 45), isTrue);
    expect(days.toSet().length, greaterThanOrEqualTo(20));
    expect(days.reduce((a, b) => a < b ? a : b), lessThanOrEqualTo(20));
    expect(days.reduce((a, b) => a > b ? a : b), greaterThanOrEqualTo(40));
    expect(days.toSet(), isNot(equals({30})));
  });

  test('reloading progress does not move a known card due date', () async {
    final progress = MemoryProgressRepository();
    await progress.seedIfNeeded(const ['a'], now: now);
    await service(progress).markKanjiAsKnown('a', now: now);

    final first = (await progress.getSchedule('a'))!;
    final again = (await progress.getSchedule('a'))!;
    expect(again.dueAt, first.dueAt);
    expect(again.interval, first.interval);
  });

  test('reviewing a known card hands scheduling back to normal SRS', () async {
    final progress = MemoryProgressRepository();
    await progress.seedIfNeeded(const ['a'], now: now);
    final known = (await service(progress).markKanjiAsKnown('a', now: now))!;
    final later = now.add(known.interval);

    final afterGood = engine.schedule(
      current: known,
      result: ReviewResult.good,
      now: later,
    );
    expect(afterGood.interval, isNot(calculateInitialKnownCardSchedule('a')));
    expect(afterGood.interval.inSeconds, greaterThan(known.interval.inSeconds));
    expect(afterGood.dueAt, later.add(afterGood.interval));
    expect(afterGood.reviewCount, 1);
    expect(afterGood.consecutiveGoodCount, 1);

    final afterAgain = engine.schedule(
      current: known,
      result: ReviewResult.again,
      now: later,
    );
    expect(afterAgain.interval, SrsEngine.againInterval);
    expect(afterAgain.dueAt, later.add(SrsEngine.againInterval));
    expect(afterAgain.state, CardLearningState.learning);
  });

  test(
    'individual and bulk Mark as Known share the same schedule function',
    () {
      expect(
        calculateInitialKnownCardSchedule('n5-001'),
        engine
            .markAsKnown(current: CardSchedule.fresh('n5-001', now), now: now)
            .interval,
      );
    },
  );
}

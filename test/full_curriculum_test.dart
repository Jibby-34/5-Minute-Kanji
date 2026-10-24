import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/kanji_card.dart';
import 'package:fiveminutekanji/core/models/placement.dart';
import 'package:fiveminutekanji/core/models/progress.dart';
import 'package:fiveminutekanji/core/models/review.dart';
import 'package:fiveminutekanji/core/theme/app_theme.dart';
import 'package:fiveminutekanji/data/shared_prefs_curriculum_repository.dart';
import 'package:fiveminutekanji/features/review/review_screen.dart';
import 'package:fiveminutekanji/features/review/review_controller.dart';
import 'package:fiveminutekanji/features/settings/settings_screen.dart';
import 'package:fiveminutekanji/repositories/progress_repository.dart';
import 'package:fiveminutekanji/services/curriculum/curriculum_access.dart';
import 'package:fiveminutekanji/services/curriculum/curriculum_billing.dart';
import 'package:fiveminutekanji/services/curriculum/curriculum_products.dart';
import 'package:fiveminutekanji/services/curriculum/curriculum_repository.dart';
import 'package:fiveminutekanji/services/curriculum/learned_kanji_backfill.dart';
import 'package:fiveminutekanji/services/daily_workload.dart';
import 'package:fiveminutekanji/services/initial_known_card_schedule.dart';
import 'package:fiveminutekanji/services/mark_as_known.dart';
import 'package:fiveminutekanji/services/placement_service.dart';
import 'package:fiveminutekanji/services/reminder_scheduler.dart';
import 'package:fiveminutekanji/services/srs_engine.dart';
import 'package:fiveminutekanji/services/srs_scheduler.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 22, 9);
  const engine = SrsEngine();
  const config = ReviewSessionConfig(
    duration: Duration(minutes: 30),
    maxCards: 60,
  );

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  CurriculumAccess accessFor({
    required MemoryProgressRepository progress,
    CurriculumRecord? record,
    FakeCurriculumBilling? billing,
  }) {
    return CurriculumAccess(
      progressRepository: progress,
      repository: MemoryCurriculumRepository(record: record),
      billing: billing ?? FakeCurriculumBilling(),
    );
  }

  Future<ReviewController> learner({
    required MemoryProgressRepository progress,
    required CurriculumAccess access,
    required List<String> ids,
    DailyWorkloadService? workload,
  }) async {
    await progress.seedIfNeeded(ids, now: now);
    final controller = ReviewController(
      progressRepository: progress,
      srsEngine: engine,
      cards: ids.map(testCard).toList(),
      config: config,
      clock: () => now,
      startTime: now,
      curriculumAccess: access,
      workloadService: workload,
    );
    await controller.hydrate();
    return controller;
  }

  Future<void> learnCurrent(ReviewController controller) async {
    controller.beginPractice();
    await controller.completePractice();
  }

  test('a new user can learn the first 50 unique kanji', () async {
    final progress = MemoryProgressRepository();
    final access = accessFor(
      progress: progress,
      record: const CurriculumRecord(backfillCompleted: true),
    );
    await access.ensureLoaded();
    final ids = [for (var i = 0; i < 50; i++) 'k$i'];
    for (final id in ids) {
      final controller = await learner(
        progress: progress,
        access: access,
        ids: [id],
      );
      expect(controller.current?.id, id);
      await learnCurrent(controller);
      expect(
        (await progress.getSchedule(id))!.state,
        CardLearningState.learning,
      );
    }

    expect(access.studiedCount, 50);
    expect(access.canLearnNewKanji, isFalse);
  });

  test('the 50th kanji is allowed and the 51st new kanji is blocked', () async {
    final progress = MemoryProgressRepository();
    final access = accessFor(
      progress: progress,
      record: const CurriculumRecord(backfillCompleted: true),
    );
    await access.ensureLoaded();
    for (var i = 0; i < 50; i++) {
      final controller = await learner(
        progress: progress,
        access: access,
        ids: ['k$i'],
      );
      await learnCurrent(controller);
    }
    expect(access.studiedCount, 50);

    final blockedSession = await learner(
      progress: progress,
      access: access,
      ids: ['k50'],
    );
    expect(blockedSession.current, isNull);
    expect(access.studiedIds.contains('k50'), isFalse);
    expect(
      (await progress.getSchedule('k50'))!.state,
      CardLearningState.newCard,
    );
    expect(
      (await progress.getSchedule('k49'))!.state,
      CardLearningState.learning,
    );
    expect((await progress.getDailyNewKanji()).count, 50);

    final gate = ReviewController(
      progressRepository: progress,
      srsEngine: engine,
      cards: [testCard('k50')],
      config: config,
      clock: () => now,
      startTime: now,
      schedules: {'k50': (await progress.getSchedule('k50'))!},
      curriculumAccess: access,
    );
    gate.beginPractice();
    await gate.completePractice();
    expect(access.studiedCount, 50);
    expect(
      (await progress.getSchedule('k50'))!.state,
      CardLearningState.newCard,
    );
  });

  test('marking kanji as known does not consume trial credits', () async {
    final progress = MemoryProgressRepository();
    final access = accessFor(progress: progress);
    final known = MarkAsKnownService(
      progressRepository: progress,
      srsEngine: engine,
      clock: () => now,
    );
    await known.markKanjiAsKnownAll(['known-a', 'known-b'], now: now);
    await access.ensureLoaded();

    expect(access.studiedCount, 0);
    expect(access.canLearnNewKanji, isTrue);

    final controller = await learner(
      progress: progress,
      access: access,
      ids: ['known-c'],
    );
    await controller.markCurrentAsKnown();

    expect(access.studiedCount, 0);
    expect(
      (await progress.getSchedule('known-c'))!.state,
      CardLearningState.review,
    );
    expect(await access.tryRecordStudy('still-new'), isAllowed(newly: true));
    expect(access.studiedCount, 1);
  });

  test('placement test results do not consume trial credits', () async {
    final progress = MemoryProgressRepository();
    final cards = [testCard('known'), testCard('confirm'), testCard('left')];
    final placement = PlacementService(
      kanjiRepository: FakeKanjiRepository(cards),
      progressRepository: progress,
      markAsKnown: MarkAsKnownService(
        progressRepository: progress,
        srsEngine: engine,
        clock: () => now,
      ),
      clock: () => now,
    );
    await placement.complete(
      const PlacementOutcome(
        knownCardIds: ['known'],
        confirmCardIds: ['confirm'],
        answeredCount: 1,
      ),
    );
    final access = accessFor(progress: progress);
    await access.ensureLoaded();

    expect(access.studiedCount, 0);
    expect(
      (await progress.getSchedule('known'))!.state,
      CardLearningState.review,
    );
    expect(
      (await progress.getSchedule('confirm'))!.state,
      CardLearningState.learning,
    );
    expect(await progress.getSchedule('left'), isNull);
  });

  test(
    'learning the same kanji more than once does not increase the count',
    () async {
      final progress = MemoryProgressRepository();
      final access = accessFor(
        progress: progress,
        record: const CurriculumRecord(backfillCompleted: true),
      );
      await access.ensureLoaded();
      final controller = await learner(
        progress: progress,
        access: access,
        ids: ['once'],
      );
      await learnCurrent(controller);
      expect(access.studiedCount, 1);

      final again = await access.tryRecordStudy('once');
      expect(again.allowed, isTrue);
      expect(again.newlyRecorded, isFalse);
      expect(access.studiedCount, 1);

      final review = ReviewController(
        progressRepository: progress,
        srsEngine: engine,
        cards: [testCard('once')],
        config: config,
        clock: () => now,
        startTime: now,
        schedules: Map<String, CardSchedule>.from(progress.schedules),
        curriculumAccess: access,
      );
      review.submit();
      await review.rate(ReviewResult.good);
      expect(access.studiedCount, 1);
    },
  );

  test('retaking the placement test does not reset the trial', () async {
    final progress = MemoryProgressRepository();
    final learned = engine.introduce(
      current: CardSchedule.fresh('studied', now),
      now: now,
    );
    await progress.saveSchedule(learned);
    final access = accessFor(progress: progress);
    await access.ensureLoaded();
    expect(access.studiedIds, {'studied'});

    final placement = PlacementService(
      kanjiRepository: FakeKanjiRepository([
        testCard('studied'),
        testCard('extra'),
      ]),
      progressRepository: progress,
      markAsKnown: MarkAsKnownService(
        progressRepository: progress,
        srsEngine: engine,
        clock: () => now,
      ),
      clock: () => now,
    );
    await placement.restart();
    await placement.complete(
      const PlacementOutcome(
        knownCardIds: ['extra', 'studied'],
        answeredCount: 2,
      ),
    );

    expect(access.studiedIds, {'studied'});
    final kept = await progress.getSchedule('studied');
    expect(kept!.interval, learned.interval);
    expect(kept.dueAt, learned.dueAt);
    expect(kept.reviewCount, learned.reviewCount);
  });

  test('existing learned kanji and SRS progress survive the update', () async {
    final progress = MemoryProgressRepository();
    final introduced = engine.introduce(
      current: CardSchedule.fresh('old', now),
      now: now,
    );
    final reviewed = engine.schedule(
      current: introduced,
      result: ReviewResult.good,
      now: now.add(const Duration(minutes: 10)),
    );
    final known = engine.markAsKnown(
      current: CardSchedule.fresh('known', now),
      now: now,
      interval: calculateInitialKnownCardSchedule('known'),
    );
    await progress.saveSchedule(reviewed);
    await progress.saveSchedule(known);
    final beforeReviewed = await progress.getSchedule('old');
    final beforeKnown = await progress.getSchedule('known');

    final access = accessFor(progress: progress);
    await access.ensureLoaded();

    expect(access.studiedIds, {'old'});
    expect(await progress.getSchedule('old'), beforeReviewed);
    expect(await progress.getSchedule('known'), beforeKnown);
    expect(access.canLearnNewKanji, isTrue);
  });

  test(
    'users at the limit can still review previously learned cards',
    () async {
      final progress = MemoryProgressRepository();
      final studied = {for (var i = 0; i < 50; i++) 'done-$i'};
      final due = CardSchedule(
        cardId: 'done-0',
        state: CardLearningState.review,
        reviewCount: 2,
        correctCount: 2,
        incorrectCount: 0,
        dueAt: now,
        interval: const Duration(days: 1),
        ease: 2.5,
        lastReviewedAt: now.subtract(const Duration(days: 1)),
        consecutiveGoodCount: 2,
      );
      await progress.saveSchedule(due);
      final access = accessFor(
        progress: progress,
        record: CurriculumRecord(studiedIds: studied, backfillCompleted: true),
      );
      await access.ensureLoaded();
      final controller = await learner(
        progress: progress,
        access: access,
        ids: ['done-0', 'brand-new'],
      );

      expect(controller.current?.id, 'done-0');
      expect(controller.phase.name, 'recall');
      controller.submit();
      await controller.rate(ReviewResult.good);

      final updated = await progress.getSchedule('done-0');
      expect(updated!.reviewCount, 3);
      expect(updated.interval, isNot(due.interval));
      expect(access.studiedCount, 50);
      expect(
        (await progress.getSchedule('brand-new'))!.state,
        CardLearningState.newCard,
      );
    },
  );

  test('every path to a new kanji respects the cap', () async {
    final progress = MemoryProgressRepository(
      settings: const AppSettings(dailyStudyMinutes: 30, newKanjiPerDay: 5),
    );
    final studied = {for (var i = 0; i < 50; i++) 'done-$i'};
    await progress.saveSchedule(
      CardSchedule(
        cardId: 'due',
        state: CardLearningState.review,
        reviewCount: 1,
        correctCount: 1,
        incorrectCount: 0,
        dueAt: now,
        interval: const Duration(days: 1),
        ease: 2.5,
        lastReviewedAt: now.subtract(const Duration(days: 1)),
        consecutiveGoodCount: 1,
      ),
    );
    final access = accessFor(
      progress: progress,
      record: CurriculumRecord(studiedIds: studied, backfillCompleted: true),
    );
    await access.ensureLoaded();
    final cards = [testCard('due'), testCard('new-a'), testCard('new-b')];
    final workload = DailyWorkloadService(
      kanjiRepository: FakeKanjiRepository(cards),
      progressRepository: progress,
      curriculumAccess: access,
    );

    final sitting = await workload.read(now: now);
    expect(
      sitting.sessionCards.map((card) => card.id),
      isNot(contains('new-a')),
    );
    expect(
      sitting.sessionCards.map((card) => card.id),
      isNot(contains('new-b')),
    );
    expect(sitting.sessionCards.map((card) => card.id), contains('due'));

    final eligible = await workload.eligibleByPriority(now: now);
    expect(eligible.map((card) => card.id), ['due']);

    await progress.saveDailySessionPlan(
      (await progress.getDailySessionPlan()).copyWith(completed: true),
    );
    final overflow = await workload.read(now: now);
    expect(overflow.studyAnywayAvailable, isTrue);
    expect(overflow.overflowCards.map((card) => card.id), ['due']);

    final blocked = await access.tryRecordStudy('new-a');
    expect(blocked.allowed, isFalse);

    final controller = await learner(
      progress: progress,
      access: access,
      ids: ['new-a', 'due'],
      workload: workload,
    );
    expect(controller.current?.id, 'due');
    expect(await progress.getSchedule('new-a'), isNotNull);
    expect(
      (await progress.getSchedule('new-a'))!.state,
      CardLearningState.newCard,
    );
  });

  test('two introductions cannot both pass the last free slot', () async {
    final progress = MemoryProgressRepository();
    final seeded = {for (var i = 0; i < 49; i++) 'done-$i'};
    final access = CurriculumAccess(
      progressRepository: progress,
      repository: _SlowCurriculumRepository(
        MemoryCurriculumRepository(
          record: CurriculumRecord(studiedIds: seeded, backfillCompleted: true),
        ),
      ),
      billing: FakeCurriculumBilling(),
    );
    await access.ensureLoaded();

    final results = await Future.wait([
      access.tryRecordStudy('one'),
      access.tryRecordStudy('two'),
    ]);
    final allowed = results.where((result) => result.allowed).length;
    expect(allowed, 1);
    expect(access.studiedCount, 50);
    expect(access.canLearnNewKanji, isFalse);
  });

  test(
    'purchasing unlocks new kanji immediately and a tap alone does not',
    () async {
      final progress = MemoryProgressRepository(
        settings: const AppSettings(dailyStudyMinutes: 30, newKanjiPerDay: 5),
      );
      final billing = FakeCurriculumBilling(
        product: const CurriculumProduct(
          id: fullCurriculumUnlock,
          price: r'CA$79.99',
          raw: Object(),
        ),
      );
      final studied = {for (var i = 0; i < 50; i++) 'done-$i'};
      final access = accessFor(
        progress: progress,
        record: CurriculumRecord(studiedIds: studied, backfillCompleted: true),
        billing: billing,
      );
      await access.ensureLoaded();
      await pumpEventQueue();
      expect(access.localizedPrice, r'CA$79.99');
      expect(access.purchaseButtonLabel, r'Unlock full version · CA$79.99');

      final buying = access.buy();
      expect(access.unlocked, isFalse);
      await buying;
      expect(billing.buyCalls, 1);
      expect(access.unlocked, isFalse);

      billing.emit(_purchase());
      await pumpEventQueue();

      expect(access.unlocked, isTrue);
      expect(access.trialLimitReached, isFalse);
      expect(billing.completed, isNotEmpty);
      expect(
        await access.tryRecordStudy('after-purchase'),
        isAllowed(newly: true),
      );

      final workload = DailyWorkloadService(
        kanjiRepository: FakeKanjiRepository([testCard('fresh')]),
        progressRepository: progress,
        curriculumAccess: access,
      );
      final sitting = await workload.read(now: now);
      expect(sitting.sessionCards.map((card) => card.id), contains('fresh'));
    },
  );

  test('canceled and failed purchases do not unlock the curriculum', () async {
    final progress = MemoryProgressRepository();
    final billing = FakeCurriculumBilling();
    final access = accessFor(
      progress: progress,
      record: const CurriculumRecord(backfillCompleted: true),
      billing: billing,
    );
    await access.ensureLoaded();

    await access.buy();
    billing.emit(_purchase(status: CurriculumPurchaseStatus.canceled));
    await pumpEventQueue();
    expect(access.unlocked, isFalse);
    expect(access.purchaseMessage, 'Purchase cancelled.');
    expect(access.notice, CurriculumNotice.cancelled);

    billing.emit(
      _purchase(
        status: CurriculumPurchaseStatus.error,
        verification: '',
        errorMessage: 'Billing unavailable',
      ),
    );
    await pumpEventQueue();
    expect(access.unlocked, isFalse);
    expect(access.purchaseMessage, 'Billing unavailable');

    billing.emit(
      _purchase(status: CurriculumPurchaseStatus.pending, verification: ''),
    );
    await pumpEventQueue();
    expect(access.unlocked, isFalse);
    expect(access.activity, CurriculumActivity.pending);

    billing.emit(_purchase(verification: '   '));
    await pumpEventQueue();
    expect(access.unlocked, isFalse);
    expect(access.purchaseMessage, 'Purchase could not be verified.');
  });

  test('restoring an existing purchase unlocks the curriculum', () async {
    final progress = MemoryProgressRepository();
    final billing = FakeCurriculumBilling()
      ..queryResult = EntitlementQueryResult.owned
      ..restoredOnRestore = _purchase(
        status: CurriculumPurchaseStatus.restored,
      );
    final access = accessFor(
      progress: progress,
      record: const CurriculumRecord(backfillCompleted: true),
      billing: billing,
    );
    await access.ensureLoaded();
    expect(access.unlocked, isFalse);

    await access.restore();
    await pumpEventQueue();

    expect(billing.restoreCalls, 1);
    expect(access.unlocked, isTrue);
    expect(access.canLearnNewKanji, isTrue);
  });

  test(
    'a refund query clears a cached unlock when the store can answer',
    () async {
      final progress = MemoryProgressRepository();
      final billing = FakeCurriculumBilling()
        ..available = true
        ..queryResult = EntitlementQueryResult.notOwned;
      final access = accessFor(
        progress: progress,
        record: const CurriculumRecord(backfillCompleted: true, unlocked: true),
        billing: billing,
      );
      await access.ensureLoaded();
      await pumpEventQueue();

      expect(access.unlocked, isFalse);
    },
  );

  test('an unreachable store keeps the cached unlock', () async {
    final progress = MemoryProgressRepository();
    final billing = FakeCurriculumBilling()
      ..available = false
      ..queryResult = EntitlementQueryResult.notOwned;
    final access = accessFor(
      progress: progress,
      record: const CurriculumRecord(backfillCompleted: true, unlocked: true),
      billing: billing,
    );
    await access.ensureLoaded();
    await pumpEventQueue();

    expect(access.unlocked, isTrue);
    expect(access.canLearnNewKanji, isTrue);
  });

  test(
    'purchase state and trial progress persist across app restarts',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final progress = MemoryProgressRepository();
      final first = CurriculumAccess(
        progressRepository: progress,
        repository: SharedPrefsCurriculumRepository(prefs),
        billing: FakeCurriculumBilling(),
      );
      await first.ensureLoaded();
      expect(await first.tryRecordStudy('kept'), isAllowed(newly: true));
      await SharedPrefsCurriculumRepository(prefs).write(
        const CurriculumRecord(
          studiedIds: {'kept'},
          backfillCompleted: true,
          unlocked: true,
        ),
      );

      final reopened = CurriculumAccess(
        progressRepository: progress,
        repository: SharedPrefsCurriculumRepository(prefs),
        billing: FakeCurriculumBilling()..available = false,
      );
      await reopened.ensureLoaded();
      await pumpEventQueue();

      expect(reopened.studiedIds, {'kept'});
      expect(reopened.unlocked, isTrue);
      expect(reopened.canLearnNewKanji, isTrue);
    },
  );

  test('historical backfill ignores known and placement cards', () {
    final introduced = engine.introduce(
      current: CardSchedule.fresh('learned', now),
      now: now,
    );
    final graduated = engine.schedule(
      current: introduced,
      result: ReviewResult.good,
      now: now,
    );
    final known = engine.markAsKnown(
      current: CardSchedule.fresh('known', now),
      now: now,
      interval: calculateInitialKnownCardSchedule('known'),
    );
    final knownReviewed = engine.schedule(
      current: known,
      result: ReviewResult.good,
      now: now,
    );
    final confirmed = CardSchedule(
      cardId: 'confirm',
      state: CardLearningState.learning,
      reviewCount: 0,
      correctCount: 0,
      incorrectCount: 0,
      dueAt: now.add(const Duration(days: 4)),
      interval: const Duration(days: 4),
      ease: 2.5,
    );

    expect(
      LearnedKanjiBackfill.idsFrom([
        introduced,
        graduated,
        known,
        knownReviewed,
        confirmed,
        CardSchedule.fresh('new', now),
      ]),
      {'learned'},
    );
    expect(knownReviewed.interval.inDays, greaterThanOrEqualTo(15));
  });

  testWidgets('the review prompt is shown once per session', (tester) async {
    final progress = MemoryProgressRepository();
    await progress.saveSchedule(
      CardSchedule(
        cardId: 'due',
        state: CardLearningState.review,
        reviewCount: 1,
        correctCount: 1,
        incorrectCount: 0,
        dueAt: now,
        interval: const Duration(days: 1),
        ease: 2.5,
        lastReviewedAt: now.subtract(const Duration(days: 1)),
        consecutiveGoodCount: 1,
      ),
    );
    final billing = FakeCurriculumBilling(
      product: const CurriculumProduct(
        id: fullCurriculumUnlock,
        price: '¥8,800',
        raw: Object(),
      ),
    );
    final access = accessFor(
      progress: progress,
      record: CurriculumRecord(
        studiedIds: {for (var i = 0; i < 50; i++) 'done-$i'},
        backfillCompleted: true,
      ),
      billing: billing,
    );
    await access.ensureLoaded();

    await tester.pumpWidget(
      _sessionApp(progress: progress, access: access, now: now),
    );
    await _pumpUntil(tester, find.text("You've learned your first 50 kanji"));

    expect(find.text("You've learned your first 50 kanji"), findsOneWidget);
    expect(find.text('Go to purchase screen'), findsOneWidget);
    expect(find.text('Keep reviewing'), findsOneWidget);
    expect(find.text('Unlock full version · ¥8,800'), findsNothing);

    await tester.tap(find.text('Go to purchase screen'));
    await _pumpUntil(tester, find.text('Unlock the full curriculum'));
    expect(billing.buyCalls, 0);
    expect(access.unlocked, isFalse);

    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text('Unlock the full curriculum'),
          matching: find.byType(Scaffold),
        ),
        matching: find.byTooltip('Close'),
      ),
    );
    await _pumpUntil(tester, find.text('Submit'));
    expect(find.text("You've learned your first 50 kanji"), findsNothing);
    expect(find.text('Submit'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text("You've learned your first 50 kanji"), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      _sessionApp(progress: progress, access: access, now: now),
    );
    await _pumpUntil(tester, find.text("You've learned your first 50 kanji"));
    expect(find.text("You've learned your first 50 kanji"), findsOneWidget);
  });

  testWidgets(
    'a purchased user does not see the trial prompt or restrictions',
    (tester) async {
      final progress = MemoryProgressRepository(
        settings: const AppSettings(dailyStudyMinutes: 30, newKanjiPerDay: 5),
      );
      await progress.saveSchedule(
        CardSchedule(
          cardId: 'due',
          state: CardLearningState.review,
          reviewCount: 1,
          correctCount: 1,
          incorrectCount: 0,
          dueAt: now,
          interval: const Duration(days: 1),
          ease: 2.5,
          lastReviewedAt: now.subtract(const Duration(days: 1)),
          consecutiveGoodCount: 1,
        ),
      );
      final access = accessFor(
        progress: progress,
        record: CurriculumRecord(
          studiedIds: {for (var i = 0; i < 50; i++) 'done-$i'},
          backfillCompleted: true,
          unlocked: true,
        ),
      );
      await access.ensureLoaded();

      await tester.pumpWidget(
        _sessionApp(
          progress: progress,
          access: access,
          now: now,
          cards: [testCard('due'), testCard('fresh')],
        ),
      );
      await _pumpFrames(tester);

      expect(find.text("You've learned your first 50 kanji"), findsNothing);
      expect(find.text('Submit'), findsOneWidget);
      expect(access.trialLimitReached, isFalse);

      final workload = DailyWorkloadService(
        kanjiRepository: FakeKanjiRepository([
          testCard('due'),
          testCard('fresh'),
        ]),
        progressRepository: progress,
        curriculumAccess: access,
      );
      final sitting = await workload.read(now: now);
      expect(sitting.sessionCards.map((card) => card.id), contains('fresh'));
    },
  );

  testWidgets('settings shows trial progress and the price is not hardcoded', (
    tester,
  ) async {
    final progress = MemoryProgressRepository();
    final access = accessFor(
      progress: progress,
      record: CurriculumRecord(
        studiedIds: {for (var i = 0; i < 37; i++) 'done-$i'},
        backfillCompleted: true,
      ),
      billing: FakeCurriculumBilling(
        product: const CurriculumProduct(
          id: fullCurriculumUnlock,
          price: '€59.99',
          raw: Object(),
        ),
      ),
    );
    await access.ensureLoaded();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ProgressRepository>.value(value: progress),
          Provider<ReminderScheduler?>.value(value: null),
          ChangeNotifierProvider<CurriculumAccess>.value(value: access),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('37 / 50 free kanji learned'), findsOneWidget);
    expect(find.text('Unlock full version'), findsWidgets);
    expect(find.text(r'$59.99'), findsNothing);

    await tester.tap(find.text('Unlock full version').first);
    await tester.pumpAndSettle();

    expect(find.text('Unlock the full curriculum'), findsOneWidget);
    expect(
      find.text('Learn every kanji, with no subscription.'),
      findsOneWidget,
    );
    expect(find.text('€59.99'), findsOneWidget);
    expect(find.text('Restore Purchases'), findsOneWidget);
    expect(find.text(r'$59.99'), findsNothing);
  });
}

class FakeCurriculumBilling implements CurriculumBilling {
  FakeCurriculumBilling({this.product, this.available = true});

  final _updates = StreamController<List<CurriculumPurchaseUpdate>>.broadcast();
  CurriculumProduct? product;
  bool available;
  EntitlementQueryResult queryResult = EntitlementQueryResult.unavailable;
  bool startResult = true;
  int buyCalls = 0;
  int restoreCalls = 0;
  final List<String> completed = [];
  CurriculumPurchaseUpdate? restoredOnRestore;

  void emit(CurriculumPurchaseUpdate update) {
    _updates.add([update]);
  }

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<CurriculumProduct?> loadProduct() async => product;

  @override
  Future<CurriculumCatalog> loadCatalog() async {
    return CurriculumCatalog(lifetime: await loadProduct());
  }

  @override
  Future<bool> startPurchase(CurriculumProduct product) async {
    buyCalls++;
    return startResult;
  }

  @override
  Future<void> restorePurchases() async {
    restoreCalls++;
    final update = restoredOnRestore;
    if (update != null) emit(update);
  }

  @override
  Future<EntitlementQueryResult> queryEntitlement() async => queryResult;

  @override
  Future<StoreEntitlementSnapshot> queryStoreEntitlement() async {
    return StoreEntitlementSnapshot(lifetime: await queryEntitlement());
  }

  @override
  Stream<List<CurriculumPurchaseUpdate>> get purchaseUpdates => _updates.stream;

  @override
  Future<void> complete(CurriculumPurchaseUpdate update) async {
    completed.add(update.purchaseId ?? update.productId);
  }
}

class _SlowCurriculumRepository implements CurriculumRepository {
  _SlowCurriculumRepository(this.inner);

  final CurriculumRepository inner;

  @override
  Future<CurriculumRecord> read() => inner.read();

  @override
  Future<void> write(CurriculumRecord record) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await inner.write(record);
  }
}

CurriculumPurchaseUpdate _purchase({
  CurriculumPurchaseStatus status = CurriculumPurchaseStatus.purchased,
  String verification = 'signed-receipt',
  String? errorMessage,
}) {
  return CurriculumPurchaseUpdate(
    productId: fullCurriculumUnlock,
    purchaseId: 'txn-1',
    status: status,
    pendingComplete: status != CurriculumPurchaseStatus.pending,
    verificationData: verification,
    errorMessage: errorMessage,
  );
}

Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
}

Matcher isAllowed({required bool newly}) {
  return isA<StudyRecordResult>()
      .having((result) => result.allowed, 'allowed', isTrue)
      .having((result) => result.newlyRecorded, 'newlyRecorded', newly);
}

Widget _sessionApp({
  required MemoryProgressRepository progress,
  required CurriculumAccess access,
  required DateTime now,
  List<KanjiCard>? cards,
}) {
  return MultiProvider(
    providers: [
      Provider<ProgressRepository>.value(value: progress),
      Provider<SrsScheduler>.value(value: const SrsEngine()),
      ChangeNotifierProvider<CurriculumAccess>.value(value: access),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: ReviewScreen(
        cards: cards ?? [testCard('due')],
        config: const ReviewSessionConfig(
          duration: Duration(minutes: 5),
          maxCards: 4,
        ),
        clock: () => now,
      ),
    ),
  );
}

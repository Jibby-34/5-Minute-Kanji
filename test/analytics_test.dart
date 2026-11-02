import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/daily_session_plan.dart';
import 'package:fiveminutekanji/core/models/notification_settings.dart';
import 'package:fiveminutekanji/core/models/placement.dart';
import 'package:fiveminutekanji/core/models/progress.dart';
import 'package:fiveminutekanji/core/models/review.dart';
import 'package:fiveminutekanji/core/models/start_of_day.dart';
import 'package:fiveminutekanji/core/models/study_day_type.dart';
import 'package:fiveminutekanji/core/theme/app_theme.dart';
import 'package:fiveminutekanji/data/hardcoded_kanji_repository.dart';
import 'package:fiveminutekanji/data/shared_prefs_progress_repository.dart';
import 'package:fiveminutekanji/features/placement/placement_controller.dart';
import 'package:fiveminutekanji/features/review/review_controller.dart';
import 'package:fiveminutekanji/features/review/review_screen.dart';
import 'package:fiveminutekanji/features/settings/settings_controller.dart';
import 'package:fiveminutekanji/repositories/progress_repository.dart';
import 'package:fiveminutekanji/services/analytics/analytics_service.dart';
import 'package:fiveminutekanji/services/analytics/onboarding_completion.dart';
import 'package:fiveminutekanji/services/analytics/study_review_classification.dart';
import 'package:fiveminutekanji/services/card_priority_scorer.dart';
import 'package:fiveminutekanji/services/curriculum/curriculum_access.dart';
import 'package:fiveminutekanji/services/curriculum/curriculum_analytics.dart';
import 'package:fiveminutekanji/services/curriculum/curriculum_billing.dart';
import 'package:fiveminutekanji/services/curriculum/curriculum_entitlement.dart';
import 'package:fiveminutekanji/services/curriculum/curriculum_products.dart';
import 'package:fiveminutekanji/services/curriculum/curriculum_repository.dart';
import 'package:fiveminutekanji/services/daily_workload.dart';
import 'package:fiveminutekanji/services/mark_as_known.dart';
import 'package:fiveminutekanji/services/placement_service.dart';
import 'package:fiveminutekanji/services/placement_test_engine.dart';
import 'package:fiveminutekanji/services/recall_estimator.dart';
import 'package:fiveminutekanji/services/srs_engine.dart';
import 'package:fiveminutekanji/services/srs_scheduler.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 6, 1, 9);

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('AnalyticsService', () {
    test('sanitizes parameters and ignores a failing client', () async {
      final client = _RecordingClient();
      final analytics = AnalyticsService(client: client);
      analytics.kanjiReviewed(
        result: 'good',
        isNew: true,
        reviewCategory: 'new',
      );
      analytics.studySessionCompleted(
        durationSeconds: -4,
        cardsReviewed: 2,
        newCardsLearned: 1,
        goalCompleted: false,
        sessionType: 'normal',
      );
      await _settle();

      final reviewed = client.named('kanji_reviewed').single;
      expect(reviewed['is_new'], 1);
      expect(reviewed['result'], 'good');

      final completed = client.named('study_session_completed').single;
      expect(completed['duration_seconds'], 0);
      expect(completed['goal_completed'], 0);

      final noisy = sanitizeAnalyticsParameters({
        'ok': 'value',
        '': 'drop',
        '1bad': 'drop',
        'empty': '',
        'missing': null,
        'long': 'x' * 140,
        'ratio': double.nan,
      });
      expect(noisy.keys, ['ok', 'long']);
      expect((noisy['long']! as String).length, 100);

      final throwing = AnalyticsService(client: _ThrowingClient());
      expect(() => throwing.onboardingStarted(), returnsNormally);
      await _settle();
    });

    test('claims a transaction id once', () {
      final saved = <List<String>>[];
      final analytics = AnalyticsService(
        onReportedTransactionIdsChanged: saved.add,
      );
      expect(analytics.claimTransaction('  '), isFalse);
      expect(analytics.claimTransaction('id:tx-1'), isTrue);
      expect(analytics.claimTransaction('id:tx-1'), isFalse);
      expect(saved.single, ['id:tx-1']);
    });
  });

  group('study review classification', () {
    test('Again and Good are new, due, or early, and Hard is skipped', () {
      final due = _due('a', now);
      final ahead = due.copyWith(dueAt: now.add(const Duration(days: 10)));
      expect(
        classifyStudyReview(
          result: ReviewResult.hard,
          scheduleBeforeAnswer: due,
          introducedThisSession: false,
          now: now,
          startOfDay: StartOfDay.defaults,
        ),
        isNull,
      );
      final again = classifyStudyReview(
        result: ReviewResult.again,
        scheduleBeforeAnswer: due,
        introducedThisSession: false,
        now: now,
        startOfDay: StartOfDay.defaults,
      );
      expect(again!.result, 'again');
      expect(again.isNew, isFalse);
      expect(again.reviewCategory, 'due');

      final introduced = classifyStudyReview(
        result: ReviewResult.good,
        scheduleBeforeAnswer: due,
        introducedThisSession: true,
        now: now,
        startOfDay: StartOfDay.defaults,
      );
      expect(introduced!.isNew, isTrue);
      expect(introduced.reviewCategory, 'new');

      final early = classifyStudyReview(
        result: ReviewResult.good,
        scheduleBeforeAnswer: ahead,
        introducedThisSession: false,
        now: now,
        startOfDay: StartOfDay.defaults,
      );
      expect(early!.reviewCategory, 'early');
    });
  });

  group('onboarding completion', () {
    test('uses the placement estimate, then the self-assessment', () {
      final placed = OnboardingCompletion.assemble(
        dailyGoalMinutes: 5,
        selfAssessment: PlacementSelfAssessment.beginner,
        estimatedLevel: 42,
      );
      expect(placed.startingMethod, 'placement_test');
      expect(placed.startingLevel, 42);

      final skipped = OnboardingCompletion.assemble(
        dailyGoalMinutes: 10,
        selfAssessment: PlacementSelfAssessment.newUser,
      );
      expect(skipped.startingMethod, 'manual_selection');
      expect(skipped.startingLevel, 'new_user');
    });
  });

  group('review session events', () {
    test(
      'a finished sitting completes once and keeps sitting duration',
      () async {
        final client = _RecordingClient();
        final progress = MemoryProgressRepository(
          schedules: {'a': _due('a', now)},
          dailySessionPlan: _matchingPlan(now, cardIds: ['a']),
        );
        var clock = now;
        final controller = _controller(
          progress: progress,
          ids: ['a'],
          analytics: AnalyticsService(client: client),
          clock: () => clock,
          startTime: now,
        );
        await _settle();
        expect(
          client.named('study_session_started').single['session_type'],
          'normal',
        );
        expect(
          client.named('study_session_started').single['available_cards'],
          1,
        );

        clock = now.add(const Duration(seconds: 40));
        controller.submit();
        expect(await controller.rate(ReviewResult.good), isNotNull);
        await _settle();

        expect(client.named('study_session_completed'), hasLength(1));
        expect(client.named('study_session_abandoned'), isEmpty);
        final completed = client.named('study_session_completed').single;
        expect(completed['duration_seconds'], 40);
        expect(completed['cards_reviewed'], 1);
        expect(completed['new_cards_learned'], 0);
        expect(completed['goal_completed'], 1);
        expect(client.named('kanji_reviewed').single['result'], 'good');
        expect(client.named('kanji_reviewed').single['is_new'], 0);
        expect(client.named('kanji_reviewed').single['review_category'], 'due');

        controller.abandonIfUnfinished();
        controller.completeHeldSession();
        await _settle();
        expect(client.named('study_session_completed'), hasLength(1));
        expect(client.named('study_session_abandoned'), isEmpty);
      },
    );

    test('leaving an open sitting is abandoned, not completed', () async {
      final client = _RecordingClient();
      final controller = _controller(
        progress: MemoryProgressRepository(schedules: {'a': _due('a', now)}),
        ids: ['a'],
        analytics: AnalyticsService(client: client),
        clock: () => now,
      );
      await _settle();
      controller.abandonIfUnfinished();
      controller.abandonIfUnfinished();
      await _settle();

      expect(client.named('study_session_abandoned'), hasLength(1));
      expect(client.named('study_session_completed'), isEmpty);
      expect(client.named('kanji_reviewed'), isEmpty);
      expect(
        client.named('study_session_abandoned').single['cards_reviewed'],
        0,
      );
    });

    test(
      'undo drops the reversed answer and a new card is learned once',
      () async {
        final client = _RecordingClient();
        final progress = MemoryProgressRepository(
          schedules: {'a': _due('a', now), 'b': _due('b', now)},
        );
        final controller = _controller(
          progress: progress,
          ids: ['a', 'b'],
          analytics: AnalyticsService(client: client),
          clock: () => now,
        );
        await _settle();

        controller.submit();
        expect(await controller.rate(ReviewResult.good), isNull);
        expect(await controller.undoLastAnswer(), isTrue);
        controller.submit();
        expect(await controller.rate(ReviewResult.good), isNull);
        controller.submit();
        expect(await controller.rate(ReviewResult.good), isNotNull);
        await _settle();

        final reviews = client.named('kanji_reviewed');
        expect(reviews, hasLength(2));
        expect(reviews.map((event) => event['result']), ['good', 'good']);
        expect(client.named('study_session_completed'), hasLength(1));
        expect(
          client.named('study_session_completed').single['new_cards_learned'],
          0,
        );
      },
    );

    test(
      'introducing a card counts as learned and mark-as-known does not',
      () async {
        final learned = _RecordingClient();
        final learnProgress = MemoryProgressRepository();
        final learn = _controller(
          progress: learnProgress,
          ids: ['a'],
          analytics: AnalyticsService(client: learned),
          clock: () => now,
        );
        await _settle();
        learn.beginPractice();
        // The first retrieval is still inside this sitting, so introduction
        // itself does not end the session.
        expect(await learn.completePractice(), isNull);
        expect(
          (await learnProgress.getSchedule('a'))!.state,
          CardLearningState.learning,
        );
        learn.submit();
        expect(await learn.rate(ReviewResult.good), isNotNull);
        await _settle();
        final reviewed = learned.named('kanji_reviewed').single;
        expect(reviewed['result'], 'good');
        expect(reviewed['is_new'], 1);
        expect(reviewed['review_category'], 'new');
        expect(
          learned.named('study_session_completed').single['new_cards_learned'],
          1,
        );

        final known = _RecordingClient();
        final knownController = _controller(
          progress: MemoryProgressRepository(),
          ids: ['b'],
          analytics: AnalyticsService(client: known),
          clock: () => now,
        );
        await _settle();
        expect(await knownController.markCurrentAsKnown(), isNotNull);
        await _settle();
        expect(known.named('kanji_reviewed'), isEmpty);
        expect(
          known.named('study_session_completed').single['new_cards_learned'],
          0,
        );
      },
    );

    test('practice mode and a throwing client do not break study', () async {
      final practice = _RecordingClient();
      final practiceController = _controller(
        progress: MemoryProgressRepository(),
        ids: ['a'],
        practice: true,
        analytics: AnalyticsService(client: practice),
        clock: () => now,
      );
      practiceController.beginPractice();
      await practiceController.completePractice();
      practiceController.submit();
      await practiceController.rate(ReviewResult.good);
      practiceController.abandonIfUnfinished();
      await _settle();
      expect(practice.events, isEmpty);

      final progress = MemoryProgressRepository(
        schedules: {'a': _due('a', now)},
      );
      final controller = _controller(
        progress: progress,
        ids: ['a'],
        analytics: AnalyticsService(client: _ThrowingClient()),
        clock: () => now,
      );
      controller.submit();
      await controller.rate(ReviewResult.good);
      await _settle();
      expect((await progress.getSchedule('a'))!.reviewCount, greaterThan(2));
    });

    test('study anyway overrides a reinforcement plan', () async {
      final client = _RecordingClient();
      final progress = MemoryProgressRepository(
        schedules: {'a': _due('a', now)},
        dailySessionPlan: _matchingPlan(
          now,
          cardIds: ['a'],
          dayType: StudyDayType.reinforcement,
        ),
      );
      _controller(
        progress: progress,
        ids: ['a'],
        studyAnyway: true,
        analytics: AnalyticsService(client: client),
        clock: () => now,
      );
      await _settle();
      expect(
        client.named('study_session_started').single['session_type'],
        'study_anyway',
      );

      final reinforcement = _RecordingClient();
      final reinforcementController = _controller(
        progress: progress,
        ids: ['a'],
        analytics: AnalyticsService(client: reinforcement),
        clock: () => now,
      );
      await _settle();
      expect(
        reinforcement.named('study_session_started').single['session_type'],
        'reinforcement',
      );
      reinforcementController.abandonIfUnfinished();
    });
  });

  group('placement events', () {
    test('a new user skips the test and a real test reports once', () async {
      final skipped = _RecordingClient();
      final skippedController = _placement(
        analytics: AnalyticsService(client: skipped),
      );
      await skippedController.load();
      await skippedController.choose(PlacementSelfAssessment.newUser);
      await _settle();
      expect(skipped.events, isEmpty);

      final client = _RecordingClient();
      final controller = _placement(
        analytics: AnalyticsService(client: client),
        maxQuestions: 1,
      );
      await controller.load();
      await controller.choose(PlacementSelfAssessment.beginner);
      controller.start();
      controller.start();
      await controller.answer(known: true);
      await _settle();

      expect(client.named('placement_test_started'), hasLength(1));
      final completed = client.named('placement_test_completed').single;
      expect(completed['questions_answered'], 1);
      expect(completed['estimated_level'], greaterThan(0));
    });

    test('resuming a saved run does not start the test again', () async {
      final client = _RecordingClient();
      final progress = MemoryProgressRepository();
      final service = _placementService(progress);
      await service.saveSelfAssessment(PlacementSelfAssessment.intermediate);
      final cards = await service.candidates();
      await service.saveAnswers([
        PlacementAnswer(cardId: cards.first.id, known: false),
      ]);
      final controller = PlacementController(
        service: service,
        engine: const PlacementTestEngine(maxQuestions: 5, selectionSeed: 1),
        analytics: AnalyticsService(client: client),
      );
      await controller.load();
      controller.start();
      await _settle();
      expect(client.named('placement_test_started'), isEmpty);
      expect(controller.isResuming, isTrue);
    });
  });

  group('settings events', () {
    test('goal and reminder changes emit once per actual change', () async {
      final client = _RecordingClient();
      final controller = SettingsController(
        progressRepository: MemoryProgressRepository(),
        analytics: AnalyticsService(client: client),
      );
      await controller.load();
      await controller.setDailyStudyMinutes(
        AppSettings.defaultDailyStudyMinutes,
      );
      await controller.setDailyStudyMinutes(10);
      await controller.setDailyStudyMinutes(10);
      // Reminders start enabled, so turning them on is not a change.
      await controller.setDailyReminderEnabled(true);
      await controller.setDailyReminderEnabled(false);
      await controller.setDailyReminderEnabled(false);
      await controller.setReminderTime(const ReminderTime(hour: 8, minute: 30));
      await _settle();

      expect(
        client.named('daily_goal_changed').single['daily_goal_minutes'],
        10,
      );
      final reminders = client.named('reminder_settings_changed');
      expect(reminders, hasLength(2));
      expect(reminders.first['enabled'], 0);
      expect(reminders.last['enabled'], 0);
      expect(reminders.last['reminder_hour'], 8);
      expect(reminders.last['reminder_minute'], 30);
    });
  });

  group('purchase events', () {
    test('verified purchases, restores, and failures stay distinct', () async {
      final client = _RecordingClient();
      final billing = _Billing(
        lifetime: const CurriculumProduct(
          id: fullCurriculumUnlock,
          price: r'$79.99',
          raw: Object(),
        ),
        monthly: const CurriculumProduct(
          id: fullCurriculumMonthly,
          price: r'$8.99',
          raw: Object(),
          billingPeriod: 'P1M',
        ),
      );
      final access = CurriculumAccess(
        progressRepository: MemoryProgressRepository(),
        repository: MemoryCurriculumRepository(
          record: const CurriculumRecord(backfillCompleted: true),
        ),
        billing: billing,
        analytics: CurriculumAnalytics(
          events: AnalyticsService(client: client),
        ),
        clock: () => now,
      );
      await access.ensureLoaded();
      await access.buyMonthly();
      await _settle();
      expect(
        client.named('purchase_started').single['purchase_type'],
        'subscription',
      );
      expect(client.named('purchase_completed'), isEmpty);

      billing.emit(
        CurriculumPurchaseUpdate(
          productId: fullCurriculumMonthly,
          status: CurriculumPurchaseStatus.pending,
          verificationData: '',
        ),
      );
      await _settle();
      expect(client.named('purchase_completed'), isEmpty);

      billing.emit(
        const CurriculumPurchaseUpdate(
          productId: fullCurriculumMonthly,
          status: CurriculumPurchaseStatus.canceled,
        ),
      );
      await _settle();
      expect(client.named('purchase_failed'), isEmpty);
      expect(client.named('purchase_completed'), isEmpty);

      final purchased = CurriculumPurchaseUpdate(
        productId: fullCurriculumMonthly,
        purchaseId: 'tx-monthly',
        status: CurriculumPurchaseStatus.purchased,
        verificationData: 'signed-receipt',
        subscriptionState: MonthlySubscriptionState.active,
        subscriptionExpiresAt: now.add(const Duration(days: 30)),
      );
      billing.emit(purchased);
      billing.emit(purchased);
      await _settle();
      expect(client.named('purchase_completed'), hasLength(1));
      expect(client.named('purchase_restored'), isEmpty);

      billing.emit(
        CurriculumPurchaseUpdate(
          productId: fullCurriculumMonthly,
          purchaseId: 'tx-monthly',
          status: CurriculumPurchaseStatus.restored,
          verificationData: 'signed-receipt',
          subscriptionState: MonthlySubscriptionState.active,
          subscriptionExpiresAt: now.add(const Duration(days: 30)),
        ),
      );
      await _settle();
      expect(client.named('purchase_restored'), isEmpty);

      billing.emit(
        const CurriculumPurchaseUpdate(
          productId: fullCurriculumUnlock,
          purchaseId: 'tx-life',
          status: CurriculumPurchaseStatus.purchased,
          verificationData: '',
        ),
      );
      await _settle();
      expect(client.named('purchase_completed'), hasLength(1));
      expect(
        client.named('purchase_failed').single['error_category'],
        'verification_failed',
      );

      billing.emit(
        const CurriculumPurchaseUpdate(
          productId: fullCurriculumUnlock,
          status: CurriculumPurchaseStatus.error,
          errorCode: 'network_error',
        ),
      );
      billing.emit(
        const CurriculumPurchaseUpdate(
          productId: fullCurriculumUnlock,
          status: CurriculumPurchaseStatus.error,
          errorCode: 'network_error',
        ),
      );
      await _settle();
      expect(
        client.named('purchase_failed').map((event) => event['error_category']),
        ['verification_failed', 'network'],
      );
    });

    test('a verified restore grants purchase_restored once', () async {
      final client = _RecordingClient();
      final billing = _Billing();
      final access = CurriculumAccess(
        progressRepository: MemoryProgressRepository(),
        repository: MemoryCurriculumRepository(
          record: const CurriculumRecord(backfillCompleted: true),
        ),
        billing: billing,
        analytics: CurriculumAnalytics(
          events: AnalyticsService(client: client),
        ),
        clock: () => now,
      );
      await access.ensureLoaded();
      final restored = CurriculumPurchaseUpdate(
        productId: fullCurriculumUnlock,
        purchaseId: 'tx-restore',
        status: CurriculumPurchaseStatus.restored,
        verificationData: 'signed-receipt',
      );
      billing.emit(restored);
      billing.emit(restored);
      await _settle();
      expect(client.named('purchase_completed'), isEmpty);
      expect(client.named('purchase_restored'), hasLength(1));
      expect(
        client.named('purchase_restored').single['purchase_type'],
        'lifetime',
      );
      expect(access.lifetimeOwned, isTrue);
    });
  });

  group('reinforcement day', () {
    test('a newly saved reinforcement plan is reported once', () async {
      final client = _RecordingClient();
      final cards = [for (var i = 0; i < 8; i++) testCard('r$i')];
      final progress = MemoryProgressRepository(
        schedules: {for (final card in cards) card.id: _due(card.id, now)},
      );
      final service = DailyWorkloadService(
        kanjiRepository: FakeKanjiRepository(cards),
        progressRepository: progress,
        scorer: const CardPriorityScorer(recall: _FixedRecall(0.3)),
        analytics: AnalyticsService(client: client),
      );
      await service.read(now: now);
      await service.read(now: now);
      await _settle();

      final events = client.named('reinforcement_day_started');
      expect(events, hasLength(1));
      expect(events.single['day_type'], 'reinforcement');
      expect(events.single['trigger_category'], 'average_recall');
    });
  });

  testWidgets(
    'closing the review screen abandons the open session',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      const kanji = HardcodedKanjiRepository();
      final progress = SharedPrefsProgressRepository(prefs);
      final cards = await kanji.getAll();
      await progress.seedIfNeeded(cards.map((card) => card.id).toList());
      final client = _RecordingClient();
      final analytics = AnalyticsService(client: client);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ProgressRepository>.value(value: progress),
            Provider<SrsScheduler>.value(value: const SrsEngine()),
            Provider<AnalyticsService>.value(value: analytics),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: Builder(
              builder: (context) {
                return TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ReviewScreen(
                          cards: [cards.first],
                          config: const ReviewSessionConfig(
                            duration: Duration(minutes: 5),
                            maxCards: 5,
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open'),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(client.named('study_session_started'), hasLength(1));

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(client.named('study_session_abandoned'), hasLength(1));
      expect(client.named('study_session_completed'), isEmpty);
      expect(find.text('Open'), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

Future<void> _settle() async {
  await pumpEventQueue();
  await pumpEventQueue();
}

ReviewController _controller({
  required MemoryProgressRepository progress,
  required List<String> ids,
  required AnalyticsService analytics,
  required DateTime Function() clock,
  bool practice = false,
  bool studyAnyway = false,
  DateTime? startTime,
}) {
  return ReviewController(
    progressRepository: progress,
    srsEngine: const SrsEngine(),
    cards: [for (final id in ids) testCard(id)],
    config: const ReviewSessionConfig(
      duration: Duration(minutes: 5),
      maxCards: 5,
    ),
    isPractice: practice,
    isStudyAnyway: studyAnyway,
    schedules: Map<String, CardSchedule>.from(progress.schedules),
    analytics: analytics,
    clock: clock,
    startTime: startTime,
  );
}

PlacementController _placement({
  required AnalyticsService analytics,
  int maxQuestions = 12,
  MemoryProgressRepository? progress,
}) {
  return PlacementController(
    service: _placementService(progress ?? MemoryProgressRepository()),
    engine: PlacementTestEngine(maxQuestions: maxQuestions, selectionSeed: 1),
    analytics: analytics,
  );
}

PlacementService _placementService(MemoryProgressRepository progress) {
  final cards = [
    for (final difficulty in [10, 30, 50, 70, 90])
      testCard('p$difficulty', difficulty: difficulty),
  ];
  return PlacementService(
    kanjiRepository: FakeKanjiRepository(cards),
    progressRepository: progress,
    markAsKnown: MarkAsKnownService(
      progressRepository: progress,
      srsEngine: const SrsEngine(),
    ),
    clock: () => DateTime(2026, 6, 1, 9),
  );
}

DailySessionPlan _matchingPlan(
  DateTime now, {
  required List<String> cardIds,
  StudyDayType dayType = StudyDayType.normal,
}) {
  const settings = AppSettings();
  return DailySessionPlan(
    studyDate: settings.startOfDay.studyDate(now),
    budgetMinutes: settings.dailyStudyMinutes,
    newKanjiPerDay: settings.newKanjiPerDay,
    startOfDay: settings.startOfDay,
    curriculumMode: settings.curriculumMode,
    allowsNewKanji: true,
    dayType: dayType,
    cardIds: cardIds,
  );
}

CardSchedule _due(String id, DateTime now) {
  return CardSchedule(
    cardId: id,
    state: CardLearningState.review,
    reviewCount: 2,
    correctCount: 2,
    incorrectCount: 0,
    dueAt: now.subtract(const Duration(hours: 1)),
    interval: const Duration(days: 1),
    ease: 2.5,
    lastReviewedAt: now.subtract(const Duration(days: 2)),
    consecutiveGoodCount: 2,
  );
}

class _FixedRecall extends RecallEstimator {
  const _FixedRecall(this.value);

  final double value;

  @override
  double probability({
    required CardSchedule? schedule,
    required DateTime now,
    required bool isNew,
  }) {
    return value;
  }
}

class _RecordingClient extends AnalyticsClient {
  final events = <_LoggedEvent>[];

  List<Map<String, Object>> named(String name) {
    return [
      for (final event in events)
        if (event.name == name) event.parameters,
    ];
  }

  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) async {
    events.add(_LoggedEvent(name, Map<String, Object>.from(parameters)));
  }
}

class _LoggedEvent {
  _LoggedEvent(this.name, this.parameters);

  final String name;
  final Map<String, Object> parameters;
}

class _ThrowingClient extends AnalyticsClient {
  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) async {
    throw StateError('analytics unavailable');
  }
}

class _Billing implements CurriculumBilling {
  _Billing({this.lifetime, this.monthly});

  final _updates = StreamController<List<CurriculumPurchaseUpdate>>.broadcast();
  final CurriculumProduct? lifetime;
  final CurriculumProduct? monthly;

  void emit(CurriculumPurchaseUpdate update) => _updates.add([update]);

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<CurriculumProduct?> loadProduct() async => lifetime;

  @override
  Future<CurriculumCatalog> loadCatalog() async {
    return CurriculumCatalog(lifetime: lifetime, monthly: monthly);
  }

  @override
  Future<bool> startPurchase(CurriculumProduct product) async => true;

  @override
  Future<void> restorePurchases() async {}

  @override
  Future<EntitlementQueryResult> queryEntitlement() async {
    return EntitlementQueryResult.unavailable;
  }

  @override
  Future<StoreEntitlementSnapshot> queryStoreEntitlement() async {
    return const StoreEntitlementSnapshot(
      lifetime: EntitlementQueryResult.unavailable,
    );
  }

  @override
  Stream<List<CurriculumPurchaseUpdate>> get purchaseUpdates => _updates.stream;

  @override
  Future<void> complete(CurriculumPurchaseUpdate update) async {}
}

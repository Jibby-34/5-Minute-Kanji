import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fiveminutekanji/app.dart';
import 'package:fiveminutekanji/core/models/daily_goal.dart';
import 'package:fiveminutekanji/core/models/kanji_card.dart';
import 'package:fiveminutekanji/core/models/notification_settings.dart';
import 'package:fiveminutekanji/core/models/onboarding.dart';
import 'package:fiveminutekanji/core/models/placement.dart';
import 'package:fiveminutekanji/core/models/progress.dart';
import 'package:fiveminutekanji/data/shared_prefs_progress_repository.dart';
import 'package:fiveminutekanji/repositories/progress_repository.dart';
import 'package:fiveminutekanji/services/daily_workload.dart';
import 'package:fiveminutekanji/services/daily_workload_estimator.dart';
import 'package:fiveminutekanji/services/notification_gateway.dart';
import 'package:fiveminutekanji/services/onboarding_service.dart';
import 'package:fiveminutekanji/services/reminder_scheduler.dart';

import 'support/fake_notifications.dart';
import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  void usePhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('OnboardingService', () {
    OnboardingService serviceFor(ProgressRepository progress) {
      return OnboardingService(progressRepository: progress);
    }

    test('a fresh install starts at the beginning', () async {
      final progress = MemoryProgressRepository();

      expect(
        await serviceFor(progress).resolveStage(),
        OnboardingStage.notStarted,
      );
      // Nothing is written until the user actually starts.
      expect(progress.onboarding.stage, OnboardingStage.notStarted);
    });

    test('an install from before onboarding is not sent through it', () async {
      final progress = MemoryProgressRepository();
      await completePlacementTest(progress);

      expect(
        await serviceFor(progress).resolveStage(),
        OnboardingStage.completed,
      );
      expect(progress.onboarding.stage, OnboardingStage.completed);
    });

    test('a user who has already studied is not sent through it', () async {
      final progress = MemoryProgressRepository();
      progress.streak = StreakInfo(
        current: 3,
        lastStudyDate: DateTime(2026, 9, 2),
      );

      expect(
        await serviceFor(progress).resolveStage(),
        OnboardingStage.completed,
      );
    });

    test('a session finished elsewhere counts as the first one', () async {
      final progress = MemoryProgressRepository();
      final service = serviceFor(progress);
      await service.advanceTo(OnboardingStage.dailyGoalSelected);
      progress.streak = StreakInfo(
        current: 1,
        lastStudyDate: DateTime(2026, 9, 2),
      );

      expect(
        await service.resolveStage(),
        OnboardingStage.firstSessionCompleted,
      );
    });

    test('a stage never moves backwards', () async {
      final progress = MemoryProgressRepository();
      final service = serviceFor(progress);

      await service.advanceTo(OnboardingStage.firstSessionCompleted);
      await service.advanceTo(OnboardingStage.placementInProgress);

      expect(progress.onboarding.stage, OnboardingStage.firstSessionCompleted);
    });

    test('a goal becomes a daily allowance that fits inside it', () async {
      const estimator = DailyWorkloadEstimator();

      for (final goal in DailyGoal.presets) {
        final progress = MemoryProgressRepository();
        await serviceFor(progress).selectDailyGoal(goal);

        final perDay = progress.settings.newKanjiPerDay;
        expect(perDay, greaterThan(0));
        expect(
          estimator
              .estimate(newKanjiPerDay: perDay, averageSecondsPerCard: 12)
              .minMinutes,
          lessThanOrEqualTo(goal.minutes),
        );
        expect(
          estimator
              .estimate(newKanjiPerDay: perDay + 1, averageSecondsPerCard: 12)
              .minMinutes,
          greaterThan(goal.minutes),
        );
      }
    });

    test('a bigger goal means more new kanji a day', () async {
      final service = serviceFor(MemoryProgressRepository());

      expect(
        service.newKanjiPerDayFor(const DailyGoal(5)),
        lessThan(service.newKanjiPerDayFor(const DailyGoal(10))),
      );
      expect(
        service.newKanjiPerDayFor(const DailyGoal(10)),
        lessThan(service.newKanjiPerDayFor(const DailyGoal(15))),
      );
    });

    test('choosing a goal does not disturb other settings', () async {
      final progress = MemoryProgressRepository();
      progress.settings = const AppSettings(
        notifications: NotificationSettings(dailyReminderEnabled: false),
      );

      await serviceFor(progress).selectDailyGoal(DailyGoal.recommended);

      expect(progress.settings.notifications.dailyReminderEnabled, isFalse);
      expect(progress.onboarding.stage, OnboardingStage.dailyGoalSelected);
    });

    test('a seen hint is remembered', () async {
      final progress = MemoryProgressRepository();
      final service = serviceFor(progress);

      expect(await service.hasSeenHint(OnboardingHint.drawFromMemory), isFalse);
      await service.markHintSeen(OnboardingHint.drawFromMemory);

      expect(await service.hasSeenHint(OnboardingHint.drawFromMemory), isTrue);
      expect(await service.hasSeenHint(OnboardingHint.compareDrawing), isFalse);
    });

    test('hints dismissed together are both remembered', () async {
      final progress = MemoryProgressRepository();
      final service = serviceFor(progress);

      await service.markHintsSeen(const [
        OnboardingHint.compareDrawing,
        OnboardingHint.rateRecall,
      ]);

      expect(progress.onboarding.seenHints, {
        OnboardingHint.compareDrawing,
        OnboardingHint.rateRecall,
      });
    });

    test('onboarding state survives a JSON round trip', () {
      const original = OnboardingProgress(
        stage: OnboardingStage.dailyGoalSelected,
        seenHints: {OnboardingHint.rateRecall},
      );

      final restored = OnboardingProgress.fromJson(original.toJson());

      expect(restored.stage, OnboardingStage.dailyGoalSelected);
      expect(restored.seenHints, {OnboardingHint.rateRecall});
    });

    test('unknown stored values fall back to the beginning', () {
      final restored = OnboardingProgress.fromJson(const {
        'stage': 'somethingElse',
        'seenHints': ['nope'],
      });

      expect(restored.stage, OnboardingStage.notStarted);
      expect(restored.seenHints, isEmpty);
    });
  });

  group('first launch', () {
    final cards = [
      testCard(
        'n5-001',
        character: '一',
        keyword: 'one',
        jlptLevel: JlptLevel.n5,
      ),
      testCard(
        'n5-002',
        character: '二',
        keyword: 'two',
        jlptLevel: JlptLevel.n5,
      ),
      testCard(
        'n5-003',
        character: '三',
        keyword: 'three',
        jlptLevel: JlptLevel.n5,
      ),
    ];

    Future<SharedPrefsProgressRepository> freshProgress() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final progress = SharedPrefsProgressRepository(prefs);
      await progress.seedIfNeeded(cards.map((card) => card.id).toList());
      return progress;
    }

    Future<void> pumpApp(
      WidgetTester tester,
      ProgressRepository progress, {
      ReminderScheduler? reminders,
    }) async {
      await tester.pumpWidget(
        FiveMinuteKanjiApp(
          kanjiRepository: FakeKanjiRepository(cards),
          progressRepository: progress,
          reminderScheduler: reminders,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    /// Answers the placement test with "I don't know it" all the way through.
    Future<void> answerPlacement(WidgetTester tester) async {
      await tester.tap(find.text('Start Placement Test'));
      await tester.pumpAndSettle();
      while (find.text("I don't know it").evaluate().isNotEmpty) {
        await tester.tap(find.text("I don't know it"));
        await tester.pumpAndSettle();
      }
    }

    /// Works through the session until it ends, taking the shortest honest
    /// path through each phase. Stops early once [until] is on screen.
    Future<void> finishSession(WidgetTester tester, {Finder? until}) async {
      for (var step = 0; step < 60; step++) {
        if (until != null && until.evaluate().isNotEmpty) return;
        if (find.text('Practice Writing').evaluate().isNotEmpty) {
          await tester.tap(find.text('Practice Writing'));
        } else if (find.text('Done').evaluate().isNotEmpty) {
          await tester.tap(find.text('Done'));
        } else if (find.text('Submit').evaluate().isNotEmpty) {
          await tester.tap(find.text('Submit'));
        } else if (find.text('Good').evaluate().isNotEmpty) {
          await tester.tap(find.text('Good'));
        } else {
          return;
        }
        await tester.pumpAndSettle();
      }
      fail('the session never finished');
    }

    /// Home, whether or not there is anything left to do today.
    Finder homeScreen() => find.text('kanji remaining today');

    testWidgets('welcome, placement, goal, first session, then Home', (
      tester,
    ) async {
      usePhoneViewport(tester);
      final progress = await freshProgress();
      await pumpApp(tester, progress);

      // 1. Welcome.
      expect(find.text('5-Minute Kanji'), findsOneWidget);
      expect(find.text('Learn kanji in 5 minutes a day.'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
      expect(find.textContaining('Skip'), findsNothing);
      expect(find.text('Start Review'), findsNothing);

      await tester.tap(find.text('Get Started'));
      await tester.pumpAndSettle();

      // 2. The existing placement test.
      expect(find.text("Let's find your starting point"), findsOneWidget);
      await answerPlacement(tester);

      // 3. Results.
      expect(find.text("You're all set!"), findsOneWidget);
      expect(find.text('Starting around JLPT N5'), findsOneWidget);
      expect(find.text('Start Learning'), findsOneWidget);

      await tester.tap(find.text('Start Learning'));
      await tester.pumpAndSettle();

      // 4. Daily goal, with five minutes recommended and selected.
      expect(
        find.text('How much time do you want to study each day?'),
        findsOneWidget,
      );
      expect(find.text('5 minutes'), findsOneWidget);
      expect(find.text('Recommended'), findsOneWidget);
      expect(find.text('Custom'), findsOneWidget);
      expect(find.textContaining('new kanji'), findsOneWidget);

      await tester.tap(find.text('Begin'));
      await tester.pumpAndSettle();

      // The goal lands in the setting the user can change later.
      final settings = await progress.getSettings();
      expect(settings.newKanjiPerDay, 4);
      expect(settings.dailyStudyMinutes, 5);

      // 5. The real learning screen, with its first-time pointers.
      expect(find.text('Practice Writing'), findsOneWidget);
      expect(find.text('Draw the kanji from memory.'), findsNothing);

      // Learn the new kanji until the first one comes back to be recalled.
      await finishSession(tester, until: find.text('Submit'));

      expect(find.text('Submit'), findsOneWidget);
      expect(find.text('Draw the kanji from memory.'), findsOneWidget);

      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();

      expect(
        find.text('Compare your drawing with the real kanji.'),
        findsOneWidget,
      );
      expect(
        find.text('Good = you remembered it · Again = see it sooner'),
        findsOneWidget,
      );

      await tester.tap(find.text('Good'));
      await tester.pumpAndSettle();

      // Each pointer is shown once, and remembered.
      expect(find.text('Draw the kanji from memory.'), findsNothing);
      expect(
        find.text('Compare your drawing with the real kanji.'),
        findsNothing,
      );
      expect((await progress.getOnboarding()).seenHints, {
        OnboardingHint.drawFromMemory,
        OnboardingHint.compareDrawing,
        OnboardingHint.rateRecall,
      });

      await finishSession(tester);

      // 6. Day one, with the numbers the session actually produced.
      expect(find.text('Day 1 complete!'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('kanji learned'), findsOneWidget);
      expect(find.text('🔥'), findsOneWidget);
      expect(find.text('day streak'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // 7. Home.
      expect(homeScreen(), findsOneWidget);
      expect(find.text('Day 1 complete!'), findsNothing);
      expect((await progress.getOnboarding()).stage, OnboardingStage.completed);
    });

    testWidgets('a returning user goes straight to Home', (tester) async {
      usePhoneViewport(tester);
      final progress = await freshProgress();
      await completeOnboarding(progress);

      await pumpApp(tester, progress);

      expect(find.text('Get Started'), findsNothing);
      expect(find.text("Let's find your starting point"), findsNothing);
      expect(find.text('Start Review'), findsOneWidget);
    });

    testWidgets('an existing placement is never asked for twice', (
      tester,
    ) async {
      usePhoneViewport(tester);
      final progress = await freshProgress();
      // An install from before onboarding existed.
      await progress.savePlacement(const PlacementProgress(completed: true));

      await pumpApp(tester, progress);

      expect(find.text('Get Started'), findsNothing);
      expect(find.text("Let's find your starting point"), findsNothing);
      expect(find.text('Start Review'), findsOneWidget);
    });

    testWidgets('closing the app at the goal step resumes there', (
      tester,
    ) async {
      usePhoneViewport(tester);
      final progress = await freshProgress();
      await pumpApp(tester, progress);
      await tester.tap(find.text('Get Started'));
      await tester.pumpAndSettle();
      await answerPlacement(tester);
      await tester.tap(find.text('Start Learning'));
      await tester.pumpAndSettle();
      expect(
        find.text('How much time do you want to study each day?'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await pumpApp(
        tester,
        SharedPrefsProgressRepository(await SharedPreferences.getInstance()),
      );

      expect(
        find.text('How much time do you want to study each day?'),
        findsOneWidget,
      );
      expect(find.text('Get Started'), findsNothing);
    });

    testWidgets('closing the first session leaves the app usable', (
      tester,
    ) async {
      usePhoneViewport(tester);
      final progress = await freshProgress();
      await pumpApp(tester, progress);
      await tester.tap(find.text('Get Started'));
      await tester.pumpAndSettle();
      await answerPlacement(tester);
      await tester.tap(find.text('Start Learning'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Begin'));
      await tester.pumpAndSettle();

      expect(find.text('Practice Writing'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      // Home, not a dead end, and the session is still owed.
      expect(find.text('Start Review'), findsOneWidget);
      expect(
        (await progress.getOnboarding()).stage,
        OnboardingStage.dailyGoalSelected,
      );
    });

    testWidgets('a custom goal can be chosen with a slider', (tester) async {
      usePhoneViewport(tester);
      final progress = await freshProgress();
      await progress.saveOnboarding(
        const OnboardingProgress(stage: OnboardingStage.placementCompleted),
      );
      await pumpApp(tester, progress);

      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsOneWidget);

      await tester.drag(find.byType(Slider), const Offset(-200, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Begin'));
      await tester.pumpAndSettle();

      expect((await progress.getSettings()).newKanjiPerDay, lessThan(4));
    });

    testWidgets('the reminder question comes after the first session', (
      tester,
    ) async {
      usePhoneViewport(tester);
      final progress = await freshProgress();
      final gateway = FakeNotificationGateway(
        permissionStatus: NotificationPermission.notDetermined,
        permissionOnRequest: NotificationPermission.granted,
      );
      final reminders = ReminderScheduler(
        gateway: gateway,
        progressRepository: progress,
        workloadService: DailyWorkloadService(
          kanjiRepository: FakeKanjiRepository(cards),
          progressRepository: progress,
        ),
      );

      await pumpApp(tester, progress, reminders: reminders);
      await tester.tap(find.text('Get Started'));
      await tester.pumpAndSettle();
      await answerPlacement(tester);
      await tester.tap(find.text('Start Learning'));
      await tester.pumpAndSettle();

      // Nothing has asked the OS for permission yet.
      expect(gateway.requestCount, 0);

      await tester.tap(find.text('Begin'));
      await tester.pumpAndSettle();
      await finishSession(tester);
      expect(find.text('Day 1 complete!'), findsOneWidget);
      expect(find.text('Want a reminder tomorrow?'), findsNothing);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Want a reminder tomorrow?'), findsOneWidget);
      await tester.tap(find.text('Remind Me'));
      await tester.pumpAndSettle();

      expect(gateway.requestCount, 1);
      expect(homeScreen(), findsOneWidget);
      expect(
        (await progress.getSettings()).notifications.dailyReminderEnabled,
        isTrue,
      );
      expect((await progress.getOnboarding()).stage, OnboardingStage.completed);
    });

    testWidgets('declining the reminder still lets the user in', (
      tester,
    ) async {
      usePhoneViewport(tester);
      final progress = await freshProgress();
      await progress.saveOnboarding(
        const OnboardingProgress(stage: OnboardingStage.firstSessionCompleted),
      );
      final gateway = FakeNotificationGateway(
        permissionStatus: NotificationPermission.notDetermined,
      );
      final reminders = ReminderScheduler(
        gateway: gateway,
        progressRepository: progress,
        workloadService: DailyWorkloadService(
          kanjiRepository: FakeKanjiRepository(cards),
          progressRepository: progress,
        ),
      );

      await pumpApp(tester, progress, reminders: reminders);
      await tester.pumpAndSettle();

      expect(find.text('Want a reminder tomorrow?'), findsOneWidget);
      await tester.tap(find.text('Maybe Later'));
      await tester.pumpAndSettle();

      expect(gateway.requestCount, 0);
      expect(find.text('Start Review'), findsOneWidget);
      expect(
        (await progress.getSettings()).notifications.dailyReminderEnabled,
        isFalse,
      );
      expect((await progress.getOnboarding()).stage, OnboardingStage.completed);
    });

    testWidgets('granted permission skips the reminder question', (
      tester,
    ) async {
      usePhoneViewport(tester);
      final progress = await freshProgress();
      await progress.saveOnboarding(
        const OnboardingProgress(stage: OnboardingStage.firstSessionCompleted),
      );
      final reminders = ReminderScheduler(
        gateway: FakeNotificationGateway(),
        progressRepository: progress,
        workloadService: DailyWorkloadService(
          kanjiRepository: FakeKanjiRepository(cards),
          progressRepository: progress,
        ),
      );

      await pumpApp(tester, progress, reminders: reminders);
      await tester.pumpAndSettle();

      expect(find.text('Want a reminder tomorrow?'), findsNothing);
      expect(find.text('Start Review'), findsOneWidget);
      expect((await progress.getOnboarding()).stage, OnboardingStage.completed);
    });
  });
}

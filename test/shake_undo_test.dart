import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/kanji_card.dart';
import 'package:fiveminutekanji/core/models/progress.dart';
import 'package:fiveminutekanji/core/models/review.dart';
import 'package:fiveminutekanji/core/models/study_phase.dart';
import 'package:fiveminutekanji/core/theme/app_theme.dart';
import 'package:fiveminutekanji/data/hardcoded_kanji_repository.dart';
import 'package:fiveminutekanji/data/shared_prefs_progress_repository.dart';
import 'package:fiveminutekanji/features/review/review_controller.dart';
import 'package:fiveminutekanji/features/review/review_screen.dart';
import 'package:fiveminutekanji/features/settings/settings_screen.dart';
import 'package:fiveminutekanji/repositories/progress_repository.dart';
import 'package:fiveminutekanji/services/reminder_scheduler.dart';
import 'package:fiveminutekanji/services/shake_detector.dart';
import 'package:fiveminutekanji/services/srs_engine.dart';
import 'package:fiveminutekanji/services/srs_scheduler.dart';

import 'support/fakes.dart';

const _discovery = 'Made a mistake? Shake your phone to undo your last answer.';
const _confirmation = 'Last answer undone';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 2, 8);
  const config = ReviewSessionConfig(
    duration: Duration(minutes: 5),
    maxCards: 3,
  );
  const engine = SrsEngine();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  CardSchedule dueReview(String id) {
    return CardSchedule(
      cardId: id,
      state: CardLearningState.review,
      reviewCount: 1,
      correctCount: 1,
      incorrectCount: 0,
      dueAt: now,
      interval: SrsEngine.graduatingInterval,
      ease: 2.5,
      lastReviewedAt: now,
      consecutiveGoodCount: 1,
    );
  }

  void expectSchedule(CardSchedule? actual, CardSchedule expected) {
    expect(actual, isNotNull);
    expect(actual!.state, expected.state);
    expect(actual.reviewCount, expected.reviewCount);
    expect(actual.correctCount, expected.correctCount);
    expect(actual.incorrectCount, expected.incorrectCount);
    expect(actual.dueAt, expected.dueAt);
    expect(actual.interval, expected.interval);
    expect(actual.ease, expected.ease);
    expect(actual.lastReviewedAt, expected.lastReviewedAt);
    expect(actual.consecutiveGoodCount, expected.consecutiveGoodCount);
  }

  Future<ReviewController> controllerFor({
    required MemoryProgressRepository progress,
    required List<String> ids,
    bool practice = false,
    bool alreadyReviewed = true,
    DateTime Function()? clock,
  }) async {
    final cards = ids.map(testCard).toList();
    await progress.seedIfNeeded(ids, now: now);
    if (alreadyReviewed) {
      for (final id in ids) {
        await progress.saveSchedule(dueReview(id));
      }
    }
    return ReviewController(
      progressRepository: progress,
      srsEngine: engine,
      cards: cards,
      config: config,
      isPractice: practice,
      startTime: now,
      clock: clock ?? () => now,
      schedules: Map<String, CardSchedule>.from(progress.schedules),
    );
  }

  group('shake gesture', () {
    test('resting gravity and a small bump are not a shake', () {
      final gesture = ShakeGesture();
      expect(gesture.consider(0, 0, ShakeGesture.standardGravity), isFalse);
      expect(gesture.consider(0, 12, 9), isFalse);
    });

    test('a hard shake counts once until the cooldown passes', () {
      var time = DateTime(2026, 9, 2, 8);
      final gesture = ShakeGesture(clock: () => time);

      expect(gesture.consider(0, 0, 30), isTrue);
      expect(gesture.consider(30, 0, 0), isFalse);
      time = time.add(const Duration(milliseconds: 1199));
      expect(gesture.consider(0, 30, 0), isFalse);
      time = time.add(const Duration(milliseconds: 1));
      expect(gesture.consider(0, 0, 30), isTrue);
    });
  });

  group('undo last answer', () {
    test('does nothing before an answer or after the session ends', () async {
      final progress = MemoryProgressRepository();
      final controller = await controllerFor(progress: progress, ids: ['a']);

      expect(await controller.undoLastAnswer(), isFalse);
      controller.submit();
      expect(await controller.undoLastAnswer(), isFalse);

      final summary = await controller.rate(ReviewResult.good);
      expect(summary, isNotNull);
      expect(controller.isComplete, isTrue);
      expect(await controller.undoLastAnswer(), isFalse);
      expect(progress.history, hasLength(1));
      expect(progress.streak.current, 1);
      expect(controller.takeShakeUndoHint(), isFalse);
      expect(progress.shakeUndoHintSeen, isFalse);

      final schedule = await progress.getSchedule('a');
      expectSchedule(
        schedule,
        engine.schedule(
          current: dueReview('a'),
          result: ReviewResult.good,
          now: now,
        ),
      );
    });

    test(
      'Again then undo then Good schedules the original card once',
      () async {
        final progress = MemoryProgressRepository();
        final controller = await controllerFor(
          progress: progress,
          ids: ['a', 'b'],
        );
        final before = (await progress.getSchedule('a'))!;

        controller.submit();
        expect(await controller.rate(ReviewResult.again), isNull);
        expect(controller.current?.id, 'b');
        expect(await controller.undoLastAnswer(), isTrue);

        expect(controller.current?.id, 'a');
        expect(controller.phase, StudyPhase.compare);
        expect(controller.submitted, isTrue);
        expect(controller.session.reviewedCount, 0);
        expect(controller.session.againCount, 0);
        expect(progress.history, isEmpty);
        expectSchedule(await progress.getSchedule('a'), before);

        expect(await controller.rate(ReviewResult.good), isNull);
        expect(controller.current?.id, 'b');
        expect(controller.phase, StudyPhase.recall);
        expectSchedule(
          await progress.getSchedule('a'),
          engine.schedule(current: before, result: ReviewResult.good, now: now),
        );
        expect(progress.history.map((entry) => entry.rating), [
          ReviewResult.good,
        ]);
      },
    );

    test(
      'Good then undo then Again schedules the original card once',
      () async {
        final progress = MemoryProgressRepository();
        final controller = await controllerFor(
          progress: progress,
          ids: ['a', 'b'],
        );
        final before = (await progress.getSchedule('a'))!;

        controller.submit();
        expect(await controller.rate(ReviewResult.good), isNull);
        expect(await controller.undoLastAnswer(), isTrue);
        expect(await controller.rate(ReviewResult.again), isNull);

        expectSchedule(
          await progress.getSchedule('a'),
          engine.schedule(
            current: before,
            result: ReviewResult.again,
            now: now,
          ),
        );
        expect(progress.history.single.rating, ReviewResult.again);
        expect(controller.session.againCount, 1);
        expect(controller.session.successfulCount, 0);
      },
    );

    test('several answers can be undone from newest to oldest', () async {
      final progress = MemoryProgressRepository();
      final controller = await controllerFor(
        progress: progress,
        ids: ['a', 'b'],
      );
      final beforeA = (await progress.getSchedule('a'))!;
      final beforeB = (await progress.getSchedule('b'))!;

      controller.submit();
      await controller.rate(ReviewResult.again);
      controller.submit();
      await controller.rate(ReviewResult.good);

      expect(progress.history, hasLength(2));
      expect(await controller.undoLastAnswer(), isTrue);
      expect(controller.current?.id, 'b');
      expect(controller.phase, StudyPhase.compare);
      expectSchedule(await progress.getSchedule('b'), beforeB);
      expect(progress.history.single.rating, ReviewResult.again);

      expect(await controller.undoLastAnswer(), isTrue);
      expect(controller.current?.id, 'a');
      expect(controller.phase, StudyPhase.compare);
      expectSchedule(await progress.getSchedule('a'), beforeA);
      expectSchedule(await progress.getSchedule('b'), beforeB);
      expect(progress.history, isEmpty);
      expect(controller.session.reviewedCount, 0);
      expect(await controller.undoLastAnswer(), isFalse);

      expect(await controller.rate(ReviewResult.good), isNull);
      expectSchedule(
        await progress.getSchedule('a'),
        engine.schedule(current: beforeA, result: ReviewResult.good, now: now),
      );
    });

    test('a second undo is ignored while the first is still saving', () async {
      final progress = MemoryProgressRepository();
      final controller = await controllerFor(
        progress: progress,
        ids: ['a', 'b', 'c'],
      );

      controller.submit();
      await controller.rate(ReviewResult.again);
      controller.submit();
      await controller.rate(ReviewResult.good);

      final first = controller.undoLastAnswer();
      final second = controller.undoLastAnswer();
      expect(await second, isFalse);
      expect(await first, isTrue);
      expect(progress.history, hasLength(1));
      expect(await controller.undoLastAnswer(), isTrue);
      expect(progress.history, isEmpty);
    });

    test('a shake during the save cannot undo a half-written answer', () async {
      final progress = _GatedProgress();
      final gate = Completer<void>();
      final controller = await controllerFor(
        progress: progress,
        ids: ['a', 'b'],
      );
      progress
        ..armed = true
        ..gate = gate.future;

      controller.submit();
      final rating = controller.rate(ReviewResult.good);
      await progress.started.future;
      expect(controller.busy, isTrue);
      expect(await controller.undoLastAnswer(), isFalse);

      gate.complete();
      expect(await rating, isNull);
      expect(progress.history, hasLength(1));
      expect(await controller.undoLastAnswer(), isTrue);
      expect(progress.history, isEmpty);
    });

    test(
      'undo restores a newly introduced card to its pre-answer schedule',
      () async {
        final progress = MemoryProgressRepository();
        final controller = await controllerFor(
          progress: progress,
          ids: ['a', 'b'],
          alreadyReviewed: false,
        );

        controller.beginPractice();
        await controller.completePractice();
        controller.beginPractice();
        await controller.completePractice();
        expect(controller.current?.id, 'a');
        expect(controller.phase, StudyPhase.recall);
        final introduced = (await progress.getSchedule('a'))!;
        expect(introduced.state, CardLearningState.learning);
        expect(introduced.reviewCount, 0);
        expect(progress.dailyNewKanji.count, 2);

        controller.submit();
        await controller.rate(ReviewResult.good);
        expect(await controller.undoLastAnswer(), isTrue);

        expect(controller.current?.id, 'a');
        expect(controller.phase, StudyPhase.compare);
        expectSchedule(await progress.getSchedule('a'), introduced);
        expect(progress.history, isEmpty);
        expect(progress.dailyNewKanji.count, 2);

        await controller.rate(ReviewResult.again);
        expectSchedule(
          await progress.getSchedule('a'),
          engine.schedule(
            current: introduced,
            result: ReviewResult.again,
            now: now,
          ),
        );
        expect(progress.history.single.rating, ReviewResult.again);
      },
    );

    test(
      'undo puts the pace model back, then the new answer records once',
      () async {
        final progress = MemoryProgressRepository();
        var time = now;
        final controller = await controllerFor(
          progress: progress,
          ids: ['a', 'b'],
          clock: () => time,
        );

        controller.submit();
        time = now.add(const Duration(seconds: 4));
        await controller.rate(ReviewResult.good);
        expect(progress.reviewDurations.young.count, 1);
        expect(progress.reviewDurations.global.count, 1);

        expect(await controller.undoLastAnswer(), isTrue);
        expect(progress.reviewDurations.young.count, 0);
        expect(progress.reviewDurations.global.count, 0);

        time = time.add(const Duration(seconds: 4));
        await controller.rate(ReviewResult.again);
        expect(progress.reviewDurations.young.count, 1);
        expect(progress.reviewDurations.global.count, 1);
        expect(progress.history.single.rating, ReviewResult.again);
      },
    );

    test('practice undo removes the history and leaves the schedule', () async {
      final progress = MemoryProgressRepository();
      final controller = await controllerFor(
        progress: progress,
        ids: ['a', 'b'],
        practice: true,
        alreadyReviewed: false,
      );
      final before = (await progress.getSchedule('a'))!;

      controller.beginPractice();
      await controller.completePractice();
      controller.submit();
      await controller.rate(ReviewResult.good);
      expect(progress.history.single.isPractice, isTrue);

      expect(await controller.undoLastAnswer(), isTrue);
      expect(progress.history, isEmpty);
      expectSchedule(await progress.getSchedule('a'), before);
      expect(controller.phase, StudyPhase.compare);
      expect(controller.current?.id, 'a');

      await controller.rate(ReviewResult.again);
      expect(progress.history.single.rating, ReviewResult.again);
      expect(progress.history.single.isPractice, isTrue);
      expectSchedule(await progress.getSchedule('a'), before);
    });

    test(
      'the discovery hint is stored once, after a committed answer',
      () async {
        final progress = MemoryProgressRepository();
        final controller = await controllerFor(
          progress: progress,
          ids: ['a', 'b'],
        );

        expect(controller.takeShakeUndoHint(), isFalse);
        controller.submit();
        expect(controller.takeShakeUndoHint(), isFalse);

        await controller.rate(ReviewResult.good);
        expect(controller.takeShakeUndoHint(), isTrue);
        expect(controller.takeShakeUndoHint(), isFalse);
        expect(progress.shakeUndoHintSeen, isTrue);

        await controller.undoLastAnswer();
        controller.submit();
        await controller.rate(ReviewResult.again);
        expect(controller.takeShakeUndoHint(), isFalse);

        final later = await controllerFor(progress: progress, ids: ['a', 'b']);
        later.submit();
        await later.rate(ReviewResult.good);
        expect(later.takeShakeUndoHint(), isFalse);
      },
    );

    test('deleting a schedule and the hint survive a new repository', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final first = SharedPrefsProgressRepository(prefs);
      await first.seedIfNeeded(const ['a'], now: now);
      await first.saveSchedule(
        engine.schedule(
          current: (await first.getSchedule('a'))!,
          result: ReviewResult.good,
          now: now,
        ),
      );
      await first.addHistory(
        ReviewHistoryEntry(
          cardId: 'a',
          rating: ReviewResult.good,
          timestamp: now,
          timeOnCard: const Duration(seconds: 4),
        ),
      );
      await first.addHistory(
        ReviewHistoryEntry(
          cardId: 'a',
          rating: ReviewResult.again,
          timestamp: now.add(const Duration(minutes: 1)),
          timeOnCard: const Duration(seconds: 3),
        ),
      );
      expect(
        await first.removeLastHistory(
          ReviewHistoryEntry(
            cardId: 'a',
            rating: ReviewResult.again,
            timestamp: now.add(const Duration(minutes: 1)),
            timeOnCard: const Duration(seconds: 3),
          ),
        ),
        isTrue,
      );
      expect(
        await first.removeLastHistory(
          ReviewHistoryEntry(
            cardId: 'a',
            rating: ReviewResult.again,
            timestamp: now,
            timeOnCard: Duration.zero,
          ),
        ),
        isFalse,
      );
      await first.deleteSchedule('a');
      await first.markShakeUndoHintSeen();

      final reopened = SharedPrefsProgressRepository(prefs);
      expect(await reopened.getSchedule('a'), isNull);
      expect(await reopened.hasSeenShakeUndoHint(), isTrue);
      expect((await reopened.getHistory()).single.rating, ReviewResult.good);
      await reopened.markShakeUndoHintSeen();
      expect(await reopened.hasSeenShakeUndoHint(), isTrue);
    });
  });

  group('review screen', () {
    void usePhone(WidgetTester tester) {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    Future<SharedPrefsProgressRepository> reviewedProgress(
      List<String> ids,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final progress = SharedPrefsProgressRepository(prefs);
      for (final id in ids) {
        await progress.saveSchedule(dueReview(id));
      }
      return progress;
    }

    Future<void> pumpReview(
      WidgetTester tester, {
      required ProgressRepository progress,
      required List<KanjiCard> cards,
      ShakeEvents? shakes,
    }) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ProgressRepository>.value(value: progress),
            Provider<SrsScheduler>.value(value: engine),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: ReviewScreen(
              cards: cards,
              config: config,
              clock: () => now,
              shakeEvents: shakes,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'shows the discovery hint once, then only an undo confirmation',
      (tester) async {
        usePhone(tester);
        const kanji = HardcodedKanjiRepository();
        final cards = await kanji.getAll();
        final first = cards.first;
        final second = cards[1];
        final progress = await reviewedProgress([first.id, second.id]);
        var listeners = 0;
        final shakes = StreamController<void>.broadcast(
          onListen: () => listeners++,
          onCancel: () => listeners--,
        );

        await pumpReview(
          tester,
          progress: progress,
          cards: [first, second],
          shakes: _StreamShakes(shakes.stream),
        );

        shakes.add(null);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text(_confirmation), findsNothing);

        await tester.tap(find.text('Submit'));
        await tester.pumpAndSettle();
        expect(find.text(_discovery), findsNothing);

        await tester.tap(find.text('Good'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text(_discovery), findsOneWidget);
        expect(find.text(second.keyword), findsWidgets);

        await tester.pump(const Duration(seconds: 3));
        expect(find.text(_discovery), findsOneWidget);
        // The dismiss timer starts after the entrance animation, so this
        // covers the rest of the 4.5s and the exit.
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text(_discovery), findsNothing);

        await tester.tap(find.text('Submit'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Good'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text(_discovery), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await pumpReview(
          tester,
          progress: progress,
          cards: [first, second],
          shakes: _StreamShakes(shakes.stream),
        );
        await tester.tap(find.text('Submit'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Again'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text(_discovery), findsNothing);

        shakes.add(null);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text(_confirmation), findsOneWidget);
        expect(find.text('Again'), findsOneWidget);
        expect(find.text('Good'), findsOneWidget);
        expect(find.text(first.keyword), findsWidgets);

        await tester.tap(find.text('Good'));
        await tester.pumpAndSettle();
        expect(find.text(second.keyword), findsWidgets);
        expect(
          (await progress.getHistory())
              .where((entry) => entry.cardId == first.id)
              .map((entry) => entry.rating),
          [ReviewResult.good, ReviewResult.good],
        );

        await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
        await tester.pump();
        expect(listeners, 0);
        shakes.add(null);
        await tester.pump();
        expect(tester.takeException(), isNull);
        await shakes.close();
      },
    );

    testWidgets('a missing sensor still lets the review finish', (
      tester,
    ) async {
      usePhone(tester);
      const kanji = HardcodedKanjiRepository();
      final cards = await kanji.getAll();
      final first = cards.first;
      final progress = await reviewedProgress([first.id]);

      await pumpReview(
        tester,
        progress: progress,
        cards: [first],
        shakes: _BrokenShakes(),
      );

      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Good'));
      await tester.pumpAndSettle();
      expect(find.text("You're done for today!"), findsOneWidget);
      expect(find.text(_discovery), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('settings explains shake to undo without a control', (
      tester,
    ) async {
      usePhone(tester);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ProgressRepository>.value(
              value: MemoryProgressRepository(),
            ),
            Provider<ReminderScheduler?>.value(value: null),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Undo last answer'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Undo last answer'), findsOneWidget);
      expect(find.text('Shake your phone during reviews'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Undo last answer'),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );
      expect(find.text('STUDY'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

class _GatedProgress extends MemoryProgressRepository {
  final Completer<void> started = Completer<void>();
  Future<void>? gate;
  bool armed = false;

  @override
  Future<void> saveSchedule(CardSchedule schedule) async {
    if (armed) {
      if (!started.isCompleted) started.complete();
      final pending = gate;
      if (pending != null) await pending;
    }
    await super.saveSchedule(schedule);
  }
}

class _StreamShakes extends ShakeEvents {
  _StreamShakes(this.events);

  final Stream<void> events;

  @override
  Stream<void> watch() => events;
}

class _BrokenShakes extends ShakeEvents {
  @override
  Stream<void> watch() => Stream<void>.error(StateError('no sensor'));
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fiveminutekanji/app.dart';
import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/handwriting.dart';
import 'package:fiveminutekanji/core/models/kanji_card.dart';
import 'package:fiveminutekanji/core/models/kanji_status.dart';
import 'package:fiveminutekanji/core/models/progress.dart';
import 'package:fiveminutekanji/core/models/review.dart';
import 'package:fiveminutekanji/core/models/stroke_data.dart';
import 'package:fiveminutekanji/core/models/study_phase.dart';
import 'package:fiveminutekanji/core/theme/app_theme.dart';
import 'package:fiveminutekanji/data/hardcoded_kanji_repository.dart';
import 'package:fiveminutekanji/data/shared_prefs_progress_repository.dart';
import 'package:fiveminutekanji/features/review/review_controller.dart';
import 'package:fiveminutekanji/features/review/review_screen.dart';
import 'package:fiveminutekanji/repositories/progress_repository.dart';
import 'package:fiveminutekanji/repositories/stroke_data_repository.dart';
import 'package:fiveminutekanji/services/initial_known_card_schedule.dart';
import 'package:fiveminutekanji/services/kanji_status_resolver.dart';
import 'package:fiveminutekanji/services/srs_engine.dart';
import 'package:fiveminutekanji/services/srs_scheduler.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 2, 8);
  const config = ReviewSessionConfig(
    duration: Duration(minutes: 5),
    maxCards: 4,
  );
  const resolver = KanjiStatusResolver();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  void usePhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<ReviewController> controllerFor({
    required MemoryProgressRepository progress,
    required List<String> ids,
    DateTime Function()? clock,
  }) async {
    final cards = ids.map(testCard).toList();
    await progress.seedIfNeeded(ids, now: now);
    return ReviewController(
      progressRepository: progress,
      srsEngine: const SrsEngine(),
      cards: cards,
      config: config,
      startTime: now,
      clock: clock ?? () => now,
      schedules: Map<String, CardSchedule>.from(progress.schedules),
    );
  }

  Future<void> pumpReview(
    WidgetTester tester, {
    required ProgressRepository progress,
    required List<KanjiCard> cards,
    StrokeDataRepository? strokes,
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ProgressRepository>.value(value: progress),
          Provider<SrsScheduler>.value(value: const SrsEngine()),
          if (strokes != null)
            Provider<StrokeDataRepository>.value(value: strokes),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: ReviewScreen(cards: cards, config: config, clock: () => now),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> completeLearnIntro(WidgetTester tester) async {
    expect(find.text('Practice Writing'), findsOneWidget);
    await tester.tap(find.text('Practice Writing'));
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
  }

  group('ReviewController learn flow', () {
    test(
      'learn intro does not persist SRS until practice is finished',
      () async {
        final progress = MemoryProgressRepository();
        final controller = await controllerFor(progress: progress, ids: ['a']);

        expect(controller.phase, StudyPhase.learn);
        controller.beginPractice();
        controller.updateDrawing(
          const HandwritingInput(
            strokes: [
              HandwritingStroke([StrokePoint(0.2, 0.2), StrokePoint(0.8, 0.8)]),
            ],
          ),
        );
        expect((await progress.getSchedule('a'))!.reviewCount, 0);
        expect(
          (await progress.getSchedule('a'))!.state,
          CardLearningState.newCard,
        );
        expect(progress.history, isEmpty);
      },
    );

    test('finishing learn persists a future learning interval', () async {
      final progress = MemoryProgressRepository();
      final controller = await controllerFor(
        progress: progress,
        ids: ['a', 'b'],
      );

      controller.beginPractice();
      await controller.completePractice();
      expect(controller.phase, StudyPhase.learn);
      expect(controller.current?.id, 'b');

      final schedule = await progress.getSchedule('a');
      expect(schedule!.state, CardLearningState.learning);
      expect(schedule.dueAt, now.add(SrsEngine.newLearnInterval));
      expect(schedule.reviewCount, 0);
      expect(progress.history, isEmpty);
      expect(resolver.resolve(schedule), KanjiProgressStatus.learning);
    });

    test(
      'first retrieval Good after learn uses existing review scheduling',
      () async {
        final progress = MemoryProgressRepository();
        final controller = await controllerFor(
          progress: progress,
          ids: ['a', 'b'],
        );

        controller.beginPractice();
        await controller.completePractice();
        expect(controller.current?.id, 'b');
        expect(controller.phase, StudyPhase.learn);

        controller.beginPractice();
        await controller.completePractice();
        expect(controller.current?.id, 'a');
        expect(controller.phase, StudyPhase.recall);
        controller.submit();
        await controller.rate(ReviewResult.good);

        final schedule = await progress.getSchedule('a');
        expect(schedule!.reviewCount, 1);
        expect(schedule.state, CardLearningState.review);
        expect(resolver.resolve(schedule), KanjiProgressStatus.learning);
        expect(controller.current?.id, 'b');
        expect(controller.phase, StudyPhase.recall);
      },
    );

    test('already reviewed cards skip learn', () async {
      final progress = MemoryProgressRepository();
      await progress.seedIfNeeded(['a'], now: now);
      await progress.saveSchedule(
        CardSchedule(
          cardId: 'a',
          state: CardLearningState.review,
          reviewCount: 1,
          correctCount: 1,
          incorrectCount: 0,
          dueAt: now,
          interval: SrsEngine.graduatingInterval,
          ease: 2.5,
          lastReviewedAt: now,
          consecutiveGoodCount: 1,
        ),
      );

      final controller = ReviewController(
        progressRepository: progress,
        srsEngine: const SrsEngine(),
        cards: [testCard('a')],
        config: config,
        startTime: now,
        clock: () => now,
        schedules: Map<String, CardSchedule>.from(progress.schedules),
      );

      expect(controller.phase, StudyPhase.recall);
      controller.submit();
      expect(controller.phase, StudyPhase.compare);
    });

    test('Again requeue of a retrieved learning card skips learn', () async {
      final progress = MemoryProgressRepository();
      final controller = await controllerFor(progress: progress, ids: ['a']);

      controller.beginPractice();
      await controller.completePractice();
      expect(controller.current?.id, 'a');
      expect(controller.phase, StudyPhase.recall);

      controller.submit();
      await controller.rate(ReviewResult.again);
      expect(controller.current?.id, 'a');
      expect(controller.phase, StudyPhase.recall);
    });

    test(
      'mark as known skips learn and leaves a long review interval',
      () async {
        final progress = MemoryProgressRepository();
        final controller = await controllerFor(
          progress: progress,
          ids: ['a', 'b'],
        );

        expect(controller.phase, StudyPhase.learn);
        await controller.markCurrentAsKnown();

        expect(controller.current?.id, 'b');
        expect(controller.phase, StudyPhase.learn);
        expect(progress.dailyNewKanji.count, 0);

        final schedule = await progress.getSchedule('a');
        expect(schedule!.state, CardLearningState.review);
        expect(schedule.interval, calculateInitialKnownCardSchedule('a'));
        expect(schedule.dueAt, now.add(calculateInitialKnownCardSchedule('a')));
        expect(resolver.resolve(schedule), KanjiProgressStatus.learning);
      },
    );
  });

  group('Learn flow widgets', () {
    testWidgets('new kanji opens learn then practice then another card', (
      tester,
    ) async {
      usePhoneViewport(tester);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      const kanji = HardcodedKanjiRepository();
      final progress = SharedPrefsProgressRepository(prefs);
      final cards = await kanji.getAll();
      await progress.seedIfNeeded(cards.map((card) => card.id).toList());
      final first = cards.firstWhere((card) => card.id == 'n5-029');
      final second = cards.firstWhere((card) => card.id == 'n5-030');

      await pumpReview(tester, progress: progress, cards: [first, second]);

      expect(find.text('4 remaining'), findsOneWidget);
      expect(find.text(first.character), findsOneWidget);
      expect(find.text('MEANING'), findsOneWidget);
      expect(find.text(first.keyword), findsOneWidget);
      expect(find.text('COMPONENTS'), findsOneWidget);
      expect(find.text(first.componentsLabel), findsOneWidget);
      expect(find.text(first.mnemonic), findsOneWidget);
      expect(find.text('READINGS'), findsOneWidget);
      expect(find.text('Practice Writing'), findsOneWidget);
      expect(find.text('Submit'), findsNothing);

      await tester.tap(find.text('Practice Writing'));
      await tester.pumpAndSettle();

      expect(find.text(first.character), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Submit'), findsNothing);
      expect((await progress.getSchedule(first.id))!.reviewCount, 0);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.text(second.character), findsOneWidget);
      expect(find.text('3 remaining'), findsOneWidget);
      expect(find.text('Practice Writing'), findsOneWidget);
      expect(find.text('Submit'), findsNothing);
      expect(find.text(first.keyword), findsNothing);

      final schedule = await progress.getSchedule(first.id);
      expect(schedule!.state, CardLearningState.learning);
      expect(schedule.reviewCount, 0);
      expect(resolver.resolve(schedule), KanjiProgressStatus.learning);

      final restarted = SharedPrefsProgressRepository(prefs);
      final restored = await restarted.getSchedule(first.id);
      expect(restored!.state, CardLearningState.learning);
      expect(resolver.resolve(restored), KanjiProgressStatus.learning);
    });

    testWidgets('closing during learn leaves the card new', (tester) async {
      usePhoneViewport(tester);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      const kanji = HardcodedKanjiRepository();
      final progress = SharedPrefsProgressRepository(prefs);
      final cards = await kanji.getAll();
      await progress.seedIfNeeded(cards.map((card) => card.id).toList());
      final first = cards.first;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ProgressRepository>.value(value: progress),
            Provider<SrsScheduler>.value(value: const SrsEngine()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              ReviewScreen(cards: [first], config: config),
                        ),
                      );
                    },
                    child: const Text('open'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Practice Writing'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.text('open'), findsOneWidget);
      expect((await progress.getSchedule(first.id))!.reviewCount, 0);
      expect(
        resolver.resolve(await progress.getSchedule(first.id)),
        KanjiProgressStatus.notEncountered,
      );
    });

    testWidgets('learning cards skip the learn intro', (tester) async {
      usePhoneViewport(tester);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      const kanji = HardcodedKanjiRepository();
      final progress = SharedPrefsProgressRepository(prefs);
      final cards = await kanji.getAll();
      await progress.seedIfNeeded(cards.map((card) => card.id).toList());
      final first = cards.first;
      await progress.saveSchedule(
        CardSchedule(
          cardId: first.id,
          state: CardLearningState.review,
          reviewCount: 1,
          correctCount: 1,
          incorrectCount: 0,
          dueAt: now,
          interval: SrsEngine.graduatingInterval,
          ease: 2.5,
          lastReviewedAt: now,
          consecutiveGoodCount: 1,
        ),
      );

      await pumpReview(tester, progress: progress, cards: [first]);

      expect(find.text('Practice Writing'), findsNothing);
      expect(find.text(first.keyword), findsOneWidget);
      expect(find.text(first.character), findsNothing);
      expect(find.text('Submit'), findsOneWidget);
    });

    testWidgets('kanji list turns learning after finishing learn', (
      tester,
    ) async {
      usePhoneViewport(tester);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      const kanji = HardcodedKanjiRepository();
      final progress = SharedPrefsProgressRepository(prefs);
      final cards = await kanji.getAll();
      await progress.seedIfNeeded(cards.map((card) => card.id).toList());
      final first = cards.first;

      await pumpReview(tester, progress: progress, cards: [first]);
      await completeLearnIntro(tester);

      await tester.pumpWidget(
        FiveMinuteKanjiApp(
          kanjiRepository: kanji,
          progressRepository: progress,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.byTooltip('Kanji List'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(first.character));
      await tester.pumpAndSettle();

      expect(find.text('Learning'), findsOneWidget);
      expect(find.text('Not encountered'), findsNothing);
    });

    testWidgets(
      'mark as known on learn skips practice and does not count as new',
      (tester) async {
        usePhoneViewport(tester);
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        const kanji = HardcodedKanjiRepository();
        final progress = SharedPrefsProgressRepository(prefs);
        final cards = await kanji.getAll();
        await progress.seedIfNeeded(cards.map((card) => card.id).toList());
        final first = cards.firstWhere((card) => card.id == 'n5-003');
        final second = cards.firstWhere((card) => card.id == 'n5-004');
        final now = DateTime(2026, 9, 2, 8);
        await progress.saveDailyNewKanji(
          DailyNewKanjiProgress(date: now, count: 1),
        );

        await pumpReview(tester, progress: progress, cards: [first, second]);

        expect(find.text('Already know this? Mark as known'), findsOneWidget);
        await tester.tap(find.text('Already know this? Mark as known'));
        await tester.pumpAndSettle();

        expect(find.text(second.character), findsOneWidget);
        expect(find.text('Practice Writing'), findsOneWidget);
        expect(find.text(first.character), findsNothing);

        final schedule = await progress.getSchedule(first.id);
        expect(schedule!.interval, calculateInitialKnownCardSchedule(first.id));
        expect(schedule.state, CardLearningState.review);
        expect(resolver.resolve(schedule), KanjiProgressStatus.learning);
        expect((await progress.getDailyNewKanji()).count, 1);
      },
    );

    testWidgets('practice writing is available while stroke order plays', (
      tester,
    ) async {
      usePhoneViewport(tester);
      final progress = MemoryProgressRepository();
      final card = testCard('ichi', character: '一', keyword: 'one');
      await progress.seedIfNeeded([card.id], now: now);
      final raw = File('test/fixtures/strokes/04e00.json').readAsStringSync();
      final strokes = MemoryStrokeDataRepository({
        '一': StrokeData.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        ),
      });

      await pumpReview(
        tester,
        progress: progress,
        cards: [card],
        strokes: strokes,
        settle: false,
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Stroke Order'), findsOneWidget);
      expect(find.text('Practice Writing'), findsOneWidget);
      expect(find.text('一'), findsNothing);

      await tester.tap(find.text('Practice Writing'));
      await tester.pumpAndSettle();
      expect(find.text('Done'), findsOneWidget);
    });
  });
}

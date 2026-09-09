import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fiveminutekanji/app.dart';
import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/handwriting.dart';
import 'package:fiveminutekanji/core/models/review.dart';
import 'package:fiveminutekanji/core/theme/app_theme.dart';
import 'package:fiveminutekanji/data/hardcoded_kanji_repository.dart';
import 'package:fiveminutekanji/data/shared_prefs_progress_repository.dart';
import 'package:fiveminutekanji/features/review/compare_body.dart';
import 'package:fiveminutekanji/features/review/review_controller.dart';
import 'package:fiveminutekanji/features/review/review_screen.dart';
import 'package:fiveminutekanji/features/review/widgets/handwriting_pad.dart';
import 'package:fiveminutekanji/features/stroke_order/kanji_stroke_animation.dart';
import 'package:fiveminutekanji/repositories/progress_repository.dart';
import 'package:fiveminutekanji/services/srs_engine.dart';
import 'package:fiveminutekanji/services/srs_scheduler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 2, 8);

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  void usePhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('first launch shows due reviews and start review', (
    tester,
  ) async {
    usePhoneViewport(tester);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const kanji = HardcodedKanjiRepository();
    final progress = SharedPrefsProgressRepository(prefs);
    final cards = await kanji.getAll();
    await progress.seedIfNeeded(cards.map((card) => card.id).toList());

    await tester.pumpWidget(
      FiveMinuteKanjiApp(kanjiRepository: kanji, progressRepository: progress),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.data == 'Good morning' ||
                widget.data == 'Good afternoon' ||
                widget.data == 'Good evening'),
      ),
      findsOneWidget,
    );
    expect(find.text('5'), findsOneWidget);
    expect(find.text('kanji remaining today'), findsOneWidget);
    expect(find.text('Start Review'), findsOneWidget);
    expect(find.textContaining('day streak'), findsOneWidget);
  });

  testWidgets('review flow shows meaning then another mixed card', (
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
    final second = cards[1];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ProgressRepository>.value(value: progress),
          Provider<SrsScheduler>.value(value: const SrsEngine()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: ReviewScreen(
            cards: [first, second],
            config: const ReviewSessionConfig(
              duration: Duration(minutes: 5),
              maxCards: 5,
            ),
            clock: () => now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(first.character), findsOneWidget);
    expect(find.text('Practice Writing'), findsOneWidget);
    expect(find.text(first.mnemonic), findsOneWidget);
    expect(find.text('Submit'), findsNothing);

    await tester.tap(find.text('Practice Writing'));
    await tester.pumpAndSettle();
    expect(find.text(first.character), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text(second.character), findsOneWidget);
    expect(find.text('Practice Writing'), findsOneWidget);
    expect(find.text('Submit'), findsNothing);
    expect(find.text(first.character), findsNothing);
  });

  testWidgets('review cards show meaning then handwriting compare', (
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
    await progress.saveSchedule(
      CardSchedule(
        cardId: first.id,
        state: CardLearningState.review,
        reviewCount: 1,
        correctCount: 1,
        incorrectCount: 0,
        dueAt: DateTime.now(),
        interval: SrsEngine.graduatingInterval,
        ease: 2.5,
        lastReviewedAt: DateTime.now(),
        consecutiveGoodCount: 1,
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ProgressRepository>.value(value: progress),
          Provider<SrsScheduler>.value(value: const SrsEngine()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: ReviewScreen(
            cards: [first],
            config: const ReviewSessionConfig(
              duration: Duration(minutes: 5),
              maxCards: 1,
            ),
            clock: () => now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(first.keyword), findsOneWidget);
    expect(find.text(first.character), findsNothing);
    expect(find.text('What does this mean?'), findsNothing);
    expect(find.text('Reveal Answer'), findsNothing);
    expect(find.text('HARD'), findsNothing);
    expect(find.text('Submit'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);

    const submitted = HandwritingInput(
      strokes: [
        HandwritingStroke([StrokePoint(0.2, 0.25), StrokePoint(0.8, 0.75)]),
      ],
    );
    Provider.of<ReviewController>(
      tester.element(find.text('Submit')),
      listen: false,
    ).updateDrawing(submitted);

    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(find.byType(CompareBody), findsOneWidget);
    expect(find.text('How did you do?'), findsOneWidget);
    expect(find.text('YOUR DRAWING'), findsOneWidget);
    expect(find.text('CORRECT'), findsOneWidget);
    expect(find.text(first.character), findsOneWidget);
    expect(find.text(first.keyword), findsOneWidget);
    expect(find.text(first.mnemonic), findsOneWidget);
    expect(find.text('Mnemonic'), findsNothing);
    expect(find.text('Stroke Order'), findsOneWidget);
    expect(find.byType(HandwritingPad), findsOneWidget);
    expect(find.byType(KanjiStrokeAnimation), findsOneWidget);
    expect(
      tester.widget<HandwritingPad>(find.byType(HandwritingPad)).readOnly,
      isTrue,
    );
    expect(
      tester.widget<HandwritingPad>(find.byType(HandwritingPad)).value.strokes,
      hasLength(submitted.strokes.length),
    );
    expect(
      tester.widget<HandwritingPad>(find.byType(HandwritingPad)).value.isEmpty,
      isFalse,
    );
    expect(find.text('Good'), findsOneWidget);
    expect(find.text('Again'), findsOneWidget);
    expect(find.text('HARD'), findsNothing);

    await tester.tap(find.text('Stroke Order'));
    await tester.pump();
    expect(find.byType(CompareBody), findsOneWidget);
    expect(find.byType(KanjiStrokeAnimation), findsOneWidget);
    expect(find.text('Again'), findsOneWidget);

    await tester.tap(find.text('Good'));
    await tester.pumpAndSettle();

    expect(find.text('Nice.'), findsOneWidget);
  });

  testWidgets('finishing a session persists progress and streak', (
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

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ProgressRepository>.value(value: progress),
          Provider<SrsScheduler>.value(value: const SrsEngine()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: ReviewScreen(
            cards: [first],
            config: const ReviewSessionConfig(
              duration: Duration(minutes: 5),
              maxCards: 1,
            ),
            clock: () => now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Practice Writing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Good'));
    await tester.pumpAndSettle();

    expect(find.text('Nice.'), findsOneWidget);
    expect(find.text('1 kanji reviewed'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    final schedule = await progress.getSchedule(first.id);
    expect(schedule?.state, CardLearningState.review);
    expect(schedule!.dueAt.isAfter(now), isTrue);
    expect((await progress.getStreak()).current, 1);

    await tester.tap(find.text('Done'));
    await tester.pumpWidget(
      FiveMinuteKanjiApp(kanjiRepository: kanji, progressRepository: progress),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('kanji remaining today'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    expect(find.text('day streak'), findsOneWidget);
  });

  testWidgets('caught-up home shows an empty state instead of a session', (
    tester,
  ) async {
    usePhoneViewport(tester);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const kanji = HardcodedKanjiRepository();
    final progress = SharedPrefsProgressRepository(prefs);
    final cards = await kanji.getAll();
    final later = DateTime.now().add(const Duration(days: 2));
    for (final card in cards) {
      await progress.saveSchedule(
        CardSchedule(
          cardId: card.id,
          state: CardLearningState.review,
          reviewCount: 1,
          correctCount: 1,
          incorrectCount: 0,
          dueAt: later,
          interval: const Duration(days: 2),
          ease: 2.5,
        ),
      );
    }

    await tester.pumpWidget(
      FiveMinuteKanjiApp(kanjiRepository: kanji, progressRepository: progress),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('0'), findsWidgets);
    expect(find.text('kanji remaining today'), findsOneWidget);
    expect(find.text("You're all caught up."), findsOneWidget);
    expect(find.text('Start Review'), findsNothing);
    expect(find.text('Practice Anyway'), findsOneWidget);
    expect(find.textContaining('Next review:'), findsOneWidget);
  });

  testWidgets('progress survives a new repository instance after learn', (
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

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ProgressRepository>.value(value: progress),
          Provider<SrsScheduler>.value(value: const SrsEngine()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: ReviewScreen(
            cards: [first],
            config: const ReviewSessionConfig(
              duration: Duration(minutes: 5),
              maxCards: 1,
            ),
            clock: () => now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Practice Writing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    final restarted = SharedPrefsProgressRepository(prefs);
    final schedule = await restarted.getSchedule(first.id);
    expect(schedule?.state, CardLearningState.learning);
    expect(schedule?.reviewCount, 0);
    expect(schedule!.dueAt, now.add(SrsEngine.newLearnInterval));
    expect(schedule.isDueAt(now), isFalse);
    expect((await restarted.getDailyNewKanji()).count, 1);

    await tester.pumpWidget(
      FiveMinuteKanjiApp(kanjiRepository: kanji, progressRepository: restarted),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('1 review'), findsOneWidget);
    expect(find.text('kanji remaining today'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('day streak'), findsOneWidget);
  });

  testWidgets('settings screen shows new-kanji limit and a workload estimate', (
    tester,
  ) async {
    usePhoneViewport(tester);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const kanji = HardcodedKanjiRepository();
    final progress = SharedPrefsProgressRepository(prefs);
    final cards = await kanji.getAll();
    await progress.seedIfNeeded(cards.map((card) => card.id).toList());

    await tester.pumpWidget(
      FiveMinuteKanjiApp(kanjiRepository: kanji, progressRepository: progress),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('New kanji per day'), findsOneWidget);
    expect(find.text('5'), findsWidgets);
    expect(find.textContaining('Estimated daily study time:'), findsOneWidget);
    expect(find.text('Start of day'), findsOneWidget);
    expect(find.text('4:00 AM'), findsOneWidget);

    await tester.ensureVisible(find.text('4:00 AM'));
    await tester.tap(find.text('4:00 AM'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('kanji remaining today'), findsOneWidget);
  });
}

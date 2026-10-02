import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fiveminutekanji/app.dart';
import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/kanji_card.dart';
import 'package:fiveminutekanji/core/models/kanji_status.dart';
import 'package:fiveminutekanji/core/models/placement.dart';
import 'package:fiveminutekanji/data/hardcoded_kanji_repository.dart';
import 'package:fiveminutekanji/data/shared_prefs_progress_repository.dart';
import 'package:fiveminutekanji/features/placement/placement_controller.dart';
import 'package:fiveminutekanji/repositories/progress_repository.dart';
import 'package:fiveminutekanji/services/initial_known_card_schedule.dart';
import 'package:fiveminutekanji/services/kanji_status_resolver.dart';
import 'package:fiveminutekanji/services/mark_as_known.dart';
import 'package:fiveminutekanji/services/placement_service.dart';
import 'package:fiveminutekanji/services/placement_test_engine.dart';
import 'package:fiveminutekanji/services/srs_engine.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  Future<SharedPrefsProgressRepository> freshProgress() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final progress = SharedPrefsProgressRepository(prefs);
    const kanji = HardcodedKanjiRepository();
    final cards = await kanji.getAll();
    await progress.seedIfNeeded(cards.map((card) => card.id).toList());
    // Start at the placement step: the screens around it belong to the
    // onboarding tests.
    await startPlacementStep(progress);
    return progress;
  }

  Future<void> pumpApp(
    WidgetTester tester,
    ProgressRepository progress, {
    HardcodedKanjiRepository kanji = const HardcodedKanjiRepository(),
  }) async {
    await tester.pumpWidget(
      FiveMinuteKanjiApp(kanjiRepository: kanji, progressRepository: progress),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  PlacementController controllerOf(WidgetTester tester) {
    return Provider.of<PlacementController>(
      tester.element(find.text('I know it')),
      listen: false,
    );
  }

  /// Answers every question until the results screen, deciding each answer from
  /// the kanji on screen.
  Future<List<KanjiCard>> answerAll(
    WidgetTester tester, {
    required bool Function(KanjiCard card) knows,
  }) async {
    final asked = <KanjiCard>[];
    while (find.text('I know it').evaluate().isNotEmpty) {
      final card = controllerOf(tester).question!;
      expect(find.text(card.character), findsOneWidget);
      asked.add(card);
      await tester.tap(find.text(knows(card) ? 'I know it' : "I don't know it"));
      await tester.pumpAndSettle();
    }
    return asked;
  }

  testWidgets('the placement step opens the test instead of Home', (
    tester,
  ) async {
    usePhoneViewport(tester);
    await pumpApp(tester, await freshProgress());

    expect(find.text("Let's find your starting point"), findsOneWidget);
    expect(find.text('It only takes a couple minutes.'), findsOneWidget);
    expect(find.text('Start Placement Test'), findsOneWidget);
    expect(find.text('Start Review'), findsNothing);
    expect(find.text('kanji remaining today'), findsNothing);
  });

  testWidgets('a question shows the kanji alone, with quiet progress', (
    tester,
  ) async {
    usePhoneViewport(tester);
    await pumpApp(tester, await freshProgress());
    await tester.tap(find.text('Start Placement Test'));
    await tester.pumpAndSettle();

    final card = controllerOf(tester).question!;
    expect(find.text(card.character), findsOneWidget);
    expect(find.text('I know it'), findsOneWidget);
    expect(find.text("I don't know it"), findsOneWidget);
    expect(find.text('1 / ~36'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // Nothing that would give the answer away or grade it.
    expect(find.text(card.keyword), findsNothing);
    expect(find.text(card.meaning), findsNothing);
    expect(find.text(card.mnemonic), findsNothing);
    expect(find.textContaining('JLPT'), findsNothing);

    await tester.tap(find.text("I don't know it"));
    await tester.pumpAndSettle();

    // No wrong-answer screen: straight to the next kanji.
    expect(find.text('2 / ~36'), findsOneWidget);
    expect(controllerOf(tester).question?.id, isNot(card.id));
  });

  testWidgets('the test marks what the user knows and hands over the flow', (
    tester,
  ) async {
    usePhoneViewport(tester);
    final progress = await freshProgress();
    final now = DateTime.now();
    await pumpApp(tester, progress);
    await tester.tap(find.text('Start Placement Test'));
    await tester.pumpAndSettle();

    // A learner who knows N5 but not N4.
    final asked = await answerAll(
      tester,
      knows: (card) => card.jlptLevel == JlptLevel.n5,
    );

    expect(asked.length, inInclusiveRange(12, 36));
    expect(find.text("You're all set!"), findsOneWidget);
    expect(find.text('kanji already known'), findsOneWidget);
    expect(find.textContaining('Starting around JLPT'), findsOneWidget);
    expect(
      find.text("We've added the kanji you already know to your library."),
      findsOneWidget,
    );
    expect(find.text('Start Learning'), findsOneWidget);

    final schedules = await progress.getSchedules();
    final known = schedules.values.where(
      (schedule) => schedule.state != CardLearningState.newCard,
    );
    expect(known.length, inInclusiveRange(80, 130));

    // Known kanji look exactly like hand-marked ones: same interval, same
    // status in the list, and not waiting in today's queue.
    for (final schedule in known) {
      expect(schedule.state, CardLearningState.review);
      expect(schedule.interval, calculateInitialKnownCardSchedule(schedule.cardId));
      expect(schedule.isDueAt(now), isFalse);
      expect(resolver.resolve(schedule), KanjiProgressStatus.learning);
    }

    // The test does not spend the daily new-kanji allowance.
    expect((await progress.getDailyNewKanji()).count, 0);

    await tester.tap(find.text('Start Learning'));
    await tester.pumpAndSettle();

    expect(find.text('How much time fits into your day?'), findsOneWidget);
    expect(find.text("Let's find your starting point"), findsNothing);
  });

  testWidgets('the test does not come back on the next launch', (tester) async {
    usePhoneViewport(tester);
    final progress = await freshProgress();
    await pumpApp(tester, progress);
    await tester.tap(find.text('Start Placement Test'));
    await tester.pumpAndSettle();
    await answerAll(tester, knows: (card) => false);
    await tester.tap(find.text('Start Learning'));
    await tester.pumpAndSettle();

    // Tear the tree down so the next launch starts from storage.
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpApp(tester, SharedPrefsProgressRepository(await SharedPreferences.getInstance()));

    expect(find.text("Let's find your starting point"), findsNothing);
    expect(find.text('How much time fits into your day?'), findsOneWidget);
  });

  testWidgets('closing the app mid-test resumes on the same kanji', (
    tester,
  ) async {
    usePhoneViewport(tester);
    final progress = await freshProgress();
    await pumpApp(tester, progress);
    await tester.tap(find.text('Start Placement Test'));
    await tester.pumpAndSettle();

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('I know it'));
      await tester.pumpAndSettle();
    }
    final pending = controllerOf(tester).question!;

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpApp(tester, SharedPrefsProgressRepository(await SharedPreferences.getInstance()));

    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Start Placement Test'), findsNothing);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(controllerOf(tester).question?.id, pending.id);
    expect(find.text(pending.character), findsOneWidget);
    expect(find.text('5 / ~36'), findsOneWidget);
  });

  testWidgets('a learner who knows every kanji is placed at the end', (
    tester,
  ) async {
    usePhoneViewport(tester);
    final progress = await freshProgress();
    await pumpApp(tester, progress);
    await tester.tap(find.text('Start Placement Test'));
    await tester.pumpAndSettle();

    await answerAll(tester, knows: (card) => true);

    const kanji = HardcodedKanjiRepository();
    final total = (await kanji.getAll()).length;
    expect(find.text('$total'), findsOneWidget);
    expect(find.text('kanji already known'), findsOneWidget);
    expect(find.text("That's every kanji in the app."), findsOneWidget);

    await tester.tap(find.text('Start Learning'));
    await tester.pumpAndSettle();
    expect(find.text('How much time fits into your day?'), findsOneWidget);
  });

  testWidgets('Settings can run the placement test again', (tester) async {
    usePhoneViewport(tester);
    final progress = await freshProgress();
    await completeOnboarding(progress);
    await pumpApp(tester, progress);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Retake placement test'));
    await tester.tap(find.text('Retake placement test'));
    await tester.pumpAndSettle();

    expect(find.text("Let's find your starting point"), findsOneWidget);
    expect(find.text('Start Placement Test'), findsOneWidget);

    await tester.tap(find.text('Start Placement Test'));
    await tester.pumpAndSettle();
    expect(find.text('I know it'), findsOneWidget);

    // A retake is escapable, and abandoning it leaves the test completed.
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Retake placement test'), findsOneWidget);
    expect((await progress.getPlacement()).completed, isTrue);
  });

  testWidgets('an empty kanji set skips the test without spending the flag', (
    tester,
  ) async {
    usePhoneViewport(tester);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final progress = SharedPrefsProgressRepository(prefs);
    await startPlacementStep(progress);

    await tester.pumpWidget(
      FiveMinuteKanjiApp(
        kanjiRepository: FakeKanjiRepository(const []),
        progressRepository: progress,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text("Let's find your starting point"), findsNothing);
    expect(find.text('How much time fits into your day?'), findsOneWidget);
    expect((await progress.getPlacement()).completed, isFalse);
  });

  group('PlacementService', () {
    PlacementService serviceFor(
      MemoryProgressRepository progress,
      List<KanjiCard> cards, {
      DateTime? now,
    }) {
      final clock = now == null ? null : () => now;
      return PlacementService(
        kanjiRepository: FakeKanjiRepository(cards),
        progressRepository: progress,
        markAsKnown: MarkAsKnownService(
          progressRepository: progress,
          srsEngine: const SrsEngine(),
          clock: clock,
        ),
        clock: clock,
      );
    }

    test('kanji already marked known by hand are not asked about', () async {
      final cards = [
        for (var i = 0; i < 12; i++)
          testCard('k${i.toString().padLeft(2, '0')}', jlptLevel: JlptLevel.n5),
      ];
      final progress = MemoryProgressRepository();
      await progress.seedIfNeeded(cards.map((card) => card.id).toList());
      final markAsKnown = MarkAsKnownService(
        progressRepository: progress,
        srsEngine: const SrsEngine(),
      );
      await markAsKnown.markKanjiAsKnownAll(const ['k00', 'k01']);

      final service = serviceFor(progress, cards);
      final pool = await service.candidates();

      expect(pool.map((card) => card.id), isNot(contains('k00')));
      expect(pool.map((card) => card.id), isNot(contains('k01')));
      expect(pool, hasLength(cards.length - 2));
    });

    test('completing the test preserves kanji that already had progress', () async {
      final cards = [
        for (var i = 0; i < 12; i++)
          testCard('k${i.toString().padLeft(2, '0')}', jlptLevel: JlptLevel.n5),
      ];
      final progress = MemoryProgressRepository();
      await progress.seedIfNeeded(cards.map((card) => card.id).toList());
      final learning = const SrsEngine().introduce(
        current: (await progress.getSchedule('k00'))!,
        now: DateTime(2026, 9, 2, 8),
      );
      await progress.saveSchedule(learning);

      final service = serviceFor(progress, cards);
      await service.complete(
        PlacementOutcome(
          knownCardIds: cards.map((card) => card.id).toList(),
          answeredCount: 12,
        ),
      );

      expect((await progress.getSchedule('k00'))!.dueAt, learning.dueAt);
      expect(
        (await progress.getSchedule('k00'))!.state,
        CardLearningState.learning,
      );
      expect(
        (await progress.getSchedule('k01'))!.state,
        CardLearningState.review,
      );
    });

    test('a pool with nothing left to place completes itself', () async {
      final cards = [testCard('k00'), testCard('k01')];
      final progress = MemoryProgressRepository();
      await progress.seedIfNeeded(cards.map((card) => card.id).toList());
      await MarkAsKnownService(
        progressRepository: progress,
        srsEngine: const SrsEngine(),
      ).markKanjiAsKnownAll(const ['k00', 'k01']);

      final service = serviceFor(progress, cards);

      expect(await service.isRequired(), isFalse);
      expect((await progress.getPlacement()).completed, isTrue);
    });

    test('a retake keeps the test off the next launch', () async {
      final cards = [for (var i = 0; i < 12; i++) testCard('k$i')];
      final progress = MemoryProgressRepository();
      await progress.seedIfNeeded(cards.map((card) => card.id).toList());
      final service = serviceFor(progress, cards);

      await service.complete(
        const PlacementOutcome(knownCardIds: ['k0'], answeredCount: 12),
      );
      await service.restart();
      await service.saveAnswers(const [
        PlacementAnswer(cardId: 'k1', known: true),
      ]);

      // Abandoned halfway through a retake: still completed, still resumable.
      expect(await service.isRequired(), isFalse);
      expect((await service.progress()).answers, hasLength(1));
    });

    test('the real kanji set is placed in a couple of minutes of taps', () async {
      const kanji = HardcodedKanjiRepository();
      const engine = PlacementTestEngine();
      final cards = await kanji.getAll();
      final run = engine.replay(cards, const []);
      while (!run.isFinished) {
        final question = run.currentQuestion!;
        run.record(
          PlacementAnswer(
            cardId: question.id,
            known: question.jlptLevel == JlptLevel.n5,
          ),
        );
      }

      expect(run.answeredCount, inInclusiveRange(12, 36));
      expect(run.outcome().knownCardIds.length, greaterThan(50));
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/kanji_card.dart';
import 'package:fiveminutekanji/core/models/kanji_status.dart';
import 'package:fiveminutekanji/core/models/placement.dart';
import 'package:fiveminutekanji/core/models/review.dart';
import 'package:fiveminutekanji/core/theme/app_theme.dart';
import 'package:fiveminutekanji/data/shared_prefs_progress_repository.dart';
import 'package:fiveminutekanji/features/kanji_list/kanji_detail_screen.dart';
import 'package:fiveminutekanji/features/review/review_controller.dart';
import 'package:fiveminutekanji/features/review/review_screen.dart';
import 'package:fiveminutekanji/repositories/progress_repository.dart';
import 'package:fiveminutekanji/repositories/stroke_data_repository.dart';
import 'package:fiveminutekanji/services/mark_as_known.dart';
import 'package:fiveminutekanji/services/placement_service.dart';
import 'package:fiveminutekanji/services/srs_engine.dart';
import 'package:fiveminutekanji/services/srs_scheduler.dart';
import 'package:fiveminutekanji/widgets/first_review_indicator.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 2, 8);
  const engine = SrsEngine();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  CardSchedule known(String id) {
    return engine.markAsKnown(current: CardSchedule.fresh(id, now), now: now);
  }

  CardSchedule studied(String id) {
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

  CardSchedule reviewed(String id) {
    return engine.schedule(
      current: known(id),
      result: ReviewResult.good,
      now: now,
    );
  }

  MarkAsKnownService marker(ProgressRepository progress) {
    return MarkAsKnownService(
      progressRepository: progress,
      srsEngine: engine,
      clock: () => now,
    );
  }

  test('manual and placement known kanji await a first review', () async {
    final progress = MemoryProgressRepository();
    final cards = [
      testCard('by-hand'),
      testCard('from-test'),
      testCard('confirm'),
      testCard('untouched'),
    ];
    await progress.seedIfNeeded(
      cards.map((card) => card.id).toList(),
      now: now,
    );

    await marker(progress).markKanjiAsKnown('by-hand', now: now);
    await PlacementService(
      kanjiRepository: FakeKanjiRepository(cards),
      progressRepository: progress,
      markAsKnown: marker(progress),
      clock: () => now,
    ).complete(
      const PlacementOutcome(
        knownCardIds: ['from-test'],
        confirmCardIds: ['confirm'],
        answeredCount: 1,
        estimatedDifficulty: 12,
      ),
    );

    expect(
      (await progress.getSchedule('by-hand'))!.awaitsFirstKnownReview,
      isTrue,
    );
    expect(
      (await progress.getSchedule('from-test'))!.awaitsFirstKnownReview,
      isTrue,
    );
    expect(
      (await progress.getSchedule('confirm'))!.awaitsFirstKnownReview,
      isFalse,
    );
    expect(
      (await progress.getSchedule('untouched'))!.awaitsFirstKnownReview,
      isFalse,
    );
    expect(studied('learned').awaitsFirstKnownReview, isFalse);
    expect(CardSchedule.fresh('fresh', now).awaitsFirstKnownReview, isFalse);
  });

  test(
    'the first rating clears the note for good, and a later one stays clear',
    () async {
      final progress = MemoryProgressRepository();
      await progress.seedIfNeeded(const ['a'], now: now);
      await marker(progress).markKanjiAsKnown('a', now: now);

      final controller = ReviewController(
        progressRepository: progress,
        srsEngine: engine,
        cards: [testCard('a', keyword: 'one', character: '一')],
        config: const ReviewSessionConfig(
          duration: Duration(minutes: 5),
          maxCards: 1,
        ),
        startTime: now,
        clock: () => now,
      );
      await controller.hydrate();

      expect(controller.awaitsFirstKnownReview, isTrue);
      expect((await progress.getSchedule('a'))!.reviewCount, 0);

      controller.submit();
      await controller.rate(ReviewResult.again);
      expect(controller.awaitsFirstKnownReview, isFalse);
      expect(
        (await progress.getSchedule('a'))!.awaitsFirstKnownReview,
        isFalse,
      );

      expect(await controller.undoLastAnswer(), isTrue);
      expect(controller.awaitsFirstKnownReview, isTrue);
      expect((await progress.getSchedule('a'))!.awaitsFirstKnownReview, isTrue);

      await controller.rate(ReviewResult.good);
      final saved = (await progress.getSchedule('a'))!;
      expect(saved.awaitsFirstKnownReview, isFalse);
      expect(saved.reviewCount, 1);

      final later = engine.schedule(
        current: saved,
        result: ReviewResult.good,
        now: now.add(const Duration(days: 2)),
      );
      expect(later.awaitsFirstKnownReview, isFalse);

      final missed = engine.schedule(
        current: known('b'),
        result: ReviewResult.hard,
        now: now,
      );
      expect(missed.awaitsFirstKnownReview, isFalse);
      expect(reviewed('c').awaitsFirstKnownReview, isFalse);
    },
  );

  test(
    'a finished first review stays finished after the app restarts',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final first = SharedPrefsProgressRepository(prefs);
      await first.seedIfNeeded(const ['a'], now: now);
      await marker(first).markKanjiAsKnown('a', now: now);
      expect((await first.getSchedule('a'))!.awaitsFirstKnownReview, isTrue);

      final rated = engine.schedule(
        current: (await first.getSchedule('a'))!,
        result: ReviewResult.again,
        now: now,
      );
      await first.saveSchedule(rated);

      final restarted = SharedPrefsProgressRepository(prefs);
      final loaded = await restarted.getSchedule('a');
      expect(loaded!.reviewCount, 1);
      expect(loaded.awaitsFirstKnownReview, isFalse);
    },
  );

  testWidgets('detail shows the note only before the first review', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const card = KanjiCard(
      id: 'n5-001',
      character: '一',
      meaning: 'one',
      keyword: 'one',
      mnemonic: 'One horizontal stroke.',
      components: [],
      jlptLevel: JlptLevel.n5,
    );

    Future<void> pumpDetail({
      required KanjiProgressStatus status,
      CardSchedule? schedule,
      ProgressRepository? progress,
    }) async {
      final repo = progress ?? MemoryProgressRepository();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ProgressRepository>.value(value: repo),
            Provider<StrokeDataRepository>.value(
              value: MemoryStrokeDataRepository(const {}),
            ),
            Provider<MarkAsKnownService>(create: (_) => marker(repo)),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: KanjiDetailScreen(
              card: card,
              status: status,
              schedule: schedule,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpDetail(status: KanjiProgressStatus.notEncountered);
    expect(find.byIcon(Icons.info_outline), findsNothing);
    expect(find.text(FirstReviewIndicator.explanation), findsNothing);

    await pumpDetail(
      status: KanjiProgressStatus.learning,
      schedule: studied(card.id),
    );
    expect(find.byIcon(Icons.info_outline), findsNothing);

    await pumpDetail(
      status: KanjiProgressStatus.learning,
      schedule: reviewed(card.id),
    );
    expect(find.byIcon(Icons.info_outline), findsNothing);

    final progress = MemoryProgressRepository();
    await pumpDetail(
      status: KanjiProgressStatus.notEncountered,
      progress: progress,
    );
    await tester.tap(find.text('Mark as Known'));
    await tester.pump();

    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    expect(
      (await progress.getSchedule(card.id))!.awaitsFirstKnownReview,
      isTrue,
    );

    await tester.tap(find.byTooltip(FirstReviewIndicator.title));
    await tester.pump();

    expect(find.text(FirstReviewIndicator.title), findsOneWidget);
    expect(find.text(FirstReviewIndicator.explanation), findsOneWidget);
    final explanation = tester.getRect(
      find.text(FirstReviewIndicator.explanation),
    );
    expect(explanation.left, greaterThanOrEqualTo(0));
    expect(explanation.right, lessThanOrEqualTo(390));
    expect(explanation.top, greaterThanOrEqualTo(0));
    expect(explanation.bottom, lessThanOrEqualTo(844));

    await tester.tapAt(const Offset(24, 700));
    await tester.pump();
    expect(find.text(FirstReviewIndicator.explanation), findsNothing);
  });

  testWidgets('review shows the note until the first answer is saved', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final progress = SharedPrefsProgressRepository(prefs);
    final knownCard = testCard('a', keyword: 'one', character: '一');
    final learnedCard = testCard('b', keyword: 'two', character: '二');
    await progress.seedIfNeeded([knownCard.id, learnedCard.id], now: now);
    await marker(progress).markKanjiAsKnown(knownCard.id, now: now);
    await progress.saveSchedule(studied(learnedCard.id));

    Future<void> openReview(List<KanjiCard> cards) async {
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
              config: const ReviewSessionConfig(
                duration: Duration(minutes: 5),
                maxCards: 2,
              ),
              clock: () => now,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await openReview([learnedCard]);
    expect(find.text('two'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsNothing);

    // A new session needs a new provider. Updating the same ReviewScreen
    // keeps the controller created for the previous cards.
    await tester.pumpWidget(const SizedBox.shrink());
    await openReview([knownCard]);
    expect(find.text('one'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    expect((await progress.getSchedule(knownCard.id))!.reviewCount, 0);

    await tester.tap(find.byTooltip(FirstReviewIndicator.title));
    await tester.pump();
    expect(find.text(FirstReviewIndicator.explanation), findsOneWidget);
    await tester.tapAt(const Offset(24, 700));
    await tester.pump();

    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(find.text('CORRECT'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);

    await tester.tap(find.text('Again'));
    await tester.pumpAndSettle();
    expect(find.text('one'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsNothing);
    expect(
      (await progress.getSchedule(knownCard.id))!.awaitsFirstKnownReview,
      isFalse,
    );

    final controller = Provider.of<ReviewController>(
      tester.element(find.text('Submit')),
      listen: false,
    );
    expect(await controller.undoLastAnswer(), isTrue);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.info_outline), findsOneWidget);

    await tester.tap(find.text('Good'));
    await tester.pumpAndSettle();

    final restarted = SharedPrefsProgressRepository(prefs);
    final loaded = await restarted.getSchedule(knownCard.id);
    expect(loaded!.awaitsFirstKnownReview, isFalse);
    expect(loaded.reviewCount, greaterThan(0));

    await tester.pumpWidget(const SizedBox.shrink());
    await openReview([knownCard]);
    expect(find.text('one'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsNothing);
  });
}

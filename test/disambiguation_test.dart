import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/handwriting.dart';
import 'package:fiveminutekanji/core/models/kanji_card.dart';
import 'package:fiveminutekanji/core/models/kanji_status.dart';
import 'package:fiveminutekanji/core/models/review.dart';
import 'package:fiveminutekanji/core/theme/app_theme.dart';
import 'package:fiveminutekanji/data/hardcoded_kanji_repository.dart';
import 'package:fiveminutekanji/features/kanji_list/kanji_detail_screen.dart';
import 'package:fiveminutekanji/features/kanji_list/kanji_list_screen.dart';
import 'package:fiveminutekanji/features/learn/learn_kanji_body.dart';
import 'package:fiveminutekanji/features/review/compare_body.dart';
import 'package:fiveminutekanji/features/review/review_screen.dart';
import 'package:fiveminutekanji/features/review/widgets/handwriting_pad.dart';
import 'package:fiveminutekanji/repositories/kanji_repository.dart';
import 'package:fiveminutekanji/repositories/progress_repository.dart';
import 'package:fiveminutekanji/services/mark_as_known.dart';
import 'package:fiveminutekanji/services/srs_engine.dart';
import 'package:fiveminutekanji/services/srs_scheduler.dart';
import 'package:fiveminutekanji/widgets/disambiguation_hint.dart';
import 'package:fiveminutekanji/widgets/writing_sheet_layout.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 2, 8);
  const config = ReviewSessionConfig(
    duration: Duration(minutes: 5),
    maxCards: 5,
  );

  const world = KanjiCard(
    id: 'n4-002',
    character: '世',
    meaning: 'world',
    keyword: 'world',
    disambiguation: 'generation / era',
    mnemonic: 'Three tens join into thirty years.',
  );
  const realm = KanjiCard(
    id: 'n4-105',
    character: '界',
    meaning: 'world',
    keyword: 'world',
    disambiguation: 'boundary / realm',
    mnemonic: 'A rice field jammed at the edge of the world.',
  );
  const one = KanjiCard(
    id: 'n5-001',
    character: '一',
    meaning: 'one',
    keyword: 'one',
    mnemonic: 'A single flat stroke.',
  );

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  void usePhoneViewport(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  CardSchedule reviewing(String id) {
    return CardSchedule(
      cardId: id,
      state: CardLearningState.review,
      reviewCount: 2,
      correctCount: 2,
      incorrectCount: 0,
      dueAt: now,
      interval: const Duration(days: 4),
      ease: 2.5,
      lastReviewedAt: now.subtract(const Duration(days: 4)),
      consecutiveGoodCount: 2,
    );
  }

  Future<void> pumpReview(
    WidgetTester tester, {
    required KanjiCard card,
    ThemeData? theme,
  }) async {
    final progress = MemoryProgressRepository(
      schedules: {card.id: reviewing(card.id)},
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ProgressRepository>.value(value: progress),
          Provider<SrsScheduler>.value(value: const SrsEngine()),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.light,
          home: ReviewScreen(cards: [card], config: config, clock: () => now),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpList(
    WidgetTester tester, {
    required List<KanjiCard> cards,
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<KanjiRepository>.value(value: FakeKanjiRepository(cards)),
          Provider<ProgressRepository>.value(value: MemoryProgressRepository()),
          Provider<MarkAsKnownService>(
            create: (context) => MarkAsKnownService(
              progressRepository: context.read<ProgressRepository>(),
              srsEngine: const SrsEngine(),
            ),
          ),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.light,
          home: const KanjiListScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> pumpDetail(
    WidgetTester tester, {
    required KanjiCard card,
    ThemeData? theme,
  }) async {
    final progress = MemoryProgressRepository();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ProgressRepository>.value(value: progress),
          Provider<MarkAsKnownService>(
            create: (_) => MarkAsKnownService(
              progressRepository: progress,
              srsEngine: const SrsEngine(),
            ),
          ),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.light,
          home: KanjiDetailScreen(
            card: card,
            status: KanjiProgressStatus.notEncountered,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  test('blank and missing hints collapse to null', () {
    expect(one.disambiguationHint, isNull);
    expect(testCard('blank', disambiguation: '   ').disambiguationHint, isNull);
    expect(world.disambiguationHint, 'generation / era');
  });

  test('catalog world kanji keep their distinguishing glosses', () async {
    const kanji = HardcodedKanjiRepository();
    final sei = await kanji.getById('n4-002');
    final kai = await kanji.getById('n4-105');

    expect(sei?.character, '世');
    expect(sei?.keyword, 'world');
    expect(sei?.disambiguationHint, 'generation / era');
    expect(kai?.character, '界');
    expect(kai?.keyword, 'world');
    expect(kai?.disambiguationHint, 'boundary / realm');
  });

  testWidgets('review prompt shows the hint under the keyword', (tester) async {
    usePhoneViewport(tester);
    await pumpReview(tester, card: world);

    expect(find.text('world'), findsOneWidget);
    expect(find.text('generation / era'), findsOneWidget);
    expect(find.text('世'), findsNothing);
    expect(find.text('Submit'), findsOneWidget);

    final keyword = tester.widget<Text>(find.text('world'));
    final hint = tester.widget<Text>(find.text('generation / era'));
    expect(keyword.style?.fontSize, 42);
    expect(hint.style?.fontSize, 15);
    expect(hint.style?.color, AppTheme.light.mutedText);
    expect(
      tester.getTopLeft(find.text('generation / era')).dy,
      greaterThan(tester.getBottomLeft(find.text('world')).dy),
    );
    expect(
      tester.getTopLeft(find.byType(HandwritingPad)).dy,
      greaterThan(tester.getBottomLeft(find.text('generation / era')).dy),
    );
  });

  testWidgets('review prompt without a hint keeps the original keyword block', (
    tester,
  ) async {
    usePhoneViewport(tester);
    await pumpReview(tester, card: one);

    expect(find.text('one'), findsOneWidget);
    expect(find.byType(DisambiguationHint), findsNothing);
    expect(find.text('Submit'), findsOneWidget);

    final sheetTop = tester.getTopLeft(find.byType(WritingSheetLayout)).dy;
    final keywordTop = tester.getTopLeft(find.text('one')).dy;
    final padTop = tester.getTopLeft(find.byType(HandwritingPad)).dy;
    expect(keywordTop - sheetTop, greaterThan(8));
    expect(keywordTop - sheetTop, lessThan(24));
    expect(padTop - tester.getBottomLeft(find.text('one')).dy, greaterThan(8));
    expect(tester.takeException(), isNull);
  });

  testWidgets('review hint stays visible in light and dark themes', (
    tester,
  ) async {
    usePhoneViewport(tester);
    await pumpReview(tester, card: realm, theme: AppTheme.dark);

    expect(find.text('world'), findsOneWidget);
    expect(find.text('boundary / realm'), findsOneWidget);
    final hint = tester.widget<Text>(find.text('boundary / realm'));
    expect(hint.style?.color, AppTheme.dark.mutedText);
  });

  testWidgets('long review hints wrap on a narrow phone', (tester) async {
    usePhoneViewport(tester, size: const Size(320, 568));
    const long = KanjiCard(
      id: 'long',
      character: '長',
      meaning: 'long',
      keyword: 'long',
      disambiguation:
          'an unusually lengthy gloss used to confirm wrapping under the keyword',
      mnemonic: 'A long stretch of hair.',
    );
    await pumpReview(tester, card: long);

    expect(find.text(long.disambiguation!), findsOneWidget);
    expect(
      tester.getSize(find.text(long.disambiguation!)).height,
      greaterThan(20),
    );
    expect(
      tester.getSize(find.text(long.disambiguation!)).width,
      lessThan(320),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('learn and compare screens show the hint beside the keyword', (
    tester,
  ) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: LearnKanjiBody(card: world)),
      ),
    );
    await tester.pump();

    expect(find.text('world'), findsOneWidget);
    expect(find.text('generation / era'), findsOneWidget);
    expect(find.text('世'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: CompareBody(card: realm, drawing: HandwritingInput.empty),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('world'), findsOneWidget);
    expect(find.text('boundary / realm'), findsOneWidget);
    expect(find.byType(DisambiguationHint), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: CompareBody(
            card: world,
            drawing: HandwritingInput.empty,
            isOnboarding: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('world'), findsOneWidget);
    expect(find.text('generation / era'), findsOneWidget);
  });

  testWidgets('kanji list shows hints only on cards that have them', (
    tester,
  ) async {
    usePhoneViewport(tester);
    await pumpList(tester, cards: [one, world, realm]);

    expect(find.text('一'), findsOneWidget);
    expect(find.text('世'), findsOneWidget);
    expect(find.text('界'), findsOneWidget);
    expect(find.text('one'), findsNothing);
    expect(find.text('world'), findsNWidgets(2));
    expect(find.text('generation / era'), findsOneWidget);
    expect(find.text('boundary / realm'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('kanji detail places the hint under the meaning', (tester) async {
    usePhoneViewport(tester);
    await pumpDetail(tester, card: world);

    expect(find.text('World'), findsOneWidget);
    expect(find.text('generation / era'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('generation / era')).dy,
      greaterThan(tester.getBottomLeft(find.text('World')).dy),
    );

    await pumpDetail(tester, card: one);
    expect(find.text('One'), findsOneWidget);
    expect(find.byType(DisambiguationHint), findsNothing);
  });

  testWidgets('detail hint remains muted in dark theme', (tester) async {
    usePhoneViewport(tester);
    await pumpDetail(tester, card: realm, theme: AppTheme.dark);

    expect(find.text('World'), findsOneWidget);
    expect(find.text('boundary / realm'), findsOneWidget);
    final hint = tester.widget<Text>(find.text('boundary / realm'));
    expect(hint.style?.color, AppTheme.dark.mutedText);
  });
}

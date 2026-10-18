import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/handwriting.dart';
import 'package:fiveminutekanji/core/models/kanji_card.dart';
import 'package:fiveminutekanji/core/models/review.dart';
import 'package:fiveminutekanji/core/theme/app_theme.dart';
import 'package:fiveminutekanji/features/review/compare_body.dart';
import 'package:fiveminutekanji/features/review/review_screen.dart';
import 'package:fiveminutekanji/features/review/widgets/handwriting_pad.dart';
import 'package:fiveminutekanji/repositories/progress_repository.dart';
import 'package:fiveminutekanji/services/srs_engine.dart';
import 'package:fiveminutekanji/services/srs_scheduler.dart';
import 'package:fiveminutekanji/widgets/common_words_section.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 2, 8);
  const config = ReviewSessionConfig(
    duration: Duration(minutes: 5),
    maxCards: 5,
  );

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  void usePhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  KanjiCard studyCard({
    required String id,
    required String character,
    required String keyword,
    List<CommonWord> commonWords = const [],
  }) {
    return KanjiCard(
      id: id,
      character: character,
      meaning: keyword,
      keyword: keyword,
      mnemonic: 'mnemonic $id',
      commonWords: commonWords,
      difficulty: 10,
      frequency: 10,
    );
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

  const schoolWords = [
    CommonWord(word: '学校', reading: 'がっこう', meaning: 'school'),
    CommonWord(word: '学生', reading: 'がくせい', meaning: 'student'),
  ];
  const teacherWords = [
    CommonWord(word: '先生', reading: 'せんせい', meaning: 'teacher'),
    CommonWord(word: '生活', reading: 'せいかつ', meaning: 'daily life'),
  ];

  Future<void> pumpReview(
    WidgetTester tester, {
    required List<KanjiCard> cards,
    required MemoryProgressRepository progress,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ProgressRepository>.value(value: progress),
          Provider<SrsScheduler>.value(value: const SrsEngine()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: ReviewScreen(cards: cards, config: config, clock: () => now),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('cards without common words expose an empty list', () {
    final card = studyCard(id: 'plain', character: '一', keyword: 'one');
    expect(card.commonWords, isEmpty);
    expect(card.hasCommonWords, isFalse);
    expect(
      const CommonWord(word: ' ', reading: '\n', meaning: '').isBlank,
      isTrue,
    );
  });

  testWidgets('new kanji shows vocabulary while learning, not while drawing', (
    tester,
  ) async {
    usePhoneViewport(tester);
    final card = studyCard(
      id: 'learn-gaku',
      character: '学',
      keyword: 'study',
      commonWords: schoolWords,
    );
    final progress = MemoryProgressRepository();
    await progress.seedIfNeeded([card.id], now: now);

    await pumpReview(tester, cards: [card], progress: progress);

    expect(find.text('COMMON WORDS'), findsOneWidget);
    expect(find.text('学校'), findsOneWidget);
    expect(find.text('がっこう'), findsOneWidget);
    expect(find.text('school'), findsOneWidget);
    expect(find.text('Practice Writing'), findsOneWidget);
    expect(find.byType(HandwritingPad), findsNothing);

    await tester.tap(find.text('Practice Writing'));
    await tester.pumpAndSettle();

    expect(find.text('Done'), findsOneWidget);
    expect(find.byType(HandwritingPad), findsOneWidget);
    expect(find.text('COMMON WORDS'), findsNothing);
    expect(find.text('学校'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('review reveals vocabulary only after the answer', (
    tester,
  ) async {
    usePhoneViewport(tester);
    final first = studyCard(
      id: 'review-gaku',
      character: '学',
      keyword: 'study',
      commonWords: schoolWords,
    );
    final second = studyCard(
      id: 'review-sei',
      character: '生',
      keyword: 'life',
      commonWords: teacherWords,
    );
    final progress = MemoryProgressRepository(
      schedules: {
        first.id: reviewing(first.id),
        second.id: reviewing(second.id),
      },
    );

    await pumpReview(tester, cards: [first, second], progress: progress);

    expect(find.text('study'), findsOneWidget);
    expect(find.text('Submit'), findsOneWidget);
    expect(find.byType(HandwritingPad), findsOneWidget);
    expect(find.text('COMMON WORDS'), findsNothing);
    expect(find.text('学校'), findsNothing);
    expect(find.text('学生'), findsNothing);
    expect(find.byType(CompareBody), findsNothing);

    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(find.byType(CompareBody), findsOneWidget);
    expect(find.text('COMMON WORDS'), findsOneWidget);
    expect(find.text('学校'), findsOneWidget);
    expect(find.text('がっこう'), findsOneWidget);
    expect(find.text('school'), findsOneWidget);
    expect(find.text('学生'), findsOneWidget);
    expect(find.text('がくせい'), findsOneWidget);
    expect(find.text('student'), findsOneWidget);
    expect(find.text('先生'), findsNothing);
    expect(find.text('Again'), findsOneWidget);
    expect(find.text('Good'), findsOneWidget);
    expect(
      tester.widget<HandwritingPad>(find.byType(HandwritingPad)).readOnly,
      isTrue,
    );

    await tester.tap(find.text('Good'));
    await tester.pumpAndSettle();

    expect(find.text('life'), findsOneWidget);
    expect(find.text('Submit'), findsOneWidget);
    expect(find.text('COMMON WORDS'), findsNothing);
    expect(find.text('学校'), findsNothing);
    expect(find.text('先生'), findsNothing);

    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(find.text('COMMON WORDS'), findsOneWidget);
    expect(find.text('先生'), findsOneWidget);
    expect(find.text('せんせい'), findsOneWidget);
    expect(find.text('teacher'), findsOneWidget);
    expect(find.text('生活'), findsOneWidget);
    expect(find.text('せいかつ'), findsOneWidget);
    expect(find.text('daily life'), findsOneWidget);
    expect(find.text('学校'), findsNothing);
    expect(find.text('school'), findsNothing);
    expect(find.text('Again'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('answer side hides an empty vocabulary list', (tester) async {
    usePhoneViewport(tester);
    final card = studyCard(id: 'review-plain', character: '一', keyword: 'one');
    final progress = MemoryProgressRepository(
      schedules: {card.id: reviewing(card.id)},
    );

    await pumpReview(tester, cards: [card], progress: progress);
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(find.byType(CompareBody), findsOneWidget);
    expect(find.text('COMMON WORDS'), findsNothing);
    expect(find.byType(CommonWordsSection), findsNothing);
    expect(find.text('Again'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long vocabulary wraps on a narrow answer card', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const longMeaning =
        'an extremely long definition used to confirm that vocabulary text wraps inside a narrow phone layout without overflowing the screen';
    final card = studyCard(
      id: 'review-long',
      character: '学',
      keyword: 'study',
      commonWords: const [
        CommonWord(
          word: '超長期学校教育制度改善推進委員会',
          reading: 'ちょうちょうき',
          meaning: longMeaning,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SafeArea(
            child: CompareBody(card: card, drawing: HandwritingInput.empty),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('COMMON WORDS'), findsOneWidget);
    expect(find.text('超長期学校教育制度改善推進委員会'), findsOneWidget);
    expect(find.text(longMeaning), findsOneWidget);
    expect(tester.getSize(find.text(longMeaning)).height, greaterThan(36));
    final wordSize = tester.getSize(find.text('超長期学校教育制度改善推進委員会'));
    expect(wordSize.width, lessThanOrEqualTo(320));
    expect(wordSize.height, greaterThan(28));
    expect(tester.takeException(), isNull);
  });

  testWidgets('learn card fits without scrolling', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final card = KanjiCard(
      id: 'fit-kyuu',
      character: '休',
      meaning: 'rest',
      keyword: 'rest',
      mnemonic: 'A person rests against a tree.',
      components: const ['亻 — person', '木 — tree'],
      onyomi: const ['キュウ'],
      kunyomi: const ['やすむ'],
      commonWords: const [
        CommonWord(word: '夏休み', reading: 'なつやすみ', meaning: 'summer vacation'),
        CommonWord(word: '休み', reading: 'やすみ', meaning: 'rest'),
        CommonWord(word: '休暇', reading: 'きゅうか', meaning: 'holiday'),
      ],
      difficulty: 18,
      frequency: 10,
    );
    final progress = MemoryProgressRepository();
    await progress.seedIfNeeded([card.id], now: now);

    await pumpReview(tester, cards: [card], progress: progress);

    expect(find.text('COMPONENTS'), findsNothing);
    expect(find.text(card.componentsLabel), findsNothing);
    expect(find.text('person'), findsOneWidget);
    expect(find.text('休み'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(
      tester.getRect(find.text('休暇')).bottom,
      lessThanOrEqualTo(tester.getRect(find.text('Practice Writing')).top),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('answer card fits without scrolling', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final card = KanjiCard(
      id: 'fit-kyuu-review',
      character: '休',
      meaning: 'rest',
      keyword: 'rest',
      mnemonic: 'A person rests against a tree.',
      components: const ['亻 — person', '木 — tree'],
      onyomi: const ['キュウ'],
      kunyomi: const ['やすむ'],
      commonWords: const [
        CommonWord(word: '夏休み', reading: 'なつやすみ', meaning: 'summer vacation'),
        CommonWord(word: '休み', reading: 'やすみ', meaning: 'rest'),
        CommonWord(word: '休暇', reading: 'きゅうか', meaning: 'holiday'),
      ],
      difficulty: 18,
      frequency: 10,
    );
    final reviewProgress = MemoryProgressRepository(
      schedules: {card.id: reviewing(card.id)},
    );

    await pumpReview(tester, cards: [card], progress: reviewProgress);
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(find.byType(CompareBody), findsOneWidget);
    expect(find.text('COMPONENTS'), findsNothing);
    expect(find.text('休暇'), findsOneWidget);
    expect(find.text('person'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(
      tester.getRect(find.text('休暇')).bottom,
      lessThanOrEqualTo(tester.getRect(find.text('Again')).top),
    );
    expect(tester.takeException(), isNull);
  });
}

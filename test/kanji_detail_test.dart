import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/kanji_card.dart';
import 'package:fiveminutekanji/core/models/kanji_status.dart';
import 'package:fiveminutekanji/core/models/review_duration.dart';
import 'package:fiveminutekanji/core/models/stroke_data.dart';
import 'package:fiveminutekanji/core/theme/app_theme.dart';
import 'package:fiveminutekanji/features/kanji_list/kanji_detail_screen.dart';
import 'package:fiveminutekanji/widgets/common_words_section.dart';
import 'package:fiveminutekanji/features/stroke_order/kanji_stroke_animation.dart';
import 'package:fiveminutekanji/repositories/progress_repository.dart';
import 'package:fiveminutekanji/repositories/stroke_data_repository.dart';
import 'package:fiveminutekanji/services/mark_as_known.dart';
import 'package:fiveminutekanji/services/srs_engine.dart';

import 'support/fakes.dart';

StrokeData loadFixture(String hex) {
  final raw = File('test/fixtures/strokes/$hex.json').readAsStringSync();
  return StrokeData.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
}

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

  const card = KanjiCard(
    id: 'n5-001',
    character: '一',
    meaning: 'one',
    keyword: 'one',
    mnemonic: 'One horizontal stroke.',
    components: [],
    jlptLevel: JlptLevel.n5,
    onyomi: ['イチ'],
    kunyomi: ['ひと'],
  );

  Future<void> pumpDetail(
    WidgetTester tester, {
    required KanjiCard kanji,
    StrokeData? strokeData,
    KanjiProgressStatus status = KanjiProgressStatus.notEncountered,
    CardSchedule? schedule,
    ProgressRepository? progress,
  }) async {
    final repo = progress ?? MemoryProgressRepository();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ProgressRepository>.value(value: repo),
          Provider<StrokeDataRepository>.value(
            value: MemoryStrokeDataRepository({kanji.character: ?strokeData}),
          ),
          Provider<MarkAsKnownService>(
            create: (_) => MarkAsKnownService(
              progressRepository: repo,
              srsEngine: const SrsEngine(),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: KanjiDetailScreen(
            card: kanji,
            status: status,
            schedule: schedule,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('detail uses stroke animation as the only kanji hero', (
    tester,
  ) async {
    usePhoneViewport(tester);
    await pumpDetail(tester, kanji: card, strokeData: loadFixture('04e00'));

    expect(find.text('Kanji Detail'), findsOneWidget);
    expect(find.text('一'), findsNothing);
    expect(find.byType(KanjiStrokeAnimation), findsOneWidget);
    expect(find.text('Stroke Order'), findsOneWidget);
    expect(find.text('1 stroke'), findsOneWidget);

    final state = tester.state<KanjiStrokeAnimationState>(
      find.byType(KanjiStrokeAnimation),
    );
    expect(state.hasStrokeData, isTrue);
    expect(state.isPlaying, isFalse);
    expect(state.isComplete, isTrue);

    final hero = tester.getSize(find.byType(KanjiStrokeAnimation));
    expect(hero.height, greaterThan(190));
    expect(hero.height, lessThan(250));

    expect(find.text('MEANING'), findsOneWidget);
    expect(find.text('One'), findsOneWidget);
    expect(find.text('ONE'), findsNothing);
    expect(find.text('READINGS'), findsOneWidget);
    expect(find.text('On'), findsOneWidget);
    expect(find.text('イチ'), findsOneWidget);
    expect(find.text('Kun'), findsOneWidget);
    expect(find.text('ひと'), findsOneWidget);
    expect(find.text('STATUS'), findsOneWidget);
    expect(find.text('Not encountered'), findsOneWidget);
    expect(find.text('N5'), findsOneWidget);
    expect(find.text('MEMORY TIP'), findsOneWidget);
    expect(find.text('One horizontal stroke.'), findsOneWidget);
    expect(find.text('COMMON WORDS'), findsNothing);
    expect(find.text('REVIEW STATS'), findsOneWidget);
    expect(find.text('Reviews'), findsOneWidget);
    expect(find.text('Time estimate'), findsOneWidget);
    expect(find.text('21s'), findsOneWidget);
    expect(find.text('Mark as Known'), findsOneWidget);
  });

  testWidgets('debug detail uses the learned pace for a studied card', (
    tester,
  ) async {
    usePhoneViewport(tester);
    final mature = CardSchedule(
      cardId: card.id,
      state: CardLearningState.review,
      reviewCount: 8,
      correctCount: 8,
      incorrectCount: 0,
      dueAt: DateTime(2026, 9, 2),
      interval: const Duration(days: 40),
      ease: 2.5,
      lastReviewedAt: DateTime(2026, 8, 1),
      consecutiveGoodCount: 8,
    );
    final progress = MemoryProgressRepository(
      reviewDurations: const ReviewDurationModel(
        global: PaceStats(ewmaMs: 30000, count: 20),
        mature: PaceStats(ewmaMs: 30000, count: 20),
      ),
    );

    await pumpDetail(
      tester,
      kanji: card,
      status: KanjiProgressStatus.mastered,
      schedule: mature,
      progress: progress,
    );
    await tester.pump();

    expect(find.text('Time estimate'), findsOneWidget);
    expect(find.text('30s'), findsOneWidget);
    expect(find.text('21s'), findsNothing);
  });

  testWidgets('detail replay starts the stroke animation from the beginning', (
    tester,
  ) async {
    usePhoneViewport(tester);
    await pumpDetail(tester, kanji: card, strokeData: loadFixture('04e00'));

    final state = tester.state<KanjiStrokeAnimationState>(
      find.byType(KanjiStrokeAnimation),
    );
    expect(state.isComplete, isTrue);

    await tester.tap(find.text('Stroke Order'));
    await tester.pump();
    expect(state.isPlaying, isTrue);
    expect(state.isComplete, isFalse);
  });

  testWidgets('detail omits empty readings and keeps Mark as Known', (
    tester,
  ) async {
    usePhoneViewport(tester);
    const bare = KanjiCard(
      id: 'bare',
      character: '一',
      meaning: 'daylight',
      keyword: 'day',
      mnemonic: 'A sun through a window.',
      structuredComponents: [
        KanjiComponent(
          id: 'sun',
          character: '日',
          name: 'sun',
          mnemonicText: 'sun',
        ),
      ],
      jlptLevel: JlptLevel.none,
    );
    await pumpDetail(tester, kanji: bare, strokeData: loadFixture('04e00'));

    expect(find.text('Day'), findsOneWidget);
    expect(find.text('daylight'), findsOneWidget);
    expect(find.text('READINGS'), findsNothing);
    expect(find.text('On'), findsNothing);
    expect(find.text('N5'), findsNothing);
    expect(find.text('COMPONENTS'), findsOneWidget);
    expect(find.text(bare.componentsLabel), findsOneWidget);
    expect(find.text('Mark as Known'), findsOneWidget);

    await tester.tap(find.text('Mark as Known'));
    await tester.pumpAndSettle();
    expect(find.text('Learning'), findsOneWidget);
    expect(find.text('Mark as Known'), findsNothing);
  });

  testWidgets('large text still scrolls the detail reference content', (
    tester,
  ) async {
    usePhoneViewport(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpDetail(tester, kanji: card, strokeData: loadFixture('04e00'));

    expect(find.text('MEANING'), findsOneWidget);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();
    expect(find.text('REVIEW STATS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'detail shows common words and replaces them with the next kanji',
    (tester) async {
      usePhoneViewport(tester);
      const school = KanjiCard(
        id: 'school',
        character: '学',
        meaning: 'study',
        keyword: 'study',
        mnemonic: 'A child studies under a roof.',
        commonWords: [
          CommonWord(word: '学校', reading: 'がっこう', meaning: 'school'),
          CommonWord(word: '学生', reading: 'がくせい', meaning: 'student'),
        ],
      );
      const life = KanjiCard(
        id: 'life',
        character: '生',
        meaning: 'life',
        keyword: 'life',
        mnemonic: 'A sprout pushing up through the soil.',
        commonWords: [
          CommonWord(word: '先生', reading: 'せんせい', meaning: 'teacher'),
          CommonWord(word: '生活', reading: 'せいかつ', meaning: 'life'),
        ],
      );

      await pumpDetail(tester, kanji: school);
      expect(find.text('COMMON WORDS'), findsOneWidget);
      expect(find.text('学校'), findsOneWidget);
      expect(find.text('がっこう'), findsOneWidget);
      expect(find.text('school'), findsOneWidget);
      expect(find.text('学生'), findsOneWidget);
      expect(find.text('がくせい'), findsOneWidget);
      expect(find.text('student'), findsOneWidget);

      final memoryTop = tester.getTopLeft(find.text('MEMORY TIP')).dy;
      final wordsTop = tester.getTopLeft(find.text('COMMON WORDS')).dy;
      final statsTop = tester.getTopLeft(find.text('REVIEW STATS')).dy;
      expect(wordsTop, greaterThan(memoryTop));
      expect(statsTop, greaterThan(wordsTop));

      await pumpDetail(tester, kanji: life);
      expect(find.text('学校'), findsNothing);
      expect(find.text('school'), findsNothing);
      expect(find.text('先生'), findsOneWidget);
      expect(find.text('せんせい'), findsOneWidget);
      expect(find.text('teacher'), findsOneWidget);
      expect(find.text('生活'), findsOneWidget);
      expect(find.text('せいかつ'), findsOneWidget);
      expect(find.text('life'), findsOneWidget);
    },
  );

  testWidgets('detail hides blank vocabulary instead of an empty section', (
    tester,
  ) async {
    usePhoneViewport(tester);
    const blank = KanjiCard(
      id: 'blank-words',
      character: '一',
      meaning: 'one',
      keyword: 'one',
      mnemonic: 'One horizontal stroke.',
      commonWords: [CommonWord(word: ' ', reading: '', meaning: '  ')],
    );

    await pumpDetail(tester, kanji: blank);
    expect(find.text('COMMON WORDS'), findsNothing);
    expect(find.byType(CommonWordsSection), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail wraps long vocabulary on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const longMeaning =
        'an extremely long definition used to confirm that vocabulary text wraps inside a narrow phone layout without overflowing the screen';
    const longCard = KanjiCard(
      id: 'long-words',
      character: '学',
      meaning: 'study',
      keyword: 'study',
      mnemonic: 'A child studies under a roof.',
      commonWords: [
        CommonWord(
          word: '超長期学校教育制度改善推進委員会',
          reading: 'ちょうちょうき',
          meaning: longMeaning,
        ),
      ],
    );

    await pumpDetail(tester, kanji: longCard);
    expect(find.text('超長期学校教育制度改善推進委員会'), findsOneWidget);
    expect(find.text(longMeaning), findsOneWidget);
    expect(tester.getSize(find.text(longMeaning)).height, greaterThan(36));
    expect(tester.takeException(), isNull);
  });
}

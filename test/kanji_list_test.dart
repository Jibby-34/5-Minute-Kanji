import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fiveminutekanji/app.dart';
import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/kanji_card.dart';
import 'package:fiveminutekanji/core/models/kanji_status.dart';
import 'package:fiveminutekanji/core/models/progress.dart';
import 'package:fiveminutekanji/core/models/review.dart';
import 'package:fiveminutekanji/core/theme/app_theme.dart';
import 'package:fiveminutekanji/data/hardcoded_kanji_repository.dart';
import 'package:fiveminutekanji/data/shared_prefs_progress_repository.dart';
import 'package:fiveminutekanji/features/kanji_list/kanji_list_screen.dart';
import 'package:fiveminutekanji/repositories/kanji_repository.dart';
import 'package:fiveminutekanji/repositories/progress_repository.dart';
import 'package:fiveminutekanji/services/initial_known_card_schedule.dart';
import 'package:fiveminutekanji/services/mark_as_known.dart';
import 'package:fiveminutekanji/services/srs_engine.dart';

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

  testWidgets('home list button opens kanji grid and detail', (tester) async {
    usePhoneViewport(tester);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const kanji = HardcodedKanjiRepository();
    final progress = SharedPrefsProgressRepository(prefs);
    final cards = await kanji.getAll();
    await progress.seedIfNeeded(cards.map((card) => card.id).toList());
    final first = cards.first;

    await tester.pumpWidget(
      FiveMinuteKanjiApp(kanjiRepository: kanji, progressRepository: progress),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byTooltip('Kanji List'));
    await tester.pumpAndSettle();

    expect(find.text('Kanji List'), findsOneWidget);
    expect(find.text('JLPT N5'), findsOneWidget);
    expect(find.text('JLPT N3'), findsNothing);
    expect(find.text('JLPT N2'), findsNothing);
    expect(find.text('JLPT N1'), findsNothing);
    expect(find.text('No JLPT Level'), findsNothing);
    expect(find.text(first.character), findsOneWidget);

    await tester.tap(find.text(first.character));
    await tester.pumpAndSettle();

    expect(find.text('Kanji Detail'), findsOneWidget);
    expect(find.text('MEANING'), findsOneWidget);
    expect(
      find.text(
        '${first.keyword[0].toUpperCase()}${first.keyword.substring(1)}',
      ),
      findsOneWidget,
    );
    expect(find.text('MEMORY TIP'), findsOneWidget);
    expect(find.text(first.mnemonic), findsOneWidget);
    expect(find.text('Not encountered'), findsOneWidget);
    expect(find.text('Reviews'), findsOneWidget);
  });

  testWidgets('three consecutive Goods shows Mastered on detail', (
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
    const engine = SrsEngine();
    final now = DateTime(2026, 9, 2, 8);

    var schedule = (await progress.getSchedule(first.id))!;
    for (var i = 0; i < 3; i++) {
      schedule = engine.schedule(
        current: schedule,
        result: ReviewResult.good,
        now: now,
      );
    }
    await progress.saveSchedule(schedule);

    await tester.pumpWidget(
      FiveMinuteKanjiApp(kanjiRepository: kanji, progressRepository: progress),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byTooltip('Kanji List'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(first.character));
    await tester.pumpAndSettle();

    expect(find.text('Mastered'), findsOneWidget);
  });

  testWidgets('Again after mastered shows Learning on detail', (tester) async {
    usePhoneViewport(tester);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const kanji = HardcodedKanjiRepository();
    final progress = SharedPrefsProgressRepository(prefs);
    final cards = await kanji.getAll();
    await progress.seedIfNeeded(cards.map((card) => card.id).toList());
    final first = cards.first;
    const engine = SrsEngine();
    final now = DateTime(2026, 9, 2, 8);

    var schedule = (await progress.getSchedule(first.id))!;
    for (var i = 0; i < 3; i++) {
      schedule = engine.schedule(
        current: schedule,
        result: ReviewResult.good,
        now: now,
      );
    }
    schedule = engine.schedule(
      current: schedule,
      result: ReviewResult.again,
      now: now,
    );
    await progress.saveSchedule(schedule);

    await tester.pumpWidget(
      FiveMinuteKanjiApp(kanjiRepository: kanji, progressRepository: progress),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byTooltip('Kanji List'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(first.character));
    await tester.pumpAndSettle();

    expect(find.text('Learning'), findsOneWidget);
    expect(find.text('Mastered'), findsNothing);
  });

  testWidgets('Mark as Known on detail enters SRS as learning', (tester) async {
    usePhoneViewport(tester);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const kanji = HardcodedKanjiRepository();
    final progress = SharedPrefsProgressRepository(prefs);
    final cards = await kanji.getAll();
    await progress.seedIfNeeded(cards.map((card) => card.id).toList());
    final first = cards.first;
    final now = DateTime(2026, 9, 2, 8);
    await progress.saveDailyNewKanji(
      DailyNewKanjiProgress(date: now, count: 3),
    );

    await tester.pumpWidget(
      FiveMinuteKanjiApp(kanjiRepository: kanji, progressRepository: progress),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byTooltip('Kanji List'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(first.character));
    await tester.pumpAndSettle();

    expect(find.text('Not encountered'), findsOneWidget);
    expect(find.text('Mark as Known'), findsOneWidget);

    await tester.tap(find.text('Mark as Known'));
    await tester.pumpAndSettle();

    expect(find.text('Learning'), findsOneWidget);
    expect(find.text('Mastered'), findsNothing);
    expect(find.text('Not encountered'), findsNothing);
    expect(find.text('Mark as Known'), findsNothing);

    final schedule = await progress.getSchedule(first.id);
    expect(schedule!.state, CardLearningState.review);
    expect(schedule.interval, calculateInitialKnownCardSchedule(first.id));
    expect(schedule.dueAt.isAfter(DateTime.now()), isTrue);
    expect((await progress.getDailyNewKanji()).count, 3);

    final restarted = SharedPrefsProgressRepository(prefs);
    final restored = await restarted.getSchedule(first.id);
    expect(restored!.interval, calculateInitialKnownCardSchedule(first.id));
    expect(restored.dueAt, schedule.dueAt);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(first.character));
    await tester.pumpAndSettle();
    expect(find.text('Learning'), findsOneWidget);
  });

  testWidgets(
    'mass Mark as Known selects only new cards and updates the list',
    (tester) async {
      usePhoneViewport(tester);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final cards = [
        testCard('a', keyword: 'one', character: '一', jlptLevel: JlptLevel.n5),
        testCard('b', keyword: 'two', character: '二', jlptLevel: JlptLevel.n5),
        testCard(
          'c',
          keyword: 'person',
          character: '人',
          jlptLevel: JlptLevel.n4,
        ),
      ];
      final kanji = FakeKanjiRepository(cards);
      final progress = SharedPrefsProgressRepository(prefs);
      await progress.seedIfNeeded(cards.map((card) => card.id).toList());
      final first = cards.first;
      final second = cards[1];
      final last = cards.last;
      final now = DateTime(2026, 9, 2, 8);

      var learning = (await progress.getSchedule(first.id))!;
      learning = const SrsEngine().introduce(current: learning, now: now);
      await progress.saveSchedule(learning);

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

      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      expect(find.text('0 selected'), findsOneWidget);

      await tester.tap(find.text(first.character));
      await tester.pumpAndSettle();
      expect(find.text('0 selected'), findsOneWidget);

      await tester.tap(find.text(second.character));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);

      await tester.tap(find.text(second.character));
      await tester.pumpAndSettle();
      expect(find.text('0 selected'), findsOneWidget);

      await tester.tap(find.text(second.character));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -240));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);

      await tester.tap(find.text('Select All New'));
      await tester.pumpAndSettle();
      expect(find.text('${cards.length - 1} selected'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Mark as Known'));
      await tester.pumpAndSettle();
      expect(
        find.text('Mark ${cards.length - 1} kanji as known?'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(TextButton, 'Mark as Known'));
      await tester.pumpAndSettle();

      expect(find.text('Select'), findsOneWidget);
      expect(find.text('Kanji List'), findsOneWidget);
      expect(
        (await progress.getSchedule(first.id))!.state,
        CardLearningState.learning,
      );
      expect(
        (await progress.getSchedule(second.id))!.interval,
        calculateInitialKnownCardSchedule(second.id),
      );
      expect(
        (await progress.getSchedule(last.id))!.interval,
        calculateInitialKnownCardSchedule(last.id),
      );

      await tester.tap(find.text(second.character));
      await tester.pumpAndSettle();
      expect(find.text('Learning'), findsOneWidget);
      expect(find.text('Mastered'), findsNothing);
    },
  );

  testWidgets('kanji overview groups cards by JLPT section', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime(2026, 9, 2, 8);
    final cards = [
      testCard('n5', character: '日', jlptLevel: JlptLevel.n5),
      testCard('n4', character: '堂', jlptLevel: JlptLevel.n4),
      testCard('n3', character: '議', jlptLevel: JlptLevel.n3),
      testCard('n2', character: '績', jlptLevel: JlptLevel.n2),
      testCard('n1', character: '憂', jlptLevel: JlptLevel.n1),
      testCard('none', character: '龍'),
    ];
    final progress = MemoryProgressRepository(
      schedules: {
        'n5': CardSchedule.fresh('n5', now),
        'n4': CardSchedule(
          cardId: 'n4',
          state: CardLearningState.review,
          reviewCount: 1,
          correctCount: 1,
          incorrectCount: 0,
          dueAt: now,
          interval: const Duration(days: 1),
          ease: 2.5,
          consecutiveGoodCount: 1,
        ),
        'n3': CardSchedule.fresh('n3', now),
        'n2': CardSchedule.fresh('n2', now),
        'n1': CardSchedule.fresh('n1', now),
        'none': CardSchedule(
          cardId: 'none',
          state: CardLearningState.review,
          reviewCount: 3,
          correctCount: 3,
          incorrectCount: 0,
          dueAt: now,
          interval: const Duration(days: 1),
          ease: 2.5,
          consecutiveGoodCount: 3,
        ),
      },
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<KanjiRepository>.value(value: FakeKanjiRepository(cards)),
          Provider<ProgressRepository>.value(value: progress),
          Provider<MarkAsKnownService>(
            create: (_) => MarkAsKnownService(
              progressRepository: progress,
              srsEngine: const SrsEngine(),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const KanjiListScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    const titles = [
      'JLPT N5',
      'JLPT N4',
      'JLPT N3',
      'JLPT N2',
      'JLPT N1',
      'No JLPT Level',
    ];
    const characters = ['日', '堂', '議', '績', '憂', '龍'];

    for (final title in titles) {
      expect(find.text(title), findsOneWidget);
    }
    for (final character in characters) {
      expect(find.text(character), findsOneWidget);
    }

    final headingYs = [
      for (final title in titles) tester.getTopLeft(find.text(title)).dy,
    ];
    for (var i = 1; i < headingYs.length; i++) {
      expect(headingYs[i], greaterThan(headingYs[i - 1]));
    }

    expect(tester.getTopLeft(find.text('日')).dy, greaterThan(headingYs[0]));
    expect(tester.getTopLeft(find.text('日')).dy, lessThan(headingYs[1]));
    expect(tester.getTopLeft(find.text('堂')).dy, greaterThan(headingYs[1]));
    expect(tester.getTopLeft(find.text('堂')).dy, lessThan(headingYs[2]));
    expect(tester.getTopLeft(find.text('議')).dy, greaterThan(headingYs[2]));
    expect(tester.getTopLeft(find.text('議')).dy, lessThan(headingYs[3]));
    expect(tester.getTopLeft(find.text('績')).dy, greaterThan(headingYs[3]));
    expect(tester.getTopLeft(find.text('績')).dy, lessThan(headingYs[4]));
    expect(tester.getTopLeft(find.text('憂')).dy, greaterThan(headingYs[4]));
    expect(tester.getTopLeft(find.text('憂')).dy, lessThan(headingYs[5]));
    expect(tester.getTopLeft(find.text('龍')).dy, greaterThan(headingYs[5]));

    await tester.tap(find.text('日'));
    await tester.pumpAndSettle();
    expect(find.text('Kanji Detail'), findsOneWidget);
    expect(find.text('Not encountered'), findsOneWidget);
    expect(progress.schedules['n4']!.reviewCount, 1);
    expect(progress.schedules['none']!.consecutiveGoodCount, 3);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    Material cardMaterial(String character) {
      return tester.widget<Material>(
        find
            .ancestor(of: find.text(character), matching: find.byType(Material))
            .first,
      );
    }

    expect(
      cardMaterial('日').color,
      AppTheme.light.statusWash(KanjiProgressStatus.notEncountered),
    );
    expect(
      cardMaterial('堂').color,
      AppTheme.light.statusWash(KanjiProgressStatus.learning),
    );
    expect(
      cardMaterial('龍').color,
      AppTheme.light.statusWash(KanjiProgressStatus.mastered),
    );
  });

  testWidgets('kanji overview hides JLPT headers with no cards', (
    tester,
  ) async {
    usePhoneViewport(tester);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<KanjiRepository>.value(
            value: FakeKanjiRepository([
              testCard('n5', character: '日', jlptLevel: JlptLevel.n5),
              testCard('n3', character: '議', jlptLevel: JlptLevel.n3),
            ]),
          ),
          Provider<ProgressRepository>.value(value: MemoryProgressRepository()),
          Provider<MarkAsKnownService>(
            create: (context) => MarkAsKnownService(
              progressRepository: context.read<ProgressRepository>(),
              srsEngine: const SrsEngine(),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const KanjiListScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('JLPT N5'), findsOneWidget);
    expect(find.text('JLPT N3'), findsOneWidget);
    expect(find.text('JLPT N4'), findsNothing);
    expect(find.text('JLPT N2'), findsNothing);
    expect(find.text('JLPT N1'), findsNothing);
    expect(find.text('No JLPT Level'), findsNothing);
  });
}

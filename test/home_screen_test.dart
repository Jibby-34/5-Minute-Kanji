import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fiveminutekanji/app.dart';
import 'package:fiveminutekanji/data/hardcoded_kanji_repository.dart';
import 'package:fiveminutekanji/data/shared_prefs_progress_repository.dart';
import 'package:fiveminutekanji/features/home/home_screen.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpHome(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const kanji = HardcodedKanjiRepository();
    final progress = SharedPrefsProgressRepository(prefs);
    final cards = await kanji.getAll();
    await progress.seedIfNeeded(cards.map((card) => card.id).toList());

    await completeOnboarding(progress);
    await tester.pumpWidget(
      FiveMinuteKanjiApp(kanjiRepository: kanji, progressRepository: progress),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Finder greeting() {
    return find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          (widget.data == 'Good Morning' ||
              widget.data == 'Good Afternoon' ||
              widget.data == 'Good Evening'),
    );
  }

  testWidgets('home keeps greeting, workload, streak, and start action', (
    tester,
  ) async {
    await pumpHome(tester);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(greeting(), findsOneWidget);
    expect(find.text('YOUR STUDY PLAN'), findsNothing);
    expect(find.text('study items today'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('Start Review'), findsOneWidget);
    expect(find.textContaining('day streak'), findsOneWidget);
    expect(find.textContaining('min'), findsOneWidget);
    // Work is waiting, so the next review is now and the line stays out.
    expect(find.textContaining('Next review:'), findsNothing);
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.byTooltip('Kanji list'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Streak sits in the top bar. The count leads down to the start button.
    final number = tester.getCenter(find.text('10'));
    final start = tester.getCenter(find.text('Start Review'));
    final streak = tester.getCenter(find.textContaining('day streak'));
    final hello = tester.getCenter(greeting());
    expect(streak.dy, lessThan(hello.dy));
    expect(hello.dy, lessThan(number.dy));
    expect(number.dy, lessThan(start.dy));
  });

  testWidgets('home layout does not overflow common phone sizes', (
    tester,
  ) async {
    const sizes = <Size>[
      Size(320, 568),
      Size(375, 667),
      Size(390, 844),
      Size(412, 915),
      Size(430, 932),
    ];

    for (final size in sizes) {
      await pumpHome(tester, size: size);
      expect(
        tester.takeException(),
        isNull,
        reason: 'overflow on ${size.width}x${size.height}',
      );
      expect(greeting(), findsOneWidget);
      expect(find.text('Start Review'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(
        tester.getCenter(find.text('10')).dy,
        lessThan(tester.getCenter(find.text('Start Review')).dy),
        reason:
            'count should sit above the button on ${size.width}x${size.height}',
      );
    }
  });

  testWidgets('home layout holds together at a larger text scale', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(375, 667), textScale: 1.3);

    expect(tester.takeException(), isNull);
    expect(greeting(), findsOneWidget);
    expect(find.text('study items today'), findsOneWidget);
    expect(find.text('Start Review'), findsOneWidget);
  });
}

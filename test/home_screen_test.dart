import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fiveminutekanji/app.dart';
import 'package:fiveminutekanji/data/hardcoded_kanji_repository.dart';
import 'package:fiveminutekanji/data/shared_prefs_progress_repository.dart';
import 'package:fiveminutekanji/features/home/home_screen.dart';

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
          (widget.data == 'Good morning' ||
              widget.data == 'Good afternoon' ||
              widget.data == 'Good evening'),
    );
  }

  testWidgets('home keeps greeting, workload, streak, and start action', (
    tester,
  ) async {
    await pumpHome(tester);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(greeting(), findsOneWidget);
    expect(find.text('kanji remaining today'), findsOneWidget);
    expect(find.text('Start Review'), findsOneWidget);
    expect(find.textContaining('day streak'), findsOneWidget);
    expect(find.textContaining('min'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final number = tester.getCenter(find.text('5'));
    final streak = tester.getCenter(find.textContaining('day streak'));
    final start = tester.getCenter(find.text('Start Review'));
    expect(number.dy, lessThan(844 * 0.42));
    expect(streak.dy, greaterThan(number.dy));
    expect(start.dy, greaterThan(streak.dy));
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
      expect(
        tester.getCenter(find.text('5')).dy,
        lessThan(size.height * 0.45),
        reason:
            'workload should stay upper-middle on ${size.width}x${size.height}',
      );
    }
  });

  testWidgets('home layout holds together at a larger text scale', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(375, 667), textScale: 1.3);

    expect(tester.takeException(), isNull);
    expect(greeting(), findsOneWidget);
    expect(find.text('kanji remaining today'), findsOneWidget);
    expect(find.text('Start Review'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:fiveminutekanji/core/models/review.dart';
import 'package:fiveminutekanji/core/models/start_of_day.dart';
import 'package:fiveminutekanji/core/theme/app_theme.dart';
import 'package:fiveminutekanji/features/session_complete/session_complete_screen.dart';
import 'package:fiveminutekanji/widgets/bottom_action_inset.dart';
import 'package:fiveminutekanji/widgets/primary_button.dart';
import 'package:fiveminutekanji/widgets/soft_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final clockNow = DateTime(2026, 10, 10, 10);

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpSummary(
    WidgetTester tester, {
    required SessionSummary summary,
    Size size = const Size(390, 844),
    double textScale = 1,
    ThemeData? theme,
    EdgeInsets viewPadding = EdgeInsets.zero,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = FakeViewPadding(
      left: viewPadding.left,
      top: viewPadding.top,
      right: viewPadding.right,
      bottom: viewPadding.bottom,
    );
    tester.view.padding = FakeViewPadding(
      left: viewPadding.left,
      top: viewPadding.top,
      right: viewPadding.right,
      bottom: viewPadding.bottom,
    );
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light,
        home: SessionCompleteScreen(summary: summary, clock: () => clockNow),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the session counts, duration, and next review', (
    tester,
  ) async {
    await pumpSummary(
      tester,
      summary: SessionSummary(
        duration: const Duration(minutes: 4, seconds: 12),
        reviewedCount: 12,
        successfulCount: 9,
        againCount: 3,
        nextReviewAt: DateTime(2026, 10, 11, 10),
      ),
    );

    expect(find.text('Nice work.'), findsOneWidget);
    expect(find.text('4m 12s'), findsOneWidget);
    expect(find.text('A little progress goes a long way.'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('kanji reviewed'), findsOneWidget);
    expect(find.text('Successful'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.text('Need another look'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('All caught up.'), findsNothing);
    expect(find.text('Next review.'), findsOneWidget);
    expect(find.text('Tomorrow'), findsOneWidget);
    expect(find.byType(SoftCard), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNWidgets(2));
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);

    final header = tester.getCenter(find.text('Nice work.'));
    final total = tester.getCenter(find.text('kanji reviewed'));
    final next = tester.getCenter(find.text('Next review.'));
    final done = tester.getCenter(find.text('Done'));
    expect(header.dy, lessThan(844 * 0.4));
    expect(header.dy, lessThan(total.dy));
    expect(total.dy, lessThan(next.dy));
    expect(next.dy, lessThan(done.dy));
  });

  testWidgets('phrases later today, a future date, soon, and now', (
    tester,
  ) async {
    Future<void> expectTiming(DateTime? due, String timing) async {
      await pumpSummary(
        tester,
        summary: SessionSummary(
          duration: const Duration(minutes: 75, seconds: 3),
          reviewedCount: 2,
          successfulCount: 1,
          againCount: 1,
          nextReviewAt: due,
        ),
      );
      expect(find.text('75m 03s'), findsOneWidget);
      expect(find.text(timing), findsOneWidget);
    }

    await expectTiming(DateTime(2026, 10, 10, 18), 'Later today');
    await expectTiming(DateTime(2026, 10, 15, 10), '10/15');
    await expectTiming(null, 'Soon');
    await expectTiming(clockNow, 'Now');
    await expectTiming(DateTime(2026, 10, 10, 10, 20), 'In 20 min');
  });

  testWidgets('zero again-reviews still shows the count and a calm note', (
    tester,
  ) async {
    await pumpSummary(
      tester,
      summary: const SessionSummary(
        duration: Duration(seconds: 12),
        reviewedCount: 4,
        successfulCount: 4,
        againCount: 0,
      ),
    );

    expect(find.text('0m 12s'), findsOneWidget);
    expect(find.text('A little progress goes a long way.'), findsOneWidget);
    expect(find.text('4'), findsNWidgets(2));
    expect(find.text('0'), findsOneWidget);
    expect(find.text('All caught up.'), findsOneWidget);
    expect(find.text('No reviews to revisit.'), findsNothing);
  });

  testWidgets('an empty sitting keeps zeros and avoids a progress claim', (
    tester,
  ) async {
    await pumpSummary(
      tester,
      summary: const SessionSummary(
        duration: Duration.zero,
        reviewedCount: 0,
        successfulCount: 0,
        againCount: 0,
      ),
    );

    expect(find.text('Nice work.'), findsOneWidget);
    expect(find.text('0m 00s'), findsOneWidget);
    expect(find.text('Nothing to review this time.'), findsOneWidget);
    expect(find.text('A little progress goes a long way.'), findsNothing);
    expect(find.text('0'), findsNWidgets(3));
    expect(find.text('kanji reviewed'), findsOneWidget);
    expect(find.text('No reviews to revisit.'), findsOneWidget);
    expect(find.text('All caught up.'), findsNothing);
    expect(find.text('Soon'), findsOneWidget);
  });

  testWidgets('Done stays clear of the summary and pops the route', (
    tester,
  ) async {
    const summary = SessionSummary(
      duration: Duration(minutes: 5),
      reviewedCount: 1,
      successfulCount: 1,
      againCount: 0,
    );

    tester.view.physicalSize = const Size(320, 500);
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SessionCompleteScreen(
                          summary: summary,
                          clock: () => clockNow,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(BottomActionInset), findsOneWidget);
    expect(find.widgetWithText(PrimaryButton, 'Done'), findsOneWidget);

    final scroll = tester.getRect(find.byType(SingleChildScrollView));
    final button = tester.getRect(find.byType(PrimaryButton));
    expect(scroll.bottom, lessThanOrEqualTo(button.top));
    expect(button.bottom, lessThanOrEqualTo(500 - 34));

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('Nice work.'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('dark theme lays out the same summary without overflow', (
    tester,
  ) async {
    await pumpSummary(
      tester,
      theme: AppTheme.dark,
      summary: const SessionSummary(
        duration: Duration(minutes: 3, seconds: 5),
        reviewedCount: 1,
        successfulCount: 0,
        againCount: 1,
        nextReviewAt: null,
      ),
    );

    expect(find.text('Nice work.'), findsOneWidget);
    expect(find.text('Need another look'), findsOneWidget);
    expect(find.text('All caught up.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('respects a custom start of day when naming the next review', (
    tester,
  ) async {
    // 3:30 the next calendar morning is still "later today" when the study
    // day runs until 4:00, and "tomorrow" when the day starts at midnight.
    final due = DateTime(2026, 10, 11, 3, 30);
    final summary = SessionSummary(
      duration: const Duration(minutes: 2),
      reviewedCount: 1,
      successfulCount: 1,
      againCount: 0,
      nextReviewAt: due,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SessionCompleteScreen(summary: summary, clock: () => clockNow),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Later today'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SessionCompleteScreen(
          summary: summary,
          startOfDay: const StartOfDay(hour: 0),
          clock: () => clockNow,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tomorrow'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

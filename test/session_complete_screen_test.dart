import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:fiveminutekanji/core/models/review.dart';
import 'package:fiveminutekanji/core/theme/app_theme.dart';
import 'package:fiveminutekanji/features/session_complete/session_complete_screen.dart';
import 'package:fiveminutekanji/widgets/bottom_action_inset.dart';
import 'package:fiveminutekanji/widgets/primary_button.dart';
import 'package:fiveminutekanji/widgets/soft_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
        home: SessionCompleteScreen(summary: summary),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the session counts and duration', (tester) async {
    await pumpSummary(
      tester,
      summary: const SessionSummary(
        duration: Duration(minutes: 4, seconds: 12),
        reviewedCount: 12,
        successfulCount: 9,
        againCount: 3,
      ),
    );

    expect(find.text("You're done for today!"), findsOneWidget);
    expect(find.text('Nice work!'), findsOneWidget);
    expect(find.text('4m 12s today'), findsOneWidget);
    expect(find.text('A little progress goes a long way.'), findsNothing);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('kanji reviewed'), findsOneWidget);
    expect(find.text('Successful'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.text('Need another look'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('All caught up.'), findsNothing);
    expect(find.textContaining('Next review'), findsNothing);
    expect(find.byType(SoftCard), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNWidgets(2));
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.byIcon(Icons.schedule_rounded), findsNothing);
    expect(tester.takeException(), isNull);

    final header = tester.getCenter(find.text("You're done for today!"));
    final total = tester.getCenter(find.text('kanji reviewed'));
    final done = tester.getCenter(find.text('Done'));
    expect(header.dy, lessThan(844 * 0.4));
    expect(header.dy, lessThan(total.dy));
    expect(total.dy, lessThan(done.dy));
  });

  testWidgets('extra cards stay optional after the plan is done', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => SessionCompleteScreen(
                      summary: const SessionSummary(
                        duration: Duration(minutes: 3),
                        reviewedCount: 4,
                        successfulCount: 4,
                        againCount: 0,
                        canContinue: true,
                      ),
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text("You're done for today!"), findsOneWidget);
    expect(find.text('Nice work!'), findsOneWidget);
    expect(find.text('3m 00s today'), findsOneWidget);
    expect(find.text('Have a little extra time?'), findsNothing);
    expect(
      find.text(
        "You haven't reached today's time goal yet. "
        'Press Continue to keep going.',
      ),
      findsNothing,
    );
    expect(find.widgetWithText(PrimaryButton, 'Done'), findsOneWidget);
    expect(
      find.widgetWithText(SecondaryButton, 'Optional Practice'),
      findsOneWidget,
    );
    expect(find.widgetWithText(PrimaryButton, 'Continue'), findsNothing);

    await tester.tap(find.text('Optional Practice'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(find.text('Open'), findsOneWidget);
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

    expect(find.text('0m 12s today'), findsOneWidget);
    expect(find.text('Nice work!'), findsOneWidget);
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

    expect(find.text("You're done for today!"), findsOneWidget);
    expect(find.text('Nice work!'), findsNothing);
    expect(find.text('0m 00s today'), findsOneWidget);
    expect(find.text('Nothing to review this time.'), findsOneWidget);
    expect(find.text('A little progress goes a long way.'), findsNothing);
    expect(find.text('0'), findsNWidgets(3));
    expect(find.text('kanji reviewed'), findsOneWidget);
    expect(find.text('No reviews to revisit.'), findsOneWidget);
    expect(find.text('All caught up.'), findsNothing);
    expect(find.textContaining('Next review'), findsNothing);
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
                        builder: (_) => SessionCompleteScreen(summary: summary),
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

    expect(find.text("You're done for today!"), findsNothing);
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
      ),
    );

    expect(find.text("You're done for today!"), findsOneWidget);
    expect(find.text('Nice work!'), findsOneWidget);
    expect(find.text('Need another look'), findsOneWidget);
    expect(find.text('All caught up.'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

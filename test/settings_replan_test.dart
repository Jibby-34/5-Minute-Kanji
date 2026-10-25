import 'package:fiveminutekanji/app.dart';
import 'package:fiveminutekanji/core/models/daily_session_plan.dart';
import 'package:fiveminutekanji/data/hardcoded_kanji_repository.dart';
import 'package:fiveminutekanji/data/shared_prefs_progress_repository.dart';
import 'package:fiveminutekanji/features/settings/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  test('replan clears the stored queue and leaves learned cards alone', () async {
    final progress = MemoryProgressRepository(
      dailySessionPlan: DailySessionPlan(
        studyDate: DateTime(2026, 10, 25),
        budgetMinutes: 5,
        newKanjiPerDay: 5,
        cardIds: const ['kept-until-cleared'],
        completed: true,
      ),
    );
    final controller = SettingsController(progressRepository: progress);

    await controller.replanToday();

    expect(progress.dailySessionPlan.studyDate, isNull);
    expect(progress.dailySessionPlan.cardIds, isEmpty);
    expect(progress.dailySessionPlan.completed, isFalse);
    expect(controller.replanDone, isTrue);
    expect(progress.schedules, isEmpty);
  });

  testWidgets('the settings button clears today\'s queue until Home rebuilds it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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

    final before = await progress.getDailySessionPlan();
    expect(before.cardIds, isNotEmpty);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Replan today\'s cards'), 400);
    expect(
      find.textContaining('app updates and changes in the kanji data'),
      findsOneWidget,
    );

    await tester.tap(find.text('Replan today\'s cards'));
    await tester.pumpAndSettle();

    final cleared = await progress.getDailySessionPlan();
    expect(cleared.studyDate, isNull);
    expect(cleared.cardIds, isEmpty);
    expect(find.text('Today\'s cards will be chosen again.'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    final rebuilt = await progress.getDailySessionPlan();
    expect(rebuilt.studyDate, before.studyDate);
    expect(rebuilt.cardIds, isNotEmpty);
    expect(rebuilt.completed, isFalse);
  });
}

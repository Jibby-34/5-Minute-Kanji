import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fiveminutekanji/app.dart';
import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/progress.dart';
import 'package:fiveminutekanji/core/models/study_allocation.dart';
import 'package:fiveminutekanji/core/models/study_day_type.dart';
import 'package:fiveminutekanji/core/theme/app_colors.dart';
import 'package:fiveminutekanji/core/theme/app_theme.dart';
import 'package:fiveminutekanji/core/utils/time_format.dart';
import 'package:fiveminutekanji/data/hardcoded_kanji_repository.dart';
import 'package:fiveminutekanji/data/shared_prefs_progress_repository.dart';
import 'package:fiveminutekanji/features/home/home_controller.dart';
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
    final semantics = tester.ensureSemantics();
    try {
      await pumpHome(tester);

      final plan = Provider.of<HomeController>(
        tester.element(find.byType(HomeScreen)),
        listen: false,
      ).studyAllocation;

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(greeting(), findsOneWidget);
      expect(find.text('STUDY PLAN'), findsOneWidget);
      expect(find.text('DAY TYPE'), findsOneWidget);
      expect(find.text('Normal Day'), findsOneWidget);
      expect(find.text(StudyDayType.reinforcementNote), findsNothing);
      expect(find.text('study items today'), findsNothing);
      expect(find.text('10'), findsNothing);
      expect(find.text('~5 min'), findsNothing);
      expect(plan.newCards, 5);
      expect(plan.reviewCards, 0);
      expect(plan.newSeconds, greaterThan(0));
      expect(plan.reviewSeconds, 0);
      expect(
        find.text(formatPlanDuration(plan.totalSeconds)),
        findsNWidgets(2),
      );
      expect(find.text('5 cards'), findsOneWidget);
      expect(find.text('0 cards'), findsOneWidget);
      expect(find.text('Reviews'), findsOneWidget);
      expect(find.text('New kanji'), findsOneWidget);
      expect(find.text('Due for review'), findsNothing);
      expect(find.text('Ready to learn'), findsNothing);
      expect(find.text('Free kanji learned'), findsOneWidget);
      expect(find.text('0 / 50'), findsOneWidget);
      expect(find.text('Start Review'), findsOneWidget);
      expect(find.text('days studied'), findsOneWidget);
      expect(find.textContaining('Next review:'), findsNothing);
      expect(find.byTooltip('Settings'), findsOneWidget);
      expect(find.byTooltip('Kanji list'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Estimated time split. Reviews 0 minutes. '
          'New kanji ${formatPlanDurationSpoken(plan.newSeconds)}.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      final fresh = barSegments(tester, const Color(0xFF8E96C4));
      expect(fresh, hasLength(1));
      expect(barSegments(tester, AppColors.indigo), isEmpty);
      expect(fresh.single.size.width, greaterThan(200));

      final total = tester.getCenter(find.text('STUDY PLAN'));
      final dayType = tester.getCenter(find.text('DAY TYPE'));
      final start = tester.getCenter(find.text('Start Review'));
      final streak = tester.getCenter(find.text('days studied'));
      final hello = tester.getCenter(greeting());
      expect(streak.dy, lessThan(hello.dy));
      expect(hello.dy, lessThan(dayType.dy));
      expect(dayType.dy, lessThan(total.dy));
      expect(total.dy, lessThan(start.dy));
    } finally {
      semantics.dispose();
    }
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
      expect(find.text('STUDY PLAN'), findsOneWidget);
      expect(find.text('New kanji'), findsOneWidget);
      expect(
        tester.getCenter(find.text('STUDY PLAN')).dy,
        lessThan(tester.getCenter(find.text('Start Review')).dy),
        reason:
            'plan should sit above the button on ${size.width}x${size.height}',
      );
    }
  });

  testWidgets('home layout holds together at a larger text scale', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(375, 667), textScale: 1.3);

    expect(tester.takeException(), isNull);
    expect(greeting(), findsOneWidget);
    expect(find.text('STUDY PLAN'), findsOneWidget);
    expect(find.text('New kanji'), findsOneWidget);
    expect(find.text('Start Review'), findsOneWidget);
  });

  testWidgets('the bar matches review time and new-kanji time', (tester) async {
    final now = DateTime(2026, 10, 26, 9);
    final reviews = [testCard('r1'), testCard('r2'), testCard('r3')];
    final news = [testCard('n1'), testCard('n2')];
    final controller = HomeController(
      kanjiRepository: FakeKanjiRepository([...reviews, ...news]),
      progressRepository: MemoryProgressRepository(
        settings: const AppSettings(dailyStudyMinutes: 5, newKanjiPerDay: 2),
        schedules: {
          for (final card in reviews) card.id: dueReview(card.id, now),
        },
      ),
      clock: () => now,
    );
    await controller.load();
    await pumpController(tester, controller);

    final plan = controller.studyAllocation;
    expect(plan.reviewCards, 3);
    expect(plan.newCards, 2);
    expect(plan.reviewSeconds, lessThan(plan.newSeconds));
    expect(find.text(_shownTotal(plan)), findsOneWidget);
    expect(find.text(_shown(plan.reviewSeconds)), findsOneWidget);
    expect(find.text(_shown(plan.newSeconds)), findsOneWidget);
    expect(
      _shownTotal(plan),
      formatPlanDuration(
        roundPlanSeconds(plan.reviewSeconds) +
            roundPlanSeconds(plan.newSeconds),
      ),
    );
    expect(find.text('3 cards'), findsOneWidget);
    expect(find.text('2 cards'), findsOneWidget);
    expect(find.text('Normal Day'), findsOneWidget);
    expect(find.text(StudyDayType.reinforcementNote), findsNothing);
    expect(find.text('Start Review'), findsOneWidget);

    final reviewBar = barSegments(tester, AppColors.indigo);
    final freshBar = barSegments(tester, const Color(0xFF8E96C4));
    expect(reviewBar, hasLength(1));
    expect(freshBar, hasLength(1));
    expect(
      reviewBar.single.size.width / freshBar.single.size.width,
      closeTo(plan.reviewSeconds / plan.newSeconds, 0.02),
    );
    final reviewRight = reviewBar.single
        .localToGlobal(Offset(reviewBar.single.size.width, 0))
        .dx;
    final freshLeft = freshBar.single.localToGlobal(Offset.zero).dx;
    expect(freshLeft - reviewRight, closeTo(3, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reviews only fill the bar', (tester) async {
    final now = DateTime(2026, 10, 26, 9);
    final reviews = [testCard('r1'), testCard('r2'), testCard('r3')];
    final controller = HomeController(
      kanjiRepository: FakeKanjiRepository(reviews),
      progressRepository: MemoryProgressRepository(
        settings: const AppSettings(newKanjiPerDay: 0),
        schedules: {
          for (final card in reviews) card.id: dueReview(card.id, now),
        },
      ),
      clock: () => now,
    );
    await controller.load();
    await pumpController(tester, controller, size: const Size(320, 568));

    final plan = controller.studyAllocation;
    expect(plan.reviewCards, 3);
    expect(plan.newCards, 0);
    expect(find.text('3 cards'), findsOneWidget);
    expect(find.text('0 cards'), findsOneWidget);
    expect(find.text('Normal Day'), findsOneWidget);
    expect(find.text(StudyDayType.reinforcementNote), findsNothing);
    expect(find.text(_shownTotal(plan)), findsNWidgets(2));
    expect(find.text('0 min'), findsOneWidget);
    expect(barSegments(tester, AppColors.indigo), hasLength(1));
    expect(barSegments(tester, const Color(0xFF8E96C4)), isEmpty);
    expect(tester.getSize(find.byType(HomeScreen)).width, 320);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new kanji only fill the bar', (tester) async {
    final now = DateTime(2026, 10, 26, 9);
    final news = [testCard('n1'), testCard('n2')];
    final controller = HomeController(
      kanjiRepository: FakeKanjiRepository(news),
      progressRepository: MemoryProgressRepository(
        settings: const AppSettings(newKanjiPerDay: 2),
      ),
      clock: () => now,
    );
    await controller.load();
    await pumpController(tester, controller);

    final plan = controller.studyAllocation;
    expect(plan.reviewCards, 0);
    expect(plan.newCards, 2);
    expect(barSegments(tester, AppColors.indigo), isEmpty);
    expect(barSegments(tester, const Color(0xFF8E96C4)), hasLength(1));
    expect(find.text('2 cards'), findsOneWidget);
    expect(find.text(_shown(plan.newSeconds)), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('nothing due shows a calm empty state', (tester) async {
    final now = DateTime(2026, 10, 26, 9);
    final cards = [testCard('r1')];
    final controller = HomeController(
      kanjiRepository: FakeKanjiRepository(cards),
      progressRepository: MemoryProgressRepository(
        settings: const AppSettings(newKanjiPerDay: 0),
        schedules: {
          'r1': dueReview(
            'r1',
            now,
          ).copyWith(dueAt: now.add(const Duration(days: 3))),
        },
      ),
      clock: () => now,
    );
    await controller.load();
    await pumpController(tester, controller);

    expect(find.text("You're all caught up."), findsOneWidget);
    expect(find.text('STUDY PLAN'), findsNothing);
    expect(find.text('Start Review'), findsNothing);
    expect(find.textContaining('Next review:'), findsOneWidget);
    expect(find.textContaining('NaN'), findsNothing);
    expect(barSegments(tester, AppColors.indigo), isEmpty);
    expect(barSegments(tester, const Color(0xFF8E96C4)), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tiny share stays visible without changing the times', (
    tester,
  ) async {
    final controller = HomeController(
      kanjiRepository: FakeKanjiRepository(const []),
      progressRepository: MemoryProgressRepository(),
    );
    controller.loading = false;
    controller.recommendedCount = 21;
    controller.studyAllocation = const StudyAllocation(
      reviewCards: 1,
      reviewSeconds: 13,
      newCards: 20,
      newSeconds: 1040,
    );
    await pumpController(tester, controller, size: const Size(320, 640));

    expect(find.text('10 sec'), findsOneWidget);
    expect(find.text('17 min 20 sec'), findsOneWidget);
    expect(find.text('17 min 30 sec'), findsOneWidget);
    expect(find.text('13 sec'), findsNothing);
    expect(find.text('17 min 33 sec'), findsNothing);
    expect(find.text('1 card'), findsOneWidget);
    expect(find.text('20 cards'), findsOneWidget);

    final reviewBar = barSegments(tester, AppColors.indigo);
    final freshBar = barSegments(tester, const Color(0xFF8E96C4));
    expect(reviewBar, hasLength(1));
    expect(freshBar, hasLength(1));
    expect(reviewBar.single.size.width, greaterThanOrEqualTo(8));
    expect(
      reviewBar.single.size.width / freshBar.single.size.width,
      greaterThan(13 / 1040),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a missing estimate does not invent a proportion', (
    tester,
  ) async {
    final controller = HomeController(
      kanjiRepository: FakeKanjiRepository(const []),
      progressRepository: MemoryProgressRepository(),
    );
    controller.loading = false;
    controller.recommendedCount = 3;
    controller.studyAllocation = const StudyAllocation(
      reviewCards: 4,
      reviewSeconds: 0,
      newCards: 1,
      newSeconds: 52,
    );
    await pumpController(tester, controller);

    expect(find.text('\u2014'), findsNWidgets(2));
    expect(find.text('4 cards'), findsOneWidget);
    expect(find.text('1 card'), findsOneWidget);
    expect(find.text('50 sec'), findsOneWidget);
    expect(find.textContaining('NaN'), findsNothing);
    expect(find.textContaining('null'), findsNothing);
    expect(barSegments(tester, AppColors.indigo), isEmpty);
    expect(barSegments(tester, const Color(0xFF8E96C4)), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a reinforcement day shows reviews only', (tester) async {
    final now = DateTime(2026, 10, 26, 9);
    final reviews = [for (var i = 0; i < 8; i++) testCard('r$i')];
    final news = [testCard('n1'), testCard('n2')];
    final progress = MemoryProgressRepository(
      settings: const AppSettings(dailyStudyMinutes: 5, newKanjiPerDay: 5),
      schedules: {
        for (final card in reviews)
          card.id: dueReview(card.id, now).copyWith(
            interval: const Duration(days: 10),
            lastReviewedAt: now.subtract(const Duration(days: 17)),
          ),
      },
    );
    final controller = HomeController(
      kanjiRepository: FakeKanjiRepository([...reviews, ...news]),
      progressRepository: progress,
      clock: () => now,
    );
    await controller.load();
    await pumpController(tester, controller);

    final plan = controller.studyAllocation;
    expect(controller.studyDayType, StudyDayType.reinforcement);
    expect(progress.dailySessionPlan.dayType, StudyDayType.reinforcement);
    expect(plan.newCards, 0);
    expect(plan.reviewCards, 8);
    expect(plan.newSeconds, 0);
    expect(find.text('DAY TYPE'), findsOneWidget);
    expect(find.text('Reinforcement Day'), findsOneWidget);
    expect(find.text('Normal Day'), findsNothing);
    expect(find.text(StudyDayType.reinforcementNote), findsOneWidget);
    expect(find.text('0 cards'), findsOneWidget);
    expect(find.text('8 cards'), findsOneWidget);
    expect(find.text('New kanji'), findsOneWidget);
    expect(find.text('Reviews'), findsOneWidget);
    expect(find.text('Start Review'), findsOneWidget);
    expect(find.text(_shownTotal(plan)), findsNWidgets(2));
    expect(find.text('0 min'), findsOneWidget);
    expect(barSegments(tester, AppColors.indigo), hasLength(1));
    expect(barSegments(tester, const Color(0xFF8E96C4)), isEmpty);
    expect(
      tester.getTopLeft(find.text('DAY TYPE')).dy,
      lessThan(tester.getTopLeft(find.text('STUDY PLAN')).dy),
    );
    expect(tester.takeException(), isNull);
  });
}

String _shown(int seconds) => formatPlanDuration(seconds);

String _shownTotal(StudyAllocation plan) {
  return formatPlanDuration(
    roundPlanSeconds(plan.reviewSeconds) + roundPlanSeconds(plan.newSeconds),
  );
}

List<RenderBox> barSegments(WidgetTester tester, Color color) {
  return tester
      .renderObjectList<RenderBox>(
        find.byWidgetPredicate((widget) {
          if (widget is! DecoratedBox) return false;
          final decoration = widget.decoration;
          return decoration is BoxDecoration && decoration.color == color;
        }),
      )
      .where((box) => (box.size.height - 12).abs() < 0.1)
      .toList();
}

CardSchedule dueReview(String id, DateTime now) {
  return CardSchedule(
    cardId: id,
    state: CardLearningState.review,
    reviewCount: 1,
    correctCount: 1,
    incorrectCount: 0,
    dueAt: now,
    interval: const Duration(days: 1),
    ease: 2.5,
    lastReviewedAt: now.subtract(const Duration(days: 1)),
    consecutiveGoodCount: 1,
  );
}

Future<void> pumpController(
  WidgetTester tester,
  HomeController controller, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ChangeNotifierProvider<HomeController>.value(
      value: controller,
      child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
    ),
  );
  await tester.pump();
}

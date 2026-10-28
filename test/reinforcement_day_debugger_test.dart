import 'dart:convert';

import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/daily_session_plan.dart';
import 'package:fiveminutekanji/core/models/progress.dart';
import 'package:fiveminutekanji/core/models/review.dart';
import 'package:fiveminutekanji/core/models/study_allocation.dart';
import 'package:fiveminutekanji/core/models/study_day_type.dart';
import 'package:fiveminutekanji/core/theme/app_theme.dart';
import 'package:fiveminutekanji/features/home/home_controller.dart';
import 'package:fiveminutekanji/features/settings/reinforcement_day_debugger_controller.dart';
import 'package:fiveminutekanji/features/settings/reinforcement_day_debugger_screen.dart';
import 'package:fiveminutekanji/features/settings/settings_screen.dart';
import 'package:fiveminutekanji/repositories/kanji_repository.dart';
import 'package:fiveminutekanji/repositories/progress_repository.dart';
import 'package:fiveminutekanji/services/curriculum/curriculum_access.dart';
import 'package:fiveminutekanji/services/curriculum/curriculum_billing.dart';
import 'package:fiveminutekanji/services/curriculum/curriculum_repository.dart';
import 'package:fiveminutekanji/services/daily_workload.dart';
import 'package:fiveminutekanji/services/reinforcement_day.dart';
import 'package:fiveminutekanji/services/reinforcement_day_scenarios.dart';
import 'package:fiveminutekanji/services/reminder_scheduler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  const policy = ReinforcementDayPolicy();

  group('synthetic scenarios', () {
    final cases = {
      ReinforcementDiagnosticSource.healthy: StudyDayType.normal,
      ReinforcementDiagnosticSource.lowAverage: StudyDayType.normal,
      ReinforcementDiagnosticSource.fragileTail: StudyDayType.normal,
      ReinforcementDiagnosticSource.borderline: StudyDayType.normal,
      ReinforcementDiagnosticSource.smallQueue: StudyDayType.normal,
      ReinforcementDiagnosticSource.empty: StudyDayType.normal,
    };

    for (final entry in cases.entries) {
      test('${entry.key.label} matches the production decision', () {
        final values = entry.key.probabilities;
        final diagnosis = policy.diagnose(values);

        expect(diagnosis.dayType, entry.value);
        expect(policy.dayTypeFor(values), diagnosis.dayType);
      });
    }

    test('a healthy queue stays a Normal Day', () {
      final diagnosis = policy.diagnose(
        ReinforcementDiagnosticSource.healthy.probabilities,
      );

      expect(diagnosis.eligibleCount, 20);
      expect(diagnosis.usableCount, 20);
      expect(diagnosis.average, closeTo(0.85, 1e-9));
      expect(diagnosis.lowCount, 0);
      expect(diagnosis.lowFraction, 0);
      expect(diagnosis.minimumMet, isTrue);
      expect(diagnosis.reasons, isEmpty);
      expect(diagnosis.dayType, StudyDayType.normal);
    });

    test('a 0.65 queue stays Normal under the production average', () {
      final diagnosis = policy.diagnose(
        ReinforcementDiagnosticSource.lowAverage.probabilities,
      );

      expect(diagnosis.average, closeTo(0.65, 1e-9));
      expect(diagnosis.lowCount, 0);
      expect(diagnosis.reasons, isEmpty);
      expect(diagnosis.dayType, StudyDayType.normal);
    });

    test('a fragile tail stays Normal when 0.30 is above the low line', () {
      final diagnosis = policy.diagnose(
        ReinforcementDiagnosticSource.fragileTail.probabilities,
      );

      expect(diagnosis.lowCount, 0);
      expect(diagnosis.lowFraction, 0);
      expect(diagnosis.average, greaterThan(0.40));
      expect(diagnosis.reasons, isEmpty);
      expect(diagnosis.dayType, StudyDayType.normal);
    });

    test('a borderline queue stays Normal under the production thresholds', () {
      final diagnosis = policy.diagnose(
        ReinforcementDiagnosticSource.borderline.probabilities,
      );

      expect(diagnosis.average, greaterThan(0.40));
      expect(diagnosis.lowCount, 0);
      expect(diagnosis.reasons, isEmpty);
      expect(diagnosis.dayType, StudyDayType.normal);
    });

    test('a small queue stays Normal', () {
      final diagnosis = policy.diagnose(
        ReinforcementDiagnosticSource.smallQueue.probabilities,
      );

      expect(diagnosis.eligibleCount, 5);
      expect(diagnosis.average, closeTo(0.20, 1e-9));
      expect(diagnosis.lowCount, 0);
      expect(diagnosis.minimumMet, isFalse);
      expect(diagnosis.reasons, isEmpty);
      expect(diagnosis.dayType, StudyDayType.normal);
      expect(
        diagnosis.minimumLabel(policy.config.minimumDueCards),
        'Short of 8 (5 eligible)',
      );
    });

    test('an empty queue does not divide', () {
      final diagnosis = policy.diagnose(
        ReinforcementDiagnosticSource.empty.probabilities,
      );

      expect(diagnosis.eligibleCount, 0);
      expect(diagnosis.usableCount, 0);
      expect(diagnosis.average, isNull);
      expect(diagnosis.lowFraction, isNull);
      expect(diagnosis.lowCount, 0);
      expect(diagnosis.averageLabel, '—');
      expect(diagnosis.lowShareLabel, '0 (—)');
      expect(diagnosis.dayType, StudyDayType.normal);
      expect(
        diagnosis.triggerLabel(policy.config),
        'None. The queue is empty.',
      );
    });
  });

  group('threshold changes', () {
    test('raising the average threshold turns a healthy queue', () {
      final diagnosis = ReinforcementDayPolicy(
        config: const ReinforcementDayConfig(averageRecallThreshold: 0.90),
      ).diagnose(ReinforcementDiagnosticSource.healthy.probabilities);

      expect(diagnosis.dayType, StudyDayType.reinforcement);
      expect(diagnosis.reasons, [ReinforcementTriggerReason.averageRecall]);
    });

    test('a higher minimum keeps a low average on a Normal Day', () {
      final diagnosis = ReinforcementDayPolicy(
        config: const ReinforcementDayConfig(minimumDueCards: 21),
      ).diagnose(ReinforcementDiagnosticSource.lowAverage.probabilities);

      expect(diagnosis.minimumMet, isFalse);
      expect(diagnosis.dayType, StudyDayType.normal);
      expect(diagnosis.reasons, isEmpty);
    });

    test('lowering the average threshold lets a low average stay Normal', () {
      final diagnosis = ReinforcementDayPolicy(
        config: const ReinforcementDayConfig(averageRecallThreshold: 0.60),
      ).diagnose(ReinforcementDiagnosticSource.lowAverage.probabilities);

      expect(diagnosis.average, greaterThan(0.60));
      expect(diagnosis.lowCount, 0);
      expect(diagnosis.dayType, StudyDayType.normal);
    });

    test('the fragile tail can fire from the fraction alone', () {
      final diagnosis = ReinforcementDayPolicy(
        config: const ReinforcementDayConfig(
          averageRecallThreshold: 0.50,
          lowRecallThreshold: 0.35,
        ),
      ).diagnose(ReinforcementDiagnosticSource.fragileTail.probabilities);

      expect(diagnosis.reasons, [ReinforcementTriggerReason.lowRecallFraction]);
      expect(diagnosis.dayType, StudyDayType.reinforcement);
    });

    test('loosening both thresholds keeps the borderline queue Normal', () {
      final diagnosis = ReinforcementDayPolicy(
        config: const ReinforcementDayConfig(
          averageRecallThreshold: 0.60,
          lowRecallFractionThreshold: 0.26,
        ),
      ).diagnose(ReinforcementDiagnosticSource.borderline.probabilities);

      expect(diagnosis.dayType, StudyDayType.normal);
      expect(diagnosis.reasons, isEmpty);
    });
  });

  group('boundaries', () {
    test('an average equal to the threshold stays Normal', () {
      final diagnosis = policy.diagnose(List<double>.filled(8, 0.40));

      expect(diagnosis.average, closeTo(0.40, 1e-9));
      expect(diagnosis.dayType, StudyDayType.normal);
      expect(diagnosis.reasons, isEmpty);
    });

    test('an average just under the threshold is Reinforcement Day', () {
      final diagnosis = policy.diagnose(List<double>.filled(8, 0.39));

      expect(diagnosis.reasons, [ReinforcementTriggerReason.averageRecall]);
    });

    test('recall equal to the low threshold is not a low card', () {
      final diagnosis = policy.diagnose([
        ...List<double>.filled(6, 1),
        ...List<double>.filled(2, 0.20),
      ]);

      expect(diagnosis.lowCount, 0);
      expect(diagnosis.dayType, StudyDayType.normal);
    });

    test('two cards just under the low threshold are exactly a quarter', () {
      final diagnosis = policy.diagnose([
        ...List<double>.filled(6, 1),
        ...List<double>.filled(2, 0.199),
      ]);

      expect(diagnosis.lowFraction, closeTo(0.25, 1e-9));
      expect(diagnosis.reasons, [ReinforcementTriggerReason.lowRecallFraction]);
    });

    test('one low card in eight stays under the fraction', () {
      final diagnosis = policy.diagnose([...List<double>.filled(7, 1), 0]);

      expect(diagnosis.lowFraction, closeTo(0.125, 1e-9));
      expect(diagnosis.dayType, StudyDayType.normal);
    });

    test('seven due cards stay Normal and eight do not', () {
      expect(
        policy.diagnose(List<double>.filled(7, 0)).dayType,
        StudyDayType.normal,
      );
      final eight = policy.diagnose(List<double>.filled(8, 0));
      expect(eight.dayType, StudyDayType.reinforcement);
      expect(eight.reasons, [
        ReinforcementTriggerReason.averageRecall,
        ReinforcementTriggerReason.lowRecallFraction,
      ]);
    });
  });

  group('invalid values', () {
    test('parsers reject empty, out of range, and non-numeric text', () {
      expect(ReinforcementDayConfig.tryParseMinimum(''), isNull);
      expect(ReinforcementDayConfig.tryParseMinimum('-1'), isNull);
      expect(ReinforcementDayConfig.tryParseMinimum('8.5'), isNull);
      expect(ReinforcementDayConfig.tryParseMinimum('1000'), isNull);
      expect(ReinforcementDayConfig.tryParseMinimum('0'), 0);
      expect(ReinforcementDayConfig.tryParseMinimum('999'), 999);

      expect(ReinforcementDayConfig.tryParseUnit(''), isNull);
      expect(ReinforcementDayConfig.tryParseUnit('1.2'), isNull);
      expect(ReinforcementDayConfig.tryParseUnit('-0.01'), isNull);
      expect(ReinforcementDayConfig.tryParseUnit('nan'), isNull);
      expect(ReinforcementDayConfig.tryParseUnit('infinity'), isNull);
      expect(ReinforcementDayConfig.tryParseUnit('0'), 0);
      expect(ReinforcementDayConfig.tryParseUnit('1'), 1);
      expect(ReinforcementDayConfig.tryParseUnit('0.70'), closeTo(0.70, 1e-12));
    });

    test('unusable estimates are left out and do not count as zero', () {
      final diagnosis = policy.diagnose([
        ...List<double>.filled(6, 0.1),
        double.nan,
        double.infinity,
        -1,
        1.1,
      ]);

      expect(diagnosis.eligibleCount, 10);
      expect(diagnosis.usableCount, 6);
      expect(diagnosis.excludedCount, 4);
      expect(diagnosis.minimumMet, isFalse);
      expect(diagnosis.dayType, StudyDayType.normal);
    });

    test('eight usable low estimates still trigger around invalid ones', () {
      final diagnosis = policy.diagnose([
        ...List<double>.filled(8, 0.1),
        double.nan,
      ]);

      expect(diagnosis.usableCount, 8);
      expect(diagnosis.excludedCount, 1);
      expect(diagnosis.dayType, StudyDayType.reinforcement);
    });

    test('a queue of only invalid estimates stays Normal', () {
      final diagnosis = policy.diagnose([
        double.nan,
        double.negativeInfinity,
        -0.1,
        2,
      ]);

      expect(diagnosis.usableCount, 0);
      expect(diagnosis.average, isNull);
      expect(diagnosis.dayType, StudyDayType.normal);
    });

    test('a minimum of zero still does not divide an empty queue', () {
      final diagnosis = const ReinforcementDayPolicy(
        config: ReinforcementDayConfig(minimumDueCards: 0),
      ).diagnose(const <double>[]);

      expect(diagnosis.average, isNull);
      expect(diagnosis.dayType, StudyDayType.normal);
    });
  });

  group('stored progress', () {
    final now = DateTime(2026, 10, 26, 12);

    test('tuning and scenarios leave the saved study data alone', () async {
      final harness = _Harness(now);
      final controller = harness.controller;
      final before = harness.snapshot();

      await controller.reevaluate();
      expect(controller.diagnosis.eligibleCount, 8);
      expect(controller.diagnosis.dayType, StudyDayType.reinforcement);

      controller.selectSource(ReinforcementDiagnosticSource.healthy);
      expect(controller.diagnosis.dayType, StudyDayType.normal);
      controller.selectSource(ReinforcementDiagnosticSource.empty);
      controller.selectSource(ReinforcementDiagnosticSource.fragileTail);
      expect(controller.applyMinimum('100'), isTrue);
      expect(controller.applyAverage('0.10'), isTrue);
      expect(controller.applyLow('0.20'), isTrue);
      expect(controller.applyFraction('0.90'), isTrue);
      expect(controller.applyAverage('nope'), isFalse);
      expect(
        controller.diagnostic.averageRecallThreshold,
        closeTo(0.10, 1e-12),
      );
      controller.selectPreview(DayTypePreview.forceReinforcement);
      controller.returnToAutomatic();
      controller.resetThresholds();
      await controller.reevaluate();

      expect(harness.snapshot(), before);
      expect(controller.workload.dayPolicy.config.minimumDueCards, 8);
      expect(controller.workload.dayPolicy.config.averageRecallThreshold, 0.40);
      expect(controller.workload.dayPolicy.config.lowRecallThreshold, 0.20);
      expect(harness.curriculum.record.studiedIds, {'kept'});
      expect(harness.curriculum.record.backfillCompleted, isFalse);
      expect(harness.access.studiedCount, 0);
    });

    test(
      'rebuild uses production thresholds and leaves schedules alone',
      () async {
        final harness = _Harness(now);
        final controller = harness.controller;
        final before = harness.snapshot();

        expect(controller.applyMinimum('100'), isTrue);
        await controller.reevaluate();
        expect(controller.diagnosis.dayType, StudyDayType.normal);
        expect(harness.snapshot(), before);

        await controller.rebuildSavedPlan();

        expect(
          harness.progress.dailySessionPlan.dayType,
          StudyDayType.reinforcement,
        );
        expect(
          harness.progress.dailySessionPlan.cardIds,
          isNot(contains('sentinel')),
        );
        expect(controller.diagnostic.minimumDueCards, 100);
        expect(controller.diagnosis.dayType, StudyDayType.normal);
        expect(harness.progress.settings.toJson(), before.settings);
        expect(harness.schedulesJson(), before.schedules);
        expect(harness.progress.dailyNewKanji.toJson(), before.newKanji);
        expect(harness.progress.history, hasLength(1));
        expect(harness.curriculum.record.studiedIds, {'kept'});
        expect(harness.curriculum.record.backfillCompleted, isFalse);
      },
    );
  });

  group('preview allocation', () {
    const sitting = StudyAllocation(
      reviewCards: 4,
      reviewSeconds: 120,
      newCards: 2,
      newSeconds: 60,
    );

    test('automatic and forced Normal keep the sitting', () {
      expect(
        allocationForPreview(sitting: sitting, dayType: StudyDayType.normal),
        isA<StudyAllocation>()
            .having((plan) => plan.newCards, 'newCards', 2)
            .having((plan) => plan.reviewCards, 'reviewCards', 4),
      );
    });

    test('a Reinforcement preview drops new kanji from the sitting', () {
      final preview = allocationForPreview(
        sitting: sitting,
        dayType: StudyDayType.reinforcement,
      );

      expect(preview.reviewCards, 4);
      expect(preview.reviewSeconds, 120);
      expect(preview.newCards, 0);
      expect(preview.newSeconds, 0);
    });
  });

  group('debugger screen', () {
    testWidgets('settings opens the debugger in a debug build', (tester) async {
      final harness = _Harness(DateTime(2026, 10, 26, 12));
      await _pumpSettings(tester, harness);
      await tester.scrollUntilVisible(
        find.text('Reinforcement Day Debugger'),
        400,
        scrollable: _verticalScroll,
      );
      await tester.tap(find.text('Reinforcement Day Debugger'));
      await tester.pumpAndSettle();

      expect(find.text('Saved plan: Normal Day'), findsOneWidget);
      expect(find.text('1 card in the saved queue.'), findsOneWidget);
      await _scrollTo(tester, find.text('Reevaluate diagnostic prediction'));
      expect(find.text('Reevaluate diagnostic prediction'), findsOneWidget);
    });

    testWidgets('scenarios, thresholds, and preview stay off the saved plan', (
      tester,
    ) async {
      final harness = _Harness(DateTime(2026, 10, 26, 12));
      await _pumpDebugger(tester, harness);
      final before = harness.snapshot();
      harness.home.studyAllocation = const StudyAllocation(
        reviewCards: 4,
        reviewSeconds: 120,
        newCards: 2,
        newSeconds: 60,
      );
      harness.home.trialProgressLabel = '2 / 50 free kanji learned';
      harness.home.notifyListeners();
      await tester.pump();

      await _chooseSource(tester, 'Low average');
      expect(
        find.text('Simulation. These probabilities are sample data.'),
        findsOneWidget,
      );
      expect(find.text('Predicted: Normal Day'), findsOneWidget);
      expect(find.text('Eligible due cards: 20'), findsOneWidget);

      await _reveal(tester, find.byKey(const Key('debug-average')));
      await tester.enterText(find.byKey(const Key('debug-average')), '0.90');
      await tester.pump();
      expect(find.text('Predicted: Reinforcement Day'), findsOneWidget);
      await _scrollTo(tester, find.text('STUDY PLAN'));
      expect(find.text('0 cards'), findsOneWidget);
      expect(find.text('4 cards'), findsOneWidget);
      expect(
        find.text('Today is about strengthening what you know.'),
        findsOneWidget,
      );

      await _reveal(tester, find.byKey(const Key('debug-average')));
      await tester.enterText(find.byKey(const Key('debug-average')), '2');
      await tester.pump();
      expect(find.text('Enter a value from 0 to 1.'), findsOneWidget);
      expect(find.text('Predicted: Reinforcement Day'), findsOneWidget);

      await _reveal(tester, find.byKey(const Key('debug-minimum')));
      await tester.enterText(find.byKey(const Key('debug-minimum')), '100');
      await tester.pump();
      await _reveal(tester, find.text('Predicted: Normal Day'));
      expect(find.text('Predicted: Normal Day'), findsOneWidget);

      await _scrollTo(tester, find.text('STUDY PLAN'));
      expect(find.text('2 cards'), findsOneWidget);
      expect(find.text('3 min'), findsOneWidget);
      expect(
        find.text('Today is about strengthening what you know.'),
        findsNothing,
      );

      await _reveal(tester, find.text('Force Reinforcement'));
      await tester.tap(find.text('Force Reinforcement'));
      await tester.pump();
      await _scrollTo(tester, find.text('STUDY PLAN'));
      expect(find.text('0 cards'), findsOneWidget);
      expect(find.text('4 cards'), findsOneWidget);
      expect(find.text('2 min'), findsNWidgets(2));
      expect(
        find.text('Today is about strengthening what you know.'),
        findsOneWidget,
      );
      expect(find.text('Free kanji learned'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('DAY TYPE')).dy,
        lessThan(tester.getTopLeft(find.text('STUDY PLAN')).dy),
      );

      await _reveal(tester, find.text('Return to automatic'));
      await tester.tap(find.text('Return to automatic'));
      await tester.pump();
      await _scrollTo(tester, find.text('STUDY PLAN'));
      expect(find.text('2 cards'), findsOneWidget);

      await _chooseSource(tester, 'Empty queue');
      await _reveal(tester, find.text('Eligible due cards: 0'));
      expect(find.text('Average recall: —'), findsOneWidget);
      expect(find.text('None. The queue is empty.'), findsOneWidget);

      await _scrollTo(tester, find.text("Rebuild today's saved plan"));
      await tester.tap(find.text("Rebuild today's saved plan"));
      await tester.pumpAndSettle();
      expect(find.text("Rebuild today's saved plan?"), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(harness.snapshot(), before);
      expect(harness.curriculum.record.studiedIds, {'kept'});
    });

    testWidgets('the debugger scrolls on a small phone', (tester) async {
      final harness = _Harness(DateTime(2026, 10, 26, 12));
      await _pumpDebugger(tester, harness, size: const Size(320, 568));
      await _scrollTo(tester, find.text("Rebuild today's saved plan"));
      expect(tester.takeException(), isNull);
    });
  });
}

class _Stored {
  const _Stored({
    required this.plan,
    required this.settings,
    required this.newKanji,
    required this.schedules,
    required this.history,
    required this.studied,
  });

  final Map<String, dynamic> plan;
  final Map<String, dynamic> settings;
  final Map<String, dynamic> newKanji;
  final String schedules;
  final int history;
  final Set<String> studied;

  @override
  bool operator ==(Object other) {
    return other is _Stored &&
        _mapsEqual(plan, other.plan) &&
        _mapsEqual(settings, other.settings) &&
        _mapsEqual(newKanji, other.newKanji) &&
        schedules == other.schedules &&
        history == other.history &&
        studied.length == other.studied.length &&
        studied.containsAll(other.studied);
  }

  @override
  int get hashCode => schedules.hashCode;
}

bool _mapsEqual(Map<String, dynamic> a, Map<String, dynamic> b) {
  return jsonEncode(a) == jsonEncode(b);
}

class _Harness {
  _Harness(this.now) {
    final schedules = <String, CardSchedule>{
      for (var index = 0; index < 8; index++)
        'r$index': _collapsed('r$index', now),
      'n0': CardSchedule.fresh('n0', now),
      'future': CardSchedule(
        cardId: 'future',
        state: CardLearningState.review,
        reviewCount: 2,
        correctCount: 2,
        incorrectCount: 0,
        dueAt: now.add(const Duration(days: 3)),
        interval: const Duration(days: 3),
        ease: 2.5,
        lastReviewedAt: now,
      ),
      'known': CardSchedule(
        cardId: 'known',
        state: CardLearningState.review,
        reviewCount: 0,
        correctCount: 0,
        incorrectCount: 0,
        dueAt: now,
        interval: Duration.zero,
        ease: 2.5,
      ),
    };
    progress = MemoryProgressRepository(
      schedules: schedules,
      settings: const AppSettings(),
      dailyNewKanji: DailyNewKanjiProgress(date: now, count: 2),
      dailySessionPlan: const DailySessionPlan(cardIds: ['sentinel']),
    );
    progress.history.add(
      ReviewHistoryEntry(
        cardId: 'r0',
        rating: ReviewResult.good,
        timestamp: now,
        timeOnCard: const Duration(seconds: 4),
      ),
    );
    kanji = FakeKanjiRepository([
      for (final id in schedules.keys) testCard(id),
    ]);
    curriculum = MemoryCurriculumRepository(
      record: const CurriculumRecord(
        studiedIds: {'kept'},
        backfillCompleted: false,
      ),
    );
    access = CurriculumAccess(
      progressRepository: progress,
      repository: curriculum,
      billing: const UnavailableCurriculumBilling(),
      clock: () => now,
    );
    workload = DailyWorkloadService(
      kanjiRepository: kanji,
      progressRepository: progress,
    );
    controller = ReinforcementDayDebuggerController(
      kanjiRepository: kanji,
      progressRepository: progress,
      workload: workload,
      clock: () => now,
    );
    home = HomeController(
      kanjiRepository: kanji,
      progressRepository: progress,
      clock: () => now,
    );
  }

  final DateTime now;
  late final MemoryProgressRepository progress;
  late final FakeKanjiRepository kanji;
  late final MemoryCurriculumRepository curriculum;
  late final CurriculumAccess access;
  late final DailyWorkloadService workload;
  late final ReinforcementDayDebuggerController controller;
  late final HomeController home;

  String schedulesJson() {
    final entries = progress.schedules.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries
        .map((entry) => '${entry.key}:${entry.value.toJson()}')
        .join('|');
  }

  _Stored snapshot() {
    return _Stored(
      plan: progress.dailySessionPlan.toJson(),
      settings: progress.settings.toJson(),
      newKanji: progress.dailyNewKanji.toJson(),
      schedules: schedulesJson(),
      history: progress.history.length,
      studied: Set<String>.of(curriculum.record.studiedIds),
    );
  }
}

CardSchedule _collapsed(String id, DateTime now) {
  return CardSchedule(
    cardId: id,
    state: CardLearningState.review,
    reviewCount: 6,
    correctCount: 1,
    incorrectCount: 5,
    dueAt: now.subtract(const Duration(days: 13)),
    interval: const Duration(days: 1),
    ease: 1.3,
    lastReviewedAt: now.subtract(const Duration(days: 14)),
  );
}

Future<void> _pumpDebugger(
  WidgetTester tester,
  _Harness harness, {
  Size size = const Size(390, 844),
}) async {
  await _pump(
    tester,
    harness,
    size: size,
    home: const ReinforcementDayDebuggerScreen(),
  );
}

Future<void> _pumpSettings(WidgetTester tester, _Harness harness) async {
  await _pump(tester, harness, home: const SettingsScreen());
}

Future<void> _pump(
  WidgetTester tester,
  _Harness harness, {
  required Widget home,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(harness.home.dispose);
  addTearDown(harness.controller.dispose);
  addTearDown(harness.access.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<KanjiRepository>.value(value: harness.kanji),
        Provider<ProgressRepository>.value(value: harness.progress),
        Provider<ReminderScheduler?>.value(value: null),
        ChangeNotifierProvider<HomeController>.value(value: harness.home),
      ],
      child: MaterialApp(theme: AppTheme.light, home: home),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _verticalScroll {
  return find.byWidgetPredicate(
    (widget) =>
        widget is Scrollable && widget.axisDirection == AxisDirection.down,
  );
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder);
    await tester.pump();
    return;
  }
  final state = tester.state<ScrollableState>(_verticalScroll.last);
  state.position.jumpTo(0);
  await tester.pump();
  await _scrollTo(tester, finder);
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) {
  return tester.scrollUntilVisible(
    finder,
    400,
    scrollable: _verticalScroll.last,
  );
}

Future<void> _chooseSource(WidgetTester tester, String label) async {
  await _reveal(tester, find.byKey(const Key('debug-source')));
  await tester.tap(find.byKey(const Key('debug-source')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/navigation/app_navigator.dart';
import 'core/theme/app_scroll_behavior.dart';
import 'core/theme/app_theme.dart';
import 'data/asset_stroke_data_repository.dart';
import 'features/home/home_controller.dart';
import 'features/onboarding/onboarding_gate.dart';
import 'features/onboarding/onboarding_hint_controller.dart';
import 'features/onboarding/widgets/onboarding_hint_text.dart';
import 'repositories/kanji_repository.dart';
import 'repositories/progress_repository.dart';
import 'repositories/stroke_data_repository.dart';
import 'services/curriculum/curriculum_access.dart';
import 'services/curriculum/curriculum_billing.dart';
import 'services/curriculum/curriculum_repository.dart';
import 'services/mark_as_known.dart';
import 'services/onboarding_service.dart';
import 'services/placement_service.dart';
import 'services/reminder_scheduler.dart';
import 'services/srs_engine.dart';
import 'services/srs_scheduler.dart';

class FiveMinuteKanjiApp extends StatelessWidget {
  const FiveMinuteKanjiApp({
    super.key,
    required this.kanjiRepository,
    required this.progressRepository,
    this.srsEngine = const SrsEngine(),
    this.strokeDataRepository,
    this.reminderScheduler,
    this.curriculumAccess,
  });

  final KanjiRepository kanjiRepository;
  final ProgressRepository progressRepository;
  final SrsScheduler srsEngine;
  final StrokeDataRepository? strokeDataRepository;

  /// Absent in tests and on platforms without local notifications.
  final ReminderScheduler? reminderScheduler;

  /// Store-backed entitlement. Tests omit it and get an offline billing stub.
  final CurriculumAccess? curriculumAccess;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ReminderScheduler?>.value(value: reminderScheduler),
        Provider<KanjiRepository>.value(value: kanjiRepository),
        Provider<ProgressRepository>.value(value: progressRepository),
        Provider<SrsScheduler>.value(value: srsEngine),
        Provider<StrokeDataRepository>(
          create: (_) => strokeDataRepository ?? AssetStrokeDataRepository(),
        ),
        Provider<MarkAsKnownService>(
          create: (_) => MarkAsKnownService(
            progressRepository: progressRepository,
            srsEngine: srsEngine,
          ),
        ),
        Provider<PlacementService>(
          create: (context) => PlacementService(
            kanjiRepository: kanjiRepository,
            progressRepository: progressRepository,
            markAsKnown: context.read<MarkAsKnownService>(),
          ),
        ),
        Provider<OnboardingService>(
          create: (_) =>
              OnboardingService(progressRepository: progressRepository),
        ),
        ChangeNotifierProvider<CurriculumAccess>(
          create: (_) {
            final access =
                curriculumAccess ??
                CurriculumAccess(
                  progressRepository: progressRepository,
                  repository: MemoryCurriculumRepository(),
                  billing: const UnavailableCurriculumBilling(),
                );
            if (!access.isLoaded) unawaited(access.load());
            return access;
          },
        ),
        ChangeNotifierProvider<OnboardingHintController>(
          create: (context) => OnboardingHintController(
            service: context.read<OnboardingService>(),
          )..load(),
        ),
        ChangeNotifierProvider(
          create: (context) => HomeController(
            kanjiRepository: kanjiRepository,
            progressRepository: progressRepository,
            reminderScheduler: reminderScheduler,
            curriculumAccess: context.read<CurriculumAccess>(),
          )..load(),
        ),
      ],
      child: MaterialApp(
        title: '5-Minute Kanji',
        navigatorKey: AppNavigator.key,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.light,
        scrollBehavior: const AppScrollBehavior(),
        builder: (context, child) {
          final overlay =
              Theme.of(context).appBarTheme.systemOverlayStyle ??
              SystemUiOverlayStyle.dark;
          // Above the navigator so first-time hints reach pushed sessions.
          return OnboardingHintScope(
            notifier: context.read<OnboardingHintController>(),
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: overlay,
              child: _EntitlementRefresh(child: child ?? const SizedBox.shrink()),
            ),
          );
        },
        home: const OnboardingGate(),
      ),
    );
  }
}

/// Asks the store for the lifetime unlock and monthly subscription again
/// when the app returns to the foreground. Launch already refreshes once.
class _EntitlementRefresh extends StatefulWidget {
  const _EntitlementRefresh({required this.child});

  final Widget child;

  @override
  State<_EntitlementRefresh> createState() => _EntitlementRefreshState();
}

class _EntitlementRefreshState extends State<_EntitlementRefresh>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(context.read<CurriculumAccess>().refresh());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/navigation/app_navigator.dart';
import 'core/theme/app_scroll_behavior.dart';
import 'core/theme/app_theme.dart';
import 'data/asset_stroke_data_repository.dart';
import 'features/home/home_controller.dart';
import 'features/home/home_screen.dart';
import 'repositories/kanji_repository.dart';
import 'repositories/progress_repository.dart';
import 'repositories/stroke_data_repository.dart';
import 'services/mark_as_known.dart';
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
  });

  final KanjiRepository kanjiRepository;
  final ProgressRepository progressRepository;
  final SrsScheduler srsEngine;
  final StrokeDataRepository? strokeDataRepository;

  /// Absent in tests and on platforms without local notifications.
  final ReminderScheduler? reminderScheduler;

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
        ChangeNotifierProvider(
          create: (context) => HomeController(
            kanjiRepository: kanjiRepository,
            progressRepository: progressRepository,
            reminderScheduler: reminderScheduler,
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
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: overlay,
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const HomeScreen(),
      ),
    );
  }
}

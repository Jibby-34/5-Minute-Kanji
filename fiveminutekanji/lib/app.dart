import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_scroll_behavior.dart';
import 'core/theme/app_theme.dart';
import 'features/home/home_controller.dart';
import 'features/home/home_screen.dart';
import 'repositories/kanji_repository.dart';
import 'repositories/progress_repository.dart';
import 'services/mark_as_known.dart';
import 'services/srs_engine.dart';
import 'services/srs_scheduler.dart';

class FiveMinuteKanjiApp extends StatelessWidget {
  const FiveMinuteKanjiApp({
    super.key,
    required this.kanjiRepository,
    required this.progressRepository,
    this.srsEngine = const SrsEngine(),
  });

  final KanjiRepository kanjiRepository;
  final ProgressRepository progressRepository;
  final SrsScheduler srsEngine;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<KanjiRepository>.value(value: kanjiRepository),
        Provider<ProgressRepository>.value(value: progressRepository),
        Provider<SrsScheduler>.value(value: srsEngine),
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
          )..load(),
        ),
      ],
      child: MaterialApp(
        title: '5-Minute Kanji',
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

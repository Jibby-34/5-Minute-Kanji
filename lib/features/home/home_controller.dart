import 'package:flutter/foundation.dart';

import '../../core/models/kanji_card.dart';
import '../../core/models/review.dart';
import '../../core/models/start_of_day.dart';
import '../../core/utils/clock.dart';
import '../../repositories/kanji_repository.dart';
import '../../repositories/progress_repository.dart';
import '../../services/daily_workload.dart';
import '../../services/due_card_selector.dart';
import '../../services/reminder_scheduler.dart';

class HomeController extends ChangeNotifier {
  HomeController({
    required this.kanjiRepository,
    required this.progressRepository,
    this.config = ReviewSessionConfig.fiveMinute,
    this.selector = const DueCardSelector(),
    this.reminderScheduler,
    Clock? clock,
  }) : clock = clock ?? DateTime.now,
       workloadService = DailyWorkloadService(
         kanjiRepository: kanjiRepository,
         progressRepository: progressRepository,
         selector: selector,
       );

  final KanjiRepository kanjiRepository;
  final ProgressRepository progressRepository;
  final ReviewSessionConfig config;
  final DueCardSelector selector;
  final DailyWorkloadService workloadService;

  /// Absent in tests and on platforms without notifications.
  final ReminderScheduler? reminderScheduler;
  final Clock clock;

  bool loading = true;
  int dueCount = 0;
  int newRemainingToday = 0;
  int estimatedMinutes = 0;
  int streak = 0;
  int recommendedCount = 0;
  bool recommendedComplete = false;
  bool studyAnywayAvailable = false;
  DateTime? nextReviewAt;
  StartOfDay startOfDay = StartOfDay.defaults;

  /// New kanji still left in today's allowance. Decreases when a card is
  /// learned, not when it is retrieved for the first time.
  int get remainingToday => newRemainingToday;

  bool get isCaughtUp => !loading && dueCount == 0 && newRemainingToday == 0;

  Future<void> load({bool showLoading = true}) async {
    if (showLoading) {
      loading = true;
      notifyListeners();
    }

    try {
      final streakInfo = await progressRepository.getStreak();
      final workload = await workloadService.read(now: clock());

      dueCount = workload.dueCount;
      newRemainingToday = workload.newRemainingToday;
      estimatedMinutes = workload.estimatedMinutes;
      recommendedCount = workload.sessionCards.length;
      recommendedComplete = workload.recommendedComplete;
      studyAnywayAvailable = workload.studyAnywayAvailable;
      streak = streakInfo.current;
      startOfDay = workload.startOfDay;
      nextReviewAt = workload.nextReviewAt;
    } catch (_) {
      dueCount = 0;
      newRemainingToday = 0;
      estimatedMinutes = 0;
      recommendedCount = 0;
      recommendedComplete = false;
      studyAnywayAvailable = false;
      streak = 0;
      startOfDay = StartOfDay.defaults;
      nextReviewAt = null;
    }

    loading = false;
    notifyListeners();

    // Home reloads at exactly the moments today's workload can have changed:
    // startup, resume, and returning from a sitting, the kanji list or
    // settings. That makes it the right place to keep the reminder honest.
    await reminderScheduler?.reschedule();
  }

  Future<List<KanjiCard>> cardsForSession({bool studyAnyway = false}) async {
    final workload = await workloadService.read(now: clock());
    if (studyAnyway) return workload.overflowCards;
    return workload.sessionCards;
  }
}

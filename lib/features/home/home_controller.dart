import 'package:flutter/foundation.dart';

import '../../core/models/kanji_card.dart';
import '../../core/models/review.dart';
import '../../core/models/start_of_day.dart';
import '../../core/models/study_allocation.dart';
import '../../core/utils/clock.dart';
import '../../repositories/kanji_repository.dart';
import '../../repositories/progress_repository.dart';
import '../../services/curriculum/curriculum_access.dart';
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
    this.curriculumAccess,
    Clock? clock,
  }) : clock = clock ?? DateTime.now,
       workloadService = DailyWorkloadService(
         kanjiRepository: kanjiRepository,
         progressRepository: progressRepository,
         selector: selector,
         curriculumAccess: curriculumAccess,
       );

  final KanjiRepository kanjiRepository;
  final ProgressRepository progressRepository;
  final ReviewSessionConfig config;
  final DueCardSelector selector;
  final DailyWorkloadService workloadService;

  /// Absent in tests and on platforms without notifications.
  final ReminderScheduler? reminderScheduler;
  final CurriculumAccess? curriculumAccess;
  final Clock clock;

  bool loading = true;
  int dueCount = 0;
  int newRemainingToday = 0;
  int estimatedMinutes = 0;
  int streak = 0;
  int recommendedCount = 0;

  /// Showings in today's sitting. Reviews count once; each new kanji counts
  /// twice because the sitting introduces it and then asks for it again.
  int studyItemCount = 0;

  /// Reviews and new kanji in the recommended sitting, with the time each
  /// group reserves. The home plan draws its counts and bar from this.
  StudyAllocation studyAllocation = StudyAllocation.empty;
  bool recommendedComplete = false;
  bool studyAnywayAvailable = false;
  DateTime? nextReviewAt;
  StartOfDay startOfDay = StartOfDay.defaults;

  /// Set while the full version is locked, for example `37 / 50 free kanji learned`.
  String? trialProgressLabel;

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
      studyItemCount = workload.studyItemCount;
      studyAllocation = workload.allocation;
      recommendedComplete = workload.recommendedComplete;
      studyAnywayAvailable = workload.studyAnywayAvailable;
      streak = streakInfo.current;
      startOfDay = workload.startOfDay;
      nextReviewAt = workload.nextReviewAt;
      final access = curriculumAccess;
      if (access != null) {
        await access.ensureLoaded();
        trialProgressLabel = access.unlocked ? null : access.trialProgressLabel;
      } else {
        trialProgressLabel = null;
      }
    } catch (_) {
      dueCount = 0;
      newRemainingToday = 0;
      estimatedMinutes = 0;
      recommendedCount = 0;
      studyItemCount = 0;
      studyAllocation = StudyAllocation.empty;
      recommendedComplete = false;
      studyAnywayAvailable = false;
      streak = 0;
      startOfDay = StartOfDay.defaults;
      nextReviewAt = null;
      trialProgressLabel = null;
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

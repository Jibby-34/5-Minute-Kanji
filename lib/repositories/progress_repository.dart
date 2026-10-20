import '../core/models/card_schedule.dart';
import '../core/models/daily_session_plan.dart';
import '../core/models/onboarding.dart';
import '../core/models/placement.dart';
import '../core/models/progress.dart';
import '../core/models/review_duration.dart';

abstract class ProgressRepository {
  Future<Map<String, CardSchedule>> getSchedules();

  Future<CardSchedule?> getSchedule(String cardId);

  Future<void> saveSchedule(CardSchedule schedule);

  Future<void> saveSchedules(Iterable<CardSchedule> schedules);

  /// Removes one card's schedule. No-op when it was never stored.
  Future<void> deleteSchedule(String cardId);

  Future<List<ReviewHistoryEntry>> getHistory();

  Future<void> addHistory(ReviewHistoryEntry entry);

  /// Drops the newest history entry when it is [entry]. Returns false when
  /// the newest entry is something else, so an undo cannot erase the wrong
  /// answer.
  Future<bool> removeLastHistory(ReviewHistoryEntry entry);

  Future<bool> hasSeenShakeUndoHint();

  Future<void> markShakeUndoHintSeen();

  Future<StreakInfo> getStreak();

  Future<void> saveStreak(StreakInfo streak);

  Future<AppSettings> getSettings();

  Future<void> saveSettings(AppSettings settings);

  Future<DailyNewKanjiProgress> getDailyNewKanji();

  Future<void> saveDailyNewKanji(DailyNewKanjiProgress progress);

  Future<DailyReviewTime> getDailyReviewTime();

  Future<void> saveDailyReviewTime(DailyReviewTime progress);

  /// Learned per-card paces. Empty until the user finishes real reviews.
  Future<ReviewDurationModel> getReviewDurationModel();

  Future<void> saveReviewDurationModel(ReviewDurationModel model);

  Future<DailySessionPlan> getDailySessionPlan();

  Future<void> saveDailySessionPlan(DailySessionPlan plan);

  Future<PlacementProgress> getPlacement();

  Future<void> savePlacement(PlacementProgress placement);

  Future<OnboardingProgress> getOnboarding();

  Future<void> saveOnboarding(OnboardingProgress onboarding);

  /// Creates a fresh due-now schedule for any card that has none.
  Future<void> seedIfNeeded(List<String> cardIds, {DateTime? now});
}

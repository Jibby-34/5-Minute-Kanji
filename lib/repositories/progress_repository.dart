import '../core/models/card_schedule.dart';
import '../core/models/progress.dart';

abstract class ProgressRepository {
  Future<Map<String, CardSchedule>> getSchedules();

  Future<CardSchedule?> getSchedule(String cardId);

  Future<void> saveSchedule(CardSchedule schedule);

  Future<void> saveSchedules(Iterable<CardSchedule> schedules);

  Future<List<ReviewHistoryEntry>> getHistory();

  Future<void> addHistory(ReviewHistoryEntry entry);

  Future<StreakInfo> getStreak();

  Future<void> saveStreak(StreakInfo streak);

  Future<AppSettings> getSettings();

  Future<void> saveSettings(AppSettings settings);

  Future<DailyNewKanjiProgress> getDailyNewKanji();

  Future<void> saveDailyNewKanji(DailyNewKanjiProgress progress);

  /// Creates a fresh due-now schedule for any card that has none.
  Future<void> seedIfNeeded(List<String> cardIds, {DateTime? now});
}

import '../core/models/progress.dart';
import '../core/models/start_of_day.dart';

class StreakService {
  const StreakService();

  /// A day counts if the user completes at least one session. Study-day local.
  StreakInfo recordCompletion(
    StreakInfo current,
    DateTime now, {
    StartOfDay startOfDay = StartOfDay.defaults,
  }) {
    final today = startOfDay.studyDate(now);
    final last = current.lastStudyDate;

    if (last == null) {
      return StreakInfo(current: 1, lastStudyDate: today);
    }

    final lastDay = calendarDay(last);
    if (lastDay == today) {
      return StreakInfo(
        current: current.current == 0 ? 1 : current.current,
        lastStudyDate: today,
      );
    }

    final yesterday = today.subtract(const Duration(days: 1));
    if (lastDay == yesterday) {
      return StreakInfo(current: current.current + 1, lastStudyDate: today);
    }

    return StreakInfo(current: 1, lastStudyDate: today);
  }
}

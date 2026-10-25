import '../core/models/progress.dart';
import '../core/models/start_of_day.dart';

class StreakService {
  const StreakService();

  /// Counts one study day. A missed day leaves the total where it is.
  StreakInfo recordCompletion(
    StreakInfo current,
    DateTime now, {
    StartOfDay startOfDay = StartOfDay.defaults,
  }) {
    final today = startOfDay.studyDate(now);
    final last = current.lastStudyDate;

    if (last != null && calendarDay(last) == today) {
      return StreakInfo(
        current: current.current == 0 ? 1 : current.current,
        lastStudyDate: today,
      );
    }

    return StreakInfo(current: current.current + 1, lastStudyDate: today);
  }
}

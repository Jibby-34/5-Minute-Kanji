import '../core/models/progress.dart';

class StreakService {
  const StreakService();

  /// A day counts if the user completes at least one session. Calendar-local.
  StreakInfo recordCompletion(StreakInfo current, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final last = current.lastStudyDate;

    if (last == null) {
      return StreakInfo(current: 1, lastStudyDate: today);
    }

    final lastDay = DateTime(last.year, last.month, last.day);
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

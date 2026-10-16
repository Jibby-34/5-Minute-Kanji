import '../core/models/progress.dart';
import '../core/models/start_of_day.dart';

/// Active review time for the current study day.
///
/// [accrued] is time already saved from earlier sittings. This sitting adds
/// only the stretches when the clock is running, so time in the background
/// does not count. A new study day drops the previous total.
class DailyReviewClock {
  DailyReviewClock({
    required DateTime startedAt,
    required this.startOfDay,
    this.accrued = Duration.zero,
    this.accruedDay,
  }) : _openStart = startedAt;

  StartOfDay startOfDay;
  Duration accrued;
  DateTime? accruedDay;

  final List<(DateTime, DateTime)> _closed = [];
  DateTime? _openStart;

  bool get isRunning => _openStart != null;

  void pause(DateTime now) {
    final start = _openStart;
    if (start == null) return;
    if (!now.isBefore(start)) _closed.add((start, now));
    _openStart = null;
  }

  void resume(DateTime now) {
    _openStart ??= now;
  }

  /// Review time that belongs to the study day containing [now].
  Duration totalAt(DateTime now) {
    var total = _accruedOn(now);
    for (final segment in _closed) {
      total += _overlap(segment.$1, segment.$2, now);
    }
    final open = _openStart;
    if (open != null) total += _overlap(open, now, now);
    return total;
  }

  Duration _accruedOn(DateTime now) {
    final day = accruedDay;
    if (day == null || accrued <= Duration.zero) return Duration.zero;
    if (calendarDay(day) != startOfDay.studyDate(now)) return Duration.zero;
    return accrued;
  }

  Duration _overlap(DateTime start, DateTime end, DateTime now) {
    final dayStart = startOfDay.startOfStudyDay(now);
    final dayEnd = startOfDay.startOfNextStudyDay(now);
    final from = start.isBefore(dayStart) ? dayStart : start;
    final to = end.isAfter(dayEnd) ? dayEnd : end;
    if (!to.isAfter(from)) return Duration.zero;
    return to.difference(from);
  }
}

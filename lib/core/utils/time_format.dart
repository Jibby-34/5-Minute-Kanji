import '../models/start_of_day.dart';

String greetingFor(DateTime now) {
  final hour = now.hour;
  if (hour >= 5 && hour < 12) return 'Good Morning';
  if (hour >= 12 && hour < 17) return 'Good Afternoon';
  return 'Good Evening';
}

String formatSessionDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds % 60;
  return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
}

/// Nearest 10 seconds for the study-plan readout. Five seconds rounds up.
/// The sitting itself still uses the unrounded estimate.
int roundPlanSeconds(int seconds) {
  if (seconds <= 0) return 0;
  return ((seconds + 5) ~/ 10) * 10;
}

/// Study-plan duration, in the same voice as the welcome example:
/// `5 min`, `4 min 20 sec`, or `40 sec`. Zero is `0 min`.
String formatPlanDuration(int seconds) {
  return _planDuration(roundPlanSeconds(seconds)).visual;
}

/// The same duration in full words, for a screen reader.
String formatPlanDurationSpoken(int seconds) {
  return _planDuration(roundPlanSeconds(seconds)).spoken;
}

({String visual, String spoken}) _planDuration(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final minutes = safe ~/ 60;
  final remainder = safe % 60;
  if (minutes == 0 && remainder == 0) {
    return (visual: '0 min', spoken: '0 minutes');
  }
  if (minutes == 0) {
    return (
      visual: '$remainder sec',
      spoken: remainder == 1 ? '1 second' : '$remainder seconds',
    );
  }
  final minuteVisual = '$minutes min';
  final minuteSpoken = minutes == 1 ? '1 minute' : '$minutes minutes';
  if (remainder == 0) {
    return (visual: minuteVisual, spoken: minuteSpoken);
  }
  return (
    visual: '$minuteVisual $remainder sec',
    spoken:
        '$minuteSpoken '
        '${remainder == 1 ? '1 second' : '$remainder seconds'}',
  );
}

String formatStartOfDay(StartOfDay startOfDay) {
  final hour12 = startOfDay.hour % 12 == 0 ? 12 : startOfDay.hour % 12;
  final minute = startOfDay.minute.toString().padLeft(2, '0');
  final period = startOfDay.hour < 12 ? 'AM' : 'PM';
  return '$hour12:$minute $period';
}

String formatNextReview(
  DateTime? due,
  DateTime now, {
  StartOfDay startOfDay = StartOfDay.defaults,
}) {
  if (due == null) return 'soon';
  if (!due.isAfter(now)) return 'now';

  final diff = due.difference(now);
  if (diff.inMinutes < 1) return 'in a moment';
  if (diff.inMinutes < 60) return 'in ${diff.inMinutes} min';

  final today = startOfDay.studyDate(now);
  final dueDay = startOfDay.studyDate(due);
  final tomorrow = today.add(const Duration(days: 1));

  if (dueDay == today) return 'later today';
  if (dueDay == tomorrow) return 'tomorrow';

  return '${dueDay.month}/${dueDay.day}';
}

int estimateReviewMinutes({
  required int dueCount,
  required int averageSecondsPerCard,
}) {
  if (dueCount <= 0) return 0;
  final minutes = (dueCount * averageSecondsPerCard) / 60;
  return minutes.ceil().clamp(1, 999);
}

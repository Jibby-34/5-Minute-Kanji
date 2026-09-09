import '../models/start_of_day.dart';

String greetingFor(DateTime now) {
  final hour = now.hour;
  if (hour >= 5 && hour < 12) return 'Good morning';
  if (hour >= 12 && hour < 17) return 'Good afternoon';
  return 'Good evening';
}

String formatSessionDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds % 60;
  return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
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

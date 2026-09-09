import 'review.dart';
import 'start_of_day.dart';

class ReviewHistoryEntry {
  const ReviewHistoryEntry({
    required this.cardId,
    required this.rating,
    required this.timestamp,
    required this.timeOnCard,
    this.isPractice = false,
  });

  final String cardId;
  final ReviewResult rating;
  final DateTime timestamp;
  final Duration timeOnCard;
  final bool isPractice;

  Map<String, dynamic> toJson() {
    return {
      'cardId': cardId,
      'rating': rating.name,
      'timestamp': timestamp.toIso8601String(),
      'timeOnCardMs': timeOnCard.inMilliseconds,
      'isPractice': isPractice,
    };
  }

  static ReviewHistoryEntry? fromJson(Map<String, dynamic> json) {
    try {
      final rating = switch (json['rating'] as String?) {
        'again' => ReviewResult.again,
        'hard' => ReviewResult.hard,
        'good' => ReviewResult.good,
        _ => null,
      };
      final cardId = json['cardId'] as String?;
      if (cardId == null || rating == null) return null;
      return ReviewHistoryEntry(
        cardId: cardId,
        rating: rating,
        timestamp: DateTime.parse(json['timestamp'] as String),
        timeOnCard: Duration(
          milliseconds: (json['timeOnCardMs'] as num?)?.toInt() ?? 0,
        ),
        isPractice: json['isPractice'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }
}

class StreakInfo {
  const StreakInfo({required this.current, this.lastStudyDate});

  static const empty = StreakInfo(current: 0);

  final int current;
  final DateTime? lastStudyDate;

  Map<String, dynamic> toJson() {
    return {
      'current': current,
      'lastStudyDate': lastStudyDate == null ? null : _dateOnly(lastStudyDate!),
    };
  }

  static StreakInfo fromJson(Map<String, dynamic>? json) {
    if (json == null) return empty;
    try {
      final rawDate = json['lastStudyDate'] as String?;
      return StreakInfo(
        current: (json['current'] as num?)?.toInt() ?? 0,
        lastStudyDate: rawDate == null ? null : DateTime.parse(rawDate),
      );
    } catch (_) {
      return empty;
    }
  }

  static String _dateOnly(DateTime date) => calendarDayKey(date);
}

/// How many previously unencountered kanji were introduced on [date].
class DailyNewKanjiProgress {
  const DailyNewKanjiProgress({this.date, this.count = 0});

  static const empty = DailyNewKanjiProgress();

  final DateTime? date;
  final int count;

  /// Stored progress for [now]'s study day. Yesterday's count becomes 0.
  DailyNewKanjiProgress forDay(
    DateTime now, {
    StartOfDay startOfDay = StartOfDay.defaults,
  }) {
    final today = startOfDay.studyDate(now);
    if (date != null && calendarDay(date!) == today) return this;
    return DailyNewKanjiProgress(date: today);
  }

  DailyNewKanjiProgress increment() {
    return DailyNewKanjiProgress(date: date, count: count + 1);
  }

  int remainingAllowance(int dailyLimit) {
    final leftover = dailyLimit - count;
    return leftover < 0 ? 0 : leftover;
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date == null ? null : calendarDayKey(date!),
      'count': count,
    };
  }

  static DailyNewKanjiProgress fromJson(Map<String, dynamic>? json) {
    if (json == null) return empty;
    try {
      final rawDate = json['date'] as String?;
      return DailyNewKanjiProgress(
        date: rawDate == null ? null : DateTime.parse(rawDate),
        count: (json['count'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return empty;
    }
  }
}

class AppSettings {
  const AppSettings({
    this.averageSecondsPerCard = 12,
    this.newKanjiPerDay = defaultNewKanjiPerDay,
    this.startOfDay = StartOfDay.defaults,
  });

  static const int defaultNewKanjiPerDay = 5;
  static const int minNewKanjiPerDay = 0;
  static const int maxNewKanjiPerDay = 50;

  final int averageSecondsPerCard;
  final int newKanjiPerDay;
  final StartOfDay startOfDay;

  AppSettings copyWith({
    int? averageSecondsPerCard,
    int? newKanjiPerDay,
    StartOfDay? startOfDay,
  }) {
    return AppSettings(
      averageSecondsPerCard:
          averageSecondsPerCard ?? this.averageSecondsPerCard,
      newKanjiPerDay: newKanjiPerDay == null
          ? this.newKanjiPerDay
          : clampNewKanjiPerDay(newKanjiPerDay),
      startOfDay: startOfDay ?? this.startOfDay,
    );
  }

  static int clampNewKanjiPerDay(int value) {
    return value.clamp(minNewKanjiPerDay, maxNewKanjiPerDay);
  }

  Map<String, dynamic> toJson() {
    return {
      'averageSecondsPerCard': averageSecondsPerCard,
      'newKanjiPerDay': newKanjiPerDay,
      'startOfDayHour': startOfDay.hour,
      'startOfDayMinute': startOfDay.minute,
    };
  }

  static AppSettings fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AppSettings();
    return AppSettings(
      averageSecondsPerCard:
          (json['averageSecondsPerCard'] as num?)?.toInt() ?? 12,
      newKanjiPerDay: clampNewKanjiPerDay(
        (json['newKanjiPerDay'] as num?)?.toInt() ?? defaultNewKanjiPerDay,
      ),
      startOfDay: StartOfDay.normalize(
        hour:
            (json['startOfDayHour'] as num?)?.toInt() ?? StartOfDay.defaultHour,
        minute:
            (json['startOfDayMinute'] as num?)?.toInt() ??
            StartOfDay.defaultMinute,
      ),
    );
  }
}

/// Date-only local midnight. Use [StartOfDay.studyDate] for study-day logic.
DateTime calendarDay(DateTime date) =>
    DateTime(date.year, date.month, date.day);

String calendarDayKey(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

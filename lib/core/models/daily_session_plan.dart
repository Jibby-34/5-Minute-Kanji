import 'progress.dart';
import 'start_of_day.dart';

/// The recommended queue for one study day.
///
/// Frozen until the study day, time budget, new-kanji allowance, or start of
/// day changes. Cards left out of [cardIds] stay eligible; they are not
/// failed, skipped, or rescheduled.
class DailySessionPlan {
  const DailySessionPlan({
    this.studyDate,
    this.budgetMinutes = 0,
    this.newKanjiPerDay = 0,
    this.startOfDay = StartOfDay.defaults,
    this.cardIds = const [],
    this.completed = false,
  });

  static const empty = DailySessionPlan();

  final DateTime? studyDate;
  final int budgetMinutes;
  final int newKanjiPerDay;
  final StartOfDay startOfDay;
  final List<String> cardIds;
  final bool completed;

  bool matches({
    required DateTime studyDate,
    required int budgetMinutes,
    required int newKanjiPerDay,
    required StartOfDay startOfDay,
  }) {
    final stored = this.studyDate;
    if (stored == null) return false;
    return calendarDay(stored) == calendarDay(studyDate) &&
        this.budgetMinutes == budgetMinutes &&
        this.newKanjiPerDay == newKanjiPerDay &&
        this.startOfDay == startOfDay;
  }

  DailySessionPlan copyWith({bool? completed}) {
    return DailySessionPlan(
      studyDate: studyDate,
      budgetMinutes: budgetMinutes,
      newKanjiPerDay: newKanjiPerDay,
      startOfDay: startOfDay,
      cardIds: cardIds,
      completed: completed ?? this.completed,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'studyDate': studyDate == null ? null : calendarDayKey(studyDate!),
      'budgetMinutes': budgetMinutes,
      'newKanjiPerDay': newKanjiPerDay,
      'startOfDayHour': startOfDay.hour,
      'startOfDayMinute': startOfDay.minute,
      'cardIds': cardIds,
      'completed': completed,
    };
  }

  static DailySessionPlan fromJson(Map<String, dynamic>? json) {
    if (json == null) return empty;
    try {
      final rawDate = json['studyDate'] as String?;
      final rawIds = json['cardIds'];
      final ids = <String>[];
      if (rawIds is List) {
        for (final id in rawIds) {
          if (id is String && id.isNotEmpty) ids.add(id);
        }
      }
      return DailySessionPlan(
        studyDate: rawDate == null ? null : DateTime.parse(rawDate),
        budgetMinutes: (json['budgetMinutes'] as num?)?.toInt() ?? 0,
        newKanjiPerDay: (json['newKanjiPerDay'] as num?)?.toInt() ?? 0,
        startOfDay: StartOfDay.normalize(
          hour:
              (json['startOfDayHour'] as num?)?.toInt() ??
              StartOfDay.defaultHour,
          minute:
              (json['startOfDayMinute'] as num?)?.toInt() ??
              StartOfDay.defaultMinute,
        ),
        cardIds: ids,
        completed: json['completed'] as bool? ?? false,
      );
    } catch (_) {
      return empty;
    }
  }
}

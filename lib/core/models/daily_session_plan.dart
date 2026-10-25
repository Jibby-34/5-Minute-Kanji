import 'curriculum_mode.dart';
import 'progress.dart';
import 'start_of_day.dart';

/// The recommended queue for one study day.
///
/// Frozen until the study day, time budget, new-kanji allowance, start of
/// day, or curriculum mode changes, or Settings clears it. Cards left out of
/// [cardIds] stay eligible; they are not failed, skipped, or rescheduled.
class DailySessionPlan {
  const DailySessionPlan({
    this.studyDate,
    this.budgetMinutes = 0,
    this.newKanjiPerDay = 0,
    this.startOfDay = StartOfDay.defaults,
    this.curriculumMode = CurriculumMode.defaultMode,
    this.allowsNewKanji = true,
    this.cardIds = const [],
    this.completed = false,
  });

  static const empty = DailySessionPlan();

  final DateTime? studyDate;
  final int budgetMinutes;
  final int newKanjiPerDay;
  final StartOfDay startOfDay;

  /// The learning order this queue was built with.
  final CurriculumMode curriculumMode;

  /// False when the queue was built after the free trial had blocked new kanji.
  ///
  /// Buying the full version makes today's plan stop matching, so the next
  /// load can include new kanji again. Older saves omit the field and stay
  /// open to new kanji.
  final bool allowsNewKanji;

  final List<String> cardIds;
  final bool completed;

  bool matches({
    required DateTime studyDate,
    required int budgetMinutes,
    required int newKanjiPerDay,
    required StartOfDay startOfDay,
    CurriculumMode curriculumMode = CurriculumMode.defaultMode,
    bool allowsNewKanji = true,
  }) {
    final stored = this.studyDate;
    if (stored == null) return false;
    return calendarDay(stored) == calendarDay(studyDate) &&
        this.budgetMinutes == budgetMinutes &&
        this.newKanjiPerDay == newKanjiPerDay &&
        this.startOfDay == startOfDay &&
        this.curriculumMode == curriculumMode &&
        this.allowsNewKanji == allowsNewKanji;
  }

  DailySessionPlan copyWith({bool? completed}) {
    return DailySessionPlan(
      studyDate: studyDate,
      budgetMinutes: budgetMinutes,
      newKanjiPerDay: newKanjiPerDay,
      startOfDay: startOfDay,
      curriculumMode: curriculumMode,
      allowsNewKanji: allowsNewKanji,
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
      'curriculumMode': curriculumMode.name,
      'allowsNewKanji': allowsNewKanji,
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
        curriculumMode: CurriculumMode.fromStorage(
          json['curriculumMode'] as String?,
        ),
        allowsNewKanji: json['allowsNewKanji'] as bool? ?? true,
        cardIds: ids,
        completed: json['completed'] as bool? ?? false,
      );
    } catch (_) {
      return empty;
    }
  }
}

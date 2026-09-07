import '../core/models/card_schedule.dart';
import '../core/models/kanji_card.dart';
import '../core/models/progress.dart';

/// Picks cards for a sitting. SRS [CardSchedule.dueAt] is the ideal review
/// time; this class decides daily availability for today's study window.
class DueCardSelector {
  const DueCardSelector();

  bool isNew(CardSchedule? schedule) {
    return schedule == null || schedule.state == CardLearningState.newCard;
  }

  /// Encountered cards that belong to today's study window.
  bool isEncounteredDue(CardSchedule? schedule, DateTime now) {
    return !isNew(schedule) && isAvailableToday(schedule!, now);
  }

  bool isDue(CardSchedule? schedule, DateTime now) {
    return isNew(schedule) || isAvailableToday(schedule!, now);
  }

  /// True when [schedule] can be shown in today's sitting.
  ///
  /// Overdue cards and cards due later today are included. Cards due
  /// tomorrow or later are not. Does not change SRS intervals.
  bool isAvailableToday(CardSchedule schedule, DateTime now) {
    return schedule.dueAt.isBefore(_startOfTomorrow(now));
  }

  DateTime _startOfTomorrow(DateTime now) =>
      calendarDay(now).add(const Duration(days: 1));

  List<KanjiCard> select({
    required List<KanjiCard> cards,
    required Map<String, CardSchedule> schedules,
    required DateTime now,
    required int limit,
    int? maxNewCards,
  }) {
    if (limit <= 0) return const [];

    final learningDue = <KanjiCard>[];
    final reviewDue = <KanjiCard>[];
    final news = <KanjiCard>[];

    for (final card in cards) {
      final schedule = schedules[card.id];
      if (isNew(schedule)) {
        news.add(card);
      } else if (isAvailableToday(schedule!, now)) {
        if (schedule.state == CardLearningState.learning) {
          learningDue.add(card);
        } else {
          reviewDue.add(card);
        }
      }
    }

    _sortByDueThenId(learningDue, schedules, now);
    _sortByDueThenId(reviewDue, schedules, now);
    news.sort(_compareNewLearnOrder);

    final existingAvailable = learningDue.length + reviewDue.length;
    final int newTakeCount;
    final int existingTakeCount;
    if (maxNewCards == null) {
      existingTakeCount = existingAvailable < limit ? existingAvailable : limit;
      final leftover = limit - existingTakeCount;
      newTakeCount = news.length < leftover ? news.length : leftover;
    } else {
      final cappedNew = maxNewCards < 0 ? 0 : maxNewCards;
      newTakeCount = [
        cappedNew,
        news.length,
        limit,
      ].reduce((a, b) => a < b ? a : b);
      final leftover = limit - newTakeCount;
      existingTakeCount = existingAvailable < leftover
          ? existingAvailable
          : leftover;
    }

    final newTake = news.take(newTakeCount).toList();
    final existing = [
      ...learningDue,
      ...reviewDue,
    ].take(existingTakeCount).toList();

    return _interleaveNew(existing: existing, news: newTake);
  }

  int countDue({
    required List<KanjiCard> cards,
    required Map<String, CardSchedule> schedules,
    required DateTime now,
  }) {
    var due = 0;
    for (final card in cards) {
      if (isEncounteredDue(schedules[card.id], now)) due++;
    }
    return due;
  }

  int countNew({
    required List<KanjiCard> cards,
    required Map<String, CardSchedule> schedules,
  }) {
    var n = 0;
    for (final card in cards) {
      if (isNew(schedules[card.id])) n++;
    }
    return n;
  }

  DateTime? nextFutureDue({
    required List<KanjiCard> cards,
    required Map<String, CardSchedule> schedules,
    required DateTime now,
  }) {
    DateTime? next;
    for (final card in cards) {
      final schedule = schedules[card.id];
      if (schedule == null ||
          isNew(schedule) ||
          isAvailableToday(schedule, now)) {
        continue;
      }
      if (next == null || schedule.dueAt.isBefore(next)) {
        next = schedule.dueAt;
      }
    }
    return next;
  }

  int _compareNewLearnOrder(KanjiCard a, KanjiCard b) {
    final aLevel = JlptLevel.sectionOrder.indexOf(a.jlptLevel);
    final bLevel = JlptLevel.sectionOrder.indexOf(b.jlptLevel);
    final levelCompare = aLevel.compareTo(bLevel);
    if (levelCompare != 0) return levelCompare;
    return a.id.compareTo(b.id);
  }

  void _sortByDueThenId(
    List<KanjiCard> cards,
    Map<String, CardSchedule> schedules,
    DateTime now,
  ) {
    cards.sort((a, b) {
      final aDue = schedules[a.id]?.dueAt ?? now;
      final bDue = schedules[b.id]?.dueAt ?? now;
      final dueCompare = aDue.compareTo(bDue);
      if (dueCompare != 0) return dueCompare;
      return a.id.compareTo(b.id);
    });
  }

  /// Spreads new cards through existing due cards.
  ///
  /// Starts with a due card when any exist, avoids dumping all new cards at
  /// the front or back, and is not a rigid Review/New/Review/New pattern.
  List<KanjiCard> _interleaveNew({
    required List<KanjiCard> existing,
    required List<KanjiCard> news,
  }) {
    if (news.isEmpty) return existing;
    if (existing.isEmpty) return news;

    final reviews = List<KanjiCard>.from(existing);
    final incoming = List<KanjiCard>.from(news);
    final result = <KanjiCard>[reviews.removeAt(0)];

    final remainingTotal = reviews.length + incoming.length;
    if (remainingTotal == 0) return result;

    final gap = remainingTotal / incoming.length;
    var nextNewAt = gap / 2;
    var position = 0;
    var newIndex = 0;
    var reviewIndex = 0;
    var lastWasNew = false;

    while (reviewIndex < reviews.length || newIndex < incoming.length) {
      final reviewsRemain = reviewIndex < reviews.length;
      final newsRemain = newIndex < incoming.length;
      var placeNew =
          newsRemain && (!reviewsRemain || position + 1 >= nextNewAt.round());
      if (placeNew && lastWasNew && reviewsRemain) {
        placeNew = false;
      }

      if (placeNew) {
        result.add(incoming[newIndex++]);
        nextNewAt += gap;
        lastWasNew = true;
      } else {
        result.add(reviews[reviewIndex++]);
        lastWasNew = false;
      }
      position++;
    }

    return result;
  }
}


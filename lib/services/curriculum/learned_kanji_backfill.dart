import '../../core/models/card_schedule.dart';
import '../initial_known_card_schedule.dart';
import '../srs_engine.dart';

/// Kanji already studied before trial tracking existed.
///
/// The studied set is recorded explicitly from here on. This classification
/// runs once so people who already learned kanji are not handed another 50
/// free introductions, while untouched Mark as Known and placement results
/// stay out of the count.
///
/// Schedules are only read. Intervals and review counts are left as they are.
class LearnedKanjiBackfill {
  const LearnedKanjiBackfill._();

  static Set<String> idsFrom(Iterable<CardSchedule> schedules) {
    return {
      for (final schedule in schedules)
        if (countsAsStudied(schedule)) schedule.cardId,
    };
  }

  /// True when [schedule] looks like the normal Learn flow, not a known card
  /// or an unreviewed placement confirmation.
  static bool countsAsStudied(CardSchedule schedule) {
    if (schedule.cardId.isEmpty) return false;
    if (schedule.state == CardLearningState.newCard) return false;
    if (_untouchedKnown(schedule)) return false;
    if (_untouchedPlacementConfirm(schedule)) return false;
    if (_earlyKnownReview(schedule)) return false;
    return true;
  }

  /// Mark as Known lands in review before any rating is stored.
  static bool _untouchedKnown(CardSchedule schedule) {
    return schedule.state == CardLearningState.review &&
        schedule.reviewCount == 0 &&
        schedule.lastReviewedAt == null;
  }

  /// Placement confirmation puts a still-new kanji into learning with a
  /// multi-day interval. The Learn flow's first interval is ten minutes.
  static bool _untouchedPlacementConfirm(CardSchedule schedule) {
    return schedule.state == CardLearningState.learning &&
        schedule.reviewCount == 0 &&
        schedule.lastReviewedAt == null &&
        schedule.interval >= const Duration(days: 1) &&
        schedule.interval != SrsEngine.newLearnInterval;
  }

  /// The first few Mark-as-Known reviews stay on a long interval. A kanji
  /// learned in the app graduates to one day and is still under two weeks
  /// after three reviews, so those cards are not treated as known.
  static bool _earlyKnownReview(CardSchedule schedule) {
    return schedule.state == CardLearningState.review &&
        schedule.reviewCount > 0 &&
        schedule.reviewCount <= 3 &&
        schedule.interval >= const Duration(days: initialKnownMinDays);
  }
}

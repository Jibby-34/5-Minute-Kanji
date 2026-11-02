import '../../core/models/card_schedule.dart';
import '../../core/models/review.dart';
import '../../core/models/start_of_day.dart';
import '../due_card_selector.dart';

/// How one committed Again or Good should be described.
///
/// [isNew] is true when this answer is the first retrieval of a kanji that
/// was introduced in this sitting, or the schedule was still new. Mark as
/// Known and the placement test do not produce a review.
class StudyReviewClassification {
  const StudyReviewClassification({
    required this.result,
    required this.isNew,
    required this.reviewCategory,
  });

  /// `again` or `good`.
  final String result;

  final bool isNew;

  /// `new`, `due`, or `early`.
  final String reviewCategory;
}

/// Classifies a review answer without reading the kanji, its meaning, or its id.
///
/// Returns null for ratings other than Again and Good. The app's study screen
/// only offers those two. A card that is not new and is not available in
/// today's study window is `early`. Current sessions only queue new and due
/// cards, so `early` is reserved for a schedule that is genuinely ahead.
StudyReviewClassification? classifyStudyReview({
  required ReviewResult result,
  required CardSchedule? scheduleBeforeAnswer,
  required bool introducedThisSession,
  required DateTime now,
  required StartOfDay startOfDay,
  DueCardSelector selector = const DueCardSelector(),
}) {
  final label = switch (result) {
    ReviewResult.again => 'again',
    ReviewResult.good => 'good',
    ReviewResult.hard => null,
  };
  if (label == null) return null;

  final wasNew =
      introducedThisSession ||
      scheduleBeforeAnswer == null ||
      scheduleBeforeAnswer.state == CardLearningState.newCard;
  final String category;
  if (wasNew) {
    category = 'new';
  } else if (selector.isAvailableToday(
    scheduleBeforeAnswer,
    now,
    startOfDay: startOfDay,
  )) {
    category = 'due';
  } else {
    category = 'early';
  }
  return StudyReviewClassification(
    result: label,
    isNew: wasNew,
    reviewCategory: category,
  );
}

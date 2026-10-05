import '../core/models/card_schedule.dart';

/// How long a card is expected to take. Separate from how important it is.
///
/// Constants stand in for measured review times. Passing different durations
/// here is the seam a later estimator can use once real timings exist.
class CardTimeEstimator {
  const CardTimeEstimator({
    this.newCard = const Duration(seconds: 30),
    this.learningCard = const Duration(seconds: 24),
    this.reviewCard = const Duration(seconds: 20),
    this.matureCard = const Duration(seconds: 14),
    this.matureInterval = const Duration(days: 21),
  });

  final Duration newCard;
  final Duration learningCard;
  final Duration reviewCard;
  final Duration matureCard;
  final Duration matureInterval;

  Duration estimate(CardSchedule? schedule, {required bool isNew}) {
    if (isNew ||
        schedule == null ||
        schedule.state == CardLearningState.newCard) {
      return newCard;
    }
    if (schedule.state == CardLearningState.learning) return learningCard;
    if (schedule.interval >= matureInterval) return matureCard;
    return reviewCard;
  }
}

/// Calm minute estimate. Never claims a session will take exactly the budget.
int estimatedMinutesFor(Duration duration) {
  if (duration.inSeconds <= 0) return 0;
  return (duration.inSeconds / 60).ceil().clamp(1, 999);
}

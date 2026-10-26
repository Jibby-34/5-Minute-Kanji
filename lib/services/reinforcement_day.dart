import '../core/models/card_schedule.dart';
import '../core/models/kanji_card.dart';
import '../core/models/start_of_day.dart';
import '../core/models/study_day_type.dart';
import 'due_card_selector.dart';
import 'recall_estimator.dart';

/// Thresholds that choose a Reinforcement Day.
///
/// Change these values to retune the trigger. [ReinforcementDayPolicy] reads
/// them and does not keep a second copy of the numbers.
class ReinforcementDayConfig {
  const ReinforcementDayConfig({
    this.minimumDueCards = 8,
    this.averageRecallThreshold = 0.70,
    this.lowRecallThreshold = 0.40,
    this.lowRecallFractionThreshold = 0.25,
  });

  /// Eligible due cards required before either recall rule can fire.
  final int minimumDueCards;

  /// Average recall below this starts a Reinforcement Day.
  final double averageRecallThreshold;

  /// Recall below this counts as a low-recall card. This value does not.
  final double lowRecallThreshold;

  /// Share of low-recall cards that starts a Reinforcement Day.
  ///
  /// A share equal to this value is enough. A smaller share is not.
  final double lowRecallFractionThreshold;
}

/// Decides Normal Day or Reinforcement Day from recall probabilities.
///
/// Eligible inputs are cards already due for review. The caller supplies
/// probabilities from [RecallEstimator]; this class does not schedule cards.
class ReinforcementDayPolicy {
  const ReinforcementDayPolicy({this.config = const ReinforcementDayConfig()});

  final ReinforcementDayConfig config;

  /// Day type for cards that are due at the planning boundary.
  ///
  /// Unseen cards, reviews due on a later study day, and untouched
  /// Mark-as-Known cards are left out of the sample. They are not removed
  /// from the review queue.
  StudyDayType dayTypeForCards({
    required List<KanjiCard> cards,
    required Map<String, CardSchedule> schedules,
    required DateTime now,
    required StartOfDay startOfDay,
    required RecallEstimator recall,
    DueCardSelector dueCards = const DueCardSelector(),
  }) {
    final probabilities = <double>[];
    for (final card in cards) {
      final schedule = schedules[card.id];
      if (schedule == null ||
          !_isEligibleDue(schedule, now, startOfDay, dueCards)) {
        continue;
      }
      probabilities.add(
        recall.probability(schedule: schedule, now: now, isNew: false),
      );
    }
    return dayTypeFor(probabilities);
  }

  /// [recallProbabilities] belong to eligible due cards.
  ///
  /// Non-finite values, and values outside `0.0`–`1.0`, are left out. An
  /// empty sample is a Normal Day, as is a sample smaller than
  /// [ReinforcementDayConfig.minimumDueCards].
  StudyDayType dayTypeFor(Iterable<double> recallProbabilities) {
    final usable = <double>[];
    for (final value in recallProbabilities) {
      if (isUsableRecall(value)) usable.add(value);
    }
    final minimum = config.minimumDueCards;
    if (usable.isEmpty || usable.length < minimum) {
      return StudyDayType.normal;
    }

    var total = 0.0;
    var low = 0;
    for (final value in usable) {
      total += value;
      if (value < config.lowRecallThreshold) low++;
    }
    final average = total / usable.length;
    if (average < config.averageRecallThreshold) {
      return StudyDayType.reinforcement;
    }
    final fraction = low / usable.length;
    if (fraction >= config.lowRecallFractionThreshold) {
      return StudyDayType.reinforcement;
    }
    return StudyDayType.normal;
  }

  /// True when [schedule] was marked known and has never been reviewed.
  static bool isMarkedKnown(CardSchedule schedule) {
    return schedule.state == CardLearningState.review &&
        schedule.reviewCount == 0 &&
        schedule.lastReviewedAt == null;
  }

  /// A probability the estimator could actually return.
  static bool isUsableRecall(double value) {
    return value.isFinite && value >= 0 && value <= 1;
  }

  bool _isEligibleDue(
    CardSchedule schedule,
    DateTime now,
    StartOfDay startOfDay,
    DueCardSelector dueCards,
  ) {
    if (dueCards.isNew(schedule)) return false;
    if (!dueCards.isAvailableToday(schedule, now, startOfDay: startOfDay)) {
      return false;
    }
    if (isMarkedKnown(schedule)) return false;
    return true;
  }
}

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
    this.averageRecallThreshold = 0.40,
    this.lowRecallThreshold = 0.20,
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

  /// The values shipped with the app. Diagnostic edits copy this and stay
  /// in memory.
  static const production = ReinforcementDayConfig();

  ReinforcementDayConfig copyWith({
    int? minimumDueCards,
    double? averageRecallThreshold,
    double? lowRecallThreshold,
    double? lowRecallFractionThreshold,
  }) {
    return ReinforcementDayConfig(
      minimumDueCards: minimumDueCards ?? this.minimumDueCards,
      averageRecallThreshold:
          averageRecallThreshold ?? this.averageRecallThreshold,
      lowRecallThreshold: lowRecallThreshold ?? this.lowRecallThreshold,
      lowRecallFractionThreshold:
          lowRecallFractionThreshold ?? this.lowRecallFractionThreshold,
    );
  }

  /// A whole number from 0 through 999, or null when [text] is unusable.
  static int? tryParseMinimum(String text) {
    final value = int.tryParse(text.trim());
    if (value == null || value < 0 || value > 999) return null;
    return value;
  }

  /// A finite probability from 0 through 1, or null when [text] is unusable.
  static double? tryParseUnit(String text) {
    final value = double.tryParse(text.trim());
    if (value == null || !value.isFinite || value < 0 || value > 1) {
      return null;
    }
    return value;
  }
}

/// Why a Reinforcement Day was chosen.
///
/// [ReinforcementDayPolicy] checks [averageRecall] first. A diagnosis lists
/// every condition that is met, with the deciding one first.
enum ReinforcementTriggerReason {
  averageRecall,
  lowRecallFraction;

  String describe(ReinforcementDayConfig config) {
    final average = formatThreshold(config.averageRecallThreshold);
    final low = formatThreshold(config.lowRecallThreshold);
    final fraction = formatThreshold(config.lowRecallFractionThreshold);
    return switch (this) {
      ReinforcementTriggerReason.averageRecall =>
        'Average recall is below $average.',
      ReinforcementTriggerReason.lowRecallFraction =>
        'The share of cards below $low is at least $fraction.',
    };
  }
}

/// The metrics behind one day-type decision.
///
/// [dayTypeFor] returns [dayType] from this result, so a diagnostic screen
/// and the daily plan share one comparison.
class ReinforcementDayDiagnosis {
  const ReinforcementDayDiagnosis({
    required this.eligibleCount,
    required this.usableCount,
    required this.excludedCount,
    required this.average,
    required this.lowCount,
    required this.lowFraction,
    required this.minimumMet,
    required this.dayType,
    required this.reasons,
  });

  /// Due cards offered to the decision, including unusable estimates.
  final int eligibleCount;

  /// Estimates that were finite and inside 0.0–1.0.
  final int usableCount;

  /// Eligible cards left out of the average.
  final int excludedCount;

  /// Null when [usableCount] is 0.
  final double? average;

  final int lowCount;

  /// Null when [usableCount] is 0.
  final double? lowFraction;

  final bool minimumMet;
  final StudyDayType dayType;

  /// Empty when the day stays Normal. The first entry is the check that
  /// selects Reinforcement Day.
  final List<ReinforcementTriggerReason> reasons;

  String get averageLabel {
    final value = average;
    if (value == null) return '—';
    return value.toStringAsFixed(3);
  }

  String get lowShareLabel {
    final fraction = lowFraction;
    if (fraction == null || usableCount == 0) return '0 (—)';
    final percent = (fraction * 100).toStringAsFixed(1);
    return '$lowCount of $usableCount ($percent%)';
  }

  String minimumLabel(int minimum) {
    if (minimumMet) return 'Satisfied ($usableCount eligible)';
    return 'Short of $minimum ($usableCount eligible)';
  }

  /// The condition that selected Reinforcement Day, or a short reason the
  /// day stayed Normal.
  String triggerLabel(ReinforcementDayConfig config) {
    if (reasons.isEmpty) {
      if (usableCount == 0) return 'None. The queue is empty.';
      if (!minimumMet) {
        return 'None. $usableCount eligible cards is under the minimum of ${config.minimumDueCards}.';
      }
      return 'None. Average recall and the low-recall share both stay within a Normal Day.';
    }
    return reasons.map((reason) => reason.describe(config)).join(' ');
  }
}

/// `0.7` prints as `0.70`. Longer values keep their digits.
String formatThreshold(double value) {
  if (!value.isFinite) return '—';
  final text = value.toString();
  final dot = text.indexOf('.');
  if (dot < 0 || text.length - dot - 1 < 2) {
    return value.toStringAsFixed(2);
  }
  return text;
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
    return diagnose(
      recallProbabilities(
        cards: cards,
        schedules: schedules,
        now: now,
        startOfDay: startOfDay,
        recall: recall,
        dueCards: dueCards,
      ),
    ).dayType;
  }

  /// Probabilities for cards due at the planning boundary.
  ///
  /// Unseen cards, reviews due on a later study day, and untouched
  /// Mark-as-Known cards are left out. Unusable estimates stay in the list
  /// so [diagnose] can count them and then drop them.
  List<double> recallProbabilities({
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
    return probabilities;
  }

  /// [recallProbabilities] belong to eligible due cards.
  ///
  /// Non-finite values, and values outside `0.0`–`1.0`, are left out. An
  /// empty sample is a Normal Day, as is a sample smaller than
  /// [ReinforcementDayConfig.minimumDueCards].
  StudyDayType dayTypeFor(Iterable<double> recallProbabilities) {
    return diagnose(recallProbabilities).dayType;
  }

  /// The single comparison used by the daily plan and the debugger.
  ReinforcementDayDiagnosis diagnose(Iterable<double> recallProbabilities) {
    final submitted = recallProbabilities.toList(growable: false);
    final usable = <double>[];
    for (final value in submitted) {
      if (isUsableRecall(value)) usable.add(value);
    }

    final usableCount = usable.length;
    double? average;
    var lowCount = 0;
    double? lowFraction;
    if (usableCount > 0) {
      var total = 0.0;
      for (final value in usable) {
        total += value;
        if (_isBelow(value, config.lowRecallThreshold)) lowCount++;
      }
      average = total / usableCount;
      lowFraction = lowCount / usableCount;
    }

    final minimumMet = usableCount > 0 && usableCount >= config.minimumDueCards;
    final reasons = <ReinforcementTriggerReason>[];
    if (minimumMet) {
      if (_isBelow(average!, config.averageRecallThreshold)) {
        reasons.add(ReinforcementTriggerReason.averageRecall);
      }
      if (lowFraction! >= config.lowRecallFractionThreshold) {
        reasons.add(ReinforcementTriggerReason.lowRecallFraction);
      }
    }

    return ReinforcementDayDiagnosis(
      eligibleCount: submitted.length,
      usableCount: usableCount,
      excludedCount: submitted.length - usableCount,
      average: average,
      lowCount: lowCount,
      lowFraction: lowFraction,
      minimumMet: minimumMet,
      dayType: reasons.isEmpty
          ? StudyDayType.normal
          : StudyDayType.reinforcement,
      reasons: List.unmodifiable(reasons),
    );
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

  /// Strictly below [line]. A gap that is only float noise does not count,
  /// so a queue sitting on the threshold stays a Normal Day.
  static bool _isBelow(double value, double line) {
    return line - value > 1e-9;
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

import 'dart:math' as math;

import '../core/models/card_schedule.dart';
import '../core/models/kanji_card.dart';
import 'recall_estimator.dart';

/// How valuable it is to spend limited time on a card. Higher means sooner.
///
/// Forgetting risk is one input. A stable card that is merely old does not
/// outrank a card that is about to be forgotten, and a brand-new card does
/// not crowd out a card the user just failed.
class CardPriorityScorer {
  const CardPriorityScorer({this.recall = const RecallEstimator()});

  final RecallEstimator recall;

  double score({
    required CardSchedule? schedule,
    required DateTime now,
    required bool isNew,
    JlptLevel level = JlptLevel.none,
  }) {
    if (isNew ||
        schedule == null ||
        schedule.state == CardLearningState.newCard) {
      return 1.05 + _levelNudge(level);
    }

    final recallP = recall.probability(
      schedule: schedule,
      now: now,
      isNew: false,
    );
    final forgetting = 1 - recallP;
    // Highest when recall is slipping, not when it is already near zero
    // or still comfortable.
    final slip = 1 - (recallP - 0.55).abs();
    final slipValue = slip.clamp(0.15, 1.0);

    final elapsed = _elapsedSeconds(schedule, now);
    final stability = math.max(schedule.interval.inSeconds, 1).toDouble();
    final overdueRatio = elapsed / stability;
    final overdue = overdueRatio > 1 ? math.log(overdueRatio) : 0.0;

    final failures = math.min(0.8, schedule.incorrectCount * 0.12);
    final learning = schedule.state == CardLearningState.learning ? 0.75 : 0.0;
    final recentFailure =
        schedule.consecutiveGoodCount == 0 && schedule.incorrectCount > 0
        ? 0.4
        : 0.0;
    final stable = schedule.interval.inDays >= 21 && recallP > 0.85 ? 0.5 : 0.0;
    final success = math.min(0.25, schedule.consecutiveGoodCount * 0.04);

    return slipValue +
        forgetting * 0.35 +
        overdue * 0.2 +
        failures +
        learning +
        recentFailure +
        _levelNudge(level) -
        stable -
        success;
  }

  double _elapsedSeconds(CardSchedule schedule, DateTime now) {
    final reviewed = schedule.lastReviewedAt;
    if (reviewed == null) return schedule.interval.inSeconds.toDouble();
    final elapsed = now.difference(reviewed).inSeconds;
    return elapsed < 0 ? 0 : elapsed.toDouble();
  }

  /// A small tie-break toward earlier JLPT levels. Not the main signal.
  double _levelNudge(JlptLevel level) {
    return switch (level) {
      JlptLevel.n5 => 0.04,
      JlptLevel.n4 => 0.03,
      JlptLevel.n3 => 0.02,
      JlptLevel.n2 => 0.01,
      _ => 0,
    };
  }
}

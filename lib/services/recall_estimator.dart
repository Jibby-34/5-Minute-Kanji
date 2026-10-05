import 'dart:math' as math;

import '../core/models/card_schedule.dart';

/// Estimates the chance a card is recalled right now.
///
/// Deterministic and replaceable. A later model can implement the same
/// [probability] contract without the session planner knowing.
class RecallEstimator {
  const RecallEstimator();

  /// Probability in `0.0`–`1.0`. New cards have not been recalled yet.
  double probability({
    required CardSchedule? schedule,
    required DateTime now,
    required bool isNew,
  }) {
    if (isNew ||
        schedule == null ||
        schedule.state == CardLearningState.newCard) {
      return 0;
    }

    final elapsed = _elapsedSeconds(schedule, now);
    final stability = math.max(schedule.interval.inSeconds, 1);
    final ratio = elapsed / stability;
    var recall = math.pow(0.5, ratio).toDouble();

    if (schedule.state == CardLearningState.learning) {
      recall *= 0.75;
    }
    if (schedule.incorrectCount > 0) {
      final penalty = math.min(0.4, schedule.incorrectCount * 0.08);
      recall *= 1 - penalty;
    }
    if (schedule.consecutiveGoodCount > 0) {
      recall += math.min(0.12, schedule.consecutiveGoodCount * 0.02);
    }

    return recall.clamp(0.0, 0.99);
  }

  double _elapsedSeconds(CardSchedule schedule, DateTime now) {
    final reviewed = schedule.lastReviewedAt;
    if (reviewed != null) {
      final elapsed = now.difference(reviewed).inSeconds;
      return elapsed < 0 ? 0 : elapsed.toDouble();
    }
    if (schedule.interval.inSeconds > 0) {
      return schedule.interval.inSeconds.toDouble();
    }
    final overdue = now.difference(schedule.dueAt).inSeconds;
    return overdue < 0 ? 0 : overdue.toDouble();
  }
}

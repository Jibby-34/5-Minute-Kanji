import 'dart:math' as math;

import '../core/models/card_schedule.dart';
import '../core/models/review.dart';
import 'initial_known_card_schedule.dart';
import 'srs_scheduler.dart';

/// Deterministic interval scheduler. Replace this class with FSRS later.
class SrsEngine implements SrsScheduler {
  const SrsEngine();

  static const double defaultEase = 2.5;
  static const double minEase = 1.3;
  static const Duration againInterval = Duration(minutes: 1);
  static const Duration learningHardInterval = Duration(minutes: 10);

  /// Delay after Learn before the card is eligible for retrieval.
  /// Tune independently of Again / Hard / Good intervals.
  static const Duration newLearnInterval = Duration(minutes: 10);
  static const Duration graduatingInterval = Duration(days: 1);

  /// Nominal center of the first Mark-as-Known interval (~30 days).
  /// The actual first due date is scattered by
  /// [calculateInitialKnownCardSchedule]. Again / Good do not use this.
  static const Duration knownInterval = Duration(days: 30);

  @override
  CardSchedule introduce({
    required CardSchedule current,
    required DateTime now,
  }) {
    if (current.state != CardLearningState.newCard) return current;
    return current.copyWith(
      state: CardLearningState.learning,
      interval: newLearnInterval,
      dueAt: now.add(newLearnInterval),
    );
  }

  @override
  CardSchedule markAsKnown({
    required CardSchedule current,
    required DateTime now,
    Duration? interval,
  }) {
    if (current.state != CardLearningState.newCard) return current;
    final initial =
        interval ?? calculateInitialKnownCardSchedule(current.cardId);
    return current.copyWith(
      state: CardLearningState.review,
      interval: initial,
      dueAt: now.add(initial),
    );
  }

  @override
  CardSchedule schedule({
    required CardSchedule current,
    required ReviewResult result,
    required DateTime now,
  }) {
    return switch (result) {
      ReviewResult.again => _again(current, now),
      ReviewResult.hard => _hard(current, now),
      ReviewResult.good => _good(current, now),
    };
  }

  CardSchedule _again(CardSchedule current, DateTime now) {
    return current.copyWith(
      state: CardLearningState.learning,
      reviewCount: current.reviewCount + 1,
      incorrectCount: current.incorrectCount + 1,
      interval: againInterval,
      dueAt: now.add(againInterval),
      ease: math.max(minEase, current.ease - 0.2),
      lastReviewedAt: now,
      consecutiveGoodCount: 0,
    );
  }

  CardSchedule _hard(CardSchedule current, DateTime now) {
    final inReview = current.state == CardLearningState.review;
    final interval = inReview
        ? _scaledInterval(current.interval, 1.2, minimum: learningHardInterval)
        : learningHardInterval;
    return current.copyWith(
      state: inReview ? CardLearningState.review : CardLearningState.learning,
      reviewCount: current.reviewCount + 1,
      correctCount: current.correctCount + 1,
      interval: interval,
      dueAt: now.add(interval),
      ease: math.max(minEase, current.ease - 0.15),
      lastReviewedAt: now,
      consecutiveGoodCount: 0,
    );
  }

  CardSchedule _good(CardSchedule current, DateTime now) {
    if (current.state == CardLearningState.review) {
      final interval = _scaledInterval(
        current.interval,
        current.ease,
        minimum: graduatingInterval,
      );
      return current.copyWith(
        state: CardLearningState.review,
        reviewCount: current.reviewCount + 1,
        correctCount: current.correctCount + 1,
        interval: interval,
        dueAt: now.add(interval),
        lastReviewedAt: now,
        consecutiveGoodCount: current.consecutiveGoodCount + 1,
      );
    }

    return current.copyWith(
      state: CardLearningState.review,
      reviewCount: current.reviewCount + 1,
      correctCount: current.correctCount + 1,
      interval: graduatingInterval,
      dueAt: now.add(graduatingInterval),
      lastReviewedAt: now,
      consecutiveGoodCount: current.consecutiveGoodCount + 1,
    );
  }

  Duration _scaledInterval(
    Duration current,
    double factor, {
    required Duration minimum,
  }) {
    final seconds = math.max(
      minimum.inSeconds,
      (current.inSeconds * factor).round(),
    );
    return Duration(seconds: seconds);
  }
}

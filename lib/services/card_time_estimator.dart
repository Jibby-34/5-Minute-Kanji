import 'dart:math' as math;

import '../core/models/card_schedule.dart';
import '../core/models/review_duration.dart';

/// How long a card is expected to take. Separate from how important it is.
///
/// With no recorded reviews, the fixed paces are 26s for a new kanji, 21s
/// while it is still in learning, 18s for a short-interval review, and 13s
/// once the interval reaches [matureInterval]. Each is the previous default
/// raised by 25% and rounded to the nearest second.
///
/// Completed reviews replace those defaults gradually. Each pace keeps an
/// exponentially weighted duration. A pace with only a few samples is pulled
/// back toward its default, and toward the user's overall pace once other
/// kinds of cards have been timed too.
class CardTimeEstimator {
  const CardTimeEstimator({
    this.newCard = const Duration(seconds: 26),
    this.learningCard = const Duration(seconds: 21),
    this.reviewCard = const Duration(seconds: 18),
    this.matureCard = const Duration(seconds: 13),
    this.matureInterval = const Duration(days: 21),
    this.model = ReviewDurationModel.empty,
  });

  /// Share of a new sample applied to the smoothed pace. The rest stays put,
  /// so one review cannot swing the next session on its own.
  static const alpha = 0.3;

  /// Samples in one pace before that pace is used on its own.
  static const fullTrustCount = 8;

  /// Active time shorter than this is a missed tap or a clock that did not move.
  static const minValidDuration = Duration(seconds: 1);

  /// Active time longer than this was left open. It is not a finished card.
  static const maxValidDuration = Duration(seconds: 180);

  static const minEstimate = Duration(seconds: 4);
  static const maxEstimate = Duration(seconds: 90);

  /// How hard a sparse pace is held to its own default when the global pace
  /// disagrees. The rest of that anchor is the global pace.
  static const priorAnchorWeight = 0.65;

  final Duration newCard;
  final Duration learningCard;
  final Duration reviewCard;
  final Duration matureCard;
  final Duration matureInterval;
  final ReviewDurationModel model;

  CardTimeEstimator withModel(ReviewDurationModel model) {
    return CardTimeEstimator(
      newCard: newCard,
      learningCard: learningCard,
      reviewCard: reviewCard,
      matureCard: matureCard,
      matureInterval: matureInterval,
      model: model,
    );
  }

  /// New, young, or mature from SRS state at the moment of the review.
  ///
  /// Young covers cards still in learning and review cards whose interval is
  /// shorter than [matureInterval], including cards sent back by Again.
  /// Mature is a review card at or beyond that interval. Overdue cards stay
  /// in the pace their interval already implies. Handwriting is part of the
  /// card, not a separate pace.
  ReviewPace paceFor(CardSchedule? schedule, {required bool isNew}) {
    if (isNew ||
        schedule == null ||
        schedule.state == CardLearningState.newCard) {
      return ReviewPace.newCard;
    }
    if (schedule.state == CardLearningState.review &&
        schedule.interval >= matureInterval) {
      return ReviewPace.mature;
    }
    return ReviewPace.young;
  }

  /// Positive, bounded expected duration for one eligible card.
  Duration estimate(CardSchedule? schedule, {required bool isNew}) {
    final prior = _prior(schedule, isNew: isNew);
    final stats = model.statsFor(paceFor(schedule, isNew: isNew));
    if (!stats.hasObservations) return prior;

    final priorSeconds = prior.inMilliseconds / 1000.0;
    final trust = math.min(1.0, stats.count / fullTrustCount);
    final blended =
        trust * stats.seconds + (1 - trust) * _anchor(priorSeconds, stats);
    return Duration(seconds: _boundedSeconds(blended).round());
  }

  /// Folds one finished, active duration into [model].
  ///
  /// Returns null when the sample must not change future estimates. The same
  /// review must not be passed twice; the caller records each completion once.
  ReviewDurationModel? learn(
    ReviewDurationModel model, {
    required CardSchedule? schedule,
    required bool isNew,
    required Duration duration,
  }) {
    if (!isUsableDuration(duration)) return null;
    final sampleSeconds = duration.inMilliseconds / 1000.0;
    final pace = paceFor(schedule, isNew: isNew);
    final priorSeconds = _prior(schedule, isNew: isNew).inMilliseconds / 1000.0;
    final global = _update(model.global, sampleSeconds, priorSeconds);
    final category = _update(model.statsFor(pace), sampleSeconds, priorSeconds);
    return model.withPace(pace, category).copyWith(global: global);
  }

  static bool isUsableDuration(Duration duration) {
    return !duration.isNegative &&
        duration >= minValidDuration &&
        duration <= maxValidDuration;
  }

  Duration _prior(CardSchedule? schedule, {required bool isNew}) {
    if (isNew ||
        schedule == null ||
        schedule.state == CardLearningState.newCard) {
      return newCard;
    }
    if (schedule.state == CardLearningState.learning) return learningCard;
    if (schedule.interval >= matureInterval) return matureCard;
    return reviewCard;
  }

  /// Sparse anchor. With no other paces recorded, this is the category
  /// default. Once other cards have been timed, a fraction of the global
  /// pace is mixed in so a couple of odd samples cannot run away, without
  /// letting a fast mature history pretend new cards are already fast.
  double _anchor(double priorSeconds, PaceStats stats) {
    final others = model.global.count - stats.count;
    if (others <= 0 || !model.global.hasObservations) return priorSeconds;
    return priorAnchorWeight * priorSeconds +
        (1 - priorAnchorWeight) * model.global.seconds;
  }

  PaceStats _update(
    PaceStats stats,
    double sampleSeconds,
    double priorSeconds,
  ) {
    final belief = stats.hasObservations ? stats.seconds : priorSeconds;
    final adjusted = _winsorize(sampleSeconds, belief);
    final next = belief + alpha * (adjusted - belief);
    return PaceStats(
      ewmaMs: (_boundedSeconds(next) * 1000).round(),
      count: stats.count + 1,
    );
  }

  /// Limits how far one sample may pull the current belief.
  double _winsorize(double sampleSeconds, double belief) {
    final low = math.max(minEstimate.inSeconds.toDouble(), belief * 0.5);
    final high = math.min(120.0, math.max(belief * 2, belief + 8));
    final ceiling = high < low ? low : high;
    return sampleSeconds.clamp(low, ceiling).toDouble();
  }

  double _boundedSeconds(double seconds) {
    final low = minEstimate.inSeconds.toDouble();
    final high = maxEstimate.inSeconds.toDouble();
    if (seconds < low) return low;
    if (seconds > high) return high;
    return seconds;
  }
}

/// Calm minute estimate. Never claims a session will take exactly the budget.
int estimatedMinutesFor(Duration duration) {
  if (duration.inSeconds <= 0) return 0;
  return (duration.inSeconds / 60).ceil().clamp(1, 999);
}

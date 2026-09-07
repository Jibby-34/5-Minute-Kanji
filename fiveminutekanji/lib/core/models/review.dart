enum ReviewResult { again, hard, good }

/// Answer types a review card can use. MVP implements [handwriting] only.
enum ReviewMode { recognition, recall, handwriting }

class ReviewSessionConfig {
  const ReviewSessionConfig({
    required this.duration,
    this.maxCards,
    this.averageSecondsPerCard = 12,
    this.reviewMode = ReviewMode.handwriting,
  });

  static const fiveMinute = ReviewSessionConfig(
    duration: Duration(minutes: 5),
    averageSecondsPerCard: 12,
    reviewMode: ReviewMode.handwriting,
  );

  final Duration duration;
  final int? maxCards;
  final int averageSecondsPerCard;
  final ReviewMode reviewMode;

  int get effectiveMaxCards {
    if (maxCards != null) return maxCards!;
    final computed = duration.inSeconds / averageSecondsPerCard;
    return computed.isFinite ? computed.round().clamp(1, 999) : 1;
  }

  ReviewSessionConfig copyWith({
    Duration? duration,
    int? maxCards,
    int? averageSecondsPerCard,
    ReviewMode? reviewMode,
  }) {
    return ReviewSessionConfig(
      duration: duration ?? this.duration,
      maxCards: maxCards ?? this.maxCards,
      averageSecondsPerCard:
          averageSecondsPerCard ?? this.averageSecondsPerCard,
      reviewMode: reviewMode ?? this.reviewMode,
    );
  }
}

class SessionSummary {
  const SessionSummary({
    required this.duration,
    required this.reviewedCount,
    required this.successfulCount,
    required this.againCount,
    this.nextReviewAt,
  });

  final Duration duration;
  final int reviewedCount;
  final int successfulCount;
  final int againCount;
  final DateTime? nextReviewAt;
}

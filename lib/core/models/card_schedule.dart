enum CardLearningState { newCard, learning, review }

/// Persistent SRS state for one card. Independent of content source.
class CardSchedule {
  const CardSchedule({
    required this.cardId,
    required this.state,
    required this.reviewCount,
    required this.correctCount,
    required this.incorrectCount,
    required this.dueAt,
    required this.interval,
    required this.ease,
    this.lastReviewedAt,
    this.consecutiveGoodCount = 0,
  });

  factory CardSchedule.fresh(String cardId, DateTime now) {
    return CardSchedule(
      cardId: cardId,
      state: CardLearningState.newCard,
      reviewCount: 0,
      correctCount: 0,
      incorrectCount: 0,
      dueAt: now,
      interval: Duration.zero,
      ease: 2.5,
    );
  }

  final String cardId;
  final CardLearningState state;
  final int reviewCount;
  final int correctCount;
  final int incorrectCount;
  final DateTime dueAt;
  final Duration interval;
  final double ease;
  final DateTime? lastReviewedAt;
  final int consecutiveGoodCount;

  bool isDueAt(DateTime now) => !dueAt.isAfter(now);

  CardSchedule copyWith({
    CardLearningState? state,
    int? reviewCount,
    int? correctCount,
    int? incorrectCount,
    DateTime? dueAt,
    Duration? interval,
    double? ease,
    DateTime? lastReviewedAt,
    int? consecutiveGoodCount,
  }) {
    return CardSchedule(
      cardId: cardId,
      state: state ?? this.state,
      reviewCount: reviewCount ?? this.reviewCount,
      correctCount: correctCount ?? this.correctCount,
      incorrectCount: incorrectCount ?? this.incorrectCount,
      dueAt: dueAt ?? this.dueAt,
      interval: interval ?? this.interval,
      ease: ease ?? this.ease,
      lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
      consecutiveGoodCount: consecutiveGoodCount ?? this.consecutiveGoodCount,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'cardId': cardId,
      'state': state.name,
      'reviewCount': reviewCount,
      'correctCount': correctCount,
      'incorrectCount': incorrectCount,
      'dueAt': dueAt.toIso8601String(),
      'intervalSeconds': interval.inSeconds,
      'ease': ease,
      'lastReviewedAt': lastReviewedAt?.toIso8601String(),
      'consecutiveGoodCount': consecutiveGoodCount,
    };
  }

  static CardSchedule? fromJson(Map<String, dynamic> json) {
    try {
      final cardId = json['cardId'] as String?;
      if (cardId == null || cardId.isEmpty) return null;
      return CardSchedule(
        cardId: cardId,
        state: _stateFromName(json['state'] as String?),
        reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
        correctCount: (json['correctCount'] as num?)?.toInt() ?? 0,
        incorrectCount: (json['incorrectCount'] as num?)?.toInt() ?? 0,
        dueAt: DateTime.parse(json['dueAt'] as String),
        interval: Duration(
          seconds: (json['intervalSeconds'] as num?)?.toInt() ?? 0,
        ),
        ease: (json['ease'] as num?)?.toDouble() ?? 2.5,
        lastReviewedAt: json['lastReviewedAt'] == null
            ? null
            : DateTime.parse(json['lastReviewedAt'] as String),
        consecutiveGoodCount:
            (json['consecutiveGoodCount'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  static CardLearningState _stateFromName(String? name) {
    return switch (name) {
      'learning' => CardLearningState.learning,
      'review' => CardLearningState.review,
      _ => CardLearningState.newCard,
    };
  }
}

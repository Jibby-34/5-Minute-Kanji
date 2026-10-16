/// How established a card is in this user's review history.
///
/// This is learning progress, not the kanji's JLPT level or difficulty.
enum ReviewPace {
  /// Never studied. The learner still has to take in the meaning and writing.
  newCard,

  /// Introduced, but still on a short interval or back in learning.
  young,

  /// A review card whose interval is long enough to treat as established.
  mature,
}

/// One exponentially weighted pace, plus how many reviews produced it.
class PaceStats {
  const PaceStats({this.ewmaMs = 0, this.count = 0});

  static const empty = PaceStats();

  /// Smoothed duration in milliseconds. Zero means this pace is still unused.
  final int ewmaMs;

  final int count;

  bool get hasObservations => count > 0 && ewmaMs > 0;

  double get seconds => ewmaMs / 1000.0;

  Map<String, dynamic> toJson() {
    return {'ewmaMs': ewmaMs < 0 ? 0 : ewmaMs, 'count': count < 0 ? 0 : count};
  }

  /// Drops counts that cannot be a real pace, including older installs that
  /// have no timing block at all.
  static PaceStats fromJson(Object? json) {
    final map = _asStringKeyMap(json);
    if (map == null) return empty;
    final count = (map['count'] as num?)?.toInt() ?? 0;
    final ewmaMs = (map['ewmaMs'] as num?)?.toInt() ?? 0;
    if (count <= 0 || ewmaMs <= 0) return empty;
    // Longer than a single card can honestly take. Treat it as unset so one
    // corrupt value cannot pin every future session.
    if (ewmaMs > const Duration(minutes: 15).inMilliseconds) return empty;
    return PaceStats(ewmaMs: ewmaMs, count: count);
  }
}

/// Compact pace memory for every review and for each card category.
///
/// Stored with the rest of progress. Missing data is an empty model, which
/// keeps the original fixed estimates until real reviews arrive.
class ReviewDurationModel {
  const ReviewDurationModel({
    this.global = PaceStats.empty,
    this.newCards = PaceStats.empty,
    this.young = PaceStats.empty,
    this.mature = PaceStats.empty,
  });

  static const empty = ReviewDurationModel();

  final PaceStats global;
  final PaceStats newCards;
  final PaceStats young;
  final PaceStats mature;

  PaceStats statsFor(ReviewPace pace) {
    return switch (pace) {
      ReviewPace.newCard => newCards,
      ReviewPace.young => young,
      ReviewPace.mature => mature,
    };
  }

  ReviewDurationModel withPace(ReviewPace pace, PaceStats stats) {
    return switch (pace) {
      ReviewPace.newCard => ReviewDurationModel(
        global: global,
        newCards: stats,
        young: young,
        mature: mature,
      ),
      ReviewPace.young => ReviewDurationModel(
        global: global,
        newCards: newCards,
        young: stats,
        mature: mature,
      ),
      ReviewPace.mature => ReviewDurationModel(
        global: global,
        newCards: newCards,
        young: young,
        mature: stats,
      ),
    };
  }

  ReviewDurationModel copyWith({PaceStats? global}) {
    return ReviewDurationModel(
      global: global ?? this.global,
      newCards: newCards,
      young: young,
      mature: mature,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'global': global.toJson(),
      'newCards': newCards.toJson(),
      'young': young.toJson(),
      'mature': mature.toJson(),
    };
  }

  static ReviewDurationModel fromJson(Object? json) {
    final map = _asStringKeyMap(json);
    if (map == null) return empty;
    return ReviewDurationModel(
      global: PaceStats.fromJson(map['global']),
      newCards: PaceStats.fromJson(map['newCards']),
      young: PaceStats.fromJson(map['young']),
      mature: PaceStats.fromJson(map['mature']),
    );
  }
}

Map<String, dynamic>? _asStringKeyMap(Object? value) {
  if (value == null) return null;
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return null;
}

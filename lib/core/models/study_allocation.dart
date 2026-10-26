import 'dart:math' as math;

/// How today's recommended sitting splits between reviews and new kanji.
///
/// Counts are cards in the sitting. A new kanji is one card, while its
/// seconds include both showings the session reserves: the introduction and
/// the retrieval before the sitting ends. Review seconds are one showing.
/// The two durations add up to the sitting's estimate.
class StudyAllocation {
  const StudyAllocation({
    this.reviewCards = 0,
    this.reviewSeconds = 0,
    this.newCards = 0,
    this.newSeconds = 0,
  });

  static const empty = StudyAllocation();

  final int reviewCards;
  final int reviewSeconds;
  final int newCards;
  final int newSeconds;

  /// Sum of the known category durations. A missing estimate contributes
  /// nothing here; [totalKnown] says whether that sum is the whole sitting.
  int get totalSeconds {
    final reviews = reviewSeconds > 0 ? reviewSeconds : 0;
    final fresh = newSeconds > 0 ? newSeconds : 0;
    return reviews + fresh;
  }

  /// False when reviews are waiting and none of them were timed.
  bool get reviewTimeKnown => reviewCards <= 0 || reviewSeconds > 0;

  /// False when new kanji are waiting and none of them were timed.
  bool get newTimeKnown => newCards <= 0 || newSeconds > 0;

  bool get totalKnown => reviewTimeKnown && newTimeKnown;

  /// Widths of the two bar segments inside [width].
  ///
  /// Proportions follow seconds. A category that has time keeps at least
  /// [minimum] pixels when both are present, unless the bar is too narrow
  /// for that. The gap is left for the caller to paint between them.
  ({double reviews, double fresh}) segmentWidths({
    required double width,
    double gap = 3,
    double minimum = 8,
  }) {
    if (!width.isFinite || width <= 0) {
      return (reviews: 0, fresh: 0);
    }

    final reviews = reviewSeconds > 0 ? reviewSeconds : 0;
    final fresh = newSeconds > 0 ? newSeconds : 0;
    if (reviews == 0 && fresh == 0) return (reviews: 0, fresh: 0);
    if (reviews == 0) return (reviews: 0, fresh: width);
    if (fresh == 0) return (reviews: width, fresh: 0);

    final gapWidth = math.min(math.max(gap, 0), width);
    final available = width - gapWidth;
    if (available <= 0) return (reviews: 0, fresh: 0);

    final total = reviews + fresh;
    var reviewWidth = available * reviews / total;
    var freshWidth = available - reviewWidth;
    final floor = math.min(math.max(minimum, 0.0), available / 2);
    if (reviewWidth < floor) {
      reviewWidth = floor;
      freshWidth = available - floor;
    } else if (freshWidth < floor) {
      freshWidth = floor;
      reviewWidth = available - floor;
    }
    return (reviews: reviewWidth, fresh: freshWidth);
  }
}

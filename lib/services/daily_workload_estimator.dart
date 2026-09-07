/// Approximate daily study time created by a chosen new-kanji rate.
///
/// Isolated from SRS scheduling so the model can be replaced later with
/// measured review times. Assumptions are fields, not buried magic numbers.
class DailyWorkloadEstimator {
  const DailyWorkloadEstimator({
    this.secondsPerNewLearn = 30,
    this.reviewsPerNewCardLow = 3.5,
    this.reviewsPerNewCardHigh = 5.0,
  });

  /// Learn intro + practice writing for one new kanji.
  final int secondsPerNewLearn;

  /// Conservative reviews each new card is expected to generate per day
  /// once the SRS pipeline is running (same-day retrieval plus later due).
  final double reviewsPerNewCardLow;

  /// Heavier early-SRS review load per new card per day.
  final double reviewsPerNewCardHigh;

  DailyWorkloadEstimate estimate({
    required int newKanjiPerDay,
    required int averageSecondsPerCard,
  }) {
    if (newKanjiPerDay <= 0) {
      return const DailyWorkloadEstimate(minMinutes: 0, maxMinutes: 0);
    }

    final learnSeconds = newKanjiPerDay * secondsPerNewLearn;
    final reviewSecondsLow =
        newKanjiPerDay * reviewsPerNewCardLow * averageSecondsPerCard;
    final reviewSecondsHigh =
        newKanjiPerDay * reviewsPerNewCardHigh * averageSecondsPerCard;

    final minMinutes = _toMinutes(learnSeconds + reviewSecondsLow);
    final maxMinutes = _toMinutes(learnSeconds + reviewSecondsHigh);
    return DailyWorkloadEstimate(
      minMinutes: minMinutes,
      maxMinutes: maxMinutes < minMinutes ? minMinutes : maxMinutes,
    );
  }

  int _toMinutes(double seconds) {
    if (seconds <= 0) return 0;
    return (seconds / 60).round().clamp(1, 999);
  }
}

class DailyWorkloadEstimate {
  const DailyWorkloadEstimate({
    required this.minMinutes,
    required this.maxMinutes,
  });

  final int minMinutes;
  final int maxMinutes;

  /// User-facing label. Clearly an estimate, not a guarantee.
  String get label {
    if (minMinutes <= 0 && maxMinutes <= 0) {
      return 'Estimated daily study time: ~0 min';
    }
    if (minMinutes == maxMinutes) {
      return 'Estimated daily study time: ~$minMinutes min';
    }
    return 'Estimated daily study time: ~$minMinutes–$maxMinutes min';
  }
}

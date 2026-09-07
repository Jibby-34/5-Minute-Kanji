import 'package:flutter_test/flutter_test.dart';
import 'package:fiveminutekanji/services/daily_workload_estimator.dart';

void main() {
  const estimator = DailyWorkloadEstimator();

  test('five new kanji estimates around 6-9 minutes', () {
    final estimate = estimator.estimate(
      newKanjiPerDay: 5,
      averageSecondsPerCard: 12,
    );

    expect(estimate.minMinutes, inInclusiveRange(5, 8));
    expect(estimate.maxMinutes, inInclusiveRange(estimate.minMinutes, 12));
    expect(estimate.label, contains('Estimated daily study time:'));
    expect(estimate.label, contains('~'));
  });

  test('raising the daily new-kanji rate increases the estimate', () {
    final five = estimator.estimate(
      newKanjiPerDay: 5,
      averageSecondsPerCard: 12,
    );
    final twenty = estimator.estimate(
      newKanjiPerDay: 20,
      averageSecondsPerCard: 12,
    );

    expect(twenty.minMinutes, greaterThan(five.minMinutes));
    expect(twenty.maxMinutes, greaterThan(five.maxMinutes));
  });

  test('zero new kanji estimates no added study time', () {
    final estimate = estimator.estimate(
      newKanjiPerDay: 0,
      averageSecondsPerCard: 12,
    );

    expect(estimate.minMinutes, 0);
    expect(estimate.maxMinutes, 0);
    expect(estimate.label, 'Estimated daily study time: ~0 min');
  });
}

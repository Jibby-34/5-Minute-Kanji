import 'package:flutter_test/flutter_test.dart';
import 'package:fiveminutekanji/core/models/study_allocation.dart';
import 'package:fiveminutekanji/core/utils/time_format.dart';

void main() {
  test('missing seconds stay unknown instead of becoming zero', () {
    const plan = StudyAllocation(
      reviewCards: 2,
      reviewSeconds: 0,
      newCards: 1,
      newSeconds: 40,
    );

    expect(plan.reviewTimeKnown, isFalse);
    expect(plan.newTimeKnown, isTrue);
    expect(plan.totalKnown, isFalse);
    expect(plan.totalSeconds, 40);
    expect(formatPlanDuration(plan.newSeconds), '40 sec');
  });

  test('an empty plan is a known zero', () {
    expect(StudyAllocation.empty.totalKnown, isTrue);
    expect(StudyAllocation.empty.totalSeconds, 0);
    expect(StudyAllocation.empty.reviewTimeKnown, isTrue);
    expect(StudyAllocation.empty.newTimeKnown, isTrue);
  });

  test('segment widths follow time and keep a short share visible', () {
    const crowded = StudyAllocation(
      reviewCards: 1,
      reviewSeconds: 13,
      newCards: 20,
      newSeconds: 1040,
    );
    final widths = crowded.segmentWidths(width: 303);

    expect(widths.reviews, greaterThanOrEqualTo(8));
    expect(widths.reviews + widths.fresh + 3, closeTo(303, 0.01));
    expect(widths.reviews / widths.fresh, greaterThan(13 / 1040));

    const timed = StudyAllocation(
      reviewCards: 3,
      reviewSeconds: 54,
      newCards: 2,
      newSeconds: 104,
    );
    final split = timed.segmentWidths(width: 303);
    expect(split.reviews / split.fresh, closeTo(54 / 104, 0.001));
    expect(split.reviews / split.fresh, isNot(closeTo(3 / 2, 0.05)));
  });

  test('one category fills the bar and the other is absent', () {
    const reviews = StudyAllocation(reviewCards: 4, reviewSeconds: 72);
    final onlyReviews = reviews.segmentWidths(width: 280);
    expect(onlyReviews.reviews, 280);
    expect(onlyReviews.fresh, 0);

    const fresh = StudyAllocation(newCards: 2, newSeconds: 104);
    final onlyNew = fresh.segmentWidths(width: 280);
    expect(onlyNew.reviews, 0);
    expect(onlyNew.fresh, 280);

    expect(StudyAllocation.empty.segmentWidths(width: 280).reviews, 0);
    expect(StudyAllocation.empty.segmentWidths(width: 280).fresh, 0);
  });
}

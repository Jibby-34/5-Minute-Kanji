import 'package:flutter_test/flutter_test.dart';
import 'package:fiveminutekanji/core/models/start_of_day.dart';
import 'package:fiveminutekanji/core/utils/time_format.dart';

void main() {
  test('greeting follows local time of day', () {
    expect(greetingFor(DateTime(2026, 9, 3, 5)), 'Good Morning');
    expect(greetingFor(DateTime(2026, 9, 3, 11, 59)), 'Good Morning');
    expect(greetingFor(DateTime(2026, 9, 3, 12)), 'Good Afternoon');
    expect(greetingFor(DateTime(2026, 9, 3, 16, 59)), 'Good Afternoon');
    expect(greetingFor(DateTime(2026, 9, 3, 17)), 'Good Evening');
    expect(greetingFor(DateTime(2026, 9, 3, 21)), 'Good Evening');
  });

  test('late-night hours keep an evening greeting', () {
    expect(greetingFor(DateTime(2026, 9, 3, 0)), 'Good Evening');
    expect(greetingFor(DateTime(2026, 9, 3, 2, 30)), 'Good Evening');
    expect(greetingFor(DateTime(2026, 9, 3, 4, 59)), 'Good Evening');
  });

  test('start of day formats in 12-hour time', () {
    expect(formatStartOfDay(const StartOfDay(hour: 4)), '4:00 AM');
    expect(formatStartOfDay(const StartOfDay(hour: 0)), '12:00 AM');
    expect(formatStartOfDay(const StartOfDay(hour: 12, minute: 5)), '12:05 PM');
    expect(formatStartOfDay(const StartOfDay(hour: 16, minute: 30)), '4:30 PM');
  });

  test('plan durations keep seconds and add up in words', () {
    expect(roundPlanSeconds(0), 0);
    expect(roundPlanSeconds(-4), 0);
    expect(roundPlanSeconds(4), 0);
    expect(roundPlanSeconds(5), 10);
    expect(roundPlanSeconds(13), 10);
    expect(roundPlanSeconds(14), 10);
    expect(roundPlanSeconds(15), 20);
    expect(roundPlanSeconds(54), 50);
    expect(roundPlanSeconds(158), 160);
    expect(formatPlanDuration(0), '0 min');
    expect(formatPlanDuration(-4), '0 min');
    expect(formatPlanDuration(1), '0 min');
    expect(formatPlanDuration(13), '10 sec');
    expect(formatPlanDuration(40), '40 sec');
    expect(formatPlanDuration(54), '50 sec');
    expect(formatPlanDuration(60), '1 min');
    expect(formatPlanDuration(90), '1 min 30 sec');
    expect(formatPlanDuration(260), '4 min 20 sec');
    expect(formatPlanDurationSpoken(0), '0 minutes');
    expect(formatPlanDurationSpoken(1), '0 minutes');
    expect(formatPlanDurationSpoken(10), '10 seconds');
    expect(formatPlanDurationSpoken(60), '1 minute');
    expect(formatPlanDurationSpoken(260), '4 minutes 20 seconds');
    expect(formatPlanDuration(560 + 160), '12 min');
  });

  test('next review labels follow the study-day boundary', () {
    const start = StartOfDay(hour: 4);
    final evening = DateTime(2026, 9, 8, 22);
    expect(
      formatNextReview(DateTime(2026, 9, 9, 3, 59), evening, startOfDay: start),
      'later today',
    );
    expect(
      formatNextReview(DateTime(2026, 9, 9, 4), evening, startOfDay: start),
      'tomorrow',
    );
  });
}

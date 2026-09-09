import 'package:flutter_test/flutter_test.dart';
import 'package:fiveminutekanji/core/models/start_of_day.dart';
import 'package:fiveminutekanji/core/utils/time_format.dart';

void main() {
  test('greeting follows local time of day', () {
    expect(greetingFor(DateTime(2026, 9, 3, 5)), 'Good morning');
    expect(greetingFor(DateTime(2026, 9, 3, 11, 59)), 'Good morning');
    expect(greetingFor(DateTime(2026, 9, 3, 12)), 'Good afternoon');
    expect(greetingFor(DateTime(2026, 9, 3, 16, 59)), 'Good afternoon');
    expect(greetingFor(DateTime(2026, 9, 3, 17)), 'Good evening');
    expect(greetingFor(DateTime(2026, 9, 3, 21)), 'Good evening');
  });

  test('late-night hours keep an evening greeting', () {
    expect(greetingFor(DateTime(2026, 9, 3, 0)), 'Good evening');
    expect(greetingFor(DateTime(2026, 9, 3, 2, 30)), 'Good evening');
    expect(greetingFor(DateTime(2026, 9, 3, 4, 59)), 'Good evening');
  });

  test('start of day formats in 12-hour time', () {
    expect(formatStartOfDay(const StartOfDay(hour: 4)), '4:00 AM');
    expect(formatStartOfDay(const StartOfDay(hour: 0)), '12:00 AM');
    expect(formatStartOfDay(const StartOfDay(hour: 12, minute: 5)), '12:05 PM');
    expect(formatStartOfDay(const StartOfDay(hour: 16, minute: 30)), '4:30 PM');
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

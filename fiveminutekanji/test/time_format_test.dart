import 'package:flutter_test/flutter_test.dart';
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
}

import 'package:flutter_test/flutter_test.dart';
import 'package:fiveminutekanji/core/models/start_of_day.dart';

void main() {
  const start = StartOfDay(hour: 4);

  test('4:00 AM begins the new study date', () {
    expect(start.studyDate(DateTime(2026, 9, 9, 4)), DateTime(2026, 9, 9));
    expect(start.studyDate(DateTime(2026, 9, 9, 8)), DateTime(2026, 9, 9));
  });

  test('3:59 AM still belongs to the previous study date', () {
    expect(start.studyDate(DateTime(2026, 9, 9, 3, 59)), DateTime(2026, 9, 8));
    expect(start.studyDate(DateTime(2026, 9, 9)), DateTime(2026, 9, 8));
  });

  test('midnight start keeps calendar dates', () {
    const midnight = StartOfDay(hour: 0);
    expect(midnight.studyDate(DateTime(2026, 9, 9)), DateTime(2026, 9, 9));
    expect(
      midnight.studyDate(DateTime(2026, 9, 8, 23, 59)),
      DateTime(2026, 9, 8),
    );
  });

  test('custom hour and minute are honored at the boundary', () {
    const late = StartOfDay(hour: 6, minute: 30);
    expect(late.studyDate(DateTime(2026, 9, 9, 6, 29)), DateTime(2026, 9, 8));
    expect(late.studyDate(DateTime(2026, 9, 9, 6, 30)), DateTime(2026, 9, 9));
  });

  test('start of next study day is the configured clock time', () {
    expect(
      start.startOfNextStudyDay(DateTime(2026, 9, 8, 22)),
      DateTime(2026, 9, 9, 4),
    );
    expect(
      start.startOfNextStudyDay(DateTime(2026, 9, 9, 3, 59)),
      DateTime(2026, 9, 9, 4),
    );
    expect(
      start.startOfNextStudyDay(DateTime(2026, 9, 9, 4)),
      DateTime(2026, 9, 10, 4),
    );
  });

  test('same-study-day comparison spans midnight', () {
    expect(
      start.isSameStudyDay(
        DateTime(2026, 9, 8, 22),
        DateTime(2026, 9, 9, 3, 59),
      ),
      isTrue,
    );
    expect(
      start.isSameStudyDay(
        DateTime(2026, 9, 9, 3, 59),
        DateTime(2026, 9, 9, 4),
      ),
      isFalse,
    );
  });
}

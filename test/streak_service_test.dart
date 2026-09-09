import 'package:flutter_test/flutter_test.dart';
import 'package:fiveminutekanji/core/models/progress.dart';
import 'package:fiveminutekanji/core/models/start_of_day.dart';
import 'package:fiveminutekanji/services/streak_service.dart';

void main() {
  const service = StreakService();

  test('first completed session starts a streak of one', () {
    final next = service.recordCompletion(
      StreakInfo.empty,
      DateTime(2026, 9, 2, 8),
    );
    expect(next.current, 1);
    expect(next.lastStudyDate, DateTime(2026, 9, 2));
  });

  test('a second session the same day does not increment', () {
    final current = StreakInfo(current: 3, lastStudyDate: DateTime(2026, 9, 2));
    final next = service.recordCompletion(current, DateTime(2026, 9, 2, 21));
    expect(next.current, 3);
  });

  test('studying the next calendar day increments the streak', () {
    final current = StreakInfo(current: 3, lastStudyDate: DateTime(2026, 9, 1));
    final next = service.recordCompletion(current, DateTime(2026, 9, 2, 8));
    expect(next.current, 4);
  });

  test('a skipped day resets the streak', () {
    final current = StreakInfo(
      current: 8,
      lastStudyDate: DateTime(2026, 8, 30),
    );
    final next = service.recordCompletion(current, DateTime(2026, 9, 2, 8));
    expect(next.current, 1);
  });

  test('3:59 AM is still the previous study day', () {
    final current = StreakInfo(current: 3, lastStudyDate: DateTime(2026, 9, 8));
    final next = service.recordCompletion(
      current,
      DateTime(2026, 9, 9, 3, 59),
      startOfDay: const StartOfDay(hour: 4),
    );
    expect(next.current, 3);
    expect(next.lastStudyDate, DateTime(2026, 9, 8));
  });

  test('4:00 AM begins a new streak day', () {
    final current = StreakInfo(current: 3, lastStudyDate: DateTime(2026, 9, 8));
    final next = service.recordCompletion(
      current,
      DateTime(2026, 9, 9, 4),
      startOfDay: const StartOfDay(hour: 4),
    );
    expect(next.current, 4);
    expect(next.lastStudyDate, DateTime(2026, 9, 9));
  });
}

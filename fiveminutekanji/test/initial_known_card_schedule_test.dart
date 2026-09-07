import 'package:flutter_test/flutter_test.dart';
import 'package:fiveminutekanji/services/initial_known_card_schedule.dart';
import 'package:fiveminutekanji/services/srs_engine.dart';

void main() {
  test('one card is scheduled about 30 days out', () {
    final interval = calculateInitialKnownCardSchedule('rtk_001');

    expect(interval.inDays, closeTo(30, 15));
    expect(
      interval.inDays,
      inInclusiveRange(initialKnownMinDays, initialKnownMaxDays),
    );
    expect(interval, Duration(days: interval.inDays));
  });

  test('the same kanji id always maps to the same interval', () {
    final first = calculateInitialKnownCardSchedule('n5-014');
    final second = calculateInitialKnownCardSchedule('n5-014');
    expect(first, second);
    expect(first, isNot(SrsEngine.againInterval));
    expect(first, isNot(SrsEngine.graduatingInterval));
  });

  test('different kanji ids scatter instead of sharing one due day', () {
    final first = calculateInitialKnownCardSchedule('n5-001');
    final second = calculateInitialKnownCardSchedule('n5-002');
    expect(first, isNot(second));
  });

  test('selection order is not an input — only the kanji id is', () {
    final selectedFirst = ['n5-090', 'n5-010', 'n5-050'];
    final selectedSecond = ['n5-010', 'n5-050', 'n5-090'];

    final byFirstOrder = {
      for (final id in selectedFirst) id: calculateInitialKnownCardSchedule(id),
    };
    final bySecondOrder = {
      for (final id in selectedSecond)
        id: calculateInitialKnownCardSchedule(id),
    };

    expect(byFirstOrder, bySecondOrder);
  });

  test('a large id set fills the 15–45 day window', () {
    final days = [
      for (var i = 0; i < 310; i++)
        calculateInitialKnownCardSchedule(
          'n5-${i.toString().padLeft(3, '0')}',
        ).inDays,
    ];

    expect(
      days.every(
        (day) => day >= initialKnownMinDays && day <= initialKnownMaxDays,
      ),
      isTrue,
    );
    expect(days.toSet().length, greaterThanOrEqualTo(25));
    expect(days.contains(initialKnownMinDays), isTrue);
    expect(days.contains(initialKnownMaxDays), isTrue);
  });
}

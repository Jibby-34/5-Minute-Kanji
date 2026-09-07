import 'package:flutter_test/flutter_test.dart';
import 'package:fiveminutekanji/services/session_new_card_budget.dart';

void main() {
  test(
    'a 5-minute sitting introduces a few new cards, not the whole daily cap',
    () {
      expect(
        sessionNewCardLimit(
          sessionCapacity: 25,
          dueReviewCount: 10,
          remainingDaily: 6,
        ),
        inInclusiveRange(1, 3),
      );
    },
  );

  test('a longer sitting can introduce more new cards', () {
    final short = sessionNewCardLimit(
      sessionCapacity: 10,
      dueReviewCount: 0,
      remainingDaily: 6,
    );
    final longer = sessionNewCardLimit(
      sessionCapacity: 25,
      dueReviewCount: 0,
      remainingDaily: 6,
    );
    expect(short, inInclusiveRange(1, 3));
    expect(longer, greaterThan(short));
    expect(longer, lessThanOrEqualTo(6));
  });

  test('never exceeds the remaining daily allowance', () {
    expect(
      sessionNewCardLimit(
        sessionCapacity: 25,
        dueReviewCount: 0,
        remainingDaily: 2,
      ),
      2,
    );
  });

  test('zero remaining daily introduces no new cards', () {
    expect(
      sessionNewCardLimit(
        sessionCapacity: 25,
        dueReviewCount: 8,
        remainingDaily: 0,
      ),
      0,
    );
  });

  test(
    'does not fill every leftover slot with new cards when reviews exist',
    () {
      final limit = sessionNewCardLimit(
        sessionCapacity: 25,
        dueReviewCount: 2,
        remainingDaily: 20,
      );
      expect(limit, lessThan(20));
      expect(limit, lessThanOrEqualTo(10));
    },
  );
}

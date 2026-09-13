import 'package:flutter_test/flutter_test.dart';
import 'package:fiveminutekanji/services/session_new_card_budget.dart';

void main() {
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

  test('0 reviews and 5 new takes every remaining new card', () {
    final budget = sessionCardBudget(
      sessionCapacity: 25,
      dueReviewCount: 0,
      remainingDaily: 5,
    );
    expect(budget.maxNewCards, 5);
    expect(budget.sessionLimit, greaterThanOrEqualTo(5));
  });

  test('0 reviews still takes all new when they exceed the usual cap', () {
    final budget = sessionCardBudget(
      sessionCapacity: 25,
      dueReviewCount: 0,
      remainingDaily: 50,
    );
    expect(budget.maxNewCards, 50);
    expect(budget.sessionLimit, 50);
  });

  test('1 review and 5 new is the last sitting and takes all 5', () {
    final budget = sessionCardBudget(
      sessionCapacity: 25,
      dueReviewCount: 1,
      remainingDaily: 5,
    );
    expect(budget.maxNewCards, 5);
    expect(budget.sessionLimit, greaterThanOrEqualTo(6));
  });

  test('2 reviews and 5 new is the last sitting and takes all 5', () {
    expect(
      sessionNewCardLimit(
        sessionCapacity: 25,
        dueReviewCount: 2,
        remainingDaily: 5,
      ),
      5,
    );
  });

  test('a last sitting grows so leftover new cards are not stranded', () {
    final budget = sessionCardBudget(
      sessionCapacity: 25,
      dueReviewCount: 10,
      remainingDaily: 20,
    );
    expect(budget.maxNewCards, 20);
    expect(budget.sessionLimit, 30);
  });

  test('many reviews pace new cards across remaining sittings', () {
    expect(
      sessionNewCardLimit(
        sessionCapacity: 25,
        dueReviewCount: 30,
        remainingDaily: 5,
      ),
      3,
    );
    expect(
      sessionNewCardLimit(
        sessionCapacity: 25,
        dueReviewCount: 51,
        remainingDaily: 5,
      ),
      2,
    );
  });

  test('an overflowing review load keeps the usual sitting size', () {
    final budget = sessionCardBudget(
      sessionCapacity: 25,
      dueReviewCount: 40,
      remainingDaily: 5,
    );
    expect(budget.maxNewCards, lessThan(5));
    expect(budget.sessionLimit, 25);
  });
}

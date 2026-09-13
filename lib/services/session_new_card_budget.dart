import 'dart:math' as math;

/// How many new kanji this sitting should introduce, and how large the
/// sitting may grow so those cards actually fit.
///
/// Separate from the daily allowance (how many may be encountered today)
/// and from SRS due times (when a card is eligible again).
///
/// Today's new kanji must be learned by the last review of the day. When
/// no reviews remain, the sitting *is* that work: do not report done
/// while unused daily new cards are still unlearned.
class SessionCardBudget {
  const SessionCardBudget({
    required this.maxNewCards,
    required this.sessionLimit,
  });

  final int maxNewCards;
  final int sessionLimit;
}

SessionCardBudget sessionCardBudget({
  required int sessionCapacity,
  required int dueReviewCount,
  required int remainingDaily,
}) {
  if (sessionCapacity <= 0) {
    return const SessionCardBudget(maxNewCards: 0, sessionLimit: 0);
  }

  final remainingNew = remainingDaily < 0 ? 0 : remainingDaily;
  final due = dueReviewCount < 0 ? 0 : dueReviewCount;

  // Every remaining review fits in one sitting — including the 0-review
  // case. This is the last review sitting, so take every remaining new
  // card and grow the queue if the usual cap would leave any behind.
  if (due <= sessionCapacity) {
    final needed = due + remainingNew;
    return SessionCardBudget(
      maxNewCards: remainingNew,
      sessionLimit: needed > sessionCapacity ? needed : sessionCapacity,
    );
  }

  // More review sittings remain. Spread new cards across them so the
  // last sitting still introduces whatever is left.
  final reviewSessionsLeft = (due + sessionCapacity - 1) ~/ sessionCapacity;
  final paced = remainingNew == 0
      ? 0
      : (remainingNew + reviewSessionsLeft - 1) ~/ reviewSessionsLeft;
  final maxNew = math.min(remainingNew, math.min(paced, sessionCapacity));
  return SessionCardBudget(maxNewCards: maxNew, sessionLimit: sessionCapacity);
}

/// How many new kanji this sitting should introduce.
int sessionNewCardLimit({
  required int sessionCapacity,
  required int dueReviewCount,
  required int remainingDaily,
}) {
  return sessionCardBudget(
    sessionCapacity: sessionCapacity,
    dueReviewCount: dueReviewCount,
    remainingDaily: remainingDaily,
  ).maxNewCards;
}

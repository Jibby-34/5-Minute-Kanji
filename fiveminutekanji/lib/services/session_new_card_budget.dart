import 'dart:math' as math;

/// How many new kanji this sitting should introduce.
///
/// Separate from the daily allowance (how many may be encountered today)
/// and from SRS due times (when a card is eligible again).
///
/// Assumptions, easy to retune:
/// - Most of a sitting should stay available for cards that already need review.
/// - New cards scale with session capacity, not leftover daily allowance.
/// - A session with no reviews may introduce more new cards, still not the
///   entire remaining daily cap in a short sitting.
int sessionNewCardLimit({
  required int sessionCapacity,
  required int dueReviewCount,
  required int remainingDaily,
}) {
  if (remainingDaily <= 0 || sessionCapacity <= 0) return 0;

  // ~1 new card per 8 slots when mixing with reviews (~3 in a 25-card sitting).
  // ~1 per 4 slots when nothing is due, so a short session still introduces a few.
  final slotsPerNew = dueReviewCount > 0 ? 8 : 4;
  var target = sessionCapacity ~/ slotsPerNew;
  if (target < 1) target = 1;

  // Never spend more than ~40% of a sitting on brand-new cards.
  final shareCap = math.max(1, (sessionCapacity * 0.4).round());
  target = math.min(target, shareCap);

  return math.min(remainingDaily, math.min(target, sessionCapacity));
}

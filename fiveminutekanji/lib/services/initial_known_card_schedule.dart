/// Initial Mark-as-Known scheduling only.
///
/// Scatters the first review around the nominal 30-day interval so a bulk
/// "Mark as Known" does not land every card on the same day. Once the card
/// is reviewed, normal SRS scheduling takes over — this helper is never used
/// for Again / Good / Hard.

/// Inclusive lower bound of the first Mark-as-Known interval, in days.
const int initialKnownMinDays = 15;

/// Inclusive upper bound of the first Mark-as-Known interval, in days.
const int initialKnownMaxDays = 45;

/// Number of distinct day-buckets in the initial window.
const int initialKnownDaySpan = initialKnownMaxDays - initialKnownMinDays + 1;

/// First-review interval for a card just marked as known.
///
/// Deterministic from [kanjiId]: the same id always maps to the same whole-day
/// offset in [[initialKnownMinDays], [initialKnownMaxDays]]. Selection order,
/// JLPT level, and assumed difficulty are not inputs.
Duration calculateInitialKnownCardSchedule(String kanjiId) {
  final days = initialKnownMinDays + _stableDayBucket(kanjiId);
  return Duration(days: days);
}

int _stableDayBucket(String kanjiId) {
  // FNV-1a 32-bit. Dart's [Object.hashCode] is not a persistence contract.
  var hash = 2166136261;
  for (final unit in kanjiId.codeUnits) {
    hash ^= unit;
    hash = (hash * 16777619) & 0xFFFFFFFF;
  }
  return hash % initialKnownDaySpan;
}

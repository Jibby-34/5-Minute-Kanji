import '../core/models/card_schedule.dart';
import '../core/models/review.dart';

/// Scheduling port. Swap [SrsEngine] for FSRS later without touching UI.
abstract class SrsScheduler {
  const SrsScheduler();

  /// First SRS interval after the Learn flow. Not a review rating.
  CardSchedule introduce({
    required CardSchedule current,
    required DateTime now,
  });

  /// Enter a new card into review with a long initial interval.
  ///
  /// Used when the user already knows the kanji. When [interval] is omitted,
  /// implementations scatter the first due date around ~30 days. Mark as
  /// Known passes a proficiency-adjusted interval. An imported Anki interval
  /// can be passed the same way.
  CardSchedule markAsKnown({
    required CardSchedule current,
    required DateTime now,
    Duration? interval,
  });

  CardSchedule schedule({
    required CardSchedule current,
    required ReviewResult result,
    required DateTime now,
  });
}

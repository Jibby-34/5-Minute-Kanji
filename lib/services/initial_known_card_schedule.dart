import '../core/models/card_schedule.dart';
import '../core/models/placement.dart';

/// Initial scheduling for kanji marked known by hand or the placement test.
///
/// [calculateProficiencyAdjustedKnownInterval] is the interval those kanji
/// receive the moment they leave the new-card state. Later Again / Good
/// reviews never call it. [calculateInitialKnownCardSchedule] remains only
/// for a card with no difficulty score, and for the scheduler's default when
/// the caller does not pass an interval.

/// Inclusive lower bound of the legacy first-review window, in days.
///
/// Learned-kanji backfill still treats an interval at least this long as the
/// old Mark-as-Known shape. Personalized intervals use [knownIntervalMinDays].
const int initialKnownMinDays = 15;

/// Inclusive upper bound of the legacy first-review window, in days.
const int initialKnownMaxDays = 45;

/// Number of distinct day-buckets in the legacy window.
const int initialKnownDaySpan = initialKnownMaxDays - initialKnownMinDays + 1;

/// First-review interval when a kanji has no difficulty score.
///
/// Deterministic from [kanjiId]: the same id always maps to the same whole-day
/// offset in [[initialKnownMinDays], [initialKnownMaxDays]].
Duration calculateInitialKnownCardSchedule(String kanjiId) {
  final days =
      initialKnownMinDays + _stableDayBucket(kanjiId, initialKnownDaySpan);
  return Duration(days: days);
}

// --- Proficiency-adjusted initial interval -------------------------------
//
// initialInterval = baseInterval × relativeDifficultyMultiplier,
// then a small per-id scatter, then a clamp to whole days.
// Every constant below is a tuning knob. Nothing else in SRS reads them.

/// [KanjiCard.difficulty] range. 0 means the card has no score.
const int knownDifficultyMin = 1;
const int knownDifficultyMax = 100;

/// Base first-review interval for each proficiency band, in days.
const int knownIntervalBeginnerDays = 14;
const int knownIntervalIntermediateDays = 21;
const int knownIntervalAdvancedDays = 30;
const int knownIntervalExpertDays = 40;

/// Shortest and longest personalized first-review interval, in days.
const int knownIntervalMinDays = 7;
const int knownIntervalMaxDays = 90;

/// How many known kanji it takes before their average fully drives the
/// multiplier. A set of size n is trusted by n / (n + this).
///
/// One or two kanji therefore cannot pin the baseline to an extreme.
const int knownDifficultyBaselinePriorCount = 8;

/// Difficulty points from the user's average that map to the multiplier
/// anchors. Positive means the kanji is easier than that average.
const double knownDifficultyEasierPoints = 15;
const double knownDifficultyMuchEasierPoints = 30;
const double knownDifficultyHarderPoints = 15;
const double knownDifficultyMuchHarderPoints = 30;

const double knownMultiplierMuchEasier = 2.0;
const double knownMultiplierEasier = 1.5;
const double knownMultiplierAverage = 1.0;
const double knownMultiplierHarder = 0.75;
const double knownMultiplierMuchHarder = 0.5;

/// Scatter is a fraction of the personalized interval, and never wider than
/// [knownIntervalScatterMaxDays]. That keeps a large batch off a single due
/// day without washing out the proficiency and difficulty gaps.
const double knownIntervalScatterFraction = 0.10;
const int knownIntervalScatterMinDays = 1;
const int knownIntervalScatterMaxDays = 3;

/// Placement posterior (1–100 learning-path position) band edges.
///
/// Below [knownProficiencyIntermediateFrom] is beginner. The self-assessment
/// enum has no Advanced value; a finished test lands there by this scale.
const double knownProficiencyIntermediateFrom = 30;
const double knownProficiencyAdvancedFrom = 55;
const double knownProficiencyExpertFrom = 80;

/// Bands used only to choose [knownIntervalBaseDays]. Stored proficiency stays
/// on [PlacementProgress]: the test's difficulty estimate, or the
/// self-assessment when the test was skipped.
enum KnownIntervalProficiency { beginner, intermediate, advanced, expert }

int knownIntervalBaseDays(KnownIntervalProficiency proficiency) {
  return switch (proficiency) {
    KnownIntervalProficiency.beginner => knownIntervalBeginnerDays,
    KnownIntervalProficiency.intermediate => knownIntervalIntermediateDays,
    KnownIntervalProficiency.advanced => knownIntervalAdvancedDays,
    KnownIntervalProficiency.expert => knownIntervalExpertDays,
  };
}

bool knownDifficultyIsValid(int difficulty) {
  return difficulty >= knownDifficultyMin && difficulty <= knownDifficultyMax;
}

/// Maps a finished placement estimate onto the four interval bands.
KnownIntervalProficiency proficiencyFromEstimatedDifficulty(double estimate) {
  if (estimate < knownProficiencyIntermediateFrom) {
    return KnownIntervalProficiency.beginner;
  }
  if (estimate < knownProficiencyAdvancedFrom) {
    return KnownIntervalProficiency.intermediate;
  }
  if (estimate < knownProficiencyExpertFrom) {
    return KnownIntervalProficiency.advanced;
  }
  return KnownIntervalProficiency.expert;
}

/// Prefers a placement estimate on the 1–100 scale. Otherwise uses the
/// self-assessment. With neither, the historical nominal interval (advanced,
/// 30 days) applies so a missing level does not pretend to be a beginner.
KnownIntervalProficiency proficiencyFromPlacement({
  double? estimatedDifficulty,
  PlacementSelfAssessment? selfAssessment,
}) {
  final estimate = estimatedDifficulty;
  if (estimate != null &&
      estimate >= knownDifficultyMin &&
      estimate <= knownDifficultyMax) {
    return proficiencyFromEstimatedDifficulty(estimate);
  }
  return switch (selfAssessment) {
    PlacementSelfAssessment.newUser ||
    PlacementSelfAssessment.beginner => KnownIntervalProficiency.beginner,
    PlacementSelfAssessment.intermediate =>
      KnownIntervalProficiency.intermediate,
    PlacementSelfAssessment.expert => KnownIntervalProficiency.expert,
    null => KnownIntervalProficiency.advanced,
  };
}

/// How far [easePoints] (positive = easier than the user's average) moves
/// the interval. Piecewise linear between the anchors, flat outside them.
double knownMultiplierForEase(double easePoints) {
  const anchors = <(double, double)>[
    (-knownDifficultyMuchHarderPoints, knownMultiplierMuchHarder),
    (-knownDifficultyHarderPoints, knownMultiplierHarder),
    (0, knownMultiplierAverage),
    (knownDifficultyEasierPoints, knownMultiplierEasier),
    (knownDifficultyMuchEasierPoints, knownMultiplierMuchEasier),
  ];
  if (easePoints <= anchors.first.$1) return anchors.first.$2;
  if (easePoints >= anchors.last.$1) return anchors.last.$2;
  for (var index = 0; index < anchors.length - 1; index++) {
    final start = anchors[index];
    final end = anchors[index + 1];
    if (easePoints > end.$1) continue;
    final span = end.$1 - start.$1;
    if (span == 0) return end.$2;
    final t = (easePoints - start.$1) / span;
    return start.$2 + t * (end.$2 - start.$2);
  }
  return knownMultiplierAverage;
}

/// Multiplier for [difficulty] against the user's known-kanji scores.
///
/// An empty list, or a list with no scores in range, returns 1. A small list
/// is shrunk toward 1 so a couple of kanji cannot produce 0.5× or 2.0×.
double knownRelativeDifficultyMultiplier({
  required int difficulty,
  required Iterable<int> knownDifficulties,
}) {
  if (!knownDifficultyIsValid(difficulty)) return knownMultiplierAverage;
  final baseline = _knownDifficultyBaseline(knownDifficulties);
  if (baseline == null) return knownMultiplierAverage;
  final ease = (baseline.average - difficulty) * baseline.confidence;
  return knownMultiplierForEase(ease);
}

/// Whole-day first interval for one known kanji.
///
/// [knownDifficulties] is the known set the average is taken over, including
/// the kanji being initialized when it is part of that set. Scatter is applied
/// after the personalized interval and stays inside a few days of it.
Duration calculateProficiencyAdjustedKnownInterval({
  required String kanjiId,
  required int difficulty,
  required Iterable<int> knownDifficulties,
  required KnownIntervalProficiency proficiency,
}) {
  final base = knownIntervalBaseDays(proficiency);
  final multiplier = knownRelativeDifficultyMultiplier(
    difficulty: difficulty,
    knownDifficulties: knownDifficulties,
  );
  final center = _clampKnownDays((base * multiplier).round());
  final radius = knownIntervalScatterRadius(center);
  final offset = _stableDayBucket(kanjiId, radius * 2 + 1) - radius;
  return Duration(days: _clampKnownDays(center + offset));
}

/// Half-width, in days, of the scatter around an already-personalized interval.
int knownIntervalScatterRadius(int centerDays) {
  final scaled = (centerDays.abs() * knownIntervalScatterFraction).round();
  var radius = scaled < knownIntervalScatterMinDays
      ? knownIntervalScatterMinDays
      : scaled;
  if (radius > knownIntervalScatterMaxDays) {
    radius = knownIntervalScatterMaxDays;
  }
  return radius;
}

/// Kanji that belong in the known-difficulty average.
///
/// New marks set [CardSchedule.introducedAsKnown]. Older marks are recognized
/// the same way the rest of the app already recognizes an unreviewed or
/// just-reviewed known card.
bool scheduleCountsAsKnownKanji(CardSchedule schedule) {
  if (schedule.introducedAsKnown) return true;
  if (schedule.awaitsFirstKnownReview) return true;
  return schedule.state == CardLearningState.review &&
      schedule.reviewCount > 0 &&
      schedule.reviewCount <= 3 &&
      schedule.interval >= const Duration(days: initialKnownMinDays);
}

class _KnownDifficultyBaseline {
  const _KnownDifficultyBaseline({required this.average, required this.count});

  final double average;
  final int count;

  double get confidence {
    if (count <= 0) return 0;
    return count / (count + knownDifficultyBaselinePriorCount);
  }
}

_KnownDifficultyBaseline? _knownDifficultyBaseline(Iterable<int> difficulties) {
  var sum = 0.0;
  var count = 0;
  for (final difficulty in difficulties) {
    if (!knownDifficultyIsValid(difficulty)) continue;
    sum += difficulty;
    count++;
  }
  if (count == 0) return null;
  return _KnownDifficultyBaseline(average: sum / count, count: count);
}

int _clampKnownDays(int days) {
  if (days < knownIntervalMinDays) return knownIntervalMinDays;
  if (days > knownIntervalMaxDays) return knownIntervalMaxDays;
  return days;
}

int _stableDayBucket(String kanjiId, int span) {
  if (span <= 1) return 0;
  // FNV-1a 32-bit. Dart's [Object.hashCode] is not a persistence contract.
  var hash = 2166136261;
  for (final unit in kanjiId.codeUnits) {
    hash ^= unit;
    hash = (hash * 16777619) & 0xFFFFFFFF;
  }
  return hash % span;
}

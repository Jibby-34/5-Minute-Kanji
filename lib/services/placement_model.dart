import 'dart:math' as math;

import '../core/models/curriculum_mode.dart';
import '../core/models/kanji_card.dart';
import '../core/models/placement.dart';
import 'curriculum_priority_service.dart';
import 'due_card_selector.dart';

/// Chance an answer is right even when the kanji is well above the learner.
const double placementGuessProbability = 0.05;

/// Chance an answer is wrong even when the kanji is well below the learner.
const double placementSlipProbability = 0.05;

/// How many difficulty points the knowledge curve takes to rise.
///
/// Kanji near the estimated position stay uncertain instead of forming a
/// hard known/unknown cutoff.
const double placementBoundarySoftness = 7.5;

/// Absolute maximum number of placement questions.
const int placementMaxQuestions = 20;

/// Do not stop before this many answers, unless the pool is smaller.
///
/// Four or five questions can look settled when a self-assessment was off
/// and the answers disagree. The test still ends at [placementMaxQuestions].
const int placementMinQuestions = 12;

/// Stop early once the posterior is at least this concentrated.
const double placementEarlyStopDeviation = 10;

/// First questions, spread across the difficulty scale.
const List<int> placementAnchorDifficulties = [10, 30, 50, 70, 90];

/// Half-width of the first window when picking a kanji near a target.
///
/// Tight enough that a question lands near the difficulty it was chosen
/// for. The window still grows when nothing sits that close.
const int placementSelectionWindow = 4;

/// Untested kanji at or above this probability are marked known.
///
/// With the slip above, a single kanji's probability never quite reaches
/// 0.95, so this band is only for an estimate that is essentially certain.
/// Lower the constant to mark more untested kanji known.
const double placementKnownProbability = 0.95;

/// Untested kanji at or above this, and below [placementKnownProbability],
/// are queued for a short confirmation instead of treated as new.
const double placementConfirmProbability = 0.50;

const int placementMinDifficulty = 1;
const int placementMaxDifficulty = 100;

/// Overlapping slices of the placement order, as fractions of the sorted list.
///
/// Kanji are sorted by [KanjiCard.difficulty] ascending — the order the
/// placement model already estimates. A slice is a position in that list,
/// not a raw difficulty number, so gaps in the values do not create a cutoff.
/// The ranges overlap so a learner who misjudges themselves is still nearby.
const double placementBeginnerMinPercent = 0.0;
const double placementBeginnerMaxPercent = 0.35;

const double placementIntermediateMinPercent = 0.20;
const double placementIntermediateMaxPercent = 0.70;

const double placementExpertMinPercent = 0.50;
const double placementExpertMaxPercent = 1.0;

/// Narrowest self-assessment bell, in difficulty points.
///
/// Wide enough that answers can still move the estimate well outside the
/// selected slice. The bell is wider when the slice itself is wide.
const double placementSelfAssessmentMinSpread = 18;

/// How many difficulty points question selection may step outside the
/// current slice after an answer pushes against an edge.
const int placementRangeExpansionStep = 8;

/// Untested kanji are marked known from this percentile of the estimate.
///
/// The average is where a kanji is a coin flip, and it sits high when the
/// test is still unsure. The 25th percentile stays under that average, so
/// the kanji we skip are the ones the learner is likely to know.
const double placementKnownQuantile = 0.25;

/// Confirmation reviews are spread over at least this many days.
const int placementConfirmMinHorizonDays = 30;

/// Learner positions the posterior is stored on. One point each.
const int placementPositionCount =
    placementMaxDifficulty - placementMinDifficulty + 1;

bool placementDifficultyIsValid(int difficulty) {
  return difficulty >= placementMinDifficulty &&
      difficulty <= placementMaxDifficulty;
}

double placementSigmoid(double x) {
  if (x >= 20) return 1;
  if (x <= -20) return 0;
  return 1 / (1 + math.exp(-x));
}

/// P(correct | position, difficulty) on the soft boundary.
double placementProbabilityCorrect(int position, int difficulty) {
  final scale = (position - difficulty) / placementBoundarySoftness;
  final ceiling = 1 - placementGuessProbability - placementSlipProbability;
  return placementGuessProbability + ceiling * placementSigmoid(scale);
}

/// Inclusive difficulty bounds of one self-assessment slice.
class PlacementSelfAssessmentBand {
  const PlacementSelfAssessmentBand({
    required this.low,
    required this.high,
    required this.center,
  });

  final int low;
  final int high;

  /// Difficulty of the kanji at the middle of the slice.
  final double center;
}

/// Eligible kanji in Learning Path order, earliest first.
///
/// This is the kanji list's default order: recommended priority from
/// frequency, JLPT, difficulty, and components. [catalog] supplies the
/// frequency scale when [cards] is only the askable subset. Nothing is
/// treated as already known, so the order stays the default path.
List<KanjiCard> placementRanked(
  Iterable<KanjiCard> cards, {
  Iterable<KanjiCard>? catalog,
}) {
  final ranked = cards.toList();
  final curriculum = CurriculumPriorityService(catalog ?? ranked);
  ranked.sort(
    curriculum.comparer(
      mode: CurriculumMode.recommended,
      knownCardIds: const {},
      customRanks: null,
    ),
  );
  return ranked;
}

/// Learning-path position from 1 (first to study) to 100 (last).
///
/// Kanji that sit next to each other on the path share a position, which is
/// the group the placement test asks from.
int placementPathPosition(int index, int length) {
  if (length <= 1) return placementMinDifficulty;
  final span = placementMaxDifficulty - placementMinDifficulty;
  return placementMinDifficulty + ((index * span) / (length - 1)).round();
}

/// Path position for every card in [ranked], which must already be in
/// Learning Path order.
Map<String, int> placementPathPositions(List<KanjiCard> ranked) {
  return {
    for (var index = 0; index < ranked.length; index++)
      ranked[index].id: placementPathPosition(index, ranked.length),
  };
}

/// The overlapping slice for [assessment], or null when the test should
/// start from the uniform prior. [newUser] does not run the test at all.
PlacementSelfAssessmentBand? placementBandFor(
  Iterable<KanjiCard> cards,
  PlacementSelfAssessment? assessment,
) {
  final (double, double)? percents = switch (assessment) {
    PlacementSelfAssessment.beginner => (
      placementBeginnerMinPercent,
      placementBeginnerMaxPercent,
    ),
    PlacementSelfAssessment.intermediate => (
      placementIntermediateMinPercent,
      placementIntermediateMaxPercent,
    ),
    PlacementSelfAssessment.expert => (
      placementExpertMinPercent,
      placementExpertMaxPercent,
    ),
    PlacementSelfAssessment.newUser || null => null,
  };
  if (percents == null) return null;
  return _bandFromPercents(placementRanked(cards), percents.$1, percents.$2);
}

/// Mode of a bell whose mean, after the scale's edges, is [targetMean].
///
/// A bell aimed at a low difficulty is cut off by the bottom of the scale,
/// and that leftover mass pulls the average upward. Placing the mode so the
/// average lands on [targetMean] keeps the starting guess from running high.
double placementPriorMode({
  required double targetMean,
  required double spread,
}) {
  final floor = placementMinDifficulty.toDouble();
  final ceiling = placementMaxDifficulty.toDouble();
  final target = targetMean < floor
      ? floor
      : targetMean > ceiling
      ? ceiling
      : targetMean;
  var low = floor;
  var high = ceiling;
  var best = target;
  for (var step = 0; step < 24; step++) {
    final mid = (low + high) / 2;
    final mean = PlacementPosterior.centered(mid, spread: spread).mean;
    best = mid;
    if ((mean - target).abs() < 0.2) return mid;
    if (mean > target) {
      high = mid;
    } else {
      low = mid;
    }
  }
  return best;
}

/// Spread of the starting bell for [band]. Always at least
/// [placementSelfAssessmentMinSpread], and wider for a wider slice.
double placementSelfAssessmentSpreadFor(PlacementSelfAssessmentBand band) {
  final span = (band.high - band.low).abs().toDouble();
  final scaled = span * 0.6;
  if (scaled < placementSelfAssessmentMinSpread) {
    return placementSelfAssessmentMinSpread;
  }
  return scaled;
}

PlacementSelfAssessmentBand _bandFromPercents(
  List<KanjiCard> ranked,
  double minPercent,
  double maxPercent,
) {
  if (ranked.isEmpty) {
    return const PlacementSelfAssessmentBand(
      low: placementMinDifficulty,
      high: placementMaxDifficulty,
      center: 50.5,
    );
  }
  final lowIndex = _percentileIndex(ranked.length, minPercent);
  final highIndex = _percentileIndex(ranked.length, maxPercent);
  final midIndex = _percentileIndex(
    ranked.length,
    (minPercent + maxPercent) / 2,
  );
  final first = lowIndex < highIndex ? lowIndex : highIndex;
  final last = lowIndex < highIndex ? highIndex : lowIndex;
  final positions = placementPathPositions(ranked);
  return PlacementSelfAssessmentBand(
    low: positions[ranked[first].id]!,
    high: positions[ranked[last].id]!,
    center: positions[ranked[midIndex].id]!.toDouble(),
  );
}

int _percentileIndex(int length, double percent) {
  if (length <= 1) return 0;
  final clamped = percent < 0
      ? 0.0
      : percent > 1
      ? 1.0
      : percent;
  final index = (clamped * (length - 1)).round();
  if (index < 0) return 0;
  if (index > length - 1) return length - 1;
  return index;
}

/// Probability distribution over learner positions 1–100.
class PlacementPosterior {
  PlacementPosterior() : _log = List<double>.filled(placementPositionCount, 0);

  /// Broad bell centered on [center]. Every position keeps some weight.
  PlacementPosterior.centered(double center, {required double spread})
    : _log = _bell(center, spread < 1 ? 1 : spread);

  /// Unnormalized log weights. Equal logs are the uniform prior.
  final List<double> _log;
  List<double>? _weights;

  static List<double> _bell(double center, double spread) {
    return List<double>.generate(placementPositionCount, (index) {
      final position = index + placementMinDifficulty;
      final z = (position - center) / spread;
      return -0.5 * z * z;
    });
  }

  void observe({required int difficulty, required bool correct}) {
    if (!placementDifficultyIsValid(difficulty)) return;
    _weights = null;
    for (var index = 0; index < _log.length; index++) {
      final probability = placementProbabilityCorrect(
        index + placementMinDifficulty,
        difficulty,
      );
      final likelihood = correct ? probability : 1 - probability;
      _log[index] += math.log(likelihood);
    }
  }

  /// Normalized P(position), index 0 = difficulty 1.
  List<double> get weights {
    final cached = _weights;
    if (cached != null) return cached;
    var maxLog = _log.first;
    for (final value in _log) {
      if (value > maxLog) maxLog = value;
    }
    final scaled = <double>[];
    var sum = 0.0;
    for (final value in _log) {
      final weight = math.exp(value - maxLog);
      scaled.add(weight);
      sum += weight;
    }
    if (sum <= 0 || sum.isNaN) {
      final even = 1 / placementPositionCount;
      final uniform = List<double>.filled(placementPositionCount, even);
      _weights = uniform;
      return uniform;
    }
    final normalized = [for (final weight in scaled) weight / sum];
    _weights = normalized;
    return normalized;
  }

  double get mean {
    final values = weights;
    var total = 0.0;
    for (var index = 0; index < values.length; index++) {
      total += (index + placementMinDifficulty) * values[index];
    }
    return total
        .clamp(
          placementMinDifficulty.toDouble(),
          placementMaxDifficulty.toDouble(),
        )
        .toDouble();
  }

  double get standardDeviation {
    final center = mean;
    final values = weights;
    var variance = 0.0;
    for (var index = 0; index < values.length; index++) {
      final distance = (index + placementMinDifficulty) - center;
      variance += distance * distance * values[index];
    }
    if (variance < 0) return 0;
    return math.sqrt(variance);
  }

  /// Smallest position where the cumulative probability reaches [probability].
  int quantile(double probability) {
    final values = weights;
    var cumulative = 0.0;
    for (var index = 0; index < values.length; index++) {
      cumulative += values[index];
      if (cumulative >= probability - 1e-9) {
        return index + placementMinDifficulty;
      }
    }
    return placementMaxDifficulty;
  }

  /// Smallest positions where the cumulative probability reaches 10% and 90%.
  PlacementCredibleInterval get credibleInterval {
    final values = weights;
    var cumulative = 0.0;
    int? low;
    int? high;
    for (var index = 0; index < values.length; index++) {
      cumulative += values[index];
      final position = index + placementMinDifficulty;
      // A small tolerance keeps a probability that lands on 0.10 from
      // rounding down to the next point.
      if (low == null && cumulative >= 0.10 - 1e-9) low = position;
      if (high == null && cumulative >= 0.90 - 1e-9) {
        high = position;
        break;
      }
    }
    return PlacementCredibleInterval(
      low: low ?? placementMinDifficulty,
      high: high ?? placementMaxDifficulty,
    );
  }

  /// P(correct | difficulty), averaged over the whole posterior.
  double probabilityFor(int difficulty) {
    if (!placementDifficultyIsValid(difficulty)) return 0;
    final values = weights;
    var total = 0.0;
    for (var index = 0; index < values.length; index++) {
      total +=
          values[index] *
          placementProbabilityCorrect(
            index + placementMinDifficulty,
            difficulty,
          );
    }
    return total;
  }
}

class PlacementCredibleInterval {
  const PlacementCredibleInterval({required this.low, required this.high});

  final int low;
  final int high;
}

/// Where an estimate sits on the Learning Path.
class PlacementCorpus {
  PlacementCorpus(List<KanjiCard> cards) : this._(placementRanked(cards));

  PlacementCorpus._(List<KanjiCard> ranked)
    : ranked = ranked,
      positions = placementPathPositions(ranked);

  /// Kanji in Learning Path order, earliest first.
  final List<KanjiCard> ranked;

  /// Learning-path position of each ranked kanji, from 1 to 100.
  final Map<String, int> positions;

  /// How many ranked kanji sit at or before [estimate] on the path.
  int positionFor(double estimate) {
    var count = 0;
    for (final card in ranked) {
      final position = positions[card.id];
      if (position == null) continue;
      if (position <= estimate) {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  /// Kanji that come before [estimatedDifficulty] in JLPT order.
  ///
  /// The score is only used to find early, mid, or late in a level. Earlier
  /// levels are included in full. Early includes none of the current level,
  /// mid includes its first third, and late includes its first two thirds.
  /// Inside a level the order is [compareKanjiLearnOrder], not difficulty.
  Set<String> idsKnownBefore(double estimatedDifficulty) {
    if (ranked.isEmpty) return const {};
    final position = positionFor(estimatedDifficulty);
    if (position >= ranked.length) {
      return {for (final card in ranked) card.id};
    }
    final place = _place(position);
    final byLevel = <JlptLevel, List<KanjiCard>>{};
    for (final card in ranked) {
      (byLevel[card.jlptLevel] ??= []).add(card);
    }
    for (final cards in byLevel.values) {
      cards.sort(compareKanjiLearnOrder);
    }

    final known = <String>{};
    final placedOrder = JlptLevel.sectionOrder.indexOf(place.level);
    for (final level in JlptLevel.sectionOrder) {
      final cards = byLevel[level];
      if (cards == null) continue;
      final order = JlptLevel.sectionOrder.indexOf(level);
      if (order < placedOrder) {
        known.addAll(cards.map((card) => card.id));
      } else if (order == placedOrder) {
        final take = (cards.length * _fractionBefore(place.band)).floor();
        known.addAll(cards.take(take).map((card) => card.id));
      }
    }
    return known;
  }

  /// "You're roughly late N3", plus an overlap line when the interval
  /// crosses into a later level.
  PlacementDescription describe({
    required double estimatedDifficulty,
    required int intervalHigh,
  }) {
    if (ranked.isEmpty) {
      return const PlacementDescription(headline: '', nothingToPlace: true);
    }
    final meanPlace = _place(positionFor(estimatedDifficulty));
    final highPlace = _place(positionFor(intervalHigh.toDouble()));
    final headline = _headline(meanPlace);
    final detail = _overlap(meanPlace, highPlace);
    return PlacementDescription(headline: headline, detail: detail);
  }

  _LevelPlace _place(int position) {
    final counts = <JlptLevel, int>{};
    for (final card in ranked) {
      counts[card.jlptLevel] = (counts[card.jlptLevel] ?? 0) + 1;
    }
    var start = 0;
    _LevelPlace? first;
    _LevelPlace? last;
    for (final level in JlptLevel.sectionOrder) {
      final count = counts[level] ?? 0;
      if (count == 0) continue;
      final end = start + count;
      final place = _LevelPlace(level: level, start: start, count: count);
      first ??= place;
      last = place;
      if (position <= end) return place.withPosition(position);
      start = end;
    }
    final fallback =
        last ??
        first ??
        const _LevelPlace(level: JlptLevel.none, start: 0, count: 1);
    return fallback.withPosition(position);
  }

  String _headline(_LevelPlace place) {
    if (place.level == JlptLevel.none) {
      return "You're roughly at the end of the list";
    }
    return "You're roughly ${place.band} ${place.level.shortName}";
  }

  double _fractionBefore(String band) {
    return switch (band) {
      'mid' => 1 / 3,
      'late' => 2 / 3,
      _ => 0,
    };
  }

  String? _overlap(_LevelPlace mean, _LevelPlace high) {
    if (high.level == mean.level || high.level == JlptLevel.none) return null;
    final meanOrder = JlptLevel.sectionOrder.indexOf(mean.level);
    final highOrder = JlptLevel.sectionOrder.indexOf(high.level);
    if (highOrder <= meanOrder) return null;
    return 'We estimate you know kanji around this point, '
        'with some overlap into ${high.level.shortName}.';
  }
}

class PlacementDescription {
  const PlacementDescription({
    required this.headline,
    this.detail,
    this.nothingToPlace = false,
  });

  final String headline;
  final String? detail;
  final bool nothingToPlace;
}

class _LevelPlace {
  const _LevelPlace({
    required this.level,
    required this.start,
    required this.count,
    this.index = 1,
  });

  final JlptLevel level;

  /// How many ranked kanji sit in earlier levels.
  final int start;
  final int count;

  /// 1-based index inside the level.
  final int index;

  _LevelPlace withPosition(int position) {
    final raw = position - start;
    final clamped = raw < 1
        ? 1
        : raw > count
        ? count
        : raw;
    return _LevelPlace(
      level: level,
      start: start,
      count: count,
      index: clamped,
    );
  }

  String get band {
    final fraction = (index - 0.5) / count;
    if (fraction < 1 / 3) return 'early';
    if (fraction < 2 / 3) return 'mid';
    return 'late';
  }
}

extension on JlptLevel {
  String get shortName => switch (this) {
    JlptLevel.n5 => 'N5',
    JlptLevel.n4 => 'N4',
    JlptLevel.n3 => 'N3',
    JlptLevel.n2 => 'N2',
    JlptLevel.n1 => 'N1',
    JlptLevel.none => 'the list',
  };
}

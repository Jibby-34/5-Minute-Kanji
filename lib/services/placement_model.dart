import 'dart:math' as math;

import '../core/models/kanji_card.dart';
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

/// Stop early once the posterior is at least this concentrated.
const double placementEarlyStopDeviation = 10;

/// First questions, spread across the difficulty scale.
const List<int> placementAnchorDifficulties = [10, 30, 50, 70, 90];

/// Half-width of the first window when picking a kanji near a target.
const int placementSelectionWindow = 10;

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

/// Probability distribution over learner positions 1–100.
class PlacementPosterior {
  PlacementPosterior() : _log = List<double>.filled(placementPositionCount, 0);

  /// Unnormalized log weights. Equal logs are the uniform prior.
  final List<double> _log;
  List<double>? _weights;

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

/// Where an estimated difficulty sits in the real catalog.
class PlacementCorpus {
  PlacementCorpus(List<KanjiCard> cards)
    : ranked = [
        for (final card in cards)
          if (placementDifficultyIsValid(card.difficulty)) card,
      ] {
    ranked.sort((a, b) {
      final byDifficulty = a.difficulty.compareTo(b.difficulty);
      if (byDifficulty != 0) return byDifficulty;
      return a.id.compareTo(b.id);
    });
  }

  /// Valid-difficulty kanji, easiest first.
  final List<KanjiCard> ranked;

  /// How many ranked kanji have difficulty at or below [difficulty].
  int positionFor(double difficulty) {
    var count = 0;
    for (final card in ranked) {
      if (card.difficulty <= difficulty) {
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

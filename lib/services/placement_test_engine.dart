import 'dart:developer' as developer;
import 'dart:math' as math;

import '../core/models/kanji_card.dart';
import '../core/models/placement.dart';
import 'placement_model.dart';

/// One answered placement question, kept for debug inspection.
class PlacementStep {
  const PlacementStep({
    required this.cardId,
    required this.difficulty,
    required this.correct,
    required this.mean,
    required this.standardDeviation,
  });

  final String cardId;
  final int difficulty;
  final bool correct;
  final double mean;
  final double standardDeviation;
}

/// Placement test over kanji the app does not already know.
///
/// Answers are noisy evidence about a difficulty position from 1 to 100.
/// The test keeps a probability distribution over that position, asks up to
/// [questionCap] kanji, and never treats a single answer as a hard cutoff.
/// A self-assessment, when one was chosen, is only a soft prior and a
/// starting slice of that same order. Answers can move the estimate, and
/// the questions, well outside the slice.
/// A run is a pure function of the pool, the selection seed, the
/// self-assessment, and the answers so far, so a test interrupted by the
/// app closing is replayed.
class PlacementTestEngine {
  const PlacementTestEngine({
    this.maxQuestions = placementMaxQuestions,
    this.selectionSeed = 1,
  });

  /// Hard ceiling for one test. [maxQuestions] cannot raise it.
  static const int questionCap = placementMaxQuestions;

  final int maxQuestions;

  /// Mixes which kanji is chosen near a target difficulty. The same seed and
  /// answers always reproduce the same question.
  final int selectionSeed;

  /// [maxQuestions] clamped to [questionCap].
  int get questionLimit {
    final requested = maxQuestions < 1 ? 1 : maxQuestions;
    return requested < questionCap ? requested : questionCap;
  }

  /// The denominator behind the `1 / ~20` progress hint. A ceiling, not a
  /// prediction: finishing early reads as a bonus, finishing late would not.
  int estimatedQuestionCount(int poolSize) {
    if (poolSize <= 0) return 0;
    return questionLimit < poolSize ? questionLimit : poolSize;
  }

  /// Rebuilds a run by feeding [answers] back through the same question
  /// stream that produced them.
  ///
  /// [corpus] is the full catalog used to turn a difficulty estimate into a
  /// place in the real list. It defaults to [pool].
  PlacementRun replay(
    List<KanjiCard> pool,
    Iterable<PlacementAnswer> answers, {
    List<KanjiCard>? corpus,
    PlacementSelfAssessment? selfAssessment,
  }) {
    final run = PlacementRun._(this, pool, corpus ?? pool, selfAssessment);
    for (final answer in answers) {
      run.record(answer);
    }
    return run;
  }
}

/// One in-progress or finished placement test.
class PlacementRun {
  PlacementRun._(
    this._engine,
    List<KanjiCard> pool,
    List<KanjiCard> corpus,
    PlacementSelfAssessment? selfAssessment,
  ) : _corpus = PlacementCorpus(corpus) {
    final skipped = <String>[];
    for (final card in pool) {
      _byId[card.id] = card;
      if (placementDifficultyIsValid(card.difficulty)) {
        _eligible.add(card);
      } else {
        skipped.add(card.id);
      }
    }
    _eligible.sort((a, b) {
      final byDifficulty = a.difficulty.compareTo(b.difficulty);
      if (byDifficulty != 0) return byDifficulty;
      return a.id.compareTo(b.id);
    });
    assert(() {
      if (skipped.isNotEmpty) {
        developer.log(
          'skipped ${skipped.length} kanji without a difficulty from '
          '$placementMinDifficulty to $placementMaxDifficulty: '
          '${skipped.take(8).join(', ')}',
          name: 'placement',
        );
      }
      return true;
    }());
    _applyAssessment(selfAssessment);
  }

  final PlacementTestEngine _engine;
  final PlacementCorpus _corpus;
  final Map<String, KanjiCard> _byId = {};
  final List<KanjiCard> _eligible = [];
  final Map<String, bool> _responses = {};
  late final PlacementPosterior _posterior;
  final List<PlacementStep> _steps = [];

  /// Null when the run uses the uniform prior and the full difficulty scale.
  PlacementSelfAssessmentBand? _band;
  int _selectionLow = placementMinDifficulty;
  int _selectionHigh = placementMaxDifficulty;
  int? _hardestAsked;
  int? _easiestAsked;
  bool _probingUp = false;
  bool _probingDown = false;

  int get answeredCount => _responses.length;

  int get questionsAsked => _steps.length;

  /// Estimated length of the whole test, for the progress indicator.
  int get estimatedTotal => _engine.estimatedQuestionCount(_eligible.length);

  bool get isFinished => currentQuestion == null;

  double get estimatedDifficulty => _posterior.mean;

  double get standardDeviation => _posterior.standardDeviation;

  PlacementCredibleInterval get credibleInterval => _posterior.credibleInterval;

  List<PlacementStep> get steps => List.unmodifiable(_steps);

  /// P(the learner knows a kanji of [difficulty]), over the whole posterior.
  double knowledgeProbability(int difficulty) =>
      _posterior.probabilityFor(difficulty);

  /// The kanji to put on screen, or null when the test is over.
  KanjiCard? get currentQuestion => _select();

  /// Applies one answer. Answers for kanji outside the pool are ignored so a
  /// replay survives a pool that has changed since the test began.
  void record(PlacementAnswer answer) {
    final card = _byId[answer.cardId];
    if (card == null || _responses.containsKey(answer.cardId)) return;
    if (answeredCount >= _engine.questionLimit) return;
    _responses[answer.cardId] = answer.known;
    if (placementDifficultyIsValid(card.difficulty)) {
      _posterior.observe(difficulty: card.difficulty, correct: answer.known);
      _expandSearch(card.difficulty, answer.known);
    }
    final step = PlacementStep(
      cardId: card.id,
      difficulty: card.difficulty,
      correct: answer.known,
      mean: estimatedDifficulty,
      standardDeviation: standardDeviation,
    );
    _steps.add(step);
    assert(() {
      developer.log(
        'asked=${step.cardId} difficulty=${step.difficulty} '
        'correct=${step.correct} mean=${step.mean.toStringAsFixed(1)} '
        'sd=${step.standardDeviation.toStringAsFixed(1)} n=$answeredCount',
        name: 'placement',
      );
      return true;
    }());
  }

  bool shouldStop() {
    if (_eligible.isEmpty) return true;
    if (answeredCount >= _engine.questionLimit) return true;
    if (_unasked.isEmpty) return true;
    final anchorsLeft =
        answeredCount < placementAnchorDifficulties.length &&
        answeredCount < _eligible.length;
    if (anchorsLeft) return false;
    // Keep going while the last answer is pushing past the slice we started
    // in. Stopping there would freeze a confident-but-wrong self-assessment.
    if (_probingUp || _probingDown) return false;
    if (standardDeviation > placementEarlyStopDeviation) return false;
    // A tight average can still be high if every question sat well above or
    // below it. Check something near the boundary before trusting the stop.
    return _boundaryChecked;
  }

  bool get _boundaryChecked {
    final estimate = estimatedDifficulty;
    for (final step in _steps) {
      final distance = step.difficulty - estimate;
      final gap = distance < 0 ? -distance : distance;
      if (gap <= placementBoundarySoftness) return true;
    }
    return false;
  }

  /// Difficulty below which an untested kanji is treated as known.
  ///
  /// Uses a percentile under the average, and never reaches a difficulty
  /// the learner said they don't know.
  double get _knownCutoff {
    var cutoff = _posterior.quantile(placementKnownQuantile).toDouble();
    var lowestMiss = placementMaxDifficulty + 1.0;
    var sawMiss = false;
    for (final step in _steps) {
      if (step.correct) continue;
      sawMiss = true;
      if (step.difficulty < lowestMiss) {
        lowestMiss = step.difficulty.toDouble();
      }
    }
    if (sawMiss && lowestMiss - 1 < cutoff) {
      cutoff = lowestMiss - 1;
    }
    return cutoff;
  }

  /// What the test concluded.
  ///
  /// A tested kanji keeps the answer the learner gave. An untested kanji is
  /// marked known only when its difficulty sits clearly below the estimate.
  /// Earlier JLPT levels are not granted in bulk: a hard kanji in an early
  /// level stays new unless the learner actually knows that difficulty.
  PlacementOutcome outcome() {
    if (_eligible.isEmpty && _responses.isEmpty) {
      return PlacementOutcome(
        knownCardIds: const [],
        answeredCount: answeredCount,
        nothingToPlace: true,
      );
    }

    final cutoff = _knownCutoff;
    final known = <String>[];
    for (final card in _byId.values) {
      final answered = _responses[card.id];
      if (answered == false) continue;
      if (answered == true ||
          (placementDifficultyIsValid(card.difficulty) &&
              card.difficulty <= cutoff)) {
        known.add(card.id);
      }
    }

    final interval = credibleInterval;
    final describedAt = cutoff < placementMinDifficulty
        ? estimatedDifficulty
        : cutoff;
    final description = _corpus.describe(
      estimatedDifficulty: describedAt,
      intervalHigh: interval.high,
    );
    final result = PlacementOutcome(
      knownCardIds: known,
      confirmCardIds: const [],
      answeredCount: answeredCount,
      estimatedDifficulty: estimatedDifficulty,
      intervalLow: interval.low,
      intervalHigh: interval.high,
      corpusPosition: _corpus.positionFor(describedAt),
      headline: description.headline,
      detail: description.detail,
      nothingToPlace: description.nothingToPlace,
    );
    assert(() {
      developer.log(
        'final mean=${result.estimatedDifficulty.toStringAsFixed(1)} '
        'interval=${result.intervalLow}–${result.intervalHigh} '
        'position=${result.corpusPosition} '
        'questions=${result.answeredCount} '
        'headline=${result.headline}',
        name: 'placement',
      );
      return true;
    }());
    return result;
  }

  KanjiCard? _select() {
    if (shouldStop()) return null;
    final target = _targetDifficulty();
    final choice = _pickNear(target);
    return choice;
  }

  void _applyAssessment(PlacementSelfAssessment? assessment) {
    _band = placementBandFor(_eligible, assessment);
    final band = _band;
    if (band == null) {
      _posterior = PlacementPosterior();
      return;
    }
    _selectionLow = band.low;
    _selectionHigh = band.high;
    final spread = placementSelfAssessmentSpreadFor(band);
    _posterior = PlacementPosterior.centered(
      placementPriorMode(targetMean: band.center, spread: spread),
      spread: spread,
    );
  }

  /// Grows the search slice by one step when answers push against an edge.
  /// The posterior itself is not clamped. The next question moves one step
  /// past what has actually been asked, so the walk out of the slice is gradual.
  void _expandSearch(int difficulty, bool correct) {
    if (_band == null) return;
    final origin = _band!;
    final edge = _edgeWidth();
    final mean = estimatedDifficulty;
    final previousHigh = _hardestAsked ?? origin.high;
    final previousLow = _easiestAsked ?? origin.low;
    final rising =
        correct &&
        (difficulty >= previousHigh - edge || difficulty >= origin.center) &&
        _selectionHigh < placementMaxDifficulty;
    final falling =
        !correct &&
        (difficulty <= previousLow + edge || difficulty <= origin.center) &&
        _selectionLow > placementMinDifficulty;

    if (rising) {
      final frontier = math.max(_selectionHigh, previousHigh);
      _selectionHigh = math.min(
        placementMaxDifficulty,
        frontier + placementRangeExpansionStep,
      );
      _probingUp = _selectionHigh > previousHigh;
      _probingDown = false;
    } else if (falling) {
      final frontier = math.min(_selectionLow, previousLow);
      _selectionLow = math.max(
        placementMinDifficulty,
        frontier - placementRangeExpansionStep,
      );
      _probingDown = _selectionLow < previousLow;
      _probingUp = false;
    } else if (mean > _selectionHigh &&
        _selectionHigh < placementMaxDifficulty) {
      _selectionHigh = math.min(
        placementMaxDifficulty,
        _selectionHigh + placementRangeExpansionStep,
      );
      _probingUp = true;
      _probingDown = false;
    } else if (mean < _selectionLow && _selectionLow > placementMinDifficulty) {
      _selectionLow = math.max(
        placementMinDifficulty,
        _selectionLow - placementRangeExpansionStep,
      );
      _probingDown = true;
      _probingUp = false;
    } else if (correct) {
      _probingUp = false;
      _probingDown = false;
    } else if (!_probingDown) {
      _probingUp = false;
    }

    if (_hardestAsked == null || difficulty > _hardestAsked!) {
      _hardestAsked = difficulty;
    }
    if (_easiestAsked == null || difficulty < _easiestAsked!) {
      _easiestAsked = difficulty;
    }
    if (_probingUp) {
      final stepped = _hardestAsked! + placementRangeExpansionStep;
      final target = stepped > _selectionHigh ? _selectionHigh : stepped;
      if (target <= _hardestAsked! || target > placementMaxDifficulty) {
        _probingUp = false;
      }
    }
    if (_probingDown) {
      final stepped = _easiestAsked! - placementRangeExpansionStep;
      final target = stepped < _selectionLow ? _selectionLow : stepped;
      if (target >= _easiestAsked! || target < placementMinDifficulty) {
        _probingDown = false;
      }
    }
  }

  double _edgeWidth() {
    final span = (_selectionHigh - _selectionLow).toDouble();
    final quarter = span * 0.25;
    if (quarter > placementBoundarySoftness) return quarter;
    return placementBoundarySoftness;
  }

  double _targetDifficulty() {
    if (_band == null) {
      if (answeredCount < placementAnchorDifficulties.length) {
        return placementAnchorDifficulties[answeredCount].toDouble();
      }
      return estimatedDifficulty;
    }
    if (answeredCount < placementAnchorDifficulties.length) {
      return _anchorInBand(answeredCount);
    }
    if (_probingUp) {
      final hardest = _hardestAsked ?? _selectionHigh;
      final stepped = hardest + placementRangeExpansionStep;
      final capped = stepped > _selectionHigh ? _selectionHigh : stepped;
      return capped.toDouble();
    }
    if (_probingDown) {
      final easiest = _easiestAsked ?? _selectionLow;
      final stepped = easiest - placementRangeExpansionStep;
      final capped = stepped < _selectionLow ? _selectionLow : stepped;
      return capped.toDouble();
    }
    final low = _selectionLow.toDouble();
    final high = _selectionHigh.toDouble();
    final estimate = estimatedDifficulty;
    if (estimate < low) return low;
    if (estimate > high) return high;
    return estimate;
  }

  /// Five interior points of the starting slice, in the same role as
  /// [placementAnchorDifficulties] on an unconstrained test.
  double _anchorInBand(int index) {
    final band = _band!;
    final count = placementAnchorDifficulties.length;
    final span = band.high - band.low;
    if (span <= 0 || count <= 0) return band.center;
    final t = (index + 1) / (count + 1);
    return band.low + span * t;
  }

  KanjiCard? _pickNear(double target) {
    final waiting = _preferred(_unasked);
    if (waiting.isEmpty) return null;
    var window = placementSelectionWindow;
    while (window <= placementMaxDifficulty) {
      final near = [
        for (final card in waiting)
          if ((card.difficulty - target).abs() <= window) card,
      ];
      if (near.isNotEmpty) return near[_mixIndex(near.length, target)];
      window += placementSelectionWindow;
    }
    return waiting[_mixIndex(waiting.length, target)];
  }

  List<KanjiCard> get _unasked => [
    for (final card in _eligible)
      if (!_responses.containsKey(card.id)) card,
  ];

  /// Kanji inside the current search slice. Falls back to the full pool
  /// once that slice has nothing left to ask, so the test cannot get stuck.
  List<KanjiCard> _preferred(List<KanjiCard> waiting) {
    if (_band == null) return waiting;
    final inside = [
      for (final card in waiting)
        if (card.difficulty >= _selectionLow &&
            card.difficulty <= _selectionHigh)
          card,
    ];
    if (inside.isEmpty) return waiting;
    return inside;
  }

  int _mixIndex(int length, double target) {
    var state = _engine.selectionSeed & 0x7fffffff;
    state = (state * 33 + target.round()) & 0x7fffffff;
    state = (state * 33 + answeredCount) & 0x7fffffff;
    state = (state * 1103515245 + 12345) & 0x7fffffff;
    if (length <= 1) return 0;
    return state % length;
  }
}

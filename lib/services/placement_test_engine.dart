import 'dart:developer' as developer;

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
/// A run is a pure function of the pool, the selection seed, and the answers
/// so far, so a test interrupted by the app closing is replayed.
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
  }) {
    final run = PlacementRun._(this, pool, corpus ?? pool);
    for (final answer in answers) {
      run.record(answer);
    }
    return run;
  }
}

/// One in-progress or finished placement test.
class PlacementRun {
  PlacementRun._(this._engine, List<KanjiCard> pool, List<KanjiCard> corpus)
    : _corpus = PlacementCorpus(corpus) {
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
  }

  final PlacementTestEngine _engine;
  final PlacementCorpus _corpus;
  final Map<String, KanjiCard> _byId = {};
  final List<KanjiCard> _eligible = [];
  final Map<String, bool> _responses = {};
  final PlacementPosterior _posterior = PlacementPosterior();
  final List<PlacementStep> _steps = [];

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
    return standardDeviation <= placementEarlyStopDeviation;
  }

  /// What the test concluded.
  ///
  /// The difficulty estimate is turned into a spot in JLPT order. Untested
  /// kanji before that spot are marked known. A tested kanji keeps the
  /// answer the learner gave, whichever side of that spot it sits on.
  PlacementOutcome outcome() {
    if (_eligible.isEmpty && _responses.isEmpty) {
      return PlacementOutcome(
        knownCardIds: const [],
        answeredCount: answeredCount,
        nothingToPlace: true,
      );
    }

    final before = _corpus.idsKnownBefore(estimatedDifficulty);
    final known = <String>[];
    for (final card in _byId.values) {
      final answered = _responses[card.id];
      if (answered == false) continue;
      if (answered == true || before.contains(card.id)) known.add(card.id);
    }

    final interval = credibleInterval;
    final description = _corpus.describe(
      estimatedDifficulty: estimatedDifficulty,
      intervalHigh: interval.high,
    );
    final result = PlacementOutcome(
      knownCardIds: known,
      confirmCardIds: const [],
      answeredCount: answeredCount,
      estimatedDifficulty: estimatedDifficulty,
      intervalLow: interval.low,
      intervalHigh: interval.high,
      corpusPosition: _corpus.positionFor(estimatedDifficulty),
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

  double _targetDifficulty() {
    if (answeredCount < placementAnchorDifficulties.length) {
      return placementAnchorDifficulties[answeredCount].toDouble();
    }
    return estimatedDifficulty;
  }

  KanjiCard? _pickNear(double target) {
    final waiting = _unasked;
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

  int _mixIndex(int length, double target) {
    var state = _engine.selectionSeed & 0x7fffffff;
    state = (state * 33 + target.round()) & 0x7fffffff;
    state = (state * 33 + answeredCount) & 0x7fffffff;
    state = (state * 1103515245 + 12345) & 0x7fffffff;
    if (length <= 1) return 0;
    return state % length;
  }
}

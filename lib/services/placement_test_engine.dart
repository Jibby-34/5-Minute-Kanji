import '../core/models/kanji_card.dart';
import '../core/models/placement.dart';
import 'due_card_selector.dart';

/// Placement test over kanji the app does not already know.
///
/// The pool is ordered by [compareKanjiLearnOrder], which is JLPT order and
/// the order the app treats as difficulty. Questions step upward through that
/// order, doubling the index each time so a beginner is not walked kanji by
/// kanji and an advanced learner is not kept on N5. The first "I don't know
/// it" ends the climb. The test then binary-searches backward through the gap
/// between the last kanji the user knew and that miss, until the two sit next
/// to each other or the question budget runs out.
///
/// Only kanji at or below the last confirmed known index are treated as known.
/// An unfinished gap is left unknown, so the estimate does not run ahead of
/// what the user demonstrated. A run never asks more than [questionCap]
/// questions. The engine is stateless: a run is a pure function of the pool
/// plus the answers so far, so a test interrupted by the app closing is
/// replayed rather than restarted.
class PlacementTestEngine {
  const PlacementTestEngine({this.maxQuestions = questionCap});

  /// Hard ceiling for one test. [maxQuestions] cannot raise it.
  static const int questionCap = 20;

  final int maxQuestions;

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
  PlacementRun replay(List<KanjiCard> pool, Iterable<PlacementAnswer> answers) {
    final ordered = List<KanjiCard>.of(pool)..sort(compareKanjiLearnOrder);
    final run = PlacementRun._(this, ordered);
    for (final answer in answers) {
      run.record(answer);
    }
    return run;
  }
}

/// One in-progress or finished placement test.
class PlacementRun {
  PlacementRun._(this._engine, this._pool) : _unknownAt = _pool.length {
    for (var i = 0; i < _pool.length; i++) {
      _indexOf[_pool[i].id] = i;
    }
  }

  final PlacementTestEngine _engine;

  /// Difficulty order: easiest JLPT level first, then id within a level.
  final List<KanjiCard> _pool;
  final Map<String, int> _indexOf = {};
  final Map<String, bool> _responses = {};

  /// Highest index the user has confirmed they know. -1 means none.
  int _knownThrough = -1;

  /// Lowest index the user has missed. One past the end means none yet.
  int _unknownAt;

  /// True while questions are still stepping upward.
  bool _ascending = true;

  /// Index the upward step will ask next.
  int _ascentIndex = 0;

  int get answeredCount => _responses.length;

  /// Estimated length of the whole test, for the progress indicator.
  int get estimatedTotal => _engine.estimatedQuestionCount(_pool.length);

  bool get isFinished => currentQuestion == null;

  /// The kanji to put on screen, or null when the test is over.
  KanjiCard? get currentQuestion {
    final index = _nextIndex();
    if (index == null) return null;
    return _pool[index];
  }

  /// Applies one answer. Answers for kanji outside the pool are ignored so a
  /// replay survives a pool that has changed since the test began.
  void record(PlacementAnswer answer) {
    final index = _indexOf[answer.cardId];
    if (index == null || _responses.containsKey(answer.cardId)) return;

    final steppingUp = _ascending && index == _ascentIndex;
    _responses[answer.cardId] = answer.known;
    if (answer.known) {
      if (index < _unknownAt && index > _knownThrough) _knownThrough = index;
      if (steppingUp) _stepUp(index);
    } else {
      // A miss below the confirmed point pulls the estimate back. The search
      // never treats kanji above a miss as known just because an earlier
      // sample passed.
      if (index <= _knownThrough) _knownThrough = index - 1;
      if (index < _unknownAt) _unknownAt = index;
      _ascending = false;
    }
  }

  /// What the test concluded.
  ///
  /// An explicit "I don't know it" is never inferred as known, and an explicit
  /// "I know it" counts even above the boundary. Everything else at or below
  /// the last confirmed known index is known. The unresolved gap above that
  /// index stays unknown.
  PlacementOutcome outcome() {
    final known = <String>[];
    for (var i = 0; i < _pool.length; i++) {
      final card = _pool[i];
      final answered = _responses[card.id];
      final isKnown = answered ?? i <= _knownThrough;
      if (isKnown) known.add(card.id);
    }

    final knownIds = known.toSet();
    KanjiCard? next;
    for (final card in _pool) {
      if (!knownIds.contains(card.id)) {
        next = card;
        break;
      }
    }

    return PlacementOutcome(
      knownCardIds: known,
      answeredCount: answeredCount,
      startingLevel: next?.jlptLevel,
      resumesMidLevel: next != null && _resumesMidLevel(next, knownIds),
    );
  }

  bool _resumesMidLevel(KanjiCard next, Set<String> knownIds) {
    for (final card in _pool) {
      if (card.id == next.id) return false;
      if (card.jlptLevel == next.jlptLevel && knownIds.contains(card.id)) {
        return true;
      }
    }
    return false;
  }

  int? _nextIndex() {
    if (_pool.isEmpty || answeredCount >= _engine.questionLimit) return null;
    if (_unknownAt - _knownThrough <= 1) return null;

    if (_ascending &&
        _ascentIndex > _knownThrough &&
        _ascentIndex < _unknownAt &&
        !_responses.containsKey(_pool[_ascentIndex].id)) {
      return _ascentIndex;
    }

    final span = _unknownAt - _knownThrough;
    var mid = _knownThrough + span ~/ 2;
    if (mid <= _knownThrough) mid = _knownThrough + 1;
    if (mid >= _unknownAt) mid = _unknownAt - 1;
    if (mid <= _knownThrough || mid >= _unknownAt) return null;
    if (_responses.containsKey(_pool[mid].id)) return null;
    return mid;
  }

  void _stepUp(int index) {
    if (_pool.length <= 1) {
      _ascending = false;
      return;
    }
    final doubled = index == 0 ? 1 : index * 2 + 1;
    final next = doubled >= _pool.length ? _pool.length - 1 : doubled;
    if (next <= index || next >= _unknownAt) {
      _ascending = false;
      return;
    }
    _ascentIndex = next;
  }
}

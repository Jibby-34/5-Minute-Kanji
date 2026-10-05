import 'dart:math' as math;

import '../core/models/kanji_card.dart';
import '../core/models/placement.dart';
import 'due_card_selector.dart';

/// Adaptive placement test over a pool of kanji the app does not already know.
///
/// The pool is ordered by [compareKanjiLearnOrder] and cut into difficulty
/// bands, easiest first. Each JLPT level is sliced into several bands, so the
/// result can fall inside a level instead of only on a level boundary. One
/// band is probed at a time: passing a band pushes the search upward, failing
/// it pulls the search back down, and the climb doubles band indexes before
/// bisecting. That resolves a fine boundary in a handful of rounds, which is
/// what keeps the quiz short.
///
/// A run never asks more than [questionCap] questions. The engine is
/// stateless: a run is a pure function of the pool plus the answers so far,
/// so a test interrupted by the app closing is replayed rather than restarted.
class PlacementTestEngine {
  const PlacementTestEngine({
    this.questionsPerBand = 2,
    this.minQuestions = 12,
    this.maxQuestions = questionCap,
    this.maxBands = 25,
    this.minBandSize = 3,
    this.passRatio = 2 / 3,
  });

  /// Hard ceiling for one test. [maxQuestions] cannot raise it.
  static const int questionCap = 20;

  /// Questions asked before a band is judged.
  final int questionsPerBand;

  /// The search often brackets the boundary sooner than this. The remaining
  /// questions are spent around the boundary, where they change the estimate
  /// most.
  final int minQuestions;

  final int maxQuestions;
  final int maxBands;

  /// Fewer kanji than this per band makes a band verdict meaningless, so small
  /// pools get fewer bands rather than thinner ones.
  final int minBandSize;

  /// Share of a band's answers that must be "I know it" for the band to pass.
  final double passRatio;

  /// [maxQuestions] clamped to [questionCap].
  int get questionLimit {
    final requested = maxQuestions < 1 ? 1 : maxQuestions;
    return requested < questionCap ? requested : questionCap;
  }

  /// Confirmation floor, never above [questionLimit].
  int get minimumQuestions {
    final requested = minQuestions < 0 ? 0 : minQuestions;
    return requested < questionLimit ? requested : questionLimit;
  }

  /// Pool split into difficulty bands, easiest first.
  ///
  /// Levels stay apart, and the question budget is spent on equal slices of
  /// every level (about a fifth of each on the full N5–N1 list). The slice
  /// count is how many bands the doubling search can still bracket inside
  /// [questionLimit], not one probe per band. If there are more levels than
  /// that, the largest adjacent levels are merged so the beginner boundary
  /// is the last one given up.
  List<List<KanjiCard>> bands(List<KanjiCard> pool) {
    final ordered = List<KanjiCard>.of(pool)..sort(compareKanjiLearnOrder);
    if (ordered.isEmpty) return const [];

    final groups = <_LevelGroup>[];
    for (final card in ordered) {
      if (groups.isEmpty ||
          groups.last.cards.first.jlptLevel != card.jlptLevel) {
        groups.add(_LevelGroup([card]));
      } else {
        groups.last.cards.add(card);
      }
    }

    _fitGroupsToBudget(groups, _bandBudget(ordered.length));
    return [
      for (final group in groups) ..._splitEvenly(group.cards, group.bandCount),
    ];
  }

  /// How many bands the doubling search can bracket inside [questionLimit].
  ///
  /// [_bandsResolvedBy] is the largest band count whose worst-case number of
  /// rounds still fits in the rounds this budget can pay for. It matches the
  /// doubling climb below, so a change to that climb has to update the table.
  int _bandBudget(int poolSize) {
    final perBand = questionsPerBand < 1 ? 1 : questionsPerBand;
    final rounds = math.max(1, questionLimit ~/ perBand);
    final bySearch = _bandsResolvedBy(rounds);
    final bySize = math.max(1, poolSize ~/ math.max(1, minBandSize));
    final cap = maxBands < 1 ? 1 : maxBands;
    return math.min(cap, math.min(bySearch, bySize));
  }

  static int _bandsResolvedBy(int rounds) {
    const limits = <int>[1, 2, 3, 4, 6, 7, 11, 13, 21, 25];
    if (rounds <= limits.length) return limits[rounds - 1];
    return limits.last + (rounds - limits.length) * 8;
  }

  void _fitGroupsToBudget(List<_LevelGroup> groups, int budget) {
    while (groups.length > budget && groups.length > 1) {
      var mergeAt = 0;
      var largest = -1;
      for (var i = 0; i < groups.length - 1; i++) {
        final size = groups[i].cards.length + groups[i + 1].cards.length;
        if (size >= largest) {
          largest = size;
          mergeAt = i;
        }
      }
      groups[mergeAt] = _LevelGroup([
        ...groups[mergeAt].cards,
        ...groups[mergeAt + 1].cards,
      ]);
      groups.removeAt(mergeAt + 1);
    }

    for (final group in groups) {
      group.bandCount = 1;
    }
    var remaining = budget - groups.length;
    while (remaining > 0) {
      _LevelGroup? best;
      var fewest = 1 << 30;
      var largest = -1;
      for (final group in groups) {
        final nextCount = group.bandCount + 1;
        if (group.cards.length ~/ nextCount < minBandSize) continue;
        final fewer = group.bandCount < fewest;
        final tieOnLargerLevel =
            group.bandCount == fewest && group.cards.length > largest;
        if (fewer || tieOnLargerLevel) {
          best = group;
          fewest = group.bandCount;
          largest = group.cards.length;
        }
      }
      if (best == null) break;
      best.bandCount++;
      remaining--;
    }
  }

  List<List<KanjiCard>> _splitEvenly(List<KanjiCard> cards, int count) {
    final bands = count < 1 ? 1 : math.min(count, cards.length);
    if (bands <= 1) return [cards];
    return [
      for (var i = 0; i < bands; i++)
        cards.sublist(
          (cards.length * i) ~/ bands,
          (cards.length * (i + 1)) ~/ bands,
        ),
    ];
  }

  /// The denominator behind the `1 / ~20` progress hint. A ceiling, not a
  /// prediction: finishing early reads as a bonus, finishing late would not.
  int estimatedQuestionCount(int poolSize) {
    if (poolSize <= 0) return 0;
    return math.min(questionLimit, poolSize);
  }

  /// Rebuilds a run by feeding [answers] back through the same question
  /// stream that produced them.
  PlacementRun replay(List<KanjiCard> pool, Iterable<PlacementAnswer> answers) {
    final run = PlacementRun._(this, bands(pool));
    for (final answer in answers) {
      run.record(answer);
    }
    return run;
  }
}

/// One in-progress or finished placement test.
class PlacementRun {
  PlacementRun._(this._engine, this._bands)
    : _unresolvedCeiling = _bands.length {
    for (final band in _bands) {
      _pool.addAll(band);
    }
  }

  final PlacementTestEngine _engine;
  final List<List<KanjiCard>> _bands;

  /// The whole pool in difficulty order.
  final List<KanjiCard> _pool = [];

  final Map<String, bool> _responses = {};
  final Map<int, _BandTally> _tallies = {};

  /// Highest band the user has passed. -1 means not even the easiest band.
  int _highestPass = -1;

  /// Lowest band the user has failed, or one past the hardest band while they
  /// have not failed one yet. The boundary is somewhere below it.
  int _unresolvedCeiling;

  /// True while the search is still doubling upward looking for a ceiling.
  bool _climbing = true;

  int _band = 0;
  int _roundAsked = 0;
  int _roundKnown = 0;

  int get answeredCount => _responses.length;

  /// Estimated length of the whole test, for the progress indicator.
  int get estimatedTotal => _engine.estimatedQuestionCount(_pool.length);

  bool get isFinished => currentQuestion == null;

  /// The kanji to put on screen, or null when the test is over.
  KanjiCard? get currentQuestion {
    if (_bands.isEmpty) return null;
    if (answeredCount >= _engine.questionLimit) return null;
    if (_boundaryBracketed && answeredCount >= _engine.minimumQuestions) {
      return null;
    }

    final band = _bandWithQuestionsNear(_band);
    if (band == null) return null;

    for (final card in _questionOrder(band)) {
      if (!_responses.containsKey(card.id)) return card;
    }
    return null;
  }

  /// Applies one answer. Answers for kanji outside the pool are ignored so a
  /// replay survives a pool that has changed since the test began.
  void record(PlacementAnswer answer) {
    final band = _bandOf(answer.cardId);
    if (band == null || _responses.containsKey(answer.cardId)) return;

    // Only reachable if the pool shifted mid-test; keep the round aligned with
    // the band actually being answered.
    if (band != _band) {
      _closeRound();
      _band = band;
    }

    _responses[answer.cardId] = answer.known;
    (_tallies[band] ??= _BandTally()).add(known: answer.known);
    _roundAsked++;
    if (answer.known) _roundKnown++;

    final bandExhausted = _bands[band].every(
      (card) => _responses.containsKey(card.id),
    );
    if (_roundAsked >= _engine.questionsPerBand || bandExhausted) {
      _closeRound();
    }
  }

  /// What the test concluded.
  ///
  /// Explicit answers always win: a kanji answered "I don't know it" is never
  /// inferred as known, and one answered "I know it" counts even if its band
  /// was failed. Everything else is filled in from the band verdicts, walking
  /// up from the easiest band and stopping at the first band the user failed.
  PlacementOutcome outcome() {
    final boundary = _knownBoundary();
    final known = <String>[];

    for (var band = 0; band < _bands.length; band++) {
      final inferredKnown = band <= boundary;
      for (final card in _bands[band]) {
        final answered = _responses[card.id];
        final isKnown = answered ?? inferredKnown;
        if (isKnown) known.add(card.id);
      }
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

  /// True when some earlier kanji of [next]'s level were placed as known, so
  /// learning starts inside that level rather than at its first card.
  bool _resumesMidLevel(KanjiCard next, Set<String> knownIds) {
    for (final card in _pool) {
      if (card.id == next.id) return false;
      if (card.jlptLevel == next.jlptLevel && knownIds.contains(card.id)) {
        return true;
      }
    }
    return false;
  }

  /// True once the boundary sits between two adjacent bands and there is
  /// nothing left to bisect.
  bool get _boundaryBracketed => _unresolvedCeiling - _highestPass <= 1;

  /// Judges the band just probed and picks the next one.
  void _closeRound() {
    if (_roundAsked == 0) return;

    final passed = _roundKnown / _roundAsked >= _engine.passRatio;
    if (passed) {
      _highestPass = math.max(_highestPass, _band);
      if (_climbing) {
        final next = _nextClimb(_band);
        if (next == _band) {
          _climbing = false;
        } else {
          _band = next;
        }
      }
    } else {
      _unresolvedCeiling = math.min(_unresolvedCeiling, _band);
      _climbing = false;
    }

    if (!_climbing) {
      _band = _boundaryBracketed
          ? math.max(0, _highestPass)
          : _highestPass + (_unresolvedCeiling - _highestPass) ~/ 2;
    }

    _roundAsked = 0;
    _roundKnown = 0;
  }

  /// Doubling climb, clamped to the hardest band.
  int _nextClimb(int band) {
    final top = _bands.length - 1;
    if (band >= top) return band;
    return band == 0 ? math.min(1, top) : math.min(band * 2, top);
  }

  /// [preferred] if it still has unanswered kanji, otherwise the closest band
  /// that does. Keeps confirmation questions near the boundary and lets an
  /// exhausted band fall through instead of stalling the test.
  int? _bandWithQuestionsNear(int preferred) {
    int? best;
    var bestDistance = 0;
    for (var band = 0; band < _bands.length; band++) {
      final hasQuestions = _bands[band].any(
        (card) => !_responses.containsKey(card.id),
      );
      if (!hasQuestions) continue;
      final distance = (band - preferred).abs();
      if (best == null || distance < bestDistance) {
        best = band;
        bestDistance = distance;
      }
    }
    return best;
  }

  /// Band order for questions: a stride walk rather than the content order, so
  /// three questions from one band are not three neighbours on the frequency
  /// list. Deterministic, which is what makes a replay match.
  List<KanjiCard> _questionOrder(int band) {
    final cards = _bands[band];
    final length = cards.length;
    if (length <= 2) return cards;

    var stride = (length / _engine.questionsPerBand).round().clamp(
      1,
      length - 1,
    );
    while (_gcd(stride, length) != 1) {
      stride++;
    }
    return [for (var i = 0; i < length; i++) cards[(i * stride) % length]];
  }

  int? _bandOf(String cardId) {
    for (var band = 0; band < _bands.length; band++) {
      for (final card in _bands[band]) {
        if (card.id == cardId) return band;
      }
    }
    return null;
  }

  /// Highest band to treat as known: the last passed band below the first
  /// failed one. Untested bands in between inherit, because ability along the
  /// difficulty order is assumed monotonic.
  int _knownBoundary() {
    var firstFail = _bands.length;
    for (var band = 0; band < _bands.length; band++) {
      final tally = _tallies[band];
      if (tally != null && !tally.passed(_engine.passRatio)) {
        firstFail = band;
        break;
      }
    }

    var boundary = -1;
    for (var band = 0; band < firstFail; band++) {
      if (_tallies[band]?.passed(_engine.passRatio) ?? false) boundary = band;
    }
    return boundary;
  }
}

class _BandTally {
  int known = 0;
  int total = 0;

  void add({required bool known}) {
    total++;
    if (known) this.known++;
  }

  bool passed(double ratio) => total > 0 && known / total >= ratio;
}

class _LevelGroup {
  _LevelGroup(this.cards);

  final List<KanjiCard> cards;
  int bandCount = 1;
}

int _gcd(int a, int b) {
  while (b != 0) {
    final next = a % b;
    a = b;
    b = next;
  }
  return a;
}

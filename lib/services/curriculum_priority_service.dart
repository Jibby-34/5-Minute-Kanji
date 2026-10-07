import 'dart:math' as math;

import '../core/models/curriculum_mode.dart';
import '../core/models/kanji_card.dart';

/// Tunable weights for [CurriculumMode.recommended].
///
/// Every score they multiply is already normalized to 0–1. A higher total
/// means the kanji should be introduced earlier. Change these in one place
/// when the curriculum needs retuning.
class CurriculumPriorityWeights {
  const CurriculumPriorityWeights({
    this.frequency = 0.50,
    this.jlpt = 0.30,
    this.difficulty = 0.15,
    this.component = 0.05,
  });

  static const recommended = CurriculumPriorityWeights();

  final double frequency;
  final double jlpt;
  final double difficulty;
  final double component;
}

/// Initial JLPT contribution. Lower levels are more foundational, but this
/// is a signal, not a hard boundary between levels.
class JlptCurriculumScores {
  const JlptCurriculumScores({
    this.n5 = 1.00,
    this.n4 = 0.80,
    this.n3 = 0.60,
    this.n2 = 0.40,
    this.n1 = 0.20,
    this.none = 0.10,
  });

  static const initial = JlptCurriculumScores();

  final double n5;
  final double n4;
  final double n3;
  final double n2;
  final double n1;
  final double none;

  double forLevel(JlptLevel level) {
    return switch (level) {
      JlptLevel.n5 => n5,
      JlptLevel.n4 => n4,
      JlptLevel.n3 => n3,
      JlptLevel.n2 => n2,
      JlptLevel.n1 => n1,
      JlptLevel.none => none,
    };
  }
}

/// The normalized signals behind one kanji's curriculum priority.
class KanjiPriorityFactors {
  const KanjiPriorityFactors({
    required this.frequencyScore,
    required this.jlptScore,
    required this.difficultyScore,
    required this.componentScore,
    required this.weights,
  });

  final double frequencyScore;
  final double jlptScore;
  final double difficultyScore;
  final double componentScore;
  final CurriculumPriorityWeights weights;

  double get priorityScore =>
      frequencyScore * weights.frequency +
      jlptScore * weights.jlpt +
      difficultyScore * weights.difficulty +
      componentScore * weights.component;

  /// A short explanation of why this kanji scored as it did.
  String describe(String character) {
    return [
      character,
      '',
      'Priority: ${priorityScore.toStringAsFixed(2)}',
      '',
      _line('Frequency', frequencyScore, weights.frequency),
      _line('JLPT', jlptScore, weights.jlpt),
      _line('Difficulty', difficultyScore, weights.difficulty),
      _line('Components', componentScore, weights.component),
    ].join('\n');
  }

  static String _line(String label, double score, double weight) {
    final percent = (weight * 100).round();
    return '$label: ${score.toStringAsFixed(2)} × $percent%';
  }
}

/// Ranks kanji for introduction. Does not schedule reviews or pick a daily
/// count.
///
/// Frequency is normalized across [catalog], so scores stay stable as the
/// learner's remaining set shrinks. Component familiarity is the only signal
/// that reads what the learner already knows.
class CurriculumPriorityService {
  factory CurriculumPriorityService(
    Iterable<KanjiCard> catalog, {
    CurriculumPriorityWeights weights = CurriculumPriorityWeights.recommended,
    JlptCurriculumScores jlptScores = JlptCurriculumScores.initial,
  }) {
    final cards = catalog.toList(growable: false);
    final bounds = _logBounds(cards);
    return CurriculumPriorityService._(
      componentCardIds: _indexByCharacter(cards),
      logMin: bounds.min,
      logMax: bounds.max,
      hasPositiveFrequency: bounds.hasPositive,
      weights: weights,
      jlptScores: jlptScores,
    );
  }

  const CurriculumPriorityService._({
    required Map<String, String> componentCardIds,
    required double logMin,
    required double logMax,
    required bool hasPositiveFrequency,
    required this.weights,
    required this.jlptScores,
  }) : _componentCardIds = componentCardIds,
       _logMin = logMin,
       _logMax = logMax,
       _hasPositiveFrequency = hasPositiveFrequency;

  /// Used when a kanji has no component that maps to another kanji.
  ///
  /// Missing relationships stay neutral so they are not treated as unfamiliar
  /// building blocks.
  static const neutralComponentScore = 0.5;

  final CurriculumPriorityWeights weights;
  final JlptCurriculumScores jlptScores;
  final Map<String, String> _componentCardIds;
  final double _logMin;
  final double _logMax;
  final bool _hasPositiveFrequency;

  double get _logSpan => _logMax - _logMin;

  KanjiPriorityFactors factors(
    KanjiCard card, {
    required Set<String> knownCardIds,
  }) {
    return KanjiPriorityFactors(
      frequencyScore: frequencyScoreFor(card.frequency),
      jlptScore: jlptScores.forLevel(card.jlptLevel),
      difficultyScore: difficultyScoreFor(card.difficulty),
      componentScore: componentScoreFor(card, knownCardIds: knownCardIds),
      weights: weights,
    );
  }

  String debugBreakdown(KanjiCard card, {required Set<String> knownCardIds}) {
    return factors(card, knownCardIds: knownCardIds).describe(card.character);
  }

  /// 1 for the most frequent rank in the catalog, 0 for the least.
  ///
  /// Ranks are logarithmic so a jump from 1 to 10 matters more than a jump
  /// from 2000 to 2010. Non-positive ranks score 0.
  double frequencyScoreFor(int frequency) {
    if (frequency <= 0 || !_hasPositiveFrequency) return 0;
    final logFrequency = math.log(frequency);
    if (logFrequency.isNaN || logFrequency.isInfinite) return 0;
    if (_logSpan == 0) return 1;
    final normalized = (logFrequency - _logMin) / _logSpan;
    if (normalized.isNaN || normalized.isInfinite) return 0;
    return (1 - normalized).clamp(0.0, 1.0);
  }

  /// Higher difficulty slightly lowers priority. Values outside 1–100 are
  /// neutral so an unset difficulty does not outrank the whole catalog.
  double difficultyScoreFor(int difficulty) {
    if (difficulty < 1 || difficulty > 100) return 0.5;
    return 1 - ((difficulty - 1) / 99);
  }

  /// Share of meaningful components the learner has already encountered.
  ///
  /// A component counts only when its character is another kanji in the
  /// catalog. Radicals and other glyphs that are not kanji are ignored.
  /// When none of the components can be matched, the score is
  /// [neutralComponentScore]. This never blocks a kanji from being learned.
  double componentScoreFor(
    KanjiCard card, {
    required Set<String> knownCardIds,
  }) {
    final meaningful = _meaningfulComponentIds(card);
    if (meaningful.isEmpty) return neutralComponentScore;
    var known = 0;
    for (final id in meaningful) {
      if (knownCardIds.contains(id)) known++;
    }
    return known / meaningful.length;
  }

  /// Higher priority first. Equal recommended scores break ties by frequency,
  /// then difficulty, then id.
  int compare(
    KanjiCard a,
    KanjiCard b, {
    required CurriculumMode mode,
    required Set<String> knownCardIds,
    Map<String, int>? customRanks,
  }) {
    switch (mode) {
      case CurriculumMode.frequency:
        return _frequencyThenId(a, b);
      case CurriculumMode.jlpt:
        final byLevel = JlptLevel.sectionOrder
            .indexOf(a.jlptLevel)
            .compareTo(JlptLevel.sectionOrder.indexOf(b.jlptLevel));
        if (byLevel != 0) return byLevel;
        return _frequencyThenId(a, b);
      case CurriculumMode.difficulty:
        final byDifficulty = _difficultyRank(a).compareTo(_difficultyRank(b));
        if (byDifficulty != 0) return byDifficulty;
        return _frequencyThenId(a, b);
      case CurriculumMode.custom:
        final ranks = customRanks;
        if (ranks != null && ranks.isNotEmpty) {
          final byRank = _customRank(a, ranks).compareTo(_customRank(b, ranks));
          if (byRank != 0) return byRank;
          return a.id.compareTo(b.id);
        }
        return _compareRecommended(a, b, knownCardIds);
      case CurriculumMode.recommended:
        return _compareRecommended(a, b, knownCardIds);
    }
  }

  int Function(KanjiCard a, KanjiCard b) comparer({
    required CurriculumMode mode,
    required Set<String> knownCardIds,
    Map<String, int>? customRanks,
  }) {
    return (a, b) => compare(
      a,
      b,
      mode: mode,
      knownCardIds: knownCardIds,
      customRanks: customRanks,
    );
  }

  /// Eligible new kanji in curriculum order.
  ///
  /// Learning, mastered, and marked-known cards stay out when [isEligibleNew]
  /// says so. The daily allowance is applied by the caller.
  List<KanjiCard> orderedNewKanji({
    required Iterable<KanjiCard> cards,
    required bool Function(KanjiCard card) isEligibleNew,
    required Set<String> knownCardIds,
    CurriculumMode mode = CurriculumMode.recommended,
    Map<String, int>? customRanks,
  }) {
    final eligible = [
      for (final card in cards)
        if (isEligibleNew(card)) card,
    ];
    eligible.sort(
      comparer(
        mode: mode,
        knownCardIds: knownCardIds,
        customRanks: customRanks,
      ),
    );
    return eligible;
  }

  int _compareRecommended(KanjiCard a, KanjiCard b, Set<String> knownCardIds) {
    final aScore = factors(a, knownCardIds: knownCardIds).priorityScore;
    final bScore = factors(b, knownCardIds: knownCardIds).priorityScore;
    final byScore = bScore.compareTo(aScore);
    if (byScore != 0) return byScore;
    return _recommendedTieBreak(a, b);
  }

  int _recommendedTieBreak(KanjiCard a, KanjiCard b) {
    final byFrequency = _frequencyRank(a).compareTo(_frequencyRank(b));
    if (byFrequency != 0) return byFrequency;
    final byDifficulty = _difficultyRank(a).compareTo(_difficultyRank(b));
    if (byDifficulty != 0) return byDifficulty;
    return a.id.compareTo(b.id);
  }

  int _frequencyThenId(KanjiCard a, KanjiCard b) {
    final byFrequency = _frequencyRank(a).compareTo(_frequencyRank(b));
    if (byFrequency != 0) return byFrequency;
    return a.id.compareTo(b.id);
  }

  /// Missing frequency sorts after every real rank.
  int _frequencyRank(KanjiCard card) {
    if (card.frequency <= 0) return 0x3fffffff;
    return card.frequency;
  }

  /// Missing difficulty sorts after every real difficulty.
  int _difficultyRank(KanjiCard card) {
    if (card.difficulty < 1 || card.difficulty > 100) return 101;
    return card.difficulty;
  }

  int _customRank(KanjiCard card, Map<String, int> ranks) {
    return ranks[card.id] ?? 0x3fffffff;
  }

  Set<String> _meaningfulComponentIds(KanjiCard card) {
    final ids = <String>{};
    for (final component in card.componentModels) {
      final id = _componentCardIds[component.character];
      if (id == null || id == card.id) continue;
      ids.add(id);
    }
    return ids;
  }

  static Map<String, String> _indexByCharacter(Iterable<KanjiCard> catalog) {
    final index = <String, String>{};
    for (final card in catalog) {
      if (card.character.isEmpty) continue;
      index.putIfAbsent(card.character, () => card.id);
    }
    return index;
  }

  static ({double min, double max, bool hasPositive}) _logBounds(
    Iterable<KanjiCard> catalog,
  ) {
    double? min;
    double? max;
    for (final card in catalog) {
      if (card.frequency <= 0) continue;
      final logFrequency = math.log(card.frequency);
      if (logFrequency.isNaN || logFrequency.isInfinite) continue;
      min = min == null || logFrequency < min ? logFrequency : min;
      max = max == null || logFrequency > max ? logFrequency : max;
    }
    if (min == null || max == null) {
      return (min: 0, max: 0, hasPositive: false);
    }
    return (min: min, max: max, hasPositive: true);
  }
}

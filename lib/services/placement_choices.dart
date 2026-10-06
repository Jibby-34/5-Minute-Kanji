import '../core/models/kanji_card.dart';
import 'due_card_selector.dart';

/// One meaning shown under a placement kanji.
class PlacementChoice {
  const PlacementChoice({required this.label, required this.correct});

  final String label;

  /// True only for the meaning of the kanji on screen.
  final bool correct;
}

/// How many meanings a placement question offers.
const int placementChoiceCount = 4;

/// Everyday glosses used only when the pool has fewer than three other
/// distinct meanings, so a tiny catalog still shows four answers.
const List<String> _fallbackMeanings = [
  'water',
  'fire',
  'tree',
  'gold',
  'earth',
  'moon',
  'mountain',
  'river',
  'mouth',
  'eye',
];

/// Four meanings for [card]: its own, plus three others.
///
/// The other three are real meanings from [pool], taken from the same JLPT
/// level first and from kanji near [card] in learn order. They are ordinary
/// wrong answers, not lookalike traps. The correct meaning is mixed into a
/// stable slot for [card], so a resumed question shows the same four.
List<PlacementChoice> placementMeaningChoices({
  required KanjiCard card,
  required List<KanjiCard> pool,
}) {
  final correct = _gloss(card);
  final ordered = List<KanjiCard>.of(pool)..sort(compareKanjiLearnOrder);
  final distractors = _distractors(card, ordered, correct);
  final labels = <String>[correct, ...distractors];
  _mix(labels, card.id);

  final correctKey = correct.toLowerCase();
  return [
    for (final label in labels)
      PlacementChoice(label: label, correct: label.toLowerCase() == correctKey),
  ];
}

String _gloss(KanjiCard card) {
  final meaning = card.meaning.trim();
  if (meaning.isNotEmpty) return meaning;
  final keyword = card.keyword.trim();
  if (keyword.isNotEmpty) return keyword;
  return card.character;
}

List<String> _distractors(
  KanjiCard card,
  List<KanjiCard> ordered,
  String correct,
) {
  final seen = <String>{correct.toLowerCase()};
  final distractors = <String>[];
  final needed = placementChoiceCount - 1;

  void consider(KanjiCard other) {
    if (distractors.length >= needed || other.id == card.id) return;
    final gloss = _gloss(other);
    if (gloss.isEmpty) return;
    if (seen.add(gloss.toLowerCase())) distractors.add(gloss);
  }

  var index = ordered.indexWhere((other) => other.id == card.id);
  if (index < 0) index = 0;

  final sameLevel = <KanjiCard>[];
  final otherLevels = <KanjiCard>[];
  for (var distance = 1; distance < ordered.length; distance++) {
    final before = index - distance;
    final after = index + distance;
    if (before >= 0) _bucket(ordered[before], card, sameLevel, otherLevels);
    if (after < ordered.length) {
      _bucket(ordered[after], card, sameLevel, otherLevels);
    }
  }

  for (final other in sameLevel) {
    consider(other);
  }
  for (final other in otherLevels) {
    consider(other);
  }
  for (final gloss in _fallbackMeanings) {
    if (distractors.length >= needed) break;
    if (seen.add(gloss.toLowerCase())) distractors.add(gloss);
  }
  return distractors;
}

void _bucket(
  KanjiCard candidate,
  KanjiCard card,
  List<KanjiCard> sameLevel,
  List<KanjiCard> otherLevels,
) {
  if (candidate.jlptLevel == card.jlptLevel) {
    sameLevel.add(candidate);
  } else {
    otherLevels.add(candidate);
  }
}

/// Mixes [labels] in an order that depends only on [id].
void _mix(List<String> labels, String id) {
  var state = 0;
  for (final unit in id.codeUnits) {
    state = (state * 33 + unit) & 0x7fffffff;
  }
  for (var i = labels.length - 1; i > 0; i--) {
    state = (state * 1103515245 + 12345) & 0x7fffffff;
    final swap = state % (i + 1);
    final held = labels[i];
    labels[i] = labels[swap];
    labels[swap] = held;
  }
}

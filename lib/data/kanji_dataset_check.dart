import '../core/models/kanji_card.dart';

/// Structural problems in a kanji list. Empty when the list can be loaded.
///
/// Wording of mnemonics is not checked. A card the app cannot identify, look
/// up, or render is.
List<String> kanjiDatasetProblems(List<KanjiCard> cards) {
  final problems = <String>[];
  final ids = <String>{};
  final characters = <String>{};

  for (final card in cards) {
    final label = card.id.isEmpty ? '(blank id)' : card.id;
    if (card.id.isEmpty) {
      problems.add('A card has a blank id.');
    } else if (!ids.add(card.id)) {
      problems.add('Duplicate id $label.');
    }
    if (card.character.isEmpty) {
      problems.add('$label has a blank character.');
    } else if (!characters.add(card.character)) {
      problems.add('Duplicate character ${card.character} ($label).');
    }
    if (card.meaning.trim().isEmpty) {
      problems.add('$label has a blank meaning.');
    }
    if (card.keyword.trim().isEmpty) {
      problems.add('$label has a blank keyword.');
    }
    if (card.mnemonic.trim().isEmpty) {
      problems.add('$label has a blank mnemonic.');
    }
    if (card.difficulty < 1 || card.difficulty > 100) {
      problems.add('$label has a difficulty outside 1–100.');
    }
    if (card.frequency < 1) {
      problems.add('$label has a frequency below 1.');
    }
    for (final component in card.components) {
      if (component.trim().isEmpty) {
        problems.add('$label has a blank component.');
      }
    }
    for (final component in card.structuredComponents) {
      if (component.id.isEmpty ||
          component.character.isEmpty ||
          component.name.trim().isEmpty) {
        problems.add('$label has a component missing id, character, or name.');
      }
      if (component.occurrence < 0) {
        problems.add('$label has a negative component occurrence.');
      }
    }
  }

  return problems;
}

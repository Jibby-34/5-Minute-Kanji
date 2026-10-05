import 'package:flutter_test/flutter_test.dart';

import 'package:fiveminutekanji/core/models/kanji_card.dart';
import 'package:fiveminutekanji/data/hardcoded_kanji_repository.dart';
import 'package:fiveminutekanji/data/kanji_dataset_check.dart';
import 'package:fiveminutekanji/data/legacy_kanji_id_remap.dart';

void main() {
  test('the N5–N1 catalog loads with the fields the app renders', () async {
    const kanji = HardcodedKanjiRepository();
    final cards = await kanji.getAll();

    expect(kanjiDatasetProblems(cards), isEmpty);
    expect(cards, isNotEmpty);

    final counts = <JlptLevel, int>{};
    for (final card in cards) {
      counts[card.jlptLevel] = (counts[card.jlptLevel] ?? 0) + 1;
      expect(card.id.startsWith('${card.jlptLevel.name}-'), isTrue);
      expect(await kanji.getById(card.id), same(card));
    }

    expect(counts[JlptLevel.n5], 80);
    expect(counts[JlptLevel.n4], 167);
    expect(counts[JlptLevel.n3], 370);
    expect(counts[JlptLevel.n2], 368);
    expect(counts[JlptLevel.n1], 1235);
    expect(cards, hasLength(2220));

    final withComponents = cards.where((card) => card.components.isNotEmpty);
    expect(withComponents, isNotEmpty);
    expect(cards.where((card) => card.jlptLevel == JlptLevel.n1), isNotEmpty);
  });

  test('legacy ids point at current kanji and do not collide', () {
    expect(
      legacyKanjiIdRemap.values.toSet(),
      hasLength(legacyKanjiIdRemap.length),
    );
  });
}

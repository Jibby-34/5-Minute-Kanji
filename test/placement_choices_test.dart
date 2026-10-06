import 'package:flutter_test/flutter_test.dart';
import 'package:fiveminutekanji/core/models/kanji_card.dart';
import 'package:fiveminutekanji/data/hardcoded_kanji_repository.dart';
import 'package:fiveminutekanji/services/placement_choices.dart';

import 'support/fakes.dart';

void main() {
  test('a question has four meanings and exactly one is right', () {
    final pool = [
      for (var i = 0; i < 8; i++)
        testCard('n5-$i', keyword: 'meaning-$i', jlptLevel: JlptLevel.n5),
    ];
    final card = pool[3];

    final choices = placementMeaningChoices(card: card, pool: pool);

    expect(choices, hasLength(placementChoiceCount));
    expect(choices.where((choice) => choice.correct), hasLength(1));
    expect(choices.singleWhere((choice) => choice.correct).label, card.meaning);
    expect(
      choices.map((choice) => choice.label.toLowerCase()).toSet(),
      hasLength(placementChoiceCount),
    );
  });

  test(
    'wrong answers come from the same level when it has enough meanings',
    () {
      final n5 = [
        for (var i = 0; i < 6; i++)
          testCard('n5-$i', keyword: 'n5-meaning-$i', jlptLevel: JlptLevel.n5),
      ];
      final n1 = [
        for (var i = 0; i < 6; i++)
          testCard('n1-$i', keyword: 'n1-meaning-$i', jlptLevel: JlptLevel.n1),
      ];

      final choices = placementMeaningChoices(
        card: n5[2],
        pool: [...n5, ...n1],
      );
      final wrong = choices
          .where((choice) => !choice.correct)
          .map((c) => c.label);

      expect(wrong, everyElement(startsWith('n5-meaning-')));
    },
  );

  test('nearby kanji supply the wrong answers, and the mix stays put', () {
    final pool = [
      for (var i = 0; i < 8; i++)
        testCard('n5-$i', keyword: 'meaning-$i', jlptLevel: JlptLevel.n5),
    ];

    List<String> wrongFor(int index) {
      return placementMeaningChoices(card: pool[index], pool: pool)
          .where((choice) => !choice.correct)
          .map((choice) => choice.label)
          .toList();
    }

    final first = wrongFor(0);
    final again = wrongFor(0);
    expect(again, first);
    expect(wrongFor(7), isNot(first));

    final slots = {
      for (final card in pool)
        placementMeaningChoices(
          card: card,
          pool: pool,
        ).indexWhere((choice) => choice.correct),
    };
    expect(slots.length, greaterThan(1));
  });

  test('a short pool still offers four different meanings', () {
    final pool = [testCard('a', keyword: 'one'), testCard('b', keyword: 'two')];

    final choices = placementMeaningChoices(card: pool.first, pool: pool);

    expect(choices, hasLength(4));
    expect(
      choices.map((choice) => choice.label.toLowerCase()).toSet(),
      hasLength(4),
    );
    expect(choices.singleWhere((choice) => choice.correct).label, 'one');
    expect(choices.map((choice) => choice.label), contains('two'));
  });

  test('the real catalog can ask about any kanji', () async {
    final cards = await const HardcodedKanjiRepository().getAll();
    final sample = [
      cards.first,
      cards[40],
      cards[80],
      cards[500],
      cards[1200],
      cards.last,
    ];

    for (final card in sample) {
      final choices = placementMeaningChoices(card: card, pool: cards);
      expect(choices, hasLength(4), reason: card.id);
      expect(
        choices.map((choice) => choice.label.toLowerCase()).toSet(),
        hasLength(4),
        reason: card.id,
      );
      expect(
        choices.singleWhere((choice) => choice.correct).label,
        card.meaning,
        reason: card.id,
      );
    }
  });
}

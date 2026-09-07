import 'package:flutter_test/flutter_test.dart';
import 'package:fiveminutekanji/core/models/handwriting.dart';
import 'package:fiveminutekanji/core/models/kanji_card.dart';
import 'package:fiveminutekanji/services/answer_grader.dart';

void main() {
  test('ManualAnswerGrader never auto-scores', () {
    const grader = ManualAnswerGrader();
    const card = KanjiCard(
      id: 'rtk_001',
      character: '一',
      meaning: 'one',
      keyword: 'one',
      mnemonic: 'one',
      components: [],
      strokeCount: 1,
    );
    final answer = ReviewAnswer(
      cardId: card.id,
      drawing: HandwritingInput.empty,
      submittedAt: DateTime(2026, 9, 2),
    );

    expect(grader.suggest(answer, card), isNull);
  });
}

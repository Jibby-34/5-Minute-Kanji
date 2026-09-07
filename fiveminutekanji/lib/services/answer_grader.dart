import '../core/models/handwriting.dart';
import '../core/models/kanji_card.dart';
import '../core/models/review.dart';

/// Grades a submitted drawing. Return null to let the learner self-grade.
abstract class AnswerGrader {
  ReviewResult? suggest(ReviewAnswer answer, KanjiCard card);
}

/// MVP grader: never auto-scores. A future recognizer can replace this.
class ManualAnswerGrader implements AnswerGrader {
  const ManualAnswerGrader();

  @override
  ReviewResult? suggest(ReviewAnswer answer, KanjiCard card) => null;
}
